import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/getm3u8diy.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 集中所有常量
class M3U8Constants {
  // 数值常量
  static const int defaultTimeoutSeconds = 30; // 默认超时时间（秒）
  static const int maxFoundUrlsSize = 50; // 发现URL的最大存储数量
  static const int maxPageLoadedStatusSize = 50; // 已加载页面状态的最大存储数量
  static const int maxCacheSize = 50; // 通用缓存的最大容量
  static const int maxRuleCacheSize = 20; // 规则缓存的最大容量
  static const int maxRetryCount = 2; // 最大重试次数
  static const int periodicCheckIntervalMs = 1000; // 定期检查间隔（毫秒）
  static const int clickDelayMs = 500; // 点击操作延迟（毫秒）
  static const int urlCheckDelayMs = 3000; // URL检查延迟（毫秒）
  static const int retryDelayMs = 500; // 重试延迟（毫秒）
  static const int contentSampleLength = 38888; // 内容采样长度
  static const int cleanupDelayMs = 3000; // 清理延迟（毫秒）
  static const int webviewCleanupDelayMs = 500; // WebView清理延迟（毫秒）
  static const int defaultSetSize = 50; // 默认集合大小

  // 字符串常量
  static const String rulePatterns = 'iptv345.com|flv?sign=@4gtv.tv|master.m3u8@tcrbs.com|auth_key@xybtv.com|auth_key@aodianyun.com|auth_key@ptbtv.com|hd/live@setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook='; // M3U8过滤规则模式
  static const String specialRulePatterns = 'nctvcloud.com|flv@iptv345.com|flv'; // 特殊规则模式
  static const String dynamicKeywords = 'sousuo@jinan@gansu@xizang@sichuan@xishui@yanan@foshan'; // getm3u8diy关键字
  static const String whiteExtensions = 'r.png?t=@www.hljtv.com@guangdianyun.tv'; // 白名单关键字
  static const String blockedExtensions = '.png@.jpg@.jpeg@.gif@.webp@.css@.woff@.woff2@.ttf@.eot@.ico@.svg@.mp3@.wav@.pdf@.doc@.docx@.swf'; // 屏蔽的扩展名
  static const String invalidPatterns = 'advertisement|analytics|tracker|pixel|beacon|stats|google'; // 无效模式（如广告、跟踪）

  // 数据结构常量
  static const List<Map<String, String>> timeApis = [
    {'name': 'Aliyun API', 'url': 'https://acs.m.taobao.com/gw/mtop.common.getTimestamp/'}, // 阿里云时间API
    {'name': 'Suning API', 'url': 'https://quan.suning.com/getSysTime.do'}, // 苏宁时间API
    {'name': 'Meituan API', 'url': 'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime'}, // 美团时间API
  ]; // 时间同步API列表
}

/// URL 处理工具类
class UrlUtils {
  static final RegExp _escapeRegex = RegExp(r'\\(\|/|")'); // 转义字符正则
  static final RegExp _multiSlashRegex = RegExp(r'/{3,}'); // 多斜杠正则
  static final RegExp _htmlEntityRegex = RegExp(r'&(#?[a-z0-9]+);'); // HTML实体正则
  static final RegExp _unicodeRegex = RegExp(r'\\u([0-9a-fA-F]{4})'); // Unicode编码正则
  static final RegExp _protocolRegex = RegExp(r'^https?://'); // 协议头正则

  // HTML实体映射
  static const Map<String, String> _htmlEntities = {
    'amp': '&', 'quot': '"', '#x2F': '/', '#47': '/', 'lt': '<', 'gt': '>'
  };

  // 清理URL中的转义字符、HTML实体等
  static String basicUrlClean(String url) {
    if (url.isEmpty) return url;
    if (url.endsWith(r'\')) url = url.substring(0, url.length - 1); // 移除末尾反斜杠

    String result = url
        .replaceAllMapped(_escapeRegex, (match) => match.group(1)!) // 替换转义字符
        .replaceAll(r'\/', '/') // 统一斜杠
        .replaceAll(_multiSlashRegex, '/') // 合并多斜杠
        .replaceAllMapped(_htmlEntityRegex, (m) => _htmlEntities[m.group(1)] ?? m.group(0)!) // 替换HTML实体
        .replaceAllMapped(_unicodeRegex, (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16))); // 解码Unicode

    if (result.contains('%')) {
      try {
        result = Uri.decodeComponent(result); // 解码URL编码
      } catch (e) {
        // 解析失败保持原样
      }
    }

    return result.trim(); // 去除首尾空格
  }

  // 构建完整URL
  static String buildFullUrl(String path, Uri baseUri) {
    if (_protocolRegex.hasMatch(path)) return path; // 已包含协议，直接返回
    if (path.startsWith('//')) return '${baseUri.scheme}://${path.replaceFirst('//', '')}'; // 处理无协议的URL
    String cleanPath = path.startsWith('/') ? path.substring(1) : path; // 清理开头的斜杠
    return '${baseUri.scheme}://${baseUri.host}/$cleanPath'; // 拼接完整URL
  }
}

/// M3U8过滤规则配置
class M3U8FilterRule {
  final String domain; // 域名
  final String requiredKeyword; // 必需关键字

  const M3U8FilterRule({required this.domain, required this.requiredKeyword});

  // 从字符串解析规则
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length < 2) return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: '');
    return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: parts[1].trim());
  }
}

/// 限制大小的集合类
class LimitedSizeSet<T> {
  final int maxSize; // 最大容量
  final LinkedHashSet<T> _set; // 内部集合

