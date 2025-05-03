import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static const String _baseUrl = 'https://tonkiang.us/';
  static const String _baseHost = 'tonkiang.us'; // 目标网站主机名
  static const int _timeoutSeconds = 30; // 搜索超时时间
  static const int _maxStreams = 6; // 最大提取的流地址数量
  static const int _httpRequestTimeoutSeconds = 5; // 请求超时时间
  
  /// 解析搜索页面
  static Future<String> parse(String url) async {
    final completer = Completer<String>();
    final List<String> foundStreams = []; // 存储找到的媒体流地址
    Timer? timeoutTimer;
    
    try {
      // 从URL中提取搜索关键词
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      LogUtil.i('开始搜索关键词: $searchKeyword');
      
      // 创建WebView控制器
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      
      // 设置拦截器拦截图片、CSS和非目标域名的请求
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('页面开始加载: $pageUrl');
        },
        onPageFinished: (String pageUrl) async {
          LogUtil.i('页面加载完成: $pageUrl');
          
          // 获取当前URL
          String? currentUrl = await controller.currentUrl();
          
          // 如果是首页，填写并提交搜索表单
          if (currentUrl != null && (currentUrl == _baseUrl || currentUrl.startsWith('${_baseUrl}?'))) {
            LogUtil.i('检测到首页，准备提交搜索');
            
            // 使用JavaScript填写搜索框并提交表单
            await controller.runJavaScript('''
              (function() {
                const searchInput = document.getElementById('search');
                const form = document.getElementById('form1');
                
                if (searchInput && form) {
                  // 填写搜索关键词
                  searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
                  
                  // 触发提交
                  const submitButton = document.querySelector('input[type="submit"]');
                  if (submitButton) {
                    submitButton.click();
                  } else {
                    form.submit();
                  }
                  
                  console.log('已提交搜索表单');
                  return true;
                } else {
                  console.log('未找到搜索表单元素');
                  return false;
                }
              })();
            ''');
            
            // 延迟一下等待结果加载
            await Future.delayed(Duration(seconds: 1));
          } else {
            // 可能是结果页面，尝试提取媒体流地址
            LogUtil.i('可能是结果页面，尝试提取流媒体地址');
            
            // 使用JavaScript提取带有class="tuan"的tba标签内容
            final jsResult = await controller.runJavaScriptReturningResult('''
              (function() {
                // 查找所有class为tuan的tba元素
                const linkElements = document.querySelectorAll('tba.tuan');
                const links = [];
                
                // 提取内容
                for (let i = 0; i < linkElements.length; i++) {
                  const link = linkElements[i].textContent.trim();
                  if (link.startsWith('http')) {
                    links.push(link);
                  }
                }
                
                console.log('找到 ' + links.length + ' 个媒体流地址');
                return JSON.stringify(links);
              })();
            ''');
            
            // 处理JavaScript返回结果 - 转换成Dart列表
            final String jsonString = jsResult.toString();
            LogUtil.i('JavaScript返回结果: $jsonString');
            
            if (jsonString.startsWith('"[') && jsonString.endsWith(']"')) {
              // 去除多余的引号并解析JSON
              String cleanJsonString = jsonString.substring(1, jsonString.length - 1)
                                       .replaceAll('\\"', '"');
              
              try {
                List<dynamic> jsonList = json.decode(cleanJsonString);
                
                for (final urlString in jsonList) {
                  if (urlString is String && 
                      urlString.startsWith('http') && 
                      !foundStreams.contains(urlString)) {
                    LogUtil.i('添加媒体链接: $urlString');
                    foundStreams.add(urlString);
                    
                    // 限制提取的URL数量
                    if (foundStreams.length >= _maxStreams) {
                      break;
                    }
                  }
                }
              } catch (e) {
                LogUtil.e('解析JSON失败: $e');
              }
            }
            
            // 如果没有通过JavaScript找到链接，尝试获取HTML并用正则表达式提取
            if (foundStreams.isEmpty) {
              LogUtil.i('通过JavaScript未找到链接，尝试正则表达式提取');
              
              final htmlContent = await controller.runJavaScriptReturningResult(
                'document.documentElement.outerHTML'
              );
              
              // 处理返回的HTML (去除引号)
              String html = htmlContent.toString();
              if (html.startsWith('"') && html.endsWith('"')) {
                html = html.substring(1, html.length - 1)
                       .replaceAll('\\"', '"')
                       .replaceAll('\\n', '\n');
              }
              
              // 使用简单的正则表达式提取tba class="tuan"的内容
              final RegExp tbaRegex = RegExp(r'<tba class="tuan">\s*(http[^<]+)</tba>');
              final matches = tbaRegex.allMatches(html);
              
              for (final match in matches) {
                if (match.groupCount >= 1) {
                  final mediaUrl = match.group(1)?.trim();
                  if (mediaUrl != null && 
                      mediaUrl.isNotEmpty && 
                      !foundStreams.contains(mediaUrl)) {
                    LogUtil.i('通过正则表达式添加媒体链接: $mediaUrl');
                    foundStreams.add(mediaUrl);
                    
                    // 限制提取的URL数量
                    if (foundStreams.length >= _maxStreams) {
                      break;
                    }
                  }
                }
              }
            }
            
            // 如果找到了足够的媒体流地址，开始测试并完成任务
            if (foundStreams.isNotEmpty) {
              LogUtil.i('找到 ${foundStreams.length} 个媒体流地址，准备测试');
              
              // 取消超时计时器
              timeoutTimer?.cancel();
              
              // 测试并获取最快的流
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  completer.complete(result);
                }
              });
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}');
        },
        // 只允许导航到目标域名
        onNavigationRequest: (NavigationRequest request) {
          final Uri requestUri = Uri.parse(request.url);
          
          if (requestUri.host == _baseHost) {
            return NavigationDecision.navigate;
          }
          
          LogUtil.i('阻止导航到非目标域名: ${request.url}');
          return NavigationDecision.prevent;
        },
      ));
      
      // 添加JavaScript通道用于接收消息
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('收到JavaScript消息: ${message.message}');
          
          // 如果消息内容是URL，添加到地址列表
          if (message.message.startsWith('http') && 
              !foundStreams.contains(message.message) && 
              foundStreams.length < _maxStreams) {
            foundStreams.add(message.message);
            LogUtil.i('通过JavaScript通道添加媒体链接: ${message.message}');
          }
        },
      );
      
      // 注入监听脚本
      await controller.runJavaScript('''
        // 监听DOM变化查找媒体链接
        const observer = new MutationObserver(function() {
          const links = document.querySelectorAll('tba.tuan');
          links.forEach(function(link) {
            const url = link.textContent.trim();
            if (url.startsWith('http')) {
              AppChannel.postMessage(url);
            }
          });
        });
        
        // 观察整个文档
        observer.observe(document.documentElement, { 
          childList: true, 
          subtree: true 
        });
        
        // 定期检查页面内容
        setInterval(function() {
          const links = document.querySelectorAll('tba.tuan');
          if (links.length > 0) {
            console.log('定期检查: 找到 ' + links.length + ' 个媒体链接');
            links.forEach(function(link) {
              const url = link.textContent.trim();
              if (url.startsWith('http')) {
                AppChannel.postMessage(url);
              }
            });
          }
        }, 1000);
      ''');
      
      // 加载初始页面
      await controller.loadRequest(Uri.parse(_baseUrl));
      
      // 设置超时
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        if (!completer.isCompleted) {
          LogUtil.i('等待搜索结果超时，总共找到 ${foundStreams.length} 个媒体流地址');
          
          if (foundStreams.isEmpty) {
            completer.complete('ERROR');
          } else {
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              completer.complete(result);
            });
          }
        }
      });
      
      // 等待结果
      final result = await completer.future;
      
      // 清理WebView资源
      await _disposeWebView(controller);
      
      return result;
      
    } catch (e, stackTrace) {
      LogUtil.logError('解析搜索页面失败', e, stackTrace);
      
      if (!completer.isCompleted) {
        if (foundStreams.isEmpty) {
          completer.complete('ERROR');
        } else {
          _testStreamsAndGetFastest(foundStreams).then((String result) {
            completer.complete(result);
          });
        }
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      timeoutTimer?.cancel();
      
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    }
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) return 'ERROR';
    
    LogUtil.i('开始测试 ${streams.length} 个媒体流地址的响应速度');
    
    // 创建一个取消标记，用于在找到第一个可用流后取消其他请求
    final cancelToken = CancelToken();
    
    // 创建一个完成器，用于获取第一个响应的流
    final completer = Completer<String>();
    
    // 记录测试开始时间
    final startTime = DateTime.now();
    
    // 测试结果，包含URL和响应时间
    final Map<String, int> results = {};
    
    // 为每个流创建一个测试任务
    final List<Future<void>> tasks = streams.map((streamUrl) async {
      try {
        // 发送请求检查流可用性
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'GET',
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
          LogUtil.i('流地址 $streamUrl 响应成功，时间: ${responseTime}ms');
          
          // 如果这是第一个响应的流，完成任务
          if (!completer.isCompleted) {
            completer.complete(streamUrl);
            // 取消其他请求
            cancelToken.cancel('已找到可用流');
          }
        }
      } catch (e) {
        LogUtil.i('流地址 $streamUrl 请求出错: $e');
      }
    }).toList();
    
    // 添加超时处理
    final timeoutTimer = Timer(Duration(seconds: _httpRequestTimeoutSeconds * 2), () {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找到响应最快的流
          final sortedEntries = results.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          
          completer.complete(sortedEntries.first.key);
        } else if (streams.isNotEmpty) {
          // 如果没有可用的流，返回第一个
          completer.complete(streams.first);
        } else {
          completer.complete('ERROR');
        }
      }
    });
    
    // 等待所有任务完成或被取消
    await Future.wait(tasks).catchError((_) {
      // 忽略取消错误
    });
    
    // 取消超时计时器
    timeoutTimer.cancel();
    
    // 如果没有完成，使用最佳流完成
    if (!completer.isCompleted) {
      if (results.isNotEmpty) {
        // 找到响应最快的流
        final sortedEntries = results.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        
        completer.complete(sortedEntries.first.key);
      } else if (streams.isNotEmpty) {
        // 如果没有可用的流，返回第一个
        completer.complete(streams.first);
      } else {
        completer.complete('ERROR');
      }
    }
    
    return completer.future;
  }
  
  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.loadRequest(Uri.parse('about:blank'));
    } catch (e) {
      LogUtil.e('清理WebView资源失败: $e');
    }
  }
}
