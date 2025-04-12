import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/getm3u8diy.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// URL 处理工具类
class UrlUtils {
  static const String _protocolPatternStr = r'(?:https?)'; // 定义协议模式字符串
  static final RegExp _escapeRegex = RegExp(r'\\(\|/|")'); // 匹配转义字符
  static final RegExp _multiSlashRegex = RegExp(r'/{3,}'); // 匹配多余斜杠
  static final RegExp _htmlEntityRegex = RegExp(r'&(#?[a-z0-9]+);'); // 匹配HTML实体
  static final RegExp _unicodeRegex = RegExp(r'\u([0-9a-fA-F]{4})'); // 匹配Unicode编码
  static final RegExp _protocolRegex = RegExp('^${_protocolPatternStr}://'); // 匹配协议头

  static const Map<String, String> _htmlEntities = { // HTML实体映射表
    'amp': '&', 'quot': '"', '#x2F': '/', '#47': '/', 'lt': '<', 'gt': '>'
  };

  /// 清理URL，去除转义字符、多余斜杠、HTML实体等
  static String basicUrlClean(String url) {
    if (url.isEmpty) return url; // 空URL直接返回
    if (url.endsWith(r'\')) url = url.substring(0, url.length - 1); // 移除末尾反斜杠
    
    String result = url
        .replaceAllMapped(_escapeRegex, (match) => match.group(1)!) // 移除转义符号
        .replaceAll(r'\/', '/') // 替换反斜杠斜杠为单斜杠
        .replaceAllMapped(_htmlEntityRegex, (m) => _htmlEntities[m.group(1)] ?? m.group(0)!) // 转换HTML实体
        .replaceAll(_multiSlashRegex, '/') // 合并多斜杠为单斜杠
        .trim(); // 去除首尾空格
    
    if (result.contains(r'\u')) { // 处理Unicode编码
      result = result.replaceAllMapped(_unicodeRegex, (match) => _parseUnicode(match.group(1)));
    }
    
    if (result.contains('%')) { // 处理URL编码
      try {
        result = Uri.decodeComponent(result);
      } catch (e) {
      }
    }
    
    return result;
  }

  /// 将Unicode十六进制转换为字符
  static String _parseUnicode(String? hex) {
    if (hex == null) return ''; // 空值返回空字符串
    try {
      return String.fromCharCode(int.parse(hex, radix: 16)); // 转换为字符
    } catch (e) {
      return hex; // 解析失败返回原值
    }
  }

  /// 构建完整URL，补全协议和域名
  static String buildFullUrl(String path, Uri baseUri) {
    if (_protocolRegex.hasMatch(path)) return path; // 已含协议直接返回
    if (path.startsWith('//')) return '${baseUri.scheme}://${path.replaceFirst('//', '')}'; // 补全协议
    String cleanPath = path.startsWith('/') ? path.substring(1) : path; // 清理首斜杠
    return '${baseUri.scheme}://${baseUri.host}/$cleanPath'; // 拼接完整URL
  }

  /// 检查URL是否包含有效协议
  static bool hasValidProtocol(String url) {
    return _protocolRegex.hasMatch(url); // 返回是否匹配协议正则
  }
}

/// M3U8过滤规则配置
class M3U8FilterRule {
  final String domain; // 域名
  final String requiredKeyword; // 必需关键词

  const M3U8FilterRule({required this.domain, required this.requiredKeyword});

  /// 从字符串解析规则
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|'); // 以|分割规则
    if (parts.length < 2) return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: ''); // 缺关键词时为空
    return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: parts[1].trim()); // 解析域名和关键词
  }
}

/// 限制大小的集合类，用于优化内存管理
class LimitedSizeSet<T> {
  // 定义默认最大容量常量
  static const int DEFAULT_MAX_SIZE = 50;

  final int maxSize; // 最大容量
  final Set<T> _internalSet = {}; // 内部集合存储元素
  final List<T> _insertionOrder = []; // 记录插入顺序
  
  LimitedSizeSet([this.maxSize = DEFAULT_MAX_SIZE]); // 修改：使用常量作为默认值
  
  /// 添加元素，超出容量时移除最早元素
  bool add(T element) {
    if (_internalSet.contains(element)) return false; // 已存在则不添加
    if (_internalSet.length >= maxSize) { // 超出容量
      final oldest = _insertionOrder.removeAt(0); // 移除最早元素
      _internalSet.remove(oldest);
    }
    _internalSet.add(element);
    _insertionOrder.add(element);
    return true;
  }
  
  bool contains(T element) => _internalSet.contains(element); // 检查元素是否存在
  int get length => _internalSet.length; // 获取当前元素数量
  List<T> toList() => List<T>.from(_insertionOrder); // 转换为列表
  Set<T> toSet() => Set<T>.from(_internalSet); // 转换为集合
  void clear() { _internalSet.clear(); _insertionOrder.clear(); } // 清空集合
  void remove(T element) { // 移除指定元素
    if (_internalSet.remove(element)) _insertionOrder.remove(element);
  }
}

