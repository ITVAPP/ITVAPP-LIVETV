import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 解析阶段枚举 - 移至顶层
enum ParseStage {
  formSubmission,  // 阶段1: 页面加载和表单提交
  searchResults,   // 阶段2: 搜索结果处理和流测试
  completed,       // 完成
  error            // 错误
}

/// 解析会话类 - 处理解析逻辑和状态管理
class _ParserSession {
  final Completer<String> completer = Completer<String>();
  final List<String> foundStreams = [];
  WebViewController? controller;
  bool contentChangedDetected = false;
  Timer? contentChangeDebounceTimer;
  
  // 状态标记
  bool isResourceCleaned = false;
  bool isTestingStarted = false;
  bool isExtractionInProgress = false;
  
  // 提取触发标记
  static bool _extractionTriggered = false;
  
  // 状态对象
  final Map<String, dynamic> searchState = {
    'searchKeyword': '',
    'activeEngine': 'primary',
    'searchSubmitted': false,
    'startTimeMs': DateTime.now().millisecondsSinceEpoch,
    'engineSwitched': false,
    'primaryEngineLoadFailed': false,
    'lastHtmlLength': 0,
    'extractionCount': 0,
    'stage': ParseStage.formSubmission,
    'stage1StartTime': DateTime.now().millisecondsSinceEpoch,
    'stage2StartTime': 0,
  };
  
  // 全局超时计时器
  Timer? globalTimeoutTimer;
  
  // 取消监听
  StreamSubscription? cancelListener;
  
  // 取消令牌
  final CancelToken? cancelToken;
  
  _ParserSession({this.cancelToken});
  
  /// 检查是否已取消
  bool isCancelled() {
    return cancelToken?.isCancelled ?? false;
  }
  
  /// 设置取消监听器 - 优化使用Future而不是转换为Stream
  void setupCancelListener() {
    if (cancelToken != null) {
      cancelToken!.whenCancel.then((_) {
        LogUtil.i('检测到取消信号，立即释放所有资源');
        cleanupResources(immediate: true);
      });
    }
  }
  
