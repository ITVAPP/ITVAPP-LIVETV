import 'dart:async';
import 'dart:math' as math;
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
  static const int _primaryEngineTimeoutSeconds = 10; // 主引擎超时时间
  
  // 标记是否使用简化脚本和备用提取方法
  static bool _useSimplifiedScripts = false;
  static bool _useBackupExtractionMethod = false;
  
  // 提取锁，防止并发提取
  static bool _extractionInProgress = false;
  
  // 错误计数器
  static final Map<ParseErrorType, int> _errorCounts = {};
  
  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url) async {
    ParserLogger.info('开始解析URL: $url', 'parse');
    final completer = Completer<String>();
    final List<String> foundStreams = [];
    final timeoutManager = TimeoutManager();
    WebViewController? controller;
    bool contentChangedDetected = false;
    final stateMachine = ParserStateMachine();
    
    // 状态对象 - 更健壮的结构
    final searchState = {
      'searchKeyword': '',
      'activeEngine': 'primary',
      'searchSubmitted': false,
      'startTimeMs': DateTime.now().millisecondsSinceEpoch,
      'engineSwitchInProgress': false,
      'extractionAttempts': 0,
      'errorCount': 0,
    };
    
    // 清理资源函数
    void cleanupResources() async {
      ParserLogger.info('开始清理资源', 'cleanupResources');
      
      // 取消所有计时器
      timeoutManager.cancelAll();
      
      // 清理WebView资源
      if (controller != null) {
        await _disposeWebView(controller!);
      }
      
      // 确保completer被完成
      if (!completer.isCompleted) {
        ParserLogger.info('Completer未完成，强制完成为ERROR', 'cleanupResources');
        completer.complete('ERROR');
      }
      
      ParserLogger.info('资源清理完成', 'cleanupResources');
    }
    
    // 切换到备用引擎
    Future<void> switchToBackupEngine() async {
      if (searchState['engineSwitchInProgress'] == true) {
        ParserLogger.info('引擎切换已在进行中，跳过', 'switchToBackupEngine');
        return;
      }
      
      searchState['engineSwitchInProgress'] = true;
      searchState['activeEngine'] = 'backup';
      searchState['searchSubmitted'] = false;
      
      ParserLogger.info('开始切换到备用引擎', 'switchToBackupEngine');
      
      try {
        await controller?.loadRequest(Uri.parse(_backupEngine));
        // 更新状态机
        stateMachine.transitionTo(ParserStateMachine.STATE_ENGINE_LOADING, {
          'engine': 'backup',
          'url': _backupEngine
        });
      } catch (e, stackTrace) {
        _handleError('switchToBackupEngine', e, stackTrace, 
          type: ParseErrorType.WEBVIEW_ERROR,
          searchState: searchState,
          controller: controller,
          completer: completer
        );
      }
      
      // 延迟重置切换状态
      Future.delayed(Duration(seconds: 2), () {
        searchState['engineSwitchInProgress'] = false;
        ParserLogger.info('引擎切换状态重置', 'switchToBackupEngine');
      });
    }
    
    try {
      // 从URL中提取搜索关键词
      ParserLogger.info('开始从URL中提取搜索关键词', 'parse');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        ParserLogger.error('参数验证失败: 缺少搜索关键词参数 clickText', 'parse');
        return 'ERROR';
      }
      
      ParserLogger.info('成功提取搜索关键词: $searchKeyword', 'parse');
      searchState['searchKeyword'] = searchKeyword;
      stateMachine.transitionTo(ParserStateMachine.STATE_INITIAL);
      
      // 创建WebView控制器
      ParserLogger.info('开始创建WebView控制器', 'parse');
      controller = await _createWebViewController();
      stateMachine.transitionTo(ParserStateMachine.STATE_WEBVIEW_READY);
      
      // 设置导航委托
      ParserLogger.info('开始设置WebView导航委托', 'parse');
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String pageUrl) {
          ParserLogger.info('页面开始加载: $pageUrl', 'onPageStarted');
        },
        onPageFinished: (String pageUrl) async {
          final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
          final startMs = searchState['startTimeMs'] as int;
          final loadTimeMs = currentTimeMs - startMs;
          ParserLogger.info('页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms', 'onPageFinished');
          
          // 忽略空白页面
          if (pageUrl == 'about:blank') {
            ParserLogger.info('空白页面加载完成，忽略', 'onPageFinished');
            return;
          }
          
          // 确定当前引擎类型
          bool isPrimaryEngine = _isPrimaryEngine(pageUrl);
          bool isBackupEngine = _isBackupEngine(pageUrl);
          
          if (!isPrimaryEngine && !isBackupEngine) {
            ParserLogger.info('未知页面加载完成: $pageUrl', 'onPageFinished');
            return;
          }
          
          // 更新当前活跃引擎和状态机
          if (isPrimaryEngine) {
            searchState['activeEngine'] = 'primary';
            ParserLogger.info('主搜索引擎页面加载完成', 'onPageFinished');
            stateMachine.transitionTo(ParserStateMachine.STATE_ENGINE_READY, {'engine': 'primary'});
            
            // 取消主引擎超时计时器
            timeoutManager.cancelTimeout('primaryEngine');
          } else if (isBackupEngine) {
            searchState['activeEngine'] = 'backup';
            ParserLogger.info('备用搜索引擎页面加载完成', 'onPageFinished');
            stateMachine.transitionTo(ParserStateMachine.STATE_ENGINE_READY, {'engine': 'backup'});
          }
          
          // 如果搜索还未提交，则提交搜索表单
          if (searchState['searchSubmitted'] == false) {
            ParserLogger.info('准备提交搜索表单', 'onPageFinished');
            
            // 防止重复提交，立即设置标志
            searchState['searchSubmitted'] = true;
            
            final success = await _submitSearchForm(controller!, searchKeyword);
            
            if (success) {
              ParserLogger.info('搜索表单提交成功，注入DOM变化监听器', 'onPageFinished');
              stateMachine.transitionTo(ParserStateMachine.STATE_SEARCH_SUBMITTED);
              
              // 注入DOM变化监听器
              await _injectDomChangeMonitor(controller!);
              
              // 添加延迟检查，防止监听器未生效
              timeoutManager.setTimeout('contentCheck', Duration(seconds: 3), () {
                if (!contentChangedDetected && !completer.isCompleted && 
                    stateMachine.currentState == ParserStateMachine.STATE_SEARCH_SUBMITTED) {
                  ParserLogger.info('延迟检查，强制提取媒体链接', 'onPageFinished');
                  _extractMediaLinks(controller!, foundStreams, isBackupEngine);
                }
              });
            } else {
              // 提交失败时重置标志
              searchState['searchSubmitted'] = false;
              ParserLogger.error('搜索表单提交失败', 'onPageFinished');
              
              // 如果是主引擎且提交失败，切换到备用引擎
              if (isPrimaryEngine) {
                ParserLogger.info('主引擎表单提交失败，切换到备用引擎', 'onPageFinished');
                await switchToBackupEngine();
              }
            }
          } else if (contentChangedDetected) {
            // 如果搜索已提交且检测到内容变化，尝试提取媒体链接
            ParserLogger.info('检测到内容变化，准备提取媒体链接', 'onPageFinished');
            stateMachine.transitionTo(ParserStateMachine.STATE_WAITING_RESULTS);
            
            int beforeExtractCount = foundStreams.length;
            await _extractMediaLinks(controller!, foundStreams, isBackupEngine);
            int afterExtractCount = foundStreams.length;
            
            if (afterExtractCount > beforeExtractCount) {
              ParserLogger.info('新增 ${afterExtractCount - beforeExtractCount} 个媒体链接，准备测试', 'onPageFinished');
              stateMachine.transitionTo(ParserStateMachine.STATE_LINKS_FOUND, {'linkCount': foundStreams.length});
              
              // 测试流并返回结果
              stateMachine.transitionTo(ParserStateMachine.STATE_TESTING_STREAMS);
              _testStreamsAndGetFastest(foundStreams).then((String result) {
                if (!completer.isCompleted) {
                  ParserLogger.info('完成解析过程，返回结果', 'onPageFinished');
                  completer.complete(result);
                  stateMachine.transitionTo(ParserStateMachine.STATE_COMPLETED, {'result': result});
                  cleanupResources();
                }
              });
            }
          }
        },
        onWebResourceError: (WebResourceError error) {
          // 不记录次要资源的错误
          if (error.url == null || _isMinorResourceUrl(error.url!)) {
            return;
          }
          
          ParserLogger.error('WebView资源加载错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url ?? "未知"}', 'onWebResourceError');
          
          // 增加错误计数
          searchState['errorCount'] = (searchState['errorCount'] as int) + 1;
          
          // 如果主引擎加载出错且搜索尚未提交，则切换到备用引擎
          if (searchState['activeEngine'] == 'primary' && 
              searchState['searchSubmitted'] == false && 
              error.url != null && 
              error.url!.contains('tonkiang.us')) {
            ParserLogger.info('主搜索引擎加载出错，切换到备用搜索引擎', 'onWebResourceError');
            switchToBackupEngine();
          }
          
          // 如果错误太多，考虑终止
          if (searchState['errorCount'] > 10 && !completer.isCompleted) {
            ParserLogger.error('错误次数过多，终止解析', 'onWebResourceError');
            stateMachine.transitionTo(ParserStateMachine.STATE_ERROR, {'reason': 'tooManyErrors'});
            completer.complete('ERROR');
            cleanupResources();
          }
        },
        onNavigationRequest: (NavigationRequest request) {
          // 监控导航请求，可以用来检测表单提交后的页面跳转
          ParserLogger.info('导航请求: ${request.url}', 'onNavigationRequest');
          
          // 允许所有导航请求
          return NavigationDecision.navigate;
        },
      ));
      ParserLogger.info('WebView导航委托设置完成', 'parse');
      
      // 添加JavaScript通道用于接收消息
      ParserLogger.info('开始添加JavaScript通道', 'parse');
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          ParserLogger.info('收到JavaScript消息: ${message.message}', 'JavaScriptChannel');
          
          if (message.message == 'CONTENT_CHANGED') {
            ParserLogger.info('检测到页面内容发生变化', 'JavaScriptChannel');
            contentChangedDetected = true;
            
            if (searchState['searchSubmitted'] == true && !completer.isCompleted) {
              ParserLogger.info('开始提取媒体链接', 'JavaScriptChannel');
              
              // 更新状态机
              if (stateMachine.currentState == ParserStateMachine.STATE_SEARCH_SUBMITTED) {
                stateMachine.transitionTo(ParserStateMachine.STATE_WAITING_RESULTS);
              }
              
              // 延迟一段时间确保内容完全加载
              Future.delayed(Duration(milliseconds: 500), () {
                _extractMediaLinks(
                  controller!, 
                  foundStreams, 
                  searchState['activeEngine'] == 'backup'
                );
              });
            }
          } else if (message.message.startsWith('http') && 
                     !foundStreams.contains(message.message) && 
                     foundStreams.length < _maxStreams) {
            foundStreams.add(message.message);
            ParserLogger.info('通过JavaScript通道添加媒体链接: ${message.message}, 当前列表大小: ${foundStreams.length}/${_maxStreams}', 'JavaScriptChannel');
            
            // 更新状态机
            stateMachine.transitionTo(ParserStateMachine.STATE_LINKS_FOUND, {'linkCount': foundStreams.length});
            
            // 如果找到了至少一个媒体链接，准备测试
            if (foundStreams.length == 1) {
              ParserLogger.info('找到第一个媒体链接，准备测试', 'JavaScriptChannel');
              
              Future.delayed(Duration(milliseconds: 500), () {
                if (!completer.isCompleted) {
                  stateMachine.transitionTo(ParserStateMachine.STATE_TESTING_STREAMS);
                  _testStreamsAndGetFastest(foundStreams).then((String result) {
                    if (!completer.isCompleted) {
                      ParserLogger.info('测试完成，返回结果', 'JavaScriptChannel');
                      completer.complete(result);
                      stateMachine.transitionTo(ParserStateMachine.STATE_COMPLETED, {'result': result});
                      cleanupResources();
                    }
                  });
                }
              });
            }
          }
        },
      );
      ParserLogger.info('JavaScript通道添加完成', 'parse');
      
      // 先尝试加载主搜索引擎
      ParserLogger.info('开始加载主搜索引擎: $_primaryEngine', 'parse');
      stateMachine.transitionTo(ParserStateMachine.STATE_ENGINE_LOADING, {
        'engine': 'primary',
        'url': _primaryEngine
      });
      
      await controller.loadRequest(Uri.parse(_primaryEngine));
      ParserLogger.info('主搜索引擎加载请求已发送', 'parse');
      
      // 设置主引擎连接超时
      ParserLogger.info('设置主搜索引擎连接超时: ${_primaryEngineTimeoutSeconds}秒', 'parse');
      timeoutManager.setTimeout('primaryEngine', Duration(seconds: _primaryEngineTimeoutSeconds), () {
        ParserLogger.info('主引擎连接超时检查触发', 'primaryEngineTimeout');
        
        // 仅当搜索尚未提交时切换
        if (searchState['searchSubmitted'] == false && 
            searchState['activeEngine'] == 'primary' &&
            stateMachine.currentState == ParserStateMachine.STATE_ENGINE_LOADING) {
          ParserLogger.info('主搜索引擎连接超时，切换到备用搜索引擎', 'primaryEngineTimeout');
          switchToBackupEngine();
        }
      });
      
      // 设置总体搜索超时
      ParserLogger.info('设置总体搜索超时: ${_timeoutSeconds}秒', 'parse');
      timeoutManager.setTimeout('globalSearch', Duration(seconds: _timeoutSeconds), () {
        ParserLogger.info('搜索总超时触发，当前状态: completer完成=${completer.isCompleted}, 找到流数量=${foundStreams.length}', 'searchTimeout');
        
        if (!completer.isCompleted) {
          ParserLogger.info('搜索超时，共找到 ${foundStreams.length} 个媒体流地址', 'searchTimeout');
          
          if (foundStreams.isEmpty) {
            ParserLogger.info('未找到任何媒体流地址，返回ERROR', 'searchTimeout');
            stateMachine.transitionTo(ParserStateMachine.STATE_ERROR, {'reason': 'timeout'});
            completer.complete('ERROR');
            cleanupResources();
          } else {
            ParserLogger.info('开始测试找到的媒体流地址', 'searchTimeout');
            stateMachine.transitionTo(ParserStateMachine.STATE_TESTING_STREAMS);
            _testStreamsAndGetFastest(foundStreams).then((String result) {
              ParserLogger.info('流地址测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}', 'searchTimeout');
              completer.complete(result);
              stateMachine.transitionTo(ParserStateMachine.STATE_COMPLETED, {'result': result});
              cleanupResources();
            });
          }
        }
      });
      
      // 等待结果
      ParserLogger.info('等待解析结果中...', 'parse');
      final result = await completer.future;
      ParserLogger.info('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}', 'parse');
      
      // 计算总耗时
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState['startTimeMs'] as int;
      ParserLogger.info('整个解析过程共耗时: ${endTimeMs - startMs}ms', 'parse');
      
      return result;
    } catch (e, stackTrace) {
      _handleError('parse', e, stackTrace, 
        type: ParseErrorType.UNKNOWN_ERROR,
        searchState: searchState,
        controller: controller,
        completer: completer
      );
      
      // 如果出错但已有结果，返回最快的流
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        ParserLogger.info('尽管出错，但已找到 ${foundStreams.length} 个媒体流地址，尝试测试', 'parse');
        stateMachine.transitionTo(ParserStateMachine.STATE_TESTING_STREAMS);
        _testStreamsAndGetFastest(foundStreams).then((String result) {
          completer.complete(result);
          stateMachine.transitionTo(ParserStateMachine.STATE_COMPLETED, {'result': result});
        });
      } else if (!completer.isCompleted) {
        ParserLogger.info('出错且未找到媒体流地址，返回ERROR', 'parse');
        stateMachine.transitionTo(ParserStateMachine.STATE_ERROR, {'reason': 'exception'});
        completer.complete('ERROR');
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      cleanupResources();
    }
  }
  
  /// 创建和配置WebView控制器
  static Future<WebViewController> _createWebViewController() async {
    ParserLogger.info('开始创建WebView控制器', '_createWebViewController');
    
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent);
    
    // 确保控制器创建完成
    await Future.delayed(Duration(milliseconds: 50));
    
    ParserLogger.info('WebView控制器创建完成', '_createWebViewController');
    return controller;
  }
  
  /// 检查URL是否是主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 检查URL是否是备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 检查是否是次要资源URL (忽略这些资源的错误)
  static bool _isMinorResourceUrl(String url) {
    return url.endsWith('.png') || 
           url.endsWith('.jpg') || 
           url.endsWith('.gif') || 
           url.endsWith('.css') ||
           url.endsWith('.ico');
  }
  
  /// 注入DOM变化监听器
  static Future<void> _injectDomChangeMonitor(WebViewController controller) async {
    ParserLogger.info('开始注入DOM变化监听器', '_injectDomChangeMonitor');
    
    try {
      // 使用简化版还是完整版监视脚本
      final monitorScript = _useSimplifiedScripts ? _getSimplifiedMonitorScript() : _getFullMonitorScript();
      
      await controller.runJavaScript(monitorScript);
      ParserLogger.info('DOM变化监听器注入完成', '_injectDomChangeMonitor');
    } catch (e, stackTrace) {
      _handleError('_injectDomChangeMonitor', e, stackTrace, type: ParseErrorType.JAVASCRIPT_ERROR);
      
      // 出错时尝试使用简化脚本
      if (!_useSimplifiedScripts) {
        _useSimplifiedScripts = true;
        ParserLogger.info('尝试使用简化监视脚本', '_injectDomChangeMonitor');
        await _injectDomChangeMonitor(controller);
      }
    }
  }
  
  /// 获取完整版DOM监视脚本
  static String _getFullMonitorScript() {
    return '''
      (function() {
        // 防止重复注入
        if (window._domMonitorInstalled) {
          console.log("DOM监视器已安装，跳过");
          return;
        }
        
        window._domMonitorInstalled = true;
        console.log("安装DOM变化监视器");
        
        // 记录初始内容特征
        const initialState = {
          bodyLength: document.body.innerHTML.length,
          tableCount: document.querySelectorAll('table').length,
          linkCount: document.querySelectorAll('a').length
        };
        
        console.log("初始状态:", JSON.stringify(initialState));
        
        // 检测内容变化的函数
        function checkForContentChanges() {
          const currentState = {
            bodyLength: document.body.innerHTML.length,
            tableCount: document.querySelectorAll('table').length,
            linkCount: document.querySelectorAll('a').length
          };
          
          // 计算变化
          const lengthChange = Math.abs(currentState.bodyLength - initialState.bodyLength);
          const lengthChangePct = (lengthChange / initialState.bodyLength) * 100;
          const tableChange = currentState.tableCount - initialState.tableCount;
          const linkChange = currentState.linkCount - initialState.linkCount;
          
          console.log("内容变化检测 - 长度变化: " + lengthChangePct.toFixed(1) + "%, 表格变化: " + tableChange + ", 链接变化: " + linkChange);
          
          // 如果有显著变化，通知应用
          if (lengthChangePct > 10 || tableChange > 0 || linkChange > 3) {
            console.log("检测到显著内容变化");
            
            // 查找可能包含媒体链接的元素
            extractAndSendLinks();
            
            // 通知应用内容已变化
            AppChannel.postMessage('CONTENT_CHANGED');
          }
        }
        
        // 提取和发送链接的函数
        function extractAndSendLinks() {
          // 获取所有可能的拷贝按钮
          const copyButtons = document.querySelectorAll('img[onclick], button[onclick], a[onclick]');
          console.log("找到 " + copyButtons.length + " 个可能的复制按钮");
          
          copyButtons.forEach(function(button, index) {
            const onclickAttr = button.getAttribute('onclick') || '';
            
            // 尝试几种不同的模式匹配媒体链接
            [/wqjs\\s*\\(\\s*['"]([^'"]+)['"]\\s*\\)/, 
             /copyto\\s*\\(\\s*['"]([^'"]+)['"]\\s*\\)/, 
             /copyUrl\\s*\\(\\s*['"]([^'"]+)['"]\\s*\\)/].forEach(function(pattern) {
              const match = onclickAttr.match(pattern);
              if (match && match[1] && match[1].startsWith('http')) {
                console.log("按钮 #" + index + " 提取到URL: " + match[1]);
                AppChannel.postMessage(match[1]);
              }
            });
          });
        }
        
        // 设置 MutationObserver
        const observer = new MutationObserver(function(mutations) {
          // 防止过于频繁检测
          if (window._checkTimer) {
            clearTimeout(window._checkTimer);
          }
          
          // 延迟检测，等待一组变化完成
          window._checkTimer = setTimeout(checkForContentChanges, 300);
        });

        // 配置监视选项
        observer.observe(document.body, { 
          childList: true, 
          subtree: true,
          attributes: false,
          characterData: false 
        });
        
        // 保存观察者引用以便后续清理
        window._appMonitorObserver = observer;
        
        // 设置备用计时器，在3秒后检查页面，防止mutation事件未触发
        const backupTimer = setTimeout(function() {
          // 获取所有表格和可能的结果容器
          const tables = document.querySelectorAll('table');
          const resultContainers = document.querySelectorAll('.result, .result-item, .search-result');
          
          if (tables.length > 0 || resultContainers.length > 0) {
            console.log("备用计时器检测到可能的搜索结果");
            checkForContentChanges();
          }
        }, 3000);
        
        // 存储计时器引用
        window._appTimers = window._appTimers || [];
        window._appTimers.push(backupTimer);
        
        console.log("DOM监视器安装完成");
      })();
    ''';
  }
  
  /// 获取简化版DOM监视脚本
  static String _getSimplifiedMonitorScript() {
    return '''
      (function() {
        // 防止重复注入
        if (window._domMonitorInstalled) {
          console.log("已有监视器");
          return;
        }
        
        window._domMonitorInstalled = true;
        console.log("安装简化监视器");
        
        // 直接查找和提取链接
        function findAndSendLinks() {
          // 收集所有onclick属性
          let elements = document.querySelectorAll('[onclick]');
          console.log("找到 " + elements.length + " 个可能包含链接的元素");
          
          let foundLinks = 0;
          elements.forEach(function(el) {
            let onclick = el.getAttribute('onclick') || '';
            let url = '';
            
            // 简单提取URL
            if (onclick.indexOf('http') !== -1) {
              let start = onclick.indexOf('http');
              let end = onclick.indexOf(')', start);
              if (end === -1) end = onclick.indexOf('"', start);
              if (end === -1) end = onclick.indexOf("'", start);
              if (end === -1) end = onclick.length;
              
              url = onclick.substring(start, end).replace(/['",)]/g, '');
              
              if (url.startsWith('http')) {
                console.log("提取到URL: " + url);
                AppChannel.postMessage(url);
                foundLinks++;
              }
            }
          });
          
          console.log("共发送 " + foundLinks + " 个链接");
          AppChannel.postMessage('CONTENT_CHANGED');
        }
        
        // 立即执行一次查找
        setTimeout(findAndSendLinks, 1000);
        
        // 每隔2秒检查一次
        const intervalId = setInterval(findAndSendLinks, 2000);
        
        // 存储引用以便清理
        window._appTimers = window._appTimers || [];
        window._appTimers.push(intervalId);
        
        /// 获取简化版DOM监视脚本
  static String _getSimplifiedMonitorScript() {
    return '''
      (function() {
        // 防止重复注入
        if (window._domMonitorInstalled) {
          console.log("已有监视器");
          return;
        }
        
        window._domMonitorInstalled = true;
        console.log("安装简化监视器");
        
        // 直接查找和提取链接
        function findAndSendLinks() {
          // 收集所有onclick属性
          let elements = document.querySelectorAll('[onclick]');
          console.log("找到 " + elements.length + " 个可能包含链接的元素");
          
          let foundLinks = 0;
          elements.forEach(function(el) {
            let onclick = el.getAttribute('onclick') || '';
            let url = '';
            
            // 简单提取URL
            if (onclick.indexOf('http') !== -1) {
              let start = onclick.indexOf('http');
              let end = onclick.indexOf(')', start);
              if (end === -1) end = onclick.indexOf('"', start);
              if (end === -1) end = onclick.indexOf("'", start);
              if (end === -1) end = onclick.length;
              
              url = onclick.substring(start, end).replace(/['",)]/g, '');
              
              if (url.startsWith('http')) {
                console.log("提取到URL: " + url);
                AppChannel.postMessage(url);
                foundLinks++;
              }
            }
          });
          
          console.log("共发送 " + foundLinks + " 个链接");
          AppChannel.postMessage('CONTENT_CHANGED');
        }
        
        // 立即执行一次查找
        setTimeout(findAndSendLinks, 1000);
        
        // 每隔2秒检查一次
        const intervalId = setInterval(findAndSendLinks, 2000);
        
        // 存储引用以便清理
        window._appTimers = window._appTimers || [];
        window._appTimers.push(intervalId);
        
        // 5秒后停止检查
        setTimeout(function() {
          clearInterval(intervalId);
          console.log("简化监视器完成工作");
        }, 5000);
      })();
    ''';
  }
  
  /// 提交搜索表单 - 统一处理两个引擎的表单提交
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    ParserLogger.info('开始提交搜索表单，关键词: $searchKeyword', '_submitSearchForm');
    
    try {
      // 延迟一下确保页面完全加载
      ParserLogger.info('等待页面完全加载 (500ms)', '_submitSearchForm');
      await Future.delayed(Duration(milliseconds: 500));
      
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
            
            // 备用策略 - 尝试查找任何表单和搜索输入
            const anyForm = document.forms[0];
            const anySearchInput = document.querySelector('input[type="text"]');
            
            if (anyForm && anySearchInput) {
              console.log("找到备用表单和输入框");
              anySearchInput.value = "${searchKeyword.replaceAll('"', '\\"')}";
              
              // 尝试查找提交按钮
              const anySubmitButton = anyForm.querySelector('input[type="submit"]');
              if (anySubmitButton) {
                console.log("找到备用提交按钮，点击提交");
                anySubmitButton.click();
                return true;
              } else {
                console.log("未找到提交按钮，直接提交表单");
                anyForm.submit();
                return true;
              }
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
      ParserLogger.info('搜索表单提交结果: $result', '_submitSearchForm');
      
      // 等待一段时间，让表单提交和页面加载
      ParserLogger.info('等待页面响应 (2秒)', '_submitSearchForm');
      await Future.delayed(Duration(seconds: 2));
      
      return result.toString().toLowerCase() == 'true';
    } catch (e, stackTrace) {
      _handleError('_submitSearchForm', e, stackTrace, type: ParseErrorType.JAVASCRIPT_ERROR);
      return false;
    }
  }
  
  /// 从搜索结果页面提取媒体链接
  static Future<void> _extractMediaLinks(WebViewController controller, List<String> foundStreams, bool usingBackupEngine) async {
    // 检查是否已经在提取过程中
    if (_extractionInProgress) {
      ParserLogger.info('已有提取过程在进行中，跳过本次提取', '_extractMediaLinks');
      return;
    }
    
    _extractionInProgress = true;
    ParserLogger.info('开始从${usingBackupEngine ? "备用" : "主"}搜索引擎提取媒体链接', '_extractMediaLinks');
    
    try {
      // 如果设置了使用备用提取方法，直接从HTML中提取
      if (_useBackupExtractionMethod) {
        await _extractMediaLinksFromHtml(controller, foundStreams);
        return;
      }
      
      // 注入脚本提取媒体链接
      ParserLogger.info('注入JavaScript脚本提取媒体链接', '_extractMediaLinks');
      final extractScript = '''
        (function() {
          console.log("开始在页面中查找带有onclick属性的复制按钮");
          // 获取所有带有onclick属性的复制按钮和链接
          const copyButtons = document.querySelectorAll('[onclick]');
          console.log("找到 " + copyButtons.length + " 个可能的复制按钮");
          
          // 从onclick属性中提取URL
          let foundUrls = 0;
          copyButtons.forEach(function(button, index) {
            const onclickAttr = button.getAttribute('onclick') || '';
            if (onclickAttr.indexOf('http') !== -1) {
              // 根据不同搜索引擎使用不同的提取正则
              const patterns = ${usingBackupEngine ? 
                '[/copyto\\\\s*\\\\(\\\\s*[\'"]([^\'"]+)[\'"]\\\\s*\\\\)/, /copy\\\\s*\\\\(\\\\s*[\'"]([^\'"]+)[\'"]\\\\s*\\\\)/]' : 
                '[/wqjs\\\\s*\\\\(\\\\s*[\'"]([^\'"]+)[\'"]\\\\s*\\\\)/, /play\\\\s*\\\\(\\\\s*[\'"]([^\'"]+)[\'"]\\\\s*\\\\)/]'};
              
              // 尝试每种模式
              patterns.forEach(function(pattern) {
                const match = onclickAttr.match(pattern);
                if (match && match[1]) {
                  const url = match[1];
                  console.log("按钮#" + index + " 提取到URL: " + url);
                  if (url.startsWith('http')) {
                    AppChannel.postMessage(url);
                    foundUrls++;
                  }
                }
              });
              
              // 如果正则没匹配到，尝试简单提取
              if (foundUrls === 0) {
                let start = onclickAttr.indexOf('http');
                if (start !== -1) {
                  let end = onclickAttr.indexOf(')', start);
                  if (end === -1) end = onclickAttr.indexOf('"', start);
                  if (end === -1) end = onclickAttr.indexOf("'", start);
                  if (end === -1) end = onclickAttr.length;
                  
                  const url = onclickAttr.substring(start, end).replace(/['",)]/g, '');
                  if (url.startsWith('http')) {
                    console.log("通过简单方法提取到URL: " + url);
                    AppChannel.postMessage(url);
                    foundUrls++;
                  }
                }
              }
            }
          });
          
          console.log("通过JavaScript通道发送了 " + foundUrls + " 个媒体链接");
          return foundUrls;
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(extractScript);
      final int foundByJS = int.tryParse(result.toString()) ?? 0;
      
      // 等待JavaScript执行完成
      ParserLogger.info('JavaScript提取完成，找到 $foundByJS 个链接', '_extractMediaLinks');
      await Future.delayed(Duration(milliseconds: 500));
      
      // 如果JavaScript通道没有获取到足够的链接，尝试从HTML中提取
      if (foundStreams.isEmpty || foundByJS == 0) {
        ParserLogger.info('通过JavaScript通道未获取到足够链接，尝试从HTML中提取', '_extractMediaLinks');
        await _extractMediaLinksFromHtml(controller, foundStreams);
      }
    } catch (e, stackTrace) {
      _handleError('_extractMediaLinks', e, stackTrace, type: ParseErrorType.EXTRACTION_ERROR);
      
      // 出错时切换到备用提取方法
      _useBackupExtractionMethod = true;
      ParserLogger.info('提取出错，切换到备用提取方法', '_extractMediaLinks');
      
      // 尝试使用备用方法提取
      await _extractMediaLinksFromHtml(controller, foundStreams);
    } finally {
      _extractionInProgress = false;
      ParserLogger.info('提取过程结束，释放锁', '_extractMediaLinks');
    }
  }
  
  /// 从HTML中提取媒体链接的备用方法
  static Future<void> _extractMediaLinksFromHtml(WebViewController controller, List<String> foundStreams) async {
    ParserLogger.info('开始从HTML中提取媒体链接', '_extractMediaLinksFromHtml');
    
    try {
      final html = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML'
      );
      
      // 清理HTML字符串
      String htmlContent = html.toString();
      ParserLogger.info('获取到HTML，长度: ${htmlContent.length}', '_extractMediaLinksFromHtml');
      
      if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
        htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                  .replaceAll('\\"', '"')
                  .replaceAll('\\n', '\n');
        ParserLogger.info('清理HTML字符串，处理后长度: ${htmlContent.length}', '_extractMediaLinksFromHtml');
      }
      
      // 使用多个正则表达式提取媒体URL
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
        
        // 通用正则 - 找出所有onclick中包含http的部分
        RegExp(r'onclick="[^"]*?(http[s]?://[^\"\')\s]+)'),
      ];
      
      ParserLogger.info('使用正则表达式从HTML提取媒体链接', '_extractMediaLinksFromHtml');
      
      // 对每种正则表达式尝试匹配
      int totalMatches = 0;
      int addedCount = 0;
      
      for (final regex in regexPatterns) {
        final matches = regex.allMatches(htmlContent);
        totalMatches += matches.length;
        
        for (final match in matches) {
          if (match.groupCount >= 1) {
            final mediaUrl = match.group(1)?.trim();
            if (mediaUrl != null && 
                mediaUrl.isNotEmpty && 
                !foundStreams.contains(mediaUrl) &&
                mediaUrl.startsWith('http')) {
              foundStreams.add(mediaUrl);
              ParserLogger.info('从HTML提取到媒体链接: $mediaUrl', '_extractMediaLinksFromHtml');
              addedCount++;
              
              // 限制提取数量
              if (foundStreams.length >= _maxStreams) {
                ParserLogger.info('已达到最大媒体链接数限制 $_maxStreams，停止提取', '_extractMediaLinksFromHtml');
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
      
      ParserLogger.info('正则匹配总结果数: $totalMatches, 成功提取不重复链接: $addedCount', '_extractMediaLinksFromHtml');
      
      // 如果正则表达式匹配失败，尝试使用更简单的方法
      if (addedCount == 0 && totalMatches == 0) {
        // 简单查找所有 http:// 和 https:// 开头的字符串
        final simpleHttpRegex = RegExp(r'(https?://[^\s\'"()<>]+)');
        final simpleMatches = simpleHttpRegex.allMatches(htmlContent);
        
        for (final match in simpleMatches) {
          if (match.groupCount >= 1) {
            String mediaUrl = match.group(1)?.trim() ?? '';
            
            // 清理URL末尾的标点符号
            if (mediaUrl.isNotEmpty) {
              if (mediaUrl.endsWith('"') || mediaUrl.endsWith("'") || 
                  mediaUrl.endsWith(')') || mediaUrl.endsWith(',') ||
                  mediaUrl.endsWith(';')) {
                mediaUrl = mediaUrl.substring(0, mediaUrl.length - 1);
              }
              
              // 检查是否可能是流媒体URL
              if (_isPotentialStreamUrl(mediaUrl) && 
                  !foundStreams.contains(mediaUrl) &&
                  foundStreams.length < _maxStreams) {
                foundStreams.add(mediaUrl);
                ParserLogger.info('通过简单方法提取到疑似媒体链接: $mediaUrl', '_extractMediaLinksFromHtml');
                addedCount++;
              }
            }
          }
        }
        
        ParserLogger.info('简单提取方法结果: 找到 $addedCount 个疑似媒体链接', '_extractMediaLinksFromHtml');
      }
      
      // 仍然没有找到任何链接，记录HTML片段以便调试
      if (foundStreams.isEmpty) {
        int sampleLength = math.min(2000, htmlContent.length);
        ParserLogger.info('未找到媒体链接，HTML片段: ${htmlContent.substring(0, sampleLength)}', '_extractMediaLinksFromHtml');
      }
    } catch (e, stackTrace) {
      _handleError('_extractMediaLinksFromHtml', e, stackTrace, type: ParseErrorType.EXTRACTION_ERROR);
    }
    
    ParserLogger.info('HTML提取完成，当前链接列表大小: ${foundStreams.length}', '_extractMediaLinksFromHtml');
  }
  
  /// 判断URL是否可能是流媒体URL
  static bool _isPotentialStreamUrl(String url) {
    // 检查常见的流媒体URL特征
    return url.contains('.m3u8') || 
           url.contains('.ts') || 
           url.contains('/live/') || 
           url.contains('/play/') || 
           url.contains('/stream/') ||
           url.contains('/iptv/') ||
           url.contains('?c=') ||
           url.contains('.tv/') ||
           url.contains(':8080/') ||
           url.contains(':1935/');
  }
  
  /// 测试所有流媒体地址并返回响应最快的有效地址
  static Future<String> _testStreamsAndGetFastest(List<String> streams) async {
    if (streams.isEmpty) {
      ParserLogger.info('无流地址可测试，返回ERROR', '_testStreamsAndGetFastest');
      return 'ERROR';
    }
    
    ParserLogger.info('开始测试 ${streams.length} 个媒体流地址的响应速度', '_testStreamsAndGetFastest');
    
    // 创建一个取消标记和完成器
    final cancelToken = CancelToken();
    final completer = Completer<String>();
    final Map<String, int> results = {};
    
    // 测试单个流的函数
    Future<bool> testStream(String streamUrl) async {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      ParserLogger.info('开始测试流地址: $streamUrl', '_testStreamsAndGetFastest');
      
      try {
        // 使用HEAD请求快速检查可用性
        final headResponse = await HttpUtil().getRequestWithResponse(
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
        
        if (headResponse == null) return false;
        
        // 获取响应时间
        final headResponseTime = DateTime.now().millisecondsSinceEpoch - startTime;
        ParserLogger.info('HEAD请求成功，响应时间: ${headResponseTime}ms', '_testStreamsAndGetFastest');
        
        // 记录时间并返回结果
        results[streamUrl] = headResponseTime;
        
        // 如果HEAD请求成功，尝试获取内容
        bool isValidStream = false;
        
        // 对于m3u8链接，尝试获取内容验证
        if (streamUrl.contains('.m3u8')) {
          try {
            final getResponse = await HttpUtil().getRequestWithResponse(
              streamUrl,
              options: Options(
                headers: HeadersConfig.generateHeaders(url: streamUrl),
                method: 'GET',
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
            
            if (getResponse != null) {
              final contentType = getResponse.headers.value('content-type') ?? '';
              final data = getResponse.data as List<int>? ?? [];
              
              // 验证m3u8内容
              if (contentType.contains('mpegurl') || 
                  (data.length > 4 && String.fromCharCodes(data.take(4)).startsWith('#EXT'))) {
                isValidStream = true;
                ParserLogger.info('验证m3u8内容成功', '_testStreamsAndGetFastest');
              }
            }
          } catch (e) {
            ParserLogger.info('获取m3u8内容出错: $e', '_testStreamsAndGetFastest');
          }
        } else {
          // 非m3u8链接，直接认为HEAD请求成功即可
          isValidStream = true;
        }
        
        final endTime = DateTime.now().millisecondsSinceEpoch;
        final totalResponseTime = endTime - startTime;
        
        ParserLogger.logStreamTest(streamUrl, isValidStream, totalResponseTime);
        
        return isValidStream;
      } catch (e) {
        final endTime = DateTime.now().millisecondsSinceEpoch;
        ParserLogger.error('测试流地址 $streamUrl 失败，耗时: ${endTime - startTime}ms', '_testStreamsAndGetFastest', e);
        return false;
      }
    }
    
    // 设置测试超时保护
    Timer(Duration(seconds: _httpRequestTimeoutSeconds + 1), () {
      if (!completer.isCompleted) {
        if (results.isNotEmpty) {
          // 找出响应最快的流
          String fastestStream = results.entries
              .reduce((a, b) => a.value < b.value ? a : b)
              .key;
          ParserLogger.info('测试超时，选择响应最快的流: $fastestStream，响应时间: ${results[fastestStream]}ms', '_testStreamsAndGetFastest');
          completer.complete(fastestStream);
        } else {
          ParserLogger.info('测试超时，无可用结果，返回ERROR', '_testStreamsAndGetFastest');
          completer.complete('ERROR');
        }
        
        // 取消所有未完成的请求
        cancelToken.cancel('测试超时');
      }
    });
    
    // 并行测试所有流
    for (final stream in streams) {
      testStream(stream).then((isValid) {
        if (isValid && !completer.isCompleted) {
          ParserLogger.info('找到可用流: $stream，响应时间: ${results[stream]}ms', '_testStreamsAndGetFastest');
          completer.complete(stream);
          // 取消其他请求
          cancelToken.cancel('已找到可用流');
        }
      });
    }
    
    // 等待结果
    final result = await completer.future;
    ParserLogger.info('测试完成，返回结果: $result', '_testStreamsAndGetFastest');
    return result;
  }
  
  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    ParserLogger.info('开始清理WebView资源', '_disposeWebView');
    
    try {
      // 取消所有JavaScript监听器
      await controller.runJavaScript('''
        (function() {
          // 清理DOM监视器
          if (window._appMonitorObserver) {
            window._appMonitorObserver.disconnect();
            window._appMonitorObserver = null;
            console.log("已移除DOM监视器");
          }
          
          // 清理计时器
          if (window._appTimers && window._appTimers.length > 0) {
            window._appTimers.forEach(function(t) {
              clearTimeout(t);
              clearInterval(t);
            });
            window._appTimers = [];
            console.log("已清理计时器");
          }
          
          // 移除DOM属性
          window._domMonitorInstalled = false;
          
          console.log("已清理页面资源");
        })();
      ''').catchError((e) {
        ParserLogger.error('清理JavaScript资源时出错', '_disposeWebView', e);
      });
      
      // 加载空白页
      await controller.loadHtmlString('<html><body></body></html>');
      
      // 等待空白页加载完成
      await Future.delayed(Duration(milliseconds: 100));
      
      // 清除缓存和存储
      await controller.clearLocalStorage();
      await controller.clearCache();
      
      ParserLogger.info('WebView资源清理完成', '_disposeWebView');
    } catch (e) {
      ParserLogger.error('清理WebView资源时出错', '_disposeWebView', e);
    }
  }
  
  /// 定义错误处理函数
  static void _handleError(String operation, dynamic error, StackTrace? stackTrace, {
    ParseErrorType type = ParseErrorType.UNKNOWN_ERROR,
    Map<String, dynamic>? searchState,
    WebViewController? controller,
    Completer<String>? completer
  }) {
    final errorType = _getErrorTypeString(type);
    ParserLogger.error('$operation - $errorType', operation, error, stackTrace);
    
    // 记录错误计数
    _errorCounts[type] = (_errorCounts[type] ?? 0) + 1;
    
    // 根据错误类型和次数采取恢复策略
    switch (type) {
      case ParseErrorType.NETWORK_ERROR:
        if (_errorCounts[type]! <= 2) {
          // 重试网络请求，但减少超时时间
          _httpRequestTimeoutSeconds = math.max(2, _httpRequestTimeoutSeconds - 1);
          ParserLogger.info('网络错误恢复: 调整超时为 $_httpRequestTimeoutSeconds 秒', operation);
        } else if (searchState != null && searchState['activeEngine'] == 'primary') {
          // 如果是主引擎的网络错误，尝试切换到备用引擎
          searchState['engineSwitchInProgress'] = true;
          searchState['activeEngine'] = 'backup';
          searchState['searchSubmitted'] = false;
          controller?.loadRequest(Uri.parse(_backupEngine));
        }
        break;
        
      case ParseErrorType.JAVASCRIPT_ERROR:
        // 尝试使用简化版脚本
        _useSimplifiedScripts = true;
        ParserLogger.info('JavaScript错误恢复: 启用简化脚本模式', operation);
        break;
        
      case ParseErrorType.EXTRACTION_ERROR:
        // 使用备用提取方法
        _useBackupExtractionMethod = true;
        ParserLogger.info('提取错误恢复: 启用备用提取方法', operation);
        break;
        
      case ParseErrorType.WEBVIEW_ERROR:
        // WebView错误，可能需要完全重建
        if (_errorCounts[type]! > 2 && completer != null && !completer.isCompleted) {
          ParserLogger.info('WebView错误过多，终止解析', operation);
          completer.complete('ERROR');
        }
        break;
        
      default:
        // 默认错误处理
        if (completer != null && !completer.isCompleted && _isCriticalError(error)) {
          ParserLogger.info('检测到关键错误，终止解析', operation);
          completer.complete('ERROR');
        }
        break;
    }
  }
  
  /// 获取错误类型的描述
  static String _getErrorTypeString(ParseErrorType type) {
    switch (type) {
      case ParseErrorType.NETWORK_ERROR: return "网络错误";
      case ParseErrorType.TIMEOUT_ERROR: return "超时错误";
      case ParseErrorType.JAVASCRIPT_ERROR: return "JavaScript执行错误";
      case ParseErrorType.EXTRACTION_ERROR: return "内容提取错误";
      case ParseErrorType.STREAM_TEST_ERROR: return "流测试错误";
      case ParseErrorType.WEBVIEW_ERROR: return "WebView错误";
      case ParseErrorType.UNKNOWN_ERROR: return "未知错误";
    }
  }
  
  /// 判断是否是关键错误
  static bool _isCriticalError(dynamic error) {
    if (error is Exception) {
      final errorMsg = error.toString().toLowerCase();
      return errorMsg.contains('permission') || 
             errorMsg.contains('security') || 
             errorMsg.contains('fatal') ||
             errorMsg.contains('timeout') ||
             errorMsg.contains('memory');
    }
    return false;
  }
}

/// 错误类型枚举
enum ParseErrorType {
  NETWORK_ERROR,
  TIMEOUT_ERROR,
  JAVASCRIPT_ERROR,
  EXTRACTION_ERROR,
  STREAM_TEST_ERROR,
  WEBVIEW_ERROR,
  UNKNOWN_ERROR
}

/// 专用的解析器日志类
class ParserLogger {
  static const String TAG = "SousuoParser";
  static const int MAX_LOG_CONTENT_LENGTH = 1000;
  
  // 不同级别的日志方法
  static void info(String message, [String? method]) {
    _log('i', message, method);
  }
  
  static void debug(String message, [String? method]) {
    _log('d', message, method);
  }
  
  static void error(String message, [String? method, dynamic error, StackTrace? stackTrace]) {
    _log('e', message, method);
    if (error != null) {
      String errorMessage = error.toString();
      if (errorMessage.length > MAX_LOG_CONTENT_LENGTH) {
        errorMessage = errorMessage.substring(0, MAX_LOG_CONTENT_LENGTH) + "... (已截断)";
      }
      LogUtil.e('$TAG.$method - 错误详情: $errorMessage');
      
      if (stackTrace != null) {
        String stackTraceStr = stackTrace.toString();
        if (stackTraceStr.length > MAX_LOG_CONTENT_LENGTH) {
          stackTraceStr = stackTraceStr.substring(0, MAX_LOG_CONTENT_LENGTH) + "... (已截断)";
        }
        LogUtil.e('$TAG.$method - 堆栈: $stackTraceStr');
      }
    }
  }
  
  static void _log(String level, String message, [String? method]) {
    final methodName = method != null ? '.$method' : '';
    
    // 确保日志内容不超过长度限制
    if (message.length > MAX_LOG_CONTENT_LENGTH) {
      message = message.substring(0, MAX_LOG_CONTENT_LENGTH) + "... (已截断)";
    }
    
    switch (level) {
      case 'i':
        LogUtil.i('$TAG$methodName - $message');
        break;
      case 'd':
        LogUtil.d('$TAG$methodName - $message');
        break;
      case 'e':
        LogUtil.e('$TAG$methodName - $message');
        break;
    }
  }
  
  // 记录流媒体测试结果
  static void logStreamTest(String url, bool success, int responseTimeMs) {
    String shortenedUrl = url;
    if (shortenedUrl.length > 50) {
      shortenedUrl = shortenedUrl.substring(0, 47) + "...";
    }
    
    LogUtil.i('$TAG.streamTest - 流[$shortenedUrl]: ${success ? "成功" : "失败"}, 响应时间: ${responseTimeMs}ms');
  }
  
  // 记录重要的状态转换
  static void logStateTransition(String from, String to, String trigger) {
    LogUtil.i('$TAG.stateTransition - 从[$from]到[$to], 触发: $trigger');
  }
}

/// 超时管理类
class TimeoutManager {
  final Map<String, Timer> _timers = {};
  
  void setTimeout(String key, Duration duration, Function callback) {
    // 确保之前的同名定时器被取消
    cancelTimeout(key);
    
    _timers[key] = Timer(duration, () {
      callback();
      _timers.remove(key);
    });
    
    ParserLogger.info('设置计时器: $key, 持续时间: ${duration.inSeconds}秒', 'TimeoutManager');
  }
  
  void cancelTimeout(String key) {
    if (_timers.containsKey(key)) {
      _timers[key]?.cancel();
      _timers.remove(key);
      ParserLogger.info('取消计时器: $key', 'TimeoutManager');
    }
  }
  
  void cancelAll() {
    for (var key in _timers.keys.toList()) {
      _timers[key]?.cancel();
    }
    _timers.clear();
    ParserLogger.info('取消所有计时器', 'TimeoutManager');
  }
}

/// 状态机类 - 管理解析器状态
class ParserStateMachine {
  // 状态定义
  static const String STATE_INITIAL = 'INITIAL';
  static const String STATE_WEBVIEW_READY = 'WEBVIEW_READY';
  static const String STATE_ENGINE_LOADING = 'ENGINE_LOADING';
  static const String STATE_ENGINE_READY = 'ENGINE_READY';
  static const String STATE_SEARCH_SUBMITTED = 'SEARCH_SUBMITTED';
  static const String STATE_WAITING_RESULTS = 'WAITING_RESULTS';
  static const String STATE_LINKS_FOUND = 'LINKS_FOUND';
  static const String STATE_TESTING_STREAMS = 'TESTING_STREAMS';
  static const String STATE_COMPLETED = 'COMPLETED';
  static const String STATE_ERROR = 'ERROR';
  
  // 当前状态
  String _currentState = STATE_INITIAL;
  final Map<String, dynamic> _stateData = {};
  
  // 获取当前状态
  String get currentState => _currentState;
  
  // 状态转换，返回是否成功
  bool transitionTo(String newState, [Map<String, dynamic>? data]) {
    final oldState = _currentState;
    
    // 检查转换是否有效
    if (!_isValidTransition(oldState, newState)) {
      ParserLogger.error('无效的状态转换: $oldState -> $newState', 'stateMachine');
      return false;
    }
    
    // 更新状态
    _currentState = newState;
    
    // 更新状态数据
    if (data != null) {
      _stateData.addAll(data);
    }
    
    // 记录转换
    ParserLogger.logStateTransition(oldState, newState, data?.toString() ?? '无附加数据');
    return true;
  }
  
  // 检查转换是否有效
  bool _isValidTransition(String fromState, String toState) {
    // 定义有效转换
    final Map<String, List<String>> validTransitions = {
      STATE_INITIAL: [STATE_WEBVIEW_READY, STATE_ERROR],
      STATE_WEBVIEW_READY: [STATE_ENGINE_LOADING, STATE_ERROR],
      STATE_ENGINE_LOADING: [STATE_ENGINE_READY, STATE_ERROR],
      STATE_ENGINE_READY: [STATE_SEARCH_SUBMITTED, STATE_ENGINE_LOADING, STATE_ERROR],
      STATE_SEARCH_SUBMITTED: [STATE_WAITING_RESULTS, STATE_LINKS_FOUND, STATE_ERROR],
      STATE_WAITING_RESULTS: [STATE_LINKS_FOUND, STATE_ERROR],
      STATE_LINKS_FOUND: [STATE_TESTING_STREAMS, STATE_ERROR],
      STATE_TESTING_STREAMS: [STATE_COMPLETED, STATE_ERROR],
      STATE_COMPLETED: [STATE_ERROR], // 完成状态只能转为错误
      STATE_ERROR: [], // 错误状态是终态
    };
    
    // 错误状态可以从任何状态转换而来
    if (toState == STATE_ERROR) {
      return true;
    }
    
    // 检查转换是否在有效列表中
    return validTransitions.containsKey(fromState) && 
           validTransitions[fromState]!.contains(toState);
  }
  
  // 获取状态数据
  T? getStateData<T>(String key) {
    return _stateData[key] as T?;
  }
  
  // 检查是否处于指定状态
  bool isInState(String state) {
    return _currentState == state;
  }
  
  // 检查是否可以执行特定操作
  bool canPerform(String operation) {
    switch (operation) {
      case 'submitSearch':
        return _currentState == STATE_ENGINE_READY;
      case 'extractLinks':
        return _currentState == STATE_SEARCH_SUBMITTED || 
               _currentState == STATE_WAITING_RESULTS;
      case 'testStreams':
        return _currentState == STATE_LINKS_FOUND;
      case 'switchEngine':
        return _currentState == STATE_ENGINE_READY || 
               _currentState == STATE_ENGINE_LOADING;
      default:
        return false;
    }
  }
}