/// M3U8地址获取类
class GetM3U8 {
  // 修改：添加常量定义
  static const int DEFAULT_TIMEOUT_SECONDS = 15; // 默认超时时间（秒）
  static const int MAX_FOUND_URLS_SIZE = 50; // 已发现URL集合的最大容量
  static const int MAX_PAGE_LOADED_STATUS_SIZE = 50; // 页面加载状态集合的最大容量
  static const int MAX_CACHE_SIZE = 50; // 通用缓存最大容量（脚本、正则等）
  static const int MAX_RULE_CACHE_SIZE = 20; // 规则缓存最大容量
  static const int MAX_RETRY_COUNT = 2; // 最大重试次数
  static const int PERIODIC_CHECK_INTERVAL_MS = 1000; // 定期检查间隔（毫秒）
  static const int CLICK_DELAY_MS = 500; // 点击操作延迟（毫秒）
  static const int URL_CHECK_DELAY_MS = 2500; // URL点击延迟（毫秒）
  static const int RETRY_DELAY_MS = 500; // 重试延迟（毫秒）
  static const int CONTENT_SAMPLE_LENGTH = 38888; // 内容采样长度
  static const int WEBVIEW_CLEANUP_DELAY_MS = 300; // WebView清理延迟（毫秒）

  static final Map<String, String> _scriptCache = {}; // 脚本缓存
  static final Map<String, List<M3U8FilterRule>> _ruleCache = {}; // 规则缓存
  static final Map<String, Set<String>> _keywordsCache = {}; // 关键词缓存
  static final Map<String, Map<String, String>> _specialRulesCache = {}; // 特殊规则缓存
  static final Map<String, RegExp> _patternCache = {}; // 正则缓存

  /// 限制Map大小，移除最早项
  static void _limitMapSize<K, V>(Map<K, V> map, int maxSize, K key, V value) {
    if (map.length >= maxSize) map.remove(map.keys.first); // 超出时移除首项
    map[key] = value; // 添加新项
  }

  static final RegExp _invalidPatternRegex = RegExp( // 无效URL模式正则
    'advertisement|analytics|tracker|pixel|beacon|stats|log',
    caseSensitive: false,
  );

  // 过滤规则字符串
  static String rulesString = 'ptbtv.com|hd/live@setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook=';
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4'; // 特殊规则字符串
  static String dynamicKeywordsString = 'jinan@gansu@xizang@sichuan'; // 使用getm3u8diy解析的关键词
  static const String allowedResourcePatternsString = 'r.png?t='; // 允许资源模式字符串

  // 阻止加载的黑名单关键字（扩展名带点号，避免误判）
  static final List<String> _blockedExtensions = [
    '.jpg', '.jpeg', '.gif', '.webp', '.css', '.woff', '.woff2', '.ttf', '.eot',
    '.ico', '.svg', '.mp3', '.wav', '.pdf', '.doc', '.docx', '.swf',
  ];

  final String url; // 目标URL
  final String? fromParam; // 替换参数from
  final String? toParam; // 替换参数to
  final String? clickText; // 点击文本
  final int clickIndex; // 点击索引
  final int timeoutSeconds; // 超时时间（秒）
  late WebViewController _controller; // WebView控制器
  bool _m3u8Found = false; // 是否找到M3U8
  final LimitedSizeSet<String> _foundUrls = LimitedSizeSet<String>(MAX_FOUND_URLS_SIZE); // 修改：使用常量
  Timer? _periodicCheckTimer; // 定期检查定时器
  int _retryCount = 0; // 重试次数
  int _checkCount = 0; // 检查次数
  final List<M3U8FilterRule> _filterRules; // 过滤规则列表
  bool _isClickExecuted = false; // 是否已执行点击
  bool _isControllerInitialized = false; // 控制器是否初始化
  String _filePattern = 'm3u8'; // 文件模式
  RegExp get _m3u8Pattern => _getOrCreatePattern(_filePattern); // 获取M3U8正则
  static final Map<String, int> _hashFirstLoadMap = {}; // Hash路由加载记录
  bool isHashRoute = false; // 是否为Hash路由
  bool _isHtmlContent = false; // 是否为HTML内容
  String? _httpResponseContent; // HTTP响应内容
  static int? _cachedTimeOffset; // 时间偏移缓存
  final LimitedSizeSet<String> _pageLoadedStatus = LimitedSizeSet<String>(MAX_PAGE_LOADED_STATUS_SIZE); // 修改：使用常量
  static const List<Map<String, String>> TIME_APIS = [ // 时间API列表
    {'name': 'Aliyun API', 'url': 'https://acs.m.taobao.com/gw/mtop.common.getTimestamp/'},
    {'name': 'Suning API', 'url': 'https://quan.suning.com/getSysTime.do'},
    {'name': 'WorldTime API', 'url': 'https://worldtimeapi.org/api/timezone/Asia/Shanghai'},
    {'name': 'Meituan API', 'url': 'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime'},
  ];
  late final Uri _parsedUri; // 解析后的URI
  final CancelToken? cancelToken; // 取消令牌
  bool _isDisposed = false; // 是否已释放
  Timer? _timeoutTimer; // 超时定时器

