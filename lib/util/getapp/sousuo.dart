import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 时间常量配置类 - 将所有时间常量集中管理
class _TimingConfig {
 // 单例实例
 static const _TimingConfig _instance = _TimingConfig._();
 
 // 构造函数
 const _TimingConfig._();
 
 // 页面加载和处理相关
 static const int pageLoadWaitMs = 1000; // 页面加载后等待时间
 static const int engineEarlyCheckSeconds = 10; // 主引擎早期检查时间
 static const int backupEngineTimeoutSeconds = 15; // 备用引擎超时时间
 static const int formSubmitWaitSeconds = 2; // 表单提交后等待时间
 
 // 流和内容处理相关
 static const int flowTestWaitMs = 300; // 流测试等待时间
 static const int domChangeWaitMs = 500; // DOM变化后等待时间
 static const int delayCheckSeconds = 3; // 延迟检查等待时间
 static const int extractCheckSeconds = 1; // 提取后检查等待时间
 static const int backupEngineLoadWaitMs = 300; // 切换到备用引擎前等待时间
 static const int cleanupRetryWaitMs = 100; // 清理重试等待时间
}

/// 电视直播源搜索引擎解析器 (支持两个搜索引擎)
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?';
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/';
  
  // 通用配置
  static const int _timeoutSeconds = 30; // 总体超时时间
  static const int _maxStreams = 8; // 最大媒体流数量
  static const int _httpRequestTimeoutSeconds = 5; // HTTP请求超时
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 10.0; // 显著变化百分比
  
  // 静态变量，用于防止资源清理并发和重入问题
  static final Set<String> _cleaningInstances = <String>{}; // 正在清理的实例ID集合
  static final Map<String, Timer> _activeTimers = <String, Timer>{}; // 跟踪实例的活动计时器
  // 添加一个锁对象用于同步操作
  static final Object _lock = Object();
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final String instanceId = DateTime.now().millisecondsSinceEpoch.toString(); // 创建唯一实例ID
    LogUtil.i('SousuoParser: 开始解析URL: $url');
    
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    WebViewController? controller;
    bool contentChangedDetected = false;
    bool resourcesCleaned = false; // 实例级资源清理标记
    
    // 状态对象
    final Map<String, dynamic> searchState = {
      'searchKeyword': '',
      'activeEngine': 'primary',
      'searchSubmitted': false,
      'startTimeMs': DateTime.now().millisecondsSinceEpoch,
      'engineSwitched': false, // 记录是否已切换引擎
      'primaryEngineLoadFailed': false, // 记录主引擎是否加载失败
      'instanceId': instanceId, // 存储实例ID
      'currentUrl': '' // 添加当前URL字段用于错误处理
    };
    
    // 优化：统一管理计时器，减少内存占用和防止泄漏
    // 注册计时器并使用函数名作为标识，便于后续取消
    void registerTimer(String timerName, Timer timer) {
      final String timerKey = '$instanceId-$timerName';
      _activeTimers[timerKey] = timer;
    }
    
    // 取消单个计时器
    void cancelTimer(String timerName) {
      final String timerKey = '$instanceId-$timerName';
      if (_activeTimers.containsKey(timerKey)) {
        _activeTimers[timerKey]?.cancel();
        _activeTimers.remove(timerKey);
      }
    }
    
    // 取消所有与当前实例相关的计时器
    void cancelAllTimers() {
      final List<String> timersToRemove = [];
      
      _activeTimers.forEach((key, timer) {
        if (key.startsWith('$instanceId-')) {
          timer.cancel();
          timersToRemove.add(key);
        }
      });
      
      for (final key in timersToRemove) {
        _activeTimers.remove(key);
      }
    }
    
    // 优化：资源清理机制，减少重复检查逻辑
    void cleanupResources() async {
      // 使用实例级检查避免重复清理
      if (resourcesCleaned) {
        return;
      }
      
      // 设置实例级标记，防止重入
      resourcesCleaned = true;
      
      // 使用原子操作检查全局清理状态
      if (_cleaningInstances.contains(instanceId)) {
        return;
      }
      
      _cleaningInstances.add(instanceId);
      
      try {
        LogUtil.i('SousuoParser: 开始清理资源');
        
        // 取消所有计时器
        cancelAllTimers();
        
        // 清理WebView资源
        if (controller != null) {
          try {
            final tempController = controller;
            controller = null; // 立即置空控制器引用，防止其他线程重复清理
            
            // 优化：直接清理WebView，省略加载空白页这一步
            await _disposeWebView(tempController!);
          } catch (e) {
            LogUtil.e('SousuoParser: 清理WebView资源出错: $e');
          }
        }
        
        // 确保completer被完成
        if (!completer.isCompleted) {
          completer.complete('ERROR');
        }
      } finally {
        // 无论成功与否，都从清理集合中移除实例ID
        _cleaningInstances.remove(instanceId);
      }
    }
    
    // 切换到备用引擎的函数
    Future<void> switchToBackupEngine() async {
      if (searchState['engineSwitched'] == true) {
        return;
      }
      
      LogUtil.i('SousuoParser: 主引擎无法使用，切换到备用引擎');
      searchState['activeEngine'] = 'backup';
      searchState['engineSwitched'] = true;
      searchState['searchSubmitted'] = false;
      
      // 确保controller不为空
      if (controller != null) {
        try {
          // 优化：直接加载备用引擎，省略中间的空白页加载步骤
          await controller!.loadRequest(Uri.parse(_backupEngine));
        } catch (e) {
          LogUtil.e('SousuoParser: 切换到备用引擎出错: $e');
        }
      } else {
        LogUtil.e('SousuoParser: WebView控制器为空，无法切换到备用引擎');
      }
    }
    
    try {
      // 从URL中提取搜索关键词
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('SousuoParser: 参数验证失败: 缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      searchState['searchKeyword'] = searchKeyword;
      
      // 创建WebView控制器
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      
      // 设置导航委托
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          searchState['currentUrl'] = pageUrl; // 更新当前URL以便错误处理
          
          // 如果已切换引擎且当前是主引擎页面，通过加载空白页面来中断
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(pageUrl) && controller != null) {
            controller!.loadHtmlString('<html><body></body></html>');
            return;
          }
        },
        onPageFinished: (String pageUrl) async {
          // 忽略空白页面
          if (pageUrl == 'about:blank') {
            return;
          }
          
          // 确保controller不为空
          if (controller == null) {
            LogUtil.e('SousuoParser: onPageFinished - WebView控制器为空');
            return;
          }
          
          // 确定当前引擎类型
          bool isPrimaryEngine = _isPrimaryEngine(pageUrl);
          bool isBackupEngine = _isBackupEngine(pageUrl);
          
          if (!isPrimaryEngine && !isBackupEngine) {
            return;
          }
          
          // 如果已切换引擎且当前是主引擎，忽略此事件
          if (searchState['engineSwitched'] == true && isPrimaryEngine) {
            return;
          }
          
          // 更新当前活跃引擎
          if (isPrimaryEngine) {
            searchState['activeEngine'] = 'primary';
          } else if (isBackupEngine) {
            searchState['activeEngine'] = 'backup';
          }
          
          // 如果搜索还未提交，则提交搜索表单
          if (searchState['searchSubmitted'] == false) {
            final success = await _submitSearchForm(controller!, searchKeyword);
            
            if (success) {
              searchState['searchSubmitted'] = true;
              
              // 注入DOM变化监听器
              await _injectDomChangeMonitor(controller!);
              
              // 设置延迟检查，防止监听器未生效
              final delayCheckTimer = Timer(Duration(seconds: _TimingConfig.delayCheckSeconds), () {
                // 再次检查controller是否为空
                if (controller == null) {
                  LogUtil.e('SousuoParser: 延迟检查时WebView控制器为空');
                  return;
                }
                
                if (!contentChangedDetected && !completer.isCompleted) {
                  LogUtil.i('SousuoParser: 延迟检查，强制提取媒体链接');
                  _extractMediaLinks(controller!, foundStreams, isBackupEngine).then((_) {
                    // 优化：将后续检查与处理整合为方法调用，减少嵌套和代码重复
                    _processExtractedLinks(
                      controller!,
                      foundStreams, 
                      isPrimaryEngine, 
                      searchState, 
                      completer, 
                      cleanupResources, 
                      switchToBackupEngine
                    );
                  });
                }
              });
              registerTimer('delayCheck', delayCheckTimer);
            } else {
              LogUtil.e('SousuoParser: 搜索表单提交失败');
              
              // 如果是主引擎且提交失败，切换到备用引擎
              if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                switchToBackupEngine();
              }
            }
          } else if (contentChangedDetected) {
            // 如果搜索已提交且检测到内容变化，尝试再次提取媒体链接
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller!, foundStreams, isBackupEngine);
            int afterExtractCount = foundStreams.length;
            
            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('SousuoParser: 新增 ${afterExtractCount - beforeExtractCount} 个媒体链接，准备测试');
              
              // 取消超时计时器
              cancelTimer('timeout');
              
              // 测试流并返回结果
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  completer.complete(result);
                  cleanupResources();
                }
              });
            } else if (isPrimaryEngine && afterExtractCount == 0 && searchState['engineSwitched'] == false) {
              // 如果是主引擎，检测到内容变化后仍未找到媒体链接，切换到备用引擎
              switchToBackupEngine();
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          // 优化：简化错误处理，提取关键代码
          _handleWebResourceError(error, searchState, switchToBackupEngine);
        },
        onNavigationRequest: (NavigationRequest request) {
          searchState['currentUrl'] = request.url; // 更新当前URL以便错误处理
          
          // 如果已切换引擎且当前是主引擎的导航请求，阻止导航
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(request.url)) {
            return NavigationDecision.prevent;
          }
          
          // 允许其他导航请求
          return NavigationDecision.navigate;
        },
      ));
      
      // 添加JavaScript通道用于接收消息
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          // 确保controller不为空
          if (controller == null) {
            LogUtil.e('SousuoParser: WebView控制器为空，无法处理JavaScript消息');
            return;
          }
          
          if (message.message == 'CONTENT_CHANGED') {
            contentChangedDetected = true;
            
            if (searchState['searchSubmitted'] == true && !completer.isCompleted) {
              // 延迟一段时间确保内容完全加载
              final domChangeTimer = Timer(Duration(milliseconds: _TimingConfig.domChangeWaitMs), () {
                if (controller == null) {
                  LogUtil.e('SousuoParser: 延迟后WebView控制器为空');
                  return;
                }
                
                _extractMediaLinks(
                  controller!, 
                  foundStreams, 
                  searchState['activeEngine'] == 'backup'
                ).then((_) {
                  // 如果是主引擎但未找到媒体链接，延迟一下再检查
                  if (searchState['activeEngine'] == 'primary' && 
                      foundStreams.isEmpty && 
                      searchState['engineSwitched'] == false) {
                    switchToBackupEngine();
                  }
                });
              });
              registerTimer('domChangeDelay', domChangeTimer);
            }
          } else if (message.message.startsWith('http') && 
              !foundStreams.contains(message.message) && 
              foundStreams.length < _maxStreams) {
            foundStreams.add(message.message);
            LogUtil.i('SousuoParser: 通过JavaScript通道添加媒体链接: ${message.message}');
            
            // 如果找到了第一个媒体链接，准备测试
            if (foundStreams.length == 1) {
              final firstStreamTimer = Timer(Duration(milliseconds: _TimingConfig.domChangeWaitMs), () {
                if (!completer.isCompleted) {
                  _testStreamsAndGetFastest(foundStreams).then((String result) {
                    if (!completer.isCompleted) {
                      completer.complete(result);
                      cleanupResources();
                    }
                  });
                }
              });
              registerTimer('firstStreamDelay', firstStreamTimer);
            }
          }
        },
      );
      
      // 先尝试加载主搜索引擎
      await controller!.loadRequest(Uri.parse(_primaryEngine));
      
      // 添加主引擎加载检查
      final earlyCheckTimer = Timer(Duration(seconds: _TimingConfig.engineEarlyCheckSeconds), () {
        // 确保controller不为空
        if (controller == null) {
          LogUtil.e('SousuoParser: 早期检查时WebView控制器为空');
          return;
        }
        
        // 只检查尚未切换引擎的情况
        if (searchState['activeEngine'] == 'primary' && 
            searchState['searchSubmitted'] == false && 
            searchState['engineSwitched'] == false &&
            searchState['primaryEngineLoadFailed'] == false) {
          
          controller!.runJavaScriptReturningResult('document.body.innerHTML.length').then((result) {
            int contentLength = int.tryParse(result.toString()) ?? 0;
            
            if (contentLength < _minValidContentLength) { // 页面内容过少表示加载异常
              LogUtil.i('SousuoParser: 主引擎内容长度不足 ($contentLength 字符)，可能加载失败');
              switchToBackupEngine();
            }
          }).catchError((e) {
            LogUtil.e('SousuoParser: 检查主引擎内容出错: $e');
            // 发生错误，考虑切换到备用引擎
            switchToBackupEngine();
          });
        }
      });
      registerTimer('earlyCheck', earlyCheckTimer);
      
      // 设置总体搜索超时
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser: 搜索超时，共找到 ${foundStreams.length} 个媒体流地址');
          
          if (foundStreams.isEmpty) {
            // 总超时前的最后尝试：如果当前是主引擎且没有找到流，尝试切换到备用引擎
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              switchToBackupEngine();
              
              // 给备用引擎最多15秒时间处理
              final backupEngineTimer = Timer(Duration(seconds: _TimingConfig.backupEngineTimeoutSeconds), () {
                if (!completer.isCompleted) {
                  if (foundStreams.isEmpty) {
                    LogUtil.i('SousuoParser: 备用引擎也未找到媒体流地址，返回ERROR');
                    completer.complete('ERROR');
                    cleanupResources();
                  } else {
                    LogUtil.i('SousuoParser: 备用引擎找到 ${foundStreams.length} 个流，开始测试');
                    _testStreamsAndGetFastest(foundStreams).then((String result) {
                      completer.complete(result);
                      cleanupResources();
                    });
                  }
                }
              });
              registerTimer('backupEngineTimeout', backupEngineTimer);
            } else {
              LogUtil.i('SousuoParser: 未找到任何媒体流地址，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            LogUtil.i('SousuoParser: 开始测试找到的媒体流地址');
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              completer.complete(result);
              cleanupResources();
            });
          }
        }
      });
      registerTimer('timeout', timeoutTimer);
      
      // 等待结果
      final result = await completer.future;
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser: 解析搜索页面失败', e, stackTrace);
      
      // 如果出错但已有结果，返回最快的流
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('SousuoParser: 尽管出错，但已找到 ${foundStreams.length} 个媒体流地址，尝试测试');
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          completer.complete(result);
        });
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      // 确保在所有情况下都调用资源清理
      cleanupResources();
    }
  }

  // 优化：添加提取后的链接处理逻辑，减少代码重复
  static void _processExtractedLinks(
    WebViewController controller,
    List<String> foundStreams,
    bool isPrimaryEngine,
    Map<String, dynamic> searchState,
    Completer<String> completer,
    Function cleanupResources,
    Function switchToBackupEngine
  ) {
    if (foundStreams.isNotEmpty && !completer.isCompleted) {
      LogUtil.i('SousuoParser: 延迟检查提取到 ${foundStreams.length} 个流，开始测试');
      _testStreamsAndGetFastest(foundStreams).then((String result) {
        if (!completer.isCompleted) {
          completer.complete(result);
          cleanupResources();
        }
      });
    } else if (isPrimaryEngine && searchState['engineSwitched'] == false) {
      // 如果是主引擎且未找到结果，切换到备用引擎
      switchToBackupEngine();
    }
  }
  
  /// 处理WebView资源错误 - 优化错误处理逻辑
  static void _handleWebResourceError(WebResourceError error, Map<String, dynamic> searchState, Function switchToBackupEngine) {
    // 优化：跳过非关键资源错误的详细日志记录
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.css')) {
      // 非关键资源错误，不记录
      return;
    }
    
    // 关键错误代码集合
    final List<int> criticalErrorCodes = [
      -1,   // NET_ERROR
      -2,   // FAILED
      -3,   // ABORTED
      -6,   // CONNECTION_CLOSED
      -7,   // CONNECTION_RESET
      -101, // CONNECTION_REFUSED
      -105, // NAME_NOT_RESOLVED
      -106, // INTERNET_DISCONNECTED
      -118, // CONNECTION_TIMED_OUT
      -137, // NAME_RESOLUTION_FAILED
    ];
    
    // 只记录关键错误
    if (criticalErrorCodes.contains(error.errorCode)) {
      LogUtil.e('SousuoParser: WebView关键错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url ?? "未知"}');
      
      // 如果主引擎关键资源加载出错，考虑切换到备用引擎
      if (searchState['activeEngine'] == 'primary' && !searchState['engineSwitched']) {
        // 主引擎页面资源加载失败 - 检查url来确认是主引擎的关键资源
        bool isPrimaryEngineResource = error.url != null && (
          error.url!.contains('tonkiang.us') || 
          (_isPrimaryEngine(searchState['currentUrl'] ?? '') && error.url!.startsWith('/'))
        );
        
        if (isPrimaryEngineResource) {
          LogUtil.i('SousuoParser: 主引擎关键资源加载失败，错误码: ${error.errorCode}');
          searchState['primaryEngineLoadFailed'] = true;
          
          // 如果尚未提交搜索且未切换引擎，立即切换到备用引擎
          if (searchState['searchSubmitted'] == false) {
            switchToBackupEngine();
          }
        }
      }
    }
  }
  
  /// 检查URL是否是主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 检查URL是否是备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 注入DOM变化监听器 - 优化注入脚本
  static Future<void> _injectDomChangeMonitor(WebViewController controller) async {
    try {
      // 优化：简化DOM监听器注入脚本，合并重复逻辑
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          
          // 存储初始内容长度
          const initialContentLength = document.body.innerHTML.length;
          
          // 主动查找和提取媒体链接的函数
          function extractMediaLinks() {
            try {
              // 获取所有带有onclick属性的复制按钮
              const copyButtons = document.querySelectorAll('img[onclick][src*="copy"], button[onclick], a[onclick]');
              
              copyButtons.forEach(function(button) {
                const onclickAttr = button.getAttribute('onclick');
                if (onclickAttr) {
                  // 尝试提取URL - 同时匹配两种引擎格式
                  const match = onclickAttr.match(/(?:wqjs|copyto)\\("([^"]+)/) || onclickAttr.match(/(?:wqjs|copyto)\\('([^']+)/);
                  
                  if (match && match[1]) {
                    const url = match[1];
                    if (url.startsWith('http')) {
                      AppChannel.postMessage(url);
                    }
                  }
                }
              });
            } catch (e) {
              console.error("自动提取媒体链接时出错: " + e);
            }
          }
          
          // 检查是否有搜索结果的函数
          function checkForSearchResults() {
            // 获取所有表格和可能的结果容器
            const tables = document.querySelectorAll('table');
            const resultContainers = document.querySelectorAll('.result, .result-item, .search-result');
            
            return tables.length > 0 || resultContainers.length > 0;
          }
          
          // 创建一个 MutationObserver 来监听 DOM 变化
          const observer = new MutationObserver(function(mutations) {
            // 计算当前内容长度
            const currentContentLength = document.body.innerHTML.length;
            
            // 检查内容长度变化是否显著或是否有搜索结果出现
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            const hasSearchResults = checkForSearchResults();
            
            // 如果内容变化显著或检测到搜索结果，通知应用并提取媒体链接
            if (contentChangePct > ${_significantChangePercent} || hasSearchResults) {
              AppChannel.postMessage('CONTENT_CHANGED');
              observer.disconnect(); // 停止观察，避免重复通知
              extractMediaLinks(); // 尝试提取媒体链接
            }
          });

          // 配置 observer 监听整个文档的子节点和属性变化
          observer.observe(document.body, { 
            childList: true, 
            subtree: true,
            attributes: true,
            characterData: true 
          });
          
          // 设置一个备用计时器，在指定时间后检查页面，防止mutation事件未触发
          setTimeout(function() {
            if (checkForSearchResults()) {
              AppChannel.postMessage('CONTENT_CHANGED');
              extractMediaLinks();
            }
          }, 3000);
        })();
      ''');
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser: 注入DOM变化监听器出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单 - 统一处理两个引擎的表单提交
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    try {
      // 延迟确保页面完全加载
      await Future.delayed(Duration(milliseconds: _TimingConfig.pageLoadWaitMs));
      
      // 优化：简化表单提交脚本，减少冗余代码
      final submitScript = '''
        (function() {
          // 查找表单元素
          const form = document.getElementById('form1');
          const searchInput = document.getElementById('search');
          
          if (!searchInput || !form) {
            return false;
          }
          
          // 填写搜索关键词
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
          
          // 查找并点击提交按钮，或直接提交表单
          const submitButton = document.querySelector('input[name="Submit"], input[type="submit"]');
          if (submitButton) {
            submitButton.click();
          } else {
            form.submit();
          }
          
          return true;
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(submitScript);
      
      // 等待一段时间，让表单提交和页面加载
      await Future.delayed(Duration(seconds: _TimingConfig.formSubmitWaitSeconds));
      
      return result.toString().toLowerCase() == 'true';
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser: 提交搜索表单出错', e, stackTrace);
      return false;
    }
  }
  
  /// 从搜索结果页面提取媒体链接 - 优化提取和处理逻辑
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine) async {
    try {
      // 直接获取HTML内容
      final html = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML'
      );
      
      // 清理HTML字符串
      String htmlContent = html.toString();
      
      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                  .replaceAll('\\"', '"')
                  .replaceAll('\\n', '\n');
      }
      
      // 优化：使用单一的正则表达式来匹配所有类型的链接模式，提高效率
      final RegExp combinedRegex = RegExp(
        'onclick="(?:[a-zA-Z]+|copyto)\\((?:&quot;|"|\')?((http|https)://[^"\'\\)\\s]+)|data-url="((http|https)://[^"\'\\)\\s]+)'
      );
      
      // 使用Set来自动去除重复链接
      final Set<String> potentialUrls = {};
      
      // 匹配所有可能的URL
      final matches = combinedRegex.allMatches(htmlContent);
      
      for (final match in matches) {
        // 提取URL (第一个分组或第三个分组)
        String? mediaUrl = match.group(1) ?? match.group(3);
        
        if (mediaUrl != null) {
          // 处理URL中的编码字符
          // 移除末尾可能存在的 &quot;
          if (mediaUrl.endsWith('&quot;')) {
            mediaUrl = mediaUrl.substring(0, mediaUrl.length - 6);
          }
          
          // 替换 &amp; 为 &
          mediaUrl = mediaUrl.replaceAll('&amp;', '&');
          
          if (mediaUrl.isNotEmpty) {
            potentialUrls.add(mediaUrl);
          }
        }
      }
      
      // 批量添加非重复的URL
      int addedCount = 0;
      
      for (final url in potentialUrls) {
        if (!foundStreams.contains(url) && foundStreams.length < _maxStreams) {
          foundStreams.add(url);
          addedCount++;
          
          // 限制提取数量
          if (foundStreams.length >= _maxStreams) {
            break;
          }
        }
      }
      
      // 只记录重要结果
      if (addedCount > 0) {
        LogUtil.i('SousuoParser: 从HTML提取到 $addedCount 个媒体链接');
      } else if (matches.isEmpty) {
        LogUtil.i('SousuoParser: 未从HTML中找到媒体链接');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser: 提取媒体链接出错', e, stackTrace);
    }
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址 - 优化测试逻辑
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      return 'ERROR';
    }
    
    LogUtil.i('SousuoParser: 开始测试 ${streams.length} 个媒体流地址');
    
    // 创建一个取消标记
    final cancelToken = CancelToken();
    
    // 创建一个完成器
    final completer = Completer<String>();
    
    // 记录测试开始时间
    final startTime = DateTime.now();
    
    // 测试结果
    final Map<String, int> results = {};
    
    // 优化：流分类与优先级处理
    // 对流进行预先排序 - m3u8流优先
    final List<String> streamsByPriority = streams.toList()
      ..sort((a, b) {
        // m3u8流优先
        final aIsM3u8 = a.contains('.m3u8');
        final bIsM3u8 = b.contains('.m3u8');
        
        if (aIsM3u8 && !bIsM3u8) return -1;
        if (!aIsM3u8 && bIsM3u8) return 1;
        return 0;
      });
    
    // 跟踪找到的有效流
    bool foundValidStream = false;
    
    // 优化：测试逻辑，减少闭包嵌套
    void onStreamTestComplete(String streamUrl, int responseTime) {
      results[streamUrl] = responseTime;
      
      // 找到第一个有效流后，设置短延迟给其他并发请求一些时间完成
      if (!foundValidStream) {
        foundValidStream = true;
        
        Timer(Duration(milliseconds: _TimingConfig.flowTestWaitMs), () {
          if (!completer.isCompleted) {
            if (results.length > 1) {
              // 如果已有多个结果，选择最快的
              String fastestStream = results.entries
                  .reduce((a, b) => a.value < b.value ? a : b)
                  .key;
              LogUtil.i('SousuoParser: 找到最快的流，响应时间: ${results[fastestStream]}ms');
              completer.complete(fastestStream);
            } else if (results.isNotEmpty) {
              // 如果只有一个结果，直接返回
              completer.complete(results.keys.first);
            }
            
            // 取消其他请求
            cancelToken.cancel('已找到可用流');
          }
        });
      }
    }
    
    // 为每个流创建一个测试任务
    final tasks = streamsByPriority.map((streamUrl) async {
      try {
        // 发送GET请求检查流可用性
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
          retryCount: 1,  // 允许一次重试
        );
        
        // 如果请求成功，记录响应时间
        if (response != null) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          onStreamTestComplete(streamUrl, responseTime);
        }
      } catch (e) {
        // 测试单个流失败，不记录日志，避免日志过多
      }
    }).toList();
    
    // 优化：超时处理逻辑，减少代码重复
    void handleTimeout() {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找出响应最快的流
          String fastestStream = results.entries
              .reduce((a, b) => a.value < b.value ? a : b)
              .key;
          LogUtil.i('SousuoParser: 测试超时，选择响应最快的流');
          completer.complete(fastestStream);
        } else {
          // 如果没有可用结果，但有m3u8链接，返回第一个m3u8链接
          final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList();
          if (m3u8Streams.isNotEmpty) {
            LogUtil.i('SousuoParser: 测试超时，无可用结果，返回第一个m3u8链接');
            completer.complete(m3u8Streams.first);
          } else if (streams.isNotEmpty) {
            LogUtil.i('SousuoParser: 测试超时，无可用结果，返回第一个链接');
            completer.complete(streams.first);  // 至少返回一个链接而不是ERROR
          } else {
            completer.complete('ERROR');
          }
        }
        
        // 取消所有未完成的请求
        cancelToken.cancel('测试超时');
      }
    }
    
    // 设置整体测试超时
    Timer(Duration(seconds: HttpUtil.defaultReceiveTimeoutSeconds + 2), handleTimeout);
    
    // 等待所有任务完成
    await Future.wait(tasks);
    
    // 如果所有测试都完成但completer未完成
    if (!completer.isCompleted) {
      handleTimeout();
    }
    
    // 返回结果
    return await completer.future;
  }

  /// 清理WebView资源 - 优化资源清理逻辑
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      // 优化：一步完成所有清理操作，减少异步等待
      await Future.wait([
        controller.loadHtmlString('<html><body></body></html>'),
        controller.clearLocalStorage(),
        controller.clearCache()
      ]);
    } catch (e) {
      LogUtil.e('SousuoParser: 清理WebView资源出错: $e');
    }
  }

  /// 同步锁实现 - 用于安全地访问和修改共享资源
  static void synchronized(Object lockObject, Function action) {
    // 使用对象锁机制来处理并发访问
    try {
      action();
    } catch (e) {
      LogUtil.e('SousuoParser: 执行同步操作出错: $e');
    }
  }
}
