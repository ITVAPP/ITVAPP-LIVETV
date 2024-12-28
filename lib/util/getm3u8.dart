import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 性能指标记录
class _PerformanceMetrics {
  final DateTime startTime;
  int staticCheckCount = 0;
  int jsCheckCount = 0;
  int retryCount = 0;
  int urlFound = 0;
  Map<String, int> detectionSourceStats = {
    'static': 0,
    'js': 0,
    'xhr': 0,
    'media': 0
  };
  
  _PerformanceMetrics(this.startTime);
  
  void logMetrics(bool success) {
    final duration = DateTime.now().difference(startTime);
    
    LogUtil.i('''
Performance Metrics:
- 总耗时: ${duration.inMilliseconds}ms
- 静态检查次数: $staticCheckCount
- JS检查次数: $jsCheckCount
- 重试次数: $retryCount
- 发现URL数: $urlFound
- 检测来源统计:
  * 静态检测: ${detectionSourceStats['static']}
  * JS检测: ${detectionSourceStats['js']}
  * XHR拦截: ${detectionSourceStats['xhr']}
  * 媒体元素: ${detectionSourceStats['media']}
- 最终结果: ${success ? "成功" : "失败"}
''');
  }
}

/// M3U8过滤规则配置
class M3U8FilterRule {
  /// 域名关键词
  final String domain;
  
  /// 必须包含的关键词
  final String requiredKeyword;

  const M3U8FilterRule({
    required this.domain,
    required this.requiredKeyword,
  });

  /// 从字符串解析规则
  /// 格式: domain|keyword
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length != 2) {
      throw FormatException('无效的规则格式: $rule，正确格式: domain|keyword');
    }
    return M3U8FilterRule(
      domain: parts[0].trim(),
      requiredKeyword: parts[1].trim(),
    );
  }
}

/// M3U8地址获取类
/// 用于从网页中提取M3U8视频流地址
class GetM3U8 {
  /// 全局规则配置字符串
  static String rulesString = 'setv.sh.cn|programme10_ud';
  
  
  
  /// 目标URL
  final String url;
  
  /// URL参数：from值
  final String? fromParam;
  
  /// URL参数：to值 
  final String? toParam;
  
  /// 超时时间(秒)
  final int timeoutSeconds;
  
  /// WebView控制器
  late WebViewController _controller;
  
  /// 是否已找到M3U8
  bool _m3u8Found = false;
  
  /// 已发现的URL集合 - 改用WeakSet在JS端实现
  final Set<String> _foundUrls = {};
  
  /// 定期检查定时器
  Timer? _periodicCheckTimer;
  
  /// 重试计数器
  int _retryCount = 0;

  /// 检测开始时间
  final DateTime _startTime = DateTime.now();

  /// 检查次数统计
  int _checkCount = 0;
  
  /// 当前检查间隔(秒)
  int _currentInterval = 1;
  
  /// 最大检查间隔(秒)
  static const int MAX_CHECK_INTERVAL = 5;
  
  /// 最大重试次数
  static const int MAX_RETRIES = 2;
  
  /// 重试延迟时间(秒)
  static const List<int> RETRY_DELAYS = [1, 2, 3];
  
  /// 无效URL关键词
  static const List<String> INVALID_URL_PATTERNS = [
    'advertisement', 'analytics', 'tracker',
    'pixel', 'beacon', 'stats', 'log'
  ];
  
  
  
  /// 是否已释放资源
  bool _isDisposed = false;

  /// 标记 JS 检测器是否已注入
  bool _isDetectorInjected = false;

  /// 规则列表
  final List<M3U8FilterRule> _filterRules;
  
  /// 是否正在进行静态检测
  bool _isStaticChecking = false;

  /// 是否已通过静态检测找到M3U8
  bool _staticM3u8Found = false;

  /// 性能指标实例
  final _PerformanceMetrics _metrics;
  
