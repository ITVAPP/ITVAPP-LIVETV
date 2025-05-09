import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 解析阶段枚举 - 定义解析流程的不同阶段
enum ParseStage {
  formSubmission,  // 阶段1: 页面加载和表单提交
  searchResults,   // 阶段2: 搜索结果处理和流测试
  completed,       // 完成
  error            // 错误
}

/// 解析会话类 - 管理解析逻辑和状态
class _ParserSession {
  final Completer<String> completer = Completer<String>(); // 异步解析结果完成器
  final List<String> foundStreams = []; // 存储提取的流地址
  WebViewController? controller; // WebView控制器
  bool contentChangedDetected = false; // 内容变化检测标志
  Timer? contentChangeDebounceTimer; // 内容变化防抖计时器
  
  // 状态标记
  bool isResourceCleaned = false; // 资源是否已清理
  bool isTestingStarted = false; // 流测试是否开始
  bool isExtractionInProgress = false; // 链接提取是否进行中
  
  // 提取触发标记
  static bool _extractionTriggered = false; // 提取操作是否已触发
  
  // 状态对象 - 存储解析过程中的状态信息
  final Map<String, dynamic> searchState = {
    'searchKeyword': '', // 搜索关键词
    'activeEngine': 'primary', // 当前使用的搜索引擎
    'searchSubmitted': false, // 表单是否已提交
    'startTimeMs': DateTime.now().millisecondsSinceEpoch, // 解析开始时间
    'engineSwitched': false, // 是否切换到备用引擎
    'primaryEngineLoadFailed': false, // 主引擎是否加载失败
    'lastHtmlLength': 0, // 上次处理的HTML长度
    'extractionCount': 0, // 链接提取次数
    'stage': ParseStage.formSubmission, // 当前解析阶段
    'stage1StartTime': DateTime.now().millisecondsSinceEpoch, // 阶段1开始时间
    'stage2StartTime': 0, // 阶段2开始时间
  };
  
  // 全局超时计时器
  Timer? globalTimeoutTimer; // 全局超时控制
  
  // 取消监听
  StreamSubscription? cancelListener; // 取消操作监听器
  
  // 取消令牌
  final CancelToken? cancelToken; // 取消请求的令牌
  
  _ParserSession({this.cancelToken}); // 构造函数，接收取消令牌
  
  /// 检查是否已取消
  bool isCancelled() {
    return cancelToken?.isCancelled ?? false; // 返回取消状态
  }
  
  /// 设置取消监听器
  void setupCancelListener() {
    if (cancelToken != null) {
      cancelListener = cancelToken?.whenCancel?.asStream().listen((_) {
        LogUtil.i('检测到取消信号，立即释放所有资源'); // 取消信号触发
        cleanupResources(immediate: true); // 立即清理资源
      });
    }
  }
  
