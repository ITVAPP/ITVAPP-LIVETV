import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 定义解析阶段枚举，描述解析流程的状态
enum ParseStage {
  formSubmission,  // 页面加载和表单提交阶段
  searchResults,   // 搜索结果处理和流测试阶段
  completed,       // 解析完成
  error            // 解析出错
}

/// 解析会话类，管理解析逻辑和状态
class _ParserSession {
  final Completer<String> completer = Completer<String>(); // 异步任务完成器
  final List<String> foundStreams = []; // 存储提取的流地址
  WebViewController? controller; // WebView控制器
  Timer? contentChangeDebounceTimer; // 内容变化防抖计时器
  
  // 状态标记
  bool isResourceCleaned = false; // 资源是否已清理
  bool isTestingStarted = false; // 是否已开始测试流
  bool isExtractionInProgress = false; // 是否正在提取链接
  
  bool extractionTriggered = false; // 提取操作是否已触发
  
  bool isCollectionFinished = false; // 是否完成链接收集
  Timer? noMoreChangesTimer; // 无变化检测计时器
  
  // 搜索状态管理
  final Map<String, dynamic> searchState = {
    'searchKeyword': '', // 搜索关键词
    'activeEngine': 'primary', // 当前使用的引擎
    'searchSubmitted': false, // 是否已提交搜索
    'startTimeMs': DateTime.now().millisecondsSinceEpoch, // 解析开始时间
    'engineSwitched': false, // 是否切换到备用引擎
    'primaryEngineLoadFailed': false, // 主引擎是否加载失败
    'lastHtmlLength': 0, // 上次处理的HTML长度
    'extractionCount': 0, // 提取次数
    'stage': ParseStage.formSubmission, // 当前解析阶段
    'stage1StartTime': DateTime.now().millisecondsSinceEpoch, // 阶段1开始时间
    'stage2StartTime': 0, // 阶段2开始时间
  };
  
  Timer? globalTimeoutTimer; // 全局超时计时器
  StreamSubscription? cancelListener; // 取消操作监听器
  final CancelToken? cancelToken; // 取消令牌
  
  _ParserSession({this.cancelToken});
  
  /// 检查是否取消任务并处理
  bool _checkCancelledAndHandle(String context, {bool completeWithError = true}) {
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，$context');
      if (completeWithError && !completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return true;
    }
    return false;
  }
  
  /// 设置取消操作监听器
  void setupCancelListener() {
    if (cancelToken != null) {
      cancelToken!.whenCancel.then((_) {
        LogUtil.i('检测到取消信号，释放资源');
        cleanupResources(immediate: true);
      });
    }
  }
  
  /// 设置全局超时计时器
  void setupGlobalTimeout() {
    globalTimeoutTimer?.cancel();
    globalTimeoutTimer = Timer(Duration(seconds: SousuoParser._timeoutSeconds), () {
      LogUtil.i('全局超时触发');
      if (_checkCancelledAndHandle('不处理全局超时')) return;
      if (!isCollectionFinished && foundStreams.isNotEmpty) {
        LogUtil.i('超时，强制测试 ${foundStreams.length} 个流');
        finishCollectionAndTest();
      } else if (searchState['activeEngine'] == 'primary' && !searchState['engineSwitched']) {
        LogUtil.i('主引擎超时，切换备用引擎');
        switchToBackupEngine();
      } else {
        LogUtil.i('无可用流，返回错误');
        if (!completer.isCompleted) {
          completer.complete('ERROR');
          cleanupResources();
        }
      }
    });
  }
  
  /// 完成链接收集并开始测试
  void finishCollectionAndTest() {
    if (isCollectionFinished || isTestingStarted) return;
    isCollectionFinished = true;
    LogUtil.i('收集完成，测试 ${foundStreams.length} 个流');
    noMoreChangesTimer?.cancel();
    noMoreChangesTimer = null;
    startStreamTesting();
  }
  
  /// 设置无变化检测计时器
  void setupNoMoreChangesDetection() {
    noMoreChangesTimer?.cancel();
    noMoreChangesTimer = Timer(Duration(seconds: 3), () {
      if (!isCollectionFinished && foundStreams.isNotEmpty) {
        LogUtil.i('3秒无变化，结束收集');
        finishCollectionAndTest();
      }
    });
  }
  
