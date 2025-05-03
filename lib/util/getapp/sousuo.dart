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
    LogUtil.i('SousuoParser.parse - 开始解析URL: $url');
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    bool searchSubmitted = false;
    bool usingBackupEngine = false;
    int startTimeMs = DateTime.now().millisecondsSinceEpoch;
    
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
      
      // 创建WebView控制器
      LogUtil.i('SousuoParser.parse - 开始创建WebView控制器');
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      LogUtil.i('SousuoParser.parse - WebView控制器创建完成');
      
      // 设置导航委托
      LogUtil.i('SousuoParser.parse - 开始设置WebView导航委托');
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('SousuoParser.onPageStarted - 页面开始加载: $pageUrl');
        },
        onPageFinished: (String pageUrl) async {
          LogUtil.i('SousuoParser.onPageFinished - 页面加载完成: $pageUrl, 耗时: ${DateTime.now().millisecondsSinceEpoch - startTimeMs}ms');
          
          // 确定当前引擎类型
          if (!searchSubmitted) {
            if (pageUrl.startsWith(_primaryEngine)) {
              LogUtil.i('SousuoParser.onPageFinished - 使用主搜索引擎');
              usingBackupEngine = false;
            } else if (pageUrl.startsWith(_backupEngine)) {
              LogUtil.i('SousuoParser.onPageFinished - 使用备用搜索引擎');
              usingBackupEngine = true;
            } else {
              LogUtil.i('SousuoParser.onPageFinished - 页面URL不匹配任何已知搜索引擎: $pageUrl');
            }
            
            // 在搜索页面填写并提交表单
            LogUtil.i('SousuoParser.onPageFinished - 准备提交搜索表单');
            await _submitSearchForm(controller, searchKeyword);
            searchSubmitted = true;
            LogUtil.i('SousuoParser.onPageFinished - 搜索表单已提交，状态更新: searchSubmitted = true');
            
            // 等待搜索结果加载
            LogUtil.i('SousuoParser.onPageFinished - 等待搜索结果加载中...');
            await Future.delayed(Duration(seconds: 2));
            LogUtil.i('SousuoParser.onPageFinished - 搜索结果等待时间结束');
          } else {
            // 从搜索结果页面提取媒体链接
            LogUtil.i('SousuoParser.onPageFinished - 开始从搜索结果页面提取媒体链接');
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller, foundStreams, usingBackupEngine);
            int afterExtractCount = foundStreams.length;
            LogUtil.i('SousuoParser.onPageFinished - 提取完成，新增媒体链接数: ${afterExtractCount - beforeExtractCount}');
            
            // 如果找到了流媒体地址，测试并返回
            if (foundStreams.isNotEmpty) {
              LogUtil.i('SousuoParser.onPageFinished - 找到 ${foundStreams.length} 个媒体流地址，准备测试');
              
              timeoutTimer?.cancel();
              LogUtil.i('SousuoParser.onPageFinished - 主计时器已取消，开始测试流地址');
              
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                LogUtil.i('SousuoParser.onPageFinished - 流地址测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
                if (!completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 完成解析过程，返回结果');
                  completer.complete(result);
                } else {
                  LogUtil.i('SousuoParser.onPageFinished - completer已完成，忽略测试结果');
                }
              });
            } else {
              LogUtil.i('SousuoParser.onPageFinished - 未找到任何媒体流地址');
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('SousuoParser.onWebResourceError - WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url ?? "未知"}');
          
          // 如果主引擎加载失败且尚未切换到备用引擎，则切换到备用引擎
          if (!usingBackupEngine && !searchSubmitted) {
            LogUtil.i('SousuoParser.onWebResourceError - 主搜索引擎加载失败，切换到备用搜索引擎');
            LogUtil.i('SousuoParser.onWebResourceError - 状态更新: usingBackupEngine = true');
            usingBackupEngine = true;
            controller.loadRequest(Uri.parse(_backupEngine));
            LogUtil.i('SousuoParser.onWebResourceError - 已发送备用搜索引擎加载请求: $_backupEngine');
          } else {
            LogUtil.i('SousuoParser.onWebResourceError - 忽略错误，当前状态: usingBackupEngine=$usingBackupEngine, searchSubmitted=$searchSubmitted');
          }
        },
      ));
      LogUtil.i('SousuoParser.parse - WebView导航委托设置完成');
      
      // 添加JavaScript通道用于接收消息
      LogUtil.i('SousuoParser.parse - 开始添加JavaScript通道');
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('SousuoParser.JavaScriptChannel - 收到JavaScript消息: ${message.message}');
          
          // 如果消息内容是URL，添加到地址列表
          if (message.message.startsWith('http') && 
              !foundStreams.contains(message.message) && 
              foundStreams.length < _maxStreams) {
            foundStreams.add(message.message);
            LogUtil.i('SousuoParser.JavaScriptChannel - 通过JavaScript通道添加媒体链接: ${message.message}, 当前列表大小: ${foundStreams.length}/${_maxStreams}');
          } else if (!message.message.startsWith('http')) {
            LogUtil.i('SousuoParser.JavaScriptChannel - 忽略非HTTP格式消息: ${message.message}');
          } else if (foundStreams.contains(message.message)) {
            LogUtil.i('SousuoParser.JavaScriptChannel - 忽略重复的媒体链接: ${message.message}');
          } else if (foundStreams.length >= _maxStreams) {
            LogUtil.i('SousuoParser.JavaScriptChannel - 已达到最大媒体链接数限制 ${_maxStreams}，忽略: ${message.message}');
          }
        },
      );
      LogUtil.i('SousuoParser.parse - JavaScript通道添加完成');
      
      // 先尝试加载主搜索引擎
      LogUtil.i('SousuoParser.parse - 开始加载主搜索引擎: $_primaryEngine');
      await controller.loadRequest(Uri.parse(_primaryEngine));
      LogUtil.i('SousuoParser.parse - 主搜索引擎加载请求已发送');
      
      // 设置连接超时
      LogUtil.i('SousuoParser.parse - 设置主搜索引擎连接超时: 8秒');
      Timer(Duration(seconds: 8), () {
        LogUtil.i('SousuoParser.connectionTimeout - 连接超时检查触发，当前状态: searchSubmitted=$searchSubmitted');
        if (!searchSubmitted) {
          LogUtil.i('SousuoParser.connectionTimeout - 主搜索引擎连接超时，切换到备用搜索引擎');
          LogUtil.i('SousuoParser.connectionTimeout - 状态更新: usingBackupEngine = true');
          usingBackupEngine = true;
          controller.loadRequest(Uri.parse(_backupEngine));
          LogUtil.i('SousuoParser.connectionTimeout - 已发送备用搜索引擎加载请求: $_backupEngine');
        } else {
          LogUtil.i('SousuoParser.connectionTimeout - 搜索已提交，忽略连接超时');
        }
      });
      
      // 设置总体搜索超时
      LogUtil.i('SousuoParser.parse - 设置总体搜索超时: ${_timeoutSeconds}秒');
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('SousuoParser.searchTimeout - 搜索总超时触发，当前状态: completer完成=${completer.isCompleted}, 找到流数量=${foundStreams.length}');
        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser.searchTimeout - 搜索超时，共找到 ${foundStreams.length} 个媒体流地址');
          
          if (foundStreams.isEmpty) {
            LogUtil.i('SousuoParser.searchTimeout - 未找到任何媒体流地址，返回ERROR');
            completer.complete('ERROR');
          } else {
            LogUtil.i('SousuoParser.searchTimeout - 开始测试找到的媒体流地址');
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              LogUtil.i('SousuoParser.searchTimeout - 流地址测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
              completer.complete(result);
            });
          }
        } else {
          LogUtil.i('SousuoParser.searchTimeout - completer已完成，忽略超时');
        }
      });
      
      // 等待结果
      LogUtil.i('SousuoParser.parse - 等待解析结果中...');
      final result = await completer.future;
      LogUtil.i('SousuoParser.parse - 解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      // 清理资源
      LogUtil.i('SousuoParser.parse - 开始清理WebView资源');
      await _disposeWebView(controller);
      LogUtil.i('SousuoParser.parse - WebView资源清理完成');
      
      // 计算总耗时
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('SousuoParser.parse - 整个解析过程共耗时: ${endTimeMs - startTimeMs}ms');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser.parse - 解析搜索页面失败', e, stackTrace);
      
      // 如果出错但已有结果，返回最快的流
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 尽管出错，但已找到 ${foundStreams.length} 个媒体流地址，尝试测试');
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          LogUtil.i('SousuoParser.parse - 出错后的流地址测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
          completer.complete(result);
        });
      } else if (!completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 出错且未找到媒体流地址，返回ERROR');
        completer.complete('ERROR');
      } else {
        LogUtil.i('SousuoParser.parse - 出错但completer已完成，无需处理');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      // 确保计时器被取消
      if (timeoutTimer?.isActive == true) {
        LogUtil.i('SousuoParser.parse.finally - 取消未触发的计时器');
        timeoutTimer?.cancel();
      }
      
      // 确保completer被完成
      if (!completer.isCompleted) {
        LogUtil.i('SousuoParser.parse.finally - Completer未完成，强制完成为ERROR');
        completer.complete('ERROR');
      }
      
      LogUtil.i('SousuoParser.parse.finally - 解析过程清理完成');
    }
  }
  
  /// 提交搜索表单
  static Future<void> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    LogUtil.i('SousuoParser._submitSearchForm - 开始提交搜索表单，关键词: $searchKeyword');
    
    try {
      // 延迟一下确保页面完全加载
      LogUtil.i('SousuoParser._submitSearchForm - 等待页面完全加载 (500ms)');
      await Future.delayed(Duration(milliseconds: 500));
      
      // 填写搜索表单并提交
      LogUtil.i('SousuoParser._submitSearchForm - 开始执行JavaScript填写搜索表单');
      final result = await controller.runJavaScriptReturningResult('''
        (function() {
          console.log("开始在页面中查找搜索表单元素");
          // 查找搜索表单和输入框
          const searchInput = document.getElementById('search');
          const form = document.getElementById('form1');
          
          if (!searchInput || !form) {
            console.log("未找到搜索表单元素: searchInput=" + (searchInput ? "存在" : "不存在") + ", form=" + (form ? "存在" : "不存在"));
            return false;
          }
          
          // 填写搜索关键词
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
          console.log("填写搜索关键词: " + searchInput.value);
          
          // 提交表单
          const submitButton = document.querySelector('input[type="submit"]');
          if (submitButton) {
            console.log("找到提交按钮，准备点击");
            submitButton.click();
            console.log("点击搜索按钮提交");
          } else {
            console.log("未找到提交按钮，直接提交表单");
            form.submit();
            console.log("提交表单");
          }
          
          return true;
        })();
      ''');
      
      LogUtil.i('SousuoParser._submitSearchForm - 搜索表单提交结果: $result');
      
      if (result.toString().toLowerCase() != 'true') {
        LogUtil.i('SousuoParser._submitSearchForm - 表单提交可能失败，返回值: $result');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._submitSearchForm - 提交搜索表单时出错', e, stackTrace);
    }
    
    LogUtil.i('SousuoParser._submitSearchForm - 提交搜索表单过程完成');
  }
  
  /// 从搜索结果页面提取媒体链接
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine) async {
    LogUtil.i('SousuoParser._extractMediaLinks - 开始从${usingBackupEngine ? "备用" : "主"}搜索引擎提取媒体链接');
    
    try {
      // 注入脚本提取媒体链接
      LogUtil.i('SousuoParser._extractMediaLinks - 注入JavaScript脚本提取媒体链接');
      await controller.runJavaScript('''
        (function() {
          console.log("开始在页面中查找带有onclick属性的复制按钮");
          // 获取所有带有onclick属性的复制按钮
          const copyButtons = document.querySelectorAll('img[onclick][src="copy.png"]');
          console.log("找到 " + copyButtons.length + " 个复制按钮");
          
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
                } else {
                  console.log("URL不是http格式，忽略: " + url);
                }
              } else {
                console.log("按钮#" + index + " 无法从onclick属性中提取URL: " + onclickAttr);
              }
            } else {
              console.log("按钮#" + index + " 没有onclick属性");
            }
          });
          console.log("通过JavaScript通道发送了 " + foundUrls + " 个媒体链接");
        })();
      ''');
      
      // 等待JavaScript执行完成
      LogUtil.i('SousuoParser._extractMediaLinks - 等待JavaScript执行完成 (500ms)');
      await Future.delayed(Duration(milliseconds: 500));
      
      // 如果没有通过JavaScript通道获取到链接，尝试从HTML中提取
      if (foundStreams.isEmpty) {
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
          
          // 根据不同搜索引擎使用不同的正则提取URL
          final RegExp regex = usingBackupEngine
              ? RegExp(r'onclick="copyto\(&quot;(http[^&]+)&quot;\)')
              : RegExp(r'onclick="wqjs\(&quot;(http[^&]+)&quot;\)');
          
          LogUtil.i('SousuoParser._extractMediaLinks - 使用正则表达式从HTML提取媒体链接');
          final matches = regex.allMatches(htmlContent);
          LogUtil.i('SousuoParser._extractMediaLinks - 正则匹配结果数: ${matches.length}');
          
          int addedCount = 0;
          for (final match in matches) {
            if (match.groupCount >= 1) {
              final mediaUrl = match.group(1)?.trim();
              if (mediaUrl != null && 
                  mediaUrl.isNotEmpty && 
                  !foundStreams.contains(mediaUrl)) {
                foundStreams.add(mediaUrl);
                LogUtil.i('SousuoParser._extractMediaLinks - 从HTML提取到媒体链接 #${addedCount+1}: $mediaUrl');
                addedCount++;
                
                // 限制提取数量
                if (foundStreams.length >= _maxStreams) {
                  LogUtil.i('SousuoParser._extractMediaLinks - 已达到最大媒体链接数限制 ${_maxStreams}，停止提取');
                  break;
                }
              } else if (mediaUrl == null || mediaUrl.isEmpty) {
                LogUtil.i('SousuoParser._extractMediaLinks - 提取到空的媒体链接');
              } else if (foundStreams.contains(mediaUrl)) {
                LogUtil.i('SousuoParser._extractMediaLinks - 忽略重复的媒体链接: $mediaUrl');
              }
            }
          }
          LogUtil.i('SousuoParser._extractMediaLinks - 从HTML成功提取了 $addedCount 个媒体链接');
        } catch (e, stackTrace) {
          LogUtil.logError('SousuoParser._extractMediaLinks - 提取HTML时出错', e, stackTrace);
        }
      } else {
        LogUtil.i('SousuoParser._extractMediaLinks - 已通过JavaScript通道获取到 ${foundStreams.length} 个链接，跳过HTML提取');
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
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试开始时间: ${startTime.toIso8601String()}');
    
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
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 流地址 $streamUrl 响应成功，状态码: ${response.statusCode}, 响应时间: ${responseTime}ms');
          
          // 如果这是第一个响应的流，完成任务
          if (!completer.isCompleted) {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 找到第一个可用流，完成任务: $streamUrl');
            completer.complete(streamUrl);
            // 取消其他请求
            cancelToken.cancel('已找到可用流');
          }
        } else {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 流地址 $streamUrl 请求返回空响应');
        }
      } catch (e, stackTrace) {
        LogUtil.logError('SousuoParser._testStreamsAndGetFastest - 测试流地址 $streamUrl 时出错', e, stackTrace);
      }
    }).toList();
    
    // 等待所有任务完成或超时
    try {
      // 设置测试超时
      LogUtil.i('SousuoParser._testStreamsAndGetFastest - 设置测试超时: ${_httpRequestTimeoutSeconds + 1}秒');
      Timer(Duration(seconds: _httpRequestTimeoutSeconds + 1), () {
        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，检查是否有可用结果');
          
          if (results.isNotEmpty) {
            // 找出响应最快的流
            String fastestStream = results.entries
                .reduce((a, b) => a.value < b.value ? a : b)
                .key;
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，选择响应最快的流: $fastestStream, 响应时间: ${results[fastestStream]}ms');
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
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._testStreamsAndGetFastest - 测试流地址时发生错误', e, stackTrace);
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找出响应最快的流
          String fastestStream = results.entries
              .reduce((a, b) => a.value < b.value ? a : b)
              .key;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 出错后选择响应最快的流: $fastestStream, 响应时间: ${results[fastestStream]}ms');
          completer.complete(fastestStream);
        } else {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 出错且无可用结果，返回ERROR');
          completer.complete('ERROR');
        }
      }
    }
    
    // 返回结果
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 等待测试结果...');
    final result = await completer.future;
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，返回结果: $result');
    return result;
  }
  
  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    LogUtil.i('SousuoParser._disposeWebView - 开始清理WebView资源');
    
    try {
      // 加载空白页面
      LogUtil.i('SousuoParser._disposeWebView - 加载空白页面');
      await controller.loadHtmlString('<html><body></body></html>');
      
      // 清除历史记录
      LogUtil.i('SousuoParser._disposeWebView - 清除历史记录');
      await controller.clearLocalStorage();
      await controller.clearCache();
      
      LogUtil.i('SousuoParser._disposeWebView - WebView资源清理完成');
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._disposeWebView - 清理WebView资源时出错', e, stackTrace);
    }
  }
}
