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
  
  /// 是否正在进行静态检测
  bool _isStaticChecking = false;

  /// 是否已通过静态检测找到M3U8
  bool _staticM3u8Found = false;

  /// 标记页面是否已处理过加载完成事件
  bool _isPageLoadProcessed = false;

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

/// URL整理
String _cleanUrl(String url) {
 // 先处理基本的字符清理
 String cleanedUrl = url.trim()
   .replaceAll(r'\s*\\s*$', '')
   .replaceAll('&amp;', '&')
   .replaceAll(RegExp(r'([^:])//+'), r'$1/')
   .replaceAll('+', '%20')
   .replaceAll('&quot;', '"')
   .replaceAll('&#x2F;', '/')
   .replaceAll('&#47;', '/');

 // 如果已经是完整URL则直接返回
 if (cleanedUrl.startsWith('http')) {
   return cleanedUrl;
 }

 try {
   final baseUri = Uri.parse(this.url);
   
   if (cleanedUrl.startsWith('//')) {
     // 如果以//开头，去除//和域名部分(如果有)
     String cleanPath = cleanedUrl.substring(2);
     if (cleanPath.contains('/')) {
       // 如果包含域名，去除域名部分
       cleanPath = cleanPath.substring(cleanPath.indexOf('/'));
     }
     // 确保路径以/开头
     cleanPath = cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath;
     cleanedUrl = '${baseUri.scheme}://${baseUri.host}/$cleanPath';
   } else {
     // 处理以/开头或不以/开头的URL
     String cleanPath = cleanedUrl.startsWith('/') ? cleanedUrl.substring(1) : cleanedUrl;
     cleanedUrl = '${baseUri.scheme}://${baseUri.host}/$cleanPath';
   }
 } catch (e) {
   LogUtil.e('URL整理失败: $e');
 }

 return cleanedUrl;
}

