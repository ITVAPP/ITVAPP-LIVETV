import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static const String _baseUrl = 'https://tonkiang.us/';
  static const String _baseHost = 'tonkiang.us';
  static const int _timeoutSeconds = 30;
  static const int _maxStreams = 6;
  static const int _httpRequestTimeoutSeconds = 5;
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    bool searchSubmitted = false;
    
    try {
      // 提取搜索关键词
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
      
      // 设置导航委托
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('页面开始加载: $pageUrl');
        },
        onPageFinished: (String pageUrl) async {
          LogUtil.i('页面加载完成: $pageUrl');
          
          // 如果是首页且尚未提交搜索
          if (pageUrl.startsWith(_baseUrl) && !searchSubmitted) {
            // 延迟一下确保页面完全加载
            await Future.delayed(Duration(milliseconds: 500));
            
            // 填写搜索表单并提交
            final result = await controller.runJavaScriptReturningResult('''
              (function() {
                // 查找搜索表单和输入框
                const searchInput = document.getElementById('search');
                const form = document.getElementById('form1');
                
                if (!searchInput || !form) {
                  console.log('未找到搜索表单元素');
                  return false;
                }
                
                // 填写搜索关键词
                searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
                console.log('填写搜索关键词: ' + searchInput.value);
                
                // 提交表单
                const submitButton = document.querySelector('input[type="submit"]');
                if (submitButton) {
                  submitButton.click();
                  console.log('点击搜索按钮提交');
                } else {
                  form.submit();
                  console.log('提交表单');
                }
                
                return true;
              })();
            ''');
            
            LogUtil.i('搜索表单提交结果: $result');
            searchSubmitted = true;
            
            // 添加延迟等待结果加载
            await Future.delayed(Duration(seconds: 2));
          }
          // 如果不是首页或已经提交过搜索，尝试提取媒体链接
          else if (searchSubmitted || !pageUrl.startsWith(_baseUrl)) {
            LogUtil.i('尝试提取页面中的媒体链接');
            
            // 获取页面HTML
            final htmlResult = await controller.runJavaScriptReturningResult(
              'document.documentElement.outerHTML'
            );
            
            // 清理HTML字符串
            String html = htmlResult.toString();
            if (html.startsWith('"') && html.endsWith('"')) {
              html = html.substring(1, html.length - 1)
                     .replaceAll('\\"', '"')
                     .replaceAll('\\n', '\n');
            }
            
            // 输出页面标题和URL以便调试
            final title = await controller.runJavaScriptReturningResult('document.title');
            final currentUrl = await controller.currentUrl();
            LogUtil.i('当前页面: $title, URL: $currentUrl');
            
            // 统计页面中的tba.tuan元素数量
            final tuanCount = await controller.runJavaScriptReturningResult(
              'document.querySelectorAll("tba.tuan").length'
            );
            LogUtil.i('页面中tba.tuan元素数量: $tuanCount');
            
            // 使用正则表达式提取流媒体地址
            final RegExp regex = RegExp(r'<tba class="tuan">\s*(http[^<]+)</tba>');
            final matches = regex.allMatches(html);
            
            int extractedCount = 0;
            for (final match in matches) {
              if (match.groupCount >= 1) {
                final mediaUrl = match.group(1)?.trim();
                if (mediaUrl != null && 
                    mediaUrl.isNotEmpty && 
                    !foundStreams.contains(mediaUrl)) {
                  foundStreams.add(mediaUrl);
                  extractedCount++;
                  LogUtil.i('提取到媒体链接 #$extractedCount: $mediaUrl');
                  
                  // 限制提取数量
                  if (foundStreams.length >= _maxStreams) {
                    break;
                  }
                }
              }
            }
            
            LogUtil.i('从HTML中提取到 $extractedCount 个媒体链接');
            
            // 如果找到了足够的链接，测试并返回
            if (foundStreams.isNotEmpty) {
              LogUtil.i('准备测试 ${foundStreams.length} 个媒体流地址');
              
              timeoutTimer?.cancel();
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  completer.complete(result);
                }
              });
            }
            // 如果未找到链接但已提交搜索，尝试再次检查页面内容
            else if (searchSubmitted) {
              // 尝试通过JavaScript直接获取链接
              await controller.runJavaScript('''
                // 直接通过JavaScript提取并输出所有链接
                const tuanElements = document.querySelectorAll('tba.tuan');
                console.log('找到 ' + tuanElements.length + ' 个tba.tuan元素');
                
                for (let i = 0; i < tuanElements.length; i++) {
                  const url = tuanElements[i].textContent.trim();
                  console.log('元素 #' + (i+1) + ' 内容: ' + url);
                  
                  if (url.startsWith('http')) {
                    console.log('发现媒体链接: ' + url);
                  }
                }
                
                // 查看是否有其他类似元素
                const allTba = document.querySelectorAll('tba');
                console.log('页面中共有 ' + allTba.length + ' 个tba元素');
                
                // 输出前5个tba元素的信息
                for (let i = 0; i < Math.min(5, allTba.length); i++) {
                  console.log('tba元素 #' + (i+1) + ' 类名: "' + allTba[i].className + '", 内容: ' + allTba[i].textContent.substring(0, 30));
                }
              ''');
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('WebView加载错误: ${error.description}');
        },
        onNavigationRequest: (NavigationRequest request) {
          final Uri requestUri = Uri.parse(request.url);
          
          // 只允许导航到目标域名
          if (requestUri.host == _baseHost) {
            return NavigationDecision.navigate;
          }
          
          LogUtil.i('阻止导航到: ${request.url}');
          return NavigationDecision.prevent;
        },
      ));
      
      // 添加JavaScript通道
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          // 如果消息是URL，添加到链接列表
          final content = message.message.trim();
          if (content.startsWith('http') && 
              !foundStreams.contains(content) && 
              foundStreams.length < _maxStreams) {
            foundStreams.add(content);
            LogUtil.i('通过JavaScript通道获取到流媒体链接: $content');
            
            // 如果已经找到足够的链接，可以立即测试
            if (foundStreams.length >= 3 && !completer.isCompleted) {
              timeoutTimer?.cancel();
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                completer.complete(result);
              });
            }
          }
        },
      );
      
      // 注入辅助脚本监听页面变化
      await controller.runJavaScript('''
        // 定期检查页面内容
        setInterval(function() {
          const links = document.querySelectorAll('tba.tuan');
          if (links.length > 0) {
            console.log('定期检查: 找到 ' + links.length + ' 个tba.tuan元素');
            
            links.forEach(function(element) {
              const url = element.textContent.trim();
              if (url.startsWith('http')) {
                console.log('发现媒体链接: ' + url);
                AppChannel.postMessage(url);
              }
            });
          }
        }, 1000);
      ''');
      
      // 访问网站首页
      await controller.loadRequest(Uri.parse(_baseUrl));
      LogUtil.i('开始加载网站首页');
      
      // 设置超时处理
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        if (!completer.isCompleted) {
          LogUtil.i('搜索超时，共找到 ${foundStreams.length} 个媒体流地址');
          
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
      
      // 清理资源
      await _disposeWebView(controller);
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析搜索页面失败', e, stackTrace);
      
      // 如果出错但已有结果，返回最快的流
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          completer.complete(result);
        });
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      // 确保计时器被取消
      timeoutTimer?.cancel();
      
      // 确保completer被完成
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    }
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) return 'ERROR';
    
    LogUtil.i('开始测试 ${streams.length} 个媒体流地址的响应速度');
    
    // 创建一个取消标记
    final cancelToken = CancelToken();
    
    // 创建一个完成器
    final completer = Completer<String>();
    
    // 记录测试开始时间
    final startTime = DateTime.now();
    
    // 测试结果
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