  /// 设置全局超时
  void setupGlobalTimeout() {
    globalTimeoutTimer?.cancel(); // 清除旧计时器
    LogUtil.i('设置全局超时: ${SousuoParser._timeoutSeconds * 2}秒');超时设置
    globalTimeoutTimer = Timer(Duration(seconds: SousuoParser._timeoutSeconds * 2), () {
      LogUtil.i('全局超时触发'); // 超时触发
      if (isCancelled() || completer.isCompleted) return; // 已取消或完成则返回
      if (foundStreams.isNotEmpty) {
        LogUtil.i('全局超时触发，已找到 ${foundStreams.length} 个流，开始测试'); // 找到流则测试
        startStreamTesting(); // 开始测试流
      } else if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
        LogUtil.i('全局超时触发，主引擎未找到流，切换备用引擎'); // 主引擎无流，切换备用
        switchToBackupEngine(); // 切换到备用引擎
      } else {
        LogUtil.i('全局超时触发，无可用流'); // 无流可用
        if (!completer.isCompleted) {
          completer.complete('ERROR'); // 完成并返回错误
          cleanupResources(); // 清理资源
        }
      }
    });
  }
  
  /// 清理资源
  Future<void> cleanupResources({bool immediate = false}) async {
    if (isResourceCleaned) {
      LogUtil.i('资源已清理，跳过'); // 已清理则跳过
      return;
    }
    LogUtil.i('开始清理资源'); // 开始清理
    try {
      isResourceCleaned = true; // 标记为已清理
      if (globalTimeoutTimer != null) {
        globalTimeoutTimer!.cancel();
        globalTimeoutTimer = null; // 取消全局超时计时器
        LogUtil.i('全局超时计时器已取消');
      }
      if (contentChangeDebounceTimer != null) {
        contentChangeDebounceTimer!.cancel(); // 取消内容变化防抖计时器
        contentChangeDebounceTimer = null; // 清空引用
        LogUtil.i('内容变化防抖计时器已取消');
      }
      if (cancelListener != null) {
        await cancelListener!.cancel(); // 取消监听器
        cancelListener = null; // 清空引用
        LogUtil.i('取消监听器已清理');
      }
      if (controller != null) {
        try {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
          if (!immediate) {
            await Future.delayed(Duration(milliseconds: 100)); // 等待页面加载
            await SousuoParser._disposeWebView(controller!); // 清理WebView资源
          }
        } catch (e) {
          LogUtil.e('清理WebView资源时出错: $e'); // 错误日志
        } finally {
          controller = null; // 清空控制器引用
          LogUtil.i('WebView控制器已清理');
        }
      }
      if (!completer.isCompleted) {
        LogUtil.i('Completer未完成，强制返回ERROR'); // 未完成则返回错误
        completer.complete('ERROR'); // 完成并返回错误
      }
      LogUtil.i('所有资源清理完成'); // 清理完成
    } catch (e) {
      LogUtil.e('清理资源过程中出错: $e'); // 错误日志
      if (!completer.isCompleted) {
        completer.complete('ERROR'); // 确保完成
      }
      globalTimeoutTimer = null; // 清空引用
      contentChangeDebounceTimer = null; // 清空引用
      cancelListener = null; // 清空引用
      controller = null; // 清空引用
    }
  }
  
  /// 开始测试流链接
  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('已经开始测试流链接，忽略重复测试请求'); // 已开始测试则忽略
      return;
    }
    if (foundStreams.isEmpty) {
      LogUtil.i('没有找到流链接，无法开始测试'); // 无流则返回错误
      if (!completer.isCompleted) {
        completer.complete('ERROR'); // 完成并返回错误
        cleanupResources(); // 清理资源
      }
      return;
    }
    isTestingStarted = true; // 标记测试开始
    LogUtil.i('开始测试 ${foundStreams.length} 个流链接');
    final testCancelToken = CancelToken(); // 创建测试取消令牌
    StreamSubscription? testCancelListener; // 测试取消监听器
    if (cancelToken != null) {
      testCancelListener = cancelToken?.whenCancel?.asStream().listen((_) {
        if (!testCancelToken.isCancelled) {
          LogUtil.i('父级cancelToken已取消，取消所有测试请求'); // 父级取消触发
          testCancelToken.cancel('父级已取消'); // 取消测试
        }
      });
    }
    try {
      SousuoParser._testStreamsAndGetFastest(foundStreams, cancelToken: testCancelToken)
        .then((String result) {
          LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}'); // 测试结果
          if (!completer.isCompleted) {
            completer.complete(result); // 完成并返回结果
            cleanupResources(); // 清理资源
          }
        })
        .catchError((e) {
          LogUtil.e('测试流过程中出错: $e'); // 测试错误
          if (!completer.isCompleted) {
            completer.complete('ERROR'); // 完成并返回错误
            cleanupResources(); // 清理资源
          }
        })
        .whenComplete(() {
          testCancelListener?.cancel(); // 取消测试监听器
        });
    } catch (e) {
      LogUtil.e('启动流测试出错: $e'); // 启动测试错误
      testCancelListener?.cancel(); // 取消监听器
      if (!completer.isCompleted) {
        completer.complete('ERROR'); // 完成并返回错误
        cleanupResources(); // 清理资源
      }
    }
  }
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState['engineSwitched'] == true) {
      LogUtil.i('已切换到备用引擎，忽略'); // 已切换则忽略
      return;
    }
    if (isCancelled()) {
      LogUtil.i('任务已取消，不切换到备用引擎'); // 已取消则返回
      if (!completer.isCompleted) {
        completer.complete('ERROR'); // 完成并返回错误
        await cleanupResources(); // 清理资源
      }
      return;
    }
    LogUtil.i('主引擎不可用，切换到备用引擎'); // 切换备用引擎
    searchState['activeEngine'] = 'backup'; // 设置备用引擎
    searchState['engineSwitched'] = true; // 标记已切换
    searchState['searchSubmitted'] = false; // 重置提交状态
    searchState['lastHtmlLength'] = 0; // 重置HTML长度
    searchState['extractionCount'] = 0; // 重置提取次数
    searchState['stage'] = ParseStage.formSubmission; // 重置阶段
    searchState['stage1StartTime'] = DateTime.now().millisecondsSinceEpoch; // 重置阶段1时间
    _extractionTriggered = false; // 重置提取标记
    globalTimeoutTimer?.cancel(); // 取消全局超时
    if (controller != null) {
      try {
        await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
        await Future.delayed(Duration(milliseconds: SousuoParser._backupEngineLoadWaitMs)); // 等待
        await controller!.loadRequest(Uri.parse(SousuoParser._backupEngine)); // 加载备用引擎
        LogUtil.i('已加载备用引擎: ${SousuoParser._backupEngine}');
        setupGlobalTimeout(); // 设置新的全局超时
      } catch (e) {
        LogUtil.e('加载备用引擎时出错: $e'); // 加载错误
        if (!isResourceCleaned && !completer.isCompleted) {
          LogUtil.i('加载备用引擎失败，返回ERROR'); // 加载失败
          completer.complete('ERROR'); // 完成并返回错误
          await cleanupResources(); // 清理资源
        }
      }
    } else {
      LogUtil.e('WebView控制器为空，无法切换'); // 控制器为空
      if (!isResourceCleaned && !completer.isCompleted) {
        completer.complete('ERROR'); // 完成并返回错误
        await cleanupResources(); // 清理资源
      }
    }
  }
  
  /// 处理内容变化
  void handleContentChange() {
    contentChangeDebounceTimer?.cancel(); // 取消防抖计时器
    if (isCancelled()) {
      LogUtil.i('任务已取消，停止处理内容变化'); // 已取消则返回
      if (!completer.isCompleted) {
        completer.complete('ERROR'); // 完成并返回错误
        cleanupResources(); // 清理资源
      }
      return;
    }
    if (isExtractionInProgress) {
      LogUtil.i('提取操作正在进行中，跳过此次提取'); // 提取进行中则跳过
      return;
    }
    if (_extractionTriggered) {
      LogUtil.i('已经触发过提取操作，跳过此次提取'); // 已触发提取则跳过
      return;
    }
    contentChangeDebounceTimer = Timer(Duration(milliseconds: SousuoParser._contentChangeDebounceMs), () async {
      if (controller == null || completer.isCompleted || isCancelled()) return; // 无效状态则返回
      isExtractionInProgress = true; // 标记提取开始
      LogUtil.i('处理页面内容变化（防抖后）');
      contentChangedDetected = true; // 标记内容变化
      if (searchState['searchSubmitted'] == true && !completer.isCompleted && !isTestingStarted) {
        _extractionTriggered = true; // 标记提取触发
        int beforeExtractCount = foundStreams.length; // 记录提取前数量
        bool isBackupEngine = searchState['activeEngine'] == 'backup'; // 是否备用引擎
        await SousuoParser._extractMediaLinks(
          controller!, 
          foundStreams, 
          isBackupEngine,
          lastProcessedLength: searchState['lastHtmlLength']
        ); // 提取媒体链接
        try {
          final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length'); // 获取HTML长度
          searchState['lastHtmlLength'] = int.tryParse(result.toString()) ?? 0; // 更新HTML长度
        } catch (e) {
          LogUtil.e('获取HTML长度时出错: $e'); // 错误日志
        }
        searchState['extractionCount'] = searchState['extractionCount'] + 1; // 增加提取计数
        int afterExtractCount = foundStreams.length; // 记录提取后数量
        if (afterExtractCount > beforeExtractCount) {
          LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接'); // 日志新增链接
          if (afterExtractCount >= SousuoParser._maxStreams) {
            LogUtil.i('达到最大链接数 ${SousuoParser._maxStreams}，开始测试'); // 达到最大链接数
            startStreamTesting(); // 开始测试
          } else if (afterExtractCount > 0) {
            LogUtil.i('提取完成，找到 ${afterExtractCount} 个链接，立即开始测试'); // 找到链接立即测试
            startStreamTesting(); // 开始测试
          }
        } else if (searchState['activeEngine'] == 'primary' && 
                  afterExtractCount == 0 && 
                  searchState['engineSwitched'] == false) {
          _extractionTriggered = false; // 重置提取标记
          LogUtil.i('主引擎无链接，切换备用引擎，重置提取标记'); // 主引擎无链接
          switchToBackupEngine(); // 切换备用引擎
        }
      }
      isExtractionInProgress = false; // 标记提取结束
    });
  }
  
  /// 注入表单检测脚本
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return; // 控制器为空则返回
    try {
      await controller!.runJavaScript('''
        (function() {
          console.log("开始注入表单检测脚本");
          window.__formCheckState = {
            formFound: false, // 表单是否找到
            checkInterval: null, // 检查定时器
            searchKeyword: "${searchKeyword.replaceAll('"', '\\"')}" // 搜索关键词
          };
          function clearFormCheckInterval() {
            if (window.__formCheckState.checkInterval) {
              clearInterval(window.__formCheckState.checkInterval); // 清除定时器
              window.__formCheckState.checkInterval = null; // 清空引用
              console.log("停止表单检测");
            }
          }
          async function simulateHumanBehavior(searchKeyword) {
            return new Promise((resolve) => {
              if (window.AppChannel) {
                window.AppChannel.postMessage('开始模拟真人行为'); // 通知开始模拟
              }
              const searchInput = document.getElementById('search'); // 获取搜索输入框
              if (!searchInput) {
                console.log("未找到搜索输入框");
                if (window.AppChannel) {
                  window.AppChannel.postMessage("未找到搜索输入框"); // 通知失败
                }
                return resolve(false); // 返回失败
              }
              let lastX = window.innerWidth / 2; // 初始鼠标X坐标
              let lastY = window.innerHeight / 2; // 初始鼠标Y坐标
              function getInputPosition() {
                const rect = searchInput.getBoundingClientRect(); // 获取输入框位置
                return {
                  top: rect.top,
                  left: rect.left,
                  right: rect.right,
                  bottom: rect.bottom,
                  width: rect.width,
                  height: rect.height
                };
              }
              async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
                const steps = 3 + Math.floor(Math.random() * 3); // 随机3-6步
                if (window.AppChannel) {
                  window.AppChannel.postMessage("开始移动鼠标"); // 通知开始移动
                }
                for (let i = 0; i < steps; i++) {
                  const progress = i / steps; // 移动进度
                  const offsetX = Math.sin(progress * Math.PI) * 8 * (Math.random() - 0.5); // X轴偏移
                  const offsetY = Math.sin(progress * Math.PI) * 8 * (Math.random() - 0.5); // Y轴偏移
                  const curX = fromX + (toX - fromX) * progress + offsetX; // 当前X坐标
                  const curY = fromY + (toY - fromY) * progress + offsetY; // 当前Y坐标
                  const mousemoveEvent = new MouseEvent('mousemove', {
                    'view': window,
                    'bubbles': true,
                    'cancelable': true,
                    'clientX': curX,
                    'clientY': curY
                  }); // 创建鼠标移动事件
                  const elementAtPoint = document.elementFromPoint(curX, curY); // 获取当前位置元素
                  if (elementAtPoint) {
                    elementAtPoint.dispatchEvent(mousemoveEvent); // 触发事件
                  } else {
                    document.body.dispatchEvent(mousemoveEvent); // 触发到body
                  }
                  await new Promise(r => setTimeout(r, 10 + Math.random() * 20)); // 随机延迟
                }
                if (window.AppChannel) {
                  window.AppChannel.postMessage("完成鼠标移动"); // 通知完成
                }
              }
              async function simulateHover(targetElement, x, y) {
                return new Promise((hoverResolve) => {
                  try {
                    const mouseoverEvent = new MouseEvent('mouseover', {
                      'view': window,
                      'bubbles': true,
                      'cancelable': true,
                      'clientX': x,
                      'clientY': y
                    }); // 创建悬停事件
                    targetElement.dispatchEvent(mouseoverEvent); // 触发事件
                    const hoverTime = 100 + Math.floor(Math.random() * 200); // 随机悬停时间
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("鼠标悬停"); // 通知悬停
                    }
                    setTimeout(() => {
                      hoverResolve(); // 完成悬停
                    }, hoverTime);
                  } catch (e) {
                    console.log("悬停操作出错: " + e); // 日志错误
                    hoverResolve(); // 出错继续
                  }
                });
              }
              async function simulateClick(targetElement, x, y) {
                return new Promise((clickResolve) => {
                  try {
                    const mousedownEvent = new MouseEvent('mousedown', {
                      'view': window,
                      'bubbles': true,
                      'cancelable': true,
                      'clientX': x,
                      'clientY': y,
                      'buttons': 1
                    }); // 创建鼠标按下事件
                    targetElement.dispatchEvent(mousedownEvent); // 触发事件
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("按下鼠标"); // 通知按下
                    }
                    const pressTime = 150 + Math.floor(Math.random() * 150); // 随机按压时间
                    setTimeout(() => {
                      const mouseupEvent = new MouseEvent('mouseup', {
                        'view': window,
                        'bubbles': true,
                        'cancelable': true,
                        'clientX': x,
                        'clientY': y,
                        'buttons': 0
                      }); // 创建鼠标释放事件
                      targetElement.dispatchEvent(mouseupEvent); // 触发事件
                      const clickEvent = new MouseEvent('click', {
                        'view': window,
                        'bubbles': true,
                        'cancelable': true,
                        'clientX': x,
                        'clientY': y
                      }); // 创建点击事件
                      targetElement.dispatchEvent(clickEvent); // 触发事件
                      if (window.AppChannel) {
                        window.AppChannel.postMessage("释放鼠标"); // 通知释放
                      }
                      if (targetElement === searchInput) {
                        searchInput.focus(); // 输入框获得焦点
                      }
                      lastX = x; // 更新X坐标
                      lastY = y; // 更新Y坐标
                      clickResolve(); // 完成点击
                    }, pressTime);
                  } catch (e) {
                    console.log("点击操作出错: " + e); // 日志错误
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("点击操作出错: " + e); // 通知错误
                    }
                    clickResolve(); // 出错继续
                  }
                });
              }
              async function clickTarget(isInputBox) {
                try {
                  const pos = getInputPosition(); // 获取输入框位置
                  let targetX, targetY, elementDescription;
                  let targetElement = null;
                  if (isInputBox) {
                    targetX = pos.left + (Math.random() * 0.6 + 0.2) * pos.width; // 随机X坐标
                    targetY = pos.top + (Math.random() * 0.6 + 0.2) * pos.height; // 随机Y坐标
                    elementDescription = "输入框"; // 描述
                    targetElement = searchInput; // 目标为输入框
                  } else {
                    targetX = pos.left + (Math.random() * 0.8 + 0.1) * pos.width; // 随机X坐标
                    targetY = Math.max(pos.top - (20 + Math.random() * 10), 5); // 随机Y坐标
                    elementDescription = "输入框上方空白处"; // 描述
                    targetElement = document.elementFromPoint(targetX, targetY); // 获取元素
                    if (!targetElement) {
                      for (let attempt = 1; attempt <= 5; attempt++) {
                        targetY += 2; // 向下调整
                        targetElement = document.elementFromPoint(targetX, targetY); // 重新获取
                        if (targetElement) break;
                      }
                      if (!targetElement) {
                        console.log("未在指定位置找到元素，使用body");
                        targetElement = document.body; // 使用body
                      }
                    }
                  }
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击" + elementDescription); // 通知准备点击
                  }
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY); // 移动鼠标
                  await simulateHover(targetElement, targetX, targetY); // 模拟悬停
                  await simulateClick(targetElement, targetX, targetY); // 模拟点击
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击" + elementDescription + "完成"); // 通知点击完成
                  }
                  return true; // 成功
                } catch (e) {
                  console.log("点击操作出错: " + e); // 日志错误
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击操作出错: " + e); // 通知错误
                  }
                  return false; // 失败
                }
              }
              async function fillSearchInput() {
                try {
                  searchInput.value = ''; // 清空输入框
                  searchInput.value = searchKeyword; // 填写关键词
                  const inputEvent = new Event('input', { bubbles: true, cancelable: true }); // 创建输入事件
                  searchInput.dispatchEvent(inputEvent); // 触发事件
                  const changeEvent = new Event('change', { bubbles: true, cancelable: true }); // 创建变更事件
                  searchInput.dispatchEvent(changeEvent); // 触发事件
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword); // 通知填写
                  }
                  return true; // 成功
                } catch (e) {
                  console.log("填写搜索关键词出错: " + e); // 日志错误
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写搜索关键词出错: " + e); // 通知错误
                  }
                  return false; // 失败
                }
              }
              async function clickSearchButton() {
                try {
                  const form = document.getElementById('form1'); // 获取表单
                  if (!form) {
                    console.log("未找到表单");
                    return false; // 失败
                  }
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找提交按钮
                  if (!submitButton) {
                    console.log("未找到提交按钮，直接提交表单");
                    form.submit(); // 直接提交
                    return true; // 成功
                  }
                  const rect = submitButton.getBoundingClientRect(); // 获取按钮位置
                  const targetX = rect.left + Math.random() * rect.width * 0.6 + rect.width * 0.2; // 随机X坐标
                  const targetY = rect.top + Math.random() * rect.height * 0.6 + rect.height * 0.2; // 随机Y坐标
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击搜索按钮"); // 通知准备点击
                  }
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY); // 移动鼠标
                  await simulateHover(submitButton, targetX, targetY); // 模拟悬停
                  await simulateClick(submitButton, targetX, targetY); // 模拟点击
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮完成"); // 通知点击完成
                  }
                  return true; // 成功
                } catch (e) {
                  console.log("点击搜索按钮出错: " + e); // 日志错误
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮出错: " + e); // 通知错误
                  }
                  try {
                    const form = document.getElementById('form1'); // 再次获取表单
                    if (form) form.submit(); // 尝试提交
                  } catch (e2) {
                    console.log("备用提交方式也失败: " + e2); // 日志错误
                  }
                  return false; // 失败
                }
              }
              async function executeSequence() {
                try {
                  await clickTarget(true); // 点击输入框
                  await new Promise(r => setTimeout(r, 500 + Math.floor(Math.random() * 500))); // 随机延迟
                  await clickTarget(false); // 点击输入框上方
                  await new Promise(r => setTimeout(r, 500 + Math.floor(Math.random() * 500))); // 随机延迟
                  await clickTarget(true); // 再次点击输入框
                  await new Promise(r => setTimeout(r, 200 + Math.floor(Math.random() * 300))); // 随机延迟
                  await fillSearchInput(); // 填写关键词
                  await new Promise(r => setTimeout(r, 500 + Math.floor(Math.random() * 500))); // 随机延迟
                  await clickTarget(false); // 点击输入框上方
                  await new Promise(r => setTimeout(r, 500 + Math.floor(Math.random() * 500))); // 随机延迟
                  await clickSearchButton(); // 点击搜索按钮
                  resolve(true); // 成功
                } catch (e) {
                  console.log("模拟序列执行出错: " + e); // 日志错误
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("模拟序列执行出错: " + e); // 通知错误
                  }
                  resolve(false); // 失败
                }
              }
              executeSequence(); // 执行模拟序列
            });
          }
          async function submitSearchForm() {
            console.log("准备提交搜索表单");
            const form = document.getElementById('form1'); // 获取表单
            const searchInput = document.getElementById('search'); // 获取输入框
            if (!form || !searchInput) {
              console.log("未找到有效的表单元素");
              console.log("表单数量: " + document.forms.length); // 日志表单数量
              for(let i = 0; i < document.forms.length; i++) {
                console.log("表单 #" + i + " ID: " + document.forms[i].id); // 日志表单ID
              }
              const inputs = document.querySelectorAll('input'); // 获取所有输入框
              console.log("输入框数量: " + inputs.length); // 日志输入框数量
              for(let i = 0; i < inputs.length; i++) {
                console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name); // 日志输入框信息
              }
              return false; // 失败
            }
            console.log("找到表单和输入框");
            try {
              console.log("开始模拟真人行为");
              const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword); // 模拟行为
              if (result) {
                console.log("模拟真人行为成功");
                if (window.AppChannel) {
                  setTimeout(function() {
                    window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知表单提交
                  }, 300);
                }
                return true; // 成功
              } else {
                console.log("模拟真人行为失败，尝试常规提交");
                try {
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找提交按钮
                  if (submitButton) {
                    submitButton.click(); // 点击按钮
                  } else {
                    form.submit(); // 直接提交
                  }
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知提交
                  }
                  return true; // 成功
                } catch (e2) {
                  console.log("备用提交方式也失败: " + e2); // 日志错误
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                  }
                  return false; // 失败
                }
              }
            } catch (e) {
              console.log("模拟行为失败: " + e); // 日志错误
              if (window.AppChannel) {
                window.AppChannel.postMessage('SIMULATION_FAILED'); // 通知模拟失败
              }
              try {
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找提交按钮
                if (submitButton) {
                  submitButton.click(); // 点击按钮
                } else {
                  form.submit(); // 直接提交
                }
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知提交
                }
                return true; // 成功
              } catch (e2) {
                console.log("备用提交方式也失败: " + e2); // 日志错误
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                }
                return false; // 失败
              }
            }
          }
          function checkFormElements() {
            const form = document.getElementById('form1'); // 获取表单
            const searchInput = document.getElementById('search'); // 获取输入框
            console.log("检查表单元素");
            if (form && searchInput) {
              console.log("找到表单元素!");
              window.__formCheckState.formFound = true; // 标记找到
              clearFormCheckInterval(); // 清除定时器
              (async function() {
                try {
                  const result = await submitSearchForm(); // 提交表单
                  if (result) {
                    console.log("表单处理成功");
                  } else {
                    console.log("表单处理失败");
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                    }
                  }
                } catch (e) {
                  console.log("表单提交异常: " + e); // 日志错误
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                  }
                }
              })();
            }
          }
          clearFormCheckInterval(); // 清除旧定时器
          window.__formCheckState.checkInterval = setInterval(checkFormElements, 500); // 设置定时检查
          console.log("开始定时检查表单元素");
          checkFormElements(); // 立即检查
        })();
      ''');
      LogUtil.i('表单检测脚本注入成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace); // 错误日志
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (isCancelled()) {
      LogUtil.i('任务已取消，中断导航'); // 已取消则中断
      cleanupResources(); // 清理资源
      return;
    }
    LogUtil.i('页面开始加载: $pageUrl');
    if (searchState['engineSwitched'] == true && 
        SousuoParser._isPrimaryEngine(pageUrl) && 
        controller != null) {
      LogUtil.i('已切换备用引擎，中断主引擎加载'); // 已切换则中断主引擎
      try {
        await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
      } catch (e) {
        LogUtil.e('中断主引擎加载时出错: $e'); // 错误日志
      }
      return;
    }
    if (!searchState['searchSubmitted'] && pageUrl != 'about:blank') {
      await injectFormDetectionScript(searchState['searchKeyword']); // 注入表单检测脚本
    }
  }
  
  /// 处理导航事件 - 页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理页面完成事件'); // 已取消则返回
      cleanupResources(); // 清理资源
      return;
    }
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch; // 当前时间
    final startMs = searchState['startTimeMs'] as int; // 开始时间
    final loadTimeMs = currentTimeMs - startMs; // 加载耗时
    LogUtil.i('页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms');
    if (pageUrl == 'about:blank') {
      LogUtil.i('空白页面，忽略'); // 空白页面则忽略
      return;
    }
    if (controller == null) {
      LogUtil.e('WebView控制器为空'); // 控制器为空
      return;
    }
    bool isPrimaryEngine = SousuoParser._isPrimaryEngine(pageUrl); // 是否主引擎
    bool isBackupEngine = SousuoParser._isBackupEngine(pageUrl); // 是否备用引擎
    if (!isPrimaryEngine && !isBackupEngine) {
      LogUtil.i('未知页面: $pageUrl'); // 未知页面
      return;
    }
    if (searchState['engineSwitched'] == true && isPrimaryEngine) {
      LogUtil.i('已切换备用引擎，忽略主引擎'); // 已切换则忽略主引擎
      return;
    }
    if (isPrimaryEngine) {
      searchState['activeEngine'] = 'primary'; // 设置主引擎
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) {
      searchState['activeEngine'] = 'backup'; // 设置备用引擎
      LogUtil.i('备用引擎页面加载完成');
    }
    if (searchState['searchSubmitted'] == true) {
      if (!isExtractionInProgress && !isTestingStarted && !_extractionTriggered) {
        Timer(Duration(milliseconds: 500), () {
          if (controller != null && !completer.isCompleted && !isCancelled()) {
            LogUtil.i('页面加载完成后主动尝试提取链接');
            handleContentChange(); // 处理内容变化
          }
        });
      }
    }
  }
  
  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理资源错误'); // 已取消则返回
      cleanupResources(); // 清理资源
      return;
    }
    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}'); // 错误日志
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.webp') || 
        error.url!.endsWith('.css')) {
      return; // 忽略非关键资源错误
    }
    if (searchState['activeEngine'] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) {
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode); // 检查关键错误
      if (isCriticalError) {
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState['primaryEngineLoadFailed'] = true; // 标记主引擎失败
        if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
          LogUtil.i('主引擎加载失败，切换备用引擎');
          switchToBackupEngine(); // 切换备用引擎
        }
      }
    }
  }
  
  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，阻止所有导航'); // 已取消则阻止
      return NavigationDecision.prevent; // 阻止导航
    }
    if (searchState['engineSwitched'] == true && SousuoParser._isPrimaryEngine(request.url)) {
      LogUtil.i('阻止主引擎导航'); // 已切换则阻止主引擎
      return NavigationDecision.prevent; // 阻止导航
    }
    if (request.url.endsWith('.png') || 
        request.url.endsWith('.jpg') || 
        request.url.endsWith('.jpeg') || 
        request.url.endsWith('.gif') || 
        request.url.endsWith('.webp') || 
        request.url.endsWith('.css') ||
        request.url.endsWith('.svg') ||
        request.url.endsWith('.woff') ||
        request.url.endsWith('.woff2') ||
        request.url.endsWith('.ttf') ||
        request.url.endsWith('.ico') ||
        request.url.contains('google-analytics.com') ||
        request.url.contains('googletagmanager.com') ||
        request.url.contains('facebook.com') ||
        request.url.contains('twitter.com')) {
      LogUtil.i('阻止加载非必要资源: ${request.url}');
      return NavigationDecision.prevent; // 阻止非必要资源
    }
    return NavigationDecision.navigate; // 允许导航
  }
  
  /// 处理JavaScript消息
  void handleJavaScriptMessage(JavaScriptMessage message) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理JS消息'); // 已取消则返回
      cleanupResources(); // 清理资源
      return;
    }
    LogUtil.i('收到消息: ${message.message}');
    if (controller == null) {
      LogUtil.e('控制器为空，无法处理消息'); // 控制器为空
      return;
    }
    if (message.message.startsWith('点击输入框上方') || 
        message.message.startsWith('点击body') ||
        message.message.startsWith('点击了随机元素') ||
        message.message.startsWith('点击页面随机位置') ||
        message.message.startsWith('填写后点击')) {
      LogUtil.i('模拟行为: ${message.message}'); // 日志模拟行为
    } else if (message.message == 'FORM_SUBMITTED') {
      LogUtil.i('表单已提交');
      searchState['searchSubmitted'] = true; // 标记表单提交
      searchState['stage'] = ParseStage.searchResults; // 设置阶段为搜索结果
      searchState['stage2StartTime'] = DateTime.now().millisecondsSinceEpoch; // 记录阶段2开始时间
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel'); // 注入DOM变化监听器
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      LogUtil.i('表单处理失败');
      if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
        LogUtil.i('主引擎表单处理失败，切换备用引擎');
        switchToBackupEngine(); // 切换备用引擎
      }
    } else if (message.message == 'SIMULATION_FAILED') {
      LogUtil.e('模拟真人行为失败'); // 日志错误
    } else if (message.message.startsWith('模拟真人行为') ||
               message.message.startsWith('点击了搜索输入框') ||
               message.message.startsWith('填写了搜索关键词') ||
               message.message.startsWith('点击提交按钮')) {
      LogUtil.i('模拟行为日志: ${message.message}'); // 日志模拟行为
    } else if (message.message == 'CONTENT_CHANGED') {
      LogUtil.i('页面内容变化');
      handleContentChange(); // 处理内容变化
    }
  }
  
  /// 开始解析流程
  Future<String> startParsing(String url) async {
    try {
      if (isCancelled()) {
        LogUtil.i('任务已取消，不执行解析'); // 已取消则返回
        return 'ERROR'; // 返回错误
      }
      setupCancelListener(); // 设置取消监听
      setupGlobalTimeout(); // 设置全局超时
      LogUtil.i('从URL提取搜索关键词');
      final uri = Uri.parse(url); // 解析URL
      final searchKeyword = uri.queryParameters['clickText']; // 提取关键词
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText'); // 日志错误
        return 'ERROR'; // 返回错误
      }
      LogUtil.i('提取到搜索关键词: $searchKeyword');
      searchState['searchKeyword'] = searchKeyword; // 设置关键词
      LogUtil.i('创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JavaScript
        ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
      LogUtil.i('WebView控制器创建完成');
      LogUtil.i('设置WebView导航委托');
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: handlePageStarted, // 页面开始加载
        onPageFinished: handlePageFinished, // 页面加载完成
        onWebResourceError: handleWebResourceError, // 资源错误
        onNavigationRequest: handleNavigationRequest, // 导航请求
      ));
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: handleJavaScriptMessage, // 处理JS消息
      );
      LogUtil.i('JavaScript通道添加完成');
      try {
        LogUtil.i('开始加载页面: ${SousuoParser._primaryEngine}');
        await controller!.loadRequest(Uri.parse(SousuoParser._primaryEngine)); // 加载主引擎
        LogUtil.i('页面加载请求已发出');
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e'); // 日志错误
        if (searchState['engineSwitched'] == false) {
          LogUtil.i('主引擎加载失败，准备切换备用引擎');
          switchToBackupEngine(); // 切换备用引擎
        }
      }
      final result = await completer.future; // 等待解析结果
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      int endTimeMs = DateTime.now().millisecondsSinceEpoch; // 结束时间
      int startMs = searchState['startTimeMs'] as int; // 开始时间
      LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');耗时
      return result; // 返回结果
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace); // 日志错误
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
        try {
          final result = await SousuoParser._testStreamsAndGetFastest(foundStreams, cancelToken: cancelToken); // 测试流
          if (!completer.isCompleted) {
            completer.complete(result); // 完成并返回结果
          }
          return result; // 返回结果
        } catch (testError) {
          LogUtil.e('测试流时出错: $testError'); // 日志错误
          if (!completer.isCompleted) {
            completer.complete('ERROR'); // 完成并返回错误
          }
        }
      } else if (!completer.isCompleted) {
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR'); // 完成并返回错误
      }
      return completer.isCompleted ? await completer.future : 'ERROR'; // 返回结果
    } finally {
      if (!isResourceCleaned) {
        await cleanupResources(); // 清理资源
      }
    }
  }
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用引擎URL
  
  // 通用配置
  static const int _timeoutSeconds = 13; // 统一超时时间
  static const int _maxStreams = 8; // 最大提取流数量
  
  // 时间常量 - 页面和DOM相关
  static const int _waitSeconds = 2; // 页面加载等待时间
  static const int _domChangeWaitMs = 500; // DOM变化等待时间
  
  // 时间常量 - 测试和清理相关
  static const int _flowTestWaitMs = 500; // 流测试等待时间
  static const int _backupEngineLoadWaitMs = 300; // 切换备用引擎等待时间
  static const int _cleanupRetryWaitMs = 300; // 清理重试等待时间
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 5.0; // 显著内容变化百分比
  
  // 内容变化防抖时间
  static const int _contentChangeDebounceMs = 300; // 防抖时间（毫秒）

  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
      LogUtil.i('清理WebView完成');
    } catch (e) {
      LogUtil.e('清理 outfits: $e'); // 日志错误
    }
  }
  
  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us'); // 检查是否包含主引擎域名
  }

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com'); // 检查是否包含备用引擎域名
  }
  
  /// 注入DOM变化监听器 - 使用内容变化百分比检测
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          const initialContentLength = document.body.innerHTML.length; // 初始内容长度
          console.log("初始内容长度: " + initialContentLength);
          let lastNotificationTime = Date.now(); // 上次通知时间
          let lastNotifiedLength = initialContentLength; // 上次通知内容长度
          let debounceTimeout = null; // 防抖定时器
          const notifyContentChanged = function() {
            if (debounceTimeout) {
              clearTimeout(debounceTimeout); // 清除防抖定时器
            }
            debounceTimeout = setTimeout(function() {
              const now = Date.now(); // 当前时间
              if (now - lastNotificationTime < 1000) {
                console.log("忽略过于频繁的内容变化通知");
                return;
              }
              lastNotificationTime = now; // 更新通知时间
              lastNotifiedLength = document.body.innerHTML.length; // 更新内容长度
              console.log("通知应用内容变化");
              ${channelName}.postMessage('CONTENT_CHANGED'); // 通知内容变化
              debounceTimeout = null; // 清空定时器
            }, 200); // 200ms防抖
          };
          const observer = new MutationObserver(function(mutations) { // 创建观察者
            const currentContentLength = document.body.innerHTML.length; // 当前内容长度
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100; // 计算变化百分比
            console.log("内容长度变化百分比: " + contentChangePct.toFixed(2) + "%");
            if (contentChangePct > ${_significantChangePercent}) { // 超过阈值
              console.log("检测到显著内容变化");
              notifyContentChanged(); // 通知变化
            }
          });
          observer.observe(document.body, { // 配置观察者
            childList: true, 
            subtree: true,
            attributes: true,
            characterData: true 
          });
          setTimeout(function() {
            const currentContentLength = document.body.innerHTML.length; // 当前内容长度
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100; // 计算变化百分比
            console.log("延迟检查内容变化百分比: " + contentChangePct.toFixed(2) + "%");
            if (contentChangePct > ${_significantChangePercent}) {
              console.log("检测到显著内容变化");
              notifyContentChanged(); // 通知变化
            }
          }, 1000); // 延迟检查
        })();
      ''');
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace); // 日志错误
    }
  }
  
  /// 提交搜索表单
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面加载
    try {
      final submitScript = '''
        (function() {
          console.log("查找搜索表单元素");
          const form = document.getElementById('form1'); // 获取表单
          const searchInput = document.getElementById('search'); // 获取输入框
          const submitButton = document.querySelector('input[name="Submit"]'); // 获取提交按钮
          if (!searchInput || !form) {
            console.log("未找到表单元素");
            console.log("表单数量: " + document.forms.length); // 日志表单数量
            for(let i = 0; i < document.forms.length; i++) {
              console.log("表单 #" + i + " ID: " + document.forms[i].id); // 日志表单ID
            }
            const inputs = document.querySelectorAll('input'); // 获取所有输入框
            console.log("输入框数量: " + inputs.length); // 日志输入框数量
            for(let i = 0; i < inputs.length; i++) {
              console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name); // 日志输入框信息
            }
            return false; // 失败
          }
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}"; // 填写关键词
          console.log("填写关键词: " + searchInput.value);
          if (submitButton) {
            console.log("点击提交按钮");
            submitButton.click(); // 点击按钮
            return true; // 成功
          } else {
            console.log("未找到提交按钮，尝试其他方法");
            const otherSubmitButton = form.querySelector('input[type="submit"]'); // 查找其他提交按钮
            if (otherSubmitButton) {
              console.log("找到submit按钮，点击");
              otherSubmitButton.click(); // 点击按钮
              return true; // 成功
            } else {
              console.log("直接提交表单");
              form.submit(); // 直接提交
              return true; // 成功
            }
          }
        })();
      ''';
      final result = await controller.runJavaScriptReturningResult(submitScript); // 执行提交脚本
      await Future.delayed(Duration(seconds: _waitSeconds)); // 等待响应
      LogUtil.i('等待响应 (${_waitSeconds}秒)');
      return result.toString().toLowerCase() == 'true'; // 返回提交结果
    } catch (e, stackTrace) {
      LogUtil.logError('提交表单出错', e, stackTrace); // 日志错误
      return false; // 失败
    }
  }

  /// 提取媒体链接，优先提取m3u8格式
  static Future<void> _extractMediaLinks(
    WebViewController controller, 
    List<String> foundStreams, 
    bool usingBackupEngine, 
    {int lastProcessedLength = 0}
  ) async {
    LogUtil.i('从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
    try {
      final html = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML' // 获取页面HTML
      );
      String htmlContent = html.toString(); // 转换为字符串
      LogUtil.i('获取HTML，长度: ${htmlContent.length}');
      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                        .replaceAll('\\"', '"')
                        .replaceAll('\\n', '\n'); // 清理HTML字符串
      }
      final RegExp regex = RegExp(
        'onclick="[a-zA-Z]+\\((?:"|"|\')?((https?://[^"\']+)(?:"|"|\')?)',
        caseSensitive: false
      ); // 正则表达式匹配链接
      String matchSample = ""; // 匹配示例
      final matches = regex.allMatches(htmlContent); // 获取所有匹配
      int totalMatches = matches.length; // 匹配总数
      List<String> m3u8Links = []; // m3u8链接列表
      List<String> otherLinks = []; // 其他链接列表
      if (totalMatches > 0) {
        final firstMatch = matches.first; // 第一个匹配
        matchSample = "示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(1)}"; // 记录示例
        LogUtil.i(matchSample);
      }
      final Set<String> hostSet = Set<String>.from(
        foundStreams.map((url) {
          try {
            final uri = Uri.parse(url); // 解析URL
            return '${uri.host}:${uri.port}'; // 返回主机和端口
          } catch (_) {
            return url; // 无效URL保留
          }
        })
      ); // 已提取主机集合
      for (final match in matches) {
        if (match.groupCount >= 1) {
          String? mediaUrl = match.group(1)?.trim(); // 获取URL
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            mediaUrl = mediaUrl
                .replaceAll('&', '&')
                .replaceAll('"', '"')
                .replaceAll(RegExp("[\")'&;]+\$"), ''); // 清理URL
            try {
              final uri = Uri.parse(mediaUrl); // 解析URL
              final String hostKey = '${uri.host}:${uri.port}'; // 主机键
              if (!hostSet.contains(hostKey)) {
                hostSet.add(hostKey); // 添加主机
                if (mediaUrl.toLowerCase().contains('.m3u8')) {
                  m3u8Links.add(mediaUrl); // 添加m3u8链接
                  LogUtil.i('提取到m3u8链接: $mediaUrl');
                } else {
                  otherLinks.add(mediaUrl); // 添加其他链接
                  LogUtil.i('提取到其他格式链接: $mediaUrl');
                }
              } else {
                LogUtil.i('跳过相同主机的链接: $mediaUrl');
              }
            } catch (e) {
              LogUtil.e('解析URL出错: $e, URL: $mediaUrl'); // 日志错误
            }
          }
        }
      }
      int addedCount = 0; // 新增链接计数
      for (final link in m3u8Links) {
        foundStreams.add(link); // 添加m3u8链接
        addedCount++; // 增加计数
        if (foundStreams.length >= _maxStreams) {
          LogUtil.i('达到最大链接数 $_maxStreams，m3u8链接已足够');
          break;
        }
      }
      if (foundStreams.length < _maxStreams) {
        LogUtil.i('m3u8链接数量不足，添加其他格式链接');
        for (final link in otherLinks) {
          foundStreams.add(link); // 添加其他链接
          addedCount++; // 增加计数
          if (foundStreams.length >= _maxStreams) {
            LogUtil.i('达到最大链接数 $_maxStreams');
            break;
          }
        }
      }
      LogUtil.i('匹配数: $totalMatches, m3u8格式: ${m3u8Links.length}, 其他格式: ${otherLinks.length}, 新增: $addedCount');
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length; // 样本长度
        String debugSample = htmlContent.substring(0, sampleLength); // HTML样本
        final onclickRegex = RegExp('onclick="[^"]+"', caseSensitive: false); // onclick正则
        final onclickMatches = onclickRegex.allMatches(htmlContent).take(3).map((m) => m.group(0)).join(', '); // 获取前3个onclick
        LogUtil.i('无链接，HTML片段: $debugSample');
        if (onclickMatches.isNotEmpty) {
          LogUtil.i('页面中的onclick样本: $onclickMatches');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取链接出错', e, stackTrace); // 日志错误
    }
    LogUtil.i('提取完成，链接数: ${foundStreams.length}');
  }
  
  /// 测试流地址并返回最快有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams, {CancelToken? cancelToken}) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR'; // 返回错误
    }
    LogUtil.i('测试 ${streams.length} 个流地址');
    final testCancelToken = cancelToken ?? CancelToken(); // 创建测试取消令牌
    final completer = Completer<String>(); // 创建完成器
    bool hasValidResponse = false; // 是否有有效响应
    final testTimeoutTimer = Timer(Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        LogUtil.i('流测试超时，取消所有进行中的请求');
        if (!testCancelToken.isCancelled) {
          testCancelToken.cancel('测试超时'); // 取消测试
        }
        if (!hasValidResponse) {
          completer.complete('ERROR'); // 完成并返回错误
        }
      }
    }); // 设置测试超时
    final tasks = streams.map((streamUrl) async {
      try {
        if (completer.isCompleted || testCancelToken.isCancelled) return; // 已完成或取消则返回
        final stopwatch = Stopwatch()..start(); // 开始计时
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl), // 设置请求头
            method: 'GET',
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400, // 验证状态码
          ),
          cancelToken: testCancelToken, // 取消令牌
          retryCount: 1, // 重试次数
        ); // 发送请求
        if (response != null && !completer.isCompleted && !testCancelToken.isCancelled) {
          final responseTime = stopwatch.elapsedMilliseconds; // 响应时间
          LogUtil.i('流 $streamUrl 响应: ${responseTime}ms');
          hasValidResponse = true; // 标记有效响应
          if (!testCancelToken.isCancelled) {
            LogUtil.i('找到可用流，取消其他测试请求');
            testCancelToken.cancel('找到可用流'); // 取消其他测试
          }
          completer.complete(streamUrl); // 完成并返回流地址
        }
      } catch (e) {
        if (testCancelToken.isCancelled) {
          LogUtil.i('测试已取消: $streamUrl');
        } else {
          LogUtil.e('测试 $streamUrl 出错: $e'); // 日志错误
        }
      }
    }).toList(); // 创建测试任务列表
    try {
      await Future.wait(tasks); // 等待所有任务
      if (!completer.isCompleted) {
        LogUtil.i('所有流测试完成但未找到可用流');
        completer.complete('ERROR'); // 完成并返回错误
      }
      return await completer.future; // 返回结果
    } finally {
      testTimeoutTimer.cancel(); // 取消超时计时器
      LogUtil.i('流测试完成，清理资源');
    }
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    final session = _ParserSession(cancelToken: cancelToken); // 创建解析会话
    return await session.startParsing(url); // 开始解析并返回结果
  }
}
