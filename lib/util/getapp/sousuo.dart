import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 电视直播源搜索引擎解析器 (支持两个搜索引擎)
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用引擎URL
  
  // 配置参数
  static const int _maxStreams = 8; // 最大提取的媒体流数量
  static const int _formSubmitWaitMs = 1000; // 表单提交前等待时间(毫秒)
  static const int _streamTestTimeoutSeconds = 8; // 流测试超时时间(秒)
  static const int _backupEngineTimeoutSeconds = 20; // 备用引擎总超时时间(秒)
  static const int _primaryEngineTimeoutSeconds = 15; // 主引擎超时时间(秒)
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final completer = Completer<String>(); // 异步完成器，用于返回结果
    final List<String> foundStreams = []; // 存储提取的媒体流地址
    WebViewController? controller; // WebView控制器
    bool isResourceCleaned = false; // 资源清理标志
    Timer? backupEngineTimer; // 备用引擎超时计时器
    Timer? primaryEngineTimer; // 主引擎超时计时器
    // 解析状态，强类型Map确保类型安全
    final Map<String, dynamic> state = {
      'currentEngine': 'primary', // 当前使用的搜索引擎
      'searchKeyword': '', // 搜索关键词
      'primaryEngineFailed': false, // 主引擎是否失败
      'formSubmissionInProgress': false, // 表单提交是否进行中
      'formSubmitted': false, // 搜索表单是否已提交
      'formResultReceived': false, // 表单提交结果是否收到
      'linkExtractionDone': false, // 链接提取是否完成
      'startTime': DateTime.now().millisecondsSinceEpoch, // 解析开始时间
      'navigationCount': 0, // 页面导航计数
      'lastPageUrl': '', // 上一个页面URL
      'expectingFormResult': false, // 是否等待表单结果
    };
    
    /// 从状态获取布尔值，提供默认值防止类型错误
    bool getBoolState(String key, {bool defaultValue = false}) {
      return state[key] is bool ? state[key] as bool : defaultValue;
    }
    
    /// 从状态获取字符串值，提供默认值防止类型错误
    String getStringState(String key, {String defaultValue = ''}) {
      return state[key] is String ? state[key] as String : defaultValue;
    }
    
    /// 从状态获取整数值，提供默认值防止类型错误
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
        if (controller != null) {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页
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
      if (!isPrimaryEngine || alreadyFailed) return; // 避免重复切换
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
          await controller!.loadHtmlString('<html><body></body></html>'); // 清空当前页面
          await Future.delayed(Duration(milliseconds: 300)); // 等待页面加载
          LogUtil.i('加载备用引擎: $_backupEngine');
          await controller!.loadRequest(Uri.parse(_backupEngine)); // 加载备用引擎
          backupEngineTimer = Timer(Duration(seconds: _backupEngineTimeoutSeconds), () { // 设置备用引擎超时
            if (!completer.isCompleted) {
              LogUtil.i('备用引擎总体超时');
              if (foundStreams.isEmpty) {
                completer.complete('ERROR'); // 无结果返回错误
                cleanupResources();
              } else {
                LogUtil.i('备用引擎找到 ${foundStreams.length} 个流，开始测试');
                _testStreamsAndGetFastest(foundStreams).then((result) { // 测试流地址
                  if (!completer.isCompleted) {
                    completer.complete(result);
                    cleanupResources();
                  }
                });
              }
            }
          });
        } catch (e) {
          LogUtil.e('切换备用引擎出错: $e');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            cleanupResources();
          }
        }
      } else {
        LogUtil.e('切换备用引擎时控制器为空');
        if (!completer.isCompleted) {
          completer.complete('ERROR');
          cleanupResources();
        }
      }
    }
    
    /// 提取页面中的媒体链接
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
          htmlContent = htmlContent.substring(1, htmlContent.length - 1).replaceAll('\\"', '"').replaceAll('\\n', '\n'); // 清理HTML格式
        }
        LogUtil.i('获取HTML成功，长度: ${htmlContent.length}');
        final beforeExtractCount = foundStreams.length; // 记录提取前的流数量
        final RegExp regex = RegExp('onclick="[^"]*?\[\'"]*((http|https)://[^\'"\$ \\s]+)'); // 正则匹配onclick中的URL
        final matches = regex.allMatches(htmlContent);
        LogUtil.i('找到 ${matches.length} 个链接匹配');
        final Set<String> addedHosts = {}; // 存储已添加的主机，用于去重
        for (final existingUrl in foundStreams) {
          try {
            final uri = Uri.parse(existingUrl);
            addedHosts.add('${uri.host}:${uri.port}'); // 添加已有流的主机
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
                  if (!addedHosts.contains(hostKey)) { // 避免重复主机
                    foundStreams.add(mediaUrl);
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
        LogUtil.i('提取完成，新增:${afterExtractCount - beforeExtractCount}，总数:$afterExtractCount');
        return foundStreams.isNotEmpty; // 返回是否提取到链接
      } catch (e) {
        LogUtil.e('提取链接出错: $e');
        return false;
      }
    }
    
    try {
      // 提取搜索关键词
      LogUtil.i('从URL提取搜索关键词');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      LogUtil.i('提取到搜索关键词: $searchKeyword');
      state['searchKeyword'] = searchKeyword;
      
      // 初始化WebView控制器
      LogUtil.i('创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JavaScript
        ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
      
      // 配置WebView导航委托
      await controller?.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) { // 页面开始加载
          LogUtil.i('页面开始加载: $pageUrl');
          state['navigationCount'] = getIntState('navigationCount') + 1;
          if (getBoolState('expectingFormResult') && pageUrl != getStringState('lastPageUrl')) {
            LogUtil.i('检测到表单提交后的页面导航');
            state['formResultReceived'] = true;
            state['expectingFormResult'] = false;
          }
          state['lastPageUrl'] = pageUrl;
        },
        onPageFinished: (String pageUrl) async { // 页面加载完成
          final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
          final startTimeMs = getIntState('startTime');
          final loadTimeMs = currentTimeMs - startTimeMs;
          LogUtil.i('页面加载完成:$pageUrl, 耗时:${loadTimeMs}ms');
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
          int navigationCount = getIntState('navigationCount');
          if (navigationCount == 1 && !getBoolState('formSubmitted')) { // 初次加载，提交表单
            LogUtil.i('初始页面加载完成，等待提交表单');
            await Future.delayed(Duration(milliseconds: _formSubmitWaitMs));
            if (getBoolState('formSubmissionInProgress')) {
              LogUtil.i('表单提交已在进行中，跳过');
              return;
            }
            state['formSubmissionInProgress'] = true;
            try {
              LogUtil.i('开始提交搜索表单');
              await _submitSearchForm(controller!, searchKeyword); // 提交搜索表单
              state['expectingFormResult'] = true;
              state['formSubmitted'] = true;
              await _injectHelpers(controller!, 'AppChannel'); // 注入DOM监控脚本
              LogUtil.i('表单已提交，正在等待结果');
            } catch (e) {
              LogUtil.e('表单提交过程出错: $e');
              state['formSubmissionInProgress'] = false;
              if (isPrimaryEngine) {
                LogUtil.i('主引擎表单提交失败，切换备用引擎');
                await switchToBackupEngine();
              } else {
                LogUtil.i('备用引擎表单提交失败，返回ERROR');
                if (!completer.isCompleted) {
                  completer.complete('ERROR');
                  await cleanupResources();
                }
              }
            } finally {
              state['formSubmissionInProgress'] = false;
            }
          } else if (navigationCount >= 2 || getBoolState('formResultReceived')) { // 表单提交后，提取链接
            LogUtil.i('表单提交后页面加载完成，准备提取链接');
            if (getBoolState('linkExtractionDone')) {
              LogUtil.i('链接已提取过，跳过');
              return;
            }
            final hasLinks = await extractMediaLinks();
            state['linkExtractionDone'] = true;
            if (hasLinks) {
              LogUtil.i('成功提取到 ${foundStreams.length} 个链接，开始测试');
              final result = await _testStreamsAndGetFastest(foundStreams); // 测试流地址
              if (!completer.isCompleted) {
                completer.complete(result);
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
        onWebResourceError: (WebResourceError error) { // 处理资源加载错误
          if (error.url == null || 
              error.url!.endsWith('.png') || 
              error.url!.endsWith('.jpg') || 
              error.url!.endsWith('.gif') || 
              error.url!.endsWith('.webp') || 
              error.url!.endsWith('.css')) {
            return; // 忽略非关键资源错误
          }
          LogUtil.e('资源错误:${error.description}, 错误码:${error.errorCode}, URL: ${error.url}');
          bool isCriticalError = [-1, -2, -3, -6, -7, -101, -105, -106].contains(error.errorCode);
          if (getStringState('currentEngine') == 'primary' && 
              error.url != null && 
              error.url!.contains('tonkiang.us') &&
              isCriticalError &&
              !getBoolState('linkExtractionDone')) {
            LogUtil.i('主引擎关键错误，切换备用引擎');
            switchToBackupEngine();
          } else if (getStringState('currentEngine') == 'backup' && 
                   error.url != null && 
                   error.url!.contains('foodieguide.com') &&
                   isCriticalError &&
                   !getBoolState('linkExtractionDone')) {
            LogUtil.i('备用引擎关键错误，返回ERROR');
            if (!completer.isCompleted) {
              completer.complete('ERROR');
              cleanupResources();
            }
          }
        },
        onNavigationRequest: (NavigationRequest request) { // 处理导航请求
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
      
      // 添加JavaScript通信通道
      await controller?.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) { // 处理JavaScript消息
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
                foundStreams.add(url);
                LogUtil.i('添加链接: $url');
                if (foundStreams.length == 1) {
                  LogUtil.i('找到首个链接，开始测试');
                  _testStreamsAndGetFastest(foundStreams).then((result) { // 测试流地址
                    if (!completer.isCompleted) {
                      completer.complete(result);
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
                _testStreamsAndGetFastest(foundStreams).then((result) { // 测试流地址
                  if (!completer.isCompleted) {
                    completer.complete(result);
                    cleanupResources();
                  }
                });
              }
            });
          } else if (message.message == 'FORM_SUBMITTED') {
            LogUtil.i('收到表单提交确认');
            state['formSubmitted'] = true;
            state['expectingFormResult'] = true;
          } else if (message.message == 'FORM_SUBMISSION_FAILED') {
            LogUtil.e('收到表单提交失败通知');
            if (getStringState('currentEngine') == 'primary' && !getBoolState('primaryEngineFailed')) {
              LogUtil.i('主引擎表单提交失败，切换备用引擎');
              switchToBackupEngine();
            } else if (getStringState('currentEngine') == 'backup' && !completer.isCompleted) {
              LogUtil.i('备用引擎表单提交失败，返回ERROR');
              completer.complete('ERROR');
              cleanupResources();
            }
          }
        },
      );
      
      // 加载主搜索引擎
      LogUtil.i('加载主搜索引擎: $_primaryEngine');
      await controller?.loadRequest(Uri.parse(_primaryEngine));
      
      // 设置主引擎超时
      primaryEngineTimer = Timer(Duration(seconds: _primaryEngineTimeoutSeconds), () {
        if (!completer.isCompleted && getStringState('currentEngine') == 'primary') {
          LogUtil.i('主引擎超时，切换到备用引擎');
          switchToBackupEngine();
        }
      });
      
      // 等待解析结果
      final result = await completer.future;
      final endTimeMs = DateTime.now().millisecondsSinceEpoch;
      final startTimeMs = getIntState('startTime');
      LogUtil.i('解析完成，结果:${result == 'ERROR' ? 'ERROR' : '找到可用流'}, 总耗时:${endTimeMs - startTimeMs}ms');
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析过程出错', e, stackTrace);
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('出错但已找到 ${foundStreams.length} 个流，尝试测试');
        final result = await _testStreamsAndGetFastest(foundStreams); // 测试流地址
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
  
  /// 提交搜索表单到主或备用引擎
  static Future<void> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    LogUtil.i('准备提交搜索表单');
    try {
      final submitScript = '''
        (function() {
          console.log("开始提交搜索表单");
          const currentUrl = window.location.href;
          let engineType = '';
          if (currentUrl.includes('tonkiang.us')) {
            engineType = 'primary';
          } else if (currentUrl.includes('foodieguide.com')) {
            engineType = 'backup';
          } else {
            console.log("未知引擎: " + currentUrl);
            window.AppChannel.postMessage('FORM_SUBMISSION_FAILED');
            return false;
          }
          console.log("当前引擎: " + engineType);
          const beforeSubmitUrl = window.location.href;
          console.log("表单提交前URL: " + beforeSubmitUrl);
          const beforeSubmitContent = document.body.innerHTML.length;
          console.log("表单提交前内容长度: " + beforeSubmitContent);
          let submitted = false;
          if (engineType === 'primary') { // 主引擎表单提交
            console.log("处理主引擎表单");
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            if (!searchInput || !form) {
              console.log("未找到主引擎表单元素");
              const forms = document.forms;
              console.log("找到 " + forms.length + " 个表单");
              for (let i = 0; i < forms.length; i++) {
                const currentForm = forms[i];
                const inputs = currentForm.querySelectorAll('input[type="text"]');
                if (inputs.length > 0) {
                  inputs[0].value = "${searchKeyword.replaceAll('"', '\\"')}";
                  console.log("填写搜索关键词: " + inputs[0].value);
                  const submitBtn = currentForm.querySelector('input[type="submit"], button[type="submit"]');
                  if (submitBtn) {
                    console.log("点击提交按钮");
                    submitBtn.click();
                    submitted = true;
                    break;
                  }
                  console.log("直接提交表单");
                  try {
                    currentForm.submit();
                    submitted = true;
                    break;
                  } catch(e) {
                    console.error("表单提交出错: " + e);
                  }
                }
              }
            } else {
              searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
              console.log("填写搜索关键词: " + searchInput.value);
              const submitButton = form.querySelector('input[name="Submit"], input[type="submit"]');
              if (submitButton) {
                console.log("点击提交按钮");
                submitButton.click();
                submitted = true;
              } else {
                console.log("提交表单");
                try {
                  form.submit();
                  submitted = true;
                } catch(e) {
                  console.error("表单提交出错: " + e);
                }
              }
            }
          } else if (engineType === 'backup') { // 备用引擎表单提交
            console.log("处理备用引擎表单");
            const forms = document.forms;
            console.log("找到 " + forms.length + " 个表单");
            for (let i = 0; i < forms.length; i++) {
              const form = forms[i];
              console.log("处理表单 #" + i);
              const textInputs = form.querySelectorAll('input[type="text"]');
              if (textInputs.length > 0) {
                textInputs[0].value = "${searchKeyword.replaceAll('"', '\\"')}";
                console.log("填写搜索关键词: " + textInputs[0].value);
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"]');
                if (submitButton) {
                  console.log("点击提交按钮");
                  submitButton.click();
                  submitted = true;
                  break;
                } else {
                  console.log("直接提交表单");
                  try {
                    form.submit();
                    submitted = true;
                    break;
                  } catch(e) {
                    console.error("表单提交出错: " + e);
                  }
                }
              }
            }
            if (!submitted) {
              const allInputs = document.querySelectorAll('input[type="text"]');
              console.log("找到 " + allInputs.length + " 个文本输入框");
              if (allInputs.length > 0) {
                allInputs[0].value = "${searchKeyword.replaceAll('"', '\\"')}";
                console.log("填写第一个输入框: " + allInputs[0].value);
                const parent = allInputs[0].parentElement;
                if (parent) {
                  const nearbyButton = parent.querySelector('input[type="submit"], button');
                  if (nearbyButton) {
                    nearbyButton.click();
                    console.log("点击附近的按钮");
                    submitted = true;
                  }
                }
                if (!submitted) {
                  const anySubmitButton = document.querySelector('input[type="submit"], button[type="submit"]');
                  if (anySubmitButton) {
                    anySubmitButton.click();
                    console.log("点击任意提交按钮");
                    submitted = true;
                  }
                }
              }
            }
          }
          if (submitted) {
            console.log("表单已尝试提交");
            window.AppChannel.postMessage('FORM_SUBMITTED');
            setTimeout(function() { // 检查表单提交是否触发页面变化
              const afterSubmitUrl = window.location.href;
              const afterSubmitContent = document.body.innerHTML.length;
              console.log("表单提交后URL: " + afterSubmitUrl);
              console.log("表单提交后内容长度: " + afterSubmitContent);
              if (afterSubmitUrl !== beforeSubmitUrl || 
                  Math.abs(afterSubmitContent - beforeSubmitContent) > 100) {
                console.log("表单提交已触发页面变化");
              } else {
                console.log("表单提交后页面未变化，可能失败");
                window.AppChannel.postMessage('FORM_SUBMISSION_FAILED');
              }
            }, 1000);
            return true;
          } else {
            console.log("未能提交任何表单");
            window.AppChannel.postMessage('FORM_SUBMISSION_FAILED');
            return false;
          }
        })();
      ''';
      await controller.runJavaScript(submitScript); // 执行表单提交脚本
      LogUtil.i('已执行表单提交脚本');
    } catch (e, stackTrace) {
      LogUtil.logError('提交表单出错', e, stackTrace);
      throw e; // 抛出异常由调用者处理
    }
  }
  
  /// 注入DOM变化监视器和事件监听脚本
  static Future<void> _injectHelpers(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM监视器和辅助函数");
          function debounce(func, wait) { // 防抖函数，限制频繁调用
            let timeout;
            return function(...args) {
              clearTimeout(timeout);
              timeout = setTimeout(() => func.apply(this, args), wait);
            };
          }
          const observer = new MutationObserver(debounce(function(mutations) { // 监控DOM变化
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
                          node.classList.contains('search-result')
                        ))) {
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
          observer.observe(document.body, { // 配置DOM观察者
            childList: true,
            subtree: true,
            attributes: true,
            characterData: true
          });
          function addElementListeners() { // 添加元素点击监听
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
            setTimeout(addElementListeners, 2000); // 定期重新检查
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
  
  /// 判断URL是否为主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 判断URL是否为备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 测试流地址并返回最快的有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR';
    }
    LogUtil.i('测试 ${streams.length} 个流地址');
    final cancelToken = CancelToken(); // 用于取消HTTP请求
    final completer = Completer<String>(); // 异步完成器
    final startTime = DateTime.now(); // 测试开始时间
    final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList(); // 优先m3u8流
    final otherStreams = streams.where((url) => !url.contains('.m3u8')).toList();
    final prioritizedStreams = [...m3u8Streams, ...otherStreams]; // 按优先级排序
    final tasks = prioritizedStreams.map((streamUrl) async { // 创建测试任务
      try {
        if (completer.isCompleted) return;
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'GET',
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
          cancelToken: cancelToken,
          retryCount: 1,
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
    Timer(Duration(seconds: _streamTestTimeoutSeconds), () { // 设置测试超时
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
    await Future.wait(tasks); // 等待所有测试任务完成
    if (!completer.isCompleted) { // 无响应时返回默认流
      if (m3u8Streams.isNotEmpty) {
        LogUtil.i('无响应，返回首个m3u8: ${m3u8Streams.first}');
        completer.complete(m3u8Streams.first);
      } else {
        LogUtil.i('无响应，返回首个链接: ${streams.first}');
        completer.complete(streams.first);
      }
    }
    return await completer.future; // 返回测试结果
  }
}
