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
  static final RegExp _multiSlashRegex = RegExp(r'/{3,}'); // 匹配连续三个以上斜杠
  static final RegExp _htmlEntityRegex = RegExp(r'&(#?[a-z0-9]+);'); // 匹配 HTML 实体
  static final RegExp _unicodeRegex = RegExp(r'\u([0-9a-fA-F]{4})'); // 匹配 Unicode 编码
  static final RegExp _protocolRegex = RegExp('^${_protocolPatternStr}://'); // 匹配协议头

  static const Map<String, String> _htmlEntities = { // HTML 实体映射表
    'amp': '&', 'quot': '"', '#x2F': '/', '#47': '/', 'lt': '<', 'gt': '>'
  };

  /// 清理 URL，去除转义字符、多余斜杠、HTML 实体等
  static String basicUrlClean(String url) {
    if (url.isEmpty) return url; // 空 URL 直接返回
    if (url.endsWith(r'\')) url = url.substring(0, url.length - 1); // 移除末尾反斜杠
    
    String result = url
        .replaceAllMapped(_escapeRegex, (match) => match.group(1)!) // 移除转义符号
        .replaceAll(r'\/', '/') // 替换反斜杠斜杠为单斜杠
        .replaceAllMapped(_htmlEntityRegex, (m) => _htmlEntities[m.group(1)] ?? m.group(0)!) // 替换 HTML 实体
        .replaceAll(_multiSlashRegex, '/') // 合并多斜杠为单斜杠
        .trim(); // 去除首尾空格
    
    if (result.contains(r'\u')) { // 处理 Unicode 编码
      result = result.replaceAllMapped(_unicodeRegex, (match) => _parseUnicode(match.group(1)));
      LogUtil.i('Unicode 转换后: $result');
    }
    
    if (result.contains('%')) { // 处理 URL 编码
      try {
        result = Uri.decodeComponent(result);
      } catch (e) {
        LogUtil.i('URL解码失败，保持原样: $e');
      }
    }
    
    return result;
  }

  /// 将 Unicode 十六进制转换为字符
  static String _parseUnicode(String? hex) {
    if (hex == null) return ''; // 空值返回空字符串
    try {
      return String.fromCharCode(int.parse(hex, radix: 16)); // 转换为字符
    } catch (e) {
      return hex; // 解析失败返回原值
    }
  }

  /// 构建完整 URL，基于基础 URI 补全路径
  static String buildFullUrl(String path, Uri baseUri) {
    if (_protocolRegex.hasMatch(path)) return path; // 已含协议直接返回
    if (path.startsWith('//')) return '${baseUri.scheme}://${path.replaceFirst('//', '')}'; // 处理无协议双斜杠
    String cleanPath = path.startsWith('/') ? path.substring(1) : path; // 移除开头的斜杠
    return '${baseUri.scheme}://${baseUri.host}/$cleanPath'; // 拼接完整 URL
  }

  /// 检查 URL 是否包含有效协议
  static bool hasValidProtocol(String url) {
    return _protocolRegex.hasMatch(url); // 返回是否匹配协议正则
  }
}

/// M3U8 过滤规则配置类
class M3U8FilterRule {
  final String domain; // 域名
  final String requiredKeyword; // 必需关键字

  const M3U8FilterRule({required this.domain, required this.requiredKeyword});

  /// 从字符串解析规则，格式为 "域名|关键字"
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length < 2) return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: '');
    return M3U8FilterRule(domain: parts[0].trim(), requiredKeyword: parts[1].trim());
  }
}

/// 限制大小的集合类，用于优化内存管理
class LimitedSizeSet<T> {
  final int maxSize; // 最大容量
  final Set T _internalSet = {}; // 内部存储集合
  final List T _insertionOrder = []; // 插入顺序列表
  
  LimitedSizeSet(this.maxSize);
  
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
  int get length => _internalSet.length; // 获取当前长度
  List T toList() => List T.from(_insertionOrder); // 转换为列表
  Set T toSet() => Set T.from(_internalSet); // 转换为集合
  void clear() { _internalSet.clear(); _insertionOrder.clear(); } // 清空集合
  void remove(T element) { // 移除指定元素
    if (_internalSet.remove(element)) _insertionOrder.remove(element);
  }
}

/// M3U8 地址获取类
class GetM3U8 {
  static final Map<String, String> _scriptCache = {}; // 脚本缓存
  static final Map<String, List<M3U8FilterRule>> _ruleCache = {}; // 规则缓存
  static final Map<String, Set<String>> _keywordsCache = {}; // 关键字缓存
  static final Map<String, Map<String, String>> _specialRulesCache = {}; // 特殊规则缓存
  static final Map<String, RegExp> _patternCache = {}; // 正则缓存

  /// 限制 Map 大小，移除最早项以优化内存
  static void _limitMapSize<K, V>(Map<K, V> map, int maxSize, K key, V value) {
    if (map.length >= maxSize) map.remove(map.keys.first); // 超出时移除首项
    map[key] = value; // 添加新项
  }