  /// 清理所有资源
  Future<void> cleanupResources({bool immediate = false}) async {
    if (isResourceCleaned) {
      LogUtil.i('资源已清理，跳过');
      return;
    }
    isResourceCleaned = true;
    _cancelTimer(globalTimeoutTimer, '全局超时计时器');
    globalTimeoutTimer = null;
    _cancelTimer(contentChangeDebounceTimer, '内容变化防抖计时器');
    contentChangeDebounceTimer = null;
    _cancelTimer(noMoreChangesTimer, '无变化检测计时器');
    noMoreChangesTimer = null;
    if (cancelListener != null) {
      try {
        await cancelListener!.cancel();
        LogUtil.i('取消监听器已清理');
      } catch (e) {
        LogUtil.e('取消监听器出错: $e');
      } finally {
        cancelListener = null;
      }
    }
    if (controller != null) {
      final tempController = controller;
      controller = null;
      try {
        await tempController!.loadHtmlString('<html><body></body></html>');
        if (!immediate) {
          await Future.delayed(Duration(milliseconds: 100));
          await SousuoParser._disposeWebView(tempController);
        }
        LogUtil.i('WebView控制器已清理');
      } catch (e) {
        LogUtil.e('清理WebView出错: $e');
      }
    }
    if (!completer.isCompleted) {
      LogUtil.i('Completer未完成，返回ERROR');
      completer.complete('ERROR');
    }
    LogUtil.i('资源清理完成');
  }
  
  /// 统一取消计时器
  void _cancelTimer(Timer? timer, String timerName) {
    if (timer != null) {
      try {
        timer.cancel();
        LogUtil.i('$timerName已取消');
      } catch (e) {
        LogUtil.e('取消$timerName出错: $e');
      }
    }
  }
  
  /// 执行异步操作并统一处理错误
  Future<void> _executeAsyncOperation(
    String operationName,
    Future<void> Function() operation,
    {Function? onError}
  ) async {
    try {
      if (_checkCancelledAndHandle('不执行$operationName', completeWithError: false)) return;
      await operation();
    } catch (e) {
      LogUtil.e('$operationName出错: $e');
      if (onError != null) {
        onError();
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }
  
  /// 开始测试流链接
  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('已开始测试，忽略重复请求');
      return;
    }
    if (foundStreams.isEmpty) {
      LogUtil.i('无流链接，返回ERROR');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }
    isTestingStarted = true;
    LogUtil.i('测试 ${foundStreams.length} 个流');
    final testCancelToken = CancelToken();
    StreamSubscription? testCancelListener;
    if (cancelToken != null) {
      testCancelListener = cancelToken?.whenCancel.asStream().listen((_) {
        if (!testCancelToken.isCancelled) {
          LogUtil.i('父级取消，取消测试');
          testCancelToken.cancel('父级取消');
        }
      });
    }
    _testStreamsAsync(testCancelToken, testCancelListener);
  }
  
