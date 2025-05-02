import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static const String _baseUrl = 'https://tonkiang.us/';
  static const int _timeoutSeconds = 30; // 搜索超时时间
  static const int _maxStreams = 6; // 最大提取的流地址数量
  static const int _httpRequestTimeoutSeconds = 5; // 请求超时时间
  
  /// 解析搜索页面
  static Future<String> parse(String url) async {
    final completer = Completer<String>();
    final List<String> foundStreams = []; // 存储找到的媒体流地址
    
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
      
      // 设置JavaScript通道
      controller.addJavaScriptChannel(
        'StreamDetector',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = json.decode(message.message);
            if (data['type'] == 'foundUrl' && data['url'] != null) {
              final mediaUrl = data['url'] as String;
              LogUtil.i('检测到媒体链接: $mediaUrl');
              
              // 检查URL是否已存在
              if (!foundStreams.contains(mediaUrl)) {
                foundStreams.add(mediaUrl);
                
                // 如果已找到足够数量的URL，则返回结果
                if (foundStreams.length >= _maxStreams && !completer.isCompleted) {
                  LogUtil.i('已找到 ${foundStreams.length} 个媒体流地址，准备测试速度');
                  _testStreamsAndGetFastest(foundStreams).then((String result) {
                    completer.complete(result);
                  });
                }
              }
            }
          } catch (e) {
            LogUtil.e('解析流地址数据失败: $e');
          }
        },
      );
      
      // 设置WebView导航代理
      controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('页面开始加载: $pageUrl');
        },
        onPageFinished: (String pageUrl) async {
          LogUtil.i('页面加载完成: $pageUrl');
          
          // 检查是否为首页，如果是则自动填充搜索框并提交
          if (pageUrl.startsWith(_baseUrl) && !pageUrl.contains('?iptv=')) {
            try {
              // 注入媒体URL检测器脚本
              await controller.runJavaScript('''
                // 创建全局流检测器
                window.streamDetector = {
                  foundUrls: new Set(),
                  
                  // 检测页面中的媒体URL
                  scanPage: function() {
                    // 查找所有div.bmjxjd下的所有div.eotua元素
                    const resultElements = document.querySelectorAll('div.bmjxjd div.eotua');
                    if (resultElements && resultElements.length > 0) {
                      // 提取每个元素中的URL
                      Array.from(resultElements).slice(0, ${_maxStreams}).forEach(element => {
                        const tbaElement = element.querySelector('tba.tuanga');
                        if (tbaElement && tbaElement.textContent) {
                          const url = tbaElement.textContent.trim();
                          if (!this.foundUrls.has(url)) {
                            this.foundUrls.add(url);
                            StreamDetector.postMessage(JSON.stringify({
                              type: 'foundUrl',
                              url: url
                            }));
                          }
                        }
                      });
                    }
                  }
                };
                
                // 定期扫描页面
                setInterval(() => window.streamDetector.scanPage(), 1000);
              ''');
              
              // 等待DOM完全加载
              await Future.delayed(Duration(milliseconds: 500));
              
              // 填充搜索框并提交表单
              await controller.runJavaScript('''
                (function() {
                  const searchInput = document.getElementById('search');
                  if (searchInput) {
                    searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
                    
                    // 提交表单
                    const form = document.getElementById('form1');
                    if (form) {
                      console.log('提交搜索表单...');
                      form.submit();
                    } else {
                      console.error('未找到表单元素');
                    }
                  } else {
                    console.error('未找到搜索输入框');
                  }
                })();
              ''');
              
              LogUtil.i('自动填充搜索关键词并提交: $searchKeyword');
            } catch (e) {
              LogUtil.e('执行JavaScript时出错: $e');
            }
          } else if (pageUrl.contains('?iptv=') || pageUrl.contains('?')) {
            // 在结果页面，扫描媒体URL
            await controller.runJavaScript('window.streamDetector.scanPage();');
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}');
        },
        onNavigationRequest: (NavigationRequest request) {
          // 允许所有导航请求，由检测器脚本捕获URL
          return NavigationDecision.navigate;
        },
      ));
      
      // 加载初始页面
      await controller.loadRequest(Uri.parse(_baseUrl));
      
      // 设置超时
      Timer(Duration(seconds: _timeoutSeconds), () {
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
          final result = await _testStreamsAndGetFastest(foundStreams);
          completer.complete(result);
        }
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
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
    Timer(Duration(seconds: _httpRequestTimeoutSeconds * 2), () {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找到响应最快的流
          String fastestUrl = _getFastestStream(results);
          LogUtil.i('超时，使用响应最快的流地址: $fastestUrl (${results[fastestUrl]}ms)');
          completer.complete(fastestUrl);
        } else if (streams.isNotEmpty) {
          // 如果所有请求都失败，则返回第一个流
          LogUtil.i('所有请求失败，返回第一个流地址: ${streams.first}');
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
    
    // 如果没有完成，等待超时处理
    if (!completer.isCompleted) {
      if (results.isNotEmpty) {
        // 找到响应最快的流
        String fastestUrl = _getFastestStream(results);
        LogUtil.i('所有请求完成，使用响应最快的流地址: $fastestUrl (${results[fastestUrl]}ms)');
        completer.complete(fastestUrl);
      } else if (streams.isNotEmpty) {
        // 如果所有请求都失败，则返回第一个流
        LogUtil.i('所有请求失败，返回第一个流地址: ${streams.first}');
        completer.complete(streams.first);
      } else {
        completer.complete('ERROR');
      }
    }
    
    return completer.future;
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
        window.streamDetector = null;
        // 清理定时器
        for (let i = 1; i < 10000; i++) {
          clearTimeout(i);
          clearInterval(i);
        }
      ''');
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.loadRequest(Uri.parse('about:blank'));
    } catch (e) {
      LogUtil.e('清理WebView资源失败: $e');
    }
  }
}