/// 处理相对路径,转换为完整URL
String _handleRelativePath(String path) {
  // 已经是完整URL就直接返回
  if (path.startsWith('http')) {
    return path;
  }
  try {
    final baseUri = Uri.parse(url); 
    String fullUrl;
    if (path.startsWith('//')) {
      String cleanPath = path.substring(2);
      if (cleanPath.contains('/')) {
        cleanPath = cleanPath.substring(cleanPath.indexOf('/'));
      }
      cleanPath = cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath;
      fullUrl = '${baseUri.scheme}://${baseUri.host}/$cleanPath';
    } else {
      String cleanPath = path.startsWith('/') ? path.substring(1) : path;
      fullUrl = '${baseUri.scheme}://${baseUri.host}/$cleanPath';
    }
    // 最后通过_cleanUrl再处理一次
    return _cleanUrl(fullUrl);
  } catch (e) {
    LogUtil.e('处理相对路径失败: $e');
    return path;
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
            onPageFinished: (String url) async {
              // 防止重复处理页面加载完成事件
              if (_isPageLoadProcessed || _isDisposed) {
                LogUtil.i('页面加载完成事件已处理或资源已释放，跳过处理');
                return;
              }
              _isPageLoadProcessed = true;
              
              LogUtil.i('页面加载完成: $url');
              
              // 先进行页面内容检查
              final m3u8Url = await _checkPageContent();
              if (m3u8Url != null && !completer.isCompleted) {
                _m3u8Found = true;
                completer.complete(m3u8Url);
                _logPerformanceMetrics();
                disposeResources();
                return;
              }

              // 如果静态检查没找到，启动JS检测
              if (!_isDisposed && !_m3u8Found) {
                _setupPeriodicCheck();
                _injectM3U8Detector();
              }
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
        // 重置页面加载处理标记，允许新的重试处理页面加载
        _isPageLoadProcessed = false;
        await _initController(completer);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或已释放资源');
      completer.complete('ERROR');
      _logPerformanceMetrics();
      disposeResources();
    }
  }

  /// 加载URL并设置headers
  Future<void> _loadUrlWithHeaders() async {
    LogUtil.i('准备加载URL，添加自定义headers');
    try {
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
    // 如果已经有定时器在运行，或者已释放资源，或者已找到M3U8，则直接返回
    if (_periodicCheckTimer != null || _isDisposed || _m3u8Found) {
      LogUtil.i('跳过定期检查设置: ${_periodicCheckTimer != null ? "定时器已存在" : _isDisposed ? "已释放资源" : "已找到M3U8"}');
      return;
    }
    
    LogUtil.i('设置定期检查任务');
    
    // 创建新的定期检查定时器
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        // 如果已找到M3U8或已释放资源，取消定时器
        if (_m3u8Found || _isDisposed) {
          timer.cancel();
          _periodicCheckTimer = null;
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "已释放资源"}');
          return;
        }
        
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
      },
    );
  }
  
  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (!_isDisposed && !_m3u8Found && !completer.isCompleted) {
        LogUtil.i('GetM3U8提取超时，未找到有效的m3u8地址');
        completer.complete('ERROR');
        _logPerformanceMetrics();
        disposeResources();
      }
    });
  }
  
  /// 记录性能指标
  void _logPerformanceMetrics() {
    final duration = DateTime.now().difference(_startTime);
    LogUtil.i('Performance: 耗时=${duration.inMilliseconds}ms, 检查=$_checkCount, 重试=$_retryCount, URL数=${_foundUrls.length}, 结果=${_m3u8Found ? "成功" : "失败"}');
  }
  
  /// 释放资源
  void disposeResources() {
    // 防止重复释放
    if (_isDisposed) {
      LogUtil.i('资源已释放，跳过重复释放');
      return;
    }
    
    LogUtil.i('开始释放资源');
    _isDisposed = true;
    
    // 取消定时器
    if (_periodicCheckTimer != null) {
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = null;
    }
    
    _isDetectorInjected = false;  // 重置注入标记
    _isPageLoadProcessed = false; // 重置页面加载处理标记
    
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
  
  /// 处理发现的M3U8 URL
void _handleM3U8Found(String url, Completer<String> completer) {
  // 如果已找到或已释放资源，跳过处理
  if (_m3u8Found || _isDisposed) {
    LogUtil.i('跳过URL处理: ${_m3u8Found ? "已找到M3U8" : "资源已释放"}');
    return;
  }

  LogUtil.i('处理发现的URL: $url');
  if (url.isNotEmpty) {
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
        _logPerformanceMetrics();
        disposeResources();
      }
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

/// 检查页面内容中的M3U8地址 
Future<String?> _checkPageContent() async {
  // 如果已经找到或已释放资源，跳过检查
  if (_m3u8Found || _isDisposed) {
    LogUtil.i('跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "资源已释放"}');
    return null;
  }

  LogUtil.i('开始检查页面内容中的M3U8地址');
  _isStaticChecking = true;
  try {
    // 获取页面完整内容
    final String content = await _controller.runJavaScriptReturningResult(
      'document.documentElement.outerHTML'
    ) as String;

    // 多模式正则匹配
    final regexPatterns = [
      // 修改正则以匹配相对路径
      r'''(?:https?://)?[^\s<>"'\\]+?\.m3u8[^\s<>"'\\]*''', // 标准 URL 
      r'"(?:url|src|href)"\s*:\s*"((?:\\\/|[^"])+?\.m3u8[^"]*)"',  // JSON 格式
      r'''['"](?:url|src|href)['"]?\s*=\s*['"]([^'"]+?\.m3u8[^'"]*?)['"]''', // HTML 属性
      r'''url\(\s*['"]?([^'")]+?\.m3u8[^'")]*?)['"]?\s*\)''' // CSS URL
    ];

    final Set<String> foundUrls = {};
    int totalMatches = 0;

    for (final pattern in regexPatterns) {
      final regex = RegExp(pattern);
      final matches = regex.allMatches(content);
      totalMatches += matches.length;
      
      for (final match in matches) {
        // 获取匹配组1(如果有)或者完整匹配
        final url = match.groupCount > 0 
          ? (match.group(1) ?? match.group(0) ?? '')
          : (match.group(0) ?? '');
          
        if (url.isNotEmpty) {
          // 处理相对路径
          String decodedUrl = url.replaceAll(r'\/', '/');
          foundUrls.add(_handleRelativePath(decodedUrl));
        }
      }
    }
    
    LogUtil.i('页面内容中找到 $totalMatches 个潜在的M3U8地址，去重后剩余 ${foundUrls.length} 个');

    // 检查每个匹配的URL
    for (final url in foundUrls) {
      LogUtil.i('检查潜在的M3U8地址: $url');
      
      // 首先清理URL
      String cleanedUrl = _cleanUrl(url);
      LogUtil.i('清理后的URL: $cleanedUrl');
        
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
        _staticM3u8Found = true;
        _m3u8Found = true;
        return finalUrl;
      } else {
        LogUtil.i('URL验证失败，继续检查下一个URL');
      }
    }

    LogUtil.i('页面内容中未找到符合规则的M3U8地址，继续使用JS检测器');
    return null;
  } catch (e, stackTrace) {
    LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
    return null;
  } finally {
    _isStaticChecking = false;
  }
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
          return;
        }
        window._m3u8DetectorInitialized = true;
        
        // 已处理的URL缓存
        const processedUrls = new Set();
        const MAX_CACHE_SIZE = 88;
        
        // 全局变量
        let observer = null;
        const MAX_RECURSION_DEPTH = 3;
        
        // URL处理函数
        function processM3U8Url(url, depth = 0) {
          if (!url || typeof url !== 'string') {
            return;
          }
          
  // 处理相对路径
  if (url.startsWith('/')) {
    const baseUrl = new URL(window.location.href);
    url = baseUrl.protocol + '//' + baseUrl.host + url;
  } else if (!url.startsWith('http')) {
    const baseUrl = new URL(window.location.href);
    url = new URL(url, baseUrl).toString();
  }
          
          if (depth > MAX_RECURSION_DEPTH) {
            return;
          }
          
          if (processedUrls.has(url)) {
            return;
          }

          // 如果缓存过大，清理它
          if (processedUrls.size > MAX_CACHE_SIZE) {
            processedUrls.clear();
          }
                   
          // 处理base64编码的URL
            if (url.includes('base64,')) {
              const base64Content = url.split('base64,')[1];
              const decodedContent = atob(base64Content);
              if (decodedContent.includes('.m3u8')) {
                processM3U8Url(decodedContent, depth + 1);
              }
            }
          
          if (url.includes('.m3u8')) {
            processedUrls.add(url);
            window.M3U8Detector.postMessage(url);
          }
        }

        // 监控MediaSource
        if (window.MediaSource) {
          const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
          MediaSource.prototype.addSourceBuffer = function(mimeType) {
            return originalAddSourceBuffer.call(this, mimeType);
          };
        }
        
        // 拦截XHR请求
        const XHR = XMLHttpRequest.prototype;
        const originalOpen = XHR.open;
        const originalSetRequestHeader = XHR.setRequestHeader;
        const originalSend = XHR.send;
        
        XHR.open = function() {
          this._method = arguments[0];
          this._url = arguments[1];
          this._requestHeaders = {};
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
        const originalFetch = window.fetch;
        window.fetch = function(input) {
          const url = (input instanceof Request) ? input.url : input;
          processM3U8Url(url, 0);
          return originalFetch.apply(this, arguments);
        };
        
        // 检查媒体元素
        function checkMediaElements(doc = document) {
          // 优先检查video元素
          doc.querySelectorAll('video').forEach(element => {
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
            const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
            if (iframeDoc) {
              checkMediaElements(iframeDoc);
              efficientDOMScan();
            }
        }
        
        // 设置DOM观察器
        observer = new MutationObserver((mutations) => {
          mutations.forEach((mutation) => {
            // 处理新添加的节点
            mutation.addedNodes.forEach((node) => {
              if (node.nodeType === 1) {
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
        checkMediaElements(document);
        efficientDOMScan();
        
        // 监听URL变化
        let urlChangeTimeout = null;
        const handleUrlChange = () => {
          if (urlChangeTimeout) {
            clearTimeout(urlChangeTimeout);
          }
          urlChangeTimeout = setTimeout(() => {
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
              setTimeout(efficientDOMScan, 500);
            }
          }
        }, { passive: true });

        // 清理函数
        window._cleanupM3U8Detector = function() {
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
        };
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