  /// 异步测试流链接
  Future<void> _testStreamsAsync(CancelToken testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      final result = await SousuoParser._testStreamsAndGetFastest(foundStreams, cancelToken: testCancelToken);
      LogUtil.i('测试完成: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      if (!completer.isCompleted) {
        completer.complete(result);
        cleanupResources();
      }
    } catch (e) {
      LogUtil.e('测试流出错: $e');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    } finally {
      try {
        await testCancelListener?.cancel();
      } catch (e) {
        LogUtil.e('取消测试监听器出错: $e');
      }
    }
  }
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState['engineSwitched']) {
      LogUtil.i('已切换备用引擎，忽略');
      return;
    }
    await _executeAsyncOperation('切换备用引擎', () async {
      LogUtil.i('主引擎不可用，切换备用引擎');
      searchState['activeEngine'] = 'backup';
      searchState['engineSwitched'] = true;
      searchState['searchSubmitted'] = false;
      searchState['lastHtmlLength'] = 0;
      searchState['extractionCount'] = 0;
      searchState['stage'] = ParseStage.formSubmission;
      searchState['stage1StartTime'] = DateTime.now().millisecondsSinceEpoch;
      extractionTriggered = false;
      isCollectionFinished = false;
      noMoreChangesTimer?.cancel();
      noMoreChangesTimer = null;
      globalTimeoutTimer?.cancel();
      if (controller != null) {
        await controller!.loadHtmlString('<html><body></body></html>');
        await Future.delayed(Duration(milliseconds: SousuoParser._backupEngineLoadWaitMs));
        await controller!.loadRequest(Uri.parse(SousuoParser._backupEngine));
        LogUtil.i('加载备用引擎: ${SousuoParser._backupEngine}');
        setupGlobalTimeout();
      } else {
        LogUtil.e('WebView控制器为空');
        throw Exception('WebView控制器为空');
      }
    });
  }
  
  /// 处理内容变化，提取链接
  void handleContentChange() {
    contentChangeDebounceTimer?.cancel();
    if (_checkCancelledAndHandle('停止内容变化', completeWithError: false)) return;
    if (isCollectionFinished || isTestingStarted) {
      LogUtil.i('已完成收集或测试，跳过');
      return;
    }
    if (isExtractionInProgress) {
      LogUtil.i('提取进行中，跳过');
      return;
    }
    if (extractionTriggered) {
      LogUtil.i('已触发提取，跳过');
      return;
    }
    contentChangeDebounceTimer = Timer(Duration(milliseconds: SousuoParser._contentChangeDebounceMs), () async {
      if (controller == null || completer.isCompleted || _checkCancelledAndHandle('取消内容处理', completeWithError: false)) return;
      if (isCollectionFinished || isTestingStarted) {
        LogUtil.i('延迟期间已完成收集或测试，取消');
        return;
      }
      isExtractionInProgress = true;
      try {
        if (searchState['searchSubmitted'] && !completer.isCompleted && !isTestingStarted) {
          extractionTriggered = true;
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
            LogUtil.e('获取HTML长度出错: $e');
          }
          searchState['extractionCount'] += 1;
          int afterExtractCount = foundStreams.length;
          if (afterExtractCount > beforeExtractCount) {
            LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接，总数: $afterExtractCount');
            extractionTriggered = false;
            setupNoMoreChangesDetection();
            if (afterExtractCount >= SousuoParser._maxStreams) {
              LogUtil.i('达到最大链接数 ${SousuoParser._maxStreams}，结束收集');
              finishCollectionAndTest();
            }
          } else if (searchState['activeEngine'] == 'primary' && 
                     afterExtractCount == 0 && 
                     !searchState['engineSwitched']) {
            extractionTriggered = false;
            LogUtil.i('主引擎无链接，切换备用引擎');
            switchToBackupEngine();
          } else {
            extractionTriggered = false;
            if (afterExtractCount > 0) {
              setupNoMoreChangesDetection();
            }
          }
        }
      } catch (e) {
        LogUtil.e('处理内容变化出错: $e');
      } finally {
        isExtractionInProgress = false;
      }
    });
  }
  
  /// 注入表单检测脚本，模拟用户操作
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return;
    try {
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      await controller!.runJavaScript('''
        (function() {
          console.log("开始注入表单检测脚本");
          window.__formCheckState = {
            formFound: false,
            checkInterval: null,
            searchKeyword: "$escapedKeyword"
          };
          function clearFormCheckInterval() {
            if (window.__formCheckState.checkInterval) {
              clearInterval(window.__formCheckState.checkInterval);
              window.__formCheckState.checkInterval = null;
              console.log("停止表单检测");
            }
          }
          const MOUSE_MOVEMENT_STEPS = 5;
          const MOUSE_MOVEMENT_OFFSET = 8;
          const MOUSE_MOVEMENT_DELAY_MS = 50;
          const MOUSE_HOVER_TIME_MS = 300;
          const MOUSE_PRESS_TIME_MS = 200;
          const ACTION_DELAY_MS = 1000;
          async function simulateHumanBehavior(searchKeyword) {
            if (window.AppChannel) window.AppChannel.postMessage('开始模拟真人行为');
            const searchInput = document.getElementById('search');
            if (!searchInput) {
              console.log("未找到搜索输入框");
              if (window.AppChannel) window.AppChannel.postMessage("未找到搜索输入框");
              return false;
            }
            let lastX = window.innerWidth / 2;
            let lastY = window.innerHeight / 2;
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
            async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
              const steps = MOUSE_MOVEMENT_STEPS;
              if (window.AppChannel) window.AppChannel.postMessage("开始移动鼠标");
              for (let i = 0; i < steps; i++) {
                const progress = i / steps;
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
                await new Promise(r => setTimeout(r, MOUSE_MOVEMENT_DELAY_MS));
              }
              if (window.AppChannel) window.AppChannel.postMessage("完成鼠标移动");
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
                  });
                  targetElement.dispatchEvent(mouseoverEvent);
                  setTimeout(() => hoverResolve(), MOUSE_HOVER_TIME_MS);
                } catch (e) {
                  console.log("悬停出错: " + e);
                  hoverResolve();
                }
              });
            }
            async function simulateClick(targetElement, x, y) {
              returnandial new Promise((clickResolve) => {
                try {
                  const mousedownEvent = new MouseEvent('mousedown', {
                    'view': window,
                    'bubbles': true,
                    'cancelable': true,
                    'clientX': x,
                    'clientY': y,
                    'buttons': 1
                  });
                  targetElement.dispatchEvent(mousedownEvent);
                  setTimeout(() => {
                    const mouseupEvent = new MouseEvent('mouseup', {
                      'view': window,
                      'bubbles': true,
                      'cancelable': true,
                      'clientX': x,
                      'clientY': y,
                      'buttons': 0
                    });
                    targetElement.dispatchEvent(mouseupEvent);
                    const clickEvent = new MouseEvent('click', {
                      'view': window,
                      'bubbles': true,
                      'cancelable': true,
                      'clientX': x,
                      'clientY': y
                    });
                    targetElement.dispatchEvent(clickEvent);
                    if (targetElement === searchInput) searchInput.focus();
                    lastX = x;
                    lastY = y;
                    clickResolve();
                  }, MOUSE_PRESS_TIME_MS);
                } catch (e) {
                  console.log("点击出错: " + e);
                  if (window.AppChannel) window.AppChannel.postMessage("点击出错: " + e);
                  clickResolve();
                }
              });
            }
            async function clickTarget(isInputBox) {
              try {
                const pos = getInputPosition();
                let targetX, targetY, elementDescription;
                let targetElement = null;
                if (isInputBox) {
                  targetX = pos.left + pos.width * 0.5;
                  targetY = pos.top + pos.height * 0.5;
                  elementDescription = "输入框";
                  targetElement = searchInput;
                } else {
                  targetX = pos.left + pos.width * 0.5;
                  targetY = Math.max(pos.top - 25, 5);
                  elementDescription = "输入框上方空白处";
                  targetElement = document.elementFromPoint(targetX, targetY);
                  if (!targetElement) {
                    for (let attempt = 1; attempt <= 5; attempt++) {
                      targetY += 2;
                      targetElement = document.elementFromPoint(targetX, targetY);
                      if (targetElement) break;
                    }
                    if (!targetElement) {
                      console.log("未找到元素，使用body");
                      targetElement = document.body;
                    }
                  }
                }
                if (window.AppChannel) window.AppChannel.postMessage("准备点击" + elementDescription);
                await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                await simulateHover(targetElement, targetX, targetY);
                await simulateClick(targetElement, targetX, targetY);
                if (window.AppChannel) window.AppChannel.postMessage("点击" + elementDescription + "完成");
                return true;
              } catch (e) {
                console.log("点击出错: " + e);
                if (window.AppChannel) window.AppChannel.postMessage("点击出错: " + e);
                return false;
              }
            }
            async function fillSearchInput() {
              try {
                searchInput.value = '';
                searchInput.value = searchKeyword;
                const inputEvent = new Event('input', { bubbles: true, cancelable: true });
                searchInput.dispatchEvent(inputEvent);
                const changeEvent = new Event('change', { bubbles: true, cancelable: true });
                searchInput.dispatchEvent(changeEvent);
                if (window.AppChannel) window.AppChannel.postMessage("填写关键词: " + searchKeyword);
                return true;
              } catch (e) {
                console.log("填写关键词出错: " + e);
                if (window.AppChannel) window.AppChannel.postMessage("填写关键词出错: " + e);
                return false;
              }
            }
            async function clickSearchButton() {
              try {
                const form = document.getElementById('form1');
                if (!form) {
                  console.log("未找到表单");
                  return false;
                }
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                if (!submitButton) {
                  console.log("未找到提交按钮，提交表单");
                  form.submit();
                  return true;
                }
                const rect = submitButton.getBoundingClientRect();
                const targetX = rect.left + rect.width * 0.5;
                const targetY = rect.top + rect.height * 0.5;
                if (window.AppChannel) window.AppChannel.postMessage("准备点击搜索按钮");
                await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                await simulateHover(submitButton, targetX, targetY);
                await simulateClick(submitButton, targetX, targetY);
                if (window.AppChannel) window.AppChannel.postMessage("点击搜索按钮完成");
                return true;
              } catch (e) {
                console.log("点击按钮出错: " + e);
                if (window.AppChannel) window.AppChannel.postMessage("点击按钮出错: " + e);
                try {
                  const form = document.getElementById('form1');
                  if (form) form.submit();
                } catch (e2) {
                  console.log("备用提交失败: " + e2);
                }
                return false;
              }
            }
            async function executeSequence() {
              try {
                await clickTarget(true);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                await clickTarget(false);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                await clickTarget(true);
                await fillSearchInput();
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                await clickTarget(false);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                await clickSearchButton();
                resolve(true);
              } catch (e) {
                console.log("模拟序列出错: " + e);
                if (window.AppChannel) window.AppChannel.postMessage("模拟序列出错: " + e);
                resolve(false);
              }
            }
            executeSequence();
          }
          async function submitSearchForm() {
            console.log("准备提交搜索表单");
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            if (!form || !searchInput) {
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
            console.log("找到表单和输入框");
            try {
              console.log("开始模拟真人行为");
              const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);
              if (result) {
                console.log("模拟行为成功");
                if (window.AppChannel) {
                  setTimeout(function() {
                    window.AppChannel.postMessage('FORM_SUBMITTED');
                  }, 300);
                }
                return true;
              } else {
                console.log("模拟行为失败，常规提交");
                try {
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                  if (submitButton) {
                    submitButton.click();
                  } else {
                    form.submit();
                  }
                  if (window.AppChannel) window.AppChannel.postMessage('FORM_SUBMITTED');
                  return true;
                } catch (e2) {
                  console.log("备用提交失败: " + e2);
                  if (window.AppChannel) window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  return false;
                }
              }
            } catch (e) {
              console.log("模拟行为失败: " + e);
              if (window.AppChannel) window.AppChannel.postMessage('SIMULATION_FAILED');
              try {
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                if (submitButton) {
                  submitButton.click();
                } else {
                  form.submit();
                }
                if (window.AppChannel) window.AppChannel.postMessage('FORM_SUBMITTED');
                return true;
              } catch (e2) {
                console.log("备用提交失败: " + e2);
                if (window.AppChannel) window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                return false;
              }
            }
          }
          function checkFormElements() {
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            console.log("检查表单元素");
            if (form && searchInput) {
              console.log("找到表单元素!");
              window.__formCheckState.formFound = true;
              clearFormCheckInterval();
              (async function() {
                try {
                  const result = await submitSearchForm();
                  if (result) {
                    console.log("表单处理成功");
                  } else {
                    console.log("表单处理失败");
                    if (window.AppChannel) window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  }
                } catch (e) {
                  console.log("表单提交异常: " + e);
                  if (window.AppChannel) window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                }
              })();
            }
          }
          clearFormCheckInterval();
          window.__formCheckState.checkInterval = setInterval(checkFormElements, 500);
          console.log("开始定时检查表单元素");
          checkFormElements();
        })();
      ''');
      LogUtil.i('表单检测脚本注入成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 处理页面开始加载事件
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('中断导航', completeWithError: false)) return;
    if (searchState['engineSwitched'] && SousuoParser._isPrimaryEngine(pageUrl) && controller != null) {
      LogUtil.i('已切换备用引擎，中断主引擎加载');
      try {
        await controller!.loadHtmlString('<html><body></body></html>');
      } catch (e) {
        LogUtil.e('中断主引擎加载出错: $e');
      }
      return;
    }
    if (!searchState['searchSubmitted'] && pageUrl != 'about:blank') {
      await injectFormDetectionScript(searchState['searchKeyword']);
    }
  }
  
  /// 处理页面加载完成事件
  Future<void> handlePageFinished(String pageUrl) async {
    if (_checkCancelledAndHandle('不处理页面完成', completeWithError: false)) return;
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
    if (searchState['engineSwitched'] && isPrimaryEngine) {
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
    if (searchState['searchSubmitted']) {
      if (!isExtractionInProgress && !isTestingStarted && !extractionTriggered && !isCollectionFinished) {
        Timer(Duration(milliseconds: 500), () {
          if (controller != null && !completer.isCompleted && !cancelToken!.isCancelled && !isCollectionFinished) {
            handleContentChange();
          }
        });
      }
    }
  }
  
  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (_checkCancelledAndHandle('不处理资源错误', completeWithError: false)) return;
    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}');
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.webp') || 
        error.url!.endsWith('.css')) {
      return;
    }
    if (searchState['activeEngine'] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) {
      bool isCriticalError = [-1, -2, -3, -6, -7, -101, -105, -106].contains(error.errorCode);
      if (isCriticalError) {
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState['primaryEngineLoadFailed'] = true;
        if (!searchState['searchSubmitted'] && !searchState['engineSwitched']) {
          LogUtil.i('主引擎加载失败，切换备用引擎');
          switchToBackupEngine();
        }
      }
    }
  }
  
  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (_checkCancelledAndHandle('阻止导航', completeWithError: false)) {
      return NavigationDecision.prevent;
    }
    if (searchState['engineSwitched'] && SousuoParser._isPrimaryEngine(request.url)) {
      LogUtil.i('阻止主引擎导航');
      return NavigationDecision.prevent;
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
      LogUtil.i('阻止非必要资源: ${request.url}');
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }
  
  /// 处理JavaScript消息
  void handleJavaScriptMessage(JavaScriptMessage message) {
    if (_checkCancelledAndHandle('不处理JS消息', completeWithError: false)) return;
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
    } else if (message.message == 'FORM_SUBMITTED') {
      searchState['searchSubmitted'] = true;
      searchState['stage'] = ParseStage.searchResults;
      searchState['stage2StartTime'] = DateTime.now().millisecondsSinceEpoch;
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel');
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      if (searchState['activeEngine'] == 'primary' && !searchState['engineSwitched']) {
        LogUtil.i('主引擎表单失败，切换备用引擎');
        switchToBackupEngine();
      }
    } else if (message.message == 'SIMULATION_FAILED') {
      LogUtil.e('模拟真人行为失败');
    } else if (message.message.startsWith('模拟真人行为') ||
               message.message.startsWith('点击了搜索输入框') ||
               message.message.startsWith('填写了搜索关键词') ||
               message.message.startsWith('点击提交按钮')) {
    } else if (message.message == 'CONTENT_CHANGED') {
      handleContentChange();
    }
  }
  
  /// 开始解析流程
  Future<String> startParsing(String url) async {
    try {
      if (_checkCancelledAndHandle('不执行解析')) return 'ERROR';
      setupCancelListener();
      setupGlobalTimeout();
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少关键词参数 clickText');
        return 'ERROR';
      }
      searchState['searchKeyword'] = searchKeyword;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
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
      try {
        await controller!.loadRequest(Uri.parse(SousuoParser._primaryEngine));
        LogUtil.i('页面加载请求发出');
      } catch (e) {
        LogUtil.e('页面加载失败: $e');
        if (!searchState['engineSwitched']) {
          LogUtil.i('主引擎失败，切换备用引擎');
          switchToBackupEngine();
        }
      }
      final result = await completer.future;
      LogUtil.i('解析完成: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('找到 ${foundStreams.length} 个流，尝试测试');
        try {
          final result = await SousuoParser._testStreamsAndGetFastest(foundStreams, cancelToken: cancelToken);
          if (!completer.isCompleted) completer.complete(result);
          return result;
        } catch (testError) {
          LogUtil.e('测试流出错: $testError');
          if (!completer.isCompleted) completer.complete('ERROR');
        }
      } else if (!completer.isCompleted) {
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR');
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!isResourceCleaned) await cleanupResources();
    }
  }
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用引擎URL
  static const int _timeoutSeconds = 28; // 全局超时时间
  static const int _maxStreams = 8; // 最大提取流数量
  static const int _waitSeconds = 2; // 页面加载等待时间
  static const int _domChangeWaitMs = 500; // DOM变化等待时间
  static const int _flowTestWaitMs = 500; // 流测试等待时间
  static const int _backupEngineLoadWaitMs = 300; // 切换备用引擎等待时间
  static const int _cleanupRetryWaitMs = 300; // 清理重试等待时间
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 5.0; // 显著内容变化百分比
  static const int _contentChangeDebounceMs = 300; // 内容变化防抖时间
  static List<String> _blockKeywords = ["freetv.fun", "itvapp"]; // 屏蔽关键词
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:"|"|\')?((https?://[^"\']+)(?:"|"|\')?)',
    caseSensitive: false
  ); // 媒体链接正则
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false); // m3u8链接正则

  /// 设置屏蔽关键词
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      LogUtil.i('屏蔽关键词: ${_blockKeywords.join(', ')}');
    } else {
      _blockKeywords = [];
    }
  }

  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage();
      await controller.clearCache();
      LogUtil.i('清理WebView完成');
    } catch (e) {
      LogUtil.e('清理WebView出错: $e');
    }
  }
  
  /// 检查是否为主引擎URL
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 检查是否为备用引擎URL
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 注入DOM变化监听器
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          const initialContentLength = document.body.innerHTML.length;
          console.log("初始内容长度: " + initialContentLength);
          let lastNotificationTime = Date.now();
          let lastContentLength = initialContentLength;
          let debounceTimeout = null;
          const notifyContentChange = function() {
            if (debounceTimeout) clearTimeout(debounceTimeout);
            debounceTimeout = setTimeout(function() {
              const now = Date.now();
              if (now - lastNotificationTime < 1000) return;
              const currentContentLength = document.body.innerHTML.length;
              const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;
              if (changePercent > ${_significantChangePercent}) {
                console.log("显著内容变化: " + changePercent.toFixed(2) + "%");
                lastNotificationTime = now;
                lastContentLength = currentContentLength;
                ${channelName}.postMessage('CONTENT_CHANGED');
              }
              debounceTimeout = null;
            }, 200);
          };
          const observer = new MutationObserver(function(mutations) {
            let hasRelevantChanges = false;
            for (let i = 0; i < mutations.length; i++) {
              const mutation = mutations[i];
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
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
            if (hasRelevantChanges) notifyContentChange();
          });
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: false,
            characterData: false
          });
          setTimeout(function() {
            const currentContentLength = document.body.innerHTML.length;
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            console.log("延迟检查变化: " + contentChangePct.toFixed(2) + "%");
            if (contentChangePct > ${_significantChangePercent}) {
              console.log("延迟检测到变化");
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
    await Future.delayed(Duration(seconds: _waitSeconds));
    try {
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      final submitScript = '''
        (function() {
          console.log("查找表单元素");
          const form = document.getElementById('form1');
          const searchInput = document.getElementById('search');
          const submitButton = document.querySelector('input[name="Submit"]');
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
          searchInput.value = "$escapedKeyword";
          console.log("填写关键词: " + searchInput.value);
          if (submitButton) {
            console.log("点击提交按钮");
            submitButton.click();
            return true;
          } else {
            console.log("未找到提交按钮，尝试其他方法");
            const otherSubmitButton = form.querySelector('input[type="submit"]');
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
      final result = await controller.runJavaScriptReturningResult(submitScript);
      await Future.delayed(Duration(seconds: _waitSeconds));
      LogUtil.i('等待响应 (${_waitSeconds}秒)');
      return result.toString().toLowerCase() == 'true';
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

  /// 清理HTML字符串
  static String _cleanHtmlString(String htmlContent) {
    if (htmlContent.length < 2 || 
        htmlContent.codeUnitAt(0) != 34 || 
        htmlContent.codeUnitAt(htmlContent.length - 1) != 34) {
      return htmlContent;
    }
    final buffer = StringBuffer();
    final innerContent = htmlContent.substring(1, htmlContent.length - 1);
    for (int i = 0; i < innerContent.length; i++) {
      if (i < innerContent.length - 1 && innerContent[i] == '\\') {
        final nextChar = innerContent[i + 1];
        if (nextChar == '"') {
          buffer.write('"');
          i++;
        } else if (nextChar == 'n') {
          buffer.write('\n');
          i++;
        } else {
          buffer.write(innerContent[i]);
        }
      } else {
        buffer.write(innerContent[i]);
      }
    }
    return buffer.toString();
  }
  
  /// 提取媒体链接
  static Future<void> _extractMediaLinks(
    WebViewController controller, 
    List<String> foundStreams, 
    bool usingBackupEngine, 
    {int lastProcessedLength = 0}
  ) async {
    LogUtil.i('从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
    try {
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      String htmlContent = _cleanHtmlString(html.toString());
      final int contentLength = htmlContent.length;
      LogUtil.i('HTML长度: $contentLength');
      if (lastProcessedLength > 0 && contentLength <= lastProcessedLength) {
        LogUtil.i('内容未增加，跳过提取');
        return;
      }
      final matches = _mediaLinkRegex.allMatches(htmlContent);
      final int totalMatches = matches.length;
      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> URL: ${firstMatch.group(1)}');
      }
      final Map<String, bool> hostMap = {};
      for (final url in foundStreams) {
        try {
          final uri = Uri.parse(url);
          hostMap['${uri.host}:${uri.port}'] = true;
        } catch (_) {
          hostMap[url] = true;
        }
      }
      final List<String> m3u8Links = [];
      final List<String> otherLinks = [];
      for (final match in matches) {
        if (match.groupCount >= 1) {
          String? mediaUrl = match.group(1)?.trim();
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            mediaUrl = mediaUrl
                .replaceAll('&', '&')
                .replaceAll('"', '"')
                .replaceAll(RegExp("[\")'&;]+\$"), '');
            if (_isUrlBlocked(mediaUrl)) {
              LogUtil.i('跳过屏蔽链接: $mediaUrl');
              continue;
            }
            try {
              final uri = Uri.parse(mediaUrl);
              final String hostKey = '${uri.host}:${uri.port}';
              if (!hostMap.containsKey(hostKey)) {
                hostMap[hostKey] = true;
                if (_m3u8Regex.hasMatch(mediaUrl)) {
                  m3u8Links.add(mediaUrl);
                  LogUtil.i('提取m3u8链接: $mediaUrl');
                } else {
                  otherLinks.add(mediaUrl);
                  LogUtil.i('提取其他链接: $mediaUrl');
                }
              }
            } catch (e) {
              LogUtil.e('解析URL出错: $e, URL: $mediaUrl');
            }
          }
        }
      }
      int addedCount = 0;
      final int remainingSlots = _maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('达到最大链接数 $_maxStreams');
        return;
      }
      for (final link in m3u8Links) {
        foundStreams.add(link);
        addedCount++;
        if (foundStreams.length >= _maxStreams) {
          LogUtil.i('达到最大链接数 $_maxStreams，m3u8足够');
          break;
        }
      }
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
      LogUtil.i('匹配: $totalMatches, m3u8: ${m3u8Links.length}, 其他: ${otherLinks.length}, 新增: $addedCount');
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
        String debugSample = htmlContent.substring(0, sampleLength);
        final onclickRegex = RegExp('onclick="[^"]+"', caseSensitive: false);
        final onclickMatches = onclickRegex.allMatches(htmlContent).take(3).map((m) => m.group(0)).join(', ');
        LogUtil.i('无链接，HTML片段: $debugSample');
        if (onclickMatches.isNotEmpty) {
          LogUtil.i('onclick样本: $onclickMatches');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取链接出错', e, stackTrace);
    }
    LogUtil.i('提取完成，链接数: ${foundStreams.length}');
  }
  
  /// 测试流地址并返回最快有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams, {CancelToken? cancelToken}) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR';
    }
    LogUtil.i('测试 ${streams.length} 个流');
    final testCancelToken = cancelToken ?? CancelToken();
    final completer = Completer<String>();
    bool hasValidResponse = false;
    Timer? testTimeoutTimer;
    try {
      testTimeoutTimer = Timer(Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          LogUtil.i('测试超时，取消请求');
          if (!testCancelToken.isCancelled) testCancelToken.cancel('测试超时');
          if (!hasValidResponse) completer.complete('ERROR');
        }
      });
      final tasks = streams.map((streamUrl) async {
        try {
          if (completer.isCompleted || testCancelToken.isCancelled) return;
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
          if (response != null && !completer.isCompleted && !testCancelToken.isCancelled) {
            final responseTime = stopwatch.elapsedMilliseconds;
            LogUtil.i('流 $streamUrl 响应: ${responseTime}ms');
            hasValidResponse = true;
            if (!testCancelToken.isCancelled) {
              LogUtil.i('找到可用流，取消其他测试');
              testCancelToken.cancel('找到可用流');
            }
            completer.complete(streamUrl);
          }
        } catch (e) {
          if (testCancelToken.isCancelled) {
            LogUtil.i('测试取消: $streamUrl');
          } else {
            LogUtil.e('测试 $streamUrl 出错: $e');
          }
        }
      }).toList();
      await Future.wait(tasks);
      if (!completer.isCompleted) {
        LogUtil.i('无可用流');
        completer.complete('ERROR');
      }
      return await completer.future;
    } finally {
      testTimeoutTimer?.cancel();
      LogUtil.i('测试完成，清理资源');
    }
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    if (blockKeywords.isNotEmpty) setBlockKeywords(blockKeywords);
    final session = _ParserSession(cancelToken: cancelToken);
    return await session.startParsing(url);
  }
}
