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
    final searchState = {
      'searchKeyword': '',
      'activeEngine': 'primary',
      'searchSubmitted': false,
      'startTimeMs': DateTime.now().millisecondsSinceEpoch,
      'engineSwitched': false, // 记录是否已切换引擎
      'primaryEngineLoadFailed': false, // 新增：记录主引擎是否加载失败
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
                    } else if (isPrimaryEngine && foundStreams.isEmpty && !completer.isCompleted) {
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
              if (isPrimaryEngine && !searchState['engineSwitched']) {
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
            } else if (isPrimaryEngine && afterExtractCount == 0 && !searchState['engineSwitched']) {
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
              if (searchState['searchSubmitted'] == false && !searchState['engineSwitched']) {
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
                if (searchState['activeEngine'] == 'primary' && !searchState['engineSwitched']) {
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
            !searchState['engineSwitched'] &&
            !searchState['primaryEngineLoadFailed']) {
          
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
            if (searchState['activeEngine'] == 'primary' && !searchState['engineSwitched']) {
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
