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

// 管理M3U8相关常量
class M3U8Constants {
  // 数值常量
  static const int defaultTimeoutSeconds = 18; // 单次解析的超时时间（秒）
  static const int maxFoundUrlsSize = 50; // 最大已发现URL存储量
  static const int maxPageLoadedStatusSize = 50; // 最大已加载页面状态存储量
  static const int maxCacheSize = 50; // 通用缓存最大容量
  static const int maxRuleCacheSize = 20; // 规则缓存最大容量
  static const int maxRetryCount = 1; // 最大重试次数
  static const int periodicCheckIntervalMs = 500; // 定期检查间隔（毫秒）
  static const int clickDelayMs = 500; // 点击操作延迟（毫秒）
  static const int urlCheckDelayMs = 3000; // URL检查延迟（毫秒）
  static const int retryDelayMs = 500; // 重试延迟（毫秒）
  static const int contentSampleLength = 39888; // 内容采样长度
  static const int cleanupDelayMs = 3000; // 清理延迟（毫秒）
  static const int webviewCleanupDelayMs = 500; // WebView清理延迟（毫秒）
  static const int defaultSetSize = 50; // 默认集合大小 

  // 字符串常量
  static const String rulePatterns = 'sztv.com.cn|m3u8?sign=@4gtv.tv|master.m3u8@tcrbs.com|auth_key@xybtv.com|auth_key@aodianyun.com|auth_key@ptbtv.com|hd/live@setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook='; // M3U8过滤规则
  static const String specialRulePatterns = 'nctvcloud.com|flv@iptv345.com|flv'; // 特殊规则模式
  static const String dynamicKeywords = 'sousuo@jinan@gansu@xizang@sichuan@xishui@yanan@foshan'; // 动态关键字
  static const String whiteExtensions = 'r.png?t=@www.hljtv.com@guangdianyun.tv'; // 白名单扩展名
  static const String blockedExtensions = '.png@.jpg@.jpeg@.gif@.webp@.css@.woff@.woff2@.ttf@.eot@.ico@.svg@.mp3@.wav@.pdf@.doc@.docx@.swf'; // 屏蔽扩展名
  static const String invalidPatterns = 'advertisement|analytics|tracker|pixel|beacon|stats|google'; // 无效模式（广告、跟踪）

  // 数据结构常量
  static const List<Map<String, String>> timeApis = [
    {'name': 'Aliyun API', 'url': 'https://acs.m.taobao.com/gw/mtop.common.getTimestamp/'}, // 阿里云时间API
    {'name': 'Suning API', 'url': 'https://quan.suning.com/getSysTime.do'}, // 苏宁时间API
    {'name': 'Meituan API', 'url': 'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime'}, // 美团时间API
  ]; // 时间同步API列表
}

// URL处理工具
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

  // 清理URL中的转义字符、HTML实体及多斜杠
  static String basicUrlClean(String url) {
    if (url.isEmpty) return url;
    if (url.endsWith(r'\')) url = url.substring(0, url.length - 1); // 移除末尾反斜杠
    String result = url
        .replaceAllMapped(_escapeRegex, (match) => match.group(1)!) // 清理转义字符
        .replaceAll(r'\/', '/') // 统一斜杠格式
        .replaceAll(_multiSlashRegex, '/') // 合并连续斜杠
        .replaceAllMapped(_htmlEntityRegex, (m) => _htmlEntities[m.group(1)] ?? m.group(0)!) // 转换HTML实体
        .replaceAllMapped(_unicodeRegex, (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16))); // 解码Unicode字符
    if (result.contains('%')) {
      try {
        result = Uri.decodeComponent(result); // 解码URL编码
      } catch (e) {
        // 解码失败，保持原样
      }
    }
    return result.trim(); // 去除首尾空格
  }

  // 构建完整URL
  static String buildFullUrl(String path, Uri baseUri) {
    if (_protocolRegex.hasMatch(path)) return path; // 已含协议，直接返回
    if (path.startsWith('//')) return '${baseUri.scheme}://${path.replaceFirst('//', '')}'; // 处理无协议URL
    String cleanPath = path.startsWith('/') ? path.substring(1) : path; // 清理开头斜杠
    return '${baseUri.scheme}://${baseUri.host}/$cleanPath'; // 拼接完整URL
  }
}

