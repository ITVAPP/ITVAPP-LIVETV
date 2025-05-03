import 'dart:async';
import 'dart:convert';
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
    Timer? periodicTimer; // 定期检查页面内容的计时器
    bool searchSubmitted = false; // 标记搜索是否已提交
    
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
          
          // 检查是否为首页，如果是则注入资源拦截脚本并自动填充搜索框并提交
          if (pageUrl.startsWith(_baseUrl) && !searchSubmitted) {
            try {
              // 注入阻止图片和CSS加载的脚本
              await controller.runJavaScript('''
                // 禁止加载图片和CSS
                (function() {
                  // 创建一个MutationObserver监听DOM变化
                  const observer = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                      if (mutation.addedNodes) {
                        mutation.addedNodes.forEach(function(node) {
                          // 处理图片元素
                          if (node.tagName === 'IMG') {
                            node.src = '';
                            node.style.display = 'none';
                          }
                          
                          // 禁用所有样式表
                          if (node.tagName === 'LINK' && node.rel === 'stylesheet') {
                            node.href = '';
                            node.disabled = true;
                          }
                        });
                      }
                    });
                  });
                  
                  // 开始监听整个文档
                  observer.observe(document, { childList: true, subtree: true });
                  
                  // 立即处理当前已存在的图片和样式表
                  document.querySelectorAll('img').forEach(img => {
                    img.src = '';
                    img.style.display = 'none';
                  });
                  
                  document.querySelectorAll('link[rel="stylesheet"]').forEach(link => {
                    link.href = '';
                    link.disabled = true;
                  });
                })();
              ''');
              
              // 使用JavaScript检测表单元素并直接提交搜索
              final hasFormResult = await controller.runJavaScriptReturningResult('''
                (function() {
                  const searchInput = document.getElementById('search');
                  const form = document.getElementById('form1');
                  
                  if (searchInput && form) {
                    // 元素已准备好，填充值
                    searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
                    
                    // 手动触发搜索按钮点击事件
                    const submitButton = document.querySelector('input[type="submit"]');
                    if (submitButton) {
                      submitButton.click();
                      return true;
                    } else {
                      // 如果没有提交按钮，尝试直接提交表单
                      form.submit();
                      return true;
                    }
                  }
                  return false;
                })();
              ''');
              
              // 检查表单是否已提交
              if (hasFormResult.toString() == 'true') {
                LogUtil.i('成功提交搜索表单: $searchKeyword');
                searchSubmitted = true;
              } else {
                LogUtil.w('未找到搜索表单，将在稍后重试');
              }
            } catch (e) {
              LogUtil.e('执行JavaScript时出错: $e');
            }
          }
          
          // 设置定期检查页面内容的计时器，不论页面URL如何
          // 这样可以保证即使URL没有变化或不符合预期格式，也能捕获内容变化
          if (periodicTimer == null) {
            periodicTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
              try {
                // 定期检查HTML内容
                final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
                
                // 处理返回的HTML (去除引号)
                String htmlContent = html.toString();
                if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
                  htmlContent = htmlContent.substring(1, htmlContent.length - 1);
                  // 处理转义字符
                  htmlContent = htmlContent.replaceAll('\\"', '"').replaceAll('\\n', '\n');
                }
                
                LogUtil.i('定期检查页面内容中...');
                
                // 检查当前URL
                final currentUrl = await controller.currentUrl();
                LogUtil.i('当前页面URL: $currentUrl');
                
                // 输出页面部分内容以便调试
                await controller.runJavaScript('''
                  console.log("页面包含<tba class='tuanga'>元素: " + (document.querySelectorAll('tba.tuanga').length > 0));
                  console.log("表单状态: " + (document.getElementById('form1') ? "存在" : "不存在"));
                  console.log("搜索框状态: " + (document.getElementById('search') ? "存在" : "不存在"));
                ''');
                
                // 如果仍在主页且还未成功提交搜索，再次尝试提交
                if (!searchSubmitted && currentUrl.startsWith(_baseUrl)) {
                  await controller.runJavaScript('''
                    (function() {
                      const searchInput = document.getElementById('search');
                      const form = document.getElementById('form1');
                      
                      if (searchInput && form) {
                        searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
                        console.log("再次尝试提交搜索...");
                        
                        // 模拟用户操作触发事件
                        searchInput.dispatchEvent(new Event('change', { bubbles: true }));
                        searchInput.dispatchEvent(new Event('input', { bubbles: true }));
                        
                        // 尝试多种方式提交
                        const submitButton = document.querySelector('input[type="submit"]');
                        if (submitButton) {
                          submitButton.click();
                        } else {
                          // 如果没有提交按钮，尝试直接提交表单
                          form.submit();
                        }
                      }
                    })();
                  ''');
                  searchSubmitted = true;
                  LogUtil.i('重新尝试提交搜索表单');
                }
                
                // 使用正则表达式提取<tba class="tuanga">元素中的URL
                final foundUrls = _extractStreamUrls(htmlContent);
                
                if (foundUrls.isNotEmpty) {
                  LogUtil.i('在页面内容中找到 ${foundUrls.length} 个流媒体链接');
                  
                  for (final mediaUrl in foundUrls) {
                    if (!foundStreams.contains(mediaUrl)) {
                      LogUtil.i('检测到媒体链接: $mediaUrl');
                      foundStreams.add(mediaUrl);
                    }
                    
                    // 限制提取的URL数量
                    if (foundStreams.length >= _maxStreams) {
                      break;
                    }
                  }
                  
                  // 如果找到了足够的URL，取消定期检查计时器
                  if (foundStreams.isNotEmpty) {
                    timer.cancel();
                    periodicTimer = null;
                    
                    if (!completer.isCompleted) {
                      LogUtil.i('已找到 ${foundStreams.length} 个媒体流地址，准备测试速度');
                      timeoutTimer?.cancel();
                      
                      _testStreamsAndGetFastest(foundStreams).then((String result) {
                        if (!completer.isCompleted) {
                          completer.complete(result);
                        }
                      });
                    }
                  }
                } else {
                  LogUtil.i('未在当前页面内容中找到流媒体链接');
                  
                  // 检查是否在结果页面但未找到链接
                  if (currentUrl.contains('?') && currentUrl != _baseUrl) {
                    // 可能需要特殊处理一些情况，例如没有结果或结果格式变化
                    LogUtil.w('在结果页面但未找到流媒体链接，可能需要调整解析逻辑');
                  }
                }
              } catch (e) {
                LogUtil.e('定期检查页面内容时出错: $e');
              }
            });
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}');
        },
        // 拦截非目标域名的请求、图片和CSS
        onNavigationRequest: (NavigationRequest request) {
          final Uri requestUri = Uri.parse(request.url);
          
          // 允许导航到目标域名
          if (requestUri.host == _baseHost) {
            return NavigationDecision.navigate;
          }
          
          // 阻止导航到其他域名
          LogUtil.i('阻止导航到非目标域名: ${request.url}');
          return NavigationDecision.prevent;
        },
        // 拦截资源加载
        onUrlChange: (UrlChange change) {
          LogUtil.i('URL变更: ${change.url}');
        },
      ));
      
      // 添加JavaScript通道，用于从JavaScript回调
      await controller.addJavaScriptChannel(
        'FlutterCallback',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('JavaScript回调: ${message.message}');
          
          // 如果回调包含流媒体URL
          if (message.message.startsWith('http')) {
            final urls = message.message.split(',');
            for (final url in urls) {
              if (url.trim().startsWith('http') && !foundStreams.contains(url.trim())) {
                foundStreams.add(url.trim());
                LogUtil.i('通过JavaScript回调获取到流媒体URL: ${url.trim()}');
              }
            }
            
            // 如果找到足够的URL，开始测试
            if (foundStreams.length >= _maxStreams && !completer.isCompleted) {
              timeoutTimer?.cancel();
              periodicTimer?.cancel();
              
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  completer.complete(result);
                }
              });
            }
          }
        },
      );
      
      // 注入JavaScript帮助主动提取链接并回调
      await controller.runJavaScript('''
        // 定期扫描DOM查找流媒体链接
        setInterval(function() {
          const links = document.querySelectorAll('tba.tuanga');
          if (links && links.length > 0) {
            const urls = [];
            links.forEach(function(link) {
              const url = link.textContent.trim();
              if (url.startsWith('http')) {
                urls.push(url);
              }
            });
            
            if (urls.length > 0) {
              FlutterCallback.postMessage(urls.join(','));
            }
          }
        }, 1000);
      ''');
      
      // 加载初始页面
      await controller.loadRequest(Uri.parse(_baseUrl));
      
      // 设置超时
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        if (!completer.isCompleted) {
          LogUtil.i('等待搜索结果超时，总共找到 ${foundStreams.length} 个媒体流地址');
          periodicTimer?.cancel();
          _handleTimeout(foundStreams, completer);
        }
      });
      
      // 等待结果
      final result = await completer.future;
      
      // 清理WebView资源
      await _disposeWebView(controller);
      
      return result;
      
    } catch (e, stackTrace) {
      LogUtil.logError('解析搜索页面失败', e, stackTrace);
      periodicTimer?.cancel();
      if (!completer.isCompleted) {
        _handleTimeout(foundStreams, completer);
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      // 确保超时计时器被取消
      timeoutTimer?.cancel();
      periodicTimer?.cancel();
      
      // 如果由于某种原因completer仍未完成，则完成它
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    }
  }
  
  /// 从HTML内容中提取流媒体URL
  static List<String> _extractStreamUrls(String htmlContent) {
    final List<String> urls = [];
    
    // 使用多个不同的正则表达式模式以增加匹配的可能性
    final patterns = [
      // 原始的提取模式
      RegExp(r'<tba class="tuanga">\s*(http[^<]+)</tba>'),
      
      // 不带空格的变体
      RegExp(r'<tba class="tuanga">(http[^<]+)</tba>'),
      
      // 带有单引号的变体
      RegExp(r"<tba class='tuanga'>\s*(http[^<]+)</tba>"),
      
      // 更宽松的匹配
      RegExp(r'<tba[^>]*class=["\']tuanga["\'][^>]*>\s*(http[^<]+)</tba>'),
      
      // 尝试匹配所有可能的流媒体URL格式
      RegExp(r'(https?://[^"\'\s<>]+\.(?:m3u8|mp4|ts|flv|rtmp)[^"\'\s<>]*)'),
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(htmlContent);
      
      for (final match in matches) {
        if (match.groupCount >= 1) {
          final mediaUrl = match.group(1)?.trim();
          if (mediaUrl != null && mediaUrl.isNotEmpty && mediaUrl.startsWith('http')) {
            if (!urls.contains(mediaUrl)) {
              urls.add(mediaUrl);
            }
          }
        }
      }
    }
    
    // 输出一些调试信息
    if (urls.isEmpty) {
      // 检查HTML是否包含流媒体关键词
      final containsM3u8 = htmlContent.contains('m3u8');
      final containsTuanga = htmlContent.contains('tuanga');
      LogUtil.i('HTML内容中包含m3u8关键词: $containsM3u8, 包含tuanga关键词: $containsTuanga');
      
      // 如果包含关键词但没有匹配到URL，输出部分HTML内容以便调试
      if (containsM3u8 || containsTuanga) {
        // 找到关键词周围的内容
        int startIndex = -1;
        int endIndex = -1;
        
        if (containsTuanga) {
          startIndex = htmlContent.indexOf('tuanga');
          if (startIndex > 50) startIndex -= 50;
          endIndex = startIndex + 300;
          if (endIndex > htmlContent.length) endIndex = htmlContent.length;
        } else if (containsM3u8) {
          startIndex = htmlContent.indexOf('m3u8');
          if (startIndex > 50) startIndex -= 50;
          endIndex = startIndex + 300;
          if (endIndex > htmlContent.length) endIndex = htmlContent.length;
        }
        
        if (startIndex >= 0 && endIndex > startIndex) {
          final snippet = htmlContent.substring(startIndex, endIndex);
          LogUtil.i('未能提取URL，但找到了相关内容片段: $snippet');
        }
      }
    }
    
    return urls;
  }
  
  /// 处理超时或异常情况
  static void _handleTimeout(List<String> foundStreams, Completer<String> completer) {
    if (foundStreams.isEmpty) {
      completer.complete('ERROR');
    } else {
      _testStreamsAndGetFastest(foundStreams).then((String result) {
        completer.complete(result);
      });
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
    final List<String> failedUrls = [];
    
    // 为每个流创建一个测试任务
    final List<Future<void>> tasks = streams.map((streamUrl) async {
      try {
        // 使用getRequestWithResponse发起请求，检查资源是否可用
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            // 使用HEAD方法可能被某些服务器拒绝，改用GET但只获取前8KB数据
            method: 'GET',
            responseType: ResponseType.bytes,
            receiveDataWhenStatusError: true,
            followRedirects: true,
            extra: {
              'connectTimeout': Duration(seconds: _httpRequestTimeoutSeconds),
              'receiveTimeout': Duration(seconds: _httpRequestTimeoutSeconds),
            },
          ),
          cancelToken: cancelToken,
          retryCount: 0, // 不重试，以加快测试速度
        );
        
        // 如果请求成功，记录响应时间
        if (response != null && 
            (response.statusCode == 200 || response.statusCode == 206 || response.statusCode == 302)) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          results[streamUrl] = responseTime;
          LogUtil.i('流地址 $streamUrl 响应时间: ${responseTime}ms');
          
          // 如果这是第一个响应的流，则完成任务
          if (!completer.isCompleted) {
            completer.complete(streamUrl);
            // 取消其他请求
            cancelToken.cancel('已找到可用流');
          }
        } else {
          failedUrls.add(streamUrl);
          LogUtil.i('流地址 $streamUrl 请求失败，状态码: ${response?.statusCode}');
        }
      } catch (e) {
        failedUrls.add(streamUrl);
        LogUtil.i('流地址 $streamUrl 请求出错: $e');
      }
    }).toList();
    
    // 添加超时处理
    final timeoutTimer = Timer(Duration(seconds: _httpRequestTimeoutSeconds * 2), () {
      if (!completer.isCompleted) {
        _completeWithBestStream(completer, results, streams);
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
      _completeWithBestStream(completer, results, streams);
    }
    
    return completer.future;
  }
  
  /// 根据测试结果完成Completer
  static void _completeWithBestStream(
    Completer<String> completer, 
    Map<String, int> results, 
    List<String> streams
  ) {
    if (results.isNotEmpty) {
      // 找到响应最快的流
      String fastestUrl = _getFastestStream(results);
      LogUtil.i('使用响应最快的流地址: $fastestUrl (${results[fastestUrl]}ms)');
      completer.complete(fastestUrl);
    } else if (streams.isNotEmpty) {
      // 如果所有请求都失败，则返回第一个流
      LogUtil.i('所有请求失败，返回第一个流地址: ${streams.first}');
      completer.complete(streams.first);
    } else {
      completer.complete('ERROR');
    }
  }
  
  /// 获取响应最快的流地址
  static String _getFastestStream(Map<String, int> results) {
    if (results.isEmpty) return 'ERROR';
    
    // 按响应时间排序
    final sortedEntries = results.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    
    // 返回响应最快的流地址
    return sortedEntries.first.key;
  }
  
  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.runJavaScript('''
        // 清理全局变量
        // 清理定时器
        for (let i = 1; i < 10000; i++) {
          clearTimeout(i);
          clearInterval(i);
        }
        
        // 移除事件监听器
        const oldBody = document.body;
        const newBody = document.createElement('body');
        if (oldBody && oldBody.parentNode) {
          oldBody.parentNode.replaceChild(newBody, oldBody);
        }
        
        // 清理DOM内容
        document.documentElement.innerHTML = '';
      ''');
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.loadRequest(Uri.parse('about:blank'));
    } catch (e) {
      LogUtil.e('清理WebView资源失败: $e');
    }
  }
}
