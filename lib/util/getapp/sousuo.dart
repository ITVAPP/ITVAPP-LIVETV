import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器，支持主备两个搜索引擎
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用搜索引擎URL
  
  // 配置参数
  static const int _maxStreams = 8; // 最大提取的媒体流数量 SharePoint
  static const int _formSubmitWaitMs = 1000; // 表单提交前等待时间(毫秒)
  static const int _streamTestTimeoutSeconds = 8; // 媒体流测试超时时间(秒)
  static const int _backupEngineTimeoutSeconds = 20; // 备用引擎总超时时间(秒)
  static const int _primaryEngineTimeoutSeconds = 15; // 主引擎超时时间(秒)
  static const int _inputCheckIntervalMs = 1000; // 输入框检查间隔(毫秒)
  static const int _maxInputCheckAttempts = 30; // 最大输入框检查次数
  static const int _linkExtractionTimeoutSeconds = 10; // 链接提取超时时间(秒)

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final completer = Completer<String>(); // 异步任务完成器
    final List<String> foundStreams = []; // 存储提取的媒体流地址
    WebViewController? controller; // WebView控制器
    bool isResourceCleaned = false; // 资源清理标志
    Timer? backupEngineTimer; // 备用引擎超时计时器
    Timer? primaryEngineTimer; // 主引擎超时计时器
    Timer? linkExtractionTimer; // 链接提取超时计时器

    // 状态管理
    final Map<String, dynamic> state = {
      'currentEngine': 'primary', // 当前使用的搜索引擎
      'searchKeyword': '', // 搜索关键词
      'primaryEngineFailed': false, // 主引擎是否失败
      'formSubmissionInProgress': false, // 表单提交中
      'formSubmitted': false, // 表单已提交
      'formResultReceived': false, // 表单结果已接收
      'linkExtractionDone': false, // 链接提取完成
      'startTime': DateTime.now().millisecondsSinceEpoch, // 解析开始时间
      'navigationCount': 0, // 页面导航计数
      'lastPageUrl': '', // 上次页面URL
      'expectingFormResult': false, // 期待表单结果
    };
    
    /// 获取布尔状态值，带默认值
    bool getBoolState(String key, {bool defaultValue = false}) {
      return state[key] is bool ? state[key] as bool : defaultValue;
    }
    
    /// 获取字符串状态值，带默认值
    String getStringState(String key, {String defaultValue = ''}) {
      return state[key] is String ? state[key] as String : defaultValue;
    }
    
    /// 获取整数状态值，带默认值
    int getIntState(String key, {int defaultValue = 0}) {
      return state[key] is int ? state[key] as int : defaultValue;
    }
    
    /// 清理WebView和计时器资源
    Future<void> cleanupResources() async {
      if (isResourceCleaned) return;
      isResourceCleaned = true;
      LogUtil.i('开始清理资源');
      
      try {
        backupEngineTimer?.cancel(); // 取消备用引擎计时器
        primaryEngineTimer?.cancel(); // 取消主引擎计时器
        linkExtractionTimer?.cancel(); // 取消链接提取计时器
        if (controller != null) {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
          await Future.delayed(Duration(milliseconds: 300)); // 等待页面加载
          await controller!.clearCache(); // 清除缓存
          await controller!.clearLocalStorage(); // 清除本地存储
          LogUtil.i('清理WebView完成');
          controller = null;
        }
      } catch (e) {
        LogUtil.e('清理资源出错: $e');
      }
    }
    
    /// 切换到备用搜索引擎
    Future<void> switchToBackupEngine() async {
      final isPrimaryEngine = getStringState('currentEngine') == 'primary';
      final alreadyFailed = getBoolState('primaryEngineFailed');
      if (!isPrimaryEngine || alreadyFailed) return;
      LogUtil.i('切换到备用引擎');
      state['currentEngine'] = 'backup';
      state['primaryEngineFailed'] = true;
      state['formSubmitted'] = false;
      state['formResultReceived'] = false;
      state['linkExtractionDone'] = false;
      state['navigationCount'] = 0;
      state['expectingFormResult'] = false;
      if (controller != null) {
        try {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
          await Future.delayed(Duration(milliseconds: 300)); // 等待页面加载
          LogUtil.i('加载备用引擎: $_backupEngine');
          await controller!.loadRequest(Uri.parse(_backupEngine)); // 加载备用引擎页面
          backupEngineTimer = Timer(Duration(seconds: _backupEngineTimeoutSeconds), () {
            if (!completer.isCompleted) {
              LogUtil.i('备用引擎总体超时');
              if (foundStreams.isEmpty) {
                completer.complete('ERROR'); // 无流地址，返回错误
                cleanupResources();
              } else {
                LogUtil.i('备用引擎找到 ${foundStreams.length} 个流，开始测试');
                _testStreamsAndGetFastest(foundStreams).then((result) {
                  if (!completer.isCompleted) {
                    completer.complete(result); // 返回最快流地址
                    cleanupResources();
                  }
                });
              }
            }
          });
        } catch (e) {
          LogUtil.e('切换备用引擎出错: $e');
          if (!completer.isCompleted) {
            completer.complete('ERROR'); // 切换失败，返回错误
            cleanupResources();
          }
        }
      } else {
        LogUtil.e('切换备用引擎时控制器为空');
        if (!completer.isCompleted) {
          completer.complete('ERROR'); // 控制器为空，返回错误
          cleanupResources();
        }
      }
    }
    
    /// 从页面提取媒体流链接
    Future<bool> extractMediaLinks() async {
      if (controller == null) {
        LogUtil.e('提取链接时控制器为空');
        return false;
      }
      LogUtil.i('开始提取媒体链接');
      try {
        final html = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML'); // 获取页面HTML
        String htmlContent = html.toString();
        if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
          htmlContent = htmlContent.substring(1, htmlContent.length - 1).replaceAll('\\"', '"').replaceAll('\\n', '\n'); // 清理HTML内容
        }
        LogUtil.i('获取HTML成功，长度: ${htmlContent.length}');
        final beforeExtractCount = foundStreams.length;
        final RegExp regex = RegExp('onclick="[^"]*?\ $[\'"]*((http|https)://[^\'"\$ \\s]+)'); // 匹配媒体链接
        final matches = regex.allMatches(htmlContent);
        LogUtil.i('找到 ${matches.length} 个链接匹配');
        final Set<String> addedHosts = {}; // 存储已添加的主机地址
        for (final existingUrl in foundStreams) {
          try {
            final uri = Uri.parse(existingUrl);
            addedHosts.add('${uri.host}:${uri.port}'); // 记录主机和端口
          } catch (_) {}
        }
        for (final match in matches) {
          if (match.groupCount >= 1) {
            String? mediaUrl = match.group(1)?.trim();
            if (mediaUrl != null) {
              if (mediaUrl.endsWith('"')) {
                mediaUrl = mediaUrl.substring(0, mediaUrl.length - 6); // 清理URL尾部
              }
              mediaUrl = mediaUrl.replaceAll('&', '&'); // 替换HTML实体
              if (mediaUrl.isNotEmpty) {
                try {
                  final uri = Uri.parse(mediaUrl);
                  final hostKey = '${uri.host}:${uri.port}';
                  if (!addedHosts.contains(hostKey)) {
                    foundStreams.add(mediaUrl); // 添加新媒体链接
                    addedHosts.add(hostKey);
                    LogUtil.i('添加链接: $mediaUrl');
                    if (foundStreams.length >= _maxStreams) {
                      LogUtil.i('达到最大链接数: $_maxStreams');
                      break;
                    }
                  }
                } catch (e) {
                  LogUtil.e('解析URL出错: $e');
                }
              }
            }
          }
        }
        final afterExtractCount = foundStreams.length;
        LogUtil.i('提取完成，新增: ${afterExtractCount - beforeExtractCount}，总数: $afterExtractCount');
        return foundStreams.isNotEmpty; // 返回是否提取到链接
      } catch (e) {
        LogUtil.e('提取链接出错: $e');
        return false;
      }
    }

    try {
      LogUtil.i('从URL提取搜索关键词');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR'; // 缺少关键词，返回错误
      }
      LogUtil.i('提取到搜索关键词: $searchKeyword');
      state['searchKeyword'] = searchKeyword;

      LogUtil.i('创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JavaScript
        ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
      await controller?.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('页面开始加载: $pageUrl');
          state['navigationCount'] = getIntState('navigationCount') + 1;
          if (getBoolState('expectingFormResult') && pageUrl != getStringState('lastPageUrl')) {
            LogUtil.i('检测到表单提交后的页面导航');
            state['formResultReceived'] = true;
            state['expectingFormResult'] = false;
          }
          state['lastPageUrl'] = pageUrl;
        },
        onPageFinished: (String pageUrl) async {
          final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
          final startTimeMs = getIntState('startTime');
          final loadTimeMs = currentTimeMs - startTimeMs;
          LogUtil.i('页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms');
          if (pageUrl == 'about:blank') {
            LogUtil.i('空白页面，忽略');
            return;
          }
          final isPrimaryEngine = _isPrimaryEngine(pageUrl);
          final isBackupEngine = _isBackupEngine(pageUrl);
          if (!isPrimaryEngine && !isBackupEngine) {
            LogUtil.i('未知页面，忽略: $pageUrl');
            return;
          }
          if (getStringState('currentEngine') == 'backup' && isPrimaryEngine) {
            LogUtil.i('已切换备用引擎，忽略主引擎回调');
            return;
          }
          if (isPrimaryEngine) {
            state['currentEngine'] = 'primary';
            LogUtil.i('主引擎页面加载完成');
          } else {
            state['currentEngine'] = 'backup';
            LogUtil.i('备用引擎页面加载完成');
          }

          // 注入自动填充和提交表单的JavaScript
          await controller?.runJavaScript('''
            (function() {
              let searchAttempts = 0;
              const maxAttempts = ${_maxInputCheckAttempts};
              function checkAndSubmitSearch() {
                const searchInput = document.querySelector('input[type="text"], input[name="search"]');
                if (searchInput) {
                  setTimeout(() => {
                    searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}"; // 填充搜索关键词
                    const form = searchInput.closest('form');
                    if (form) {
                      form.submit(); // 提交表单
                      AppChannel.postMessage('FORM_SUBMITTED');
                    } else {
                      const submitButton = document.querySelector('input[type="submit"], button[type="submit"]');
                      if (submitButton) {
                        submitButton.click(); // 点击提交按钮
                        AppChannel.postMessage('FORM_SUBMITTED');
                      } else {
                        AppChannel.postMessage('SUBMIT_BUTTON_NOT_FOUND');
                      }
                    }
                  }, ${_formSubmitWaitMs});
                } else if (searchAttempts < maxAttempts) {
                  searchAttempts++;
                  setTimeout(checkAndSubmitSearch, ${_inputCheckIntervalMs}); // 重试检查输入框
                } else {
                  AppChannel.postMessage('SEARCH_INPUT_NOT_FOUND');
                }
              }

              // 开始检查搜索输入框
              checkAndSubmitSearch();
            })();
          ''');
          LogUtil.i('注入自动填充和提交表单脚本完成');
          
          // 注入DOM监控脚本
          await _injectHelpers(controller!, 'AppChannel');
          int navigationCount = getIntState('navigationCount');
          
          // 表单提交后页面加载完成 - 提取链接
          if (navigationCount >= 2 || getBoolState('formResultReceived')) {
            LogUtil.i('表单提交后页面加载完成，准备提取链接');
            
            // 确保只提取一次
            if (getBoolState('linkExtractionDone')) {
              LogUtil.i('链接已提取过，跳过');
              return;
            }
            
            // 设置链接提取超时
            linkExtractionTimer = Timer(Duration(seconds: _linkExtractionTimeoutSeconds), () {
              if (!getBoolState('linkExtractionDone')) {
                LogUtil.i('链接提取超时');
                if (isPrimaryEngine) {
                  LogUtil.i('主引擎链接提取超时，切换备用引擎');
                  switchToBackupEngine();
                } else {
                  LogUtil.i('备用引擎链接提取超时，返回ERROR');
                  if (!completer.isCompleted) {
                    completer.complete('ERROR');
                    cleanupResources();
                  }
                }
              }
            });

            // 提取链接
            final hasLinks = await extractMediaLinks();
            state['linkExtractionDone'] = true;
            linkExtractionTimer?.cancel();

            if (hasLinks) {
              LogUtil.i('成功提取到${foundStreams.length}个链接，开始测试');
              final result = await _testStreamsAndGetFastest(foundStreams);
              if (!completer.isCompleted) {
                completer.complete(result); // 返回最快流地址
                await cleanupResources();
              }
            } else if (isPrimaryEngine) {
              LogUtil.i('主引擎未提取到链接，切换备用引擎');
              await switchToBackupEngine();
            } else {
              LogUtil.i('备用引擎未提取到链接，返回ERROR');
              if (!completer.isCompleted) {
                completer.complete('ERROR');
                await cleanupResources();
              }
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          if (error.url == null ||
              error.url!.endsWith('.png') || 
              error.url!.endsWith('.jpg') || 
              error.url!.endsWith('.gif') || 
              error.url!.endsWith('.webp') || 
              error.url!.endsWith('.css')) {
            return; // 忽略非关键资源错误
          }
          LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url}');
          bool isCriticalError = [-1, -2, -3, -6, -7, -101, -105, -106].contains(error.errorCode);
          if (getStringState('currentEngine') == 'primary' && 
              error.url != null && 
              error.url!.contains('tonkiang.us') &&
              isCriticalError &&
              !getBoolState('linkExtractionDone')) {
            LogUtil.i('主引擎关键错误，切换备用引擎');
            switchToBackupEngine();
          } else if (getStringState('currentEngine') == 'backup' && 
                     error.url != null && error.url!.contains('foodieguide.com') &&
                     isCriticalError &&
                     !getBoolState('linkExtractionDone')) {
            LogUtil.i('备用引擎关键错误，返回ERROR');
            if (!completer.isCompleted) {
              completer.complete('ERROR');
              cleanupResources();
            }
          }
        },
        onNavigationRequest: (NavigationRequest request) {
          LogUtil.i('收到导航请求: ${request.url}');
          if (getBoolState('expectingFormResult')) {
            LogUtil.i('这可能是表单提交导致的导航');
            state['formResultReceived'] = true;
            state['expectingFormResult'] = false;
          }
          if (getStringState('currentEngine') == 'backup' && _isPrimaryEngine(request.url)) {
            LogUtil.i('阻止主引擎导航: ${request.url}');
            return NavigationDecision.prevent; // 阻止主引擎导航
          }
          return NavigationDecision.navigate;
        },
      ));
      
      await controller?.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('收到JS消息: ${message.message}');
          
          if (message.message.startsWith('http') && foundStreams.length < _maxStreams) {
            try {
              final url = message.message;
              final uri = Uri.parse(url);
              final hostKey = '${uri.host}:${uri.port}';
              
              bool hostExists = foundStreams.any((existingUrl) {
                try {
                  final existingUri = Uri.parse(existingUrl);
                  return '${existingUri.host}:${existingUri.port}' == hostKey;
                } catch (_) {
                  return false;
                }
              });
              
              if (!hostExists) {
                foundStreams.add(url); // 添加新媒体链接
                LogUtil.i('添加链接: $url');
                
                if (foundStreams.length == 1) {
                  LogUtil.i('找到首个链接，开始测试');
                  _testStreamsAndGetFastest(foundStreams).then((result) {
                    if (!completer.isCompleted) {
                      completer.complete(result); // 返回最快流地址
                      cleanupResources();
                    }
                  });
                }
              } else {
                LogUtil.i('跳过重复链接: $url');
              }
            } catch (e) {
              LogUtil.e('处理JS消息出错: $e');
            }
          } else if (message.message == 'DOM_UPDATED' && getBoolState('formResultReceived') && !getBoolState('linkExtractionDone')) {
            LogUtil.i('检测到DOM更新，提取链接');
            extractMediaLinks().then((hasLinks) {
              if (hasLinks) {
                LogUtil.i('DOM更新后找到 ${foundStreams.length} 个链接');
                state['linkExtractionDone'] = true;
                _testStreamsAndGetFastest(foundStreams).then((result) {
                  if (!completer.isCompleted) {
                    completer.complete(result); // 返回最快流地址
                    cleanupResources();
                  }
                });
              }
            });
          } else if (message.message == 'FORM_SUBMITTED') {
            LogUtil.i('收到表单提交确认');
            state['formSubmitted'] = true;
            state['expectingFormResult'] = true;
          } else if (message.message == 'SUBMIT_BUTTON_NOT_FOUND') {
            LogUtil.e('未找到提交按钮');
          } else if (message.message == 'SEARCH_INPUT_NOT_FOUND') {
            LogUtil.e('未找到搜索输入框');
            if (getStringState('currentEngine') == 'primary' && !getBoolState('primaryEngineFailed')) {
              LogUtil.i('主引擎未找到搜索输入框，切换备用引擎');
              switchToBackupEngine();
            } else if (getStringState('currentEngine') == 'backup' && !completer.isCompleted) {
              LogUtil.i('备用引擎未找到搜索输入框，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          }
        },
      );
      LogUtil.i('加载主搜索引擎: $_primaryEngine');
      await controller?.loadRequest(Uri.parse(_primaryEngine)); // 加载主引擎页面
      
      primaryEngineTimer = Timer(Duration(seconds: _primaryEngineTimeoutSeconds), () {
        if (!completer.isCompleted && getStringState('currentEngine') == 'primary') {
          LogUtil.i('主引擎超时，切换到备用引擎');
          switchToBackupEngine();
        }
      });
      final result = await completer.future;
      final endTimeMs = DateTime.now().millisecondsSinceEpoch;
      final startTimeMs = getIntState('startTime');
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}, 总耗时: ${endTimeMs - startTimeMs}ms');
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析过程出错', e, stackTrace);
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('出错但已找到 ${foundStreams.length} 个流，尝试测试');
        final result = await _testStreamsAndGetFastest(foundStreams);
        return result;
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!isResourceCleaned) {
        await cleanupResources(); // 确保资源清理
      }
    }
  }

  /// 注入DOM监控和辅助JavaScript脚本
  static Future<void> _injectHelpers(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM监视器和辅助函数");
          function debounce(func, wait) {
            let timeout;
            return function(...args) {
              clearTimeout(timeout);
              timeout = setTimeout(() => func.apply(this, args), wait);
            };
          }
          const observer = new MutationObserver(debounce(function(mutations) {
            console.log("检测到DOM变化");
            let hasSignificantChanges = false;
            let hasSearchResults = false;
            mutations.forEach(function(mutation) {
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                hasSignificantChanges = true;
                for (let i = 0; i < mutation.addedNodes.length; i++) {
                  const node = mutation.addedNodes[i];
                  if (node.nodeType === 1) {
                    if (node.tagName === 'TABLE' ||
                        (node.classList && (
                          node.classList.contains('result') ||
                          node.classList.contains('item') ||
                          node.classList.contains('search-result')))) {
                      console.log("检测到搜索结果元素");
                      hasSearchResults = true;
                      break;
                    }
                    if (node.querySelector) {
                      const resultElements = node.querySelectorAll('table, .result, .item, .search-result');
                      if (resultElements.length > 0) {
                        console.log("检测到搜索结果子元素");
                        hasSearchResults = true;
                        break;
                      }
                    }
                  }
                }
              }
            });
            if (hasSignificantChanges) {
              console.log("DOM有显著变化，通知应用");
              ${channelName}.postMessage('DOM_UPDATED');
            }
            if (hasSearchResults) {
              console.log("搜索结果已出现，通知应用");
              ${channelName}.postMessage('DOM_UPDATED');
            }
          }, 300));
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            characterData: true
          });
          function addElementListeners() {
            const elements = document.querySelectorAll('[onclick]');
            elements.forEach(function(element) {
              if (!element._hasClickListener) {
                element._hasClickListener = true;
                element.addEventListener('click', function() {
                  window.setTimeout(function() {
                    ${channelName}.postMessage('DOM_UPDATED');
                  }, 300);
                });
              }
            });
            setTimeout(addElementListeners, 2000);
          }
          addElementListeners();
          console.log("初始页面加载完成，通知应用");
          setTimeout(function() {
            ${channelName}.postMessage('DOM_UPDATED');
          }, 1000);
        })();
      ''');
      LogUtil.i('辅助脚本注入成功');
    } catch (e) {
      LogUtil.e('注入辅助脚本出错: $e');
    }
  }

  /// 判断是否为主搜索引擎URL
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 判断是否为备用搜索引擎URL
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 测试媒体流地址并返回最快响应地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR';
    }
    LogUtil.i('测试 ${streams.length} 个流地址');
    final cancelToken = CancelToken(); // 请求取消令牌
    final completer = Completer<String>(); // 测试任务完成器
    final startTime = DateTime.now();
    final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList(); // 优先测试m3u8流
    final otherStreams = streams.where((url) => !url.contains('.m3u8')).toList(); // 其他流
    final prioritizedStreams = [...m3u8Streams, ...otherStreams]; // 优先级排序
    
    // 并行测试流地址
    final tasks = prioritizedStreams.map((streamUrl) async {
      try {
        if (completer.isCompleted) return;
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl), // 设置请求头
            method: 'GET',
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400, // 验证状态码
          ),
          cancelToken: cancelToken,
          retryCount: 1, // 重试一次
        );
        if (response != null && !completer.isCompleted) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          LogUtil.i('流 $streamUrl 响应: ${responseTime}ms');
          completer.complete(streamUrl); // 返回首个有效流
          cancelToken.cancel('已找到可用流');
        }
      } catch (e) {
        LogUtil.e('测试 $streamUrl 出错: $e');
      }
    }).toList();

    // 设置测试超时
    Timer(Duration(seconds: _streamTestTimeoutSeconds), () {
      if (!completer.isCompleted) {
        if (m3u8Streams.isNotEmpty) {
          LogUtil.i('测试超时，返回首个m3u8: ${m3u8Streams.first}');
          completer.complete(m3u8Streams.first);
        } else {
          LogUtil.i('测试超时，返回首个链接: ${streams.first}');
          completer.complete(streams.first);
        }
        cancelToken.cancel('测试超时');
      }
    });

    // 等待所有测试任务完成
    await Future.wait(tasks);

    // 如果还未完成，返回第一个流
    if (!completer.isCompleted) {
      if (m3u8Streams.isNotEmpty) {
        LogUtil.i('无响应，返回首个m3u8: ${m3u8Streams.first}');
        completer.complete(m3u8Streams.first);
      } else {
        LogUtil.i('无响应，返回首个链接: ${streams.first}');
        completer.complete(streams.first);
      }
    }

    return await completer.future; // 返回最快流地址
  }
}
