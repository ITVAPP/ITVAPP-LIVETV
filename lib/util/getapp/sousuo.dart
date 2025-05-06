import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器 (支持两个搜索引擎)
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用搜索引擎URL
  
  // 通用配置
  static const int _timeoutSeconds = 30; // 总体搜索超时时间
  static const int _maxStreams = 8; // 最大提取的媒体流数量
  static const int _httpRequestTimeoutSeconds = 5; // HTTP请求超时时间
  
  // 时间常量 - 引擎相关
  static const int _engineEarlyCheckSeconds = 10; // 主引擎早期检查时间
  static const int _backupEngineTimeoutSeconds = 15; // 备用引擎超时时间
  static const int _backupEngineLoadWaitMs = 300; // 切换备用引擎前等待时间
  
  // 时间常量 - 页面和DOM相关
  static const int _pageLoadWaitMs = 1000; // 页面加载后等待时间
  static const int _formSubmitWaitSeconds = 2; // 表单提交后等待时间
  static const int _domChangeWaitMs = 500; // DOM变化后等待时间
  static const int _delayCheckSeconds = 3; // 延迟检查等待时间
  static const int _extractCheckSeconds = 1; // 提取后检查等待时间
  
  // 时间常量 - 测试和清理相关
  static const int _flowTestWaitMs = 500; // 流测试等待时间
  static const int _cleanupRetryWaitMs = 300; // 清理重试等待时间
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 10.0; // 显著内容变化百分比
  
  // 内容变化防抖时间(毫秒)
  static const int _contentChangeDebounceMs = 300;
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final completer = Completer<String>(); // 异步完成器，用于返回解析结果
    final List<String> foundStreams = []; // 存储提取的媒体流地址
    Timer? timeoutTimer; // 总体超时计时器
    Timer? engineCheckTimer; // 主引擎检查计时器
    WebViewController? controller; // WebView控制器
    bool contentChangedDetected = false; // 标记页面内容是否发生变化
    Timer? contentChangeDebounceTimer; // 内容变化防抖计时器
    
    // 简化资源清理标记，改为实例变量
    bool isResourceCleaned = false; // 标记资源是否已清理
    
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
    
    /// 清理WebView和相关资源
    Future<void> cleanupResources() async {
      if (isResourceCleaned) {
        return; // 已清理过资源，直接返回
      }
      
      isResourceCleaned = true; // 标记资源已清理
      LogUtil.i('开始清理资源');
      
      try {
        // 取消防抖计时器
        contentChangeDebounceTimer?.cancel();
        
        // 取消引擎检查计时器
        engineCheckTimer?.cancel();
        
        // 取消总体超时计时器
        if (timeoutTimer != null && timeoutTimer!.isActive) {
          timeoutTimer!.cancel();
          LogUtil.i('总体超时计时器已取消');
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
    
    /// 处理DOM内容变化的防抖函数
    void handleContentChange() {
      // 取消引擎检查计时器，避免切换到备用引擎
      engineCheckTimer?.cancel();
      
      contentChangeDebounceTimer?.cancel();
      
      contentChangeDebounceTimer = Timer(Duration(milliseconds: _contentChangeDebounceMs), () async {
        if (controller == null || completer.isCompleted) return;
        
        LogUtil.i('处理页面内容变化（防抖后）');
        contentChangedDetected = true;
        
        if (searchState['searchSubmitted'] == true && !completer.isCompleted) {
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
            
            // 如果已找到流，开始测试
            if (afterExtractCount > 0) {
              if (timeoutTimer != null) {
                timeoutTimer!.cancel(); // 取消超时计时器
              }
              
              _testStreamsAndGetFastest(foundStreams)
                .then((String result) {
                  if (!completer.isCompleted) {
                    completer.complete(result);
                    cleanupResources();
                  }
                });
            }
          } else if (searchState['activeEngine'] == 'primary' && 
                    afterExtractCount == 0 && 
                    searchState['engineSwitched'] == false &&
                    searchState['extractionCount'] >= 2) {
            LogUtil.i('多次提取后主引擎无链接，切换备用引擎');
            switchToBackupEngine();
          }
        }
      });
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
        onPageStarted: (String pageUrl) {
          LogUtil.i('页面开始加载: $pageUrl');
          
          // 中断主引擎页面加载（若已切换到备用引擎）
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(pageUrl) && controller != null) {
            LogUtil.i('已切换备用引擎，中断主引擎加载');
            controller!.loadHtmlString('<html><body></body></html>');
            return;
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
          
          // 提交搜索表单（若未提交）
          if (searchState['searchSubmitted'] == false) {
            final success = await _submitSearchForm(controller!, searchKeyword);
            
            if (success) {
              searchState['searchSubmitted'] = true;
              // 取消引擎检查计时器，避免切换到备用引擎
              engineCheckTimer?.cancel();
              
              await _injectDomChangeMonitor(controller!, 'AppChannel'); // 注入DOM变化监听器
              
              // 延迟检查提取结果
              Timer(Duration(seconds: _delayCheckSeconds), () {
                if (controller == null) {
                  LogUtil.e('延迟检查时控制器为空');
                  return;
                }
                
                if (!contentChangedDetected && !completer.isCompleted) {
                  LogUtil.i('强制提取媒体链接');
                  _extractMediaLinks(controller!, foundStreams, isBackupEngine);
                  
                  Timer(Duration(seconds: _extractCheckSeconds), () {
                    if (foundStreams.isNotEmpty && !completer.isCompleted) {
                      LogUtil.i('提取到 ${foundStreams.length} 个流');
                      _testStreamsAndGetFastest(foundStreams)
                        .then((String result) {
                          if (!completer.isCompleted) {
                            completer.complete(result);
                            cleanupResources();
                          }
                        });
                    } else if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                      LogUtil.i('主引擎无结果，切换备用引擎');
                      switchToBackupEngine();
                    }
                  });
                }
              });
            } else {
              LogUtil.e('表单提交失败');
              
              if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                LogUtil.i('主引擎表单失败，切换备用引擎');
                switchToBackupEngine();
              }
            }
          } else if (contentChangedDetected) {
            LogUtil.i('内容变化，重新提取链接');
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller!, foundStreams, isBackupEngine);
            int afterExtractCount = foundStreams.length;
            
            // 更新上次处理的HTML长度
            controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length')
              .then((result) {
                searchState['lastHtmlLength'] = int.tryParse(result.toString()) ?? 0;
              }).catchError((_) {});
            
            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接');
              
              if (timeoutTimer != null) {
                timeoutTimer!.cancel(); // 取消超时计时器
              }
              
              _testStreamsAndGetFastest(foundStreams)
                .then((String result) {
                  if (!completer.isCompleted) {
                    completer.complete(result);
                    cleanupResources();
                  }
                });
            } else if (isPrimaryEngine && afterExtractCount == 0 && searchState['engineSwitched'] == false) {
              LogUtil.i('主引擎无链接，切换备用引擎');
              switchToBackupEngine();
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
          
          if (message.message == 'CONTENT_CHANGED') {
            LogUtil.i('页面内容变化');
            // 取消引擎检查计时器，避免切换到备用引擎
            engineCheckTimer?.cancel();
            
            // 使用防抖函数处理内容变化
            handleContentChange();
          } else if (message.message.startsWith('http') && 
              foundStreams.length < _maxStreams) {
            // 仅通过主机去重进行判断
            try {
              Uri uri = Uri.parse(message.message);
              String hostKey = '${uri.host}:${uri.port}';
              
              // 检查主机是否已存在
              bool hostExists = foundStreams.any((url) {
                try {
                  Uri existingUri = Uri.parse(url);
                  return '${existingUri.host}:${existingUri.port}' == hostKey;
                } catch (_) {
                  return false;
                }
              });
              
              if (!hostExists) {
                foundStreams.add(message.message);
                LogUtil.i('添加链接: ${message.message}');
                
                if (foundStreams.length == 1) {
                  LogUtil.i('找到首个链接，准备测试');
                  
                  Future.delayed(Duration(milliseconds: _domChangeWaitMs), () {
                    if (!completer.isCompleted) {
                      _testStreamsAndGetFastest(foundStreams)
                        .then((String result) {
                          if (!completer.isCompleted) {
                            LogUtil.i('测试完成，返回结果');
                            completer.complete(result);
                            cleanupResources();
                          }
                        });
                    }
                  });
                }
              } else {
                LogUtil.i('跳过相同主机的链接: ${message.message}');
              }
            } catch (e) {
              LogUtil.e('解析链接出错: $e');
            }
          }
        },
      );
      LogUtil.i('JavaScript通道添加完成');
      
      // 加载主搜索引擎
      await controller!.loadRequest(Uri.parse(_primaryEngine));
      
      // 主引擎加载检查
      engineCheckTimer = Timer(Duration(seconds: _engineEarlyCheckSeconds), () {
        if (controller == null) {
          LogUtil.e('控制器为空');
          return;
        }
        
        if (searchState['activeEngine'] == 'primary' && 
            searchState['searchSubmitted'] == false && 
            searchState['engineSwitched'] == false &&
            searchState['primaryEngineLoadFailed'] == false) {
          
          controller!.runJavaScriptReturningResult('document.body.innerHTML.length').then((result) {
            int contentLength = int.tryParse(result.toString()) ?? 0;
            
            if (contentLength < _minValidContentLength) {
              LogUtil.i('主引擎内容不足，切换备用引擎');
              switchToBackupEngine();
            } else {
              LogUtil.i('主引擎内容正常，继续等待');
            }
          }).catchError((e) {
            LogUtil.e('检查主引擎内容出错: $e');
            switchToBackupEngine();
          });
        }
      });
      
      // 设置总体超时
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('搜索超时，找到 ${foundStreams.length} 个流');
        
        if (!completer.isCompleted) {
          if (foundStreams.isEmpty) {
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('主引擎无结果，切换备用引擎');
              switchToBackupEngine();
              
              Timer(Duration(seconds: _backupEngineTimeoutSeconds), () {
                if (!completer.isCompleted) {
                  if (foundStreams.isEmpty) {
                    LogUtil.i('备用引擎无结果，返回ERROR');
                    completer.complete('ERROR');
                    cleanupResources();
                  } else {
                    LogUtil.i('备用引擎找到 ${foundStreams.length} 个流');
                    _testStreamsAndGetFastest(foundStreams)
                      .then((String result) {
                        completer.complete(result);
                        cleanupResources();
                      });
                  }
                }
              });
            } else {
              LogUtil.i('无流地址，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            _testStreamsAndGetFastest(foundStreams)
              .then((String result) {
                LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
                completer.complete(result);
                cleanupResources();
              });
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
  
  /// 注入DOM变化监听器
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
            
            let hasSearchResults = false;
            mutations.forEach(function(mutation) {
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                for (let i = 0; i < mutation.addedNodes.length; i++) {
                  const node = mutation.addedNodes[i];
                  
                  if (node.tagName === 'TABLE' || 
                      (node.classList && (
                        node.classList.contains('result') || 
                        node.classList.contains('result-item') ||
                        node.classList.contains('search-result')
                      ))) {
                    console.log("检测到搜索结果出现");
                    hasSearchResults = true;
                    break;
                  }
                  
                  if (node.querySelectorAll) {
                    const tables = node.querySelectorAll('table');
                    if (tables.length > 0) {
                      console.log("检测到表格元素出现");
                      hasSearchResults = true;
                      break;
                    }
                  }
                }
              }
            });
            
            if (hasSearchResults) {
              console.log("检测到搜索结果，通知应用");
              notifyContentChanged();
              
              try {
                console.log("自动提取媒体链接");
                const copyButtons = document.querySelectorAll('img[onclick][src*="copy"], button[onclick], a[onclick]'); // 查找复制按钮
                console.log("找到 " + copyButtons.length + " 个复制按钮");
                
                // 使用Set进行URL去重
                const extractedUrls = new Set();
                
                copyButtons.forEach(function(button, index) {
                  const onclickAttr = button.getAttribute('onclick');
                  if (onclickAttr) {
                    let match;
                    match = onclickAttr.match(/wqjs\\("([^"]+)/); // 匹配主引擎URL
                    if (!match) {
                      match = onclickAttr.match(/copyto\\("([^"]+)/); // 匹配备用引擎URL
                    }
                    
                    if (match && match[1]) {
                      const url = match[1];
                      console.log("按钮#" + index + " 提取到URL: " + url);
                      if (url.startsWith('http') && !extractedUrls.has(url)) {
                        extractedUrls.add(url);
                        ${channelName}.postMessage(url); // 发送提取的URL
                        }
                    }
                  }
                });
              } catch (e) {
                console.error("自动提取链接出错: " + e);
              }
            }
          });

          observer.observe(document.body, { // 配置观察者
            childList: true, 
            subtree: true,
            attributes: true,
            characterData: true 
          });
          
          setTimeout(function() { // 备用检查定时器
            const tables = document.querySelectorAll('table');
            const resultContainers = document.querySelectorAll('.result, .result-item, .search-result');
            
            if (tables.length > 0 || resultContainers.length > 0) {
              console.log("备用定时器检测到搜索结果");
              notifyContentChanged();
            }
          }, 3000);
        })();
      ''');
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    try {
      await Future.delayed(Duration(milliseconds: _pageLoadWaitMs)); // 等待页面加载
      
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
      
      await Future.delayed(Duration(seconds: _formSubmitWaitSeconds)); // 等待页面响应
      LogUtil.i('等待响应 (${_formSubmitWaitSeconds}秒)');
      
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
    
    // 优先测试m3u8流
    final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList();
    final otherStreams = streams.where((url) => !url.contains('.m3u8')).toList();
    final prioritizedStreams = [...m3u8Streams, ...otherStreams]; // 优先级排序
    
    final tasks = prioritizedStreams.map((streamUrl) async {
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
          
          // 立即完成并返回第一个响应的流
          completer.complete(streamUrl);
          cancelToken.cancel('已找到可用流');
        }
      } catch (e) {
        LogUtil.e('测试 $streamUrl 出错: $e');
      }
    }).toList();
    
    // 设置测试超时
    Timer(Duration(seconds: HttpUtil.defaultReceiveTimeoutSeconds + 2), () {
      if (!completer.isCompleted) {
        if (m3u8Streams.isNotEmpty) {
          LogUtil.i('超时，返回首个m3u8: ${m3u8Streams.first}');
          completer.complete(m3u8Streams.first);
        } else {
          LogUtil.i('超时，返回首个链接: ${streams.first}');
          completer.complete(streams.first);
        }
        cancelToken.cancel('测试超时'); // 取消未完成请求
      }
    });
    
    await Future.wait(tasks); // 等待所有测试任务完成
    
    if (!completer.isCompleted) {
      if (m3u8Streams.isNotEmpty) {
        LogUtil.i('无响应，返回首个m3u8: ${m3u8Streams.first}');
        completer.complete(m3u8Streams.first);
      } else {
        LogUtil.i('无响应，返回首个链接: ${streams.first}');
        completer.complete(streams.first);
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