  /// 设置全局超时
  void setupGlobalTimeout() {
    // 清除可能存在的旧计时器
    globalTimeoutTimer?.cancel();
    
    LogUtil.i('设置全局超时: ${SousuoParser._timeoutSeconds}秒');
    
    // 设置全局超时计时器
    globalTimeoutTimer = Timer(Duration(seconds: SousuoParser._timeoutSeconds), () {
      LogUtil.i('全局超时触发');
      
      if (isCancelled() || completer.isCompleted) return;
      
      // 检查流的状态
      if (foundStreams.isNotEmpty) {
        LogUtil.i('全局超时触发，但已找到 ${foundStreams.length} 个流，开始测试');
        startStreamTesting();
      }
      // 检查引擎状态
      else if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
        LogUtil.i('全局超时触发，主引擎未找到流，切换备用引擎');
        switchToBackupEngine();
      } 
      // 无可用流，返回错误
      else {
        LogUtil.i('全局超时触发，无可用流');
        if (!completer.isCompleted) {
          completer.complete('ERROR');
          cleanupResources();
        }
      }
    });
  }
  
  /// 清理资源 - 优化版本，确保资源释放的可靠性和原子性
  Future<void> cleanupResources({bool immediate = false}) async {
    // 使用同步锁避免重复清理
    if (isResourceCleaned) {
      LogUtil.i('资源已清理，跳过');
      return;
    }
    
    // 立即标记为已清理，防止并发调用
    isResourceCleaned = true;
    LogUtil.i('开始清理资源');
    
    try {
      // 1. 首先取消所有计时器 - 避免后续操作被计时器中断
      if (globalTimeoutTimer != null) {
        globalTimeoutTimer!.cancel();
        globalTimeoutTimer = null;
        LogUtil.i('全局超时计时器已取消');
      }
      
      if (contentChangeDebounceTimer != null) {
        contentChangeDebounceTimer!.cancel();
        contentChangeDebounceTimer = null;
        LogUtil.i('内容变化防抖计时器已取消');
      }
      
      // 2. 取消订阅监听器
      if (cancelListener != null) {
        try {
          await cancelListener!.cancel();
        } catch (e) {
          LogUtil.e('取消监听器时出错: $e');
        } finally {
          cancelListener = null;
          LogUtil.i('取消监听器已清理');
        }
      }
      
      // 3. 处理WebView控制器 - 改进错误处理和资源释放
      if (controller != null) {
        final tempController = controller; // 保存临时引用
        controller = null; // 立即清空引用避免重复清理
        
        try {
          // 尝试加载空白页面以停止当前加载
          await tempController!.loadHtmlString('<html><body></body></html>');
          
          if (!immediate) {
            // 等待短暂时间确保页面加载
            await Future.delayed(Duration(milliseconds: 100));
            // 调用WebView资源清理方法
            await SousuoParser._disposeWebView(tempController);
          }
          LogUtil.i('WebView控制器已清理');
        } catch (e) {
          LogUtil.e('清理WebView资源时出错: $e');
        }
      }
      
      // 4. 处理未完成的Completer
      if (!completer.isCompleted) {
        LogUtil.i('Completer未完成，强制返回ERROR');
        completer.complete('ERROR');
      }
      
      LogUtil.i('所有资源清理完成');
    } catch (e) {
      LogUtil.e('清理资源过程中出错: $e');
      
      // 确保在异常情况下也完成Completer
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    }
  }
  
  /// 开始测试流链接 - 改进错误处理和资源管理
  void startStreamTesting() {
    // 防止重复测试
    if (isTestingStarted) {
      LogUtil.i('已经开始测试流链接，忽略重复测试请求');
      return;
    }
    
    // 检查是否有流可测试
    if (foundStreams.isEmpty) {
      LogUtil.i('没有找到流链接，无法开始测试');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }
    
    isTestingStarted = true;
    LogUtil.i('开始测试 ${foundStreams.length} 个流链接');
    
    // 创建专用的测试取消令牌，确保与父级cancelToken联动
    final testCancelToken = CancelToken();
    
    // 监听父级cancelToken的取消事件
    StreamSubscription? testCancelListener;
    if (cancelToken != null) {
      testCancelListener = cancelToken?.whenCancel?.asStream().listen((_) {
        if (!testCancelToken.isCancelled) {
          LogUtil.i('父级cancelToken已取消，取消所有测试请求');
          testCancelToken.cancel('父级已取消');
        }
      });
    }
    
    try {
      // 使用Future API的完整错误处理链
      SousuoParser._testStreamsAndGetFastest(foundStreams, cancelToken: testCancelToken)
        .then((String result) {
          LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
          if (!completer.isCompleted) {
            completer.complete(result);
            cleanupResources();
          }
        })
        .catchError((e) {
          // 显式处理测试过程中的异常
          LogUtil.e('测试流过程中出错: $e');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            cleanupResources();
          }
        })
        .whenComplete(() {
          // 确保监听器始终被取消
          testCancelListener?.cancel();
        });
    } catch (e) {
      // 处理启动测试过程中的同步异常
      LogUtil.e('启动流测试出错: $e');
      testCancelListener?.cancel();
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState['engineSwitched'] == true) {
      LogUtil.i('已切换到备用引擎，忽略');
      return;
    }
    
    if (isCancelled()) {
      LogUtil.i('任务已取消，不切换到备用引擎');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        await cleanupResources();
      }
      return;
    }
    
    LogUtil.i('主引擎不可用，切换到备用引擎');
    searchState['activeEngine'] = 'backup';
    searchState['engineSwitched'] = true;
    searchState['searchSubmitted'] = false;
    searchState['lastHtmlLength'] = 0;
    searchState['extractionCount'] = 0;
    
    searchState['stage'] = ParseStage.formSubmission;
    searchState['stage1StartTime'] = DateTime.now().millisecondsSinceEpoch;
    
    _extractionTriggered = false;
    
    // 重置全局超时
    globalTimeoutTimer?.cancel();
    
    if (controller != null) {
      try {
        await controller!.loadHtmlString('<html><body></body></html>');
        await Future.delayed(Duration(milliseconds: SousuoParser._backupEngineLoadWaitMs));
        
        await controller!.loadRequest(Uri.parse(SousuoParser._backupEngine));
        LogUtil.i('已加载备用引擎: ${SousuoParser._backupEngine}');
        
        // 设置新的全局超时
        setupGlobalTimeout();
      } catch (e) {
        LogUtil.e('加载备用引擎时出错: $e');
        if (!isResourceCleaned && !completer.isCompleted) {
          LogUtil.i('加载备用引擎失败，返回ERROR');
          completer.complete('ERROR');
          await cleanupResources();
        }
      }
    } else {
      LogUtil.e('WebView控制器为空，无法切换');
      if (!isResourceCleaned && !completer.isCompleted) {
        completer.complete('ERROR');
        await cleanupResources();
      }
    }
  }
  
  /// 处理内容变化 - 优化防抖逻辑
  void handleContentChange() {
    // 先取消现有计时器
    contentChangeDebounceTimer?.cancel();
    
    // 检查任务状态，避免不必要的处理
    if (isCancelled()) {
      LogUtil.i('任务已取消，停止处理内容变化');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }
    
    // 处理状态检查，避免并发提取
    if (isExtractionInProgress) {
      LogUtil.i('提取操作正在进行中，跳过此次提取');
      return;
    }
    
    if (_extractionTriggered) {
      LogUtil.i('已经触发过提取操作，跳过此次提取');
      return;
    }
    
    // 使用防抖动延迟执行内容处理
    contentChangeDebounceTimer = Timer(Duration(milliseconds: SousuoParser._contentChangeDebounceMs), () async {
      // 再次检查状态，防止在延迟期间状态变化
      if (controller == null || completer.isCompleted || isCancelled()) return;
      
      // 标记提取进行中，防止并发提取
      isExtractionInProgress = true;
      
      LogUtil.i('处理页面内容变化（防抖后）');
      contentChangedDetected = true;
      
      try {
        if (searchState['searchSubmitted'] == true && !completer.isCompleted && !isTestingStarted) {
          _extractionTriggered = true;
          
          int beforeExtractCount = foundStreams.length;
          bool isBackupEngine = searchState['activeEngine'] == 'backup';
          
          await SousuoParser._extractMediaLinks(
            controller!, 
            foundStreams, 
            isBackupEngine,
            lastProcessedLength: searchState['lastHtmlLength']
          );
          
          try {
            final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length');
            searchState['lastHtmlLength'] = int.tryParse(result.toString()) ?? 0;
          } catch (e) {
            LogUtil.e('获取HTML长度时出错: $e');
          }
          
          searchState['extractionCount'] = searchState['extractionCount'] + 1;
          int afterExtractCount = foundStreams.length;
          
          if (afterExtractCount > beforeExtractCount) {
            LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接');
            
            if (afterExtractCount >= SousuoParser._maxStreams) {
              LogUtil.i('达到最大链接数 ${SousuoParser._maxStreams}，开始测试');
              startStreamTesting();
            }
            else if (afterExtractCount > 0) {
              LogUtil.i('提取完成，找到 ${afterExtractCount} 个链接，立即开始测试');
              startStreamTesting();
            }
          } else if (searchState['activeEngine'] == 'primary' && 
                    afterExtractCount == 0 && 
                    searchState['engineSwitched'] == false) {
            _extractionTriggered = false;
            LogUtil.i('主引擎无链接，切换备用引擎，重置提取标记');
            switchToBackupEngine();
          }
        }
      } catch (e) {
        LogUtil.e('处理内容变化时出错: $e');
      } finally {
        // 确保标记被重置，避免死锁
        isExtractionInProgress = false;
      }
    });
  }
  
  /// 注入表单检测脚本
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return;
    try {
      await controller!.runJavaScript('''
        (function() {
          console.log("开始注入表单检测脚本");
          
          // 存储检查状态
          window.__formCheckState = {
            formFound: false,
            checkInterval: null,
            searchKeyword: "${searchKeyword.replaceAll('"', '\\"')}"
          };
          
          // 清理检查定时器
          function clearFormCheckInterval() {
            if (window.__formCheckState.checkInterval) {
              clearInterval(window.__formCheckState.checkInterval);
              window.__formCheckState.checkInterval = null;
              console.log("停止表单检测");
            }
          }
          
          // 定义人类行为模拟常量
          const MOUSE_MOVEMENT_STEPS = 6;        // 鼠标移动步数（次数）
          const MOUSE_MOVEMENT_OFFSET = 8;       // 鼠标移动偏移量（像素）
          const MOUSE_MOVEMENT_DELAY_MS = 50;    // 鼠标移动延迟（毫秒）
          const MOUSE_HOVER_TIME_MS = 200;       // 鼠标悬停时间（毫秒）
          const MOUSE_PRESS_TIME_MS = 300;       // 鼠标按压时间（毫秒）
          const ACTION_DELAY_MS = 1000;          // 操作间隔时间（毫秒）
          
          // 改进后的模拟真人行为函数
          function simulateHumanBehavior(searchKeyword) {
            return new Promise((resolve) => {
              if (window.AppChannel) {
                window.AppChannel.postMessage('开始模拟真人行为');
              }
              
              // 获取搜索输入框
              const searchInput = document.getElementById('search');
              
              if (!searchInput) {
                console.log("未找到搜索输入框");
                if (window.AppChannel) {
                  window.AppChannel.postMessage("未找到搜索输入框");
                }
                return resolve(false);
              }
              
              // 跟踪上一次点击的位置，用于模拟鼠标移动
              let lastX = window.innerWidth / 2;
              let lastY = window.innerHeight / 2;
              
              // 获取输入框的位置和大小
              function getInputPosition() {
                const rect = searchInput.getBoundingClientRect();
                return {
                  top: rect.top,
                  left: rect.left,
                  right: rect.right,
                  bottom: rect.bottom,
                  width: rect.width,
                  height: rect.height
                };
              }
              
              // 模拟鼠标移动轨迹，使用固定步数和固定延迟
              async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
                const steps = MOUSE_MOVEMENT_STEPS; // 固定步数
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("开始移动鼠标");
                }
                
                for (let i = 0; i < steps; i++) {
                  const progress = i / steps;
                  // 使用固定偏移量
                  const offsetX = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET;
                  const offsetY = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET;
                  
                  const curX = fromX + (toX - fromX) * progress + offsetX;
                  const curY = fromY + (toY - fromY) * progress + offsetY;
                  
                  const mousemoveEvent = new MouseEvent('mousemove', {
                    'view': window,
                    'bubbles': true,
                    'cancelable': true,
                    'clientX': curX,
                    'clientY': curY
                  });
                  
                  const elementAtPoint = document.elementFromPoint(curX, curY);
                  if (elementAtPoint) {
                    elementAtPoint.dispatchEvent(mousemoveEvent);
                  } else {
                    document.body.dispatchEvent(mousemoveEvent);
                  }
                  
                  await new Promise(r => setTimeout(r, MOUSE_MOVEMENT_DELAY_MS)); // 固定延迟
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("完成鼠标移动");
                }
              }
              
              // 模拟鼠标悬停，使用固定时间
              async function simulateHover(targetElement, x, y) {
                return new Promise((hoverResolve) => {
                  try {
                    const mouseoverEvent = new MouseEvent('mouseover', {
                      'view': window,
                      'bubbles': true,
                      'cancelable': true,
                      'clientX': x,
                      'clientY': y
                    });
                    targetElement.dispatchEvent(mouseoverEvent);
                    
                    // 固定悬停时间
                    const hoverTime = MOUSE_HOVER_TIME_MS;
                    
                    setTimeout(() => {
                      hoverResolve();
                    }, hoverTime);
                  } catch (e) {
                    console.log("悬停操作出错: " + e);
                    hoverResolve();
                  }
                });
              }
              
              // 完整的点击操作，使用固定按压时间
              async function simulateClick(targetElement, x, y) {
                return new Promise((clickResolve) => {
                  try {
                    // 创建并触发mousedown事件
                    const mousedownEvent = new MouseEvent('mousedown', {
                      'view': window,
                      'bubbles': true,
                      'cancelable': true,
                      'clientX': x,
                      'clientY': y,
                      'buttons': 1  // 按下状态
                    });
                    targetElement.dispatchEvent(mousedownEvent);
                    
                    // 固定按压时间
                    const pressTime = MOUSE_PRESS_TIME_MS;
                    
                    // 持续按压一段时间后释放
                    setTimeout(() => {
                      // 创建并触发mouseup事件
                      const mouseupEvent = new MouseEvent('mouseup', {
                        'view': window,
                        'bubbles': true,
                        'cancelable': true,
                        'clientX': x,
                        'clientY': y,
                        'buttons': 0  // 释放状态
                      });
                      targetElement.dispatchEvent(mouseupEvent);
                      
                      // 创建并触发click事件
                      const clickEvent = new MouseEvent('click', {
                        'view': window,
                        'bubbles': true,
                        'cancelable': true,
                        'clientX': x,
                        'clientY': y
                      });
                      targetElement.dispatchEvent(clickEvent);
                      
                      // 如果目标是输入框，确保获得焦点
                      if (targetElement === searchInput) {
                        searchInput.focus();
                      }
                      
                      // 更新最后点击位置
                      lastX = x;
                      lastY = y;
                      
                      // 解析点击操作完成
                      clickResolve();
                    }, pressTime);
                    
                  } catch (e) {
                    console.log("点击操作出错: " + e);
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("点击操作出错: " + e);
                    }
                    clickResolve(); // 即使出错也继续流程
                  }
                });
              }
              
              // 获取输入框或输入框上方随机位置，并点击
              async function clickTarget(isInputBox) {
                try {
                  const pos = getInputPosition();
                  let targetX, targetY, elementDescription;
                  let targetElement = null;
                  
                  if (isInputBox) {
                    // 输入框内部位置 (居中位置)
                    targetX = pos.left + pos.width * 0.5;
                    targetY = pos.top + pos.height * 0.5;
                    elementDescription = "输入框";
                    
                    // 输入框肯定是有效元素
                    targetElement = searchInput;
                  } else {
                    // 输入框上方25px的固定位置
                    targetX = pos.left + pos.width * 0.5; // 输入框宽度中心
                    targetY = Math.max(pos.top - 25, 5); // 上方25px，确保不小于5px
                    elementDescription = "输入框上方空白处";
                    
                    // 尝试获取该位置的元素
                    targetElement = document.elementFromPoint(targetX, targetY);
                    
                    // 确保我们找到有效元素，如果没有则稍微调整位置
                    if (!targetElement) {
                      // 尝试向下移动一点
                      for (let attempt = 1; attempt <= 5; attempt++) {
                        // 每次往下移动2px
                        targetY += 2;
                        targetElement = document.elementFromPoint(targetX, targetY);
                        if (targetElement) break;
                      }
                      
                      // 如果仍然没找到，使用body
                      if (!targetElement) {
                        console.log("未在指定位置找到元素，使用body");
                        targetElement = document.body;
                      }
                    }
                  }
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击" + elementDescription);
                  }
                  
                  // 先移动鼠标到目标位置
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                  
                  // 短暂悬停
                  await simulateHover(targetElement, targetX, targetY);
                  
                  // 执行点击操作
                  await simulateClick(targetElement, targetX, targetY);
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击" + elementDescription + "完成");
                  }
                  
                  return true;
                } catch (e) {
                  console.log("点击操作出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击操作出错: " + e);
                  }
                  return false;
                }
              }
              
              // 填写搜索关键词
              async function fillSearchInput() {
                try {
                  // 先清空输入框
                  searchInput.value = '';
                  
                  // 填写整个关键词
                  searchInput.value = searchKeyword;
                  
                  // 触发input事件
                  const inputEvent = new Event('input', { bubbles: true, cancelable: true });
                  searchInput.dispatchEvent(inputEvent);
                  
                  // 触发change事件
                  const changeEvent = new Event('change', { bubbles: true, cancelable: true });
                  searchInput.dispatchEvent(changeEvent);
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword);
                  }
                  
                  return true;
                } catch (e) {
                  console.log("填写搜索关键词出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写搜索关键词出错: " + e);
                  }
                  return false;
                }
              }
              
              // 点击搜索按钮
              async function clickSearchButton() {
                try {
                  const form = document.getElementById('form1');
                  if (!form) {
                    console.log("未找到表单");
                    return false;
                  }
                  
                  // 查找提交按钮
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                  
                  if (!submitButton) {
                    console.log("未找到提交按钮，直接提交表单");
                    form.submit();
                    return true;
                  }
                  
                  // 获取按钮位置
                  const rect = submitButton.getBoundingClientRect();
                  
                  // 按钮内居中位置
                  const targetX = rect.left + rect.width * 0.5;
                  const targetY = rect.top + rect.height * 0.5;
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击搜索按钮");
                  }
                  
                  // 先移动鼠标到按钮位置
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                  
                  // 悬停在按钮上
                  await simulateHover(submitButton, targetX, targetY);
                  
                  // 执行点击操作
                  await simulateClick(submitButton, targetX, targetY);
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮完成");
                  }
                  
                  return true;
                } catch (e) {
                  console.log("点击搜索按钮出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮出错: " + e);
                  }
                  
                  // 出错时尝试直接提交表单
                  try {
                    const form = document.getElementById('form1');
                    if (form) form.submit();
                  } catch (e2) {
                    console.log("备用提交方式也失败: " + e2);
                  }
                  
                  return false;
                }
              }
              
              // 执行完整的模拟操作序列，使用固定延迟
              async function executeSequence() {
                try {
                  // 2. 点击输入框上方空白处
                  await clickTarget(false); // false表示点击输入框上方
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 3. 再次点击输入框并输入
                  await clickTarget(true);
                  await fillSearchInput();
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 4. 点击输入框上方空白处
                  await clickTarget(false);
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 5. 最后点击搜索按钮
                  await clickSearchButton();
                  
                  resolve(true);
                } catch (e) {
                  console.log("模拟序列执行出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("模拟序列执行出错: " + e);
                  }
                  resolve(false);
                }
              }
              
              // 开始执行模拟序列
              executeSequence();
            });
          }
          
          // 修改后的表单提交流程，直接使用模拟真人行为函数
          async function submitSearchForm() {
            console.log("准备提交搜索表单");
            
            const form = document.getElementById('form1'); // 所有引擎统一使用相同ID选择器
            const searchInput = document.getElementById('search'); // 所有引擎统一使用相同ID选择器
            
            if (!form || !searchInput) {
              console.log("未找到有效的表单元素");
              // 记录页面状态，方便调试
              console.log("表单数量: " + document.forms.length);
              for(let i = 0; i < document.forms.length; i++) {
                console.log("表单 #" + i + " ID: " + document.forms[i].id);
              }
              
              const inputs = document.querySelectorAll('input');
              console.log("输入框数量: " + inputs.length);
              for(let i = 0; i < inputs.length; i++) {
                console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
              }
              return false;
            }
            
            console.log("找到表单和输入框");
            
            // 执行模拟真人行为（包含所有所需步骤）
            try {
              console.log("开始模拟真人行为");
              const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);
              
              if (result) {
                console.log("模拟真人行为成功");
                
                // 通知Flutter表单已提交
                if (window.AppChannel) {
                  setTimeout(function() {
                    window.AppChannel.postMessage('FORM_SUBMITTED');
                  }, 300);
                }
                
                return true;
              } else {
                console.log("模拟真人行为失败，尝试常规提交");
                
                // 尝试常规提交方式
                try {
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                  if (submitButton) {
                    submitButton.click();
                  } else {
                    form.submit();
                  }
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_SUBMITTED');
                  }
                  
                  return true;
                } catch (e2) {
                  console.log("备用提交方式也失败: " + e2);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  }
                  return false;
                }
              }
            } catch (e) {
              console.log("模拟行为失败: " + e);
              
              // 即使模拟行为失败，我们也继续提交表单
              if (window.AppChannel) {
                window.AppChannel.postMessage('SIMULATION_FAILED');
              }
              
              // 尝试常规提交方式
              try {
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                if (submitButton) {
                  submitButton.click();
                } else {
                  form.submit();
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_SUBMITTED');
                }
                
                return true;
              } catch (e2) {
                console.log("备用提交方式也失败: " + e2);
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                }
                return false;
              }
            }
          }
          
          // 修改: 改进表单检测函数，确保更可靠的异步处理
          function checkFormElements() {
            // 检查表单元素
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            
            console.log("检查表单元素");
            
            if (form && searchInput) {
              console.log("找到表单元素!");
              window.__formCheckState.formFound = true;
              clearFormCheckInterval();
              
              // 使用立即执行的异步函数包装
              (async function() {
                try {
                  const result = await submitSearchForm();
                  if (result) {
                    console.log("表单处理成功");
                  } else {
                    console.log("表单处理失败");
                    
                    // 通知Flutter表单处理失败
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                    }
                  }
                } catch (e) {
                  console.log("表单提交异常: " + e);
                  
                  // 通知Flutter表单处理失败
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  }
                }
              })();
            }
          }
          
          // 开始定时检查
          clearFormCheckInterval(); // 清除可能存在的旧定时器
          window.__formCheckState.checkInterval = setInterval(checkFormElements, 500); // 每500ms检查一次
          console.log("开始定时检查表单元素");
          
          // 立即执行一次检查
          checkFormElements();
        })();
      ''');
      
      LogUtil.i('表单检测脚本注入成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    // 首先检查是否已取消，避免不必要的操作
    if (isCancelled()) {
      LogUtil.i('任务已取消，中断导航');
      cleanupResources();
      return;
    }
    
    LogUtil.i('页面开始加载: $pageUrl');
    
    // 检查是否已切换到备用引擎但尝试加载主引擎
    if (searchState['engineSwitched'] == true && 
        SousuoParser._isPrimaryEngine(pageUrl) && 
        controller != null) {
      LogUtil.i('已切换备用引擎，中断主引擎加载');
      try {
        await controller!.loadHtmlString('<html><body></body></html>');
      } catch (e) {
        LogUtil.e('中断主引擎加载时出错: $e');
      }
      return;
    }
    
    // 如果搜索尚未提交且不是空白页，注入表单检测脚本
    if (!searchState['searchSubmitted'] && pageUrl != 'about:blank') {
      await injectFormDetectionScript(searchState['searchKeyword']);
    }
  }
  
  /// 处理导航事件 - 页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理页面完成事件');
      cleanupResources();
      return;
    }
    
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = searchState['startTimeMs'] as int;
    final loadTimeMs = currentTimeMs - startMs;
    LogUtil.i('页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms');

    if (pageUrl == 'about:blank') {
      LogUtil.i('空白页面，忽略');
      return;
    }
    
    if (controller == null) {
      LogUtil.e('WebView控制器为空');
      return;
    }
    
    bool isPrimaryEngine = SousuoParser._isPrimaryEngine(pageUrl);
    bool isBackupEngine = SousuoParser._isBackupEngine(pageUrl);
    
    if (!isPrimaryEngine && !isBackupEngine) {
      LogUtil.i('未知页面: $pageUrl');
      return;
    }
    
    if (searchState['engineSwitched'] == true && isPrimaryEngine) {
      LogUtil.i('已切换备用引擎，忽略主引擎');
      return;
    }
    
    if (isPrimaryEngine) {
      searchState['activeEngine'] = 'primary';
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) {
      searchState['activeEngine'] = 'backup';
      LogUtil.i('备用引擎页面加载完成');
    }
    
    if (searchState['searchSubmitted'] == true) {
      if (!isExtractionInProgress && !isTestingStarted && !_extractionTriggered) {
        Timer(Duration(milliseconds: 500), () {
          if (controller != null && !completer.isCompleted && !isCancelled()) {
            LogUtil.i('页面加载完成后主动尝试提取链接');
            handleContentChange();
          }
        });
      }
    }
  }
  
  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理资源错误');
      cleanupResources();
      return;
    }
    
    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}');
    
    // 忽略一些非关键资源的错误
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.webp') || 
        error.url!.endsWith('.css')) {
      return;
    }
    
    // 主引擎出现关键错误时切换到备用引擎
    if (searchState['activeEngine'] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) {
      
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode);
      
      if (isCriticalError) {
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState['primaryEngineLoadFailed'] = true;
        
        if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
          LogUtil.i('主引擎加载失败，切换备用引擎');
          switchToBackupEngine();
        }
      }
    }
  }
  
  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，阻止所有导航');
      return NavigationDecision.prevent;
    }
    
    // 如果已切换到备用引擎，阻止主引擎导航
    if (searchState['engineSwitched'] == true && SousuoParser._isPrimaryEngine(request.url)) {
      LogUtil.i('阻止主引擎导航');
      return NavigationDecision.prevent;
    }
    
    // 阻止加载非必要资源，提高性能
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
      return NavigationDecision.prevent;
    }
    
    return NavigationDecision.navigate;
  }
  
  /// 处理JavaScript消息
  void handleJavaScriptMessage(JavaScriptMessage message) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理JS消息');
      cleanupResources();
      return;
    }
    
    LogUtil.i('收到消息: ${message.message}');
    
    if (controller == null) {
      LogUtil.e('控制器为空，无法处理消息');
      return;
    }
    
    if (message.message.startsWith('点击输入框上方') || 
        message.message.startsWith('点击body') ||
        message.message.startsWith('点击了随机元素') ||
        message.message.startsWith('点击页面随机位置') ||
        message.message.startsWith('填写后点击')) {
    }
    else if (message.message == 'FORM_SUBMITTED') {
      LogUtil.i('表单已提交');
      searchState['searchSubmitted'] = true;
      
      searchState['stage'] = ParseStage.searchResults;
      searchState['stage2StartTime'] = DateTime.now().millisecondsSinceEpoch;
      
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel');
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      LogUtil.i('表单处理失败');
      
      if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
        LogUtil.i('主引擎表单处理失败，切换备用引擎');
        switchToBackupEngine();
      }
    } else if (message.message == 'SIMULATION_FAILED') {
      LogUtil.e('模拟真人行为失败');
    } else if (message.message.startsWith('模拟真人行为') ||
                message.message.startsWith('点击了搜索输入框') ||
                message.message.startsWith('填写了搜索关键词') ||
                message.message.startsWith('点击提交按钮')) {
    } else if (message.message == 'CONTENT_CHANGED') {
      LogUtil.i('页面内容变化');
      
      handleContentChange();
    }
  }
  
  /// 开始解析流程 - 优化异常处理和资源管理
  Future<String> startParsing(String url) async {
    try {
      if (isCancelled()) {
        LogUtil.i('任务已取消，不执行解析');
        return 'ERROR';
      }
      
      setupCancelListener();
      
      // 设置全局超时
      setupGlobalTimeout();
      
      LogUtil.i('从URL提取搜索关键词');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      LogUtil.i('提取到搜索关键词: $searchKeyword');
      searchState['searchKeyword'] = searchKeyword;
      
      LogUtil.i('创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      LogUtil.i('WebView控制器创建完成');
      
      LogUtil.i('设置WebView导航委托');
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: handlePageStarted,
        onPageFinished: handlePageFinished,
        onWebResourceError: handleWebResourceError,
        onNavigationRequest: handleNavigationRequest,
      ));
      
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: handleJavaScriptMessage,
      );
      LogUtil.i('JavaScript通道添加完成');
      
      try {
        LogUtil.i('开始加载页面: ${SousuoParser._primaryEngine}');
        await controller!.loadRequest(Uri.parse(SousuoParser._primaryEngine));
        LogUtil.i('页面加载请求已发出');
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e');
        
        if (searchState['engineSwitched'] == false) {
          LogUtil.i('主引擎加载失败，准备切换备用引擎');
          switchToBackupEngine();
        }
      }
      
      final result = await completer.future;
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);
      
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
        try {
          final result = await SousuoParser._testStreamsAndGetFastest(foundStreams, cancelToken: cancelToken);
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          return result;
        } catch (testError) {
          LogUtil.e('测试流时出错: $testError');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
          }
        }
      } else if (!completer.isCompleted) {
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!isResourceCleaned) {
        await cleanupResources();
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
  static const int _timeoutSeconds = 28; // 统一超时时间 - 适用于表单检测和DOM变化检测
  static const int _maxStreams = 8; // 最大提取的媒体流数量
  
  // 时间常量 - 页面和DOM相关
  static const int _waitSeconds = 2; // 页面加载和提交后等待时间
  static const int _domChangeWaitMs = 500; // DOM变化后等待时间
  
  // 时间常量 - 测试和清理相关
  static const int _flowTestWaitMs = 500; // 流测试等待时间
  static const int _backupEngineLoadWaitMs = 300; // 切换备用引擎前等待时间
  static const int _cleanupRetryWaitMs = 300; // 清理重试等待时间
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 5.0; // 显著内容变化百分比 - 从10%改为5%，提高敏感度
  
  // 内容变化防抖时间(毫秒)
  static const int _contentChangeDebounceMs = 300;

  // 添加屏蔽关键词列表
  static List<String> _blockKeywords = ["freetv.fun", "itvapp"];

  // 优化：预编译正则表达式，避免频繁创建
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false
  );

  /// 设置屏蔽关键词的方法
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      LogUtil.i('设置屏蔽关键词: ${_blockKeywords.join(', ')}');
    } else {
      _blockKeywords = [];
    }
  }

  /// 清理WebView资源 - 优化版，确保异常处理
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
      LogUtil.i('清理WebView完成');
    } catch (e) {
      LogUtil.e('清理WebView出错: $e');
      // 继续执行，不抛出异常，确保清理过程不会中断
    }
  }
  
  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 注入DOM变化监听器 - 优化实现，减少页面性能开销
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          
          // 获取初始内容长度
          const initialContentLength = document.body.innerHTML.length;
          console.log("初始内容长度: " + initialContentLength);
          
          // 跟踪状态
          let lastNotificationTime = Date.now();
          let lastContentLength = initialContentLength;
          let debounceTimeout = null;
          
          // 优化的内容变化通知函数 - 使用防抖动减少不必要的通知
          const notifyContentChange = function() {
            if (debounceTimeout) {
              clearTimeout(debounceTimeout);
            }
            
            debounceTimeout = setTimeout(function() {
              const now = Date.now();
              // 检查距离上次通知的时间是否足够长
              if (now - lastNotificationTime < 1000) {
                return; // 忽略过于频繁的通知
              }
              
              // 获取当前内容长度
              const currentContentLength = document.body.innerHTML.length;
              
              // 计算内容变化百分比
              const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;
              
              // 只有变化超过阈值时才通知
              if (changePercent > ${_significantChangePercent}) {
                console.log("检测到显著内容变化: " + changePercent.toFixed(2) + "%");
                
                // 更新状态
                lastNotificationTime = now;
                lastContentLength = currentContentLength;
                
                // 通知应用内容变化
                ${channelName}.postMessage('CONTENT_CHANGED');
              }
              
              debounceTimeout = null;
            }, 200); // 200ms防抖动延迟
          };
          
          // 创建性能优化的MutationObserver
          const observer = new MutationObserver(function(mutations) {
            // 快速检查是否有相关变化
            let hasRelevantChanges = false;
            
            // 只检查有意义的变化
            for (let i = 0; i < mutations.length; i++) {
              const mutation = mutations[i];
              
              // 检查是否为内容或结构变化
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                // 检查添加的节点是否包含实质性内容
                for (let j = 0; j < mutation.addedNodes.length; j++) {
                  const node = mutation.addedNodes[j];
                  if (node.nodeType === 1 && (node.tagName === 'DIV' || 
                                              node.tagName === 'TABLE' || 
                                              node.tagName === 'UL' || 
                                              node.tagName === 'IFRAME')) {
                    hasRelevantChanges = true;
                    break;
                  }
                }
                
                if (hasRelevantChanges) break;
              }
            }
            
            // 只有检测到相关变化时才触发通知
            if (hasRelevantChanges) {
              notifyContentChange();
            }
          });
          
          // 配置观察者 - 只观察必要的变化
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: false,
            characterData: false
          });
          
          // 页面加载后延迟检查一次内容
          setTimeout(function() {
            const currentContentLength = document.body.innerHTML.length;
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            console.log("延迟检查内容变化百分比: " + contentChangePct.toFixed(2) + "%");
            
            if (contentChangePct > ${_significantChangePercent}) {
              console.log("延迟检测到显著内容变化");
              ${channelName}.postMessage('CONTENT_CHANGED');
              lastContentLength = currentContentLength;
              lastNotificationTime = Date.now();
            }
          }, 1000);
        })();
      ''');
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
     await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面	
    try {
      final submitScript = '''
        (function() {
          console.log("查找搜索表单元素");
          
          const form = document.getElementById('form1'); // 查找表单
          const searchInput = document.getElementById('search'); // 查找输入框
          const submitButton = document.querySelector('input[name="Submit"]'); // 查找提交按钮
          
          if (!searchInput || !form) {
            console.log("未找到表单元素");
            console.log("表单数量: " + document.forms.length);
            for(let i = 0; i < document.forms.length; i++) {
              console.log("表单 #" + i + " ID: " + document.forms[i].id);
            }
            
            const inputs = document.querySelectorAll('input');
            console.log("输入框数量: " + inputs.length);
            for(let i = 0; i < inputs.length; i++) {
              console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
            }
            
            return false;
          }
          
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}"; // 填写关键词
          console.log("填写关键词: " + searchInput.value);
          
          if (submitButton) {
            console.log("点击提交按钮");
            submitButton.click();
            return true;
          } else {
            console.log("未找到提交按钮，尝试其他方法");
            
            const otherSubmitButton = form.querySelector('input[type="submit"]'); // 查找其他提交按钮
            if (otherSubmitButton) {
              console.log("找到submit按钮，点击");
              otherSubmitButton.click();
              return true;
            } else {
              console.log("直接提交表单");
              form.submit();
              return true;
            }
          }
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(submitScript); // 执行提交脚本
      
      await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面
      LogUtil.i('等待响应 (${_waitSeconds}秒)');
      
      return result.toString().toLowerCase() == 'true'; // 返回提交结果
    } catch (e, stackTrace) {
      LogUtil.logError('提交表单出错', e, stackTrace);
      return false;
    }
  }

  /// 检查URL是否包含屏蔽关键词
  static bool _isUrlBlocked(String url) {
    if (_blockKeywords.isEmpty) return false;
    
    final lowerUrl = url.toLowerCase();
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase()));
  }

  /// 提取媒体链接 - 优化版本，更高效的HTML解析和链接提取
  static Future<void> _extractMediaLinks(
    WebViewController controller, 
    List<String> foundStreams, 
    bool usingBackupEngine, 
    {int lastProcessedLength = 0}
  ) async {
    LogUtil.i('从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
    
    try {
      // 获取页面HTML
      final html = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML'
      );
      
      // 处理HTML字符串
      String htmlContent = html.toString();
      final int contentLength = htmlContent.length;
      LogUtil.i('获取HTML，长度: $contentLength');
      
      // 仅当HTML内容有实质变化时才进行处理
      if (lastProcessedLength > 0 && contentLength <= lastProcessedLength) {
        LogUtil.i('内容长度未增加，跳过提取');
        return;
      }
      
      // 清理HTML字符串
      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                  .replaceAll('\\"', '"')
                  .replaceAll('\\n', '\n');
      }
      
      // 使用预编译的正则表达式提取链接
      final matches = _mediaLinkRegex.allMatches(htmlContent);
      final int totalMatches = matches.length;
      
      // 如果有匹配项，记录示例
      String matchSample = "";
      if (totalMatches > 0) {
        final firstMatch = matches.first;
        matchSample = "示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(1)}";
        LogUtil.i(matchSample);
      }
      
      // 优化: 使用集合记录已存在的主机，避免重复链接
      final Set<String> hostSet = {};
      
      // 从已有流中提取主机信息
      for (final url in foundStreams) {
        try {
          final uri = Uri.parse(url);
          hostSet.add('${uri.host}:${uri.port}');
        } catch (_) {
          // 处理无效URL
          hostSet.add(url);
        }
      }
      
      // 分类存储链接
      final List<String> m3u8Links = [];
      final List<String> otherLinks = [];
      
      // 处理匹配的URL
      for (final match in matches) {
        if (match.groupCount >= 1) {
          String? mediaUrl = match.group(1)?.trim();
          
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            // 一次性清理URL
            mediaUrl = mediaUrl
                .replaceAll('&amp;', '&')
                .replaceAll('&quot;', '"')
                .replaceAll(RegExp("[\")'&;]+\$"), '');
            
            // 检查URL是否包含屏蔽关键词
            if (_isUrlBlocked(mediaUrl)) {
              LogUtil.i('跳过包含屏蔽关键词的链接: $mediaUrl');
              continue;
            }
            
            try {
              final uri = Uri.parse(mediaUrl);
              final String hostKey = '${uri.host}:${uri.port}';
              
              // 检查是否已添加来自同一主机的链接
              if (!hostSet.contains(hostKey)) {
                hostSet.add(hostKey);
                
                // 按格式分类
                if (mediaUrl.toLowerCase().contains('.m3u8')) {
                  m3u8Links.add(mediaUrl);
                  LogUtil.i('提取到m3u8链接: $mediaUrl');
                } else {
                  otherLinks.add(mediaUrl);
                  LogUtil.i('提取到其他格式链接: $mediaUrl');
                }
              }
            } catch (e) {
              LogUtil.e('解析URL出错: $e, URL: $mediaUrl');
            }
          }
        }
      }
      
      // 优先添加m3u8链接，再添加其他链接
      int addedCount = 0;
      
      // 计算可添加的最大数量
      final int remainingSlots = _maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达到最大链接数 $_maxStreams，不添加新链接');
        return;
      }
      
      // 添加m3u8链接
      for (final link in m3u8Links) {
        foundStreams.add(link);
        addedCount++;
        
        if (foundStreams.length >= _maxStreams) {
          LogUtil.i('达到最大链接数 $_maxStreams，m3u8链接已足够');
          break;
        }
      }
      
      // 如果m3u8链接不足，添加其他链接
      if (foundStreams.length < _maxStreams) {
        for (final link in otherLinks) {
          foundStreams.add(link);
          addedCount++;
          
          if (foundStreams.length >= _maxStreams) {
            LogUtil.i('达到最大链接数 $_maxStreams');
            break;
          }
        }
      }
      
      // 输出汇总信息
      LogUtil.i('匹配数: $totalMatches, m3u8格式: ${m3u8Links.length}, 其他格式: ${otherLinks.length}, 新增: $addedCount');
      
      // 调试输出
      if (addedCount == 0 && totalMatches == 0) {
        // 记录HTML片段和onclick属性
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
        String debugSample = htmlContent.substring(0, sampleLength);
        
        // 尝试找出所有onclick属性
        final onclickRegex = RegExp('onclick="[^"]+"', caseSensitive: false);
        final onclickMatches = onclickRegex.allMatches(htmlContent).take(3).map((m) => m.group(0)).join(', ');
        
        LogUtil.i('无链接，HTML片段: $debugSample');
        if (onclickMatches.isNotEmpty) {
          LogUtil.i('页面中的onclick样本: $onclickMatches');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取链接出错', e, stackTrace);
    }
    
    LogUtil.i('提取完成，链接数: ${foundStreams.length}');
  }
  
  /// 测试流地址并返回最快有效地址 - 优化版，改进资源管理和错误处理
  static Future<String> _testStreamsAndGetFastest(List<String> streams, {CancelToken? cancelToken}) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR';
    }
    
    LogUtil.i('测试 ${streams.length} 个流地址');
    
    // 创建独立的测试取消令牌和完成器
    final testCancelToken = cancelToken ?? CancelToken();
    final completer = Completer<String>();
    bool hasValidResponse = false;
    
    // 设置测试超时计时器
    final testTimeoutTimer = Timer(Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        LogUtil.i('流测试超时，取消所有进行中的请求');
        if (!testCancelToken.isCancelled) {
          testCancelToken.cancel('测试超时');
        }
        if (!hasValidResponse) {
          completer.complete('ERROR');
        }
      }
    });
    
    // 创建测试任务
    final tasks = streams.map((streamUrl) async {
      try {
        // 避免无效测试
        if (completer.isCompleted || testCancelToken.isCancelled) return;
        
        // 测试流
        final stopwatch = Stopwatch()..start();
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'GET',
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
          cancelToken: testCancelToken,
          retryCount: 1,
        );
        
        // 处理成功响应
        if (response != null && !completer.isCompleted && !testCancelToken.isCancelled) {
          final responseTime = stopwatch.elapsedMilliseconds;
          LogUtil.i('流 $streamUrl 响应: ${responseTime}ms');
          
          hasValidResponse = true;
          
          // 找到可用流后，取消其他测试请求
          if (!testCancelToken.isCancelled) {
            LogUtil.i('找到可用流，取消其他测试请求');
            testCancelToken.cancel('找到可用流');
          }
          
          // 返回此有效流
          completer.complete(streamUrl);
        }
      } catch (e) {
        // 区分取消错误和其他错误
        if (testCancelToken.isCancelled) {
          LogUtil.i('测试已取消: $streamUrl');
        } else {
          LogUtil.e('测试 $streamUrl 出错: $e');
        }
      }
    }).toList();
    
    try {
      // 并行执行所有测试
      await Future.wait(tasks);
      
      // 如果没有成功响应，返回ERROR
      if (!completer.isCompleted) {
        LogUtil.i('所有流测试完成但未找到可用流');
        completer.complete('ERROR');
      }
      
      return await completer.future;
    } finally {
      // 确保计时器被取消
      testTimeoutTimer.cancel();
      LogUtil.i('流测试完成，清理资源');
    }
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    // 设置屏蔽关键词
    if (blockKeywords.isNotEmpty) {
      setBlockKeywords(blockKeywords);
    }
    
    // 创建解析会话并开始解析
    final session = _ParserSession(cancelToken: cancelToken);
    return await session.startParsing(url);
  }
}