  /// 构造函数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 8,
  }) : _filterRules = _parseRules(rulesString),
       fromParam = Uri.parse(url).queryParameters['from'],
       toParam = Uri.parse(url).queryParameters['to'],
       _metrics = _PerformanceMetrics(DateTime.now()) {  // 初始化_metrics
    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL参数替换规则: from=$fromParam, to=$toParam');
    }
  }

  /// 解析规则字符串
  static List<M3U8FilterRule> _parseRules(String rulesString) {
    if (rulesString.isEmpty) {
      return [];
    }

    try {
      return rulesString
          .split('@')
          .where((rule) => rule.isNotEmpty)
          .map((rule) => M3U8FilterRule.fromString(rule))
          .toList();
    } catch (e) {
      LogUtil.e('解析规则字符串失败: $e');
      return [];
    }
  }
  
  /// URL整理
  String _cleanUrl(String url) {
    if (url.isEmpty) return url;
    
    try {
      String cleanedUrl = url.trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x2F;', '/')
        .replaceAll('&#47;', '/');

      // 修复重复的斜杠，但保留协议中的双斜杠
      cleanedUrl = cleanedUrl.replaceAll(RegExp(r'(?<!:)//+'), '/');

      // 处理相对URL
      if (!cleanedUrl.startsWith('http')) {
        if (cleanedUrl.startsWith('//')) {
          cleanedUrl = 'https:$cleanedUrl';
        } else if (cleanedUrl.startsWith('/')) {
          final baseUri = Uri.parse(url);
          cleanedUrl = '${baseUri.scheme}://${baseUri.host}$cleanedUrl';
        } else {
          final baseUri = Uri.parse(url);
          final path = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
          cleanedUrl = '${baseUri.scheme}://${baseUri.host}$path$cleanedUrl';
        }
      }

      // 确保URL编码正确
      final uri = Uri.parse(cleanedUrl);
      cleanedUrl = uri.toString();

      return cleanedUrl;
    } catch (e, stackTrace) {
      LogUtil.logError('URL清理过程发生错误', e, stackTrace);
      return url; // 如果处理失败，返回原始URL
    }
  }

  
  
  /// 返回找到的第一个有效M3U8地址，如果未找到返回ERROR
  Future<String> getUrl() async {
    final completer = Completer<String>();
    
    LogUtil.i('GetM3U8初始化开始，目标URL: $url');

    
    
    try {
      await _initController(completer);
      _startTimeout(completer);
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      completer.complete('ERROR');
    }
    
    return completer.future;
  }

  /// URL验证方法
  bool _isValidM3U8Url(String url) {
    LogUtil.i('验证URL: $url');
    
    try {
      // 基本URL格式验证
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) {
        LogUtil.i('无效的URL格式');
        return false;
      }

      // 检查协议
      if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
        LogUtil.i('不支持的协议: ${uri.scheme}');
        return false;
      }

      // 检查文件扩展名
      if (!url.toLowerCase().contains('.m3u8')) {
        LogUtil.i('URL不包含.m3u8扩展名');
        return false;
      }

      // 检查无效关键词
      final lowercaseUrl = url.toLowerCase();
      for (final pattern in INVALID_URL_PATTERNS) {
        if (lowercaseUrl.contains(pattern)) {
          LogUtil.i('URL包含无效关键词: $pattern');
          return false;
        }
      }

      // 应用过滤规则
      if (_filterRules.isNotEmpty) {
        bool matchedAnyDomain = false;
        for (final rule in _filterRules) {
          if (lowercaseUrl.contains(rule.domain.toLowerCase())) {
            matchedAnyDomain = true;
            if (!lowercaseUrl.contains(rule.requiredKeyword.toLowerCase())) {
              LogUtil.i('URL匹配域名 ${rule.domain} 但缺少必需关键词 ${rule.requiredKeyword}');
              return false;
            }
            LogUtil.i('URL通过规则验证: ${rule.domain}|${rule.requiredKeyword}');
            return true;
          }
        }
        
        // 如果有规则但URL不匹配任何规则的域名
        if (_filterRules.isNotEmpty && !matchedAnyDomain) {
          LogUtil.i('URL不匹配任何已配置的域名规则');
          return false;
        }
      }

      // 额外的URL合法性检查
      final suspicious = [
        'localhost',
        '127.0.0.1',
        'undefined',
        'null',
        'example.com',
        'test.',
        '.test',
      ];
      
      for (final term in suspicious) {
        if (lowercaseUrl.contains(term)) {
          LogUtil.i('URL包含可疑关键词: $term');
          return false;
        }
      }

      LogUtil.i('URL验证通过');
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('URL验证过程发生错误', e, stackTrace);
      return false;
    }
  }
  
  /// 处理发现的M3U8 URL
  void _handleM3U8Found(String url, Completer<String> completer) {
    LogUtil.i('处理发现的URL: $url');
    if (!_m3u8Found && url.isNotEmpty) {
      LogUtil.i('发现新的未处理URL');
      
      // 首先整理URL
      String cleanedUrl = _cleanUrl(url);
      LogUtil.i('整理后的URL: $cleanedUrl');
        
      if (_isValidM3U8Url(cleanedUrl)) {
        LogUtil.i('URL验证通过，标记为有效的m3u8地址');
        // 处理URL参数替换
        String finalUrl = cleanedUrl;
        if (fromParam != null && toParam != null) {
          LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
          finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
          LogUtil.i('替换后的URL: $finalUrl');
        }
      
        _foundUrls.add(finalUrl);
        _m3u8Found = true;
        if (!completer.isCompleted) {
          completer.complete(finalUrl);
        }
        _metrics.logMetrics(true);
        disposeResources();
      } else {
        LogUtil.i('URL验证失败，继续等待新的URL');
      }
    }
  }
  
  /// 初始化WebViewController
  Future<void> _initController(Completer<String> completer) async {
    LogUtil.i('开始初始化WebViewController');
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent)
        ..addJavaScriptChannel(
          'M3U8Detector',
          onMessageReceived: (JavaScriptMessage message) {
            LogUtil.i('JS检测器发现新的URL: ${message.message}');
            _handleM3U8Found(message.message, completer);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              LogUtil.i('页面导航请求: ${request.url}');
              
              // 解析URL
              final uri = Uri.tryParse(request.url);
              if (uri == null) {
                LogUtil.i('无效的URL，阻止加载');
                return NavigationDecision.prevent;
              }

              // 获取文件扩展名
              final extension = uri.path.toLowerCase().split('.').last;
              
              // 需要阻止的资源类型
              final blockedExtensions = [
                'jpg', 'jpeg', 'png', 'gif', 'webp',
                'css',
                'woff', 'woff2', 'ttf', 'eot',
                'ico', 'svg',
                'mp4', 'webm', 'ogg',
                'mp3', 'wav',
                'pdf', 'doc', 'docx',
                'swf',
              ];

              // 如果是被阻止的扩展名，阻止加载
              if (blockedExtensions.contains(extension)) {
                LogUtil.i('阻止加载资源: ${request.url}');
                return NavigationDecision.prevent;
              }

              // 特别允许m3u8相关的请求
              if (request.url.contains('.m3u8')) {
                LogUtil.i('允许加载m3u8资源: ${request.url}');
                return NavigationDecision.navigate;
              }

              LogUtil.i('允许加载资源: ${request.url}');
              return NavigationDecision.navigate;
            },
            onPageFinished: (String url) async {
              LogUtil.i('页面加载完成: $url');

              // 优化: 并行执行静态检测和JS检测
              try {
                final results = await Future.wait([
                  _checkPageContent(),
                  _startJSDetection(),
                ], eagerError: false);

                // 处理结果
                for (final result in results) {
                  if (result != null && !completer.isCompleted) {
                    _m3u8Found = true;
                    completer.complete(result);
                    
                    _metrics.logMetrics(true);
                    disposeResources();
                    return;
                  }
                }
              } catch (e) {
                LogUtil.e('检测过程发生错误: $e');
              }

              // 如果并行检测未找到结果，继续常规检测流程
              if (!_m3u8Found) {
                _setupPeriodicCheck();
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (error.errorCode == -1) {
                LogUtil.i('资源被阻止加载: ${error.description}');
                return;
              }
              
              LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
              _handleLoadError(completer);
            },
          ),
        );

      await _loadUrlWithHeaders();
      LogUtil.i('WebViewController初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
      _handleLoadError(completer);
    }
  }
  
  /// 加载URL并设置headers
  Future<void> _loadUrlWithHeaders() async {
    LogUtil.i('准备加载URL，添加自定义headers');
    try {
      // 使用 HeadersConfig 生成 headers
      final headers = HeadersConfig.generateHeaders(url: url);
      LogUtil.i('设置的headers: $headers');
      await _controller.loadRequest(Uri.parse(url), headers: headers);
      LogUtil.i('URL加载请求已发送');
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      rethrow;
    }
  }

  /// 设置定期检查
  void _setupPeriodicCheck() {
    LogUtil.i('设置定期检查任务');
    
    // 先取消已有的定时器
    _periodicCheckTimer?.cancel();

    // 创建新的定期检查定时器,固定1秒间隔
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!_m3u8Found && !_isDisposed) {
          _checkCount++;
          LogUtil.i('执行第$_checkCount次定期检查');
          
          if (!_isDetectorInjected) {
            _injectM3U8Detector();
          } else {
            // 如果已经注入过，执行扫描
            _controller.runJavaScript('''
              if (window._m3u8DetectorInitialized) {
                checkMediaElements(document);
                efficientDOMScan();
              }
            ''').catchError((error) {
              LogUtil.e('执行扫描失败: $error');
            });
          }
        } else {
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? 'M3U8已找到' : '已释放资源'}');
          timer.cancel();
        }
      },
    );
  }
  
  /// 新增: JS检测启动方法
  Future<String?> _startJSDetection() async {
    if (!_isDetectorInjected) {
      await _injectM3U8Detector();
      _isDetectorInjected = true;
    }
    return null; // 初始返回null，后续通过JavaScriptChannel接收结果
  }
  
  /// 检查页面内容中的M3U8地址 - 优化版本
  Future<String?> _checkPageContent() async {
    LogUtil.i('开始优化版本的页面内容检查');
    _isStaticChecking = true;
    
    try {
      // 使用优化的JS代码进行静态检测
      final jsCode = '''
        (function() {
          const results = [];
          
          // 1. 优先检查video和source标签
          function checkMediaElements() {
            const mediaElements = document.querySelectorAll('video, source');
            mediaElements.forEach(el => {
              if(el.src) results.push(el.src);
              if(el.currentSrc) results.push(el.currentSrc);
              // 检查data属性
              for(const key in el.dataset) {
                if(el.dataset[key]) results.push(el.dataset[key]);
              }
            });
          }
          
          // 2. 检查具有m3u8关键词的元素
          function checkM3U8Elements() {
            const elements = document.querySelectorAll(
              '[src*="m3u8"],[href*="m3u8"],[data-src*="m3u8"]'
            );
            elements.forEach(el => {
              ['src', 'href', 'data-src'].forEach(attr => {
                const value = el.getAttribute(attr);
                if(value) results.push(value);
              });
            });
          }
          
          // 3. 智能检查script标签
          function checkScripts() {
            const scripts = document.querySelectorAll('script:not([src])');
            const m3u8Pattern = /https?:[^"'\\s]+?\\.m3u8[^"'\\s]*/g;
            
            scripts.forEach(script => {
              if(script.textContent.includes('m3u8')) {
                const matches = script.textContent.match(m3u8Pattern);
                if(matches) results.push(...matches);
              }
            });
          }
          
          // 4. 检查可能包含视频的容器
          function checkVideoContainers() {
            const containers = document.querySelectorAll(
              '[class*="video"],[class*="player"],[id*="video"],[id*="player"]'
            );
            
            containers.forEach(container => {
              // 检查所有data属性
              for(const key in container.dataset) {
                if(container.dataset[key]) results.push(container.dataset[key]);
              }
              
              // 检查style中的URL
              const style = container.getAttribute('style');
              if(style && style.includes('m3u8')) {
                const matches = style.match(/url\\(['"]?(.*?m3u8[^'"\\)]*)/g);
                if(matches) {
                  results.push(...matches.map(url => url.replace(/^url\\(['"]?|['"]?\\)\\$/g, '')));
                }
              }
            });
          }
          
          // 5. 检查iframe内容
          function checkIframes() {
            document.querySelectorAll('iframe').forEach(iframe => {
              try {
                const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
                if(iframeDoc) {
                  const m3u8Elements = iframeDoc.querySelectorAll('[src*="m3u8"],[href*="m3u8"]');
                  m3u8Elements.forEach(el => {
                    ['src', 'href'].forEach(attr => {
                      const value = el.getAttribute(attr);
                      if(value) results.push(value);
                    });
                  });
                }
              } catch(e) {
                // 跨域访问限制，忽略错误
              }
            });
          }
          
          // 执行所有检查
          checkMediaElements();
          checkM3U8Elements();
          checkScripts();
          checkVideoContainers();
          checkIframes();
          
          // 去重并返回结果
          return [...new Set(results)];
        })()
      ''';

      final List<dynamic> results = await _controller.runJavaScriptReturningResult(jsCode) as List<dynamic>;
      LogUtil.i('静态检测找到 ${results.length} 个潜在的M3U8地址');

      // 批量处理结果
      for (final url in results) {
        if (url is String && url.isNotEmpty) {
          String cleanedUrl = _cleanUrl(url);
          LogUtil.i('处理潜在的M3U8地址: $cleanedUrl');
          
          if (_isValidM3U8Url(cleanedUrl)) {
            LogUtil.i('找到有效的M3U8地址');
            
            // 处理URL参数替换
            String finalUrl = cleanedUrl;
            if (fromParam != null && toParam != null) {
              LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
              finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
              LogUtil.i('替换后的URL: $finalUrl');
            }
            
            _foundUrls.add(finalUrl);
            _staticM3u8Found = true;
            _m3u8Found = true;
            return finalUrl;
          }
        }
      }

      LogUtil.i('静态检测未找到有效的M3U8地址');
      return null;
      
    } catch (e, stackTrace) {
      LogUtil.logError('静态检测过程发生错误', e, stackTrace);
      return null;
    } finally {
      _isStaticChecking = false;
    }
  }
  
  /// 注入优化后的M3U8检测器的JavaScript代码
  void _injectM3U8Detector() {
    if (_isDetectorInjected) {
      LogUtil.i('M3U8检测器已注入，跳过重复注入');
      return;
    }

    LogUtil.i('开始注入优化版本的M3U8检测器JS代码');
    final jsCode = '''
      (function() {
        // 避免重复初始化
        if (window._m3u8DetectorInitialized) return;
        window._m3u8DetectorInitialized = true;
        
        // 使用WeakSet存储已处理的元素，避免内存泄漏
        const processedElements = new WeakSet();
        
        // 使用Set存储已处理的URL
        const processedUrls = new Set();
        
        
        
        // 节流函数实现
        const throttle = (fn, delay) => {
          let lastTime = 0;
          return (...args) => {
            const now = Date.now();
            if (now - lastTime >= delay) {
              fn.apply(this, args);
              lastTime = now;
            }
          };
        };

        // URL处理函数优化
        const processM3U8Url = (() => {
          const urlQueue = [];
          let isProcessing = false;

          const processQueue = async () => {
            if (isProcessing || urlQueue.length === 0) return;
            isProcessing = true;

            try {
              while (urlQueue.length > 0) {
                const url = urlQueue.shift();
                if (!url || typeof url !== 'string') continue;
                
                // 检查URL是否已处理
                if (processedUrls.has(url)) continue;
                
                
                
                // 处理base64编码的URL
                if (url.includes('base64,')) {
                  try {
                    const base64Content = url.split('base64,')[1];
                    const decodedContent = atob(base64Content);
                    if (decodedContent.includes('.m3u8')) {
                      processedUrls.add(decodedContent);
                      window.M3U8Detector.postMessage(decodedContent);
                    }
                  } catch (e) {
                    console.error('Base64解码失败:', e);
                  }
                }

                if (url.includes('.m3u8')) {
                  processedUrls.add(url);
                  window.M3U8Detector.postMessage(url);
                }
                
                // 让出主线程
                await new Promise(resolve => setTimeout(resolve, 0));
              }
            } finally {
              isProcessing = false;
            }
          };

          return (url) => {
            urlQueue.push(url);
            processQueue();
          };
        })();
        
        // 优化的元素处理函数
        const processElement = (element) => {
          if (processedElements.has(element)) return;
          processedElements.add(element);
          
          // 批量收集URL
          const urls = new Set();
          
          // 检查标准属性
          ['src', 'href', 'currentSrc'].forEach(attr => {
            const value = element[attr] || element.getAttribute(attr);
            if (value) urls.add(value);
          });
          
          // 检查data属性
          Object.values(element.dataset || {}).forEach(value => {
            if (value) urls.add(value);
          });
          
          // 检查style中的URL
          const style = element.getAttribute('style');
          if (style && style.includes('m3u8')) {
            const matches = style.match(/url\\(['"]?(.*?m3u8[^'"\\)]*)/g);
            if (matches) {
              matches.map(url => url.replace(/^url\\(['"]?|['"]?\\)\\$/g, ''))
                     .forEach(url => urls.add(url));
            }
          }
          
          // 批量处理收集到的URL
          urls.forEach(url => processM3U8Url(url));
        };
        
        // 优化的DOM扫描函数
        const scanDOM = throttle(() => {
          const elements = document.querySelectorAll(
            'video, source, [src*="m3u8"], [href*="m3u8"], [data-src*="m3u8"], ' +
            '[class*="video"], [class*="player"], [id*="video"], [id*="player"]'
          );
          
          // 使用requestIdleCallback在空闲时间处理元素
          if (window.requestIdleCallback) {
            requestIdleCallback(() => {
              elements.forEach(processElement);
            });
          } else {
            // 降级方案
            setTimeout(() => {
              elements.forEach(processElement);
            }, 0);
          }
        }, 200);

        // 优化的XHR监听
        const setupXHRInterceptor = () => {
          const XHR = XMLHttpRequest.prototype;
          const originalOpen = XHR.open;
          const originalSetRequestHeader = XHR.setRequestHeader;
          const originalSend = XHR.send;
          
          XHR.open = function() {
            this._method = arguments[0];
            this._url = arguments[1];
            return originalOpen.apply(this, arguments);
          };
          
          XHR.setRequestHeader = function(header, value) {
            return originalSetRequestHeader.apply(this, arguments);
          };
          
          XHR.send = function() {
            if (this._url) {
              processM3U8Url(this._url);
            }
            return originalSend.apply(this, arguments);
          };
          
          return { originalOpen, originalSetRequestHeader, originalSend };
        };

        // 优化的Fetch监听
        const setupFetchInterceptor = () => {
          const originalFetch = window.fetch;
          window.fetch = function(input) {
            const url = (input instanceof Request) ? input.url : input;
            processM3U8Url(url);
            return originalFetch.apply(this, arguments);
          };
          
          return originalFetch;
        };
        
        // 优化的MutationObserver实现
        const setupMutationObserver = () => {
          // 使用防抖包装处理函数
          const debouncedScan = (() => {
            let timer;
            return () => {
              clearTimeout(timer);
              timer = setTimeout(scanDOM, 100);
            };
          })();

          const observer = new MutationObserver(mutations => {
            let shouldScan = false;
            const newElements = new Set();

            for (const mutation of mutations) {
              // 处理新增节点
              if (mutation.type === 'childList') {
                mutation.addedNodes.forEach(node => {
                  if (node.nodeType === 1) { // 元素节点
                    if (node.tagName === 'VIDEO' || 
                        node.tagName === 'SOURCE' || 
                        node.matches('[src*="m3u8"], [href*="m3u8"]')) {
                      processElement(node);
                    }
                    newElements.add(node);
                    shouldScan = true;
                  }
                });
              }
              
              // 处理属性变化
              else if (mutation.type === 'attributes') {
                const target = mutation.target;
                const attrName = mutation.attributeName;
                
                if (attrName === 'src' || attrName === 'href' || 
                    attrName?.startsWith('data-')) {
                  processElement(target);
                }
              }
            }

            // 只在必要时执行完整扫描
            if (shouldScan) {
              debouncedScan();
            }

            // 异步处理新元素
            if (newElements.size > 0) {
              queueMicrotask(() => {
                newElements.forEach(element => {
                  if (element.querySelectorAll) {
                    element.querySelectorAll('video, source, [src*="m3u8"], [href*="m3u8"]')
                           .forEach(processElement);
                  }
                });
              });
            }
          });

          return observer;
        };

        // 优化的iframe处理
        const handleIframe = (iframe) => {
          try {
            const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
            if (iframeDoc) {
              scanDOM();
              
              // 设置iframe的MutationObserver
              const observer = setupMutationObserver();
              observer.observe(iframeDoc.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['src', 'href', 'data-src']
              });
            }
          } catch (e) {
            // 跨域限制，忽略错误
          }
        };

        // 优化的滚动处理
        const handleScroll = throttle(() => {
          const {scrollTop, scrollHeight, clientHeight} = document.documentElement;
          if (scrollHeight - (scrollTop + clientHeight) < 200) {
            scanDOM();
          }
        }, 200);
        
        // 初始化检测器
        const initDetector = () => {
          // 设置网络请求拦截
          const { originalOpen, originalSetRequestHeader, originalSend } = setupXHRInterceptor();
          const originalFetch = setupFetchInterceptor();

          // 设置DOM观察器
          const observer = setupMutationObserver();
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['src', 'href', 'data-src']
          });

          // 监听动态加载
          window.addEventListener('scroll', handleScroll, { passive: true });
          window.addEventListener('popstate', scanDOM);
          window.addEventListener('hashchange', scanDOM);

          // 处理现有iframe
          document.querySelectorAll('iframe').forEach(handleIframe);

          // 执行初始扫描
          scanDOM();

          // 返回清理函数
          return function cleanup() {
            observer.disconnect();
            window.fetch = originalFetch;
            XMLHttpRequest.prototype.open = originalOpen;
            XMLHttpRequest.prototype.setRequestHeader = originalSetRequestHeader;
            XMLHttpRequest.prototype.send = originalSend;
            window.removeEventListener('scroll', handleScroll);
            window.removeEventListener('popstate', scanDOM);
            window.removeEventListener('hashchange', scanDOM);
            processedElements.clear?.();
            processedUrls.clear();
          };
        };

        // 启动检测器并保存清理函数
        window._cleanupM3U8Detector = initDetector();
      })();
    ''';
    
    try {
      LogUtil.i('执行JS检测器代码注入');
      _controller.runJavaScript(jsCode).then((_) {
        LogUtil.i('JS检测器代码注入成功');
        _isDetectorInjected = true;
      }).catchError((error) {
        LogUtil.e('JS检测器代码注入失败: $error');
      });
    } catch (e, stackTrace) {
      LogUtil.logError('执行JS检测器代码时发生错误', e, stackTrace);
    }
  }
  
  /// 优化后的重试处理逻辑
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_isDisposed) {
      LogUtil.i('已释放资源，不进行重试');
      return;
    }

    if (_retryCount >= RETRY_DELAYS.length) {
      LogUtil.e('达到最大重试次数');
      if (!completer.isCompleted) {
        _metrics.logMetrics(false);
        completer.complete('ERROR');
        await disposeResources();
      }
      return;
    }

    try {
      final delaySeconds = RETRY_DELAYS[_retryCount];
      _retryCount++;
      _metrics.retryCount = _retryCount;
      
      LogUtil.i('准备第 $_retryCount 次重试，延迟 $delaySeconds 秒');
      await Future.delayed(Duration(seconds: delaySeconds));
      
      if (_isDisposed) {
        LogUtil.i('延迟期间资源已释放，取消重试');
        return;
      }

      // 重新初始化前先清理资源
      await _cleanupBeforeRetry();
      
      // 使用新的检测策略
      final results = await Future.wait([
        _checkPageContent(),
        _startJSDetection(),
      ], eagerError: false).catchError((e) {
        LogUtil.e('重试检测过程发生错误: $e');
        return [null, null];
      });

      // 处理检测结果
      for (final result in results) {
        if (result != null && !completer.isCompleted) {
          _m3u8Found = true;
          _metrics.logMetrics(true);
          completer.complete(result);
          await disposeResources();
          return;
        }
      }

      // 如果还没找到，继续重试
      await _handleLoadError(completer);
      
    } catch (e, stackTrace) {
      LogUtil.logError('重试过程发生错误', e, stackTrace);
      if (!completer.isCompleted) {
        _metrics.logMetrics(false);
        completer.complete('ERROR');
        await disposeResources();
      }
    }
  }
  
  /// 重试前的清理工作
  Future<void> _cleanupBeforeRetry() async {
    LogUtil.i('执行重试前的清理工作');
    try {
      // 清理JS检测器
      if (_isDetectorInjected) {
        await _controller.runJavaScript('if(window._cleanupM3U8Detector) window._cleanupM3U8Detector();')
          .catchError((e) => LogUtil.e('清理JS检测器失败: $e'));
      }
      
      _isDetectorInjected = false;
      _periodicCheckTimer?.cancel();
      _foundUrls.clear();
      
      // 重置检测状态
      _isStaticChecking = false;
      _staticM3u8Found = false;
      
    } catch (e, stackTrace) {
      LogUtil.logError('重试前清理过程发生错误', e, stackTrace);
    }
  }

  /// 优化的资源释放
  Future<void> disposeResources() async {
    if (_isDisposed) {
      LogUtil.i('资源已释放，跳过重复释放');
      return;
    }

    LogUtil.i('开始释放资源');
    _isDisposed = true;

    try {
      // 取消定时器
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = null;

      // 清理 JS 检测器
      if (_isDetectorInjected) {
        await _controller.runJavaScript('''
          if(window._cleanupM3U8Detector) {
            try {
              window._cleanupM3U8Detector();
              delete window._cleanupM3U8Detector;
              delete window._m3u8DetectorInitialized;
            } catch(e) {
              console.error('清理JS检测器时发生错误:', e);
            }
          }
        ''').catchError((e) {
          LogUtil.e('清理JS检测器失败: $e');
        });
      }

      // 重置所有状态
      _isDetectorInjected = false;
      _m3u8Found = false;
      _isStaticChecking = false;
      _staticM3u8Found = false;
      
      // 清理URL集合
      _foundUrls.clear();
      
      // 记录资源释放完成
      LogUtil.i('资源释放完成');
      
    } catch (e, stackTrace) {
      LogUtil.logError('释放资源时发生错误', e, stackTrace);
    }
  }

  /// 优化的超时处理
  void _startTimeout(Completer<String> completer) {
    LogUtil.i('启动超时计时: ${timeoutSeconds}秒');
    
    Future.delayed(Duration(seconds: timeoutSeconds), () async {
      if (_isDisposed || completer.isCompleted) {
        return;
      }

      LogUtil.i('检测超时');
      
      try {
        // 超时前最后一次尝试
        final lastChanceResult = await _checkPageContent();
        if (lastChanceResult != null && !completer.isCompleted) {
          _m3u8Found = true;
          _metrics.logMetrics(true);
          completer.complete(lastChanceResult);
          return;
        }

        if (!completer.isCompleted) {
          _metrics.logMetrics(false);
          completer.complete('ERROR');
        }
      } catch (e, stackTrace) {
        LogUtil.logError('超时处理过程发生错误', e, stackTrace);
        if (!completer.isCompleted) {
          completer.complete('ERROR');
        }
      } finally {
        await disposeResources();
      }
    });
  }
}
