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
  static const int _timeoutSeconds = 30; // 总体超时时间
  static const int _maxStreams = 8; // 最大媒体流数量
  static const int _httpRequestTimeoutSeconds = 5; // HTTP请求超时
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 10.0; // 显著变化百分比
  
  // 静态变量，用于防止资源清理并发和重入问题
  static final Set<String> _cleaningInstances = <String>{}; // 正在清理的实例ID集合
  static final Map<String, Timer> _activeTimers = <String, Timer>{}; // 跟踪实例的活动计时器
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    final String instanceId = DateTime.now().millisecondsSinceEpoch.toString(); // 创建唯一实例ID
    LogUtil.i('SousuoParser.parse - 开始解析URL: $url, 实例ID: $instanceId');
    
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    Timer? timeoutTimer;
    WebViewController? controller;
    bool contentChangedDetected = false;
    bool resourcesCleaned = false; // 实例级资源清理标记
    
    // 状态对象
    final Map<String, dynamic> searchState = {
      'searchKeyword': '',
      'activeEngine': 'primary',
      'searchSubmitted': false,
      'startTimeMs': DateTime.now().millisecondsSinceEpoch,
      'engineSwitched': false, // 记录是否已切换引擎
      'primaryEngineLoadFailed': false, // 记录主引擎是否加载失败
      'instanceId': instanceId, // 存储实例ID
    };
    
    // 优化：Timer管理，减少内存泄漏风险
    void registerTimer(String timerName, Timer timer) {
      final String timerKey = '$instanceId-$timerName';
      _activeTimers[timerKey] = timer;
    }
    
    void cancelTimer(String timerName) {
      final String timerKey = '$instanceId-$timerName';
      if (_activeTimers.containsKey(timerKey)) {
        _activeTimers[timerKey]?.cancel();
        _activeTimers.remove(timerKey);
        LogUtil.i('SousuoParser.cancelTimer - 已取消定时器: $timerName [实例ID: $instanceId]');
      }
    }
    
    void cancelAllTimers() {
      final List<String> timersToRemove = [];
      
      _activeTimers.forEach((key, timer) {
        if (key.startsWith('$instanceId-')) {
          timer.cancel();
          timersToRemove.add(key);
        }
      });
      
      for (final key in timersToRemove) {
        _activeTimers.remove(key);
      }
      
      LogUtil.i('SousuoParser.cancelAllTimers - 已取消实例的所有定时器 [实例ID: $instanceId]');
    }
    
    // 改进：资源清理机制
    void cleanupResources() async {
      // 检查是否已经清理过资源（实例级别检查）
      if (resourcesCleaned) {
        LogUtil.i('SousuoParser.cleanupResources - 此实例资源已经清理过，跳过 [实例ID: $instanceId]');
        return;
      }
      
      // 使用同步锁机制检查全局清理状态
      bool shouldCleanup = false;
      
      synchronized(instanceId, () {
        if (_cleaningInstances.contains(instanceId)) {
          LogUtil.i('SousuoParser.cleanupResources - 此实例的清理操作正在进行，跳过 [实例ID: $instanceId]');
          return;
        }
        
        _cleaningInstances.add(instanceId);
        shouldCleanup = true;
      });
      
      if (!shouldCleanup) {
        return;
      }
      
      try {
        // 标记当前实例资源已清理
        resourcesCleaned = true;
        
        LogUtil.i('SousuoParser.cleanupResources - 开始清理资源 [实例ID: $instanceId]');
        
        // 取消所有计时器
        cancelAllTimers();
        
        // 清理WebView资源
        if (controller != null) {
          try {
            final tempController = controller; // 创建临时引用
            controller = null; // 立即置空控制器引用，防止其他线程重复清理
            
            // 加载空白页面作为清理手段
            await tempController!.loadHtmlString('<html><body></body></html>');
            LogUtil.i('SousuoParser.cleanupResources - 已加载空白页面 [实例ID: $instanceId]');
            
            await _disposeWebView(tempController);
            LogUtil.i('SousuoParser.cleanupResources - WebView资源已清理 [实例ID: $instanceId]');
          } catch (e) {
            LogUtil.e('SousuoParser.cleanupResources - 清理WebView资源时出错: $e [实例ID: $instanceId]');
          }
        }
        
        // 确保completer被完成
        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser.cleanupResources - Completer未完成，强制完成为ERROR [实例ID: $instanceId]');
          completer.complete('ERROR');
        }
      } finally {
        // 无论成功与否，都从清理集合中移除实例ID
        synchronized(instanceId, () {
          _cleaningInstances.remove(instanceId);
        });
        LogUtil.i('SousuoParser.cleanupResources - 资源清理完成 [实例ID: $instanceId]');
      }
    }
    
    // 切换到备用引擎的函数
    Future<void> switchToBackupEngine() async {
      if (searchState['engineSwitched'] == true) {
        LogUtil.i('SousuoParser.switchToBackupEngine - 已经切换到备用引擎，忽略此调用 [实例ID: $instanceId]');
        return;
      }
      
      LogUtil.i('SousuoParser.switchToBackupEngine - 主引擎无法使用，切换到备用引擎 [实例ID: $instanceId]');
      searchState['activeEngine'] = 'backup';
      searchState['engineSwitched'] = true;
      searchState['searchSubmitted'] = false;
      
      // 确保controller不为空
      if (controller != null) {
        // 先加载空白页面，再加载备用引擎
        await controller!.loadHtmlString('<html><body></body></html>');
        await Future.delayed(Duration(milliseconds: _TimingConfig.backupEngineLoadWaitMs));
        
        // 再次检查controller是否为空
        if (controller != null) {
          await controller!.loadRequest(Uri.parse(_backupEngine));
          LogUtil.i('SousuoParser.switchToBackupEngine - 已发送备用搜索引擎加载请求: $_backupEngine [实例ID: $instanceId]');
        } else {
          LogUtil.e('SousuoParser.switchToBackupEngine - 加载空白页后WebView控制器已变为空，无法切换到备用引擎 [实例ID: $instanceId]');
        }
      } else {
        LogUtil.e('SousuoParser.switchToBackupEngine - WebView控制器为空，无法切换到备用引擎 [实例ID: $instanceId]');
      }
    }
    
    try {
      // 从URL中提取搜索关键词
      LogUtil.i('SousuoParser.parse - 开始从URL中提取搜索关键词 [实例ID: $instanceId]');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('SousuoParser.parse - 参数验证失败: 缺少搜索关键词参数 clickText [实例ID: $instanceId]');
        return 'ERROR';
      }
      
      LogUtil.i('SousuoParser.parse - 成功提取搜索关键词: $searchKeyword [实例ID: $instanceId]');
      searchState['searchKeyword'] = searchKeyword;
      
      // 创建WebView控制器
      LogUtil.i('SousuoParser.parse - 开始创建WebView控制器 [实例ID: $instanceId]');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      LogUtil.i('SousuoParser.parse - WebView控制器创建完成 [实例ID: $instanceId]');
      
      // 设置导航委托
      LogUtil.i('SousuoParser.parse - 开始设置WebView导航委托 [实例ID: $instanceId]');
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          LogUtil.i('SousuoParser.onPageStarted - 页面开始加载: $pageUrl [实例ID: $instanceId]');
          
          // 如果已切换引擎且当前是主引擎页面，通过加载空白页面来中断
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(pageUrl) && controller != null) {
            LogUtil.i('SousuoParser.onPageStarted - 已切换到备用引擎，中断主引擎页面加载 [实例ID: $instanceId]');
            controller!.loadHtmlString('<html><body></body></html>');
            return;
          }
        },
        onPageFinished: (String pageUrl) async {
          final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
          final startMs = searchState['startTimeMs'] as int;
          final loadTimeMs = currentTimeMs - startMs;
          LogUtil.i('SousuoParser.onPageFinished - 页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms [实例ID: $instanceId]');
          
          // 忽略空白页面
          if (pageUrl == 'about:blank') {
            LogUtil.i('SousuoParser.onPageFinished - 空白页面加载完成，忽略 [实例ID: $instanceId]');
            return;
          }
          
          // 确保controller不为空
          if (controller == null) {
            LogUtil.e('SousuoParser.onPageFinished - WebView控制器为空，无法处理页面加载完成事件 [实例ID: $instanceId]');
            return;
          }
          
          // 确定当前引擎类型
          bool isPrimaryEngine = _isPrimaryEngine(pageUrl);
          bool isBackupEngine = _isBackupEngine(pageUrl);
          
          if (!isPrimaryEngine && !isBackupEngine) {
            LogUtil.i('SousuoParser.onPageFinished - 未知页面加载完成: $pageUrl [实例ID: $instanceId]');
            return;
          }
          
          // 如果已切换引擎且当前是主引擎，忽略此事件
          if (searchState['engineSwitched'] == true && isPrimaryEngine) {
            LogUtil.i('SousuoParser.onPageFinished - 已切换到备用引擎，忽略主引擎页面加载完成事件 [实例ID: $instanceId]');
            return;
          }
          
          // 更新当前活跃引擎
          if (isPrimaryEngine) {
            searchState['activeEngine'] = 'primary';
            LogUtil.i('SousuoParser.onPageFinished - 主搜索引擎页面加载完成 [实例ID: $instanceId]');
          } else if (isBackupEngine) {
            searchState['activeEngine'] = 'backup';
            LogUtil.i('SousuoParser.onPageFinished - 备用搜索引擎页面加载完成 [实例ID: $instanceId]');
          }
          
          // 如果搜索还未提交，则提交搜索表单
          if (searchState['searchSubmitted'] == false) {
            LogUtil.i('SousuoParser.onPageFinished - 准备提交搜索表单 [实例ID: $instanceId]');
            final success = await _submitSearchForm(controller!, searchKeyword);
            
            if (success) {
              searchState['searchSubmitted'] = true;
              LogUtil.i('SousuoParser.onPageFinished - 搜索表单提交成功，注入DOM变化监听器 [实例ID: $instanceId]');
              
              // 注入DOM变化监听器
              await _injectDomChangeMonitor(controller!);
              
              // 设置延迟检查，防止监听器未生效
              final delayCheckTimer = Timer(Duration(seconds: _TimingConfig.delayCheckSeconds), () {
                // 再次检查controller是否为空
                if (controller == null) {
                  LogUtil.e('SousuoParser.onPageFinished - 延迟检查时WebView控制器为空 [实例ID: $instanceId]');
                  return;
                }
                
                if (!contentChangedDetected && !completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 延迟检查，强制提取媒体链接 [实例ID: $instanceId]');
                  _extractMediaLinks(controller!, foundStreams, isBackupEngine);
                  
                  // 再延迟1秒检查提取结果
                  final extractCheckTimer = Timer(Duration(seconds: _TimingConfig.extractCheckSeconds), () {
                    if (foundStreams.isNotEmpty && !completer.isCompleted) {
                      LogUtil.i('SousuoParser.onPageFinished - 延迟检查提取到 ${foundStreams.length} 个流，开始测试 [实例ID: $instanceId]');
                      _testStreamsAndGetFastest(foundStreams).then((String result) {
                        if (!completer.isCompleted) {
                          completer.complete(result);
                          cleanupResources();
                        }
                      });
                    } else if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                      // 如果是主引擎且未找到结果，切换到备用引擎
                      LogUtil.i('SousuoParser.onPageFinished - 主引擎未找到结果，切换到备用引擎 [实例ID: $instanceId]');
                      switchToBackupEngine();
                    }
                  });
                  registerTimer('extractCheck', extractCheckTimer);
                }
              });
              registerTimer('delayCheck', delayCheckTimer);
            } else {
              LogUtil.e('SousuoParser.onPageFinished - 搜索表单提交失败 [实例ID: $instanceId]');
              
              // 如果是主引擎且提交失败，切换到备用引擎
              if (isPrimaryEngine && searchState['engineSwitched'] == false) {
                LogUtil.i('SousuoParser.onPageFinished - 主引擎搜索表单提交失败，切换到备用引擎 [实例ID: $instanceId]');
                switchToBackupEngine();
              }
            }
          } else if (contentChangedDetected) {
            // 如果搜索已提交且检测到内容变化，尝试再次提取媒体链接
            LogUtil.i('SousuoParser.onPageFinished - 检测到内容变化，再次提取媒体链接 [实例ID: $instanceId]');
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller!, foundStreams, isBackupEngine);
            int afterExtractCount = foundStreams.length;
            
            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('SousuoParser.onPageFinished - 新增 ${afterExtractCount - beforeExtractCount} 个媒体链接，准备测试 [实例ID: $instanceId]');
              
              // 取消超时计时器
              cancelTimer('timeout');
              
              // 测试流并返回结果
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  LogUtil.i('SousuoParser.onPageFinished - 完成解析过程，返回结果 [实例ID: $instanceId]');
                  completer.complete(result);
                  cleanupResources();
                }
              });
            } else if (isPrimaryEngine && afterExtractCount == 0 && searchState['engineSwitched'] == false) {
              // 如果是主引擎，检测到内容变化后仍未找到媒体链接，切换到备用引擎
              LogUtil.i('SousuoParser.onPageFinished - 主引擎内容已变化但未找到媒体链接，切换到备用引擎 [实例ID: $instanceId]');
              switchToBackupEngine();
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          // 改进错误处理
          _handleWebResourceError(error, searchState, switchToBackupEngine);
        },
        onNavigationRequest: (NavigationRequest request) {
          // 监控导航请求，可以用来检测表单提交后的页面跳转
          LogUtil.i('SousuoParser.onNavigationRequest - 导航请求: ${request.url} [实例ID: $instanceId]');
          
          // 如果已切换引擎且当前是主引擎的导航请求，阻止导航
          if (searchState['engineSwitched'] == true && _isPrimaryEngine(request.url)) {
            LogUtil.i('SousuoParser.onNavigationRequest - 已切换到备用引擎，阻止主引擎导航请求 [实例ID: $instanceId]');
            return NavigationDecision.prevent;
          }
          
          // 允许其他导航请求
          return NavigationDecision.navigate;
        },
      ));
      LogUtil.i('SousuoParser.parse - WebView导航委托设置完成 [实例ID: $instanceId]');
      
      // 添加JavaScript通道用于接收消息
      LogUtil.i('SousuoParser.parse - 开始添加JavaScript通道 [实例ID: $instanceId]');
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('SousuoParser.JavaScriptChannel - 收到JavaScript消息: ${message.message} [实例ID: $instanceId]');
          
          // 确保controller不为空
          if (controller == null) {
            LogUtil.e('SousuoParser.JavaScriptChannel - WebView控制器为空，无法处理JavaScript消息 [实例ID: $instanceId]');
            return;
          }
          
          if (message.message == 'CONTENT_CHANGED') {
            LogUtil.i('SousuoParser.JavaScriptChannel - 检测到页面内容发生变化 [实例ID: $instanceId]');
            contentChangedDetected = true;
            
            if (searchState['searchSubmitted'] == true && !completer.isCompleted) {
              LogUtil.i('SousuoParser.JavaScriptChannel - 开始提取媒体链接 [实例ID: $instanceId]');
              
              // 延迟一段时间确保内容完全加载
              final domChangeTimer = Timer(Duration(milliseconds: _TimingConfig.domChangeWaitMs), () {
                if (controller == null) {
                  LogUtil.e('SousuoParser.JavaScriptChannel - 延迟后WebView控制器为空 [实例ID: $instanceId]');
                  return;
                }
                
                _extractMediaLinks(
                  controller!, 
                  foundStreams, 
                  searchState['activeEngine'] == 'backup'
                );
                
                // 如果是主引擎但未找到媒体链接，延迟一下再检查
                if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
                  final extractCheckTimer = Timer(Duration(seconds: _TimingConfig.extractCheckSeconds), () {
                    if (foundStreams.isEmpty && !completer.isCompleted) {
                      LogUtil.i('SousuoParser.JavaScriptChannel - 主引擎未找到媒体链接，切换到备用引擎 [实例ID: $instanceId]');
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
            LogUtil.i('SousuoParser.JavaScriptChannel - 通过JavaScript通道添加媒体链接: ${message.message}, 当前列表大小: ${foundStreams.length}/${_maxStreams} [实例ID: $instanceId]');
            
            // 如果找到了第一个媒体链接，准备测试
            if (foundStreams.length == 1) {
              LogUtil.i('SousuoParser.JavaScriptChannel - 找到第一个媒体链接，准备测试 [实例ID: $instanceId]');
              
              final firstStreamTimer = Timer(Duration(milliseconds: _TimingConfig.domChangeWaitMs), () {
                if (!completer.isCompleted) {
                  _testStreamsAndGetFastest(foundStreams).then((String result) {
                    if (!completer.isCompleted) {
                      LogUtil.i('SousuoParser.JavaScriptChannel - 测试完成，返回结果 [实例ID: $instanceId]');
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
      LogUtil.i('SousuoParser.parse - JavaScript通道添加完成 [实例ID: $instanceId]');
      
      // 先尝试加载主搜索引擎
      LogUtil.i('SousuoParser.parse - 开始加载主搜索引擎: $_primaryEngine [实例ID: $instanceId]');
      await controller!.loadRequest(Uri.parse(_primaryEngine));
      LogUtil.i('SousuoParser.parse - 主搜索引擎加载请求已发送 [实例ID: $instanceId]');
      
      // 添加主引擎加载检查
      final earlyCheckTimer = Timer(Duration(seconds: _TimingConfig.engineEarlyCheckSeconds), () {
        // 确保controller不为空
        if (controller == null) {
          LogUtil.e('SousuoParser.earlyEngineCheck - WebView控制器为空 [实例ID: $instanceId]');
          return;
        }
        
        // 只检查尚未切换引擎的情况
        if (searchState['activeEngine'] == 'primary' && 
            searchState['searchSubmitted'] == false && 
            searchState['engineSwitched'] == false &&
            searchState['primaryEngineLoadFailed'] == false) {
          
          controller!.runJavaScriptReturningResult('document.body.innerHTML.length').then((result) {
            int contentLength = int.tryParse(result.toString()) ?? 0;
            
            if (contentLength < _minValidContentLength) { // 页面内容过少表示加载异常
              LogUtil.i('SousuoParser.earlyEngineCheck - 主引擎${_TimingConfig.engineEarlyCheckSeconds}秒后内容长度不足 ($contentLength 字符)，可能加载失败 [实例ID: $instanceId]');
              switchToBackupEngine();
            } else {
              LogUtil.i('SousuoParser.earlyEngineCheck - 主引擎${_TimingConfig.engineEarlyCheckSeconds}秒后内容长度正常 ($contentLength 字符)，继续等待 [实例ID: $instanceId]');
            }
          }).catchError((e) {
            LogUtil.e('SousuoParser.earlyEngineCheck - 检查主引擎内容时出错: $e [实例ID: $instanceId]');
            // 发生错误，考虑切换到备用引擎
            switchToBackupEngine();
          });
        }
      });
      registerTimer('earlyCheck', earlyCheckTimer);
      
      // 设置总体搜索超时
      LogUtil.i('SousuoParser.parse - 设置总体搜索超时: ${_timeoutSeconds}秒 [实例ID: $instanceId]');
      timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        LogUtil.i('SousuoParser.searchTimeout - 搜索总超时触发，当前状态: completer完成=${completer.isCompleted}, 找到流数量=${foundStreams.length} [实例ID: $instanceId]');
        
        if (!completer.isCompleted) {
          LogUtil.i('SousuoParser.searchTimeout - 搜索超时，共找到 ${foundStreams.length} 个媒体流地址 [实例ID: $instanceId]');
          
          if (foundStreams.isEmpty) {
            // 总超时前的最后尝试：如果当前是主引擎且没有找到流，尝试切换到备用引擎
            if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
              LogUtil.i('SousuoParser.searchTimeout - 主引擎未找到结果，最后尝试切换到备用引擎 [实例ID: $instanceId]');
              switchToBackupEngine();
              
              // 给备用引擎最多15秒时间处理
              final backupEngineTimer = Timer(Duration(seconds: _TimingConfig.backupEngineTimeoutSeconds), () {
                if (!completer.isCompleted) {
                  if (foundStreams.isEmpty) {
                    LogUtil.i('SousuoParser.searchTimeout - 备用引擎也未找到媒体流地址，返回ERROR [实例ID: $instanceId]');
                    completer.complete('ERROR');
                    cleanupResources();
                  } else {
                    LogUtil.i('SousuoParser.searchTimeout - 备用引擎找到 ${foundStreams.length} 个流，开始测试 [实例ID: $instanceId]');
                    _testStreamsAndGetFastest(foundStreams).then((String result) {
                      completer.complete(result);
                      cleanupResources();
                    });
                  }
                }
              });
              registerTimer('backupEngineTimeout', backupEngineTimer);
            } else {
              LogUtil.i('SousuoParser.searchTimeout - 未找到任何媒体流地址，返回ERROR [实例ID: $instanceId]');
              completer.complete('ERROR');
              cleanupResources();
            }
          } else {
            LogUtil.i('SousuoParser.searchTimeout - 开始测试找到的媒体流地址 [实例ID: $instanceId]');
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              LogUtil.i('SousuoParser.searchTimeout - 流地址测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'} [实例ID: $instanceId]');
              completer.complete(result);
              cleanupResources();
            });
          }
        }
      });
      registerTimer('timeout', timeoutTimer);
      
      // 等待结果
      LogUtil.i('SousuoParser.parse - 等待解析结果中... [实例ID: $instanceId]');
      final result = await completer.future;
      LogUtil.i('SousuoParser.parse - 解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'} [实例ID: $instanceId]');
      
      // 计算总耗时
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      LogUtil.i('SousuoParser.parse - 整个解析过程共耗时: ${endTimeMs - startMs}ms [实例ID: $instanceId]');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser.parse - 解析搜索页面失败 [实例ID: $instanceId]', e, stackTrace);
      
      // 如果出错但已有结果，返回最快的流
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 尽管出错，但已找到 ${foundStreams.length} 个媒体流地址，尝试测试 [实例ID: $instanceId]');
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          completer.complete(result);
        });
      } else if (!completer.isCompleted) {
        LogUtil.i('SousuoParser.parse - 出错且未找到媒体流地址，返回ERROR [实例ID: $instanceId]');
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      // 确保在所有情况下都调用资源清理
      cleanupResources();
    }
  }
  
  /// 处理WebView资源错误 - 优化错误处理逻辑
  static void _handleWebResourceError(WebResourceError error, Map<String, dynamic> searchState, Function switchToBackupEngine) {
    final String instanceId = searchState['instanceId'] as String;
    
    // 优化：跳过非关键资源错误的详细日志记录
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.css')) {
      // 非关键资源错误，仅记录简略信息
      return;
    }
    
    LogUtil.e('SousuoParser.onWebResourceError - WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url ?? "未知"} [实例ID: $instanceId]');
    
    // 关键错误代码集合
    final List<int> criticalErrorCodes = [
      -1,   // NET_ERROR
      -2,   // FAILED
      -3,   // ABORTED
      -6,   // CONNECTION_CLOSED
      -7,   // CONNECTION_RESET
      -101, // CONNECTION_REFUSED
      -105, // NAME_NOT_RESOLVED
      -106, // INTERNET_DISCONNECTED
      -118, // CONNECTION_TIMED_OUT
      -137, // NAME_RESOLUTION_FAILED
    ];
    
    // 如果主引擎关键资源加载出错，标记主引擎加载失败
    if (searchState['activeEngine'] == 'primary') {
      // 主引擎页面资源加载失败 - 检查url来确认是主引擎的关键资源
      bool isPrimaryEngineResource = error.url != null && (
        error.url!.contains('tonkiang.us') || 
        (_isPrimaryEngine(searchState['currentUrl'] ?? '') && error.url!.startsWith('/'))
      );
      
      if (isPrimaryEngineResource) {
        // 检查是否是关键错误
        bool isCriticalError = criticalErrorCodes.contains(error.errorCode);
        
        if (isCriticalError) {
          LogUtil.i('SousuoParser.onWebResourceError - 主引擎关键资源加载失败，错误码: ${error.errorCode} [实例ID: $instanceId]');
          searchState['primaryEngineLoadFailed'] = true;
          
          // 如果尚未提交搜索且未切换引擎，立即切换到备用引擎
          if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
            LogUtil.i('SousuoParser.onWebResourceError - 主引擎加载出错，切换到备用引擎 [实例ID: $instanceId]');
            switchToBackupEngine();
          }
        }
      }
    } 
    // 备用引擎也可能出现关键资源加载错误
    else if (searchState['activeEngine'] == 'backup') {
      bool isBackupEngineResource = error.url != null && (
        error.url!.contains('foodieguide.com') || 
        (_isBackupEngine(searchState['currentUrl'] ?? '') && error.url!.startsWith('/'))
      );
      
      if (isBackupEngineResource && criticalErrorCodes.contains(error.errorCode)) {
        LogUtil.i('SousuoParser.onWebResourceError - 备用引擎关键资源加载失败，错误码: ${error.errorCode} [实例ID: $instanceId]');
        // 备用引擎是最后的选择，无需额外处理
      }
    }
  }
  
  /// 检查URL是否是主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 检查URL是否是备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 注入DOM变化监听器
  static Future<void> _injectDomChangeMonitor(WebViewController controller) async {
    LogUtil.i('SousuoParser._injectDomChangeMonitor - 开始注入DOM变化监听器');
    
    try {
      await controller.runJavaScript('''
        (function() {
          console.log("注入DOM变化监听器");
          
          // 存储初始内容长度
          const initialContentLength = document.body.innerHTML.length;
          console.log("初始内容长度: " + initialContentLength);
          
          // 创建一个 MutationObserver 来监听 DOM 变化
          const observer = new MutationObserver(function(mutations) {
            // 计算当前内容长度
            const currentContentLength = document.body.innerHTML.length;
            
            // 检查内容长度变化是否显著
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            console.log("内容长度变化百分比: " + contentChangePct.toFixed(2) + "%");
            
            // 如果内容变化显著，通知应用
            if (contentChangePct > ${_significantChangePercent}) {  // 内容变化超过设定百分比
              console.log("检测到显著内容变化，通知应用");
              AppChannel.postMessage('CONTENT_CHANGED');
              
              // 停止观察，避免重复通知
              observer.disconnect();
            }
            
            // 同时检查是否有搜索结果表格或列表出现
            let hasSearchResults = false;
            mutations.forEach(function(mutation) {
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                for (let i = 0; i < mutation.addedNodes.length; i++) {
                  const node = mutation.addedNodes[i];
                  
                  // 查找新添加的表格或结果列表
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
                  
                  // 检查是否包含表格
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
              
              // 停止观察，避免重复通知
              observer.disconnect();
              
              // 主动查找和提取媒体链接
              try {
                console.log("自动提取页面中的媒体链接");
                // 获取所有带有onclick属性的复制按钮
                const copyButtons = document.querySelectorAll('img[onclick][src*="copy"], button[onclick], a[onclick]');
                console.log("找到 " + copyButtons.length + " 个可能的复制按钮");
                
                copyButtons.forEach(function(button, index) {
                  const onclickAttr = button.getAttribute('onclick');
                  if (onclickAttr) {
                    // 尝试提取URL
                    let match;
                    
                    // 尝试匹配主引擎格式
                    match = onclickAttr.match(/wqjs\\("([^"]+)/);
                    if (!match) {
                      // 尝试匹配备用引擎格式
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

          // 配置 observer 监听整个文档的子节点和属性变化
          observer.observe(document.body, { 
            childList: true, 
            subtree: true,
            attributes: true,
            characterData: true 
          });
          
          // 设置一个备用计时器，在3秒后检查页面，防止mutation事件未触发
          setTimeout(function() {
            // 获取所有表格和可能的结果容器
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
      LogUtil.logError('SousuoParser._injectDomChangeMonitor - 注入DOM变化监听器时出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单 - 统一处理两个引擎的表单提交
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    LogUtil.i('SousuoParser._submitSearchForm - 开始提交搜索表单，关键词: $searchKeyword');
    
    try {
      // 延迟确保页面完全加载
      LogUtil.i('SousuoParser._submitSearchForm - 等待页面完全加载 (${_TimingConfig.pageLoadWaitMs}ms)');
      await Future.delayed(Duration(milliseconds: _TimingConfig.pageLoadWaitMs));
      
      // 两个引擎使用相同的表单结构，可以使用统一的脚本
      final submitScript = '''
        (function() {
          console.log("搜索引擎：开始在页面中查找搜索表单元素");
          
          // 查找表单元素
          const form = document.getElementById('form1');
          const searchInput = document.getElementById('search');
          const submitButton = document.querySelector('input[name="Submit"]');
          
          if (!searchInput || !form) {
            console.log("未找到搜索表单元素: searchInput=" + (searchInput ? "存在" : "不存在") + ", form=" + (form ? "存在" : "不存在"));
            
            // 调试信息
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
          
          // 填写搜索关键词
          searchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
          console.log("填写搜索关键词: " + searchInput.value);
          
          // 点击提交按钮
          if (submitButton) {
            console.log("找到提交按钮，点击提交");
            submitButton.click();
            return true;
          } else {
            console.log("未找到名称为Submit的提交按钮，尝试其他方法");
            
            // 尝试查找其他提交按钮
            const otherSubmitButton = form.querySelector('input[type="submit"]');
            if (otherSubmitButton) {
              console.log("找到类型为submit的按钮，点击提交");
              otherSubmitButton.click();
              return true;
            } else {
              console.log("未找到任何提交按钮，直接提交表单");
              form.submit();
              return true;
            }
          }
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(submitScript);
      LogUtil.i('SousuoParser._submitSearchForm - 搜索表单提交结果: $result');
      
      // 等待一段时间，让表单提交和页面加载
      LogUtil.i('SousuoParser._submitSearchForm - 等待页面响应 (${_TimingConfig.formSubmitWaitSeconds}秒)');
      await Future.delayed(Duration(seconds: _TimingConfig.formSubmitWaitSeconds));
      
      return result.toString().toLowerCase() == 'true';
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._submitSearchForm - 提交搜索表单时出错', e, stackTrace);
      return false;
    }
  }
  
  /// 从搜索结果页面提取媒体链接 - 优化提取和处理逻辑
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine) async {
    LogUtil.i('SousuoParser._extractMediaLinks - 开始从${usingBackupEngine ? "备用" : "主"}搜索引擎提取媒体链接');
    
    try {
      // 直接获取HTML内容
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
      
      // 优化：使用更高效的正则表达式模式，减少不必要的匹配
      final List<RegExp> regexList = [
        // 主引擎格式
        RegExp('onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((http|https)://[^"\'\\)\\s]+)'),
        // 备用引擎格式
        RegExp('onclick="copyto\\((?:&quot;|"|\')?((http|https)://[^"\'\\)\\s]+)'),
        // 通用链接模式
        RegExp('data-url="((http|https)://[^"\'\\)\\s]+)')
      ];
      
      LogUtil.i('SousuoParser._extractMediaLinks - 使用多个正则表达式从HTML提取媒体链接');
      
      int totalMatches = 0;
      int addedCount = 0;
      
      // 优化：批量处理匹配结果，减少遍历次数
      final Set<String> potentialUrls = {};
      
      // 使用多个正则表达式提高匹配成功率
      for (final regex in regexList) {
        final matches = regex.allMatches(htmlContent);
        totalMatches += matches.length;
        
        for (final match in matches) {
          if (match.groupCount >= 1) {
            // 提取URL并处理特殊字符
            String? mediaUrl = match.group(1)?.trim();
            
            // 处理URL中的编码字符
            if (mediaUrl != null) {
              // 移除末尾可能存在的 &quot;
              if (mediaUrl.endsWith('&quot;')) {
                mediaUrl = mediaUrl.substring(0, mediaUrl.length - 6);
              }
              
              // 替换 &amp; 为 &
              mediaUrl = mediaUrl.replaceAll('&amp;', '&');
              
              if (mediaUrl.isNotEmpty) {
                potentialUrls.add(mediaUrl);
              }
            }
          }
        }
      }
      
      // 批量添加非重复的URL
      for (final url in potentialUrls) {
        if (!foundStreams.contains(url) && foundStreams.length < _maxStreams) {
          foundStreams.add(url);
          LogUtil.i('SousuoParser._extractMediaLinks - 从HTML提取到媒体链接: $url');
          addedCount++;
          
          // 限制提取数量
          if (foundStreams.length >= _maxStreams) {
            LogUtil.i('SousuoParser._extractMediaLinks - 已达到最大媒体链接数限制 ${_maxStreams}，停止提取');
            break;
          }
        }
      }
      
      LogUtil.i('SousuoParser._extractMediaLinks - 正则匹配总结果数: $totalMatches, 成功提取不重复链接: $addedCount');
      
      // 如果正则表达式匹配失败，记录HTML片段
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
        LogUtil.i('SousuoParser._extractMediaLinks - 未找到媒体链接，HTML片段: ${htmlContent.substring(0, sampleLength)}');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('SousuoParser._extractMediaLinks - 提取媒体链接时出错', e, stackTrace);
    }
    
    LogUtil.i('SousuoParser._extractMediaLinks - 提取媒体链接完成，当前列表大小: ${foundStreams.length}');
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址 - 优化测试逻辑
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
    
    // 测试结果
    final Map<String, int> results = {};
    bool foundValidStream = false;
    
    // 优化：预先检查是否有m3u8流，优先测试这些流
    final List<String> priorityStreams = streams.where((url) => url.contains('.m3u8')).toList();
    final List<String> normalStreams = streams.where((url) => !url.contains('.m3u8')).toList();
    final List<String> orderedStreams = [...priorityStreams, ...normalStreams];
    
    // 为每个流创建一个测试任务
    final tasks = orderedStreams.map((streamUrl) async {
      try {
        LogUtil.i('SousuoParser._testStreamsAndGetFastest - 开始测试流地址: $streamUrl');
        
        // 发送GET请求检查流可用性
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'GET',  // 使用GET请求测试
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
          cancelToken: cancelToken,
          retryCount: 1,  // 允许一次重试
        );
        
        // 如果请求成功，记录响应时间
        if (response != null) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          results[streamUrl] = responseTime;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 流地址 $streamUrl 响应成功，响应时间: ${responseTime}ms');
          
          // 找到第一个有效流后，延迟再返回，给其他测试一些机会
          if (!foundValidStream) {
            foundValidStream = true;
            
            // 设置短延迟，给其他请求一些时间完成
            Timer(Duration(milliseconds: _TimingConfig.flowTestWaitMs), () {
              if (!completer.isCompleted) {
                // 如果已经有多个结果，选择最快的
                if (results.length > 1) {
                  String fastestStream = results.entries
                      .reduce((a, b) => a.value < b.value ? a : b)
                      .key;
                  LogUtil.i('SousuoParser._testStreamsAndGetFastest - 找到最快的流: $fastestStream, 响应时间: ${results[fastestStream]}ms');
                  completer.complete(fastestStream);
                } else {
                  // 如果只有一个结果，直接返回
                  LogUtil.i('SousuoParser._testStreamsAndGetFastest - 只有一个有效流，直接返回: $streamUrl');
                  completer.complete(streamUrl);
                }
                
                // 取消其他请求
                cancelToken.cancel('已找到可用流');
              }
            });
          }
        }
      } catch (e) {
        LogUtil.e('SousuoParser._testStreamsAndGetFastest - 测试流地址 $streamUrl 时出错: $e');
      }
    }).toList();
    
    // 设置整体测试超时
    Timer(Duration(seconds: HttpUtil.defaultReceiveTimeoutSeconds + 2), () {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找出响应最快的流
          String fastestStream = results.entries
              .reduce((a, b) => a.value < b.value ? a : b)
              .key;
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，选择响应最快的流: $fastestStream');
          completer.complete(fastestStream);
        } else {
          // 如果没有可用结果，但有m3u8链接，返回第一个m3u8链接
          final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList();
          if (m3u8Streams.isNotEmpty) {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，无可用结果，但返回第一个m3u8链接: ${m3u8Streams.first}');
            completer.complete(m3u8Streams.first);
          } else {
            LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试超时，无可用结果，返回第一个链接: ${streams.first}');
            completer.complete(streams.first);  // 至少返回一个链接而不是ERROR
          }
        }
        
        // 取消所有未完成的请求
        cancelToken.cancel('测试超时');
      }
    });
    
    // 等待所有任务完成
    await Future.wait(tasks);
    
    // 如果所有测试都完成但completer未完成
    if (!completer.isCompleted) {
      if (results.isNotEmpty) {
        // 找出响应最快的流
        String fastestStream = results.entries
            .reduce((a, b) => a.value < b.value ? a : b)
            .key;
        LogUtil.i('SousuoParser._testStreamsAndGetFastest - 所有流测试完成，选择响应最快的流: $fastestStream');
        completer.complete(fastestStream);
      } else {
        // 如果没有可用结果，但有m3u8链接，返回第一个m3u8链接
        final m3u8Streams = streams.where((url) => url.contains('.m3u8')).toList();
        if (m3u8Streams.isNotEmpty) {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 所有流测试完成，无可用结果，但返回第一个m3u8链接: ${m3u8Streams.first}');
          completer.complete(m3u8Streams.first);
        } else {
          LogUtil.i('SousuoParser._testStreamsAndGetFastest - 所有流测试完成，无可用结果，返回第一个链接: ${streams.first}');
          completer.complete(streams.first);  // 至少返回一个链接而不是ERROR
        }
      }
    }
    
    // 返回结果
   final result = await completer.future;
   LogUtil.i('SousuoParser._testStreamsAndGetFastest - 测试完成，返回结果: $result');
   return result;
 }
 
 /// 清理WebView资源 - 优化资源清理逻辑
 static Future<void> _disposeWebView(WebViewController controller) async {
   LogUtil.i('SousuoParser._disposeWebView - 开始清理WebView资源');
   
   try {
     // 加载空白页面
     await controller.loadHtmlString('<html><body></body></html>');
     
     // 清除历史记录
     await controller.clearLocalStorage();
     await controller.clearCache();
     
     LogUtil.i('SousuoParser._disposeWebView - WebView资源清理完成');
   } catch (e) {
     LogUtil.e('SousuoParser._disposeWebView - 清理WebView资源时出错: $e');
   }
 }
 
 /// 同步锁实现 - 用于安全地访问和修改共享资源
 static void synchronized(String key, Function action) {
   // 使用简单的锁机制来处理并发访问
   try {
     action();
   } catch (e) {
     LogUtil.e('SousuoParser.synchronized - 执行同步操作时出错: $e');
   }
 }
}

/// 时间常量配置类 - 将所有时间常量集中管理
class _TimingConfig {
  // 单例实例
  static const _TimingConfig _instance = _TimingConfig._();
  
  // 构造函数
  const _TimingConfig._();
  
  // 页面加载和处理相关
  static const int pageLoadWaitMs = 1000; // 页面加载后等待时间
  static const int engineEarlyCheckSeconds = 10; // 主引擎早期检查时间
  static const int backupEngineTimeoutSeconds = 15; // 备用引擎超时时间
  static const int formSubmitWaitSeconds = 2; // 表单提交后等待时间
  
  // 流和内容处理相关
  static const int flowTestWaitMs = 300; // 流测试等待时间
  static const int domChangeWaitMs = 500; // DOM变化后等待时间
  static const int delayCheckSeconds = 3; // 延迟检查等待时间
  static const int extractCheckSeconds = 1; // 提取后检查等待时间
  static const int backupEngineLoadWaitMs = 300; // 切换到备用引擎前等待时间
  static const int cleanupRetryWaitMs = 100; // 清理重试等待时间
}