  static final RegExp _invalidPatternRegex = RegExp( // 无效 URL 模式正则
    'advertisement|analytics|tracker|pixel|beacon|stats|log',
    caseSensitive: false,
  );

  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook='; // 过滤规则字符串
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4'; // 特殊规则字符串
  static String dynamicKeywordsString = 'jinan@gansu@zhanjiang'; // 动态关键字字符串
  static const String allowedResourcePatternsString = 'r.png?t='; // 允许资源模式字符串

  final String url; // 目标 URL
  final String? fromParam; // 替换参数 from
  final String? toParam; // 替换参数 to
  final String? clickText; // 点击文本
  final int clickIndex; // 点击索引
  final int timeoutSeconds; // 超时时间（秒）
  late WebViewController _controller; // WebView 控制器
  bool _m3u8Found = false; // 是否找到 M3U8
  final LimitedSizeSet<String> _foundUrls = LimitedSizeSet<String>(50); // 已发现 URL 集合
  Timer? _periodicCheckTimer; // 定期检查定时器
  int _retryCount = 0; // 重试次数
  int _checkCount = 0; // 检查次数
  final List<M3U8FilterRule> _filterRules; // 过滤规则列表
  bool _isClickExecuted = false; // 是否已执行点击
  bool _isControllerInitialized = false; // 控制器是否初始化
  String _filePattern = 'm3u8'; // 文件模式，默认 m3u8
  RegExp get _m3u8Pattern => _getOrCreatePattern(_filePattern); // 获取 M3U8 正则
  static final Map<String, int> _hashFirstLoadMap = {}; // Hash 路由加载记录
  bool isHashRoute = false; // 是否为 Hash 路由
  bool _isHtmlContent = false; // 是否为 HTML 内容
  String? _httpResponseContent; // HTTP 响应内容
  static int? _cachedTimeOffset; // 时间偏移缓存
  final LimitedSizeSet<String> _pageLoadedStatus = LimitedSizeSet<String>(100); // 页面加载状态
  static const List<Map<String, String>> TIME_APIS = [ // 时间 API 列表
    {'name': 'Aliyun API', 'url': 'https://acs.m.taobao.com/gw/mtop.common.getTimestamp/'},
    {'name': 'Suning API', 'url': 'https://quan.suning.com/getSysTime.do'},
    {'name': 'WorldTime API', 'url': 'https://worldtimeapi.org/api/timezone/Asia/Shanghai'},
    {'name': 'Meituan API', 'url': 'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime'},
  ];
  late final Uri _parsedUri; // 解析后的 URI
  final CancelToken? cancelToken; // 取消令牌
  bool _isDisposed = false; // 是否已释放
  Timer? _timeoutTimer; // 超时定时器