  LimitedSizeSet([this.maxSize = M3U8Constants.defaultSetSize]) : _set = LinkedHashSet();

  // 添加元素，超出容量时移除最早元素
  bool add(T element) {
    if (_set.contains(element)) return false;
    if (_set.length >= maxSize) {
      _set.remove(_set.first); // 移除最早元素
    }
    return _set.add(element);
  }

  bool contains(T element) => _set.contains(element); // 检查元素是否存在
  int get length => _set.length; // 获取当前大小
  List<T> toList() => List.unmodifiable(_set); // 转换为不可修改列表
  Set<T> toSet() => Set.unmodifiable(_set); // 转换为不可修改集合
  void clear() => _set.clear(); // 清空集合
  void remove(T element) => _set.remove(element); // 移除指定元素
}

/// 通用 LRU 缓存实现
class LRUCache<K, V> {
  final int maxSize; // 最大容量
  final Map<K, V> _cache = {}; // 缓存存储
  final List<K> _keys = []; // 键顺序列表

  LRUCache(this.maxSize);

  // 获取缓存值并更新访问顺序
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;
    _keys.remove(key); // 移除旧位置
    _keys.add(key); // 移到末尾
    return _cache[key];
  }

  // 添加或更新缓存值
  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache[key] = value;
      _keys.remove(key);
      _keys.add(key);
      return;
    }
    if (_keys.length >= maxSize) {
      final oldest = _keys.removeAt(0); // 移除最旧键
      _cache.remove(oldest);
    }
    _cache[key] = value;
    _keys.add(key);
  }

  bool containsKey(K key) => _cache.containsKey(key); // 检查键是否存在
  int get length => _cache.length; // 获取当前大小
  void clear() {
    _cache.clear();
    _keys.clear();
  } // 清空缓存
  void remove(K key) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
      _keys.remove(key);
    }
  } // 移除指定键
}

/// M3U8地址获取类
class GetM3U8 {
  static final LRUCache<String, String> _scriptCache = LRUCache(M3U8Constants.maxCacheSize); // 脚本缓存
  static final LRUCache<String, List<M3U8FilterRule>> _ruleCache = LRUCache(M3U8Constants.maxRuleCacheSize); // 规则缓存
  static final LRUCache<String, Set<String>> _keywordsCache = LRUCache(M3U8Constants.maxRuleCacheSize); // 关键字缓存
  static final LRUCache<String, Map<String, String>> _specialRulesCache = LRUCache(M3U8Constants.maxRuleCacheSize); // 特殊规则缓存
  static final LRUCache<String, RegExp> _patternCache = LRUCache(M3U8Constants.maxCacheSize); // 正则模式缓存
  static List<String>? _blockedExtensionsCache; // 屏蔽扩展名缓存
  static List<String>? _whiteExtensionsCache; // 白名单扩展名缓存

  static final RegExp _invalidPatternRegex = RegExp(
    M3U8Constants.invalidPatterns,
    caseSensitive: false,
  ); // 无效模式正则

  // 解析并缓存数据
  static T _parseCached<T>(
    String input,
    String type,
    T Function(String) parser,
    LRUCache<String, T> cache,
  ) {
    if (input.isEmpty) return parser('');
    final cached = cache.get('$type:$input');
    if (cached != null) return cached;
    final result = parser(input);
    cache.put('$type:$input', result);
    return result;
  }

  // 解析屏蔽扩展名
  static List<String> _parseBlockedExtensions(String extensionsString) {
    if (_blockedExtensionsCache != null) return _blockedExtensionsCache!;
    _blockedExtensionsCache = _parseCached(
      extensionsString,
      'blocked_extensions',
      (input) => input.isEmpty ? [] : input.split('@').map((ext) => ext.trim()).toList(),
      LRUCache(1),
    );
    return _blockedExtensionsCache!;
  }
  
  // 解析白名单扩展名
  static List<String> _parseWhiteExtensions(String extensionsString) {
    if (_whiteExtensionsCache != null) return _whiteExtensionsCache!;
    _whiteExtensionsCache = _parseCached(
      extensionsString,
      'white_extensions',
      (input) => input.isEmpty ? [] : input.split('@').map((ext) => ext.trim()).toList(),
      LRUCache(1),
    );
    return _whiteExtensionsCache!;
  }

  final String url; // 目标URL
  final String? fromParam; // URL替换参数（from）
  final String? toParam; // URL替换参数（to）
  final String? clickText; // 点击触发文本
  final int clickIndex; // 点击索引
  final int timeoutSeconds; // 超时时间（秒）
  late WebViewController _controller; // WebView控制器
  bool _m3u8Found = false; // 是否找到M3U8
  final LimitedSizeSet<String> _foundUrls = LimitedSizeSet(M3U8Constants.maxFoundUrlsSize); // 已发现URL集合
  Timer? _periodicCheckTimer; // 定期检查定时器
  int _retryCount = 0; // 重试计数
  int _checkCount = 0; // 检查计数
  final List<M3U8FilterRule> _filterRules; // 过滤规则列表
  bool _isClickExecuted = false; // 是否已执行点击
  bool _isControllerInitialized = false; // 控制器是否初始化
  String _filePattern = 'm3u8'; // 文件模式（默认m3u8）
  RegExp get _m3u8Pattern => _getOrCreatePattern(_filePattern); // M3U8正则模式
  static final Map<String, int> _hashFirstLoadMap = {}; // Hash路由加载计数
  bool isHashRoute = false; // 是否为Hash路由
  bool _isHtmlContent = false; // 是否为HTML内容
  String? _httpResponseContent; // HTTP响应内容
  static int? _cachedTimeOffset; // 时间偏移缓存
  final LimitedSizeSet<String> _pageLoadedStatus = LimitedSizeSet(M3U8Constants.maxPageLoadedStatusSize); // 已加载页面状态
  late final Uri _parsedUri; // 解析后的URI
  final CancelToken? cancelToken; // 取消令牌
  bool _isDisposed = false; // 是否已释放
  Timer? _timeoutTimer; // 超时定时器

