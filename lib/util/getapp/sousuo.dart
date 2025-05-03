import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器 (支持两个搜索引擎)
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/';
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/';
  
  // 通用配置
  static const int _timeoutSeconds = 30;
  static const int _maxStreams = 6;
  static const int _httpRequestTimeoutSeconds = 5;
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    bool searchSubmitted = false;
    bool usingBackupEngine = false;
    
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
      
      // 设置导航委托
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('页面开始加载: $pageUrl');
        },
        onPageFinished: (String pageUrl) async {
          LogUtil.i('页面加载完成: $pageUrl');
          
          // 确定当前引擎类型
          if (!searchSubmitted) {
            if (pageUrl.startsWith(_primaryEngine)) {
              usingBackupEngine = false;
            } else if (pageUrl.startsWith(_backupEngine)) {
              usingBackupEngine = true;
            }
            
            // 在搜索页面填写并提交表单
            await _submitSearchForm(controller, searchKeyword);
            searchSubmitted = true;
            
            // 等待搜索结果加载
            await Future.delayed(Duration(seconds: 2));
          } else {
            // 从搜索结果页面提取媒体链接
            await _extractMediaLinks(controller, foundStreams, usingBackupEngine);
            
            // 如果找到了流媒体地址，测试并返回
            if (foundStreams.isNotEmpty) {
              LogUtil.i('找到 ${foundStreams.length} 个媒体流地址，准备测试');
              
              timeoutTimer?.cancel();
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
          
          // 如果主引擎加载失败且尚未切换到备用引擎，则切换到备用引擎
          if (!usingBackupEngine && !searchSubmitted) {
            LogUtil.i('主搜索引擎加载失败，切换到备用搜索引擎');
            usingBackupEngine = true;
            controller.loadRequest(Uri.parse(_backupEngine));
          }
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
      
      // 先尝试加载主搜索引擎
      await controller.loadRequest(Uri.parse(_primaryEngine));
      LogUtil.i('尝试加载主搜索引擎: $_primaryEngine');
      
      // 设置连接超时
      Timer(Duration(seconds: 8), () {
        if (!searchSubmitted) {
          LogUtil.i('主搜索引擎连接超时，切换到备用搜索引擎');
          usingBackupEngine = true;
          controller.loadRequest(Uri.parse(_backupEngine));
        }
      });
      
      // 设置总体搜索超时
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
  
  /// 提交搜索表单
  static Future<void> _submitSearchForm(WebViewController controller, String searchKeyword) async {
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
  }
  
  /// 从搜索结果页面提取媒体链接
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine) async {
    LogUtil.i('从${usingBackupEngine ? "备用" : "主"}搜索引擎提取媒体链接');
    
    // 注入脚本提取媒体链接
    await controller.runJavaScript('''
      (function() {
        // 获取所有带有onclick属性的复制按钮
        const copyButtons = document.querySelectorAll('img[onclick][src="copy.png"]');
        console.log('找到 ' + copyButtons.length + ' 个复制按钮');
        
        // 从onclick属性中提取URL
        copyButtons.forEach(function(button) {
          const onclickAttr = button.getAttribute('onclick');
          if (onclickAttr) {
            // 根据不同搜索引擎使用不同的提取正则
            const pattern = ${usingBackupEngine ? '/copyto\\\\("([^"]+)/' : '/wqjs\\\\("([^"]+)/'};
            const match = onclickAttr.match(pattern);
            if (match && match[1]) {
              const url = match[1];
              console.log('从复制按钮提取到URL: ' + url);
              if (url.startsWith('http')) {
                AppChannel.postMessage(url);
              }
            }
          }
        });
      })();
    ''');
    
    // 等待JavaScript执行完成
    await Future.delayed(Duration(milliseconds: 500));
    
    // 如果没有通过JavaScript通道获取到链接，尝试从HTML中提取
    if (foundStreams.isEmpty) {
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
      
      // 根据不同搜索引擎使用不同的正则提取URL
      final RegExp regex = usingBackupEngine
          ? RegExp(r'onclick="copyto\(&quot;(http[^&]+)&quot;\)')
          : RegExp(r'onclick="wqjs\(&quot;(http[^&]+)&quot;\)');
      
      final matches = regex.allMatches(htmlContent);
      
      for (final match in matches) {
        if (match.groupCount >= 1) {
          final mediaUrl = match.group(1)?.trim();
          if (mediaUrl != null && 
              mediaUrl.isNotEmpty && 
              !foundStreams.contains(mediaUrl)) {
            foundStreams.add(mediaUrl);
            LogUtil.i('从HTML提取到媒体链接: $mediaUrl');
            
            // 限制提取数量
            if (foundStreams.length >= _maxStreams) {
              break;
            }
          }
        }
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