  /// 构造函数，初始化 URL 和相关参数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 15,
    this.cancelToken,
  }) : _filterRules = _parseRules(rulesString),
        fromParam = _extractQueryParams(url)['from'],
        toParam = _extractQueryParams(url)['to'],
        clickText = _extractQueryParams(url)['clickText'],
        clickIndex = int.tryParse(_extractQueryParams(url)['clickIndex'] ?? '') ?? 0 {
    _controller = WebViewController();
    try {
      _parsedUri = Uri.parse(url); // 解析 URL
      isHashRoute = _parsedUri.fragment.isNotEmpty; // 检查是否为 Hash 路由
    } catch (e) {
      LogUtil.e('解析URL失败: $e');
      _parsedUri = Uri(scheme: 'https', host: 'invalid.host'); // 解析失败使用默认值
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

  /// 根据 URL 确定文件模式（如 m3u8、flv 等）
  String _determineFilePattern(String url) {
    String pattern = 'm3u8';
    final specialRules = _parseSpecialRules(specialRulesString);
    for (final entry in specialRules.entries) {
      if (url.contains(entry.key)) {
        pattern = entry.value; // 匹配特殊规则时更新模式
        LogUtil.i('检测到特殊模式: $pattern 用于URL: $url');
        break;
      }
    }
    return pattern;
  }

  /// 获取或创建文件模式对应的正则表达式
  RegExp _getOrCreatePattern(String filePattern) {
    final cacheKey = 'pattern_$filePattern';
    if (_patternCache.containsKey(cacheKey)) return _patternCache[cacheKey]!; // 缓存命中
    
    final pattern = RegExp( // 创建匹配文件模式的正则
      "(?:https?://|//|/)[^'\"\\s,()<>{}\\[\\]]*?\\.${filePattern}[^'\"\\s,()<>{}\\[\\]]*",
      caseSensitive: false,
    );
    
    _limitMapSize(_patternCache, 50, cacheKey, pattern); // 缓存并限制大小
    return pattern;
  }

  /// 提取 URL 查询参数，包括 fragment 中的参数
  static Map<String, String> _extractQueryParams(String url) {
    try {
      final uri = Uri.parse(url);
      Map<String, String> params = Map.from(uri.queryParameters);
      if (uri.fragment.isNotEmpty) { // 处理 fragment 参数
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

  /// 解析过滤规则字符串为规则列表
  static List<M3U8FilterRule> _parseRules(String rulesString) {
    if (rulesString.isEmpty) return []; // 空字符串返回空列表
    
    if (_ruleCache.containsKey(rulesString)) return _ruleCache[rulesString]!; // 缓存命中
    
    final rules = rulesString.split('@') // 分割并转换为规则对象
        .where((rule) => rule.isNotEmpty)
        .map(M3U8FilterRule.fromString)
        .toList();
    
    _limitMapSize(_ruleCache, 20, rulesString, rules); // 缓存并限制大小
    return rules;
  }

  /// 解析关键字字符串为集合
  static Set<String> _parseKeywords(String keywordsString) {
    if (keywordsString.isEmpty) return {}; // 空字符串返回空集合
    
    if (_keywordsCache.containsKey(keywordsString)) return _keywordsCache[keywordsString]!; // 缓存命中
    
    final keywords = keywordsString.split('@') // 分割并去重
        .map((keyword) => keyword.trim())
        .toSet();
    
    _limitMapSize(_keywordsCache, 20, keywordsString, keywords); // 缓存并限制大小
    return keywords;
  }

  /// 解析特殊规则字符串为映射表
  static Map<String, String> _parseSpecialRules(String rulesString) {
    if (rulesString.isEmpty) return {}; // 空字符串返回空映射
    
    if (_specialRulesCache.containsKey(rulesString)) return _specialRulesCache[rulesString]!; // 缓存命中
    
    final Map<String, String> rules = {};
    for (final rule in rulesString.split('@')) {
      final parts = rule.split('|');
      if (parts.length >= 2) rules[parts[0].trim()] = parts[1].trim(); // 解析键值对
    }
    
    _limitMapSize(_specialRulesCache, 20, rulesString, rules); // 缓存并限制大小
    return rules;
  }

  /// 解析允许的资源模式字符串为列表
  static List<String> _parseAllowedPatterns(String patternsString) {
    if (patternsString.isEmpty) return []; // 空字符串返回空列表
    try {
      return patternsString.split('@').map((pattern) => pattern.trim()).toList(); // 分割并清理
    } catch (e) {
      LogUtil.e('解析允许的资源模式失败: $e');
      return [];
    }
  }

  /// 清理并补全 URL
  String _cleanUrl(String url) {
    String cleanedUrl = UrlUtils.basicUrlClean(url); // 基础清理
    return UrlUtils.hasValidProtocol(cleanedUrl) ? cleanedUrl : UrlUtils.buildFullUrl(cleanedUrl, _parsedUri); // 补全协议
  }

  /// 获取本地与网络时间偏移
  Future<int> _getTimeOffset() async {
    if (_cachedTimeOffset != null) return _cachedTimeOffset!; // 缓存命中
    
    final localTime = DateTime.now();
    for (final api in TIME_APIS) {
      try {
        final networkTime = await _getNetworkTime(api['url']!); // 获取网络时间
        if (networkTime != null) {
          _cachedTimeOffset = networkTime.difference(localTime).inMilliseconds; // 计算偏移
          return _cachedTimeOffset!;
        }
      } catch (e) {
        LogUtil.e('获取时间源失败 (${api['name']}): $e');
      }
    }
    return 0; // 无有效时间返回 0
  }

  /// 从指定 URL 获取网络时间
  Future<DateTime?> _getNetworkTime(String url) async {
    if (_isCancelled()) return null; // 已取消则返回 null
    final response = await HttpUtil().getRequest<String>(
      url,
      retryCount: 1,
      cancelToken: cancelToken,
    );
    if (response == null || _isCancelled()) return null; // 无响应或已取消返回 null
    try {
      final Map<String, dynamic> data = json.decode(response);
      if (url.contains('taobao')) { // 淘宝 API
        final timeStr = data['data']?['t'];
        return timeStr != null ? DateTime.fromMillisecondsSinceEpoch(int.parse(timeStr)) : null;
      } else if (url.contains('suning')) { // 苏宁 API
        return data['sysTime2'] != null ? DateTime.parse(data['sysTime2']) : null;
      } else if (url.contains('worldtimeapi')) { // 世界时间 API
        return data['datetime'] != null ? DateTime.parse(data['datetime']) : null;
      } else if (url.contains('meituan')) { // 美团 API
        final timeStr = data['data'];
        return timeStr != null ? DateTime.fromMillisecondsSinceEpoch(int.parse(timeStr.toString())) : null;
      }
    } catch (e) {
      LogUtil.e('解析时间响应失败: $e');
    }
    return null; // 解析失败返回 null
  }

  /// 准备时间拦截器脚本
  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) return '(function(){})();'; // 无偏移返回空函数
    
    final cacheKey = 'time_interceptor_${_cachedTimeOffset}';
    if (_scriptCache.containsKey(cacheKey)) return _scriptCache[cacheKey]!; // 缓存命中
    
    try {
      final script = await rootBundle.loadString('assets/js/time_interceptor.js'); // 加载脚本
      final result = script.replaceAll('TIME_OFFSET', '$_cachedTimeOffset'); // 替换偏移值
      _limitMapSize(_scriptCache, 50, cacheKey, result); // 缓存并限制大小
      return result;
    } catch (e) {
      LogUtil.e('加载时间拦截器脚本失败: $e');
      return '(function(){})();'; // 加载失败返回空函数
    }
  }

  /// 检查任务是否已取消
  bool _isCancelled() => _isDisposed || (cancelToken?.isCancelled ?? false);

  /// 初始化 WebView 控制器
  Future<void> _initController(Completer<String> completer, String filePattern) async {
    if (_isCancelled()) { // 已取消则完成并返回错误
      LogUtil.i('初始化控制器前任务被取消');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    
    try {
      LogUtil.i('开始初始化控制器');
      _isControllerInitialized = true;
      
      final httpResult = await _tryHttpRequest(); // 尝试 HTTP 请求
      if (_isCancelled()) {
        LogUtil.i('HTTP 请求完成后任务被取消');
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
      
      if (httpResult == true) { // HTTP 请求成功
        final result = await _checkPageContent(); // 检查页面内容
        if (result != null) {
          if (!completer.isCompleted) completer.complete(result); // 找到结果则完成
          return;
        }
        
        if (!_isHtmlContent) { // 非 HTML 内容
          if (!completer.isCompleted) completer.complete('ERROR');
          return;
        }
      }
      
      await _initializeWebViewController(completer); // 初始化 WebView
      
    } catch (e, stackTrace) {
      LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
      _isControllerInitialized = true;
      await _handleLoadError(completer); // 处理加载错误
    }
  }

  /// 尝试通过 HTTP 请求获取内容
  Future<bool> _tryHttpRequest() async {
    try {
      final httpdata = await HttpUtil().getRequest(url, cancelToken: cancelToken);
      
      if (_isCancelled()) return false; // 已取消返回 false
      
      if (httpdata != null) { // 请求成功
        _httpResponseContent = httpdata.toString();
        _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || 
                         _httpResponseContent!.contains('<html'); // 判断是否为 HTML
        
        LogUtil.i('HTTP响应内容类型: ${_isHtmlContent ? 'HTML' : '非HTML'}');
        
        if (_isHtmlContent) { // 处理 HTML 内容
          String content = _httpResponseContent!;
          int styleEndIndex = -1;
          final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
          if (styleEndMatch != null) styleEndIndex = styleEndMatch.end; // 找到 </style> 位置
          
          String initialContent;
          if (styleEndIndex > 0) { // 截取部分内容
            final startIndex = styleEndIndex;
            final endIndex = startIndex + 38888 > content.length ? content.length : startIndex + 38888;
            initialContent = content.substring(startIndex, endIndex);
          } else {
            initialContent = content.length > 38888 ? content.substring(0, 38888) : content;
          }
          
          return initialContent.contains('.' + _filePattern); // 检查是否包含文件模式
        }
        return true; // 非 HTML 返回 true
      } else {
        LogUtil.e('HttpUtil请求失败，未获取到数据，将继续尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true;
        return false;
      }
    } catch (e) {
      if (_isCancelled()) return false; // 已取消返回 false
      
      LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
      _httpResponseContent = null;
      _isHtmlContent = true;
      return false;
    }
  }

  /// 初始化 WebView 控制器并加载页面
  Future<void> _initializeWebViewController(Completer<String> completer) async {
    if (_isCancelled()) return; // 已取消则返回
    
    if (!isHashRoute && !_isHtmlContent) { // 非 Hash 路由且非 HTML
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
    
    _controller = WebViewController() // 配置 WebView
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用 JS
      ..setUserAgent(HeadersConfig.userAgent); // 设置用户代理
    
    final List<String> initScripts = await _prepareInitScripts(); // 准备初始化脚本
    
    _setupJavaScriptChannels(completer); // 设置 JS 通道
    
    _setupNavigationDelegate(completer, initScripts); // 设置导航代理
    
    await _loadUrlWithHeaders(); // 加载 URL
    LogUtil.i('WebViewController初始化完成');
  }

  /// 准备 WebView 初始化脚本
  Future<List<String>> _prepareInitScripts() async {
    final List<String> scripts = [];
    
    final timeInterceptorCode = await _prepareTimeInterceptorCode(); // 时间拦截器脚本
    scripts.add(timeInterceptorCode);
    
    scripts.add(''' // 初始化全局变量
window._videoInit = false;
window._processedUrls = new Set();
window._m3u8Found = false;
''');
    
    final m3u8DetectorCode = await _prepareM3U8DetectorCode(); // M3U8 检测脚本
    scripts.add(m3u8DetectorCode);
    
    return scripts;
  }

  /// 设置 JavaScript 通道以接收消息
  void _setupJavaScriptChannels(Completer<String> completer) {
    _controller.addJavaScriptChannel( // 时间检查通道
      'TimeCheck',
      onMessageReceived: (JavaScriptMessage message) {
        if (_isCancelled()) return; // 已取消则忽略
        try {
          final data = json.decode(message.message);
          if (data['type'] == 'timeRequest') { // 处理时间请求
            final now = DateTime.now();
            final adjustedTime = now.add(Duration(milliseconds: _cachedTimeOffset ?? 0));
            LogUtil.i('检测到时间请求: ${data['method']}，返回时间：$adjustedTime');
          }
        } catch (e) {
          LogUtil.e('处理时间检查消息失败: $e');
        }
      },
    );
    
    _controller.addJavaScriptChannel( // M3U8 检测通道
      'M3U8Detector',
      onMessageReceived: (JavaScriptMessage message) {
        if (_isCancelled()) return; // 已取消则忽略
        try {
          final data = json.decode(message.message);
          _handleM3U8Found(data['type'] == 'init' ? null : (data['url'] ?? message.message), completer); // 处理 M3U8 发现
        } catch (e) {
          _handleM3U8Found(message.message, completer); // 异常时直接处理消息
        }
      },
    );
  }

  /// 设置导航代理以控制页面加载行为
  void _setupNavigationDelegate(Completer<String> completer, List<String> initScripts) {
    final allowedPatterns = _parseAllowedPatterns(allowedResourcePatternsString); // 允许的资源模式
    final scriptNames = [ // 脚本名称列表
      '时间拦截器脚本 (time_interceptor.js)',
      '自动点击脚本脚本 (click_handler.js)',
      'M3U8检测器脚本 (m3u8_detector.js)',
    ];
    
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) async { // 页面开始加载
          if (_isCancelled()) {
            LogUtil.i('页面开始加载时任务被取消: $url');
            return;
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
        onNavigationRequest: (NavigationRequest request) async { // 导航请求处理
          if (_isCancelled()) {
            LogUtil.i('导航请求时任务被取消: ${request.url}');
            return NavigationDecision.prevent; // 已取消则阻止
          }
          
          try {
            final currentUri = _parsedUri;
            final newUri = Uri.parse(request.url);
            if (currentUri.host != newUri.host) { // 跨域重定向
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
            return NavigationDecision.prevent; // 无效 URL 阻止加载
          }
          
          try { // 检查资源扩展名
            final pathParts = uri.path.toLowerCase().split('.');
            if (pathParts.length > 1) {
              final extension = pathParts.last;
              final blockedExtensions = [
                'jpg', 'jpeg', 'png', 'gif', 'webp',
                'css', 'woff', 'woff2', 'ttf', 'eot',
                'ico', 'svg', 'mp3', 'wav',
                'pdf', 'doc', 'docx', 'swf',
              ];
              if (blockedExtensions.contains(extension)) {
                if (allowedPatterns.any((pattern) => request.url.contains(pattern))) {
                  LogUtil.i('允许加载匹配模式的资源: ${request.url}');
                  return NavigationDecision.navigate; // 匹配允许模式则放行
                }
                LogUtil.i('阻止加载资源: ${request.url} (扩展名: $extension)');
                return NavigationDecision.prevent; // 阻止非必要资源
              }
            }
          } catch (e) {
            LogUtil.e('提取扩展名失败: $e');
          }
          
          try { // 检查 M3U8 URL
            final lowercasePath = uri.path.toLowerCase();
            if (lowercasePath.contains('.' + _filePattern.toLowerCase())) {
              try {
                _controller.runJavaScript( // 发送 M3U8 URL 到检测器
                  'window.M3U8Detector?.postMessage(${json.encode({
                    'type': 'url',
                    'url': request.url,
                    'source': 'navigation'
                  })});'
                );
              } catch (e) {
                LogUtil.e('发送M3U8URL到检测器失败: $e');
              }
              return NavigationDecision.prevent; // 阻止直接加载
            }
          } catch (e) {
            LogUtil.e('URL检查失败: $e');
          }
          
          return NavigationDecision.navigate; // 默认放行
        },
        onPageFinished: (String url) async { // 页面加载完成
          if (_isCancelled()) {
            LogUtil.i('页面加载完成时任务被取消: $url');
            return;
          }
          
          if (!isHashRoute && _pageLoadedStatus.contains(url)) { // 已加载过
            LogUtil.i('本页面已经加载完成，跳过重复处理');
            return;
          }
          
          _pageLoadedStatus.add(url); // 记录加载状态
          LogUtil.i('页面加载完成: $url');
          
          if (_isClickExecuted) { // 已执行点击
            LogUtil.i('点击已执行，跳过处理');
            return;
          }
          
          if (isHashRoute) { // 处理 Hash 路由
            if (!_handleHashRoute(url)) return;
          }
          
          if (!_isClickExecuted && clickText != null) { // 执行点击操作
            await Future.delayed(const Duration(milliseconds: 300));
            if (!_isCancelled()) {
              final clickResult = await _executeClick();
              if (clickResult) _startUrlCheckTimer(completer); // 点击成功后启动检查
            }
          }
          
          if (!_isCancelled() && !_m3u8Found && 
              (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
            _setupPeriodicCheck(); // 设置定期检查
          }
        },
        onWebResourceError: (WebResourceError error) async { // 资源加载错误
          if (_isCancelled()) {
            LogUtil.i('资源错误时任务被取消: ${error.description}');
            return;
          }
          
          if (error.errorCode == -1 || error.errorCode == -6 || error.errorCode == -7) { // 被阻止的资源
            LogUtil.i('资源被阻止加载: ${error.description}');
            return;
          }
          
          LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
          await _handleLoadError(completer); // 处理加载错误
        },
      ),
    );
  }

  /// 处理 Hash 路由逻辑
  bool _handleHashRoute(String url) {
    try {
      final currentUri = _parsedUri;
      String mapKey = currentUri.toString();
      _pageLoadedStatus.clear();
      _pageLoadedStatus.add(mapKey);
      
      int currentTriggers = _hashFirstLoadMap[mapKey] ?? 0;
      currentTriggers++;
      
      if (currentTriggers > 2) { // 超过两次触发跳过
        LogUtil.i('hash路由触发超过2次，跳过处理');
        return false;
      }
      
      _hashFirstLoadMap[mapKey] = currentTriggers;
      
      if (currentTriggers == 1) { // 首次加载等待
        LogUtil.i('检测到hash路由首次加载，等待第二次加载');
        return false;
      }
      
      return true; // 第二次加载继续处理
    } catch (e) {
      LogUtil.e('解析URL失败: $e');
      return true;
    }
  }

  /// 执行自动点击操作
  Future<bool> _executeClick() async {
    if (!_isControllerReady() || _isClickExecuted || clickText == null || clickText!.isEmpty) {
      final reason = !_isControllerReady() 
          ? 'WebViewController 未初始化' 
          : _isClickExecuted 
              ? '点击已执行' 
              : '无点击配置';
      LogUtil.i('$reason，跳过点击操作');
      return false;
    }
    
    LogUtil.i('开始执行点击操作，文本: $clickText, 索引: $clickIndex');
    
    try {
      final cacheKey = 'click_handler_${clickText}_${clickIndex}';
      String scriptWithParams;
      
      if (_scriptCache.containsKey(cacheKey)) { // 缓存命中
        scriptWithParams = _scriptCache[cacheKey]!;
      } else {
        final jsCode = await rootBundle.loadString('assets/js/click_handler.js'); // 加载点击脚本
        scriptWithParams = jsCode
            .replaceAll('SEARCH_TEXT', clickText!) // 替换文本
            .replaceAll('TARGET_INDEX', '$clickIndex'); // 替换索引
        _limitMapSize(_scriptCache, 50, cacheKey, scriptWithParams); // 缓存脚本
      }
      
      await _controller.runJavaScript(scriptWithParams); // 执行点击
      _isClickExecuted = true;
      LogUtil.i('点击操作执行完成，结果: 成功');
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _isClickExecuted = true;
      return true;
    }
  }

  /// 启动 URL 检查定时器
  void _startUrlCheckTimer(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return; // 已取消或完成则返回
    
    Timer(const Duration(milliseconds: 2500), () async { // 延迟 2.5 秒检查
      if (_isCancelled() || completer.isCompleted) return;
      
      if (_foundUrls.length > 0) { // 发现 URL
        _m3u8Found = true;
        String selectedUrl;
        final urlsList = _foundUrls.toList();
        
        if (clickIndex == 0 || clickIndex >= urlsList.length) { // 使用最后一个 URL
          selectedUrl = urlsList.last;
          LogUtil.i('使用最后发现的URL: $selectedUrl ${clickIndex >= urlsList.length ? "(clickIndex 超出范围)" : "(clickIndex = 0)"}');
        } else { // 使用指定索引 URL
          selectedUrl = urlsList[clickIndex];
          LogUtil.i('使用指定索引的URL: $selectedUrl (clickIndex = $clickIndex)');
        }
        
        if (!completer.isCompleted) {
          completer.complete(selectedUrl); // 完成并返回 URL
        }
        
        await dispose(); // 释放资源
      } else {
        LogUtil.i('未发现任何URL');
      }
    });
  }

  /// 处理加载错误并重试
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_isCancelled() || completer.isCompleted) return; // 已取消或完成则返回
    
    if (_retryCount < 2) { // 重试次数未达上限
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/2)，延迟800毫秒');
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (!_isCancelled() && !completer.isCompleted) {
        _pageLoadedStatus.clear();
        _isClickExecuted = false;
        await _initController(completer, _filePattern); // 重试初始化
      }
    } else if (!completer.isCompleted) { // 达到最大重试次数
      LogUtil.e('达到最大重试次数或任务已取消');
      completer.complete('ERROR');
      await dispose(); // 释放资源
    }
  }

  /// 使用自定义头加载 URL
  Future<void> _loadUrlWithHeaders() async {
    if (!_isControllerReady()) { // 控制器未准备好
      LogUtil.e('WebViewController 未初始化，无法加载URL');
      return;
    }
    
    try {
      final headers = HeadersConfig.generateHeaders(url: url); // 生成请求头
      await _controller.loadRequest(_parsedUri, headers: headers); // 加载 URL
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      throw Exception('URL 加载失败: $e');
    }
  }

  /// 检查控制器是否准备好
  bool _isControllerReady() => _isControllerInitialized && !_isCancelled();

  /// 重置控制器状态
  void _resetControllerState() {
    _isControllerInitialized = false;
    _isClickExecuted = false;
    _m3u8Found = false;
    _retryCount = 0;
    _checkCount = 0;
  }

  /// 设置定期检查以扫描页面
  void _setupPeriodicCheck() {
    if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
      final reason = _periodicCheckTimer != null 
          ? "定时器已存在" 
          : _isCancelled() 
              ? "任务被取消" 
              : "已找到M3U8";
      LogUtil.i('跳过定期检查设置: $reason');
      return;
    }
    
    _periodicCheckTimer = Timer.periodic( // 每 1.2 秒检查一次
      const Duration(milliseconds: 1200),
      (timer) async {
        if (_m3u8Found || _isCancelled()) { // 已找到或取消则停止
          timer.cancel();
          _periodicCheckTimer = null;
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "任务被取消"}');
          return;
        }
        
        _checkCount++;
        LogUtil.i('执行第$_checkCount次定期检查');
        
        if (!_isControllerReady()) { // 控制器未准备好
          LogUtil.i('WebViewController未准备好，跳过本次检查');
          return;
        }
        
        try {
          final detectorScript = await _prepareM3U8DetectorCode(); // 准备检测脚本
          await _controller.runJavaScript(''' // 执行扫描
if (window._m3u8DetectorInitialized) {
  checkMediaElements(document);
  efficientDOMScan();
} else {
  $detectorScript
  checkMediaElements(document);
  efficientDOMScan();
}
''').catchError((error) {
            LogUtil.e('执行扫描失败: $error');
          });
        } catch (e, stack) {
          LogUtil.logError('定期检查执行出错', e, stack);
        }
      },
    );
  }

  /// 启动超时处理
  void _startTimeout(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return; // 已取消或完成则返回
    
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    
    _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () async { // 设置超时
      if (_isCancelled() || completer.isCompleted) {
        LogUtil.i('${_isCancelled() ? "任务已取消" : "已完成处理"}，跳过超时处理');
        return;
      }
      
      if (_foundUrls.length > 0 && !completer.isCompleted) { // 超时前发现 URL
        _m3u8Found = true;
        final selectedUrl = _foundUrls.toList().last;
        LogUtil.i('超时前发现URL: $selectedUrl');
        completer.complete(selectedUrl);
      } else if (!completer.isCompleted) { // 未发现 URL
        completer.complete('ERROR');
      }
      
      await dispose(); // 释放资源
    });
  }

  /// 释放所有资源
  Future<void> dispose() async {
    if (_isDisposed) return; // 已释放则返回
    
    _isDisposed = true;
    LogUtil.i('开始释放资源: ${DateTime.now()}');
    
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    
    if (cancelToken != null && !cancelToken!.isCancelled) { // 取消未完成请求
      cancelToken!.cancel('GetM3U8 disposed');
      LogUtil.i('已取消所有未完成的 HTTP 请求');
    }
    
    _hashFirstLoadMap.remove(Uri.parse(url).toString()); // 清理 Hash 记录
    _foundUrls.clear();
    _pageLoadedStatus.clear();
    
    if (_isControllerInitialized) { // 清理 WebView
      await _disposeWebViewCompletely(_controller);
    } else {
      LogUtil.i('WebViewController 未初始化，跳过清理');
    }
    
    _resetControllerState();
    _httpResponseContent = null;
    
    _suggestGarbageCollection(); // 建议垃圾回收
    
    LogUtil.i('资源释放完成: ${DateTime.now()}');
  }

  /// 建议进行垃圾回收
  void _suggestGarbageCollection() {
    try {
      Future.delayed(Duration.zero, () {});
    } catch (e) {
      // 忽略异常
    }
  }

  /// 完全释放 WebView 资源
  Future<void> _disposeWebViewCompletely(WebViewController controller) async {
    try {
      await controller.setNavigationDelegate(NavigationDelegate()); // 重置导航代理
      await controller.loadRequest(Uri.parse('about:blank')); // 加载空白页
      await Future.delayed(Duration(milliseconds: 100));
      await controller.clearCache(); // 清理缓存
      
      if (_isHtmlContent) { // 清理 JS 和动态行为
        try {
          await controller.runJavaScript('''
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
''');
          LogUtil.i('已清理 JS 和动态行为');
        } catch (e) {
          LogUtil.e('清理JS行为失败: $e');
        }
      }
      
      try { // 清理缓存和存储
        await controller.clearCache();
        await controller.clearLocalStorage();
        await controller.runJavaScript('window.location.href = "about:blank";'); // 重置页面
        LogUtil.i('已清理缓存和本地存储，并重置页面');
      } catch (e) {
        LogUtil.e('清理缓存失败: $e');
      }
    } catch (e, stack) {
      LogUtil.logError('清理 WebView 时发生错误', e, stack);
    }
  }

  /// 检查 M3U8 URL 是否有效
  bool _isValidM3U8Url(String url) {
    if (url.isEmpty || _foundUrls.contains(url)) return false; // 空或已存在返回 false
    
    final lowercaseUrl = url.toLowerCase();
    if (!lowercaseUrl.contains('.' + _filePattern)) return false; // 不含文件模式返回 false
    
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
          if (!containsKeyword) {
            LogUtil.i('URL不包含所需关键词 (${rule.requiredKeyword}): $url');
          }
          return containsKeyword;
        }
      }
      
      if (matchedDomain) { // 匹配域名但无关键词
        LogUtil.i('URL匹配域名但不符合关键词要求: $url');
        return false;
      }
    }
    
    return true; // 通过所有检查
  }

  /// 替换 URL 中的参数
  String _replaceParams(String url) {
    return (fromParam != null && toParam != null) ? url.replaceAll(fromParam!, toParam!) : url; // 执行替换
  }

  /// 处理发现的 M3U8 URL
  Future<void> _handleM3U8Found(String? url, Completer<String> completer) async {
    if (_m3u8Found || _isCancelled() || completer.isCompleted || url == null || url.isEmpty) return; // 无效情况返回
    
    String cleanedUrl = _cleanUrl(url); // 清理 URL
    if (!_isValidM3U8Url(cleanedUrl)) return; // 无效则返回
    
    String finalUrl = _replaceParams(cleanedUrl); // 替换参数
    LogUtil.i('执行URL参数替换后: $finalUrl');
    _foundUrls.add(finalUrl); // 添加到已发现集合
    
    if (clickText == null) { // 无点击逻辑直接完成
      _m3u8Found = true;
      LogUtil.i('发现有效URL: $finalUrl');
      completer.complete(finalUrl);
      await dispose();
    } else { // 有点击逻辑则记录等待
      LogUtil.i('点击逻辑触发，记录URL: $finalUrl, 等待计时结束');
    }
  }

  /// 获取 M3U8 URL
  Future<String> getUrl() async {
    final completer = Completer<String>();
    
    if (_isCancelled()) { // 已取消返回错误
      LogUtil.i('GetM3U8 任务在启动前被取消');
      return 'ERROR';
    }
    
    final dynamicKeywords = _parseKeywords(dynamicKeywordsString); // 解析动态关键字
    for (final keyword in dynamicKeywords) {
      if (url.contains(keyword)) { // 匹配关键字使用特殊处理
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
      _startTimeout(completer); // 启动超时
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      if (!completer.isCompleted) completer.complete('ERROR');
    }
    
    LogUtil.i('getUrl方法执行完成');
    return completer.future; // 返回结果
  }

  /// 检查页面内容中的 M3U8 URL
  Future<String?> _checkPageContent() async {
    if (_m3u8Found || _isCancelled()) { // 已找到或取消则跳过
      LogUtil.i('跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "任务被取消"}');
      return null;
    }
    
    if (clickText != null && !_isClickExecuted) { // 点击未完成则跳过
      LogUtil.i('点击操作未完成，跳过页面内容检查');
      return null;
    }
    
    try {
      if (_httpResponseContent == null || _httpResponseContent!.isEmpty) { // 内容为空
        LogUtil.e('页面内容为空，跳过检测');
        return null;
      }
      
      String sample = UrlUtils.basicUrlClean(_httpResponseContent!); // 清理内容
      LogUtil.i('正在检测页面中的 $_filePattern 文件');
      
      final matches = _m3u8Pattern.allMatches(sample); // 匹配所有 URL
      LogUtil.i('正则匹配到 ${matches.length} 个结果');
      
      return await _processMatches(matches, sample); // 处理匹配结果
    } catch (e, stackTrace) {
      LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
      return null;
    }
  }

  /// 处理正则匹配的 URL
  Future<String?> _processMatches(Iterable<Match> matches, String sample) async {
    if (matches.isEmpty) return null; // 无匹配返回 null
    
    final uniqueUrls = <String>{}; // 去重 URL 集合
    for (final match in matches) {
      String url = match.group(0) ?? '';
      if (url.isNotEmpty) uniqueUrls.add(url);
    }
    
    final validUrls = <String>[]; // 有效 URL 列表
    for (final url in uniqueUrls) {
      final cleanedUrl = _cleanUrl(url); // 清理 URL
      if (_isValidM3U8Url(cleanedUrl)) { // 检查有效性
        String finalUrl = _replaceParams(cleanedUrl); // 替换参数
        validUrls.add(finalUrl);
      }
    }
    
    if (validUrls.isEmpty) return null; // 无有效 URL 返回 null
    
    if (clickIndex >= 0 && clickIndex < validUrls.length) { // 使用指定索引
      _m3u8Found = true;
      LogUtil.i('找到目标URL(index=$clickIndex): ${validUrls[clickIndex]}');
      return validUrls[clickIndex];
    } else { // 超出范围使用第一个
      _m3u8Found = true;
      LogUtil.i('clickIndex=$clickIndex 超出范围(共${validUrls.length}个地址)，返回第一个地址: ${validUrls[0]}');
      return validUrls[0];
    }
  }

  /// 准备 M3U8 检测脚本
  Future<String> _prepareM3U8DetectorCode() async {
    final cacheKey = 'm3u8_detector_${_filePattern}';
    
    if (_scriptCache.containsKey(cacheKey)) { // 缓存命中
      LogUtil.i('命中M3U8检测器脚本缓存: $cacheKey');
      return _scriptCache[cacheKey]!;
    }
    
    try {
      final script = await rootBundle.loadString('assets/js/m3u8_detector.js'); // 加载脚本
      final result = script.replaceAll('FILE_PATTERN', _filePattern); // 替换文件模式
      _limitMapSize(_scriptCache, 50, cacheKey, result); // 缓存脚本
      LogUtil.i('M3U8检测器脚本加载并缓存: $cacheKey');
      return result;
    } catch (e) {
      LogUtil.e('加载M3U8检测器脚本失败: $e');
      return '(function(){console.error("M3U8检测器加载失败");})();'; // 失败返回空函数
    }
  }
}
