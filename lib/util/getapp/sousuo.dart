import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 时间常量配置类 - 集中管理所有时间相关常量
class _TimingConfig {
  // 单例实例
  static const _TimingConfig _instance = _TimingConfig._();

  // 私有构造函数
  const _TimingConfig._();

  // 页面加载和处理相关
  static const int pageLoadWaitMs = 1000; // 页面加载后等待时间（毫秒）
  static const int engineEarlyCheckSeconds = 10; // 主引擎早期检查时间（秒）
  static const int backupEngineTimeoutSeconds = 15; // 备用引擎超时时间（秒）
  static const int formSubmitWaitSeconds = 2; // 表单提交后等待时间（秒）

  // 流和内容处理相关
  static const int flowTestWaitMs = 300; // 流测试等待时间（毫秒）
  static const int domChangeWaitMs = 500; // DOM变化后等待时间（毫秒）
  static const int delayCheckSeconds = 3; // 延迟检查等待时间（秒）
  static const int extractCheckSeconds = 1; // 提取后检查等待时间（秒）
  static const int backupEngineLoadWaitMs = 300; // 切换备用引擎前等待时间（毫秒）
  static const int cleanupRetryWaitMs = 100; // 清理重试等待时间（毫秒）
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  // 搜索引擎URL
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用搜索引擎URL

  // 通用配置
  static const int _timeoutSeconds = 30; // 总体搜索超时时间（秒）
  static const int _maxStreams = 8; // 最大媒体流数量
  static const int _httpRequestTimeoutSeconds = 5; // HTTP请求超时时间（秒）

  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 10.0; // 显著内容变化百分比

  // 静态变量，防止资源清理并发和重入
  static final Set<String> _cleaningInstances = <String>{}; // 正在清理的实例ID集合
  static final Map<String, Timer> _activeTimers = <String, Timer>{}; // 活动计时器映射

  // 同步锁对象，确保线程安全
  static final _lock = Object();

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final String instanceId = DateTime.now().millisecondsSinceEpoch.toString(); // 生成唯一实例ID
    LogUtil.i('SousuoParser.parse - 开始解析URL: $url, 实例ID: $instanceId');

    final completer = Completer<String>(); // 异步完成器
    final List<String> foundStreams = []; // 存储提取的媒体流地址
    WebViewController? controller; // WebView控制器
    bool contentChangedDetected = false; // 内容变化检测标志
    bool resourcesCleaned = false; // 实例资源清理标志

    // 搜索状态对象
    final Map<String, dynamic> searchState = {
      'searchKeyword': '', // 搜索关键词
      'activeEngine': 'primary', // 当前活跃引擎
      'searchSubmitted': false, // 搜索表单提交状态
      'startTimeMs': DateTime.now().millisecondsSinceEpoch, // 搜索开始时间
      'engineSwitched': false, // 引擎切换标志
      'primaryEngineLoadFailed': false, // 主引擎加载失败标志
      'instanceId': instanceId, // 实例ID
    };

    /// 注册计时器，管理内存
    void registerTimer(String timerName, Timer timer) {
      final String timerKey = '$instanceId-$timerName';
      synchronized(() {
        _activeTimers[timerKey] = timer; // 存储计时器
      });
    }

    /// 取消指定计时器
    void cancelTimer(String timerName) {
      final String timerKey = '$instanceId-$timerName';
      synchronized(() {
        if (_activeTimers.containsKey(timerKey)) {
          _activeTimers[timerKey]?.cancel();
          _activeTimers.remove(timerKey);
          LogUtil.i('SousuoParser.cancelTimer - 取消定时器: $timerName [实例ID: $instanceId]');
        }
      });
    }

    /// 取消所有计时器
    void cancelAllTimers() {
      final List<String> timersToRemove = [];
      synchronized(() {
        _activeTimers.forEach((key, timer) {
          if (key.startsWith('$instanceId-')) {
            timer.cancel();
            timersToRemove.add(key);
          }
        });
        for (final key in timersToRemove) {
          _activeTimers.remove(key);
        }
      });
      LogUtil.i('SousuoParser.cancelAllTimers - 取消实例所有定时器 [实例ID: $instanceId]');
    }

