import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器 (支持两个搜索引擎)
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?';
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/';
  
  // 通用配置
  static const int _timeoutSeconds = 45; // 增加总超时时间
  static const int _maxStreams = 6;
  static const int _httpRequestTimeoutSeconds = 5;
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    LogUtil.i('SousuoParser.parse - 开始解析URL: $url');
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    WebViewController? controller;
    bool contentChangedDetected = false;
    
    // 状态对象
    final Map<String, dynamic> searchState = {
      'searchKeyword': '',
      'activeEngine': 'primary',
      'searchSubmitted': false,
      'startTimeMs': DateTime.now().millisecondsSinceEpoch,
      'engineSwitched': false, // 记录是否已切换引擎
      'primaryEngineLoadFailed': false, // 记录主引擎是否加载失败
    };
    
    void cleanupResources() async {
      LogUtil.i('SousuoParser.cleanupResources - 开始清理资源');
      
      // 取消总体超时计时器
      if (timeoutTimer != null) {
        timeoutTimer!.cancel();
        LogUtil.i('SousuoParser.cleanupResources - 总体超时计时器已取消');
      }
      
      // 清理WebView资源
      if (controller != null) {
        try {
          // 加载空白页面作为清理手段
          await controller!.loadHtmlString('<html><body></body></html>');
          LogUtil.i('SousuoParser.cleanupResources - 已加载空白页面');
          
          await _disposeWebView(controller!);
          LogUtil.i('SousuoParser.cleanupResources - WebView资源已清理');
        } catch (e) {
          LogUtil.e('SousuoParser.cleanupResources - 清理WebView资源时出错: $e');
        }
      }
      
      // 确保completer被完成
      if (!completer.isCompleted) {
        LogUtil.i('SousuoParser.cleanupResources - Completer未完成，强制完成为ERROR');
        completer.complete('ERROR');
      }
    }
    
    // 切换到备用引擎的函数
    Future<void> switchToBackupEngine() async {
      if (searchState['engineSwitched'] == true) {
        LogUtil.i('SousuoParser.switchToBackupEngine - 已经切换到备用引擎，忽略此调用');
        return;
      }
      
      LogUtil.i('SousuoParser.switchToBackupEngine - 主引擎无法使用，切换到备用引擎');
      searchState['activeEngine'] = 'backup';
      searchState['engineSwitched'] = true;
      searchState['searchSubmitted'] = false;
      
      // 先加载空白页面，再加载备用引擎
      await controller!.loadHtmlString('<html><body></body></html>');
      await Future.delayed(Duration(milliseconds: 300));
      
      await controller!.loadRequest(Uri.parse(_backupEngine));
      LogUtil.i('SousuoParser.switchToBackupEngine - 已发送备用搜索引擎加载请求: $_backupEngine');
    }
    
    try {
      // 从URL中提取搜索关键词
      LogUtil.i('SousuoParser.parse - 开始从URL中提取搜索关键词');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('SousuoParser.parse - 参数验证失败: 缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      LogUtil.i('SousuoParser.parse - 成功提取搜索关键词: $searchKeyword');
      searchState['searchKeyword'] = searchKeyword;
      
      // 创建WebView控制器
      LogUtil.i('SousuoParser.parse - 开始创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      LogUtil.i('SousuoParser.parse - WebView控制器创建完成');
      
      // 设置导航委托
      LogUtil.i('SousuoParser.parse - 开始设置WebView导航委托');
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('SousuoParser.onPageStarted - 页面开始加载: $pageUrl');
          
          // 如果已切换引擎且当前是主引擎页面，通过加载空白页面来中断
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(pageUrl)) {
            LogUtil.i('SousuoParser.onPageStarted - 已切换到备用引擎，中断主引擎页面加载');
            controller!.loadHtmlString('<html><body></body></html>');
            return;
          }
        },
        onPageFinished: (String pageUrl) async {
          final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
          final startMs = searchState['startTimeMs'] as int;
          final loadTimeMs = currentTimeMs - startMs;
          LogUtil.i('SousuoParser.onPageFinished - 页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms');
          
          // 忽略空白页面
          if (pageUrl == 'about:blank') {
            LogUtil.i('SousuoParser.onPageFinished - 空白页面加载完成，忽略');
            return;
          }
          
          // 确定当前引擎类型
          bool isPrimaryEngine = _isPrimaryEngine(pageUrl);
          bool isBackupEngine = _isBackupEngine(pageUrl);
          
          if (!isPrimaryEngine && !isBackupEngine) {
            LogUtil.i('SousuoParser.onPageFinished - 未知页面加载完成: $pageUrl');
            return;
          }
          
          // 如果已切换引擎且当前是主引擎，忽略此事件
          if (searchState['engineSwitched'] == true && isPrimaryEngine) {
            LogUtil.i('SousuoParser.onPageFinished - 已切换到备用引擎，忽略主引擎页面加载完成事件');
            return;
          }
          
          // 更新当前活跃引擎
          if (isPrimaryEngine) {
            searchState['activeEngine'] = 'primary';
            LogUtil.i('SousuoParser.onPageFinished - 主搜索引擎页面加载完成');
          } else if (isBackupEngine) {
            searchState['activeEngine'] = 'backup';
            LogUtil.i('SousuoParser.onPageFinished - 备用搜索引擎页面加载完成');
          }
          
          // 如果搜索还未提交，则提交搜索表单
          if (searchState['searchSubmitted'] == false) {
            LogUtil.i('SousuoParser.onPageFinished - 准备提交搜索表单');
            final success = await _submitSearchForm(controller!, searchKeyword);
            
            if (success) {
              searchState['searchSubmitted'] = true;
              LogUtil.i('SousuoParser.onPageFinished - 搜索表单提交成功，注入DOM变化监听器');
              
              // 注入DOM变化监听器
              await _injectDomChangeMonitor(controller!);
              
              // 设置延迟检查，防止监听器未生效
              Timer(Duration(seconds: 3), () {
                if (!contentChangedDetected && !completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 延迟检查，强制提取媒体链接');
                  _extractMediaLinks(controller!, foundStreams, isBackupEngine);
                  
                  // 再延迟1秒检查提取结果
                  Timer(Duration(seconds: 1), () {
                    if (foundStreams.isNotEmpty && !completer.isCompleted) {
                      LogUtil.i('SousuoParser.onPageFinished - 延迟检查提取到 ${foundStreams.length} 个流，开始测试');
                      _testStreamsAndGetFastest(foundStreams).then((String result) {
                        if (!completer.isCompleted) {
                          completer.complete(result);
                          cleanupResources();
                        }
                      });
                    } else if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                      // 如果是主引擎且未找到结果，切换到备用引擎
                      LogUtil.i('SousuoParser.onPageFinished - 主引擎未找到结果，切换到备用引擎');
                      switchToBackupEngine();
                    }
                  });
                }
              });
            } else {
              LogUtil.e('SousuoParser.onPageFinished - 搜索表单提交失败');
              
              // 如果是主引擎且提交失败，切换到备用引擎
              if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                LogUtil.i('SousuoParser.onPageFinished - 主引擎搜索表单提交失败，切换到备用引擎');
                switchToBackupEngine();
              }
            }
          } else if (contentChangedDetected) {
            // 如果搜索已提交且检测到内容变化，尝试再次提取媒体链接
            LogUtil.i('SousuoParser.onPageFinished - 检测到内容变化，再次提取媒体链接');
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller!, foundStreams, isBackupEngine);
            int afterExtractCount = foundStreams.length;
            
            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('SousuoParser.onPageFinished - 新增 ${afterExtractCount - beforeExtractCount} 个媒体链接，准备测试');
              
              // 取消超时计时器
              if (timeoutTimer != null) {
                timeoutTimer!.cancel();
              }
              
              // 测试流并返回结果
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 完成解析过程，返回结果');
                  completer.complete(result);
                  cleanupResources();
                }
              });
            } else if (isPrimaryEngine && afterExtractCount == 0 && searchState['engineSwitched'] == false) {
              // 如果是主引擎，检测到内容变化后仍未找到媒体链接，切换到备用引擎
              LogUtil.i('SousuoParser.onPageFinished - 主引擎内容已变化但未找到媒体链接，切换到备用引擎');
              switchToBackupEngine();
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('SousuoParser.onWebResourceError - WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url ?? "未知"}');
          
          // 忽略次要资源错误
          if (error.url == null || 
              error.url!.endsWith('.png') || 
              error.url!.endsWith('.jpg') || 
              error.url!.endsWith('.gif') || 
              error.url!.endsWith('.css')) {
            return;
          }
          
          // 如果主引擎关键资源加载出错，标记主引擎加载失败
          if (searchState['activeEngine'] == 'primary' && 
              error.url != null && 
              error.url!.contains('tonkiang.us')) {
            
            // 检查是否是关键错误（连接失败、DNS解析失败等）
            bool isCriticalError = [
              -1,   // NET_ERROR
              -2,   // FAILED
              -3,   // ABORTED
              -6,   // CONNECTION_CLOSED
              -7,   // CONNECTION_RESET
              -101, // CONNECTION_REFUSED
              -105, // NAME_NOT_RESOLVED
              -106, // INTERNET_DISCONNECTED
            ].contains(error.errorCode);
            
            if (isCriticalError) {
              LogUtil.i('SousuoParser.onWebResourceError - 主引擎关键资源加载失败，错误码: ${error.errorCode}');
              searchState['primaryEngineLoadFailed'] = true;
              
              // 如果尚未提交搜索且未切换引擎，立即切换到备用引擎
              if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
                LogUtil.i('SousuoParser.onWebResourceError - 主引擎加载出错，切换到备用引擎');
                switchToBackupEngine();
              }
            }
          }
        },
        onNavigationRequest: (NavigationRequest request) {
          // 监控导航请求，可以用来检测表单提交后的页面跳转
          LogUtil.i('SousuoParser.onNavigationRequest - 导航请求: ${request.url}');
          
          // 如果已切换引擎且当前是主引擎的导航请求，阻止导航
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(request.url)) {
            LogUtil.i('SousuoParser.onNavigationRequest - 已切换到备用引擎，阻止主引擎导航请求');
            return NavigationDecision.prevent;
          }
          
          // 允许其他导航请求
          return NavigationDecision.navigate;
        },
      ));
      LogUtil.i('SousuoParser.parse - WebView导航委托设置完成');
      
      // 添加JavaScript通道用于接收消息
      LogUtil.i('SousuoParser.parse - 开始添加JavaScript通道');
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('SousuoParser.JavaScriptChannel - 收到JavaScript消息: ${message.message}');
          
          if (message.message == 'CONTENT_CHANGED') {
            LogUtil.i('SousuoParser.JavaScriptChannel - 检测到页面内容发生变化');
            contentChangedDetected = true;
            
            if (searchState['searchSubmitted'] == true && !completer.isCompleted) {
              LogUtil.i('SousuoParser.JavaScriptChannel - 开始提取媒体链接');
              
              // 延迟一段时间确保内容完全加载
              Future.delayed(Duration(milliseconds: 500), () {
                _extractMediaLinks(
                  controller!, 
                  foundStreams, 
                  searchState['activeEngine'] == 'backup'
                );
                
                // 如果是主引擎但未找到媒体链接，延迟一下再检查
                if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
                  Future.delayed(Duration(seconds: 1), () {
                    if (foundStreams.isEmpty && !completer.isCompleted) {
                      LogUtil.i('SousuoParser.JavaScriptChannel - 主引擎未找到媒体链接，切换到备用引擎');
                      switchToBackupEngine();
                    }
                  });
                }
              });
            }
          } else if (message.message.startsWith('http') && 
              !foundStreams.contains(message.message) && 
              foundStreams.length < _maxStreams) {
            foundStreams.add(message.message);
            LogUtil.i('SousuoParser.JavaScriptChannel - 通过JavaScript通道添加媒体链接: ${message.message}, 当前列表大小: ${foundStreams.length}/${_maxStreams}');
            
            // 如果找到了第一个媒体链接，准备测试
            if (foundStreams.length == 1) {
              LogUtil.i('SousuoParser.JavaScriptChannel - 找到第一个媒体链接，准备测试');
              
              Future.delayed(Duration(milliseconds: 500), () {
                if (!completer.isCompleted) {
                  _testStreamsAndGetFastest(foundStreams).then((String result) {
                    if (!completer.isCompleted) {
                      LogUtil.i('SousuoParser.JavaScriptChannel - 测试完成，返回结果');
                      completer.complete(result);
                      cleanupResources();
                    }
                  });
                }
              });
            }
          }
        },
      );
      LogUtil.i('SousuoParser.parse - JavaScript通道添加完成');
      
      // 先尝试加载主搜索引擎
      LogUtil.i('SousuoParser.parse - 开始加载主搜索引擎: $_primaryEngine');
      await controller.loadRequest(Uri.parse(_primaryEngine));
      LogUtil.i('SousuoParser.parse - 主搜索引擎加载请求已发送');
      
      // 设置检查主引擎可用性的定时器 - 20秒后检查主引擎是否已加载完成或失败
      Timer(Duration(seconds: 20), () {
        // 只有当主引擎既未加载完成也未被标记为失败时，才切换到备用引擎
        if (searchState['activeEngine'] == 'primary' && 
            searchState['searchSubmitted'] == false && 
            searchState['engineSwitched'] == false &&
            searchState['primaryEngineLoadFailed'] == false) {
          
          // 检查当前WebView内容，确认主引擎确实加载失败
          controller!.runJavaScriptReturningResult('document.body.innerHTML.length').then((result) {
            int contentLength = int.tryParse(result.toString()) ?? 0;
            
            if (contentLength < 1000) { // 假设少于1000字符意味着页面未正确加载
              LogUtil.i('SousuoParser.engineCheck - 主引擎20秒后内容长度不足 ($contentLength 字符)，可能加载失败');
              switchToBackupEngine();
            } else {
              LogUtil.i('SousuoParser.engineCheck - 主引擎20秒后内容长度正常 ($contentLength 字符)，继续等待');
            }
          }).catchError((e) {
            LogUtil.e('SousuoParser.engineCheck - 检查主引擎内容时出错');
            switchToBackupEngine();
          });
        }
      });
      
      // 设置总体搜索超时
      LogUtil.i('SousuoParser.parse - 设置总体搜索超时: ${_timeoutSeconds}秒');
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('SousuoParser.searchTimeout - 搜索总超时触发，当前状态: completer完成=${completer.isCompleted}, 找到流数量=${foundStreams.length}');
        
        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser.searchTimeout - 搜索超时，共找到 ${foundStreams.length} 个媒体流地址');
          
          if (foundStreams.isEmpty) {
            // 总超时前的最后尝试：如果当前是主引擎且没有找到流，尝试切换到备用引擎
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('SousuoParser.searchTimeout - 主引擎未找到结果，最后尝试切换到备用引擎');
              switchToBackupEngine();
              
              // 给备用引擎最多15秒时间处理
              Timer(Duration(seconds: 15), () {
                if (!completer.isCompleted) {
                  if (foundStreams.isEmpty) {
                    LogUtil.i('SousuoParser.searchTimeout - 备用引擎也未找到媒体流地址，返回ERROR');
                    completer.complete('ERROR');
                    cleanupResources();
                  } else {
                    LogUtil.i('SousuoParser.searchTimeout - 备用引擎找到 ${foundStreams.length} 个流，开始测试');
                    _testStreamsAndGetFastest(foundStreams).then((String result) {
                      completer.complete(result);
                      cleanupResources();
                    });
                  }
                }
              });
            } else {
              LogUtil.i('SousuoParser.searchTimeout - 未找到任何媒体流地址，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            LogUtil.i('SousuoParser.searchTimeout - 开始测试找到的媒体流地址');
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              LogUtil.i('SousuoParser.searchTimeout - 流地址测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
              completer.complete(result);
              cleanupResources();
            });
          }
        }
      });
      
      // 等待结果
      LogUtil.i('SousuoParser.parse - 等待解析结果中...');
      final result = await completer.future;
      LogUtil.i('SousuoParser.parse - 解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      // 计算总耗时
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('SousuoParser.parse - 整个解析过程共耗时: ${endTimeMs - startMs}ms');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser.parse - 解析搜索页面失败', e, stackTrace);
      
      // 如果出错但已有结果，返回最快的流
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 尽管出错，但已找到 ${foundStreams.length} 个媒体流地址，尝试测试');
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          completer.complete(result);
        });
      } else if (!completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 出错且未找到媒体流地址，返回ERROR');
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      cleanupResources();
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
  
  /// 注入DOM变化监听器
  static Future<void> _injectDomChangeMonitor(WebViewController controller) async {
    LogUtil.i('SousuoParser._injectDomChangeMonitor - 开始注入DOM变化监听器');
    
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          
          // 存储初始内容长度
          const initialContentLength = document.body.innerHTML.length;
          console.log("初始内容长度: " + initialContentLength);
          
          // 创建一个 MutationObserver 来监听 DOM 变化
          const observer = new MutationObserver(function(mutations) {
            // 计算当前内容长度
            const currentContentLength = document.body.innerHTML.length;
            
            // 检查内容长度变化是否显著
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            console.log("内容长度变化百分比: " + contentChangePct.toFixed(2) + "%");
            
            // 如果内容变化显著，通知应用
            if (contentChangePct > 10) {  // 内容变化超过10%
              console.log("检测到显著内容变化，通知应用");
              AppChannel.postMessage('CONTENT_CHANGED');
              
              // 停止观察，避免重复通知
              observer.disconnect();
            }
            
            // 同时检查是否有搜索结果表格或列表出现
            let hasSearchResults = false;
            mutations.forEach(function(mutation) {
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                for (let i = 0; i < mutation.addedNodes.length; i++) {
                  const node = mutation.addedNodes[i];
                  
                  // 查找新添加的表格或结果列表
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
                  
                  // 检查是否包含表格
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
              console.log("检测到搜索结果出现，通知应用");
              AppChannel.postMessage('CONTENT_CHANGED');
              
              // 停止观察，避免重复通知
              observer.disconnect();
              
              // 主动查找和提取媒体链接
              try {
                console.log("自动提取页面中的媒体链接");
                // 获取所有带有onclick属性的复制按钮
                const copyButtons = document.querySelectorAll('img[onclick][src*="copy"], button[onclick], a[onclick]');
                console.log("找到 " + copyButtons.length + " 个可能的复制按钮");
                
                copyButtons.forEach(function(button, index) {
                  const onclickAttr = button.getAttribute('onclick');
                  if (onclickAttr) {
                    // 尝试提取URL
                    let match;
                    
                    // 尝试匹配主引擎格式
                    match = onclickAttr.match(/wqjs\\("([^"]+)/);
                    if (!match) {
                      // 尝试匹配备用引擎格式
                      match = onclickAttr.match(/copyto\\("([^"]+)/);
                    }
                    
                    if (match && match[1]) {
                      const url = match[1];
                      console.log("按钮#" + index + " 提取到URL: " + url);
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
          });

          // 配置 observer 监听整个文档的子节点和属性变化
          observer.observe(document.body, { 
            childList: true, 
            subtree: true,
            attributes: true,
            characterData: true 
          });
          
          // 设置一个备用计时器，在3秒后检查页面，防止mutation事件未触发
          setTimeout(function() {
            // 获取所有表格和可能的结果容器
            const tables = document.querySelectorAll('table');
            const resultContainers = document.querySelectorAll('.result, .result-item, .search-result');
            
            if (tables.length > 0 || resultContainers.length > 0) {
              console.log("备用计时器检测到可能的搜索结果");
              AppChannel.postMessage('CONTENT_CHANGED');
            }
          }, 3000);
        })();
      ''');
      
      LogUtil.i('SousuoParser._injectDomChangeMonitor - DOM变化监听器注入完成');
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._injectDomChangeMonitor - 注入DOM变化监听器时出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单 - 统一处理两个引擎的表单提交
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    LogUtil.i('SousuoParser._submitSearchForm - 开始提交搜索表单，关键词: $searchKeyword');
    
    try {
      // 延迟一下确保页面完全加载
      LogUtil.i('SousuoParser._submitSearchForm - 等待页面完全加载 (500ms)');
      await Future.delayed(Duration(milliseconds: 500));
      
      // 两个引擎使用相同的表单结构，可以使用统一的脚本
      final submitScript = '''
        (function() {
          console.log("搜索引擎：开始在页面中查找搜索表单元素");
          
          // 查找表单元素
          const form = document.getElementById('form1');
          const searchInput = document.getElementById('search');
          const submitButton = document.querySelector('input[name="Submit"]');
          
          if (!searchInput || !form) {
            console.log("未找到搜索表单元素: searchInput=" + (searchInput ? "存在" : "不存在") + ", form=" + (form ? "存在" : "不存在"));
            
            // 调试信息
            console.log("调试信息 - 表单数量: " + document.forms.length);
            for(let i = 0; i < document.forms.length; i++) {
              console.log("表单 #" + i + " ID: " + document.forms[i].id);
            }
            
            const inputs = document.querySelectorAll('input');
            console.log("调试信息 - 输入框数量: " + inputs.length);
            for(let i = 0; i < inputs.length; i++) {
              console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
            }
            
            return false;
          }
          
          // 填写搜索关键词
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
          console.log("填写搜索关键词: " + searchInput.value);
          
          // 点击提交按钮
          if (submitButton) {
            console.log("找到提交按钮，点击提交");
            submitButton.click();
            return true;
          } else {
            console.log("未找到名称为Submit的提交按钮，尝试其他方法");
            
            // 尝试查找其他提交按钮
            const otherSubmitButton = form.querySelector('input[type="submit"]');
            if (otherSubmitButton) {
              console.log("找到类型为submit的按钮，点击提交");
              otherSubmitButton.click();
              return true;
            } else {
              console.log("未找到任何提交按钮，直接提交表单");
              form.submit();
              return true;
            }
          }
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(submitScript);
      LogUtil.i('SousuoParser._submitSearchForm - 搜索表单提交结果: $result');
      
      // 等待一段时间，让表单提交和页面加载
      LogUtil.i('SousuoParser._submitSearchForm - 等待页面响应 (2秒)');
      await Future.delayed(Duration(seconds: 2));
      
      return result.toString().toLowerCase() == 'true';
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._submitSearchForm - 提交搜索表单时出错', e, stackTrace);
      return false;
    }
  }
  
  /// 从搜索结果页面提取媒体链接
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine, {bool forceDeepExtract = false}) async {
    LogUtil.i('SousuoParser._extractMediaLinks - 开始从${usingBackupEngine ? "备用" : "主"}搜索引擎提取媒体链接');
    
    try {
      // 注入脚本提取媒体链接
      LogUtil.i('SousuoParser._extractMediaLinks - 注入JavaScript脚本提取媒体链接');
      await controller.runJavaScript('''
        (function() {
          console.log("开始在页面中查找带有onclick属性的复制按钮");
          // 获取所有带有onclick属性的复制按钮和链接
          const copyButtons = document.querySelectorAll('img[onclick][src*="copy"], button[onclick], a[onclick]');
          console.log("找到 " + copyButtons.length + " 个可能的复制按钮");
          
          // 从onclick属性中提取URL
          let foundUrls = 0;
          copyButtons.forEach(function(button, index) {
            const onclickAttr = button.getAttribute('onclick');
            if (onclickAttr) {
              // 根据不同搜索引擎使用不同的提取正则
              const pattern = ${usingBackupEngine ? '/copyto\\\\("([^"]+)/' : '/wqjs\\\\("([^"]+)/'};
              const match = onclickAttr.match(pattern);
              if (match && match[1]) {
                const url = match[1];
                console.log("按钮#" + index + " 提取到URL: " + url);
                if (url.startsWith('http')) {
                  AppChannel.postMessage(url);
                  foundUrls++;
                }
              }
            }
          });
          
          // 记录页面中表格的数量和结构
          const tables = document.querySelectorAll('table');
          console.log("页面中共有 " + tables.length + " 个表格");
          
          // 尝试定位包含媒体链接的表格
          for (let i = 0; i < tables.length; i++) {
            const rows = tables[i].querySelectorAll('tr');
            console.log("表格 #" + i + " 包含 " + rows.length + " 行");
            
            // 检查表格是否包含可能的媒体链接
            const possibleLinkCells = tables[i].querySelectorAll('td a, td[onclick], td img[onclick]');
            console.log("表格 #" + i + " 包含 " + possibleLinkCells.length + " 个可能的链接单元格");
          }
          
          console.log("通过JavaScript通道发送了 " + foundUrls + " 个媒体链接");
        })();
      ''');
      
      // 等待JavaScript执行完成
      LogUtil.i('SousuoParser._extractMediaLinks - 等待JavaScript执行完成 (500ms)');
      await Future.delayed(Duration(milliseconds: 500));
      
      // 如果没有通过JavaScript通道获取到链接，尝试从HTML中提取
      if (foundStreams.isEmpty || forceDeepExtract) {
        LogUtil.i('SousuoParser._extractMediaLinks - 通过JavaScript通道未获取到链接，尝试从HTML中提取');
        
        try {
          final html = await controller.runJavaScriptReturningResult(
            'document.documentElement.outerHTML'
          );
          
          // 清理HTML字符串
          String htmlContent = html.toString();
          LogUtil.i('SousuoParser._extractMediaLinks - 获取到HTML，长度: ${htmlContent.length}');
          
          if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
            htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                      .replaceAll('\\"', '"')
                      .replaceAll('\\n', '\n');
            LogUtil.i('SousuoParser._extractMediaLinks - 清理HTML字符串，处理后长度: ${htmlContent.length}');
          }
          
          // 使用正则表达式提取媒体URL
          final List<RegExp> regexPatterns = [
            // 主搜索引擎正则
            RegExp(r'onclick="wqjs\(&quot;(http[^&]+)&quot;\)'),
            RegExp(r'onclick="wqjs\(\"(http[^\"]+)\"\)'),
            
            // 备用搜索引擎正则
            RegExp(r'onclick="copyto\(&quot;(http[^&]+)&quot;\)'),
            RegExp(r'onclick="copyto\(\"(http[^\"]+)\"\)'),
            
            // 更通用的URL提取模式
            RegExp(r'onclick="[^"]*\([\'"]*(http[^\'\"]+)[\'"]')
          ];
          
          LogUtil.i('SousuoParser._extractMediaLinks - 使用正则表达式从HTML提取媒体链接');
          
          // 对每种正则表达式尝试匹配
          int totalMatches = 0;
          int addedCount = 0;
          
          for (final regex in regexPatterns) {
            final matches = regex.allMatches(htmlContent);
            totalMatches += matches.length;
            
            for (final match in matches) {
              if (match.groupCount >= 1) {
                final mediaUrl = match.group(1)?.trim();
                if (mediaUrl != null && 
                    mediaUrl.isNotEmpty && 
                    !foundStreams.contains(mediaUrl)) {
                  foundStreams.add(mediaUrl);
                  LogUtil.i('SousuoParser._extractMediaLinks - 从HTML提取到媒体链接: $mediaUrl');
                  addedCount++;
                  
                  // 限制提取数量
                  if (foundStreams.length >= _maxStreams) {
                    LogUtil.i('SousuoParser._extractMediaLinks - 已达到最大媒体链接数限制 ${_maxStreams}，停止提取');
                    break;
                  }
                }
              }
            }
            
            // 如果已达到链接数上限，跳出循环
            if (foundStreams.length >= _maxStreams) {
              break;
            }
          }
          
          LogUtil.i('SousuoParser._extractMediaLinks - 正则匹配总结果数: $totalMatches, 成功提取不重复链接: $addedCount');
          
          // 如果正则表达式匹配失败，记录HTML片段
          if (addedCount == 0 && totalMatches == 0) {
            int sampleLength = htmlContent.length > 1000 ? 1000 : htmlContent.length;
            LogUtil.i('SousuoParser._extractMediaLinks - 未找到媒体链接，HTML片段: ${htmlContent.substring(0, sampleLength)}');
          }
        } catch (e, stackTrace) {
          LogUtil.logError('SousuoParser._extractMediaLinks - 提取HTML时出错', e, stackTrace);
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._extractMediaLinks - 提取媒体链接时出错', e, stackTrace);
    }
    
    LogUtil.i('SousuoParser._extractMediaLinks - 提取媒体链接完成，当前列表大小: ${foundStreams.length}');
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      LogUtil.i('SousuoParser._testStreamsAndGetFastest - 无流地址可测试，返回ERROR');
      return 'ERROR';
    }
    
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 开始测试 ${streams.length} 个媒体流地址的响应速度');
    
    // 创建一个取消标记
    final cancelToken = CancelToken();
    
    // 创建一个完成器
    final completer = Completer<String>();
    
    // 记录测试开始时间
    final startTime = DateTime.now();
    
    // 测试结果
    final Map<String, int> results = {};
    
    // 为每个流创建一个测试任务
    final tasks = streams.map((streamUrl) async {
      try {
        LogUtil.i('SousuoParser._testStreamsAndGetFastest - 开始测试流地址: $streamUrl');
        
        // 发送请求检查流可用性
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'HEAD',  // 使用HEAD请求更快速检测
            responseType: ResponseType.bytes,
            receiveDataWhenStatusError: true,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
            extra: {
              'connectTimeout': Duration(seconds: _httpRequestTimeoutSeconds),
              'receiveTimeout': Duration(seconds: _httpRequestTimeoutSeconds),
            },
          ),
          cancelToken: cancelToken,
          retryCount: 0,
        );
        
        // 如果请求成功，记录响应时间
        if (response != null) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          results[streamUrl] = responseTime;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 流地址 $streamUrl 响应成功，响应时间: ${responseTime}ms');
          
          // 如果这是第一个响应的流，完成任务
          if (!completer.isCompleted) {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 找到第一个可用流: $streamUrl');
            completer.complete(streamUrl);
            // 取消其他请求
            cancelToken.cancel('已找到可用流');
          }
        }
      } catch (e) {
        LogUtil.e('SousuoParser._testStreamsAndGetFastest - 测试流地址 $streamUrl 时出错');
      }
    }).toList();
    
    // 等待所有任务完成或超时
    try {
      // 设置测试超时
      Timer(Duration(seconds: _httpRequestTimeoutSeconds + 1), () {
        if (!completer.isCompleted) {
          if (results.isNotEmpty) {
            // 找出响应最快的流
            String fastestStream = results.entries
                .reduce((a, b) => a.value < b.value ? a : b)
                .key;
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，选择响应最快的流: $fastestStream');
            completer.complete(fastestStream);
          } else {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，无可用结果，返回ERROR');
            completer.complete('ERROR');
          }
          
          // 取消所有未完成的请求
          cancelToken.cancel('测试超时');
        }
      });
      
      // 等待任务完成
      await Future.wait(tasks);
      
      // 如果completer未完成（可能是所有流都测试失败），返回ERROR
      if (!completer.isCompleted) {
        LogUtil.i('SousuoParser._testStreamsAndGetFastest - 所有流测试完成，但无可用结果，返回ERROR');
        completer.complete('ERROR');
      }
    } catch (e) {
      LogUtil.e('SousuoParser._testStreamsAndGetFastest - 测试流地址时发生错误');
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找出响应最快的流
          String fastestStream = results.entries
              .reduce((a, b) => a.value < b.value ? a : b)
              .key;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 出错后选择响应最快的流: $fastestStream');
          completer.complete(fastestStream);
        } else {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 出错且无可用结果，返回ERROR');
          completer.complete('ERROR');
        }
      }
    }
    
    // 返回结果
    final result = await completer.future;
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，返回结果: $result');
    return result;
  }
  
  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    LogUtil.i('SousuoParser._disposeWebView - 开始清理WebView资源');
    
    try {
      // 加载空白页面
      await controller.loadHtmlString('<html><body></body></html>');
      
      // 清除历史记录
      await controller.clearLocalStorage();
      await controller.clearCache();
      
      LogUtil.i('SousuoParser._disposeWebView - WebView资源清理完成');
    } catch (e) {
      LogUtil.e('SousuoParser._disposeWebView - 清理WebView资源时出错: $e');
    }
  }
}
