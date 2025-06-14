import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/getm3u8_rules.dart';
import 'package:itvapp_live_tv/util/getm3u8diy.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 管理M3U8常量
class M3U8Constants {
  // 数值常量
  static const int defaultTimeoutSeconds = 18; // 解析超时（秒）
  static const int maxFoundUrlsSize = 50; // 已发现URL最大容量
  static const int maxPageLoadedStatusSize = 50; // 已加载页面状态最大容量
  static const int maxCacheSize = 50; // 通用缓存最大容量
  static const int maxRuleCacheSize = 20; // 规则缓存最大容量
  static const int maxRetryCount = 1; // 最大重试次数
  static const int clickDelayMs = 500; // 点击延迟（毫秒）
  static const int urlCheckDelayMs = 3000; // URL检查延迟（毫秒）
  static const int retryDelayMs = 500; // 重试延迟（毫秒）
  static const int contentSampleLength = 59888; // 内容采样长度
  static const int cleanupDelayMs = 3000; // 清理延迟（毫秒）
  static const int webviewCleanupDelayMs = 500; // WebView清理延迟（毫秒）
  static const int defaultSetSize = 50; // 默认集合容量

  // 规则配置 - 直接使用List格式
  static List<String> get rulePatterns => M3U8Rules.rulePatterns; // M3U8过滤规则
  static List<String> get specialRulePatterns => M3U8Rules.specialRulePatterns; // 特殊规则模式
  static List<String> get dynamicKeywords => M3U8Rules.dynamicKeywords; // 动态关键字
  static List<String> get whiteExtensions => M3U8Rules.whiteExtensions; // 白名单扩展名
  static List<String> get blockedExtensions => M3U8Rules.blockedExtensions; // 屏蔽扩展名
  static List<String> get invalidPatterns => M3U8Rules.invalidPatterns; // 无效模式（广告、跟踪）

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

  // 清理URL转义、HTML实体及多斜杠
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
  final String primaryKeyword; // 主关键字（可在输入URL或检测URL中）
  final String requiredKeyword; // 必需关键字（必须在检测URL中）

  const M3U8FilterRule({required this.primaryKeyword, required this.requiredKeyword});

  // 解析规则字符串
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length < 2) return M3U8FilterRule(primaryKeyword: parts[0].trim(), requiredKeyword: '');
    return M3U8FilterRule(primaryKeyword: parts[0].trim(), requiredKeyword: parts[1].trim());
  }
}

// 限制大小集合
class LimitedSizeSet<T> {
  final int maxSize; // 最大容量
  final Queue<T> _queue; // 保持插入顺序
  final HashSet<T> _set; // 快速查找

  LimitedSizeSet([this.maxSize = M3U8Constants.defaultSetSize]) 
      : _queue = Queue(),
        _set = HashSet();

  // 添加元素，超出容量移除最早元素
  bool add(T element) {
    if (_set.contains(element)) return false;
    
    if (_queue.length >= maxSize) {
      final oldest = _queue.removeFirst(); 
      _set.remove(oldest);
    }
    
    _queue.addLast(element);
    _set.add(element);
    return true;
  }

  bool contains(T element) => _set.contains(element); 
  int get length => _set.length; // 获取当前大小
  List<T> toList() => List.unmodifiable(_queue); // 转换为不可修改列表
  Set<T> toSet() => Set.unmodifiable(_set); // 转换为不可修改集合
  void clear() {
    _queue.clear();
    _set.clear();
  } // 清空集合
  void remove(T element) {
    _queue.remove(element);
    _set.remove(element);
  } // 移除指定元素
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

  // 静态编译的无效模式正则表达式
  static final RegExp _invalidPatternRegex = RegExp(
    M3U8Constants.invalidPatterns.join('|'),
    caseSensitive: false,
  );