// M3U8过滤规则
class M3U8FilterRule {
  final String domain; // 域名
  final String requiredKeyword; // 必需关键字

  const M3U8FilterRule({required this.domain, required this.requiredKeyword});

  // 解析规则字符串
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length < 2) return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: '');
    return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: parts[1].trim());
  }
}

// 限制大小的集合
class LimitedSizeSet<T> {
  final int maxSize; // 最大容量
  final LinkedHashSet<T> _set; // 内部集合

  LimitedSizeSet([this.maxSize = M3U8Constants.defaultSetSize]) : _set = LinkedHashSet();

  // 添加元素，超出容量移除最早元素
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

// 通用LRU缓存
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

// M3U8地址获取
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

  // 验证URL有效性
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
      LogUtil.e('URL解析失败: $e');
      _parsedUri = Uri(scheme: 'https', host: 'invalid.host');
      isHashRoute = false;
    }
    _filePattern = _determineFilePattern(url); // 确定文件模式
    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL替换参数: from=$fromParam, to=$toParam');
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
        LogUtil.i('应用特殊模式: $pattern for URL: $url');
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
      LogUtil.e('URL参数解析失败: $e');
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

  // 检查URL是否包含白名单扩展
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
        LogUtil.e('时间源获取失败 (${api['name']}): $e');
      }
    }
    return 0;
  }

  // 获取网络时间
  Future<DateTime?> _getNetworkTime(String url) async {
    if (_isCancelled()) return null;
    final response = await HttpUtil().getRequest<String>(url, retryCount: 1, cancelToken: cancelToken);
    if (response == null || _isCancelled()) return null;
    try {
      final Map<String, dynamic> data = json.decode(response);
      if (url.contains('taobao')) return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?['t'] ?? '0'));
      else if (url.contains('suning')) return DateTime.parse(data['sysTime2'] ?? '');
      else if (url.contains('meituan')) return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?.toString() ?? '0'));
    } catch (e) {
      LogUtil.e('时间响应解析失败: $e');
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
      LogUtil.e('时间拦截器脚本加载失败: $e');
      return '(function(){})();';
    }
  }

  // 检查任务是否取消
  bool _isCancelled() => _isDisposed || (cancelToken?.isCancelled ?? false);

  // 初始化WebView控制器
  Future<void> _initController(Completer<String> completer, String filePattern) async {
    if (_isCancelled()) {
      LogUtil.i('任务取消，终止控制器初始化');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    try {
      _isControllerInitialized = true;
      final httpResult = await _tryHttpRequest(); // 尝试HTTP请求
      if (_isCancelled()) {
        LogUtil.i('HTTP请求后任务取消');
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
      if (httpResult == true) {
        final result = await _checkPageContent(); // 检查页面内容
        if (result != null) {
          if (!completer.isCompleted) {
            completer.complete(result);
            await dispose();
          }
          return;
        }
        if (!_isHtmlContent) {
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            await dispose();
          }
          return;
        }
      }
      await _initializeWebViewController(completer); // 初始化WebView
    } catch (e, stackTrace) {
      LogUtil.logError('WebViewController初始化失败', e, stackTrace);
      _isControllerInitialized = true;
      await _handleLoadError(completer); // 处理加载错误
    }
  }

  // 尝试HTTP请求
  Future<bool> _tryHttpRequest() async {
    try {
      final httpdata = await HttpUtil().getRequest(url, cancelToken: cancelToken);
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
          return initialContent.contains('.' + _filePattern); // 检查是否含文件模式
        }
        return true;
      } else {
        LogUtil.e('HTTP请求失败，尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true;
        return false;
      }
    } catch (e) {
      if (_isCancelled()) return false;
      LogUtil.e('HTTP请求异常: $e，尝试WebView加载');
      _httpResponseContent = null;
      _isHtmlContent = true;
      return false;
    }
  }

  // 初始化WebView控制器
  Future<void> _initializeWebViewController(Completer<String> completer) async {
    if (_isCancelled()) return;
    if (!isHashRoute && !_isHtmlContent) {
      LogUtil.i('非HTML内容，直接处理');
      final result = await _checkPageContent();
      if (result != null) {
        if (!completer.isCompleted) completer.complete(result);
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
      return;
    }
    _cachedTimeOffset ??= await _getTimeOffset(); // 获取时间偏移
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
  }

  // === 修改点1: 增强JavaScript消息处理的异常安全 ===
  void _handleJsMessage(String channel, String message, Completer<String> completer) {
    if (_isCancelled()) return;
    try {
      final data = json.decode(message);
      switch (channel) {
        case 'TimeCheck':
          if (data['type'] == 'timeRequest') {
            final method = data['method'] ?? 'unknown';
            final detail = data['detail'];
            final now = DateTime.now().add(Duration(milliseconds: _cachedTimeOffset ?? 0));
            LogUtil.i('时间请求: $method ${detail != null ? '(详情: $detail)' : ''}, 返回: $now');
          } else if (data['type'] == 'init') {
            LogUtil.i('时间拦截器初始化，偏移量: ${data['offset']}ms');
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
          LogUtil.i('发现URL [来源:$source]: ${url ?? "无URL"}');
          _handleM3U8Found(url, completer); // 处理M3U8 URL
          break;
        case 'CleanupCompleted':
          if (data['type'] == 'cleanup') {
            LogUtil.i('WebView资源清理完成: ${json.encode(data['details'])}');
          }
          break;
        case 'ClickHandler':
          final type = data['type'] ?? 'unknown';
          final msg = data['message'] ?? 'No message';
          final details = data['details'] ?? {};
          switch (type) {
            case 'error':
              LogUtil.e('点击器错误: $msg, 详情: ${json.encode(details)}');
              break;
            case 'success':
              LogUtil.i('点击操作成功: $msg, 详情: ${json.encode(details)}');
              break;
            case 'start':
              LogUtil.i('点击器启动: $msg, 详情: ${json.encode(details)}');
              break;
            case 'click':
              LogUtil.i('执行点击: $msg, 详情: ${json.encode(details)}');
              break;
            case 'info':
            default:
              LogUtil.i('点击器信息: $msg, 详情: ${json.encode(details)}');
              break;
          }
          break;
      }
    } catch (e) {
      LogUtil.e('JSON消息解析异常: $e');
      // === 增强异常处理: JSON解析失败时尝试直接处理 ===
      if (channel == 'M3U8Detector') {
        // 如果消息包含当前检测的文件格式，尝试直接处理
        if (message.contains('.$_filePattern')) {
          LogUtil.i('尝试直接处理URL消息: $message');
          _handleM3U8Found(message, completer);
        }
      } else if (channel == 'ClickHandler') {
        LogUtil.e('点击消息处理失败: $e, 消息: $message');
      } else {
        LogUtil.e('处理 $channel 消息失败: $e');
      }
    } catch (e) {
      LogUtil.e('JavaScript消息处理严重异常: $e, 通道: $channel');
      // 严重异常也不应该阻止其他检测继续
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
    final blockedExtensions = _parseBlockedExtensions(M3U8Constants.blockedExtensions); // 屏蔽扩展名
    final scriptNames = ['时间拦截器脚本', '初始化脚本', 'M3U8检测器脚本'];

    _controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (String url) async {
        if (_isCancelled()) {
          LogUtil.i('页面加载取消: $url');
          return;
        }
        
        // 🔑 关键：时间拦截器必须同步注入，确保在页面JS执行前生效
        try {
          await _controller.runJavaScript(initScripts[0]); // 时间拦截器脚本
          LogUtil.i('注入成功: ${scriptNames[0]}');
        } catch (e) {
          LogUtil.e('注入失败 (${scriptNames[0]}): $e');
        }
        
        // 🚀 其他脚本可以异步注入
        for (int i = 1; i < initScripts.length; i++) {
          unawaited(_controller.runJavaScript(initScripts[i]).then((_) {
            LogUtil.i('注入成功: ${scriptNames[i]}');
          }).catchError((e) {
            LogUtil.e('注入失败 (${scriptNames[i]}): $e');
            return null;
          }));
        }
        
        LogUtil.i('时间拦截器同步注入完成，其他脚本异步注入启动');
        
        // === 关键修改1: 脚本注入后立即启动定期检查，不等页面完成 ===
        try {
          if (!_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
            LogUtil.i('脚本注入后立即启动定期检查');
            _setupPeriodicCheck(); // 提前启动定期检查
          }
        } catch (earlyCheckError) {
          LogUtil.e('早期定期检查启动异常: $earlyCheckError');
          // 启动异常不影响页面加载
        }
      },
      onNavigationRequest: (NavigationRequest request) async {
        LogUtil.i('导航请求: ${request.url}');
        Uri? uri;
        try {
          uri = Uri.parse(request.url);
        } catch (e) {
          LogUtil.i('无效URL，阻止加载: ${request.url}');
          return NavigationDecision.prevent;
        }
        final fullUrl = request.url.toLowerCase();
        bool isWhitelisted = _isWhitelisted(request.url);
        if (isWhitelisted) {
          LogUtil.i('白名单URL，允许加载: ${request.url}');
          return NavigationDecision.navigate;
        }
        if (blockedExtensions.any((ext) => fullUrl.contains(ext))) {
          LogUtil.i('阻止资源: ${request.url} (含屏蔽扩展名)');
          return NavigationDecision.prevent;
        }
        if (_invalidPatternRegex.hasMatch(fullUrl)) {
          LogUtil.i('阻止广告/跟踪: ${request.url}');
          return NavigationDecision.prevent;
        }
        if (_validateUrl(request.url, _filePattern)) {
          // 🚀 修改：异步发送M3U8 URL，不阻塞导航
          unawaited(_controller.runJavaScript(
            'window.M3U8Detector?.postMessage(${json.encode({'type': 'url', 'url': request.url, 'source': 'navigation'})});'
          ).catchError((e) => LogUtil.e('M3U8 URL发送失败: $e')));
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onPageFinished: (String url) async {
        if (_isCancelled()) {
          LogUtil.i('页面加载取消: $url');
          return;
        }
        if (!isHashRoute && _pageLoadedStatus.contains(url)) {
          LogUtil.i('页面已加载，跳过处理');
          return;
        }
        _pageLoadedStatus.add(url); // 记录页面加载状态
        LogUtil.i('页面加载完成: $url');
        if (_isClickExecuted) {
          LogUtil.i('点击已执行，跳过');
          return;
        }
        if (isHashRoute && !_handleHashRoute(url)) return; // 处理Hash路由
        if (!_isClickExecuted && clickText != null) {
          await Future.delayed(const Duration(milliseconds: M3U8Constants.clickDelayMs));
          if (!_isCancelled()) {
            final clickResult = await _executeClick(); // 执行点击
            if (clickResult) _startUrlCheckTimer(completer); // 启动URL检查
          }
        }
        
        // === 修改点2: 避免重复启动定期检查，只在未启动时才启动 ===
        if (!_isCancelled() && !_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
          LogUtil.i('页面完成后补充启动定期检查');
          try {
            _setupPeriodicCheck(); // 设置定期检查
          } catch (supplementCheckError) {
            LogUtil.e('定期检查补充启动异常: $supplementCheckError');
          }
        }
      },
      onWebResourceError: (WebResourceError error) async {
        if (_isCancelled()) {
          LogUtil.i('资源错误，任务取消: ${error.description}');
          return;
        }
        if (error.errorCode == -1 || error.errorCode == -6 || error.errorCode == -7) {
          LogUtil.i('资源阻止加载: ${error.description}');
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
        LogUtil.i('Hash路由触发超限: ${M3U8Constants.maxRetryCount}次');
        return false;
      }
      _hashFirstLoadMap[mapKey] = currentTriggers;
      if (currentTriggers == 1) {
        LogUtil.i('Hash路由首次加载，等待下次加载');
        return false;
      }
      return true;
    } catch (e) {
      LogUtil.e('URL解析失败: $e');
      return true;
    }
  }

  // 执行点击操作
  Future<bool> _executeClick() async {
    if (!_isControllerInitialized || _isClickExecuted || clickText == null || clickText!.isEmpty) {
      final reason = !_isControllerInitialized ? '控制器未初始化' : _isClickExecuted ? '点击已执行' : '无点击配置';
      LogUtil.i('$reason，跳过点击');
      return false;
    }
    LogUtil.i('执行点击: 文本=$clickText, 索引=$clickIndex');
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
      // 🚀 修改：异步执行点击脚本，不阻塞主流程
      unawaited(_controller.runJavaScript(scriptWithParams).catchError((e) {
        LogUtil.e('点击脚本执行失败: $e');
      })); // 执行点击脚本
      _isClickExecuted = true;
      LogUtil.i('点击操作异步启动');
      return true;
    } catch (e, stack) {
      LogUtil.logError('点击操作失败', e, stack);
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
        LogUtil.i('选择URL: $selectedUrl (索引: $clickIndex)');
        if (!completer.isCompleted) completer.complete(selectedUrl);
        await dispose(); // 释放资源
      } else {
        LogUtil.i('未发现URL');
      }
    });
  }

  // 处理加载错误
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_isCancelled() || completer.isCompleted) return;
    if (_retryCount < M3U8Constants.maxRetryCount) {
      _retryCount++;
      LogUtil.i('重试: $_retryCount/${M3U8Constants.maxRetryCount}, 延迟${M3U8Constants.retryDelayMs}ms');
      
      // 取消旧的定期检查定时器
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = null;
      
      // 取消旧的超时定时器
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      
      // 重置检查计数
      _checkCount = 0;
      
      await Future.delayed(const Duration(milliseconds: M3U8Constants.retryDelayMs));
      if (!_isCancelled() && !completer.isCompleted) {
        _pageLoadedStatus.clear();
        _isClickExecuted = false;
        // 保持使用已确定的 _filePattern，不需要切换检测策略
        LogUtil.i('重试使用检测策略: $_filePattern');
        
        // 重新启动超时计时器
        _startTimeout(completer);
        
        await _initController(completer, _filePattern);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数');
      completer.complete('ERROR');
      await dispose();
    }
  }

  // 加载URL并设置请求头
  Future<void> _loadUrlWithHeaders() async {
    if (!_isControllerInitialized) {
      LogUtil.e('控制器未初始化，无法加载URL');
      return;
    }
    try {
      final headers = HeadersConfig.generateHeaders(url: url); // 生成请求头
      await _controller.loadRequest(_parsedUri, headers: headers);
    } catch (e, stackTrace) {
      LogUtil.logError('URL加载失败', e, stackTrace);
      throw Exception('URL加载失败: $e');
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

  void _setupPeriodicCheck() {
    if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
      final reason = _periodicCheckTimer != null ? '定时器已存在' : _isCancelled() ? '任务取消' : '已找到M3U8';
      LogUtil.i('跳过定期检查: $reason');
      return;
    }
    
    try {
      _prepareM3U8DetectorCode().then((detectorScript) {
        if (_m3u8Found || _isCancelled()) return;
        
        try {
          _periodicCheckTimer = Timer.periodic(const Duration(milliseconds: M3U8Constants.periodicCheckIntervalMs), (timer) async {
            try {
              if (_m3u8Found || _isCancelled()) {
                timer.cancel();
                _periodicCheckTimer = null;
                LogUtil.i('停止检查: ${_m3u8Found ? 'M3U8已找到' : '任务取消'}');
                return;
              }
              _checkCount++;
              LogUtil.i('第$_checkCount次检查');
              if (!_isControllerInitialized) {
                LogUtil.i('控制器未准备，跳过检查');
                return;
              }
              
              try {
                unawaited(_controller.runJavaScript('''
                try {
                  if (window._m3u8DetectorInitialized) {
                    if (window.checkMediaElements) checkMediaElements(document);
                    if (window.efficientDOMScan) efficientDOMScan();
                  } else {
                    console.warn('[Dart] M3U8检测器未初始化，重新注入');
                    $detectorScript
                    if (window.checkMediaElements) checkMediaElements(document);
                    if (window.efficientDOMScan) efficientDOMScan();
                  }
                } catch (jsError) {
                  console.error('[Dart] JavaScript检查异常:', jsError.message);
                }
                ''').catchError((jsError) {
                  LogUtil.e('JavaScript执行失败: $jsError');
                  // JavaScript执行失败不停止定期检查
                }));
              } catch (scriptError) {
                LogUtil.e('脚本执行异常: $scriptError');
                // 脚本执行异常不停止定期检查
              }
              
            } catch (timerError) {
              LogUtil.e('定期检查单次执行异常: $timerError');
            }
          });
          
          LogUtil.i('定期检查已启动 (间隔: ${M3U8Constants.periodicCheckIntervalMs}ms)');
        } catch (timerCreationError) {
          LogUtil.e('定期检查定时器创建异常: $timerCreationError');
        }
      }).catchError((prepareError) {
        LogUtil.e('定期检查脚本准备异常: $prepareError');
      });
    } catch (setupError) {
      LogUtil.e('定期检查设置异常: $setupError');
    }
  }

  // 启动超时计时
  void _startTimeout(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    
    // 如果已有超时定时器在运行，先取消
    _timeoutTimer?.cancel();
    
    LogUtil.i('超时计时启动: ${timeoutSeconds}s');
    
    _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      if (_isCancelled() || completer.isCompleted) {
        LogUtil.i('超时触发时任务已完成，跳过处理');
        return;
      }
      
      LogUtil.i('超时触发: ${timeoutSeconds}s，检查结果...');
      
      if (_foundUrls.length > 0 && !completer.isCompleted) {
        _m3u8Found = true;
        final selectedUrl = _foundUrls.toList().last;
        LogUtil.i('超时前发现URL: $selectedUrl');
        completer.complete(selectedUrl);
      } else if (_retryCount < M3U8Constants.maxRetryCount) {
        // 超时时如果还有重试次数，触发重试而不是返回错误
        LogUtil.i('超时但还有重试次数 ($_retryCount/${M3U8Constants.maxRetryCount})，触发重试');
        await _handleLoadError(completer);
        return; // 重要：不要调用dispose()，让重试逻辑处理
      } else if (!completer.isCompleted) {
        LogUtil.i('超时且无重试次数，返回错误');
        completer.complete('ERROR');
      }
      
      await dispose();
    });
  }

  // 释放资源
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _timeoutTimer?.cancel(); // 取消超时定时器
    _timeoutTimer = null;
    _periodicCheckTimer?.cancel(); // 取消定期检查定时器
    _periodicCheckTimer = null;
    _hashFirstLoadMap.remove(Uri.parse(url).toString()); // 清理Hash路由记录
    _foundUrls.clear(); // 清空URL集合
    _pageLoadedStatus.clear(); // 清空页面状态
    if (_isControllerInitialized) {
      bool isWhitelisted = _isWhitelisted(url);
      int cleanupDelay = isWhitelisted ? M3U8Constants.cleanupDelayMs : 0;
      Future.delayed(Duration(milliseconds: cleanupDelay), () async {
        if (!_isCancelled()) {
          await _disposeWebViewCompletely(_controller); // 延迟清理WebView
        } else {
          LogUtil.i('清理取消: 任务已终止');
        }
      });
    } else {
      LogUtil.i('控制器未初始化，跳过清理');
    }
    _resetControllerState(); // 重置控制器状态
    _httpResponseContent = null; // 清空HTTP响应
  }

  // 完全清理WebView
  Future<void> _disposeWebViewCompletely(WebViewController controller) async {
    try {
      final cleanupScript = await rootBundle.loadString('assets/js/cleanup_script.js');
      await controller.runJavaScript(cleanupScript)
          .catchError((e) => LogUtil.e('清理脚本执行失败: $e')); // 执行清理脚本
      await Future.delayed(Duration(milliseconds: M3U8Constants.webviewCleanupDelayMs));
      await controller.setNavigationDelegate(NavigationDelegate());
      await controller.loadRequest(Uri.parse('about:blank')); // 加载空白页
      await controller.clearCache(); // 清理缓存
      await controller.clearLocalStorage(); // 清理本地存储
      await controller.runJavaScript('window.location.href = "about:blank";');
      LogUtil.i('WebView资源已清理');
    } catch (e, stack) {
      LogUtil.logError('WebView清理失败', e, stack);
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
      LogUtil.i('记录URL: $finalUrl, 等待点击逻辑');
    }
  }

  // 获取M3U8 URL
  Future<String> getUrl() async {
    if (_isCancelled()) {
      LogUtil.i('任务取消，终止获取URL');
      return 'ERROR';
    }

    final dynamicKeywords = _parseKeywords(M3U8Constants.dynamicKeywords);
    for (final keyword in dynamicKeywords) {
      if (url.contains(keyword)) {
        try {
          final streamUrl = await GetM3u8Diy.getStreamUrl(url, cancelToken: cancelToken); // 调用自定义M3U8获取
          LogUtil.i('自定义M3U8获取: $streamUrl');
          return streamUrl;
        } catch (e, stackTrace) {
          LogUtil.logError('自定义M3U8获取失败', e, stackTrace);
          return 'ERROR';
        }
      }
    }

    // 只有在需要WebView检测时才启动超时计时
    final completer = Completer<String>();
    _startTimeout(completer);
    try {
      await _initController(completer, _filePattern); // 初始化控制器
    } catch (e, stackTrace) {
      LogUtil.logError('初始化失败', e, stackTrace);
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        await dispose();
      }
    }

    return completer.future;
  }

  // 检查页面内容
  Future<String?> _checkPageContent() async {
    if (_m3u8Found || _isCancelled()) {
      LogUtil.i('跳过内容检查: ${_m3u8Found ? '已找到M3U8' : '任务取消'}');
      return null;
    }
    if (clickText != null && !_isClickExecuted) {
      LogUtil.i('点击未完成，跳过内容检查');
      return null;
    }
    try {
      if (_httpResponseContent == null || _httpResponseContent!.isEmpty) {
        LogUtil.e('页面内容为空');
        return null;
      }
      String sample = UrlUtils.basicUrlClean(_httpResponseContent!); // 清理内容
      final matches = _m3u8Pattern.allMatches(sample); // 匹配M3U8
      LogUtil.i('匹配到${matches.length}个$_filePattern');
      return await _processMatches(matches, sample); // 处理匹配结果
    } catch (e, stackTrace) {
      LogUtil.logError('页面内容检查失败', e, stackTrace);
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
      LogUtil.i('目标URL: ${validUrls[clickIndex]} (index=$clickIndex)');
      return validUrls[clickIndex];
    } else {
      _m3u8Found = true;
      LogUtil.i('clickIndex=$clickIndex 超出范围，选用: ${validUrls[0]}');
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
      LogUtil.e('M3U8检测器脚本加载失败: $e');
      return '(function(){console.error("M3U8检测器加载失败");})();';
    }
  }
}
