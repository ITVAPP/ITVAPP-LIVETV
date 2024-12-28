import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

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
  /// 全局规则配置字符串，在网页加载多个m3u8的时候，指定只使用符合条件的m3u8
  /// 格式: domain1|keyword1@domain2|keyword2
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
  
  /// 已发现的URL集合
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
  
  /// 已处理URL的最大缓存数量
  static const int MAX_CACHE_SIZE = 88;
  
  /// 是否已释放资源
  bool _isDisposed = false;

  /// 标记 JS 检测器是否已注入
  bool _isDetectorInjected = false;

  /// 规则列表
  final List<M3U8FilterRule> _filterRules;

  /// 构造函数
GetM3U8({
  required this.url,
  this.timeoutSeconds = 8,
}) : _filterRules = _parseRules(rulesString),
     fromParam = Uri.parse(url).queryParameters['from'],
     toParam = Uri.parse(url).queryParameters['to'] {
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
  
  /// 返回找到的第一个有效M3U8地址，如果未找到返回ERROR
  Future<String> getUrl() async {
    final completer = Completer<String>();
    
    LogUtil.i('GetM3U8初始化开始，目标URL: $url');
    try {
      await _initController(completer);
      _startTimeout(completer);
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      completer.complete('ERROR'); // 修改：返回ERROR而不是空字符串
    }
    
    return completer.future;
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
                'jpg', 'jpeg', 'png', 'gif', 'webp', // 图片
                'css', // 样式表
                'woff', 'woff2', 'ttf', 'eot', // 字体
                'ico', 'svg', // 图标
                'mp4', 'webm', 'ogg', // 视频
                'mp3', 'wav', // 音频
                'pdf', 'doc', 'docx', // 文档
                'swf', // Flash
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

              // 默认允许其他资源加载
              LogUtil.i('允许加载资源: ${request.url}');
              return NavigationDecision.navigate;
            },
            onPageFinished: (String url) {
              LogUtil.i('页面加载完成: $url');
              _setupPeriodicCheck();
              _injectM3U8Detector();
            },
            onWebResourceError: (WebResourceError error) {
              // 忽略被阻止资源的错误
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
  
  /// 处理加载错误
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_retryCount < RETRY_DELAYS.length && !_isDisposed) {
      final delaySeconds = RETRY_DELAYS[_retryCount];
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/${RETRY_DELAYS.length})，延迟${delaySeconds}秒');
      await Future.delayed(Duration(seconds: delaySeconds));
      if (!_isDisposed) {
        await _initController(completer);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或已释放资源');
      completer.complete('ERROR'); // 修改：返回ERROR而不是空字符串
      _logPerformanceMetrics();
      disposeResources();
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
          
          // 如果URL缓存过大，清理它
          if (_foundUrls.length > MAX_CACHE_SIZE) {
            _foundUrls.clear();
            LogUtil.i('URL缓存达到上限，已清理');
          }
        } else {
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? 'M3U8已找到' : '已释放资源'}');
          timer.cancel();
        }
      },
    );
  }
  
  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (!_isDisposed && !_m3u8Found) {
        LogUtil.i('GetM3U8提取超时，未找到有效的m3u8地址');
        if (!completer.isCompleted) {
          completer.complete('ERROR'); // 修改：返回ERROR而不是空字符串
        }
        _logPerformanceMetrics();
        disposeResources();
      }
    });
  }
  
  /// 处理发现的M3U8 URL
  void _handleM3U8Found(String url, Completer<String> completer) {
    LogUtil.i('处理发现的URL: $url');
    if (!_m3u8Found && url.isNotEmpty) {
      LogUtil.i('发现新的未处理URL');
      
      if (_isValidM3U8Url(url)) {
        LogUtil.i('URL验证通过，标记为有效的m3u8地址');
        // 处理URL参数替换
        String finalUrl = url;
        if (fromParam != null && toParam != null) {
          LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
          finalUrl = url.replaceAll(fromParam!, toParam!);
          LogUtil.i('替换后的URL: $finalUrl');
        }
    
        _foundUrls.add(finalUrl);
        _m3u8Found = true;
        if (!completer.isCompleted) {
          completer.complete(finalUrl);
        }
        _logPerformanceMetrics();
        disposeResources();
      } else {
        LogUtil.i('URL验证失败，继续等待新的URL');
      }
    }
  }

  /// 验证M3U8 URL是否有效
  bool _isValidM3U8Url(String url) {
    LogUtil.i('开始验证URL: $url');
    
    // 验证URL是否为有效格式
    final validUrl = Uri.tryParse(url);
    if (validUrl == null) {
      LogUtil.i('无效的URL格式');
      return false;
    }
    
    // 检查文件扩展名
    if (!url.toLowerCase().contains('.m3u8')) {
      LogUtil.i('URL不包含.m3u8扩展名');
      return false;
    }
    
    // 检查是否为完整URL
    if (!url.startsWith('http')) {
      LogUtil.i('URL不是以http开头的完整地址');
      return false;
    }

    // 检查是否包含无效关键词
    final lowercaseUrl = url.toLowerCase();
    for (final pattern in INVALID_URL_PATTERNS) {
      if (lowercaseUrl.contains(pattern)) {
        LogUtil.i('URL包含无效关键词: $pattern');
        return false;
      }
    }

    // 应用过滤规则
    if (_filterRules.isNotEmpty) {
      // 查找匹配的规则
      for (final rule in _filterRules) {
        if (url.contains(rule.domain)) {
          final containsKeyword = url.contains(rule.requiredKeyword);
          LogUtil.i('发现匹配的域名规则: ${rule.domain}');
          LogUtil.i(containsKeyword 
            ? 'URL包含所需关键词: ${rule.requiredKeyword}' 
            : 'URL不包含所需关键词: ${rule.requiredKeyword}'
          );
          return containsKeyword; // 对于匹配的域名，必须包含指定关键词才返回true
        }
      }
    }
    
    // 没有匹配的规则，使用默认验证
    LogUtil.i('没有匹配的域名规则，采用默认验证');
    return true;
  }

  /// 记录性能指标
  void _logPerformanceMetrics() {
    final duration = DateTime.now().difference(_startTime);
    LogUtil.i('Performance: 耗时=${duration.inMilliseconds}ms, 检查=$_checkCount, 重试=$_retryCount, URL数=${_foundUrls.length}, 结果=${_m3u8Found ? "成功" : "失败"}');
  }
  
  /// 释放资源
  void disposeResources() {
    LogUtil.i('开始释放资源');
    _isDisposed = true;
    _periodicCheckTimer?.cancel();
    _isDetectorInjected = false;  // 重置注入标记
    
    // 清理JavaScript检测器
    try {
      _controller.runJavaScript('if(window._cleanupM3U8Detector) window._cleanupM3U8Detector();');
    } catch (e) {
      LogUtil.e('清理JavaScript检测器时发生错误: $e');
    }

    // 清理其他资源
    _foundUrls.clear();
    
    LogUtil.i('资源释放完成');
  }
  
  /// 注入M3U8检测器的JavaScript代码
  void _injectM3U8Detector() {
    // 如果已经注入过，直接返回
    if (_isDetectorInjected) {
      LogUtil.i('M3U8检测器已注入，跳过重复注入');
      return;
    }

    LogUtil.i('开始注入m3u8检测器JS代码');
    final jsCode = '''
      (function() {
        // 避免重复初始化
        if (window._m3u8DetectorInitialized) {
          console.log('M3U8检测器已初始化，跳过');
          return;
        }
        console.log('M3U8检测器开始初始化');
        window._m3u8DetectorInitialized = true;
        
        // 已处理的URL缓存
        const processedUrls = new Set();
        const MAX_CACHE_SIZE = 88;
        
        // 全局变量
        let observer = null;
        const MAX_RECURSION_DEPTH = 3;
        
        // URL处理函数
        function processM3U8Url(url, depth = 0) {
          console.log('处理URL: ' + url + ', 当前深度: ' + depth);
          
          if (!url || typeof url !== 'string') {
            console.log('无效URL，跳过处理');
            return;
          }
          
          if (depth > MAX_RECURSION_DEPTH) {
            console.log('达到最大递归深度，停止处理');
            return;
          }
          
          if (processedUrls.has(url)) {
            console.log('URL已处理过，跳过');
            return;
          }

          // 如果缓存过大，清理它
          if (processedUrls.size > MAX_CACHE_SIZE) {
            console.log('URL缓存达到上限，执行清理');
            processedUrls.clear();
          }
                   
          // 处理base64编码的URL
          try {
            if (url.includes('base64,')) {
              console.log('发现Base64编码的内容');
              const base64Content = url.split('base64,')[1];
              const decodedContent = atob(base64Content);
              if (decodedContent.includes('.m3u8')) {
                console.log('Base64解码后发现m3u8 URL');
                processM3U8Url(decodedContent, depth + 1);
              }
            }
          } catch(e) {
            console.error('Base64解码失败:', e);
          }
          
          if (url.includes('.m3u8')) {
            console.log('发现m3u8 URL');
            processedUrls.add(url);
            window.M3U8Detector.postMessage(url);
          }
        }

        // 监控MediaSource
        if (window.MediaSource) {
          console.log('设置MediaSource监控');
          const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
          MediaSource.prototype.addSourceBuffer = function(mimeType) {
            console.log('MediaSource添加源缓冲区:', mimeType);
            if (mimeType.includes('mp2t')) {
              console.log('检测到HLS流使用');
            }
            return originalAddSourceBuffer.call(this, mimeType);
          };
        }
        
        // 拦截XHR请求
        console.log('设置XHR请求拦截');
        const XHR = XMLHttpRequest.prototype;
        const originalOpen = XHR.open;
        const originalSetRequestHeader = XHR.setRequestHeader;
        const originalSend = XHR.send;
        
        XHR.open = function() {
          this._method = arguments[0];
          this._url = arguments[1];
          this._requestHeaders = {};
          console.log('XHR打开连接:', this._method, this._url);
          return originalOpen.apply(this, arguments);
        };
        
        XHR.setRequestHeader = function(header, value) {
          this._requestHeaders[header.toLowerCase()] = value;
          return originalSetRequestHeader.apply(this, arguments);
        };
        
        XHR.send = function() {
          if (this._url) {
            processM3U8Url(this._url, 0);
          }
          return originalSend.apply(this, arguments);
        };
        
        // 拦截Fetch请求
        console.log('设置Fetch请求拦截');
        const originalFetch = window.fetch;
        window.fetch = function(input) {
          const url = (input instanceof Request) ? input.url : input;
          console.log('拦截到Fetch请求:', url);
          processM3U8Url(url, 0);
          return originalFetch.apply(this, arguments);
        };
        
        // 检查媒体元素
        function checkMediaElements(doc = document) {
          console.log('开始检查媒体元素');
          // 优先检查video元素
          doc.querySelectorAll('video').forEach(element => {
            console.log('检查视频元素:', element);
            // 首先检查video元素本身的source
            [element.src, element.currentSrc].forEach(src => {
              if (src) processM3U8Url(src, 0);
            });
            
            // 检查source子元素
            element.querySelectorAll('source').forEach(source => {
              const src = source.src || source.getAttribute('src');
              if (src) processM3U8Url(src, 0);
            });

            // 检查data属性
            for (const attr of element.attributes) {
              if (attr.name.startsWith('data-') && attr.value) {
                processM3U8Url(attr.value, 0);
              }
            }
          });

          // 检查其他可能包含视频源的元素
          const videoContainers = doc.querySelectorAll([
            '[class*="video"]',
            '[class*="player"]',
            '[id*="video"]',
            '[id*="player"]'
          ].join(','));
          
          videoContainers.forEach(container => {
            // 检查所有data属性
            for (const attr of container.attributes) {
              if (attr.value) processM3U8Url(attr.value, 0);
            }
          });
          
          // 设置媒体元素变化监控
          doc.querySelectorAll('video,source').forEach(element => {
            const elementObserver = new MutationObserver((mutations) => {
              mutations.forEach((mutation) => {
                if (mutation.type === 'attributes') {
                  const newValue = element.getAttribute(mutation.attributeName);
                  if (newValue) {
                    processM3U8Url(newValue, 0);
                  }
                }
              });
            });
            
            elementObserver.observe(element, {
              attributes: true,
              attributeFilter: ['src', 'currentSrc', 'data-src']
            });
          });
        }
        
        // 高效的DOM扫描
        function efficientDOMScan() {
          console.log('开始高效DOM扫描');
          
          // 优先扫描明显的m3u8链接
          const elements = document.querySelectorAll([
            'a[href*="m3u8"]',
            'source[src*="m3u8"]',
            'video[src*="m3u8"]',
            '[data-src*="m3u8"]',
            'iframe[src*="m3u8"]'
          ].join(','));
          
          elements.forEach(element => {
            for (const attr of ['href', 'src', 'data-src']) {
              const value = element.getAttribute(attr);
              if (value) processM3U8Url(value, 0);
            }
          });
          
          // 扫描script标签中的内容
          document.querySelectorAll('script:not([src])').forEach(script => {
            const content = script.textContent;
            if (content) {
              const urlRegex = /https?:\\/\\/[^\\s<>"]+?\\.m3u8[^\\s<>"']*/g;
              const matches = content.match(urlRegex);
              if (matches) {
                matches.forEach(match => {
                  processM3U8Url(match, 0);
                });
              }
            }
          });
        }
        
        // 处理iframe
        function handleIframe(iframe) {
          try {
            console.log('处理iframe:', iframe.src);
            const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
            if (iframeDoc) {
              checkMediaElements(iframeDoc);
              efficientDOMScan();
            }
          } catch (e) {
            console.error('无法访问iframe内容:', e);
          }
        }
        
        // 设置DOM观察器
        observer = new MutationObserver((mutations) => {
          mutations.forEach((mutation) => {
            // 处理新添加的节点
            mutation.addedNodes.forEach((node) => {
              if (node.nodeType === 1) {
                console.log('新增DOM元素:', node.tagName);
                
                // 处理iframe
                if (node.tagName === 'IFRAME') {
                  handleIframe(node);
                }
                // 如果是视频相关元素，优先处理
                else if (node.tagName === 'VIDEO' || 
                         node.tagName === 'SOURCE' || 
                         node.matches('[class*="video"], [class*="player"]')) {
                  checkMediaElements(node.parentNode);
                }
                
                // 检查新添加元素的所有属性
                if (node instanceof Element) {
                  for (const attr of node.attributes) {
                    if (attr.value) {
                      processM3U8Url(attr.value, 0);
                    }
                  }
                }
              }
            });

            // 处理属性变化
            if (mutation.type === 'attributes') {
              const newValue = mutation.target.getAttribute(mutation.attributeName);
              if (newValue) {
                processM3U8Url(newValue, 0);
              }
            }
          });
        });
        
        // 启动观察器，设置更具体的配置
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'href', 'data-src', 'currentSrc'],
          characterData: false
        });
        
        // 处理现有iframe
        document.querySelectorAll('iframe').forEach(handleIframe);
        
        // 执行初始检查，按优先级顺序执行
        console.log('执行初始检查');
        checkMediaElements(document);
        efficientDOMScan();
        
        // 监听URL变化
        let urlChangeTimeout = null;
        const handleUrlChange = () => {
          if (urlChangeTimeout) {
            clearTimeout(urlChangeTimeout);
          }
          urlChangeTimeout = setTimeout(() => {
            console.log('检测到URL变化，重新扫描');
            checkMediaElements(document);
            efficientDOMScan();
          }, 100);
        };
        
        window.addEventListener('popstate', handleUrlChange);
        window.addEventListener('hashchange', handleUrlChange);
        
        // 添加动态内容加载的检测
        let lastScrollTime = Date.now();
        window.addEventListener('scroll', () => {
          const now = Date.now();
          if (now - lastScrollTime > 1000) {
            lastScrollTime = now;
            const scrollHeight = Math.max(
              document.documentElement.scrollHeight,
              document.body.scrollHeight
            );
            const scrollTop = window.pageYOffset;
            const clientHeight = window.innerHeight;
            
            if (scrollHeight - (scrollTop + clientHeight) < 100) {
              console.log('检测到滚动到底部，可能有新内容加载');
              setTimeout(efficientDOMScan, 500);
            }
          }
        }, { passive: true });

        // 清理函数
        window._cleanupM3U8Detector = function() {
          console.log('执行M3U8检测器清理');
          
          if (observer) {
            observer.disconnect();
          }
          
          // 恢复原始的fetch函数
          if (originalFetch) {
            window.fetch = originalFetch;
          }
          
          // 恢复原始的XHR函数
          if (originalOpen && originalSetRequestHeader && originalSend) {
            XHR.open = originalOpen;
            XHR.setRequestHeader = originalSetRequestHeader;
            XHR.send = originalSend;
            }
          
          // 清理DOM事件监听器
          window.removeEventListener('popstate', handleUrlChange);
          window.removeEventListener('hashchange', handleUrlChange);
          
          // 清理URL缓存
          processedUrls.clear();
          
          // 移除初始化标记
          delete window._m3u8DetectorInitialized;
          
          console.log('M3U8检测器清理完成');
        };
        
        console.log('M3U8检测器初始化完成');
      })();
    ''';
    
    try {
      LogUtil.i('执行JS代码注入');
      _controller.runJavaScript(jsCode).then((_) {
        LogUtil.i('JS代码注入成功');
        _isDetectorInjected = true;  // 标记为已注入
      }).catchError((error) {
        LogUtil.e('JS代码注入失败: $error');
      });
    } catch (e, stackTrace) {
      LogUtil.logError('执行JS代码时发生错误', e, stackTrace);
    }
  }
}
