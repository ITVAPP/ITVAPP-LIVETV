import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器 
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用引擎URL
  
  // 通用配置
  static const int _timeoutSeconds = 12; // 统一超时时间 - 适用于表单检测和DOM变化检测 - 增加到12秒以适应模拟行为
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
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final completer = Completer<String>(); // 异步完成器，用于返回解析结果
    final List<String> foundStreams = []; // 存储提取的媒体流地址
    Timer? timeoutTimer; // 超时计时器
    WebViewController? controller; // WebView控制器
    bool contentChangedDetected = false; // 标记页面内容是否发生变化
    Timer? contentChangeDebounceTimer; // 内容变化防抖计时器
    
    // 简化资源清理标记，改为实例变量
    bool isResourceCleaned = false; // 标记资源是否已清理
    bool isTestingStarted = false; // 标记链接测试是否已开始
    bool isExtractionInProgress = false; // 标记是否正在进行提取操作
    
    // 状态对象，存储解析过程中的动态信息
    final Map<String, dynamic> searchState = {
      'searchKeyword': '', // 搜索关键词
      'activeEngine': 'primary', // 当前使用的搜索引擎
      'searchSubmitted': false, // 搜索表单是否已提交
      'startTimeMs': DateTime.now().millisecondsSinceEpoch, // 解析开始时间
      'engineSwitched': false, // 是否已切换到备用引擎
      'primaryEngineLoadFailed': false, // 主引擎是否加载失败
      'lastHtmlLength': 0, // 上次提取时的HTML长度，用于增量提取
      'extractionCount': 0, // 提取计数，用于跟踪提取次数
    };
    
    /// 清理WebView和相关资源 - 需要放在最前面，因为被引用多次
    Future<void> cleanupResources() async {
      if (isResourceCleaned) {
        return; // 已清理过资源，直接返回
      }
      
      isResourceCleaned = true; // 标记资源已清理
      LogUtil.i('开始清理资源');
      
      try {
        // 取消防抖计时器
        contentChangeDebounceTimer?.cancel();
        
        // 取消超时计时器
        if (timeoutTimer != null && timeoutTimer!.isActive) {
          timeoutTimer!.cancel();
          LogUtil.i('超时计时器已取消');
        }
        
        // 清理WebView资源
        if (controller != null) {
          try {
            await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
            await _disposeWebView(controller!); // 释放WebView资源
            controller = null; // 置空控制器，防止重复清理
          } catch (e) {
            LogUtil.e('清理WebView资源时出错: $e');
          }
        }
        
        // 确保completer完成
        if (!completer.isCompleted) {
          LogUtil.i('Completer未完成，强制返回ERROR');
          completer.complete('ERROR');
        }
      } catch (e) {
        LogUtil.e('清理资源时出错: $e');
        if (!completer.isCompleted) {
          completer.complete('ERROR');
        }
      }
    }
    
    /// 开始测试流链接 
    void startStreamTesting() {
      if (isTestingStarted) {
        LogUtil.i('已经开始测试流链接，忽略重复测试请求');
        return;
      }
      
      isTestingStarted = true;
      LogUtil.i('开始测试 ${foundStreams.length} 个流链接');
      
      // 取消超时计时器
      if (timeoutTimer != null && timeoutTimer!.isActive) {
        timeoutTimer!.cancel();
      }
      
      _testStreamsAndGetFastest(foundStreams)
        .then((String result) {
          LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
          if (!completer.isCompleted) {
            completer.complete(result);
            cleanupResources();
          }
        });
    }
    
    /// 切换到备用搜索引擎
    Future<void> switchToBackupEngine() async {
      if (searchState['engineSwitched'] == true) {
        LogUtil.i('已切换到备用引擎，忽略');
        return;
      }
      
      LogUtil.i('主引擎不可用，切换到备用引擎');
      searchState['activeEngine'] = 'backup';
      searchState['engineSwitched'] = true;
      searchState['searchSubmitted'] = false;
      searchState['lastHtmlLength'] = 0; // 重置HTML长度
      searchState['extractionCount'] = 0; // 重置提取计数
      
      // 重置超时计时器
      if (timeoutTimer != null && timeoutTimer!.isActive) {
        timeoutTimer!.cancel();
      }
      
      // 为备用引擎设置新的超时计时器
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('备用引擎搜索超时');
        if (!completer.isCompleted) {
          if (foundStreams.isEmpty) {
            LogUtil.i('备用引擎无结果，返回ERROR');
            completer.complete('ERROR');
            cleanupResources();
          } else {
            startStreamTesting();
          }
        }
      });
      
      if (controller != null) {
        try {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
          await Future.delayed(Duration(milliseconds: _backupEngineLoadWaitMs)); // 等待备用引擎加载
          
          await controller!.loadRequest(Uri.parse(_backupEngine)); // 加载备用引擎页面
          LogUtil.i('已加载备用引擎: $_backupEngine');
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
    
    /// 重置超时计时器
    void resetTimeoutTimer() {
      if (timeoutTimer != null && timeoutTimer!.isActive) {
        timeoutTimer!.cancel();
        LogUtil.i('重置超时计时器');
      }
      
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('搜索超时，找到 ${foundStreams.length} 个流');
        
        if (!completer.isCompleted) {
          if (foundStreams.isEmpty) {
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('主引擎无结果，切换备用引擎');
              switchToBackupEngine();
            } else {
              LogUtil.i('无流地址，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            startStreamTesting();
          }
        }
      });
    }
    
    /// 处理DOM内容变化的防抖函数
    void handleContentChange() {
      contentChangeDebounceTimer?.cancel();
      
      // 防止正在提取过程中重复提取
      if (isExtractionInProgress) {
        LogUtil.i('提取操作正在进行中，跳过此次提取');
        return;
      }
      
      contentChangeDebounceTimer = Timer(Duration(milliseconds: _contentChangeDebounceMs), () async {
        if (controller == null || completer.isCompleted) return;
        
        // 标记开始处理提取
        isExtractionInProgress = true;
        
        LogUtil.i('处理页面内容变化（防抖后）');
        contentChangedDetected = true;
        
        if (searchState['searchSubmitted'] == true && !completer.isCompleted && !isTestingStarted) {
          int beforeExtractCount = foundStreams.length;
          bool isBackupEngine = searchState['activeEngine'] == 'backup';
          
          await _extractMediaLinks(
            controller!, 
            foundStreams, 
            isBackupEngine,
            lastProcessedLength: searchState['lastHtmlLength']
          );
          
          // 更新上次处理的HTML长度
          controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length')
            .then((result) {
              searchState['lastHtmlLength'] = int.tryParse(result.toString()) ?? 0;
            }).catchError((_) {});
          
          searchState['extractionCount'] = searchState['extractionCount'] + 1;
          int afterExtractCount = foundStreams.length;
          
          if (afterExtractCount > beforeExtractCount) {
            LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接');
            
            // 如果达到最大链接数，开始测试
            if (afterExtractCount >= _maxStreams) {
              LogUtil.i('达到最大链接数 $_maxStreams，开始测试');
              if (timeoutTimer != null) {
                timeoutTimer!.cancel(); // 取消超时计时器
              }
              
              startStreamTesting();
            }
            // 修改：链接提取成功后立即开始测试
            else if (afterExtractCount > 0) {
              LogUtil.i('提取完成，找到 ${afterExtractCount} 个链接，立即开始测试');
              if (timeoutTimer != null) {
                timeoutTimer!.cancel(); // 取消超时计时器
              }
              
              startStreamTesting();
            }
          } else if (searchState['activeEngine'] == 'primary' && 
                    afterExtractCount == 0 && 
                    searchState['engineSwitched'] == false) {
            LogUtil.i('主引擎无链接，切换备用引擎');
            switchToBackupEngine();
          }
        }
        
        // 标记提取操作结束
        isExtractionInProgress = false;
      });
    }
    
    /// 注入表单检测脚本
    Future<void> injectFormDetectionScript(String searchKeyword) async {
      if (controller == null) return;
      try {
        // 注入JavaScript代码检测表单 - 简化表单查找逻辑，统一使用相同ID选择器
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
            
            // 修改: 改进模拟真人行为函数，确保操作更可靠
            function simulateHumanBehavior() {
              return new Promise((resolve) => {
                if (window.AppChannel) {
                  window.AppChannel.postMessage('模拟真人行为');
                }
                
                // 优化滚动行为，确保不会出错
                function randomScroll() {
                  try {
                    let scrollAmount = Math.floor(Math.random() * 300) + 100;
                    window.scrollBy(0, scrollAmount);
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("随机滚动: " + scrollAmount + "px");
                    }
                    return true;
                  } catch (e) {
                    console.log("滚动操作出错: " + e);
                    return false;
                  }
                }
                
                // 优化点击行为，添加错误处理
                function randomClick() {
                  try {
                    let x = Math.floor(Math.random() * (window.innerWidth - 100)) + 50;
                    let y = Math.floor(Math.random() * (window.innerHeight - 100)) + 50;
                    
                    // 检查点击位置是否有元素
                    let element = document.elementFromPoint(x, y);
                    if (!element) {
                      console.log("点击位置无元素，尝试不同位置");
                      // 尝试页面中心
                      x = Math.floor(window.innerWidth / 2);
                      y = Math.floor(window.innerHeight / 2);
                      element = document.elementFromPoint(x, y);
                    }
                    
                    if (element) {
                      let clickEvent = new MouseEvent('click', {
                        'view': window,
                        'bubbles': true,
                        'cancelable': true,
                        'clientX': x,
                        'clientY': y
                      });
                      element.dispatchEvent(clickEvent);
                      if (window.AppChannel) {
                        window.AppChannel.postMessage("随机点击: (" + x + ", " + y + ")");
                      }
                      return true;
                    } else {
                      console.log("未找到可点击元素");
                      return false;
                    }
                  } catch (e) {
                    console.log("点击操作出错: " + e);
                    return false;
                  }
                }
                
                // 执行操作序列，但不依赖于结果
                randomScroll();
                
                // 无论操作成功与否，都会继续执行并最终resolve
                setTimeout(() => {
                  randomScroll();
                  setTimeout(() => {
                    randomClick();
                    // 即使点击失败也继续
                    setTimeout(() => {
                      randomClick();
                      // 无论如何都resolve Promise
                      resolve();
                    }, 500);
                  }, 500);
                }, 500);
              });
            }
            
            // 修改: 提交搜索表单函数，确保表单提交更可靠
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
              
              // 模拟真人行为并等待完成
              try {
                console.log("开始模拟真人行为");
                await simulateHumanBehavior();
                console.log("模拟真人行为完成");
              } catch (e) {
                console.log("模拟行为失败: " + e);
                // 即使模拟行为失败，我们也继续提交表单
                if (window.AppChannel) {
                  window.AppChannel.postMessage('SIMULATION_FAILED');
                }
              }
              
              // 确保关键词填写
              searchInput.value = window.__formCheckState.searchKeyword;
              console.log("已填写搜索关键词: " + searchInput.value);
              
              // 查找提交按钮
              const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
              
              // 延迟提交，给表单填充一些时间
              return new Promise((resolve) => {
                setTimeout(function() {
                  try {
                    if (submitButton) {
                      console.log("点击提交按钮");
                      submitButton.click();
                    } else {
                      console.log("直接提交表单");
                      form.submit();
                    }
                    
                    console.log("表单已提交");
                    
                    // 通知Flutter表单已提交
                    if (window.AppChannel) {
                      setTimeout(function() {
                        window.AppChannel.postMessage('FORM_SUBMITTED');
                      }, 300);
                    }
                    resolve(true);
                  } catch (e) {
                    console.log("表单提交出错: " + e);
                    
                    // 即使出错也通知，确保流程能继续
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                    }
                    resolve(false);
                  }
                }, 1000);
              });
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
    
    try {
      // 提取搜索关键词
      LogUtil.i('从URL提取搜索关键词');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      LogUtil.i('提取到搜索关键词: $searchKeyword');
      searchState['searchKeyword'] = searchKeyword;
      
      // 初始化WebView控制器
      LogUtil.i('创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JavaScript
        ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
      LogUtil.i('WebView控制器创建完成');
      
      // 配置导航委托
      LogUtil.i('设置WebView导航委托');
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) async {
          LogUtil.i('页面开始加载: $pageUrl');
          
          // 中断主引擎页面加载（若已切换到备用引擎）
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(pageUrl) && controller != null) {
            LogUtil.i('已切换备用引擎，中断主引擎加载');
            controller!.loadHtmlString('<html><body></body></html>');
            return;
          }
          
         // 注入表单检测脚本 (在页面开始加载时)
          if (!searchState['searchSubmitted'] && pageUrl != 'about:blank') {
            await injectFormDetectionScript(searchState['searchKeyword']);
          }
          
        },
        onPageFinished: (String pageUrl) async {
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
          
          bool isPrimaryEngine = _isPrimaryEngine(pageUrl); // 判断是否为主引擎
          bool isBackupEngine = _isBackupEngine(pageUrl); // 判断是否为备用引擎
          
          if (!isPrimaryEngine && !isBackupEngine) {
            LogUtil.i('未知页面: $pageUrl');
            return;
          }
          
          if (searchState['engineSwitched'] == true && isPrimaryEngine) {
            LogUtil.i('已切换备用引擎，忽略主引擎');
            return;
          }
          
          // 更新当前引擎状态
          if (isPrimaryEngine) {
            searchState['activeEngine'] = 'primary';
            LogUtil.i('主引擎页面加载完成');
          } else if (isBackupEngine) {
            searchState['activeEngine'] = 'backup';
            LogUtil.i('备用引擎页面加载完成');
          }
          
          // 如果是搜索结果页面，尝试主动提取一次
          if (searchState['searchSubmitted'] == true) {
            // 避免重复提取
            if (!isExtractionInProgress && !isTestingStarted) {
              // 延迟一小段时间后主动提取一次，确保页面完全渲染
              Timer(Duration(milliseconds: 500), () {
                if (controller != null && !completer.isCompleted) {
                  LogUtil.i('页面加载完成后主动尝试提取链接');
                  handleContentChange();
                }
              });
            }
          } 
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}');
          
          // 忽略非关键资源错误
          if (error.url == null || 
              error.url!.endsWith('.png') || 
              error.url!.endsWith('.jpg') || 
              error.url!.endsWith('.gif') || 
              error.url!.endsWith('.webp') || 
              error.url!.endsWith('.css')) {
            return;
          }
          
          // 处理主引擎关键错误
          if (searchState['activeEngine'] == 'primary' && 
              error.url != null && 
              error.url!.contains('tonkiang.us')) {
            
            bool isCriticalError = [
              -1, -2, -3, -6, -7, -101, -105, -106
            ].contains(error.errorCode); // 检查是否为关键错误
            
            if (isCriticalError) {
              LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
              searchState['primaryEngineLoadFailed'] = true;
              
              if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
                LogUtil.i('主引擎加载失败，切换备用引擎');
                switchToBackupEngine();
              }
            }
          }
        },
        onNavigationRequest: (NavigationRequest request) {
          // 阻止主引擎导航（若已切换备用引擎）
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(request.url)) {
            LogUtil.i('阻止主引擎导航');
            return NavigationDecision.prevent;
          }
          
          // 阻止加载图片、CSS等非必要资源
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
          
          return NavigationDecision.navigate; // 允许其他导航
        },
      ));
      
      // 添加JavaScript通信通道
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('收到消息: ${message.message}');
          
          if (controller == null) {
            LogUtil.e('控制器为空，无法处理消息');
            return;
          }
          
          if (message.message == 'FORM_SUBMITTED') {
            LogUtil.i('表单已提交');
            searchState['searchSubmitted'] = true;
            
            // 在表单提交时重置超时计时器
            resetTimeoutTimer();
            
            // 注入DOM变化监听器
            _injectDomChangeMonitor(controller!, 'AppChannel');
          } else if (message.message == 'FORM_PROCESS_FAILED') {
            LogUtil.i('表单处理失败');
            
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('主引擎表单处理失败，切换备用引擎');
              switchToBackupEngine();
            }
          } else if (message.message == 'SIMULATION_FAILED') {
            LogUtil.e('模拟真人行为失败');
          } else if (message.message.startsWith('模拟真人行为') ||
                     message.message.startsWith('随机滚动') ||
                     message.message.startsWith('随机点击')) {
            LogUtil.i('模拟行为日志: ${message.message}');
          } else if (message.message == 'CONTENT_CHANGED') {
            LogUtil.i('页面内容变化');
            
            // 使用防抖函数处理内容变化
            handleContentChange();
          }
        },
      );
      LogUtil.i('JavaScript通道添加完成');
      
      // 加载主搜索引擎
      await controller!.loadRequest(Uri.parse(_primaryEngine));
      
      // 设置统一超时
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('搜索超时，找到 ${foundStreams.length} 个流');
        
        if (!completer.isCompleted) {
          if (foundStreams.isEmpty) {
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('主引擎无结果，切换备用引擎');
              switchToBackupEngine();
            } else {
              LogUtil.i('无流地址，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            startStreamTesting();
          }
        }
      });
      
      // 等待解析结果
      final result = await completer.future;
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      // 计算总耗时
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);
      
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
        _testStreamsAndGetFastest(foundStreams)
          .then((String result) {
            completer.complete(result);
          });
      } else if (!completer.isCompleted) {
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!isResourceCleaned) {
        await cleanupResources(); // 确保资源清理
      }
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
  
  /// 注入DOM变化监听器 - 仅使用内容变化百分比检测
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          
          const initialContentLength = document.body.innerHTML.length; // 初始内容长度
          console.log("初始内容长度: " + initialContentLength);
          
          // 增加防抖动功能
          let debounceTimeout = null;
          
          const notifyContentChanged = function() {
            if (debounceTimeout) {
              clearTimeout(debounceTimeout);
            }
            
            debounceTimeout = setTimeout(function() {
              console.log("通知应用内容变化");
              ${channelName}.postMessage('CONTENT_CHANGED');
              debounceTimeout = null;
            }, 200); // 200ms防抖
          };
          
          const observer = new MutationObserver(function(mutations) { // 创建DOM变化观察者
            const currentContentLength = document.body.innerHTML.length;
            
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100; // 计算内容变化百分比
            console.log("内容长度变化百分比: " + contentChangePct.toFixed(2) + "%");
            
            if (contentChangePct > ${_significantChangePercent}) { // 内容变化超过阈值
              console.log("检测到显著内容变化");
              notifyContentChanged();
            }
          });

          observer.observe(document.body, { // 配置观察者
            childList: true, 
            subtree: true,
            attributes: true,
            characterData: true 
          });
          
          // 页面加载后延迟检查一次内容长度
          setTimeout(function() {
            const currentContentLength = document.body.innerHTML.length;
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            console.log("延迟检查内容变化百分比: " + contentChangePct.toFixed(2) + "%");
            
            if (contentChangePct > ${_significantChangePercent}) {
              console.log("检测到显著内容变化");
              notifyContentChanged();
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
  
  /// 提取媒体链接
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
      
      String htmlContent = html.toString();
      LogUtil.i('获取HTML，长度: ${htmlContent.length}');
      
      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                  .replaceAll('\\"', '"')
                  .replaceAll('\\n', '\n'); // 清理HTML字符串
      }
      
      // 高效的正则表达式，能正确匹配不同格式的URL
      final RegExp regex = RegExp('onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((http|https)://[^"\'\\)\\s]+)');
      final matches = regex.allMatches(htmlContent);
      int totalMatches = matches.length;
      int addedCount = 0;
      
      // 从已有流中提取主机集合，用于去重
      final Set<String> addedHosts = {};
      
      // 预先构建主机集合
      for (final existingUrl in foundStreams) {
        try {
          final uri = Uri.parse(existingUrl);
          addedHosts.add('${uri.host}:${uri.port}');
        } catch (_) {
          // 忽略无效URL
        }
      }
      
      for (final match in matches) {
        // 检查是否至少有1个捕获组，并获取第1个捕获组
        if (match.groupCount >= 1) {
          String? mediaUrl = match.group(1)?.trim(); // 提取URL
          
          if (mediaUrl != null) {
            // 处理特殊字符
            if (mediaUrl.endsWith('&quot;')) {
              mediaUrl = mediaUrl.substring(0, mediaUrl.length - 6); // 移除末尾引号
            }
            
            // 正确替换HTML实体
            mediaUrl = mediaUrl.replaceAll('&amp;', '&'); // 替换编码字符
            
            if (mediaUrl.isNotEmpty) {
              // 提取URL的主机部分
              Uri? uri;
              try {
                uri = Uri.parse(mediaUrl);
              } catch (e) {
                continue; // 跳过无效URL
              }
              
              // 生成主机标识（域名+端口）
              final String hostKey = '${uri.host}:${uri.port}';
              
              // 检查是否已添加来自同一主机的链接 - 仅使用主机名进行去重
              if (!addedHosts.contains(hostKey)) {
                foundStreams.add(mediaUrl); // 添加新链接
                addedHosts.add(hostKey); // 记录已添加的主机
                LogUtil.i('提取到链接: $mediaUrl');
                addedCount++;
                
                if (foundStreams.length >= _maxStreams) {
                  LogUtil.i('达到最大链接数 ${_maxStreams}');
                  break;
                }
              } else {
                LogUtil.i('跳过相同主机的链接: $mediaUrl');
              }
            }
          }
        }
      }
      
      LogUtil.i('匹配数: $totalMatches, 新增: $addedCount');
      
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
        LogUtil.i('无链接，HTML片段: ${htmlContent.substring(0, sampleLength)}');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取链接出错', e, stackTrace);
    }
    
    LogUtil.i('提取完成，链接数: ${foundStreams.length}');
  }
  
  /// 测试流地址并返回最快有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR';
    }
    
    LogUtil.i('测试 ${streams.length} 个流地址');
    
    final cancelToken = CancelToken(); // 请求取消标记
    final completer = Completer<String>(); // 异步完成器
    final startTime = DateTime.now(); // 测试开始时间
    bool hasValidResponse = false; // 标记是否有有效响应
    
    // 创建测试任务
    final tasks = streams.map((streamUrl) async {
      try {
        if (completer.isCompleted) return;
        
        // 发送GET请求测试流
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'GET',
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
          cancelToken: cancelToken,
          retryCount: 1,
        );
        
        if (response != null && !completer.isCompleted) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          LogUtil.i('流 $streamUrl 响应: ${responseTime}ms');
          
          hasValidResponse = true; // 标记有有效响应
          
          // 立即完成并返回第一个响应的流
          completer.complete(streamUrl);
          cancelToken.cancel('已找到可用流');
        }
      } catch (e) {
        LogUtil.e('测试 $streamUrl 出错: $e');
      }
    }).toList();
    
    // 设置测试超时
    Timer(Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        LogUtil.i('测试超时');
        if (!hasValidResponse) {
          LogUtil.i('无有效响应，返回ERROR');
          completer.complete('ERROR');
        }
        cancelToken.cancel('测试超时'); // 取消未完成请求
      }
    });
    
    await Future.wait(tasks); // 等待所有测试任务完成
    
    if (!completer.isCompleted) {
      if (!hasValidResponse) {
        LogUtil.i('所有流测试失败，返回ERROR');
        completer.complete('ERROR');
      }
    }
    
    final result = await completer.future;
    return result;
  }
  
  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
      LogUtil.i('清理WebView完成');
    } catch (e) {
      LogUtil.e('清理出错: $e');
    }
  }
}