  // 验证URL是否有效
  bool _validateUrl(String url, String filePattern) {
    if (url.isEmpty || _foundUrls.contains(url)) return false;
    final lowerUrl = url.toLowerCase();
    if (!lowerUrl.contains('.$filePattern')) return false;

    if (_filterRules.isNotEmpty) {
      bool matchedDomain = false;
      for (final rule in _filterRules) {
        if (_parsedUri.host.contains(rule.domain)) {	
          matchedDomain = true;
          return rule.requiredKeyword.isEmpty || url.contains(rule.requiredKeyword);
        }
      }
      return !matchedDomain;
    }
    return true;
  }

  GetM3U8({
    required this.url,
    this.timeoutSeconds = M3U8Constants.defaultTimeoutSeconds,
    this.cancelToken,
  }) : _filterRules = _parseCached(
          M3U8Constants.rulePatterns,
          'rules',
          (input) => input.isEmpty
              ? []
              : input.split('@').where((rule) => rule.isNotEmpty).map(M3U8FilterRule.fromString).toList(),
          _ruleCache,
        ),
        fromParam = _extractQueryParams(url)['from'],
        toParam = _extractQueryParams(url)['to'],
        clickText = _extractQueryParams(url)['clickText'],
        clickIndex = int.tryParse(_extractQueryParams(url)['clickIndex'] ?? '') ?? 0 {
    _controller = WebViewController();
    try {
      _parsedUri = Uri.parse(url); // 解析URL
      isHashRoute = _parsedUri.fragment.isNotEmpty; // 检查是否为Hash路由
    } catch (e) {
      LogUtil.e('解析URL失败: $e');
      _parsedUri = Uri(scheme: 'https', host: 'invalid.host');
      isHashRoute = false;
    }
    _filePattern = _determineFilePattern(url); // 确定文件模式
    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL参数替换规则: from=$fromParam, to=$toParam');
    }
    if (clickText != null) {
      LogUtil.i('检测到点击配置: text=$clickText, index=$clickIndex');
    }
  }

  // 确定文件模式（m3u8或其他）
  String _determineFilePattern(String url) {
    String pattern = 'm3u8';
    final specialRules = _parseCached(
      M3U8Constants.specialRulePatterns,
      'special_rules',
      (input) {
        if (input.isEmpty) return {};
        final rules = <String, String>{};
        for (final rule in input.split('@')) {
          final parts = rule.split('|');
          if (parts.length >= 2) rules[parts[0].trim()] = parts[1].trim();
        }
        return rules;
      },
      _specialRulesCache,
    );
    for (final entry in specialRules.entries) {
      if (url.contains(entry.key)) {
        pattern = entry.value;
        LogUtil.i('检测到特殊模式: $pattern 用于URL: $url');
        break;
      }
    }
    return pattern;
  }

  // 获取或创建正则模式
  RegExp _getOrCreatePattern(String filePattern) {
    final cacheKey = 'pattern_$filePattern';
    final cachedPattern = _patternCache.get(cacheKey);
    if (cachedPattern != null) return cachedPattern;
    final pattern = RegExp(
      "(?:https?://|//|/)[^'\"\\s,()<>{}\\[\\]]*?\\.${filePattern}[^'\"\\s,()<>{}\\[\\]]*",
      caseSensitive: false,
    );
    _patternCache.put(cacheKey, pattern);
    return pattern;
  }

  // 提取URL查询参数
  static Map<String, String> _extractQueryParams(String url) {
    try {
      final uri = Uri.parse(url);
      Map<String, String> params = Map.from(uri.queryParameters);
      if (uri.fragment.isNotEmpty) {
        final fragmentParts = uri.fragment.split('?');
        if (fragmentParts.length > 1) {
          final hashParams = Uri.splitQueryString(fragmentParts[1]);
          params.addAll(hashParams);
        }
      }
      return params;
    } catch (e) {
      LogUtil.e('解析URL参数时发生错误: $e');
      return {};
    }
  }

  // 解析动态关键字
  static Set<String> _parseKeywords(String keywordsString) {
    return _parseCached(
      keywordsString,
      'keywords',
      (input) => input.isEmpty ? {} : input.split('@').map((keyword) => keyword.trim()).toSet(),
      _keywordsCache,
    );
  }

  // 检查URL是否包含白名单扩展关键字
  bool _isWhitelisted(String url) {
    final whiteExtensions = _parseWhiteExtensions(M3U8Constants.whiteExtensions);
    return whiteExtensions.any((ext) => url.toLowerCase().contains(ext.toLowerCase()));
  }

  // 处理URL（清理、补全、替换）
  String _processUrl(String url) {
    String cleaned = UrlUtils.basicUrlClean(url); // 清理URL
    cleaned = UrlUtils._protocolRegex.hasMatch(cleaned) ? cleaned : UrlUtils.buildFullUrl(cleaned, _parsedUri); // 补全协议
    return (fromParam != null && toParam != null) ? cleaned.replaceAll(fromParam!, toParam!) : cleaned; // 替换参数
  }

  // 获取时间偏移
  Future<int> _getTimeOffset() async {
    if (_cachedTimeOffset != null) return _cachedTimeOffset!;
    final localTime = DateTime.now();
    for (final api in M3U8Constants.timeApis) {
      try {
        final networkTime = await _getNetworkTime(api['url']!);
        if (networkTime != null) {
          _cachedTimeOffset = networkTime.difference(localTime).inMilliseconds;
          return _cachedTimeOffset!;
        }
      } catch (e) {
        LogUtil.e('获取时间源失败 (${api['name']}): $e');
      }
    }
    return 0;
  }

  // 获取网络时间
  Future<DateTime?> _getNetworkTime(String url) async {
    // 🔥 修改点：检查取消状态
    if (_isCancelled()) return null;
    
    // 🔥 修改点：传递cancelToken给HTTP请求
    final response = await HttpUtil().getRequest<String>(
      url, 
      retryCount: 1, 
      cancelToken: cancelToken
    );
    
    if (response == null || _isCancelled()) return null;
    try {
      final Map<String, dynamic> data = json.decode(response);
      if (url.contains('taobao')) return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?['t'] ?? '0'));
      else if (url.contains('suning')) return DateTime.parse(data['sysTime2'] ?? '');
      else if (url.contains('meituan')) return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?.toString() ?? '0'));
    } catch (e) {
      LogUtil.e('解析时间响应失败: $e');
    }
    return null;
  }

  // 准备时间拦截器脚本
  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) return '(function(){})();';
    final cacheKey = 'time_interceptor_${_cachedTimeOffset}';
    final cachedScript = _scriptCache.get(cacheKey);
    if (cachedScript != null) return cachedScript;
    try {
      final script = await rootBundle.loadString('assets/js/time_interceptor.js');
      final result = script.replaceAll('const timeOffset = 0', 'const timeOffset = $_cachedTimeOffset');
      _scriptCache.put(cacheKey, result);
      return result;
    } catch (e) {
      LogUtil.e('加载时间拦截器脚本失败: $e');
      return '(function(){})();';
    }
  }

  // 🔥 修改点：增强取消状态检查
  bool _isCancelled() => _isDisposed || (cancelToken?.isCancelled ?? false);

  // 初始化WebView控制器
  Future<void> _initController(Completer<String> completer, String filePattern) async {
    // 🔥 修改点：在初始化开始就检查取消状态
    if (_isCancelled()) {
      LogUtil.i('GetM3U8: 初始化控制器前任务被取消');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    
    try {
      _isControllerInitialized = true;
      final httpResult = await _tryHttpRequest(); // 尝试HTTP请求
      
      // 🔥 修改点：HTTP请求后立即检查取消状态
      if (_isCancelled()) {
        LogUtil.i('GetM3U8: HTTP 请求完成后任务被取消');
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
      
      if (httpResult == true) {
        final result = await _checkPageContent(); // 检查页面内容
        if (result != null) {
          if (!completer.isCompleted) completer.complete(result);
          return;
        }
        if (!_isHtmlContent) {
          if (!completer.isCompleted) completer.complete('ERROR');
          return;
        }
      }
      await _initializeWebViewController(completer); // 初始化WebView
    } catch (e, stackTrace) {
      LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
      _isControllerInitialized = true;
      await _handleLoadError(completer); // 处理加载错误
    }
  }

  // 尝试HTTP请求
  Future<bool> _tryHttpRequest() async {
    try {
      // 🔥 修改点：传递cancelToken给HTTP请求
      final httpdata = await HttpUtil().getRequest(url, cancelToken: cancelToken);
      
      // 🔥 修改点：请求完成后检查取消状态
      if (_isCancelled()) return false;
      
      if (httpdata != null) {
        _httpResponseContent = httpdata.toString();
        _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || _httpResponseContent!.contains('<html'); // 判断是否为HTML
        if (_isHtmlContent) {
          String content = _httpResponseContent!;
          int styleEndIndex = -1;
          final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
          if (styleEndMatch != null) styleEndIndex = styleEndMatch.end;
          String initialContent = styleEndIndex > 0
              ? content.substring(styleEndIndex, (styleEndIndex + M3U8Constants.contentSampleLength).clamp(0, content.length))
              : content.length > M3U8Constants.contentSampleLength ? content.substring(0, M3U8Constants.contentSampleLength) : content;
          return initialContent.contains('.' + _filePattern); // 检查是否包含文件模式
        }
        return true;
      } else {
        LogUtil.e('HttpUtil请求失败，未获取到数据，将继续尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true;
        return false;
      }
    } catch (e) {
      // 🔥 修改点：区分取消异常和其他异常
      if (_isCancelled()) {
        LogUtil.i('GetM3U8: HTTP请求被取消');
        return false;
      }
      
      LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
      _httpResponseContent = null;
      _isHtmlContent = true;
      return false;
    }
  }

  // 初始化WebView控制器
  Future<void> _initializeWebViewController(Completer<String> completer) async {
    // 🔥 修改点：方法开始就检查取消状态
    if (_isCancelled()) {
      LogUtil.i('GetM3U8: WebView初始化前任务被取消');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    
    if (!isHashRoute && !_isHtmlContent) {
      LogUtil.i('检测到非HTML内容，直接处理');
      final result = await _checkPageContent();
      if (result != null) {
        if (!completer.isCompleted) completer.complete(result);
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
      return;
    }
    _cachedTimeOffset ??= await _getTimeOffset(); // 获取时间偏移
    
    // 🔥 修改点：获取时间偏移后检查取消状态
    if (_isCancelled()) {
      LogUtil.i('GetM3U8: 获取时间偏移后任务被取消');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JavaScript
      ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
    final initScripts = await Future.wait([
      _prepareTimeInterceptorCode(), // 时间拦截器脚本
      Future.value('''window._videoInit = false;window._processedUrls = new Set();window._m3u8Found = false;'''), // 初始化脚本
      _prepareM3U8DetectorCode(), // M3U8检测器脚本
    ]);
    
    await _setupJavaScriptChannels(completer); // 设置JavaScript通道 
    await _setupNavigationDelegate(completer, initScripts); // 设置导航代理
    await _loadUrlWithHeaders(); // 加载URL
    LogUtil.i('WebViewController初始化完成');
  }

  // 处理JavaScript消息
  void _handleJsMessage(String channel, String message, Completer<String> completer) {
    // 🔥 修改点：处理消息前检查取消状态
    if (_isCancelled()) {
      LogUtil.i('GetM3U8: JavaScript消息处理前任务被取消');
      return;
    }
    
    try {
      final data = json.decode(message);
      switch (channel) {
        case 'TimeCheck':
          if (data['type'] == 'timeRequest') {
            final method = data['method'] ?? 'unknown';
            final detail = data['detail'];
            final now = DateTime.now().add(Duration(milliseconds: _cachedTimeOffset ?? 0));
            LogUtil.i('检测到时间请求: $method ${detail != null ? '(详情: $detail)' : ''}，返回时间：$now');
          } else if (data['type'] == 'init') {
            LogUtil.i('时间拦截器初始化完成，偏移量: ${data['offset']}ms');
          } else if (data['type'] == 'cleanup') {
            LogUtil.i('时间拦截器清理完成');
          }
          break;
        case 'M3U8Detector':
          if (data['type'] == 'init') {
            return;
          }
          final String? url = data['url'];
          final String source = data['source'] ?? 'unknown';
          LogUtil.i('M3U8Detector: 发现URL [来源:$source] - ${url ?? "无URL"}');
          _handleM3U8Found(url, completer); // 处理发现的M3U8
          break;
        case 'CleanupCompleted':
          if (data['type'] == 'cleanup') {
            LogUtil.i('WebView资源清理完成: ${json.encode(data['details'])}');
          }
          break;
        case 'ClickHandler':
          // 新增处理点击日志的逻辑
          final type = data['type'] ?? 'unknown';
          final msg = data['message'] ?? 'No message';
          final details = data['details'] ?? {};
          
          switch (type) {
            case 'error':
              LogUtil.e('点击器错误: $msg, 详情: ${json.encode(details)}');
              break;
            case 'success':
              LogUtil.i('点击成功: $msg, 详情: ${json.encode(details)}');
              break;
            case 'start':
              LogUtil.i('点击器启动: $msg, 详情: ${json.encode(details)}');
              break;
            case 'click':
              LogUtil.i('点击执行: $msg, 详情: ${json.encode(details)}');
              break;
            case 'info':
            default:
              LogUtil.i('点击器信息: $msg, 详情: ${json.encode(details)}');
              break;
          }
          break;
      }
    } catch (e) {
      if (channel == 'M3U8Detector') _handleM3U8Found(message, completer);
      else if (channel == 'ClickHandler') {
        LogUtil.e('处理点击消息失败: $e, 原始消息: $message');
      }
      else LogUtil.e('处理 $channel 消息失败: $e');
    }
  }

  // 设置JavaScript通道
  Future<void> _setupJavaScriptChannels(Completer<String> completer) async {
    for (var channel in ['TimeCheck', 'M3U8Detector', 'CleanupCompleted', 'ClickHandler']) {
      _controller.addJavaScriptChannel(channel, onMessageReceived: (message) {
        _handleJsMessage(channel, message.message, completer);
      });
    }
  }

  // 设置导航代理
  Future<void> _setupNavigationDelegate(Completer<String> completer, List<String> initScripts) async {
    final whiteExtensions = _parseWhiteExtensions(M3U8Constants.whiteExtensions); // 白名单关键字
    final blockedExtensions = _parseBlockedExtensions(M3U8Constants.blockedExtensions); // 屏蔽的扩展名
    final scriptNames = ['时间拦截器脚本', '自动点击脚本', 'M3U8检测器脚本'];

    _controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (String url) async {
        // 🔥 修改点：页面开始加载时检查取消状态
        if (_isCancelled()) {
          LogUtil.i('GetM3U8: 页面开始加载时任务被取消: $url');
          return;
        }
        for (int i = 0; i < initScripts.length; i++) {
          try {
            await _controller.runJavaScript(initScripts[i]); // 注入脚本
            LogUtil.i('注入脚本成功: ${scriptNames[i]}');
          } catch (e) {
            LogUtil.e('注入脚本失败 (${scriptNames[i]}): $e');
          }
        }
      },
      onNavigationRequest: (NavigationRequest request) async {
        LogUtil.i('页面导航请求: ${request.url}');
        Uri? uri;
        try {
          uri = Uri.parse(request.url);
        } catch (e) {
          LogUtil.i('无效的URL，阻止加载: ${request.url}');
          return NavigationDecision.prevent;
        }
        final fullUrl = request.url.toLowerCase();
        
        // 检查是否在白名单中
        bool isWhitelisted = _isWhitelisted(request.url);
        if (isWhitelisted) {
          LogUtil.i('URL匹配白名单关键字，允许加载: ${request.url}');
          return NavigationDecision.navigate;
        }
        
        // 如果不在白名单中，执行屏蔽检查
        if (blockedExtensions.any((ext) => fullUrl.contains(ext))) {
          LogUtil.i('阻止加载资源: ${request.url} (包含扩展名)');
          return NavigationDecision.prevent;
        }
        if (_invalidPatternRegex.hasMatch(fullUrl)) {
          LogUtil.i('阻止广告/跟踪请求: ${request.url}');
          return NavigationDecision.prevent;
        }

        // 如果是需要的流媒体类型，发送到检测器，阻止加载
        if (_validateUrl(request.url, _filePattern)) {
          await _controller.runJavaScript(
            'window.M3U8Detector?.postMessage(${json.encode({'type': 'url', 'url': request.url, 'source': 'navigation'})});'
          ).catchError((e) => LogUtil.e('发送M3U8URL到检测器失败: $e'));
          return NavigationDecision.prevent;
        }
        
        return NavigationDecision.navigate;
      },
      onPageFinished: (String url) async {
        // 🔥 修改点：页面加载完成时检查取消状态
        if (_isCancelled()) {
          LogUtil.i('GetM3U8: 页面加载完成时任务被取消: $url');
          return;
        }
        if (!isHashRoute && _pageLoadedStatus.contains(url)) {
          LogUtil.i('本页面已经加载完成，跳过重复处理');
          return;
        }
        _pageLoadedStatus.add(url); // 记录页面加载状态
        LogUtil.i('页面加载完成: $url');
        if (_isClickExecuted) {
          LogUtil.i('点击已执行，跳过处理');
          return;
        }
        if (isHashRoute && !_handleHashRoute(url)) return; // 处理Hash路由
        if (!_isClickExecuted && clickText != null) {
          await Future.delayed(const Duration(milliseconds: M3U8Constants.clickDelayMs));
          if (!_isCancelled()) {
            final clickResult = await _executeClick(); // 执行点击操作
            if (clickResult) _startUrlCheckTimer(completer); // 启动URL检查定时器
          }
        }
        if (!_isCancelled() && !_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
          _setupPeriodicCheck(); // 设置定期检查
        }
      },
      onWebResourceError: (WebResourceError error) async {
        // 🔥 修改点：资源错误时检查取消状态
        if (_isCancelled()) {
          LogUtil.i('GetM3U8: 资源错误时任务被取消: ${error.description}');
          return;
        }
        if (error.errorCode == -1 || error.errorCode == -6 || error.errorCode == -7) {
          LogUtil.i('资源被阻止加载: ${error.description}');
          return;
        }
        LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
        await _handleLoadError(completer); // 处理加载错误
      },
    ));
  }

  // 处理Hash路由
  bool _handleHashRoute(String url) {
    try {
      final currentUri = _parsedUri;
      String mapKey = currentUri.toString();
      _pageLoadedStatus.clear();
      _pageLoadedStatus.add(mapKey);
      int currentTriggers = _hashFirstLoadMap[mapKey] ?? 0;
      currentTriggers++;
      if (currentTriggers > M3U8Constants.maxRetryCount) {
        LogUtil.i('hash路由触发超过${M3U8Constants.maxRetryCount}次，跳过处理');
        return false;
      }
      _hashFirstLoadMap[mapKey] = currentTriggers;
      if (currentTriggers == 1) {
        LogUtil.i('检测到hash路由首次加载，等待第二次加载');
        return false;
      }
      return true;
    } catch (e) {
      LogUtil.e('解析URL失败: $e');
      return true;
    }
  }

  // 执行点击操作
  Future<bool> _executeClick() async {
    if (!_isControllerInitialized || _isClickExecuted || clickText == null || clickText!.isEmpty) {
      final reason = !_isControllerInitialized ? 'WebViewController 未初始化' : _isClickExecuted ? '点击已执行' : '无点击配置';
      LogUtil.i('$reason，跳过点击操作');
      return false;
    }
    
    // 🔥 修改点：执行点击前检查取消状态
    if (_isCancelled()) {
      LogUtil.i('GetM3U8: 执行点击前任务被取消');
      return false;
    }
    
    LogUtil.i('开始执行点击操作，文本: $clickText, 索引: $clickIndex');
    try {
      final cacheKey = 'click_handler_${clickText}_${clickIndex}';
      String scriptWithParams;
      final cachedScript = _scriptCache.get(cacheKey);
      if (cachedScript != null) {
        scriptWithParams = cachedScript;
      } else {
        final baseScript = await rootBundle.loadString('assets/js/click_handler.js');
        scriptWithParams = baseScript
            .replaceAll('const searchText = ""', 'const searchText = "$clickText"')
            .replaceAll('const targetIndex = 0', 'const targetIndex = $clickIndex');
        _scriptCache.put(cacheKey, scriptWithParams);
      }
      await _controller.runJavaScript(scriptWithParams); // 执行点击脚本
      _isClickExecuted = true;
      LogUtil.i('点击操作执行完成，结果: 成功');
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _isClickExecuted = true;
      return true;
    }
  }

  // 启动URL检查定时器
  void _startUrlCheckTimer(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    Timer(const Duration(milliseconds: M3U8Constants.urlCheckDelayMs), () async {
      if (_isCancelled() || completer.isCompleted) return;
      if (_foundUrls.length > 0) {
        _m3u8Found = true;
        final urlsList = _foundUrls.toList();
        String selectedUrl = (clickIndex == 0 || clickIndex >= urlsList.length) ? urlsList.last : urlsList[clickIndex];
        LogUtil.i('使用${clickIndex == 0 ? "最后" : "指定索引($clickIndex)"}发现的URL: $selectedUrl');
        if (!completer.isCompleted) completer.complete(selectedUrl);
        await dispose(); // 释放资源
      } else {
        LogUtil.i('未发现任何URL');
      }
    });
  }

  // 处理加载错误
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_isCancelled() || completer.isCompleted) return;
    if (_retryCount < M3U8Constants.maxRetryCount) {
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/${M3U8Constants.maxRetryCount})，延迟${M3U8Constants.retryDelayMs}毫秒');
      await Future.delayed(const Duration(milliseconds: M3U8Constants.retryDelayMs));
      if (!_isCancelled() && !completer.isCompleted) {
        _pageLoadedStatus.clear();
        _isClickExecuted = false;
        if (_retryCount > 1) {
          _filePattern = _filePattern == 'm3u8' ? 'mp4' : 'm3u8'; // 切换检测策略
          LogUtil.i('切换检测策略为: $_filePattern');
        }
        await _initController(completer, _filePattern);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或任务已取消');
      completer.complete('ERROR');
      await dispose();
    }
  }

  // 加载URL并设置请求头
  Future<void> _loadUrlWithHeaders() async {
    if (!_isControllerInitialized) {
      LogUtil.e('WebViewController 未初始化，无法加载URL');
      return;
    }
    try {
      final headers = HeadersConfig.generateHeaders(url: url); // 生成请求头
      await _controller.loadRequest(_parsedUri, headers: headers);
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      throw Exception('URL 加载失败: $e');
    }
  }

  // 重置控制器状态
  void _resetControllerState() {
    _isControllerInitialized = false;
    _isClickExecuted = false;
    _m3u8Found = false;
    _retryCount = 0;
    _checkCount = 0;
  }

  // 设置定期检查
  void _setupPeriodicCheck() {
    if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
      final reason = _periodicCheckTimer != null ? "定时器已存在" : _isCancelled() ? "任务被取消" : "已找到M3U8";
      LogUtil.i('跳过定期检查设置: $reason');
      return;
    }
    _prepareM3U8DetectorCode().then((detectorScript) {
      if (_m3u8Found || _isCancelled()) return;
      _periodicCheckTimer = Timer.periodic(const Duration(milliseconds: M3U8Constants.periodicCheckIntervalMs), (timer) async {
        if (_m3u8Found || _isCancelled()) {
          timer.cancel();
          _periodicCheckTimer = null;
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "任务被取消"}');
          return;
        }
        _checkCount++;
        LogUtil.i('执行第$_checkCount次定期检查');
        if (!_isControllerInitialized) {
          LogUtil.i('WebViewController未准备好，跳过本次检查');
          return;
        }
        try {
          await _controller.runJavaScript('''
          if (window._m3u8DetectorInitialized) {
            checkMediaElements(document);
            efficientDOMScan();
          } else {
            ${detectorScript}
            checkMediaElements(document);
            efficientDOMScan();
          }
          ''').catchError((error) => LogUtil.e('执行扫描失败: $error')); // 执行DOM扫描
        } catch (e, stack) {
          LogUtil.logError('定期检查执行出错', e, stack);
        }
      });
    });
  }

  // 启动超时计时
  void _startTimeout(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      if (_isCancelled() || completer.isCompleted) return;
      if (_foundUrls.length > 0 && !completer.isCompleted) {
        _m3u8Found = true;
        final selectedUrl = _foundUrls.toList().last;
        LogUtil.i('超时前发现URL: $selectedUrl');
        completer.complete(selectedUrl);
      } else if (!completer.isCompleted) completer.complete('ERROR');
      await dispose();
    });
  }

  // 🔥 修改点：改进dispose方法，确保CancelToken相关资源正确释放
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    
    LogUtil.i('GetM3U8: 开始释放资源');
    
    // 🔥 修改点：首先设置取消状态，阻止新的操作
    // 注意：我们不能取消外部传入的cancelToken，因为那可能影响其他操作
    // 只能通过_isDisposed标志来防止继续执行
    
    // 1. 取消所有计时器
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    
    // 2. 清理内存数据结构
    _hashFirstLoadMap.remove(Uri.parse(url).toString());
    _foundUrls.clear();
    _pageLoadedStatus.clear();
    
    // 3. 延迟清理WebView，但确保取消状态立即生效
    if (_isControllerInitialized) {
      bool isWhitelisted = _isWhitelisted(url);
      int cleanupDelay = isWhitelisted ? M3U8Constants.cleanupDelayMs : 0;
      
      // 🔥 修改点：即使延迟清理WebView，也要立即标记资源为已释放状态
      Future.delayed(Duration(milliseconds: cleanupDelay), () async {
        if (!_isDisposed) return; // 双重检查，防止重复清理
        await _disposeWebViewCompletely(_controller);
      });
    } else {
      LogUtil.i('WebViewController 未初始化，跳过清理');
    }
    
    _resetControllerState();
    _httpResponseContent = null;
    
    LogUtil.i('GetM3U8: 资源释放标记完成');
  }

  // 完全清理WebView
  Future<void> _disposeWebViewCompletely(WebViewController controller) async {
    try {
      final cleanupScript = await rootBundle.loadString('assets/js/cleanup_script.js');
      await controller.runJavaScript(cleanupScript)
          .catchError((e) => LogUtil.e('执行清理脚本失败: $e')); // 执行清理脚本
      await Future.delayed(Duration(milliseconds: M3U8Constants.webviewCleanupDelayMs));
      await controller.setNavigationDelegate(NavigationDelegate());
      await controller.loadRequest(Uri.parse('about:blank')); // 加载空白页
      await controller.clearCache(); // 清理缓存
      await controller.clearLocalStorage(); // 清理本地存储
      await controller.runJavaScript('window.location.href = "about:blank";');
      LogUtil.i('已清理资源，并重置页面');
    } catch (e, stack) {
      LogUtil.logError('清理 WebView 时发生错误', e, stack);
    }
  }

  // 处理发现的M3U8 URL
  Future<void> _handleM3U8Found(String? url, Completer<String> completer) async {
    if (_m3u8Found || _isCancelled() || completer.isCompleted || url == null || url.isEmpty) return;
    String finalUrl = _processUrl(url); // 处理URL
    if (!_validateUrl(finalUrl, _filePattern)) return;
    _foundUrls.add(finalUrl);
    if (clickText == null) {
      _m3u8Found = true;
      LogUtil.i('发现有效URL: $finalUrl');
      completer.complete(finalUrl);
      await dispose();
    } else {
      LogUtil.i('点击逻辑触发，记录URL: $finalUrl, 等待计时结束');
    }
  }

  // 获取M3U8 URL
  Future<String> getUrl() async {
    final completer = Completer<String>();
    
    // 🔥 修改点：在开始前检查取消状态
    if (_isCancelled()) {
      LogUtil.i('GetM3U8: 任务在启动前被取消');
      return 'ERROR';
    }
    
    final dynamicKeywords = _parseKeywords(M3U8Constants.dynamicKeywords);
    for (final keyword in dynamicKeywords) {
      if (url.contains(keyword)) {
        try {
          // 🔥 修改点：传递cancelToken给GetM3u8Diy
          final streamUrl = await GetM3u8Diy.getStreamUrl(url, cancelToken: cancelToken);
          LogUtil.i('getm3u8diy 返回结果: $streamUrl');
          return streamUrl;
        } catch (e, stackTrace) {
          // 🔥 修改点：区分取消异常和其他异常
          if (e is DioException && e.type == DioExceptionType.cancel) {
            LogUtil.i('getm3u8diy 被取消');
            return 'ERROR';
          }
          LogUtil.logError('getm3u8diy 获取播放地址失败，返回 ERROR', e, stackTrace);
          return 'ERROR';
        }
      }
    }
    
    try {
      await _initController(completer, _filePattern); // 初始化控制器
      _startTimeout(completer); // 启动超时计时
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      if (!completer.isCompleted) completer.complete('ERROR');
    }
    return completer.future;
  }

  // 检查页面内容
  Future<String?> _checkPageContent() async {
    // 🔥 修改点：检查页面内容前先检查取消状态
    if (_m3u8Found || _isCancelled()) {
      LogUtil.i('跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "任务被取消"}');
      return null;
    }
    if (clickText != null && !_isClickExecuted) {
      LogUtil.i('点击操作未完成，跳过页面内容检查');
      return null;
    }
    try {
      if (_httpResponseContent == null || _httpResponseContent!.isEmpty) {
        LogUtil.e('页面内容为空，跳过检测');
        return null;
      }
      String sample = UrlUtils.basicUrlClean(_httpResponseContent!); // 清理内容
      final matches = _m3u8Pattern.allMatches(sample); // 匹配M3U8
      LogUtil.i('正则匹配到 ${matches.length} 个 $_filePattern 结果');
      return await _processMatches(matches, sample); // 处理匹配结果
    } catch (e, stackTrace) {
      LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
      return null;
    }
  }

  // 处理正则匹配结果
  Future<String?> _processMatches(Iterable<Match> matches, String sample) async {
    if (matches.isEmpty) return null;
    final uniqueUrls = <String>{};
    for (final match in matches) {
      String url = match.group(0) ?? '';
      if (url.isNotEmpty) uniqueUrls.add(url);
    }
    final validUrls = <String>[];
    for (final url in uniqueUrls) {
      final cleanedUrl = _processUrl(url); // 处理URL
      if (_validateUrl(cleanedUrl, _filePattern)) validUrls.add(cleanedUrl);
    }
    if (validUrls.isEmpty) return null;
    if (clickIndex >= 0 && clickIndex < validUrls.length) {
      _m3u8Found = true;
      LogUtil.i('找到目标URL(index=$clickIndex): ${validUrls[clickIndex]}');
      return validUrls[clickIndex];
    } else {
      _m3u8Found = true;
      LogUtil.i('clickIndex=$clickIndex 超出范围(共${validUrls.length}个地址)，返回第一个地址: ${validUrls[0]}');
      return validUrls[0];
    }
  }

  // 准备M3U8检测器脚本
  Future<String> _prepareM3U8DetectorCode() async {
    final cacheKey = 'm3u8_detector_${_filePattern}';
    final cachedScript = _scriptCache.get(cacheKey);
    if (cachedScript != null) return cachedScript;
    try {
      final script = await rootBundle.loadString('assets/js/m3u8_detector.js');
      final result = script.replaceAll('const filePattern = "m3u8"', 'const filePattern = "$_filePattern"');
      _scriptCache.put(cacheKey, result);
      return result;
    } catch (e) {
      LogUtil.e('加载M3U8检测器脚本失败: $e');
      return '(function(){console.error("M3U8检测器加载失败");})();';
    }
  }
}
