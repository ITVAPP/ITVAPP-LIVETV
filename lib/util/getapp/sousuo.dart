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
  static const int _timeoutSeconds = 30;
  static const int _maxStreams = 6;
  static const int _httpRequestTimeoutSeconds = 5;
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    LogUtil.i('SousuoParser.parse - 开始解析URL: $url');
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    WebViewController? controller;
    
    // 搜索状态
    final searchState = {
      'searchKeyword': '',
      'searchSubmitted': false,
      'startTimeMs': DateTime.now().millisecondsSinceEpoch,
    };
    
    // 清理资源函数
    void cleanupResources() async {
      LogUtil.i('SousuoParser.cleanupResources - 开始清理资源');
      
      // 取消超时定时器
      timeoutTimer?.cancel();
      
      // 清理WebView资源
      if (controller != null) {
        await controller.loadHtmlString('<html><body></body></html>');
      }
      
      // 确保completer被完成
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
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
      
      // 设置导航委托
      LogUtil.i('SousuoParser.parse - 开始设置WebView导航委托');
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (String pageUrl) async {
          LogUtil.i('SousuoParser.onPageFinished - 页面加载完成: $pageUrl');
          
          // 忽略空白页面
          if (pageUrl == 'about:blank') return;
          
          // 确定当前引擎类型
          bool isPrimaryEngine = pageUrl.contains('tonkiang.us');
          bool isBackupEngine = pageUrl.contains('foodieguide.com');
          
          if (!isPrimaryEngine && !isBackupEngine) return;
          
          // 如果搜索还未提交，则提交搜索表单
          if (searchState['searchSubmitted'] == false) {
            LogUtil.i('SousuoParser.onPageFinished - 准备提交搜索表单');
            searchState['searchSubmitted'] = true;
            
            await Future.delayed(Duration(milliseconds: 500));
            
            // 提交搜索表单
            await controller?.runJavaScript('''
              (function() {
                // 查找表单元素
                const form = document.getElementById('form1') || document.forms[0];
                const searchInput = document.getElementById('search') || document.querySelector('input[type="text"]');
                
                if (!searchInput || !form) return false;
                
                // 填写搜索关键词
                searchInput.value = "$searchKeyword";
                
                // 查找提交按钮
                const submitButton = document.querySelector('input[name="Submit"]') || 
                                    document.querySelector('input[type="submit"]') ||
                                    document.querySelector('button[type="submit"]');
                
                if (submitButton) {
                  submitButton.click();
                } else {
                  form.submit();
                }
                
                return true;
              })();
            ''');
            
            // 等待搜索结果加载
            await Future.delayed(Duration(seconds: 3));
            
            // 提取媒体链接
            if (controller != null) {
              await _extractMediaLinks(controller, foundStreams);
            }
            
            // 如果找到流，测试并返回结果
            if (foundStreams.isNotEmpty) {
              LogUtil.i('SousuoParser.onPageFinished - 找到 ${foundStreams.length} 个媒体链接，准备测试');
              
              String result = await _testStreamsAndGetFastest(foundStreams);
              if (!completer.isCompleted) {
                completer.complete(result);
                cleanupResources();
              }
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          // 忽略次要资源错误
          if (error.url == null || 
              error.url!.endsWith('.png') || 
              error.url!.endsWith('.jpg') || 
              error.url!.endsWith('.gif') || 
              error.url!.endsWith('.css')) {
            return;
          }
          
          LogUtil.e('SousuoParser.onWebResourceError - WebView资源加载错误: ${error.description}, URL: ${error.url ?? "未知"}');
          
          // 如果主引擎加载出错，尝试加载备用引擎
          if (searchState['searchSubmitted'] == false && 
              error.url != null && 
              error.url!.contains('tonkiang.us')) {
            LogUtil.i('SousuoParser.onWebResourceError - 主搜索引擎加载出错，切换到备用搜索引擎');
            controller?.loadRequest(Uri.parse(_backupEngine));
          }
        },
      ));
      
      // 先尝试加载主搜索引擎
      LogUtil.i('SousuoParser.parse - 开始加载主搜索引擎: $_primaryEngine');
      await controller.loadRequest(Uri.parse(_primaryEngine));
      
      // 设置总体搜索超时
      LogUtil.i('SousuoParser.parse - 设置总体搜索超时: ${_timeoutSeconds}秒');
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('SousuoParser.searchTimeout - 搜索超时触发');
        
        if (!completer.isCompleted) {
          if (foundStreams.isEmpty) {
            LogUtil.i('SousuoParser.searchTimeout - 未找到任何媒体流地址，返回ERROR');
            completer.complete('ERROR');
          } else {
            LogUtil.i('SousuoParser.searchTimeout - 找到 ${foundStreams.length} 个媒体流地址，开始测试');
            _testStreamsAndGetFastest(foundStreams).then((result) {
              completer.complete(result);
            });
          }
          cleanupResources();
        }
      });
      
      // 等待结果
      final result = await completer.future;
      
      // 计算总耗时
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('SousuoParser.parse - 整个解析过程共耗时: ${endTimeMs - startMs}ms');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser.parse - 解析搜索页面失败', e, stackTrace);
      
      if (!completer.isCompleted) {
        if (foundStreams.isNotEmpty) {
          _testStreamsAndGetFastest(foundStreams).then((result) {
            completer.complete(result);
          });
        } else {
          completer.complete('ERROR');
        }
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!completer.isCompleted) {
        cleanupResources();
      }
    }
  }
  
  /// 从搜索结果页面提取媒体链接
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams) async {
    LogUtil.i('SousuoParser._extractMediaLinks - 开始从HTML提取媒体链接');
    
    try {
      // 获取页面HTML
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
      
      LogUtil.i('SousuoParser._extractMediaLinks - 获取到HTML，长度: ${htmlContent.length}');
      
      // 使用正则表达式提取媒体URL
      final List<RegExp> regexPatterns = [
        // 主搜索引擎正则
        RegExp(r'onclick="wqjs\(&quot;(http[^&]+)&quot;\)'),
        RegExp(r'onclick="wqjs\(\"(http[^\"]+)\"\)'),
        RegExp(r'onclick="play\(&quot;(http[^&]+)&quot;\)'),
        RegExp(r'onclick="play\(\"(http[^\"]+)\"\)'),
        
        // 备用搜索引擎正则
        RegExp(r'onclick="copyto\(&quot;(http[^&]+)&quot;\)'),
        RegExp(r'onclick="copyto\(\"(http[^\"]+)\"\)'),
        RegExp(r'onclick="copy\(&quot;(http[^&]+)&quot;\)'),
        RegExp(r'onclick="copy\(\"(http[^\"]+)\"\)'),
      ];
      
      // 对每种正则表达式尝试匹配
      int totalMatches = 0;
      
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
              LogUtil.i('SousuoParser._extractMediaLinks - 提取到媒体链接: $mediaUrl');
              
              // 限制提取数量
              if (foundStreams.length >= _maxStreams) {
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
      
      LogUtil.i('SousuoParser._extractMediaLinks - 正则匹配总结果数: $totalMatches, 提取链接数: ${foundStreams.length}');
      
      // 如果没有找到链接，尝试更简单的方法
      if (foundStreams.isEmpty) {
        // 查找所有m3u8链接
        final simpleRegex = RegExp(r'(https?://[^\s\'"()<>]+\.m3u8)');
        final simpleMatches = simpleRegex.allMatches(htmlContent);
        
        for (final match in simpleMatches) {
          final url = match.group(1);
          if (url != null && url.isNotEmpty && !foundStreams.contains(url)) {
            foundStreams.add(url);
            LogUtil.i('SousuoParser._extractMediaLinks - 通过简单方法提取到链接: $url');
            
            if (foundStreams.length >= _maxStreams) break;
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._extractMediaLinks - 提取媒体链接时出错', e, stackTrace);
    }
    
    LogUtil.i('SousuoParser._extractMediaLinks - 提取完成，共找到 ${foundStreams.length} 个链接');
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      return 'ERROR';
    }
    
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 开始测试 ${streams.length} 个媒体流地址');
    
    // 创建一个取消标记和完成器
    final cancelToken = CancelToken();
    final completer = Completer<String>();
    final Map<String, int> results = {};
    
    // 设置测试超时
    Timer(Duration(seconds: _httpRequestTimeoutSeconds + 1), () {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找出响应最快的流
          String fastestStream = results.entries
              .reduce((a, b) => a.value < b.value ? a : b)
              .key;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 选择响应最快的流: $fastestStream');
          completer.complete(fastestStream);
        } else {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 无可用结果，返回ERROR');
          completer.complete('ERROR');
        }
        
        // 取消所有未完成的请求
        cancelToken.cancel('测试超时');
      }
    });
    
    // 并行测试所有流
    for (final streamUrl in streams) {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试流: $streamUrl');
      
      try {
        // 发送请求检查流可用性
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'HEAD',
            responseType: ResponseType.bytes,
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
          final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;
          results[streamUrl] = responseTime;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 流地址 $streamUrl 响应成功，响应时间: ${responseTime}ms');
          
          // 如果这是第一个响应的流，完成任务
          if (!completer.isCompleted) {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 找到可用流: $streamUrl');
            completer.complete(streamUrl);
            // 取消其他请求
            cancelToken.cancel('已找到可用流');
          }
        }
      } catch (e) {
        LogUtil.e('SousuoParser._testStreamsAndGetFastest - 测试流地址 $streamUrl 时出错: $e');
      }
    }
    
    // 等待结果或超时
    return await completer.future;
  }
}