    /// 清理资源，确保无内存泄漏
    void cleanupResources() async {
      if (resourcesCleaned) {
        LogUtil.i('SousuoParser.cleanupResources - 实例资源已清理，跳过 [实例ID: $instanceId]');
        return;
      }

      bool shouldCleanup = false;
      synchronized(() {
        if (_cleaningInstances.contains(instanceId)) {
          LogUtil.i('SousuoParser.cleanupResources - 清理操作进行中，跳过 [实例ID: $instanceId]');
          return;
        }
        _cleaningInstances.add(instanceId);
        shouldCleanup = true;
      });

      if (!shouldCleanup) return;

      try {
        resourcesCleaned = true;
        LogUtil.i('SousuoParser.cleanupResources - 开始清理资源 [实例ID: $instanceId]');
        cancelAllTimers(); // 取消所有计时器

        if (controller != null) {
          final tempController = controller;
          controller = null; // 置空引用
          await tempController!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
          LogUtil.i('SousuoParser.cleanupResources - 已加载空白页面 [实例ID: $instanceId]');
          await _disposeWebView(tempController); // 清理WebView
          LogUtil.i('SousuoParser.cleanupResources - WebView资源已清理 [实例ID: $instanceId]');
        }

        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser.cleanupResources - Completer未完成，强制返回ERROR [实例ID: $instanceId]');
          completer.complete('ERROR');
        }
      } catch (e) {
        LogUtil.e('SousuoParser.cleanupResources - 清理资源出错: $e [实例ID: $instanceId]');
      } finally {
        synchronized(() {
          _cleaningInstances.remove(instanceId); // 移除清理标记
        });
        LogUtil.i('SousuoParser.cleanupResources - 资源清理完成 [实例ID: $instanceId]');
      }
    }

    /// 切换到备用引擎
    Future<void> switchToBackupEngine() async {
      if (searchState['engineSwitched'] == true) {
        LogUtil.i('SousuoParser.switchToBackupEngine - 已切换备用引擎，忽略 [实例ID: $instanceId]');
        return;
      }

      LogUtil.i('SousuoParser.switchToBackupEngine - 主引擎不可用，切换备用引擎 [实例ID: $instanceId]');
      searchState['activeEngine'] = 'backup';
      searchState['engineSwitched'] = true;
      searchState['searchSubmitted'] = false;

      if (controller != null) {
        await controller!.loadHtmlString('<html><body></body></html>'); // 加载空白页面
        await Future.delayed(Duration(milliseconds: _TimingConfig.backupEngineLoadWaitMs));
        if (controller != null) {
          await controller!.loadRequest(Uri.parse(_backupEngine)); // 加载备用引擎
          LogUtil.i('SousuoParser.switchToBackupEngine - 备用引擎加载请求已发送: $_backupEngine [实例ID: $instanceId]');
        } else {
          LogUtil.e('SousuoParser.switchToBackupEngine - 空白页后控制器为空，切换失败 [实例ID: $instanceId]');
        }
      } else {
        LogUtil.e('SousuoParser.switchToBackupEngine - 控制器为空，切换失败 [实例ID: $instanceId]');
      }
    }

    try {
      LogUtil.i('SousuoParser.parse - 提取搜索关键词 [实例ID: $instanceId]');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];

      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('SousuoParser.parse - 缺少关键词参数clickText [实例ID: $instanceId]');
        return 'ERROR';
      }

      LogUtil.i('SousuoParser.parse - 提取关键词: $searchKeyword [实例ID: $instanceId]');
      searchState['searchKeyword'] = searchKeyword;

      LogUtil.i('SousuoParser.parse - 创建WebView控制器 [实例ID: $instanceId]');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      LogUtil.i('SousuoParser.parse - WebView控制器创建完成 [实例ID: $instanceId]');

      LogUtil.i('SousuoParser.parse - 设置导航委托 [实例ID: $instanceId]');
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('SousuoParser.onPageStarted - 页面开始加载: $pageUrl [实例ID: $instanceId]');
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(pageUrl) && controller != null) {
            LogUtil.i('SousuoParser.onPageStarted - 中断主引擎页面加载 [实例ID: $instanceId]');
            controller!.loadHtmlString('<html><body></body></html>');
          }
        },
        onPageFinished: (String pageUrl) async {
          final loadTimeMs = DateTime.now().millisecondsSinceEpoch - (searchState['startTimeMs'] as int);
          LogUtil.i('SousuoParser.onPageFinished - 页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms [实例ID: $instanceId]');

          if (pageUrl == 'about:blank') {
            LogUtil.i('SousuoParser.onPageFinished - 空白页面，忽略 [实例ID: $instanceId]');
            return;
          }

          if (controller == null) {
            LogUtil.e('SousuoParser.onPageFinished - 控制器为空，无法处理 [实例ID: $instanceId]');
            return;
          }

          bool isPrimaryEngine = _isPrimaryEngine(pageUrl);
          bool isBackupEngine = _isBackupEngine(pageUrl);

          if (!isPrimaryEngine && !isBackupEngine) {
            LogUtil.i('SousuoParser.onPageFinished - 未知页面: $pageUrl [实例ID: $instanceId]');
            return;
          }

          if (searchState['engineSwitched'] == true && isPrimaryEngine) {
            LogUtil.i('SousuoParser.onPageFinished - 忽略主引擎页面事件 [实例ID: $instanceId]');
            return;
          }

          searchState['activeEngine'] = isPrimaryEngine ? 'primary' : 'backup';
          LogUtil.i('SousuoParser.onPageFinished - ${isPrimaryEngine ? '主' : '备用'}引擎页面加载完成 [实例ID: $instanceId]');

          if (searchState['searchSubmitted'] == false) {
            LogUtil.i('SousuoParser.onPageFinished - 提交搜索表单 [实例ID: $instanceId]');
            final success = await _submitSearchForm(controller!, searchKeyword);
            if (success) {
              searchState['searchSubmitted'] = true;
              LogUtil.i('SousuoParser.onPageFinished - 表单提交成功，注入DOM监听器 [实例ID: $instanceId]');
              await _injectDomChangeMonitor(controller!);

              final delayCheckTimer = Timer(Duration(seconds: _TimingConfig.delayCheckSeconds), () {
                if (controller == null) {
                  LogUtil.e('SousuoParser.onPageFinished - 延迟检查控制器为空 [实例ID: $instanceId]');
                  return;
                }
                if (!contentChangedDetected && !completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 强制提取媒体链接 [实例ID: $instanceId]');
                  _extractMediaLinks(controller!, foundStreams, isBackupEngine);
                  final extractCheckTimer = Timer(Duration(seconds: _TimingConfig.extractCheckSeconds), () {
                    if (foundStreams.isNotEmpty && !completer.isCompleted) {
                      LogUtil.i('SousuoParser.onPageFinished - 提取到${foundStreams.length}个流，测试 [实例ID: $instanceId]');
                      _testStreamsAndGetFastest(foundStreams).then((String result) {
                        if (!completer.isCompleted) {
                          completer.complete(result);
                          cleanupResources();
                        }
                      });
                    } else if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                      LogUtil.i('SousuoParser.onPageFinished - 主引擎无结果，切换备用引擎 [实例ID: $instanceId]');
                      switchToBackupEngine();
                    }
                  });
                  registerTimer('extractCheck', extractCheckTimer);
                }
              });
              registerTimer('delayCheck', delayCheckTimer);
            } else {
              LogUtil.e('SousuoParser.onPageFinished - 表单提交失败 [实例ID: $instanceId]');
              if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                LogUtil.i('SousuoParser.onPageFinished - 主引擎表单失败，切换备用引擎 [实例ID: $instanceId]');
                switchToBackupEngine();
              }
            }
          } else if (contentChangedDetected) {
            LogUtil.i('SousuoParser.onPageFinished - 内容变化，重新提取链接 [实例ID: $instanceId]');
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller!, foundStreams, isBackupEngine);
            int afterExtractCount = foundStreams.length;
            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('SousuoParser.onPageFinished - 新增${afterExtractCount - beforeExtractCount}个链接，测试 [实例ID: $instanceId]');
              cancelTimer('timeout');
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 解析完成，返回结果 [实例ID: $instanceId]');
                  completer.complete(result);
                  cleanupResources();
                }
              });
            } else if (isPrimaryEngine && afterExtractCount == 0 && searchState['engineSwitched'] == false) {
              LogUtil.i('SousuoParser.onPageFinished - 主引擎无链接，切换备用引擎 [实例ID: $instanceId]');
              switchToBackupEngine();
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          _handleWebResourceError(error, searchState, switchToBackupEngine); // 处理资源加载错误
        },
        onNavigationRequest: (NavigationRequest request) {
          LogUtil.i('SousuoParser.onNavigationRequest - 导航请求: ${request.url} [实例ID: $instanceId]');
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(request.url)) {
            LogUtil.i('SousuoParser.onNavigationRequest - 阻止主引擎导航 [实例ID: $instanceId]');
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate; // 允许其他导航
        },
      ));
      LogUtil.i('SousuoParser.parse - 导航委托设置完成 [实例ID: $instanceId]');

      LogUtil.i('SousuoParser.parse - 添加JavaScript通道 [实例ID: $instanceId]');
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('SousuoParser.JavaScriptChannel - 收到消息: ${message.message} [实例ID: $instanceId]');
          if (controller == null) {
            LogUtil.e('SousuoParser.JavaScriptChannel - 控制器为空，无法处理 [instanceId: $instanceId]');
            return;
          }
          if (message.message == 'CONTENT_CHANGED') {
            LogUtil.i('SousuoParser.JavaScriptChannel - 检测到页面内容变化 [实例ID: $instanceId]');
            contentChangedDetected = true;
            if (searchState['searchSubmitted'] == true && !completer.isCompleted) {
              LogUtil.i('SousuoParser.JavaScriptChannel - 提取媒体链接 [instanceId: $instanceId]');
              final domChangeTimer = Timer(Duration(milliseconds: _TimingConfig.domChangeWaitMs), () {
                if (controller == null) {
                  LogUtil.e('SousuoParser.JavaScriptChannel - 延迟后控制器为空 [instanceId: $instanceId]');
                  return;
                }
                _extractMediaLinks(controller!, foundStreams, searchState['activeEngine'] == 'backup');
                if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
                  final extractCheckTimer = Timer(Duration(seconds: _TimingConfig.extractCheckSeconds), () {
                    if (foundStreams.isEmpty && !completer.isCompleted) {
                      LogUtil.i('SousuoParser.JavaScriptChannel - 主引擎无链接，切换备用引擎 [instanceId: $instanceId]');
                      switchToBackupEngine();
                    }
                  });
                  registerTimer('extractCheckAfterChange', extractCheckTimer);
                }
              });
              registerTimer('domChangeDelay', domChangeTimer);
            }
          } else if (message.message.startsWith('http') &&
              !foundStreams.contains(message.message) &&
              foundStreams.length < _maxStreams) {
            foundStreams.add(message.message);
            LogUtil.i('SousuoParser.JavaScriptChannel - 添加链接: ${message.message}, 当前${foundStreams.length}/${_maxStreams} [instanceId: $instanceId]');
            if (foundStreams.length == 1) {
              LogUtil.i('SousuoParser.JavaScriptChannel - 首个链接，准备测试 [instanceId: $instanceId]');
              final firstStreamTimer = Timer(Duration(milliseconds: _TimingConfig.domChangeWaitMs), () {
                if (!completer.isCompleted) {
                  _testStreamsAndGetFastest(foundStreams).then((String result) {
                    if (!completer.isCompleted) {
                      LogUtil.i('SousuoParser.JavaScriptChannel - 测试完成，返回结果 [instanceId: $instanceId]');
                      completer.complete(result);
                      cleanupResources();
                    }
                  });
                }
              });
              registerTimer('firstStreamDelay', firstStreamTimer);
            }
          }
        },
      );
      LogUtil.i('SousuoParser.parse - JavaScript通道添加完成 [instanceId: $instanceId]');

      LogUtil.i('SousuoParser.parse - 加载主引擎: $_primaryEngine [instanceId: $instanceId]');
      await controller!.loadRequest(Uri.parse(_primaryEngine));
      LogUtil.i('SousuoParser.parse - 主引擎加载请求已发送 [instanceId: $instanceId]');

      final earlyCheckTimer = Timer(Duration(seconds: _TimingConfig.engineEarlyCheckSeconds), () {
        if (controller == null) {
          LogUtil.e('SousuoParser.earlyEngineCheck - 控制器为空 [instanceId: $instanceId]');
          return;
        }
        if (searchState['activeEngine'] == 'primary' &&
            searchState['searchSubmitted'] == false &&
            searchState['engineSwitched'] == false &&
            searchState['primaryEngineLoadFailed'] == false) {
          controller!.runJavaScriptReturningResult('document.body.innerHTML.length').then((result) {
            int contentLength = int.tryParse(result.toString()) ?? 0;
            if (contentLength < _minValidContentLength) {
              LogUtil.i('SousuoParser.earlyEngineCheck - 主引擎内容不足($contentLength)，切换备用引擎 [instanceId: $instanceId]');
              switchToBackupEngine();
            } else {
              LogUtil.i('SousuoParser.earlyEngineCheck - 主引擎内容正常($contentLength)，继续等待 [instanceId: $instanceId]');
            }
          }).catchError((e) {
            LogUtil.e('SousuoParser.earlyEngineCheck - 检查主引擎出错: $e [instanceId: $instanceId]');
            switchToBackupEngine();
          });
        }
      });
      registerTimer('earlyCheck', earlyCheckTimer);

      LogUtil.i('SousuoParser.parse - 设置搜索超时: ${_timeoutSeconds}秒 [instanceId: $instanceId]');
      final timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('SousuoParser.searchTimeout - 搜索超时，找到${foundStreams.length}个流 [instanceId: $instanceId]');
        if (!completer.isCompleted) {
          if (foundStreams.isEmpty) {
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('SousuoParser.searchTimeout - 主引擎无结果，切换备用引擎 [instanceId: $instanceId]');
              switchToBackupEngine();
              final backupEngineTimer = Timer(Duration(seconds: _TimingConfig.backupEngineTimeoutSeconds), () {
                if (!completer.isCompleted) {
                  if (foundStreams.isEmpty) {
                    LogUtil.i('SousuoParser.searchTimeout - 备用引擎无流，返回ERROR [instanceId: $instanceId]');
                    completer.complete('ERROR');
                    cleanupResources();
                  } else {
                    LogUtil.i('SousuoParser.searchTimeout - 备用引擎找到${foundStreams.length}个流，测试 [instanceId: $instanceId]');
                    _testStreamsAndGetFastest(foundStreams).then((String result) {
                      completer.complete(result);
                      cleanupResources();
                    });
                  }
                }
              });
              registerTimer('backupEngineTimeout', backupEngineTimer);
            } else {
              LogUtil.i('SousuoParser.searchTimeout - 无流，返回ERROR [instanceId: $instanceId]');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            LogUtil.i('SousuoParser.searchTimeout - 测试找到的流 [instanceId: $instanceId]');
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              LogUtil.i('SousuoParser.searchTimeout - 测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'} [instanceId: $instanceId]');
              completer.complete(result);
              cleanupResources();
            });
          }
        }
      });
      registerTimer('timeout', timeoutTimer);

      LogUtil.i('SousuoParser.parse - 等待解析结果 [instanceId: $instanceId]');
      final result = await completer.future;
      LogUtil.i('SousuoParser.parse - 解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'} [instanceId: $instanceId]');

      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('SousuoParser.parse - 解析耗时: ${endTimeMs - startMs}ms [instanceId: $instanceId]');

      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser.parse - 解析失败 [instanceId: $instanceId]', e, stackTrace);
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 已找到${foundStreams.length}个流，测试 [instanceId: $instanceId]');
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          completer.complete(result);
        });
      } else if (!completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 无流，返回ERROR [instanceId: $instanceId]');
        completer.complete('ERROR');
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      cleanupResources(); // 确保资源清理
    }
  }

  /// 处理WebView资源错误
  static void _handleWebResourceError(WebResourceError error, Map<String, dynamic> searchState, Function switchToBackupEngine) {
    final String instanceId = searchState['instanceId'] as String;
    if (error.url == null ||
        error.url!.endsWith('.png') ||
        error.url!.endsWith('.jpg') ||
        error.url!.endsWith('.gif') ||
        error.url!.endsWith('.css')) {
      return; // 忽略非关键资源错误
    }

    LogUtil.e('SousuoParser.onWebResourceError - 资源错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url ?? "未知"} [instanceId: $instanceId]');

    final List<int> criticalErrorCodes = [
      -1, -2, -3, -6, -7, -101, -105, -106, -118, -137, // 关键错误码
    ];

    if (searchState['activeEngine'] == 'primary') {
      bool isPrimaryEngineResource = error.url != null &&
          (error.url!.contains('tonkiang.us') ||
              (_isPrimaryEngine(searchState['currentUrl'] ?? '') && error.url!.startsWith('/')));
      if (isPrimaryEngineResource && criticalErrorCodes.contains(error.errorCode)) {
        LogUtil.i('SousuoParser.onWebResourceError - 主引擎关键错误，错误码: ${error.errorCode} [instanceId: $instanceId]');
        searchState['primaryEngineLoadFailed'] = true;
        if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
          LogUtil.i('SousuoParser.onWebResourceError - 主引擎出错，切换备用引擎 [instanceId: $instanceId]');
          switchToBackupEngine();
        }
      }
    } else if (searchState['activeEngine'] == 'backup') {
      bool isBackupEngineResource = error.url != null &&
          (error.url!.contains('foodieguide.com') ||
              (_isBackupEngine(searchState['currentUrl'] ?? '') && error.url!.startsWith('/')));
      if (isBackupEngineResource && criticalErrorCodes.contains(error.errorCode)) {
        LogUtil.i('SousuoParser.onWebResourceError - 备用引擎关键错误，错误码: ${error.errorCode} [instanceId: $instanceId]');
      }
    }
  }

  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us'); // 判断是否为主引擎URL
  }

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com'); // 判断是否为备用引擎URL
  }

  /// 注入DOM变化监听器
  static Future<void> _injectDomChangeMonitor(WebViewController controller) async {
    LogUtil.i('SousuoParser._injectDomChangeMonitor - 注入DOM变化监听器');
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          const initialContentLength = document.body.innerHTML.length;
          console.log("初始内容长度: " + initialContentLength);
          const observer = new MutationObserver(function(mutations) {
            const currentContentLength = document.body.innerHTML.length;
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            console.log("内容长度变化百分比: " + contentChangePct.toFixed(2) + "%");
            if (contentChangePct > ${_significantChangePercent}) {
              console.log("检测到显著内容变化，通知应用");
              AppChannel.postMessage('CONTENT_CHANGED');
              observer.disconnect();
            }
            let hasSearchResults = false;
            mutations.forEach(function(mutation) {
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                for (let i = 0; i < mutation.addedNodes.length; i++) {
                  const node = mutation.addedNodes[i];
                  if (node.tagName === 'TABLE' ||
                      (node.classList && (
                        node.classList.contains('result') ||
                        node.classList.contains('result-item') ||
                        node.classList.contains('search-result')
                      ))) {
                    console.log("检测到搜索结果出现");
                    hasSearchResults = true;
                    break;
                  }
                  if (node.querySelectorAll) {
                    const tables = node.querySelectorAll('table');
                    if (tables.length > 0) {
                      console.log("检测到表格元素出现");
                      hasSearchResults = true;
                      break;
                    }
                  }
                }
              }
            });
            if (hasSearchResults) {
              console.log("检测到搜索结果出现，通知应用");
              AppChannel.postMessage('CONTENT_CHANGED');
              observer.disconnect();
              try {
                console.log("自动提取页面中的媒体链接");
                const copyButtons = document.querySelectorAll('img[onclick][src*="copy"], button[onclick], a[onclick]');
                console.log("找到 " + copyButtons.length + " 个可能的复制按钮");
                copyButtons.forEach(function(button, index) {
                  const onclickAttr = button.getAttribute('onclick');
                  if (onclickAttr) {
                    let match;
                    match = onclickAttr.match(/wqjs\\("([^"]+)/);
                    if (!match) {
                      match = onclickAttr.match(/copyto\\("([^"]+)/);
                    }
                    if (match && match[1]) {
                      const url = match[1];
                      console.log("按钮#" + index + " 提取到URL: " + url);
                      if (url.startsWith('http')) {
                        AppChannel.postMessage(url);
                      }
                    }
                  }
                });
              } catch (e) {
                console.error("自动提取媒体链接时出错: " + e);
              }
            }
          });
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            characterData: true
          });
          setTimeout(function() {
            const tables = document.querySelectorAll('table');
            const resultContainers = document.querySelectorAll('.result, .result-item, .search-result');
            if (tables.length > 0 || resultContainers.length > 0) {
              console.log("备用计时器检测到可能的搜索结果");
              AppChannel.postMessage('CONTENT_CHANGED');
            }
          }, 3000);
        })();
      ''');
      LogUtil.i('SousuoParser._injectDomChangeMonitor - DOM变化监听器注入完成');
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._injectDomChangeMonitor - 注入DOM监听器出错', e, stackTrace);
    }
  }

  /// 提交搜索表单
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    LogUtil.i('SousuoParser._submitSearchForm - 提交搜索表单，关键词: $searchKeyword');
    try {
      await Future.delayed(Duration(milliseconds: _TimingConfig.pageLoadWaitMs)); // 等待页面加载
      final submitScript = '''
        (function() {
          console.log("搜索引擎：查找搜索表单元素");
          const form = document.getElementById('form1');
          const searchInput = document.getElementById('search');
          const submitButton = document.querySelector('input[name="Submit"]');
          if (!searchInput || !form) {
            console.log("未找到搜索表单元素: searchInput=" + (searchInput ? "存在" : "不存在") + ", form=" + (form ? "存在" : "不存在"));
            console.log("调试信息 - 表单数量: " + document.forms.length);
            for(let i = 0; i < document.forms.length; i++) {
              console.log("表单 #" + i + " ID: " + document.forms[i].id);
            }
            const inputs = document.querySelectorAll('input');
            console.log("调试信息 - 输入框数量: " + inputs.length);
            for(let i = 0; i < inputs.length; i++) {
              console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
            }
            return false;
          }
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
          console.log("填写搜索关键词: " + searchInput.value);
          if (submitButton) {
            console.log("找到提交按钮，点击提交");
            submitButton.click();
            return true;
          } else {
            console.log("未找到Submit按钮，尝试其他方法");
            const otherSubmitButton = form.querySelector('input[type="submit"]');
            if (otherSubmitButton) {
              console.log("找到submit按钮，点击提交");
              otherSubmitButton.click();
              return true;
            } else {
              console.log("无提交按钮，直接提交表单");
              form.submit();
              return true;
            }
          }
        })();
      ''';
      final result = await controller.runJavaScriptReturningResult(submitScript);
      LogUtil.i('SousuoParser._submitSearchForm - 表单提交结果: $result');
      await Future.delayed(Duration(seconds: _TimingConfig.formSubmitWaitSeconds)); // 等待页面响应
      return result.toString().toLowerCase() == 'true';
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._submitSearchForm - 提交表单出错', e, stackTrace);
      return false;
    }
  }

  /// 从页面提取媒体链接
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine) async {
    LogUtil.i('SousuoParser._extractMediaLinks - 从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
    try {
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      String htmlContent = html.toString();
      LogUtil.i('SousuoParser._extractMediaLinks - 获取HTML，长度: ${htmlContent.length}');
      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = htmlContent.substring(1, htmlContent.length - 1).replaceAll('\\"', '"').replaceAll('\\n', '\n');
        LogUtil.i('SousuoParser._extractMediaLinks - 清理HTML，长度: ${htmlContent.length}');
      }
      final List<RegExp> regexList = [
        RegExp('onclick="[a-zA-Z]+\\((?:"|"|\')?((http|https)://[^"\'\\)\\s]+)'), // 主引擎格式
        RegExp('onclick="copyto\\((?:"|"|\')?((http|https)://[^"\'\\)\\s]+)'), // 备用引擎格式
        RegExp('data-url="((http|https)://[^"\'\\)\\s]+)') // 通用链接格式
      ];
      LogUtil.i('SousuoParser._extractMediaLinks - 使用正则提取链接');
      int totalMatches = 0;
      int addedCount = 0;
      final Set<String> potentialUrls = {};
      for (final regex in regexList) {
        final matches = regex.allMatches(htmlContent);
        totalMatches += matches.length;
        for (final match in matches) {
          if (match.groupCount >= 1) {
            String? mediaUrl = match.group(1)?.trim();
            if (mediaUrl != null) {
              if (mediaUrl.endsWith('"')) {
                mediaUrl = mediaUrl.substring(0, mediaUrl.length - 6);
              }
              mediaUrl = mediaUrl.replaceAll('&', '&');
              if (mediaUrl.isNotEmpty) {
                potentialUrls.add(mediaUrl);
              }
            }
          }
        }
      }
      for (final url in potentialUrls) {
        if (!foundStreams.contains(url) && foundStreams.length < _maxStreams) {
          foundStreams.add(url);
          LogUtil.i('SousuoParser._extractMediaLinks - 提取链接: $url');
          addedCount++;
          if (foundStreams.length >= _maxStreams) {
            LogUtil.i('SousuoParser._extractMediaLinks - 达到最大链接数${_maxStreams}，停止提取');
            break;
          }
        }
      }
      LogUtil.i('SousuoParser._extractMediaLinks - 匹配${totalMatches}次，提取${addedCount}个链接');
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
        LogUtil.i('SousuoParser._extractMediaLinks - 未找到链接，HTML片段: ${htmlContent.substring(0, sampleLength)}');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._extractMediaLinks - 提取链接出错', e, stackTrace);
    }
    LogUtil.i('SousuoParser._extractMediaLinks - 提取完成，当前${foundStreams.length}个链接');
  }

  /// 测试流媒体地址并返回最快有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      LogUtil.i('SousuoParser._testStreamsAndGetFastest - 无流地址，返回ERROR');
      return 'ERROR';
    }
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试${streams.length}个流地址');
    final cancelToken = CancelToken();
    final completer = Completer<String>();
    final startTime = DateTime.now();
    final Map<String, int> results = {};
    bool foundValidStream = false;
    final List<String> priorityStreams = streams.where((url) => url.contains('.m3u8')).toList();
    final List<String> normalStreams = streams.where((url) => !url.contains('.m3u8')).toList();
    final List<String> orderedStreams = [...priorityStreams, ...normalStreams];
    final tasks = orderedStreams.map((streamUrl) async {
      try {
        LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试流: $streamUrl');
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
        if (response != null) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          results[streamUrl] = responseTime;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 流$streamUrl响应成功，时间: ${responseTime}ms');
          if (!foundValidStream) {
            foundValidStream = true;
            Timer(Duration(milliseconds: _TimingConfig.flowTestWaitMs), () {
              if (!completer.isCompleted) {
                if (results.length > 1) {
                  String fastestStream = results.entries.reduce((a, b) => a.value < b.value ? a : b).key;
                  LogUtil.i('SousuoParser._testStreamsAndGetFastest - 最快流: $fastestStream, 时间: ${results[fastestStream]}ms');
                  completer.complete(fastestStream);
                } else {
                  LogUtil.i('SousuoParser._testStreamsAndGetFastest - 单一有效流: $streamUrl');
                  completer.complete(streamUrl);
                }
                cancelToken.cancel('已找到可用流');
              }
            });
          }
        }
      } catch (e) {
        LogUtil.e('SousuoParser._testStreamsAndGetFastest - 测试流$streamUrl出错: $e');
      }
    }).toList();
    Timer(Duration(seconds: HttpUtil.defaultReceiveTimeoutSeconds + 2), () {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          String fastestStream = results.entries.reduce((a, b) => a.value < b.value ? a : b).key;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 超时，选择最快流: $fastestStream');
          completer.complete(fastestStream);
        } else {
          final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList();
          if (m3u8Streams.isNotEmpty) {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 超时，返回首个m3u8: ${m3u8Streams.first}');
            completer.complete(m3u8Streams.first);
          } else {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 超时，返回首个链接: ${streams.first}');
            completer.complete(streams.first);
          }
        }
        cancelToken.cancel('测试超时');
      }
    });
    await Future.wait(tasks);
    if (!completer.isCompleted) {
      if (results.isNotEmpty) {
        String fastestStream = results.entries.reduce((a, b) => a.value < b.value ? a : b).key;
        LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，最快流: $fastestStream');
        completer.complete(fastestStream);
      } else {
        final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList();
        if (m3u8Streams.isNotEmpty) {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，返回首个m3u8: ${m3u8Streams.first}');
          completer.complete(m3u8Streams.first);
        } else {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，返回首个链接: ${streams.first}');
          completer.complete(streams.first);
        }
      }
    }
    final result = await completer.future;
    LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，返回: $result');
    return result;
  }

  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    LogUtil.i('SousuoParser._disposeWebView - 清理WebView资源');
    try {
      await controller.loadHtmlString('<html><body></body></html>'); // 加载空白页面
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
      LogUtil.i('SousuoParser._disposeWebView - WebView资源清理完成');
    } catch (e) {
      LogUtil.e('SousuoParser._disposeWebView - 清理WebView出错: $e');
    }
  }

  /// 执行同步操作，确保线程安全
  static void synchronized(Function action) {
    try {
      synchronized_block(_lock, action); // 使用锁执行操作
    } catch (e) {
      LogUtil.e('SousuoParser.synchronized - 同步操作出错: $e');
    }
  }

  /// 内部同步锁实现
  static void synchronized_block(Object lockObject, Function action) {
    action(); // 执行同步操作
  }
}
