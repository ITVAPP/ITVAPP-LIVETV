import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
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
  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8';
  
  /// 目标URL
  final String url;
  
  /// URL参数：from值
  final String? fromParam;
  
  /// URL参数：to值 
  final String? toParam;

  /// URL参数：要点击的文本
  final String? clickText;
  
  /// URL参数：点击索引（默认0）
  final int clickIndex;
  
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
  static const int MAX_CHECK_INTERVAL = 3;
  
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

  /// 标记点击是否已执行
  bool _isClickExecuted = false;

  /// 构造函数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 9,
  }) : _filterRules = _parseRules(rulesString),
       fromParam = Uri.parse(url).queryParameters['from'],
       toParam = Uri.parse(url).queryParameters['to'],
       // 从URL参数中解析点击配置
       clickText = Uri.parse(url).queryParameters['clickText'],
       clickIndex = int.tryParse(Uri.parse(url).queryParameters['clickIndex'] ?? '') ?? 0 {
    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL参数替换规则: from=$fromParam, to=$toParam');
    }
    if (clickText != null) {
      LogUtil.i('检测到点击配置: text=$clickText, index=$clickIndex');
    }
  }

/// 执行点击操作
Future<bool> _executeClick() async {
  if (_isClickExecuted || clickText == null || clickText!.isEmpty) {
    LogUtil.i(_isClickExecuted ? '点击已执行，跳过' : '无点击配置，跳过');
    return false;
  }

  LogUtil.i('开始执行点击操作，文本: $clickText, 索引: $clickIndex');
  
  final jsCode = '''
  (async function() {
    function findAndClick() {
      const searchText = '${clickText}';
      const targetIndex = ${clickIndex};
      
      // 获取所有文本和元素节点
      const walk = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
        {
          acceptNode: function(node) {
            if (node.nodeType === Node.ELEMENT_NODE) {
              if(['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
                return NodeFilter.FILTER_REJECT;
              }
              return NodeFilter.FILTER_ACCEPT;
            }
            if(node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
              return NodeFilter.FILTER_ACCEPT;
            }
            return NodeFilter.FILTER_REJECT;
          }
        }
      );

      // 记录找到的匹配
      const matches = [];
      let currentIndex = 0;
      let foundNode = null;

      // 遍历节点
      let node;
      while (node = walk.nextNode()) {
        // 处理文本节点
        if(node.nodeType === Node.TEXT_NODE) {
          const text = node.textContent.trim();
          if(text === searchText) {
            matches.push({
              text: text,
              node: node.parentElement
            });
            
            if(currentIndex === targetIndex) {
              foundNode = node.parentElement;
              break;
            }
            currentIndex++;
          }
        }
        // 处理元素节点
        else if(node.nodeType === Node.ELEMENT_NODE) {
          const children = Array.from(node.childNodes);
          const directText = children
            .filter(child => child.nodeType === Node.TEXT_NODE)
            .map(child => child.textContent.trim())
            .join('');
            
          if(directText === searchText) {
            matches.push({
              text: directText,
              node: node
            });
            
            if(currentIndex === targetIndex) {
              foundNode = node;
              break;
            }
            currentIndex++;
          }
        }
      }

      // 如果没找到匹配的节点
      if (!foundNode) {
        return {
          success: false,
          error: '未找到匹配元素',
          matches: matches.map(m => m.text)
        };
      }

      try {
        // 直接点击找到的元素
        foundNode.click();
        
        return {
          success: true,
          matches: matches.map(m => m.text),
          clicked: {
            text: foundNode.textContent.trim()
          }
        };
      } catch (e) {
        return {
          success: false,
          error: e.message || String(e),
          matches: matches.map(m => m.text)
        };
      }
    }

    return findAndClick();
  })();
  ''';

  try {
    final result = await _controller.runJavaScriptReturningResult(jsCode);
    
    // 尝试将结果转换为 Map
    Map<String, dynamic> response;
    try {
      response = result as Map<String, dynamic>;
    } catch (e) {
      if (result is String) {
        response = json.decode(result);
      } else {
        throw FormatException('Unexpected response format: ${result.runtimeType}');
      }
    }
    
    if (response['success'] == true) {
      LogUtil.i('点击成功: ${response['clicked']}');
      _isClickExecuted = true;
      await Future.delayed(const Duration(seconds: 2));
      return true;
    } else {
      _isClickExecuted = true;
      return false;
    }
  } catch (e, stack) {
    LogUtil.logError('执行点击操作时发生错误', e, stack);
    _isClickExecuted = true;
    return false;
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
  LogUtil.i('URL整理开始，原始URL: $url');

  // 先处理基本的字符清理
  String cleanedUrl = url.trim()
    .replaceAll(r'\s*\\s*$', '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#x2F;', '/')
    .replaceAll('&#47;', '/')
    .replaceAll('+', '%20');

  // 修复：只替换3个或更多的连续斜杠，保留双斜杠
  cleanedUrl = cleanedUrl.replaceAll(RegExp(r'/{3,}'), '/');
  
  // 保护协议中的双斜杠
  cleanedUrl = cleanedUrl.replaceAll(RegExp(r'(?<!:)//'), '/');

  // 如果已经是完整URL则直接返回
  if (RegExp(r'^(?:https?|rtmp|rtsp|ftp|mms|thunder)://').hasMatch(cleanedUrl)) {
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

/// 生成签名后的 URL
String _processAndSignUrl(String url) {
  LogUtil.i('检查并处理URL: $url');
  if (url.contains('hntv.tv') && url.contains('getm3u8')) {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000; // 当前Unix时间戳
    final uri = Uri.parse(url);
    // 替换路径中的 `getm3u8` 为时间戳路径
    final newPath = uri.path.replaceFirst('/getm3u8', '/$ts');
    // 构造新的 URL，不设置 `queryParameters`，以避免生成多余的 `?`
    final modifiedUrl = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: newPath,
    ).toString();
    LogUtil.i('生成替换后的URL: $modifiedUrl');
    return modifiedUrl;
  }
  return url;
}

/// 对指定的关键字使用签名替换getm3u8字符
String _processAndSignUrl2(String url) {
  if (url.contains('hntv.tv')) {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000; // 当前Unix时间戳
    final secret = '6ca114a836ac7d73'; // 密钥
    final sign = sha256.convert(utf8.encode('$secret$ts')).toString(); // 签名

    final uri = Uri.parse(url);
    // 替换路径中的 `getm3u8` 为签名
    final newPath = uri.path.replaceFirst('getm3u8', '$ts');
    final signedUrl = uri.replace(path: newPath, queryParameters: {'sign': sign}).toString();

    LogUtil.i('生成签名并替换后的URL: $signedUrl');
    return signedUrl;
  }
  return url;
}


/// 处理相对路径,转换为完整URL
String _handleRelativePath(String path) {
	
LogUtil.i('处理相对路径开始，原始URL: $path');

  // 检查是否是完整 URL (包含协议://)
if (RegExp(r'^(?:https?|rtmp|rtsp|ftp|mms|thunder)://').hasMatch(path)) {
 return path;
}
  
  // 如果以 // 开头,说明是省略协议的完整URL
  if (path.startsWith('//')) {
    final baseUri = Uri.parse(url);
    return '${baseUri.scheme}:$path';
  }

  try {
    final baseUri = Uri.parse(url);
    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return _cleanUrl('${baseUri.scheme}://${baseUri.host}/$cleanPath');
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
                return NavigationDecision.prevent;
              }

              // 特别允许m3u8相关的请求
              if (request.url.contains('.m3u8')) {
                return NavigationDecision.navigate;
              }

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
              
              // 先执行点击操作（如果有配置）
              if (clickText != null && !_isClickExecuted) {
                await _executeClick();
              }

              // 再进行页面内容检查
              final m3u8Url = await _checkPageContent();
              if (m3u8Url != null && !completer.isCompleted) {
                _m3u8Found = true;
                completer.complete(m3u8Url);
                _logPerformanceMetrics();
                await disposeResources();
                return;
              }

              // 如果静态检查没找到，启动JS检测
              if (!_isDisposed && !_m3u8Found) {
                _setupPeriodicCheck();
                _injectM3U8Detector();
              }
            },
            onWebResourceError: (WebResourceError error) async { 
              // 忽略被阻止资源的错误
              if (error.errorCode == -1) {
                LogUtil.i('资源被阻止加载: ${error.description}');
                return;
              }
              
              LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
              await _handleLoadError(completer);
            },
          ),
        );

      await _loadUrlWithHeaders();
      LogUtil.i('WebViewController初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
      await _handleLoadError(completer);
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
        // 重置页面加载处理标记和点击执行标记，允许新的重试重新执行所有操作
        _isPageLoadProcessed = false;
        _isClickExecuted = false;  // 重置点击状态，允许重试时重新点击
        await _initController(completer);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或已释放资源');
      completer.complete('ERROR');
      _logPerformanceMetrics();
      await disposeResources();
    }
  }

  /// 加载URL并设置headers
  Future<void> _loadUrlWithHeaders() async {
    try {
      // 检查如果是需要签名的处理的URL，进行签名替换getm3u8
      String modifiedUrl = _processAndSignUrl(url);
      final headers = HeadersConfig.generateHeaders(url: modifiedUrl);
      await _controller.loadRequest(Uri.parse(modifiedUrl), headers: headers);
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
    Future.delayed(Duration(seconds: timeoutSeconds), () async {	
      if (!_isDisposed && !_m3u8Found && !completer.isCompleted) {
        LogUtil.i('GetM3U8提取超时，未找到有效的m3u8地址');
        completer.complete('ERROR');
        _logPerformanceMetrics();
        await disposeResources();
      }
    });
  }
  
  /// 记录性能指标
  void _logPerformanceMetrics() {
    final duration = DateTime.now().difference(_startTime);
    LogUtil.i('Performance: 耗时=${duration.inMilliseconds}ms, 检查=$_checkCount, 重试=$_retryCount, URL数=${_foundUrls.length}, 结果=${_m3u8Found ? "成功" : "失败"}');
  }
  
  /// 释放资源
Future<void> disposeResources() async {
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

    try {
      // 注入清理脚本，终止所有正在进行的网络请求和观察器
      await _controller.runJavaScript('''
        // 停止页面加载
        window.stop();
        
        // 清理所有活跃的XHR请求
        const activeXhrs = window._activeXhrs || [];
        activeXhrs.forEach(xhr => xhr.abort());
        
        // 清理所有Fetch请求
        if (window._abortController) {
          window._abortController.abort();
        }
        
        // 清理所有定时器
        const highestTimeoutId = window.setTimeout(() => {}, 0);
        for (let i = 0; i <= highestTimeoutId; i++) {
          window.clearTimeout(i);
          window.clearInterval(i);
        }
        
        // 清理所有事件监听器
        window.removeEventListener('scroll', window._scrollHandler);
        window.removeEventListener('popstate', window._urlChangeHandler);
        window.removeEventListener('hashchange', window._urlChangeHandler);
        
        // 清理M3U8检测器
        if(window._cleanupM3U8Detector) {
          window._cleanupM3U8Detector();
        }
        
        // 终止所有正在进行的MediaSource操作
        if (window.MediaSource) {
          const mediaSources = document.querySelectorAll('video source');
          mediaSources.forEach(source => {
            const mediaElement = source.parentElement;
            if (mediaElement) {
              mediaElement.pause();
              mediaElement.removeAttribute('src');
              mediaElement.load();
            }
          });
        }
        
        // 清理所有websocket连接
        const sockets = window._webSockets || [];
        sockets.forEach(socket => socket.close());

        // 停止所有进行中的网络请求
        if (window.performance && window.performance.getEntries) {
          const resources = window.performance.getEntries().filter(e => 
            e.initiatorType === 'xmlhttprequest' || 
            e.initiatorType === 'fetch' || 
            e.initiatorType === 'beacon'
          );
          resources.forEach(resource => {
            if (resource.duration === 0) {
              try {
                const controller = new AbortController();
                controller.abort();
              } catch(e) {}
            }
          });
        }

        // 清理所有未完成的图片加载
        document.querySelectorAll('img').forEach(img => {
          if (!img.complete) {
            img.src = '';
          }
        });
      ''');

      // 清空WebView缓存
      await _controller.clearCache();
      
      // 重置所有标记
      _isDetectorInjected = false;  // 重置注入标记
      _isPageLoadProcessed = false; // 重置页面加载处理标记
      _isClickExecuted = false;     // 重置点击执行标记
      
      // 清理其他资源
      _foundUrls.clear();
      
      LogUtil.i('资源释放完成');
    } catch (e, stack) {
      LogUtil.logError('释放资源时发生错误', e, stack);
    }
}
  
  /// 处理发现的M3U8 URL
  Future<void> _handleM3U8Found(String url, Completer<String> completer) async {
  	
  // 如果需要点击且还没点击，忽略这个URL
  if (clickText != null && !_isClickExecuted) {
    LogUtil.i('点击操作未完成，忽略URL: $url');
    return;
  }
  
    // 如果已找到或已释放资源，跳过处理
    if (_m3u8Found || _isDisposed) {
      LogUtil.i('跳过URL处理: ${_m3u8Found ? "已找到M3U8" : "资源已释放"}');
      return;
    }

    LogUtil.i('处理发现的URL: $url');
    if (url.isNotEmpty) {
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
          await disposeResources();
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
    return true;
  }

  /// 检查页面内容中的M3U8地址
Future<String?> _checkPageContent() async {
  if (_m3u8Found || _isDisposed) {
    LogUtil.i('跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "资源已释放"}');
    return null;
  }
  _isStaticChecking = true;
  
  try {
    final dynamic sampleResult = await _controller.runJavaScriptReturningResult('''
      (function() {
        try {
          const htmlContent = document.documentElement.innerHTML.substring(0, 29998);
          if (htmlContent.trim()) return htmlContent;

          const textContent = document.body.innerText || document.body.textContent || '';
          if (textContent.trim()) return textContent;

          const preTag = document.querySelector('pre');
          if (preTag && preTag.textContent.trim()) return preTag.textContent;

          return ''; // 如果没有内容，返回空字符串
        } catch (e) {
          return null; // 如果出错，返回 null
        }
      })();
    ''');
    
    if (sampleResult == null) {
      LogUtil.i('获取内容样本失败');
      return null; 
    }
    
    // 处理JSON转义字符
    String sample = sampleResult.toString()
      .replaceAll(r'\\\\', '\\')  // 处理双反斜杠
      .replaceAll(r'\\/', '/')  // 处理转义斜杠
      .replaceAll(r'\\"', '"')  // 处理转义双引号
      .replaceAll(r'\"', '"')  // 处理转义双引号
      .replaceAll(r"\\'", "'")  // 处理转义单引号
      .replaceAll(r"\'", "'")  // 处理转义单引号
      .replaceAll(r'\/', '/');  // 处理转义斜杠

    // 处理HTML实体
    sample = sample
      .replaceAll('&quot;', '"')  // 双引号
      .replaceAll('&#x2F;', '/')  // 斜杠
      .replaceAll('&#47;', '/')  // 斜杠
      .replaceAll('&amp;', '&')  // &
      .replaceAll('&lt;', '<')  // 小于号
      .replaceAll('&gt;', '>');  // 大于号
    
    // URL解码
    if (sample.contains('%')) {
      try {
        sample = Uri.decodeComponent(sample);
      } catch (e) {
        LogUtil.i('URL解码失败，保持原样: $e');
      }
    }
    
    if (sample.length > 28888) {
      LogUtil.i('页面内容较大(超过30KB)，跳过静态检测');
      return null;
    }
    
    LogUtil.i('''页面内容：${sample}，页面内容较小，可能是api，进行静态检测''');
  
    // 新的正则表达式(?:https?|ftp)
    final pattern = r'''[\'"]([^\'"]*?\.m3u8[^\'"\s>]*)[\'"]|(?:^|\s)((?:https?|rtmp|rtsp|ftp|mms|thunder)?//[^\s<>]+?\.m3u8[^\s<>]*)''';
    final regex = RegExp(pattern, caseSensitive: false);
    final matches = regex.allMatches(sample);

    if (clickIndex == 0) {
      for (final match in matches) {
        // 检查两个捕获组
        String? url = match.group(1);  // 引号中的内容
        if (url == null || url.isEmpty) {
          url = match.group(2);  // 非引号的URL
        }
        
        if (url != null && url.isNotEmpty) {
          LogUtil.i('正则匹配到URL: $url');
          String cleanedUrl = _cleanUrl(_handleRelativePath(url));
          if (_isValidM3U8Url(cleanedUrl)) {
            String finalUrl = cleanedUrl;
            if (fromParam != null && toParam != null) {
              finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
            }
            _foundUrls.add(finalUrl);
            _staticM3u8Found = true;
            _m3u8Found = true;
            LogUtil.i('页面内容中找到 $finalUrl');
            return finalUrl;
          }
        }
      }
    } else {
      final Set<String> foundUrls = {};
      
      for (final match in matches) {
        String? url = match.group(1);
        if (url == null || url.isEmpty) {
          url = match.group(2);
        }
        
        if (url != null && url.isNotEmpty) {
          foundUrls.add(_handleRelativePath(url));
        }
      }
      
      LogUtil.i('页面内容中找到 ${foundUrls.length} 个潜在的M3U8地址');
      LogUtil.i('去重后的URLs: ${foundUrls.toList()}');
      
      int index = 0;
      for (final url in foundUrls) {
        String cleanedUrl = _cleanUrl(url);
        if (_isValidM3U8Url(cleanedUrl)) {
          String finalUrl = cleanedUrl;
          if (fromParam != null && toParam != null) {
            finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
          }
          _foundUrls.add(finalUrl);
          if (index == clickIndex) {
            _staticM3u8Found = true;
            _m3u8Found = true;
            LogUtil.i('找到目标URL(index=$clickIndex): $finalUrl');
            return finalUrl;
          }
          index++;
        }
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
  Future<void> dispose() async {
    await disposeResources();
  }
}
