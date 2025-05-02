import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器
class SousuoParser {
  // 配置常量
  static const String _baseUrl = 'https://tonkiang.us/';
  static const String _baseHost = 'tonkiang.us'; // 目标网站主机名
  static const int _timeoutSeconds = 30; // 搜索超时时间
  static const int _maxStreams = 6; // 最大提取的流地址数量
  static const int _httpRequestTimeoutSeconds = 5; // 请求超时时间
  
  // JavaScript 脚本常量
  static const String _resourceBlockScript = '''
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
              
              // 递归处理子节点
              if (node.childNodes && node.childNodes.length > 0) {
                for (let i = 0; i < node.childNodes.length; i++) {
                  let child = node.childNodes[i];
                  if (child.tagName === 'IMG') {
                    child.src = '';
                    child.style.display = 'none';
                  }
                  if (child.tagName === 'LINK' && child.rel === 'stylesheet') {
                    child.href = '';
                    child.disabled = true;
                  }
                }
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
      
      // 添加样式以确保图片和CSS被禁用
      const style = document.createElement('style');
      style.textContent = 'img { display: none !important; } link[rel="stylesheet"] { display: none !important; }';
      document.head.appendChild(style);
    })();
  ''';
  
  /// 解析搜索页面
  static Future<String> parse(String url) async {
    final completer = Completer<String>();
    final List<String> foundStreams = []; // 存储找到的媒体流地址
    Timer? timeoutTimer; // 超时计时器
    WebViewController? controller; // WebView控制器
    
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
      controller = WebViewController()
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
          if (pageUrl.startsWith(_baseUrl) && !pageUrl.contains('?iptv=')) {
            try {
              // 注入阻止图片和CSS加载的脚本
              await controller!.runJavaScript(_resourceBlockScript);
              
              // 等待DOM完全加载并使用JavaScript检测表单元素是否存在
              await controller.runJavaScript('''
                function waitForElement() {
                  const searchInput = document.getElementById('search');
                  const form = document.getElementById('form1');
                  
                  if (searchInput && form) {
                    // 元素已准备好，填充并提交
                    searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
                    console.log('提交搜索表单...');
                    form.submit();
                  } else {
                    // 元素未准备好，等待一段时间再检查
                    setTimeout(waitForElement, 100);
                  }
                }
                
                // 开始检查元素
                waitForElement();
              ''');
              
              LogUtil.i('自动填充搜索关键词并提交: $searchKeyword');
            } catch (e) {
              LogUtil.e('执行JavaScript时出错: $e');
            }
          } else if (pageUrl.contains('?iptv=') || pageUrl.contains('?')) {
            // 在结果页面，提取HTML并解析
            try {
              final html = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML');
              
              // 处理返回的HTML (去除引号)
              String htmlContent = html.toString();
              if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
                htmlContent = htmlContent.substring(1, htmlContent.length - 1);
                // 处理转义字符
                htmlContent = htmlContent.replaceAll('\\"', '"').replaceAll('\\n', '\n');
              }
              
              // 使用正则表达式提取<tba class="tuanga">元素中的URL
              final foundUrls = _extractStreamUrls(htmlContent);
              
              for (final mediaUrl in foundUrls) {
                if (!foundStreams.contains(mediaUrl)) {
                  LogUtil.i('检测到媒体链接: $mediaUrl');
                  foundStreams.add(mediaUrl);
                  
                  // 限制提取的URL数量
                  if (foundStreams.length >= _maxStreams) {
                    break;
                  }
                }
              }
              
              // 如果找到了足够的URL，立即开始测试
              if (foundStreams.isNotEmpty && !completer.isCompleted) {
                LogUtil.i('已找到 ${foundStreams.length} 个媒体流地址，准备测试速度');
                // 取消超时计时器
                timeoutTimer?.cancel();
                _testStreamsAndGetFastest(foundStreams).then((String result) {
                  if (!completer.isCompleted) {
                    completer.complete(result);
                  }
                });
              }
            } catch (e) {
              LogUtil.e('提取HTML内容时出错: $e');
            }
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
      
      // 设置WebView允许拦截的资源类型
      await controller.setWebViewCookie(WebViewCookie(
        name: 'blockResources',
        value: 'true',
        domain: _baseHost
      ));
      
      // 注入拦截图片和CSS的用户脚本
      await controller.addJavaScriptChannel(
        'ResourceBlocker',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('资源拦截: ${message.message}');
        },
      );
      
      // 加载用户脚本
      await controller.addUserScript(
        UserJavaScriptString(
          source: _resourceBlockScript,
          injectionTime: UserJavaScriptInjectionTime.atDocumentStart,
        ),
      );
      
      // 加载初始页面
      await controller.loadRequest(Uri.parse(_baseUrl));
      
      // 设置超时
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        if (!completer.isCompleted) {
          LogUtil.i('等待搜索结果超时，总共找到 ${foundStreams.length} 个媒体流地址');
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
      if (!completer.isCompleted) {
        _handleTimeout(foundStreams, completer);
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      // 确保超时计时器被取消
      timeoutTimer?.cancel();
      
      // 如果由于某种原因completer仍未完成，则完成它
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    }
  }

  /// 从HTML内容中提取流媒体URL
  static List<String> _extractStreamUrls(String htmlContent) {
    final List<String> urls = [];
    final RegExp urlRegex = RegExp(r'<tba class="tuanga">\s*(http[^<]+)</tba>');
    final matches = urlRegex.allMatches(htmlContent);
    
    for (final match in matches) {
      if (match.groupCount >= 1) {
        final mediaUrl = match.group(1)?.trim();
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          urls.add(mediaUrl);
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
        // 发起HEAD请求，检查资源是否可用
        final response = await HttpUtil().headRequest(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            sendTimeout: Duration(seconds: _httpRequestTimeoutSeconds),
            receiveTimeout: Duration(seconds: _httpRequestTimeoutSeconds),
          ),
          cancelToken: cancelToken,
        );
        
        // 如果请求成功，记录响应时间
        if (response != null) {
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
          LogUtil.i('流地址 $streamUrl 请求失败');
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