  /// 构造函数，初始化URL和参数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = DEFAULT_TIMEOUT_SECONDS, // 修改：使用常量
    this.cancelToken,
  }) : _filterRules = _parseRules(rulesString),
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
      _parsedUri = Uri(scheme: 'https', host: 'invalid.host'); // 解析失败时的默认值
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

  /// 根据URL确定文件模式
  String _determineFilePattern(String url) {
    String pattern = 'm3u8'; // 默认模式
    final specialRules = _parseSpecialRules(specialRulesString);
    for (final entry in specialRules.entries) {
      if (url.contains(entry.key)) { // 匹配特殊规则
        pattern = entry.value;
        LogUtil.i('检测到特殊模式: $pattern 用于URL: $url');
        break;
      }
    }
    return pattern;
  }

  /// 获取或创建文件模式正则
  RegExp _getOrCreatePattern(String filePattern) {
    final cacheKey = 'pattern_$filePattern';
    if (_patternCache.containsKey(cacheKey)) return _patternCache[cacheKey]!;
    
    final pattern = RegExp( // 创建正则表达式
      "(?:https?://|//|/)[^'\"\\s,()<>{}\\[\\]]*?\\.${filePattern}[^'\"\\s,()<>{}\\[\\]]*",
      caseSensitive: false,
    );
    
    _limitMapSize(_patternCache, MAX_CACHE_SIZE, cacheKey, pattern); // 修改：使用常量
    return pattern;
  }

  /// 提取URL查询参数
  static Map<String, String> _extractQueryParams(String url) {
    try {
      final uri = Uri.parse(url);
      Map<String, String> params = Map.from(uri.queryParameters); // 获取查询参数
      if (uri.fragment.isNotEmpty) { // 处理Hash参数
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

  /// 解析过滤规则
  static List<M3U8FilterRule> _parseRules(String rulesString) {
    if (rulesString.isEmpty) return []; // 空字符串返回空列表
    if (_ruleCache.containsKey(rulesString)) return _ruleCache[rulesString]!;
    
    final rules = rulesString.split('@') // 分割规则
        .where((rule) => rule.isNotEmpty)
        .map(M3U8FilterRule.fromString)
        .toList();
    
    _limitMapSize(_ruleCache, MAX_RULE_CACHE_SIZE, rulesString, rules); // 修改：使用常量
    return rules;
  }

  /// 解析动态关键词
  static Set<String> _parseKeywords(String keywordsString) {
    if (keywordsString.isEmpty) return {}; // 空字符串返回空集合
    if (_keywordsCache.containsKey(keywordsString)) return _keywordsCache[keywordsString]!;
    
    final keywords = keywordsString.split('@') // 分割关键词
        .map((keyword) => keyword.trim())
        .toSet();
    
    _limitMapSize(_keywordsCache, MAX_RULE_CACHE_SIZE, keywordsString, keywords); // 修改：使用常量
    return keywords;
  }

  /// 解析特殊规则
  static Map<String, String> _parseSpecialRules(String rulesString) {
    if (rulesString.isEmpty) return {}; // 空字符串返回空映射
    if (_specialRulesCache.containsKey(rulesString)) return _specialRulesCache[rulesString]!;
    
    final Map<String, String> rules = {};
    for (final rule in rulesString.split('@')) { // 分割规则
      final parts = rule.split('|');
      if (parts.length >= 2) rules[parts[0].trim()] = parts[1].trim(); // 解析键值对
    }
    
    _limitMapSize(_specialRulesCache, MAX_RULE_CACHE_SIZE, rulesString, rules); // 修改：使用常量
    return rules;
  }

  /// 解析允许的资源模式
  static List<String> _parseAllowedPatterns(String patternsString) {
    if (patternsString.isEmpty) return []; // 空字符串返回空列表
    try {
      return patternsString.split('@').map((pattern) => pattern.trim()).toList(); // 分割并清理
    } catch (e) {
      LogUtil.e('解析允许的资源模式失败: $e');
      return [];
    }
  }

  /// 清理并补全URL
  String _cleanUrl(String url) {
    String cleanedUrl = UrlUtils.basicUrlClean(url); // 基本清理
    return UrlUtils.hasValidProtocol(cleanedUrl) ? cleanedUrl : UrlUtils.buildFullUrl(cleanedUrl, _parsedUri); // 补全协议
  }

  /// 获取时间偏移
  Future<int> _getTimeOffset() async {
    if (_cachedTimeOffset != null) return _cachedTimeOffset!;
    
    final localTime = DateTime.now();
    for (final api in TIME_APIS) { // 遍历时间API
      try {
        final networkTime = await _getNetworkTime(api['url']!);
        if (networkTime != null) {
          _cachedTimeOffset = networkTime.difference(localTime).inMilliseconds; // 计算偏移
          return _cachedTimeOffset!;
        }
      } catch (e) {
        LogUtil.e('获取时间源失败 (${api['name']}): $e');
      }
    }
    return 0; // 无有效时间返回0
  }

  /// 从网络获取时间
  Future<DateTime?> _getNetworkTime(String url) async {
    if (_isCancelled()) return null; // 已取消则返回空
    final response = await HttpUtil().getRequest<String>(url, retryCount: 1, cancelToken: cancelToken);
    if (response == null || _isCancelled()) return null; // 无响应或已取消返回空
    try {
      final Map<String, dynamic> data = json.decode(response);
      if (url.contains('taobao')) return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?['t'] ?? '0')); // 淘宝API
      else if (url.contains('suning')) return DateTime.parse(data['sysTime2'] ?? ''); // 苏宁API
      else if (url.contains('worldtimeapi')) return DateTime.parse(data['datetime'] ?? ''); // 世界时间API
      else if (url.contains('meituan')) return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?.toString() ?? '0')); // 美团API
    } catch (e) {
      LogUtil.e('解析时间响应失败: $e');
    }
    return null; // 解析失败返回空
  }

  /// 准备时间拦截器代码
  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) return '(function(){})();'; // 无偏移返回空函数
    final cacheKey = 'time_interceptor_${_cachedTimeOffset}';
    if (_scriptCache.containsKey(cacheKey)) return _scriptCache[cacheKey]!;
    
    try {
      final script = await rootBundle.loadString('assets/js/time_interceptor.js'); // 加载脚本
      final result = script.replaceAll('TIME_OFFSET', '$_cachedTimeOffset'); // 替换偏移值
      _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, result); // 修改：使用常量
      return result;
    } catch (e) {
      LogUtil.e('加载时间拦截器脚本失败: $e');
      return '(function(){})();'; // 加载失败返回空函数
    }
  }

  /// 检查任务是否已取消
  bool _isCancelled() => _isDisposed || (cancelToken?.isCancelled ?? false);

  /// 初始化WebView控制器
  Future<void> _initController(Completer<String> completer, String filePattern) async {
    if (_isCancelled()) { // 已取消则完成并返回错误
      LogUtil.i('初始化控制器前任务被取消');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    
    try {
      _isControllerInitialized = true;
      
      final httpResult = await _tryHttpRequest(); // 尝试HTTP请求
      if (_isCancelled()) {
        LogUtil.i('HTTP 请求完成后任务被取消');
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
      
      if (httpResult == true) { // HTTP请求成功
        final result = await _checkPageContent(); // 检查页面内容
        if (result != null) {
          if (!completer.isCompleted) completer.complete(result); // 完成并返回结果
          return;
        }
        if (!_isHtmlContent) { // 非HTML内容
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

  /// 尝试通过HTTP请求获取内容
  Future<bool> _tryHttpRequest() async {
    try {
      final httpdata = await HttpUtil().getRequest(url, cancelToken: cancelToken);
      if (_isCancelled()) return false; // 已取消返回false
      
      if (httpdata != null) { // 有响应数据
        _httpResponseContent = httpdata.toString();
        _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || _httpResponseContent!.contains('<html'); // 判断是否HTML
        
        if (_isHtmlContent) { // HTML内容
          String content = _httpResponseContent!;
          int styleEndIndex = -1;
          final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
          if (styleEndMatch != null) styleEndIndex = styleEndMatch.end; // 找到</style>位置
          
          String initialContent = styleEndIndex > 0
              ? content.substring(styleEndIndex, (styleEndIndex + CONTENT_SAMPLE_LENGTH).clamp(0, content.length)) // 修改：使用常量
              : content.length > CONTENT_SAMPLE_LENGTH ? content.substring(0, CONTENT_SAMPLE_LENGTH) : content; // 修改：使用常量
          
          return initialContent.contains('.' + _filePattern); // 检查是否包含文件模式
        }
        return true; // 非HTML返回true
      } else {
        LogUtil.e('HttpUtil请求失败，未获取到数据，将继续尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true;
        return false;
      }
    } catch (e) {
      if (_isCancelled()) return false;
      LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
      _httpResponseContent = null;
      _isHtmlContent = true;
      return false;
    }
  }

  /// 初始化WebView控制器
  Future<void> _initializeWebViewController(Completer<String> completer) async {
    if (_isCancelled()) return; // 已取消则返回
    
    if (!isHashRoute && !_isHtmlContent) { // 非Hash路由且非HTML
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
    
    _controller = WebViewController() // 配置WebView
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JS
      ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
    
    final List<String> initScripts = await _prepareInitScripts(); // 准备初始化脚本
    
    _setupJavaScriptChannels(completer); // 设置JS通道
    _setupNavigationDelegate(completer, initScripts); // 设置导航代理
    
    await _loadUrlWithHeaders(); // 加载URL
    LogUtil.i('WebViewController初始化完成');
  }

  /// 准备初始化脚本
  Future<List<String>> _prepareInitScripts() async {
    final List<String> scripts = [];
    scripts.add(await _prepareTimeInterceptorCode()); // 添加时间拦截器
    scripts.add(''' // 初始化全局变量
window._videoInit = false;
window._processedUrls = new Set();
window._m3u8Found = false;
''');
    scripts.add(await _prepareM3U8DetectorCode()); // 添加M3U8检测器
    return scripts;
  }

  /// 设置JavaScript通道
  void _setupJavaScriptChannels(Completer<String> completer) {
    _controller.addJavaScriptChannel('TimeCheck', onMessageReceived: (message) { // 时间检查通道
      if (_isCancelled()) return;
      try {
        final data = json.decode(message.message);
        if (data['type'] == 'timeRequest') {
          final now = DateTime.now().add(Duration(milliseconds: _cachedTimeOffset ?? 0));
          LogUtil.i('检测到时间请求: ${data['method']}，返回时间：$now');
        }
      } catch (e) {
        LogUtil.e('处理时间检查消息失败: $e');
      }
    });
    
    _controller.addJavaScriptChannel('M3U8Detector', onMessageReceived: (message) { // M3U8检测通道
      if (_isCancelled()) return;
      try {
        final data = json.decode(message.message);
        _handleM3U8Found(data['type'] == 'init' ? null : (data['url'] ?? message.message), completer);
      } catch (e) {
        _handleM3U8Found(message.message, completer);
      }
    });
  }

  /// 设置导航代理
  void _setupNavigationDelegate(Completer<String> completer, List<String> initScripts) {
    final allowedPatterns = _parseAllowedPatterns(allowedResourcePatternsString); // 允许的资源模式
    final scriptNames = ['时间拦截器脚本 (time_interceptor.js)', '自动点击脚本脚本 (click_handler.js)', 'M3U8检测器脚本 (m3u8_detector.js)'];
    
    // 新增：用于记录加载的资源 URL
    final LimitedSizeSet<String> loadedResources = LimitedSizeSet<String>(MAX_FOUND_URLS_SIZE);

    _controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (String url) async { // 页面开始加载
        if (_isCancelled()) {
          LogUtil.i('页面开始加载时任务被取消: $url');
          return;
        }
        // 记录初始 URL
        if (!loadedResources.contains(url)) {
          loadedResources.add(url);
          LogUtil.i('初始页面开始加载: $url');
        }
        for (int i = 0; i < initScripts.length; i++) { // 注入初始化脚本
          try {
            await _controller.runJavaScript(initScripts[i]);
            LogUtil.i('注入脚本成功: ${scriptNames[i]}');
          } catch (e) {
            LogUtil.e('注入脚本失败 (${scriptNames[i]}): $e');
          }
        }
      },
      onNavigationRequest: (NavigationRequest request) async { // 导航请求
        if (_isCancelled()) return NavigationDecision.prevent; // 已取消阻止导航
        
        // 记录每个请求的 URL
        final requestUrl = request.url;
        if (!loadedResources.contains(requestUrl)) {
          loadedResources.add(requestUrl);
          LogUtil.i('加载资源: $requestUrl');
        }

        // 检查并阻止广告/跟踪请求
        final urlLower = request.url.toLowerCase();
        final adTrackingPattern = RegExp(r'advertisement|analytics|tracker|pixel|beacon|stats|log', caseSensitive: false);
        if (adTrackingPattern.hasMatch(urlLower)) {
          LogUtil.i('阻止广告/跟踪请求: ${request.url}');
          return NavigationDecision.prevent;
        }
        
        try { // 处理重定向
          final currentUri = _parsedUri;
          final newUri = Uri.parse(request.url);
          if (currentUri.host != newUri.host) {
            for (int i = 0; i < initScripts.length; i++) {
              try {
                await _controller.runJavaScript(initScripts[i]);
                LogUtil.i('重定向页面注入脚本成功: ${scriptNames[i]}');
              } catch (e) {
                LogUtil.e('重定向页面注入脚本失败 (${scriptNames[i]}): $e');
              }
            }
            LogUtil.i('重定向页面的拦截器代码已重新注入');
          }
        } catch (e) {
          LogUtil.e('检查重定向URL失败: $e');
        }
        
        LogUtil.i('页面导航请求: ${request.url}');
        Uri? uri;
        try {
          uri = Uri.parse(request.url);
        } catch (e) {
          LogUtil.i('无效的URL，阻止加载: ${request.url}');
          return NavigationDecision.prevent;
        }
        
        try {
          // 1. 首先检查是否匹配允许模式（白名单）
          final fullUrl = request.url.toLowerCase();
          if (allowedPatterns.any((pattern) => fullUrl.contains(pattern.toLowerCase()))) {
            LogUtil.i('允许加载匹配模式的资源: ${request.url}');
            return NavigationDecision.navigate;
          }
          
          // 2. 检查是否包含黑名单扩展名
          for (final ext in _blockedExtensions) {
            if (fullUrl.contains(ext)) {
              LogUtil.i('阻止加载资源: ${request.url} (包含扩展名: $ext)');
              return NavigationDecision.prevent;
            }
          }
        } catch (e) {
          // 出错时默认允许
          LogUtil.e('URL检查失败: $e，默认允许加载');
        }
        
        try { // 检查M3U8文件
          if (uri.path.toLowerCase().contains('.' + _filePattern.toLowerCase())) {
            await _controller.runJavaScript(
              'window.M3U8Detector?.postMessage(${json.encode({'type': 'url', 'url': request.url, 'source': 'navigation'})});'
            ).catchError((e) => LogUtil.e('发送M3U8URL到检测器失败: $e'));
            return NavigationDecision.prevent;
          }
        } catch (e) {
          LogUtil.e('URL检查失败: $e');
        }
        
        return NavigationDecision.navigate; // 默认允许导航
      },
      onPageFinished: (String url) async { // 页面加载完成
        if (_isCancelled()) {
          LogUtil.i('页面加载完成时任务被取消: $url');
          return;
        }
        
        if (!isHashRoute && _pageLoadedStatus.contains(url)) {
          LogUtil.i('本页面已经加载完成，跳过重复处理');
          return;
        }
        
        _pageLoadedStatus.add(url);
        LogUtil.i('页面加载完成: $url');
        
        if (_isClickExecuted) {
          LogUtil.i('点击已执行，跳过处理');
          return;
        }
        
        if (isHashRoute && !_handleHashRoute(url)) return; // 处理Hash路由
        
        if (!_isClickExecuted && clickText != null) { // 执行点击
          await Future.delayed(const Duration(milliseconds: CLICK_DELAY_MS)); // 修改：使用常量
          if (!_isCancelled()) {
            final clickResult = await _executeClick();
            if (clickResult) _startUrlCheckTimer(completer); // 启动URL检查
          }
        }
        
        if (!_isCancelled() && !_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
          _setupPeriodicCheck(); // 设置定期检查
        }
      },
      onWebResourceError: (WebResourceError error) async { // 资源加载错误
        if (_isCancelled()) {
          LogUtil.i('资源错误时任务被取消: ${error.description}');
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

  /// 处理Hash路由逻辑
  bool _handleHashRoute(String url) {
    try {
      final currentUri = _parsedUri;
      String mapKey = currentUri.toString();
      _pageLoadedStatus.clear();
      _pageLoadedStatus.add(mapKey);
      
      int currentTriggers = _hashFirstLoadMap[mapKey] ?? 0;
      currentTriggers++;
      
      if (currentTriggers > MAX_RETRY_COUNT) { // 修改：使用常量
        LogUtil.i('hash路由触发超过$MAX_RETRY_COUNT次，跳过处理');
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

  /// 执行点击操作
  Future<bool> _executeClick() async {
    if (!_isControllerReady() || _isClickExecuted || clickText == null || clickText!.isEmpty) {
      final reason = !_isControllerReady() ? 'WebViewController 未初始化' : _isClickExecuted ? '点击已执行' : '无点击配置';
      LogUtil.i('$reason，跳过点击操作');
      return false;
    }
    
    LogUtil.i('开始执行点击操作，文本: $clickText, 索引: $clickIndex');
    try {
      final cacheKey = 'click_handler_${clickText}_${clickIndex}';
      String scriptWithParams = _scriptCache[cacheKey] ?? (await rootBundle.loadString('assets/js/click_handler.js'))
          .replaceAll('SEARCH_TEXT', clickText!)
          .replaceAll('TARGET_INDEX', '$clickIndex'); // 加载并替换参数
      
      await _controller.runJavaScript(scriptWithParams); // 执行点击脚本
      _isClickExecuted = true;
      LogUtil.i('点击操作执行完成，结果: 成功');
      _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, scriptWithParams); // 修改：使用常量
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _isClickExecuted = true;
      return true;
    }
  }

  /// 启动URL检查定时器
  void _startUrlCheckTimer(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    
    Timer(const Duration(milliseconds: URL_CHECK_DELAY_MS), () async { // 修改：使用常量
      if (_isCancelled() || completer.isCompleted) return;
      
      if (_foundUrls.length > 0) { // 有发现的URL
        _m3u8Found = true;
        final urlsList = _foundUrls.toList();
        String selectedUrl = (clickIndex == 0 || clickIndex >= urlsList.length) ? urlsList.last : urlsList[clickIndex];
        LogUtil.i('使用${clickIndex == 0 ? "最后" : "指定索引($clickIndex)"}发现的URL: $selectedUrl');
        
        if (!completer.isCompleted) completer.complete(selectedUrl); // 完成任务
        await dispose(); // 释放资源
      } else {
        LogUtil.i('未发现任何URL');
      }
    });
  }

  /// 处理加载错误并重试
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_isCancelled() || completer.isCompleted) return;
    
    if (_retryCount < MAX_RETRY_COUNT) { // 修改：使用常量
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/$MAX_RETRY_COUNT)，延迟$RETRY_DELAY_MS毫秒'); // 修改：使用常量
      await Future.delayed(const Duration(milliseconds: RETRY_DELAY_MS)); // 修改：使用常量
      
      if (!_isCancelled() && !completer.isCompleted) {
        _pageLoadedStatus.clear();
        _isClickExecuted = false;
        await _initController(completer, _filePattern); // 重试初始化
      }
    } else if (!completer.isCompleted) { // 达到最大重试次数
      LogUtil.e('达到最大重试次数或任务已取消');
      completer.complete('ERROR');
      await dispose();
    }
  }

  /// 使用自定义头加载URL
  Future<void> _loadUrlWithHeaders() async {
    if (!_isControllerReady()) {
      LogUtil.e('WebViewController 未初始化，无法加载URL');
      return;
    }
    
    try {
      final headers = HeadersConfig.generateHeaders(url: url); // 生成请求头
      await _controller.loadRequest(_parsedUri, headers: headers); // 加载URL
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      throw Exception('URL 加载失败: $e');
    }
  }

  /// 检查控制器是否准备就绪
  bool _isControllerReady() => _isControllerInitialized && !_isCancelled();

  /// 重置控制器状态
  void _resetControllerState() {
    _isControllerInitialized = false;
    _isClickExecuted = false;
    _m3u8Found = false;
    _retryCount = 0;
    _checkCount = 0;
  }

  /// 设置定期检查
  void _setupPeriodicCheck() {
    if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
      final reason = _periodicCheckTimer != null ? "定时器已存在" : _isCancelled() ? "任务被取消" : "已找到M3U8";
      LogUtil.i('跳过定期检查设置: $reason');
      return;
    }
    
    _periodicCheckTimer = Timer.periodic(const Duration(milliseconds: PERIODIC_CHECK_INTERVAL_MS), (timer) async { // 修改：使用常量
      if (_m3u8Found || _isCancelled()) {
        timer.cancel();
        _periodicCheckTimer = null;
        LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "任务被取消"}');
        return;
      }
      
      _checkCount++;
      LogUtil.i('执行第$_checkCount次定期检查');
      
      if (!_isControllerReady()) {
        LogUtil.i('WebViewController未准备好，跳过本次检查');
        return;
      }
      
      try {
        final detectorScript = await _prepareM3U8DetectorCode();
        await _controller.runJavaScript(''' // 执行DOM扫描
if (window._m3u8DetectorInitialized) {
  checkMediaElements(document);
  efficientDOMScan();
} else {
  $detectorScript
  checkMediaElements(document);
  efficientDOMScan();
}
''').catchError((error) => LogUtil.e('执行扫描失败: $error'));
      } catch (e, stack) {
        LogUtil.logError('定期检查执行出错', e, stack);
      }
    });
  }

  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      if (_isCancelled() || completer.isCompleted) return;
      
      if (_foundUrls.length > 0 && !completer.isCompleted) { // 超时前有URL
        _m3u8Found = true;
        final selectedUrl = _foundUrls.toList().last;
        LogUtil.i('超时前发现URL: $selectedUrl');
        completer.complete(selectedUrl);
      } else if (!completer.isCompleted) completer.complete('ERROR'); // 无URL返回错误
      
      await dispose(); // 释放资源
    });
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_isDisposed) return; // 已释放则返回
    
    _isDisposed = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    
    if (cancelToken != null && !cancelToken!.isCancelled) { // 取消HTTP请求
      cancelToken!.cancel('GetM3U8 disposed');
    }
    
    _hashFirstLoadMap.remove(Uri.parse(url).toString());
    _foundUrls.clear();
    _pageLoadedStatus.clear();
    
    if (_isControllerInitialized) await _disposeWebViewCompletely(_controller); // 清理WebView
    else LogUtil.i('WebViewController 未初始化，跳过清理');
    
    _resetControllerState();
    _httpResponseContent = null;
    _suggestGarbageCollection(); // 建议垃圾回收
    
    LogUtil.i('资源释放完成: ${DateTime.now()}');
  }

  /// 建议垃圾回收
  void _suggestGarbageCollection() {
    try {
      Future.delayed(Duration.zero, () {});
    } catch (e) {
      // 忽略异常
    }
  }

  /// 完全清理WebView资源
  Future<void> _disposeWebViewCompletely(WebViewController controller) async {
    try {
      await controller.setNavigationDelegate(NavigationDelegate()); // 重置导航代理
      await controller.loadRequest(Uri.parse('about:blank')); // 加载空白页
      await Future.delayed(Duration(milliseconds: WEBVIEW_CLEANUP_DELAY_MS)); // 修改：使用常量
      await controller.clearCache(); // 清理缓存
      
      if (_isHtmlContent) { // 清理JS行为
        await controller.runJavaScript(''' // 停止并清理页面
window.stop();
document.documentElement.innerHTML = '';
window.onload = null;
window.onerror = null;
(function() {
  var ids = Object.keys(window).filter(k => typeof window[k] === 'number' && window[k] > 0);
  ids.forEach(id => { clearTimeout(id); clearInterval(id); });
})();
window.removeEventListener('load', null, true);
window.removeEventListener('unload', null, true);
''').catchError((e) => LogUtil.e('清理JS行为失败: $e'));
      }
      
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.runJavaScript('window.location.href = "about:blank";'); // 重置页面
      LogUtil.i('已清理缓存和本地存储，并重置页面');
    } catch (e, stack) {
      LogUtil.logError('清理 WebView 时发生错误', e, stack);
    }
  }

  /// 检查M3U8 URL是否有效
  bool _isValidM3U8Url(String url) {
    if (url.isEmpty || _foundUrls.contains(url)) return false; // 空或已存在返回false
    
    final lowercaseUrl = url.toLowerCase();
    if (!lowercaseUrl.contains('.' + _filePattern)) return false; // 不含文件模式返回false
    
    if (_invalidPatternRegex.hasMatch(lowercaseUrl)) { // 包含无效关键词
      LogUtil.i('URL包含无效关键词: $url');
      return false;
    }
    
    if (_filterRules.isNotEmpty) { // 检查过滤规则
      bool matchedDomain = false;
      for (final rule in _filterRules) {
        if (url.contains(rule.domain)) {
          matchedDomain = true;
          final containsKeyword = rule.requiredKeyword.isEmpty || url.contains(rule.requiredKeyword);
          return containsKeyword;
        }
      }
      if (matchedDomain) {
        LogUtil.i('URL匹配域名但不符合关键词要求: $url');
        return false;
      }
    }
    
    return true; // 通过所有检查
  }

  /// 替换URL参数
  String _replaceParams(String url) {
    return (fromParam != null && toParam != null) ? url.replaceAll(fromParam!, toParam!) : url; // 执行替换
  }

  /// 处理发现的M3U8 URL
  Future<void> _handleM3U8Found(String? url, Completer<String> completer) async {
    if (_m3u8Found || _isCancelled() || completer.isCompleted || url == null || url.isEmpty) return;
    
    String cleanedUrl = _cleanUrl(url); // 清理URL
    if (!_isValidM3U8Url(cleanedUrl)) return; // 无效则返回
    
    String finalUrl = _replaceParams(cleanedUrl); // 替换参数
    _foundUrls.add(finalUrl); // 添加到已发现集合
    
    if (clickText == null) { // 无点击逻辑直接完成
      _m3u8Found = true;
      LogUtil.i('发现有效URL: $finalUrl');
      completer.complete(finalUrl);
      await dispose();
    } else {
      LogUtil.i('点击逻辑触发，记录URL: $finalUrl, 等待计时结束');
    }
  }

  /// 获取M3U8 URL
  Future<String> getUrl() async {
    final completer = Completer<String>();
    
    if (_isCancelled()) {
      LogUtil.i('GetM3U8 任务在启动前被取消');
      return 'ERROR';
    }
    
    final dynamicKeywords = _parseKeywords(dynamicKeywordsString);
    for (final keyword in dynamicKeywords) { // 检查动态关键词
      if (url.contains(keyword)) {
        try {
          final streamUrl = await GetM3u8Diy.getStreamUrl(url);
          LogUtil.i('getm3u8diy 返回结果: $streamUrl');
          return streamUrl;
        } catch (e, stackTrace) {
          LogUtil.logError('getm3u8diy 获取播放地址失败，返回 ERROR', e, stackTrace);
          return 'ERROR';
        }
      }
    }
    
    _filePattern = _determineFilePattern(url); // 确定文件模式
    
    try {
      await _initController(completer, _filePattern); // 初始化控制器
      _startTimeout(completer); // 启动超时计时
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      if (!completer.isCompleted) completer.complete('ERROR');
    }
    
    LogUtil.i('getUrl方法执行完成');
    return completer.future; // 返回结果
  }

  /// 检查页面内容中的M3U8
  Future<String?> _checkPageContent() async {
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

  /// 处理正则匹配结果
  Future<String?> _processMatches(Iterable<Match> matches, String sample) async {
    if (matches.isEmpty) return null; // 无匹配返回空
    
    final uniqueUrls = <String>{};
    for (final match in matches) {
      String url = match.group(0) ?? '';
      if (url.isNotEmpty) uniqueUrls.add(url); // 收集唯一URL
    }
    
    final validUrls = <String>[];
    for (final url in uniqueUrls) { // 验证URL
      final cleanedUrl = _cleanUrl(url);
      if (_isValidM3U8Url(cleanedUrl)) validUrls.add(_replaceParams(cleanedUrl));
    }
    
    if (validUrls.isEmpty) return null; // 无有效URL返回空
    
    if (clickIndex >= 0 && clickIndex < validUrls.length) { // 使用指定索引
      _m3u8Found = true;
      LogUtil.i('找到目标URL(index=$clickIndex): ${validUrls[clickIndex]}');
      return validUrls[clickIndex];
    } else { // 默认返回第一个
      _m3u8Found = true;
      LogUtil.i('clickIndex=$clickIndex 超出范围(共${validUrls.length}个地址)，返回第一个地址: ${validUrls[0]}');
      return validUrls[0];
    }
  }

  /// 准备M3U8检测器代码
  Future<String> _prepareM3U8DetectorCode() async {
    final cacheKey = 'm3u8_detector_${_filePattern}';
    if (_scriptCache.containsKey(cacheKey)) {
      return _scriptCache[cacheKey]!;
    }
    
    try {
      final script = await rootBundle.loadString('assets/js/m3u8_detector.js'); // 加载脚本
      final result = script.replaceAll('FILE_PATTERN', _filePattern); // 替换文件模式
      _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, result); // 修改：使用常量
      LogUtil.i('M3U8检测器脚本加载并缓存: $cacheKey');
      return result;
    } catch (e) {
      LogUtil.e('加载M3U8检测器脚本失败: $e');
      return '(function(){console.error("M3U8检测器加载失败");})();'; // 失败返回空函数
    }
  }
}