  // 解析并缓存数据
  static T _parseCached<T>(
    List<String> input,
    String type,
    T Function(List<String>) parser,
    LRUCache<String, T> cache,
  ) {
    final cacheKey = '$type:${input.join(',')}';
    final cached = cache.get(cacheKey);
    if (cached != null) return cached;
    final result = parser(input);
    cache.put(cacheKey, result);
    return result;
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
  int _retryCount = 0; // 重试计数
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
  bool _validateUrl(String detectedUrl, String filePattern) {
    if (detectedUrl.isEmpty || _foundUrls.contains(detectedUrl)) return false;
    final lowerUrl = detectedUrl.toLowerCase();
    if (!lowerUrl.contains('.$filePattern')) return false;
    
    // 如果没有规则，默认通过
    if (_filterRules.isEmpty) return true;
    
    // 规则验证逻辑：
    // 1. 先检查输入URL触发的规则（输入URL包含主关键字的规则）
    // 2. 再检查检测URL自身的规则
    for (final rule in _filterRules) {
      // 如果输入URL包含主关键字
      if (url.contains(rule.primaryKeyword)) {
        // 检测URL必须包含必需关键字（如果有的话）
        return rule.requiredKeyword.isEmpty || detectedUrl.contains(rule.requiredKeyword);
      }
    }
    
    // 检查检测URL自身是否包含规则的主关键字
    for (final rule in _filterRules) {
      if (detectedUrl.contains(rule.primaryKeyword)) {
        // 如果包含主关键字，必须也包含必需关键字（如果有的话）
        return rule.requiredKeyword.isEmpty || detectedUrl.contains(rule.requiredKeyword);
      }
    }
    
    // 没有匹配任何规则的主关键字，默认通过
    return true;
  }

  GetM3U8({
    required this.url,
    this.timeoutSeconds = M3U8Constants.defaultTimeoutSeconds,
    this.cancelToken,
  }) : _filterRules = _parseCached(
          M3U8Constants.rulePatterns,
          'rules',
          (rules) => rules.map(M3U8FilterRule.fromString).toList(),
          _ruleCache,
        ),
        fromParam = _extractQueryParams(url)['from'],
        toParam = _extractQueryParams(url)['to'],
        clickText = _extractQueryParams(url)['clickText'],
        clickIndex = int.tryParse(_extractQueryParams(url)['clickIndex'] ?? '') ?? 0 {
    _controller = WebViewController();
    try {
      _parsedUri = Uri.parse(url); // 解析URL
      isHashRoute = _parsedUri.fragment.isNotEmpty; // 检查Hash路由
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

  // 确定文件模式
  String _determineFilePattern(String url) {
    String pattern = 'm3u8';
    final specialRules = _parseCached(
      M3U8Constants.specialRulePatterns,
      'special_rules',
      (rules) {
        final ruleMap = <String, String>{};
        for (final rule in rules) {
          final parts = rule.split('|');
          if (parts.length >= 2) ruleMap[parts[0].trim()] = parts[1].trim();
        }
        return ruleMap;
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
  static Set<String> _parseKeywords(List<String> keywordsList) {
    return _parseCached(
      keywordsList,
      'keywords',
      (keywords) => keywords.toSet(),
      _keywordsCache,
    );
  }

  // 检查URL是否在白名单
  bool _isWhitelisted(String url) {
    final whiteExtensions = M3U8Constants.whiteExtensions;
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

  // 准备点击处理器脚本
  Future<String> _prepareClickHandlerCode() async {
    if (clickText == null || clickText!.isEmpty) {
      return '(function(){console.log("无点击配置，跳过点击处理器初始化");})();';
    }
    
    final cacheKey = 'click_handler_${clickText}_${clickIndex}';
    final cachedScript = _scriptCache.get(cacheKey);
    if (cachedScript != null) return cachedScript;
    
    try {
      final baseScript = await rootBundle.loadString('assets/js/click_handler.js');
      final scriptWithParams = baseScript
          .replaceAll('const searchText = ""', 'const searchText = "$clickText"')
          .replaceAll('const targetIndex = 0', 'const targetIndex = $clickIndex');
      _scriptCache.put(cacheKey, scriptWithParams);
      return scriptWithParams;
    } catch (e) {
      LogUtil.e('点击处理器脚本加载失败: $e');
      return '(function(){console.error("点击处理器脚本加载失败");})();';
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
      
      // 如果有点击配置，直接使用WebView，跳过HTTP请求
      if (clickText != null && clickText!.isNotEmpty) {
        LogUtil.i('检测到点击配置，跳过HTTP请求，直接使用WebView');
        _isHtmlContent = true; // 假定需要WebView处理
        await _initializeWebViewController(completer);
        return;
      }
      
      // 没有点击配置时，尝试HTTP请求
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
      LogUtil.logError('WebView控制器初始化失败', e, stackTrace);
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
      _prepareClickHandlerCode(), // 点击处理器脚本
    ]);
    await _setupJavaScriptChannels(completer); // 设置JavaScript通道
    await _setupNavigationDelegate(completer, initScripts); // 设置导航代理
    await _loadUrlWithHeaders(); // 加载URL
  }

  // 触发点击检测
  void _triggerClickDetection() {
    if (_isCancelled() || _isClickExecuted || clickText == null || clickText!.isEmpty) {
      final reason = _isCancelled() ? '任务取消' : _isClickExecuted ? '点击已执行' : '无点击配置';
      LogUtil.i('跳过点击检测: $reason');
      return;
    }
    _isClickExecuted = true; // 标记点击已执行
  }

  // 处理JavaScript消息
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
          LogUtil.i('[JS检测-$source] 检测到URL: ${url ?? "无URL"}');
          _handleM3U8Found(url, completer, source: source); // 处理M3U8 URL，传递source
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
          LogUtil.i('点击器信息: $msg, 详情: ${json.encode(details)}');
          break;
      }
    } catch (e) {
      LogUtil.e('JSON消息解析异常: $e');
      if (channel == 'M3U8Detector') {
        if (message.contains('.$_filePattern')) {
          LogUtil.i('尝试直接处理URL消息: $message');
          _handleM3U8Found(message, completer, source: 'JS检测-解析失败'); // 添加source
        }
      } else if (channel == 'ClickHandler') {
        LogUtil.e('点击消息处理失败: $e, 消息: $message');
      } else {
        LogUtil.e('处理 $channel 消息失败: $e');
      }
    } catch (e) {
      LogUtil.e('JavaScript消息处理严重异常: $e, 通道: $channel');
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
    final whiteExtensions = M3U8Constants.whiteExtensions; // 白名单关键字
    final blockedExtensions = M3U8Constants.blockedExtensions; // 屏蔽扩展名
    final scriptNames = ['时间拦截器脚本', '初始化脚本', 'M3U8检测器脚本', '点击处理器脚本'];

    _controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (String url) async {
        if (_isCancelled()) {
          LogUtil.i('页面加载取消: $url');
          return;
        }
        
        try {
          await _controller.runJavaScript(initScripts[0]); // 注入时间拦截器脚本
          LogUtil.i('注入成功: ${scriptNames[0]}');
        } catch (e) {
          LogUtil.e('注入失败 (${scriptNames[0]}): $e');
        }
        
        for (int i = 1; i < initScripts.length; i++) {
          unawaited(_controller.runJavaScript(initScripts[i]).then((_) {
            LogUtil.i('注入成功: ${scriptNames[i]}');
          }).catchError((e) {
            LogUtil.e('注入失败 (${scriptNames[i]}): $e');
            return null;
          }));
        }


        if (clickText != null && !_isClickExecuted) {
          Timer(Duration(milliseconds: M3U8Constants.clickDelayMs), () {
            if (!_isCancelled()) {
              _triggerClickDetection();
            }
          });
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
          LogUtil.i('[Dart检测-导航拦截] 检测到URL: ${request.url}');
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
        if (isHashRoute && !_handleHashRoute(url)) return;
        
        if (clickText != null && _isClickExecuted) {
          _startUrlCheckTimer(completer);
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
      onSslAuthError: (SslAuthError error) async {
        LogUtil.w('SSL证书错误，忽略并继续访问');
        await error.proceed(); // 忽略SSL错误，继续访问
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
        LogUtil.i('未检测到URL');
      }
    });
  }

  // 处理加载错误
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_isCancelled() || completer.isCompleted) return;
    if (_retryCount < M3U8Constants.maxRetryCount) {
      _retryCount++;
      LogUtil.i('重试: $_retryCount/${M3U8Constants.maxRetryCount}, 延迟${M3U8Constants.retryDelayMs}ms');
      
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      
      await Future.delayed(const Duration(milliseconds: M3U8Constants.retryDelayMs));
      if (!_isCancelled() && !completer.isCompleted) {
        _pageLoadedStatus.clear();
        _isClickExecuted = false;
        LogUtil.i('重试使用检测策略: $_filePattern');
        
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
  }

  // 启动超时计时
  void _startTimeout(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    
    _timeoutTimer?.cancel();
    
    LogUtil.i('超时计时启动: ${timeoutSeconds}s');
    
    _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      if (_isCancelled() || completer.isCompleted) {
        LogUtil.i('超时触发时任务已完成，跳过处理');
        return;
      }
      
      LogUtil.i('超时触发: ${timeoutSeconds}s，检查结果');
      
      if (_foundUrls.length > 0 && !completer.isCompleted) {
        _m3u8Found = true;
        final selectedUrl = _foundUrls.toList().last;
        LogUtil.i('超时前检测到URL: $selectedUrl');
        completer.complete(selectedUrl);
      } else if (_retryCount < M3U8Constants.maxRetryCount) {
        LogUtil.i('超时但有重试次数 ($_retryCount/${M3U8Constants.maxRetryCount})，触发重试');
        await _handleLoadError(completer);
        return;
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

  // 清理WebView
  Future<void> _disposeWebViewCompletely(WebViewController controller) async {
    try {
      await Future.delayed(Duration(milliseconds: M3U8Constants.webviewCleanupDelayMs));
      await controller.setNavigationDelegate(NavigationDelegate());
      await controller.loadRequest(Uri.parse('about:blank'));
      await controller.clearCache(); // 清理缓存
      await controller.clearLocalStorage(); // 清理本地存储
      LogUtil.i('WebView资源已清理');
    } catch (e, stack) {
      LogUtil.logError('WebView清理失败', e, stack);
    }
  }

  // 处理M3U8 URL（修改：增加source参数）
  Future<void> _handleM3U8Found(String? url, Completer<String> completer, {String source = 'unknown'}) async {
    if (_m3u8Found || _isCancelled() || completer.isCompleted || url == null || url.isEmpty) return;
    String finalUrl = _processUrl(url); // 处理URL
    if (!_validateUrl(finalUrl, _filePattern)) return;
    _foundUrls.add(finalUrl);
    
    // 检查是否需要立即返回
    bool shouldReturnImmediately = false;
    
    // 检查规则匹配（简化后的逻辑）
    for (final rule in _filterRules) {
      // 如果输入URL或检测URL包含主关键字，且检测URL包含必需关键字
      if ((this.url.contains(rule.primaryKeyword) || finalUrl.contains(rule.primaryKeyword)) &&
          (rule.requiredKeyword.isEmpty || finalUrl.contains(rule.requiredKeyword))) {
        shouldReturnImmediately = true;
        LogUtil.i('URL完全匹配规则: ${rule.primaryKeyword} -> ${rule.requiredKeyword}');
        break;
      }
    }
    
    // 如果没有点击配置，或者完全匹配规则，立即返回
    if (clickText == null || shouldReturnImmediately) {
      _m3u8Found = true;
      LogUtil.i('[JS检测-$source] 检测到有效URL: $finalUrl${shouldReturnImmediately ? " (规则优先返回)" : ""}');
      completer.complete(finalUrl);
      await dispose();
    } else {
      LogUtil.i('[JS检测-$source] 记录URL: $finalUrl, 等待点击逻辑完成');
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
          LogUtil.i('[Dart检测-自定义处理] 获取到URL: $streamUrl');
          return streamUrl;
        } catch (e, stackTrace) {
          LogUtil.logError('自定义M3U8获取失败', e, stackTrace);
          return 'ERROR';
        }
      }
    }

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
      LogUtil.i('[Dart检测-HTTP响应] 匹配到${matches.length}个$_filePattern');
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
      LogUtil.i('[Dart检测-HTTP响应] 目标URL: ${validUrls[clickIndex]} (index=$clickIndex)');
      return validUrls[clickIndex];
    } else {
      _m3u8Found = true;
      LogUtil.i('[Dart检测-HTTP响应] clickIndex=$clickIndex 超出范围，选用: ${validUrls[0]}');
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
