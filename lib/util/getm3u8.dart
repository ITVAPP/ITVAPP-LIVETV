import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';  // 添加dio导入以支持CancelToken
import 'package:flutter/services.dart' show rootBundle;  // 添加rootBundle导入以支持加载JS文件
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/getm3u8diy.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// URL 处理工具类
class UrlUtils {
  static const _protocolPattern = GetM3U8._protocolPattern;

  /// 基础 URL 解码和清理
  static String basicUrlClean(String url) {
    // 合并转义字符正则表达式
    final escapeRegex = RegExp(r'\\\\(\\|/|")'); // 匹配双反斜杠后跟特殊字符
    // 合并HTML实体映射表
    const htmlEntities = {
      'amp': '&', 
      'quot': '"', 
      '#x2F': '/', 
      '#47': '/',  
      'lt': '<', 
      'gt': '>' 
    };

    // 去除末尾反斜杠
    if (url.endsWith('\\')) {
      url = url.substring(0, url.length - 1);
    }

    // 统一转义字符处理
    url = url.replaceAllMapped(escapeRegex, (match) {
      return match.group(1)!; // 提取第二个反斜杠或特殊字符
    }).replaceAll(r'\/', '/') // 单独处理JavaScript转义斜杠
        .replaceAllMapped(RegExp(r'&(#?[a-z0-9]+);'), (m) {
          // 统一HTML实体解码处理
          final entity = m.group(1)!;
          return htmlEntities[entity] ?? m.group(0)!;
        });

    // 统一URL解码流程
    void decodeUrl() {
      try {
        url = Uri.decodeComponent(url);
      } catch (e) {
        LogUtil.i('URL解码失败，保持原样: $e');
      }
    }
    
    // 分层解码策略
    decodeUrl(); // 第一层解码
    if (url.contains('%')) {
      decodeUrl(); // 第二层解码
    }

    // 统一多余斜杠处理
    url = url
      .trim()
      .replaceAll(RegExp(r'/{3,}'), '/') // 处理3+连续斜杠
      .replaceAll(RegExp(r'\s*\\s*$'), ''); // 保留末尾空格清理

    // Unicode处理优化
    url = url.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) => _parseUnicode(match.group(1)),
    );

    return url;
  }

  static String _parseUnicode(String? hex) {
    try {
      return String.fromCharCode(int.parse(hex!, radix: 16));
    } catch (e) {
      return '\\u$hex';
    }
  }

  /// 构建完整 URL
  static String buildFullUrl(String path, Uri baseUri) {
    // 检查是否已是完整 URL
    if (RegExp('^(?:${_protocolPattern})://').hasMatch(path)) {
      return path;
    }

    // 处理省略协议的完整 URL
    if (path.startsWith('//')) {
      // 移除路径开头的双斜杠，并强制添加协议头和单斜杠
      return '${baseUri.scheme}://${path.replaceFirst('//', '')}';
    }

    // 构建相对路径
    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '${baseUri.scheme}://${baseUri.host}/$cleanPath';
  }
  
  /// 检查URL是否包含有效协议
  static bool hasValidProtocol(String url) {
    return RegExp('^(?:${_protocolPattern})://').hasMatch(url);
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

  /// 从字符串解析规则，格式: domain|keyword
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length < 2) {
      return M3U8FilterRule(
        domain: parts[0].trim(),
        requiredKeyword: '',
      );
    }
    return M3U8FilterRule(
      domain: parts[0].trim(),
      requiredKeyword: parts[1].trim(),
    );
  }
}

/// 限制大小的集合类，用于优化内存管理
class LimitedSizeSet<T> {
  // 定义默认最大容量常量
  static const int DEFAULT_MAX_SIZE = 50;

  final int maxSize; // 最大容量
  final Set<T> _internalSet = {}; // 内部集合存储元素
  final List<T> _insertionOrder = []; // 记录插入顺序
  
  LimitedSizeSet([this.maxSize = DEFAULT_MAX_SIZE]);
  
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

/// 地址获取类
class GetM3U8 {
  // 常量定义
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
    
  // 统一的协议正则模式
  // static const _protocolPattern = r'(?:https?|rtmp|rtsp|ftp|mms|thunder)';
  static const _protocolPattern = r'(?:https?)';
  
  // 用于检查协议的正则
  static final _protocolRegex = RegExp('${_protocolPattern}://');
  
  // 脚本缓存
  static final Map<String, String> _scriptCache = {};
  static final Map<String, List<M3U8FilterRule>> _ruleCache = {};
  static final Map<String, Set<String>> _keywordsCache = {};
  static final Map<String, Map<String, String>> _specialRulesCache = {};
  static final Map<String, RegExp> _patternCache = {};

  /// 限制Map大小，移除最早项
  static void _limitMapSize<K, V>(Map<K, V> map, int maxSize, K key, V value) {
    if (map.length >= maxSize) map.remove(map.keys.first); // 超出时移除首项
    map[key] = value; // 添加新项
  }
  
  /// 全局规则配置字符串，在网页加载多个m3u8的时候，指定只使用符合条件的m3u8
  /// 格式: domain1|keyword1@domain2|keyword2
  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook=';

  /// 特殊规则字符串，用于动态设置监听的文件类型，格式: domain1|fileType1@domain2|fileType2
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4';

  /// 动态关键词规则字符串，符合规则使用getm3u8diy来解析
  static String dynamicKeywordsString = 'jinan@gansu@zhanjiang';

  /// 允许加载的资源模式字符串，用@分隔
  static const String allowedResourcePatternsString = 'r.png?t=perf';
  
  /// 阻止加载的黑名单关键字
  static const String blockedExtensionsString = '.png@.jpg@.jpeg@.gif@.webp@.css@.woff@.woff2@.ttf@.eot@.ico@.svg@.mp3@.wav@.pdf@.doc@.docx@.swf';

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

  /// WebView控制器 - 修改：从 late 改为 nullable
  WebViewController? _controller;

  /// 是否已找到M3U8
  bool _m3u8Found = false;

  /// 已发现的URL集合
  final LimitedSizeSet<String> _foundUrls = LimitedSizeSet<String>(MAX_FOUND_URLS_SIZE);

  /// 定期检查定时器
  Timer? _periodicCheckTimer;
  
  /// 超时定时器
  Timer? _timeoutTimer;

  /// 重试计数器
  int _retryCount = 0;

  /// 检查次数统计
  int _checkCount = 0;

  /// 无效URL关键词
  static final RegExp _invalidPatternRegex = RegExp(
    'advertisement|analytics|tracker|pixel|beacon|stats|log',
    caseSensitive: false,
  );

  /// 是否已释放资源
  bool _isDisposed = false;

  /// 标记 JS 检测器是否已注入
  bool _isDetectorInjected = false;

  /// 规则列表
  final List<M3U8FilterRule> _filterRules;

  /// 标记页面是否已处理过加载完成事件
  bool _isPageLoadProcessed = false;

  /// 标记点击是否已执行
  bool _isClickExecuted = false;

  /// 初始化状态标记
  bool _isControllerInitialized = false;

  /// 当前检测的文件类型
  String _filePattern = 'm3u8'; // 修改说明：将默认值移到类级别初始化，避免混淆后未赋值

  /// 跟踪首次hash加载
  static final Map<String, int> _hashFirstLoadMap = {};

  /// 标记URL是否使用了hash路由（#）导航方式
  bool isHashRoute = false;

  /// 是否为HTML格式
  bool _isHtmlContent = false;

  /// 存储HTTP请求的原始响应内容
  String? _httpResponseContent;

  /// 缓存的时间差值(毫秒)
  static int? _cachedTimeOffset;

  // 添加一个变量来跟踪当前URL的加载状态
  final LimitedSizeSet<String> _pageLoadedStatus = LimitedSizeSet<String>(MAX_PAGE_LOADED_STATUS_SIZE);

  /// 时间源配置
  static const List<Map<String, String>> TIME_APIS = [
    {
      'name': 'Aliyun API',
      'url': 'https://acs.m.taobao.com/gw/mtop.common.getTimestamp/',
    },
    {
      'name': 'Suning API',
      'url': 'https://quan.suning.com/getSysTime.do',
    },
    {
      'name': 'Meituan API',
      'url': 'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime',
    }
  ];

  /// 解析后的URI对象
  late final Uri _parsedUri;
  
  /// 取消令牌
  final CancelToken? cancelToken;
  
  /// 构造函数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = DEFAULT_TIMEOUT_SECONDS,
    this.cancelToken,
  }) : _filterRules = _parseRules(rulesString),
       // 初始化成员变量
       fromParam = _extractQueryParams(url)['from'],
       toParam = _extractQueryParams(url)['to'],
       clickText = _extractQueryParams(url)['clickText'],
       clickIndex = int.tryParse(_extractQueryParams(url)['clickIndex'] ?? '') ?? 0 {

    // 解析URL并存储结果
    try {
      _parsedUri = Uri.parse(url);
      isHashRoute = _parsedUri.fragment.isNotEmpty;
    } catch (e) {
      LogUtil.e('解析URL失败: $e');
      _parsedUri = Uri(scheme: 'https', host: 'invalid.host'); // 解析失败时的默认值
      isHashRoute = false;
    }
    
    // 确定文件模式
    _filePattern = _determineFilePattern(url);

    // 记录提取到的参数
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
    
    _limitMapSize(_patternCache, MAX_CACHE_SIZE, cacheKey, pattern);
    return pattern;
  }
  
  /// 从URL中提取查询参数
  static Map<String, String> _extractQueryParams(String url) {
    try {
      final uri = Uri.parse(url);
      Map<String, String> params = Map.from(uri.queryParameters);

      // 如果URL包含hash部分，解析hash中的参数
      if (uri.fragment.isNotEmpty) {
        // 检查fragment是否包含查询参数
        final fragmentParts = uri.fragment.split('?');
        if (fragmentParts.length > 1) {
          // 解析hash部分的查询参数
          final hashParams = Uri.splitQueryString(fragmentParts[1]);
          // 合并参数，hash部分的参数优先级更高
          params.addAll(hashParams);
        }
      }

      return params;
    } catch (e) {
      LogUtil.e('解析URL参数时发生错误: $e');
      return {};
    }
  }

  /// 解析规则字符串
  static List<M3U8FilterRule> _parseRules(String rulesString) {
    if (rulesString.isEmpty) {
      return [];
    }
    
    if (_ruleCache.containsKey(rulesString)) {
      return _ruleCache[rulesString]!;
    }

    try {
      final rules = rulesString
          .split('@')
          .where((rule) => rule.isNotEmpty)
          .map((rule) => M3U8FilterRule.fromString(rule))
          .toList();
          
      _limitMapSize(_ruleCache, MAX_RULE_CACHE_SIZE, rulesString, rules);
      return rules;
    } catch (e) {
      LogUtil.e('解析规则字符串失败: $e');
      return [];
    }
  }

  /// 解析动态关键词规则
  static Set<String> _parseKeywords(String keywordsString) {
    if (keywordsString.isEmpty) {
      return {};
    }
    
    if (_keywordsCache.containsKey(keywordsString)) {
      return _keywordsCache[keywordsString]!;
    }

    try {
      final keywords = keywordsString.split('@').map((keyword) => keyword.trim()).toSet();
      _limitMapSize(_keywordsCache, MAX_RULE_CACHE_SIZE, keywordsString, keywords);
      return keywords;
    } catch (e) {
      LogUtil.e('解析动态关键词规则失败: $e');
      return {};
    }
  }

  /// 解析特殊规则字符串，返回 Map，其中键是域名，值是文件类型
  static Map<String, String> _parseSpecialRules(String rulesString) {
    if (rulesString.isEmpty) {
      return {};
    }
    
    if (_specialRulesCache.containsKey(rulesString)) {
      return _specialRulesCache[rulesString]!;
    }

    try {
      final Map<String, String> rules = {};
      for (final rule in rulesString.split('@')) { // 分割规则
        final parts = rule.split('|');
        if (parts.length >= 2) rules[parts[0].trim()] = parts[1].trim(); // 解析键值对
      }
      
      _limitMapSize(_specialRulesCache, MAX_RULE_CACHE_SIZE, rulesString, rules);
      return rules;
    } catch (e) {
      LogUtil.e('解析特殊规则字符串失败: $e');
      return {};
    }
  }

  /// 解析允许的资源模式
  static List<String> _parseAllowedPatterns(String patternsString) {
    if (patternsString.isEmpty) {
      return [];
    }
    try {
      return patternsString.split('@').map((pattern) => pattern.trim()).toList();
    } catch (e) {
      LogUtil.e('解析允许的资源模式失败: $e');
      return [];
    }
  }
  
  /// 解析阻止扩展名的方法
  static List<String> _parseBlockedExtensions(String extensionsString) {
    if (extensionsString.isEmpty) return [];
    try {
      return extensionsString.split('@').map((ext) => ext.trim()).toList();
    } catch (e) {
      LogUtil.e('解析阻止的扩展名失败: $e');
      return [];
    }
  }

  /// URL整理
  String _cleanUrl(String url) {
    LogUtil.i('URL整理开始，原始URL: $url');
    
    // 基础清理
    String cleanedUrl = UrlUtils.basicUrlClean(url);
    return UrlUtils.hasValidProtocol(cleanedUrl) ? cleanedUrl : UrlUtils.buildFullUrl(cleanedUrl, _parsedUri);
  }
  
  /// 获取时间差（毫秒）
  Future<int> _getTimeOffset() async {
    // 使用缓存优先
    if (_cachedTimeOffset != null) return _cachedTimeOffset!;
    
    if (_isCancelled()) return 0;

    final localTime = DateTime.now();
    // 按顺序尝试多个时间源
    for (final api in TIME_APIS) {
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

  /// 从指定 API 获取网络时间
  Future<DateTime?> _getNetworkTime(String url) async {
    if (_isCancelled()) return null;
    
    final response = await HttpUtil().getRequest<String>(
      url,
      retryCount: 1,
      cancelToken: cancelToken,
    );

    if (response == null || _isCancelled()) return null;

    try {
      final Map<String, dynamic> data = json.decode(response);

      // 根据不同API返回格式解析时间
      if (url.contains('taobao')) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?['t'] ?? '0'));
      } else if (url.contains('suning')) {
        return DateTime.parse(data['sysTime2'] ?? '');
      } else if (url.contains('meituan')) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']?.toString() ?? '0'));
      }
    } catch (e) {
      LogUtil.e('解析时间响应失败: $e');
    }
    return null;
  }

  /// 准备时间拦截器代码
  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) {
      return '(function(){})();';
    }
    
    final cacheKey = 'time_interceptor_${_cachedTimeOffset}';
    if (_scriptCache.containsKey(cacheKey)) return _scriptCache[cacheKey]!;
    
    try {
      final script = await rootBundle.loadString('assets/js/time_interceptor.js');
      final result = script.replaceAll('TIME_OFFSET', '$_cachedTimeOffset');
      _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, result);
      return result;
    } catch (e) {
      LogUtil.e('加载时间拦截器脚本失败: $e');
      return '(function(){})();';
    }
  }
  
  /// 检查任务是否已取消
  bool _isCancelled() => _isDisposed || (cancelToken?.isCancelled ?? false);
  
/// 初始化WebViewController - 修改：确保 _controller 始终被赋值
Future<void> _initController(Completer<String> completer, String filePattern) async {
  if (_isCancelled()) {
    LogUtil.i('初始化控制器前任务被取消');
    if (!completer.isCompleted) completer.complete('ERROR');
    return;
  }
  
  try {
    LogUtil.i('开始初始化控制器');

    // 修改：立即赋值 _controller，避免未初始化
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent);
    _isControllerInitialized = true;

    // 尝试HTTP请求获取内容
    final httpResult = await _tryHttpRequest();
    if (_isCancelled()) {
      LogUtil.i('HTTP 请求完成后任务被取消');
      if (!completer.isCompleted) completer.complete('ERROR');
      return;
    }
    
    if (httpResult == true) {
      // 内容检查
      final result = await _checkPageContent();
      if (result != null) {
        if (!completer.isCompleted) completer.complete(result);
        return;
      }
      
      if (!_isHtmlContent) {
        // 非HTML内容直接返回错误
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
    }
    
    // 完整的WebView初始化
    await _initializeWebViewController(completer);

  } catch (e, stackTrace) {
    LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
    _isControllerInitialized = true; // 修改说明：即使失败也设置状态，避免后续检查失败
    await _handleLoadError(completer);
  }
}

/// 尝试通过HTTP请求获取内容
Future<bool> _tryHttpRequest() async {
  try {
    final httpdata = await HttpUtil().getRequest(url, cancelToken: cancelToken);
    if (_isCancelled()) return false;
    
    if (httpdata != null) {
      // 存储响应内容并判断是否为HTML
      _httpResponseContent = httpdata.toString();
      _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || _httpResponseContent!.contains('<html');
      LogUtil.i('HTTP响应内容类型: ${_isHtmlContent ? 'HTML' : '非HTML'}');
      
      // 如果是 HTML 内容,检查是否包含目标文件类型
      if (_isHtmlContent) {
        // 查找所有style标签的位置
        String content = _httpResponseContent!;
        int styleEndIndex = -1;
        final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
        if (styleEndMatch != null) {
          styleEndIndex = styleEndMatch.end;
        }
        
        // 确定检查内容
        String initialContent;
        if (styleEndIndex > 0) {
          initialContent = content.substring(styleEndIndex, (styleEndIndex + CONTENT_SAMPLE_LENGTH).clamp(0, content.length));
        } else {
          initialContent = content.length > CONTENT_SAMPLE_LENGTH ? content.substring(0, CONTENT_SAMPLE_LENGTH) : content;
        }
            
        return initialContent.contains('.' + _filePattern);
      }
      return true;
    } else {
      LogUtil.e('HttpUtil请求失败，未获取到数据，将继续尝试WebView加载');
      _httpResponseContent = null;
      _isHtmlContent = true; // 默认当作HTML内容处理
      return false;
    }
  } catch (e) {
    if (_isCancelled()) return false;
    LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
    _httpResponseContent = null;
    _isHtmlContent = true; // 默认当作HTML内容处理
    return false;
  }
}

/// 初始化WebView控制器
Future<void> _initializeWebViewController(Completer<String> completer) async {
  if (_isCancelled()) return;
  
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
  
  // 获取时间偏移并初始化脚本
  _cachedTimeOffset ??= await _getTimeOffset();
  
  // 准备初始化脚本
  final List<String> initScripts = await _prepareInitScripts();
  
  // 设置通信通道
  _setupJavaScriptChannels(completer);
  
  // 设置导航委托
  _setupNavigationDelegate(completer, initScripts);
  
  // 加载URL
  await _loadUrlWithHeaders();
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
  _controller!.addJavaScriptChannel(
    'TimeCheck',
    onMessageReceived: (JavaScriptMessage message) {
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
    },
  );

  _controller!.addJavaScriptChannel(
    'M3U8Detector',
    onMessageReceived: (JavaScriptMessage message) {
      if (_isCancelled()) return;
      try {
        final data = json.decode(message.message);
        if (data['type'] == 'init') {
          _isDetectorInjected = true;
        } else {
          _handleM3U8Found(data['url'] ?? message.message, completer);
        }
      } catch (e) {
        _handleM3U8Found(message.message, completer);
      }
    },
  );
}

/// 设置导航代理
void _setupNavigationDelegate(Completer<String> completer, List<String> initScripts) {
  final allowedPatterns = _parseAllowedPatterns(allowedResourcePatternsString);
  final blockedExtensions = _parseBlockedExtensions(blockedExtensionsString);
  final scriptNames = ['时间拦截器脚本 (time_interceptor.js)', '自动点击脚本脚本 (click_handler.js)', 'M3U8检测器脚本 (m3u8_detector.js)'];
  
  _controller!.setNavigationDelegate(
    NavigationDelegate(
      onPageStarted: (String url) async {
        if (_isCancelled()) {
          LogUtil.i('页面开始加载时任务被取消: $url');
          return;
        }
        for (int i = 0; i < initScripts.length; i++) {
          try {
            await _controller!.runJavaScript(initScripts[i]);
            LogUtil.i('注入脚本成功: ${scriptNames[i]}');
          } catch (e) {
            LogUtil.e('注入脚本失败 (${scriptNames[i]}): $e');
          }
        }
      },
      onNavigationRequest: (NavigationRequest request) async {
        if (_isCancelled()) return NavigationDecision.prevent;
        
        LogUtil.i('页面导航请求: ${request.url}');
        Uri? uri;
        try {
          uri = Uri.parse(request.url);
        } catch (e) {
          LogUtil.i('无效的URL，阻止加载: ${request.url}');
          return NavigationDecision.prevent;
        }
        
        try {
          final fullUrl = request.url.toLowerCase();
          
          // 1. 如果它匹配允许模式（白名单），允许它
          if (allowedPatterns.any((pattern) => fullUrl.contains(pattern.toLowerCase()))) {
            LogUtil.i('URL匹配允许模式，允许加载: ${request.url}');
            return NavigationDecision.navigate;
          }
          
          // 2. 检查URL是否包含被阻止的扩展名（黑名单）
          for (final ext in blockedExtensions) {
            if (fullUrl.contains(ext)) {
              LogUtil.i('阻止加载资源: ${request.url} (包含扩展名: $ext)');
              return NavigationDecision.prevent;
            }
          }
          
          // 3. 检查并阻止广告/跟踪请求
          if (_invalidPatternRegex.hasMatch(fullUrl)) {
             LogUtil.i('阻止广告/跟踪请求: ${request.url}');
             return NavigationDecision.prevent;
          }
          
          // 4. 检查M3U8文件
          try {
            if (uri.path.toLowerCase().contains('.' + _filePattern.toLowerCase())) {
              await _controller!.runJavaScript(
                'window.M3U8Detector?.postMessage(${json.encode({'type': 'url', 'url': request.url, 'source': 'navigation'})});'
              ).catchError((e) => LogUtil.e('发送M3U8URL到检测器失败: $e'));
              return NavigationDecision.prevent;
            }
          } catch (e) {
            LogUtil.e('URL检查失败: $e');
          }
        } catch (e) {
          // 出错时默认允许
          LogUtil.e('URL检查失败: $e，默认允许加载');
        }
        
        return NavigationDecision.navigate;
      },
      onPageFinished: (String url) async {
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
        
        if (isHashRoute && !_handleHashRoute(url)) return;
        
        if (!_isClickExecuted && clickText != null) {
          await Future.delayed(const Duration(milliseconds: CLICK_DELAY_MS));
          if (!_isCancelled()) {
            final clickResult = await _executeClick();
            if (clickResult) _startUrlCheckTimer(completer);
          }
        }
        
        if (!_isCancelled() && !_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
          _setupPeriodicCheck();
        }
      },
      onWebResourceError: (WebResourceError error) async {
        // 忽略被阻止资源的错误，忽略 SSL 错误，继续加载
        if (error.errorCode == -1 || error.errorCode == -6 || error.errorCode == -7) {
          LogUtil.i('资源被阻止加载: ${error.description}');
          return;
        }
        LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
        await _handleLoadError(completer);
      },
    ),
  );
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
    
    if (currentTriggers > MAX_RETRY_COUNT) {
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

/// 点击操作执行
Future<bool> _executeClick() async {
  if (!_isControllerReady() || _isClickExecuted || clickText == null || clickText!.isEmpty) {
    LogUtil.i(
      !_isControllerReady()
        ? 'WebViewController 未初始化，无法执行点击'
        : _isClickExecuted
          ? '点击已执行，跳过'
          : '无点击配置，跳过'
    );
    return false;
  }

  LogUtil.i('开始执行点击操作，文本: $clickText, 索引: $clickIndex');
  
  try {
    final cacheKey = 'click_handler_${clickText}_${clickIndex}';
    String scriptWithParams = _scriptCache[cacheKey] ?? (await rootBundle.loadString('assets/js/click_handler.js'))
        .replaceAll('SEARCH_TEXT', clickText!)
        .replaceAll('TARGET_INDEX', '$clickIndex');
    
    await _controller!.runJavaScript(scriptWithParams);
    _isClickExecuted = true;
    LogUtil.i('点击操作执行完成，结果: 成功');
    _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, scriptWithParams);
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
  
  Timer(const Duration(milliseconds: URL_CHECK_DELAY_MS), () async {
    if (_isCancelled() || completer.isCompleted) return;
    
    if (_foundUrls.length > 0) {
      _m3u8Found = true;
      final urlsList = _foundUrls.toList();
      String selectedUrl = (clickIndex == 0 || clickIndex >= urlsList.length) ? urlsList.last : urlsList[clickIndex];
      LogUtil.i('使用${clickIndex == 0 ? "最后" : "指定索引($clickIndex)"}发现的URL: $selectedUrl');
      
      if (!completer.isCompleted) completer.complete(selectedUrl);
      await dispose();
    } else {
      LogUtil.i('未发现任何URL');
    }
  });
}

/// 处理加载错误并重试
Future<void> _handleLoadError(Completer<String> completer) async {
  if (_isCancelled() || completer.isCompleted) return;
  
  if (_retryCount < MAX_RETRY_COUNT) {
    _retryCount++;
    LogUtil.i('尝试重试 ($_retryCount/$MAX_RETRY_COUNT)，延迟$RETRY_DELAY_MS毫秒');
    await Future.delayed(const Duration(milliseconds: RETRY_DELAY_MS));
    
    if (!_isCancelled() && !completer.isCompleted) {
      _pageLoadedStatus.clear();
      _isClickExecuted = false;
      await _initController(completer, _filePattern);
    }
  } else if (!completer.isCompleted) {
    LogUtil.e('达到最大重试次数或任务已取消');
    completer.complete('ERROR');
    await dispose();
  }
}

/// 加载URL并设置headers
Future<void> _loadUrlWithHeaders() async {
  if (!_isControllerReady()) {
    LogUtil.e('WebViewController 未初始化，无法加载URL');
    return;
  }
  try {
    final headers = HeadersConfig.generateHeaders(url: url);
    await _controller!.loadRequest(_parsedUri, headers: headers);
  } catch (e, stackTrace) {
    LogUtil.logError('加载URL时发生错误', e, stackTrace);
    throw Exception('URL 加载失败: $e');
  }
}

/// 检查控制器是否准备就绪
bool _isControllerReady() {
  if (!_isControllerInitialized || _isDisposed || _controller == null) {
    LogUtil.i('Controller 未初始化、已释放或为空，操作跳过');
    return false;
  }
  return true;
}

/// 重置控制器状态
void _resetControllerState() {
  _isControllerInitialized = false;
  _isDetectorInjected = false;
  _isPageLoadProcessed = false;
  _isClickExecuted = false;
  _m3u8Found = false;
  _retryCount = 0;
  _checkCount = 0;
}

/// 设定定期检查
void _setupPeriodicCheck() {
  if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
    final reason = _periodicCheckTimer != null ? "定时器已存在" : _isCancelled() ? "任务被取消" : "已找到M3U8";
    LogUtil.i('跳过定期检查设置: $reason');
    return;
  }
  
  _periodicCheckTimer = Timer.periodic(const Duration(milliseconds: PERIODIC_CHECK_INTERVAL_MS), (timer) async {
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
      await _controller!.runJavaScript('''
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
    
    if (_foundUrls.length > 0 && !completer.isCompleted) {
      _m3u8Found = true;
      final selectedUrl = _foundUrls.toList().last;
      LogUtil.i('超时前发现URL: $selectedUrl');
      completer.complete(selectedUrl);
    } else if (!completer.isCompleted) completer.complete('ERROR');
    
    await dispose();
  });
}

/// 释放资源
Future<void> dispose() async {
  if (_isDisposed) {
    LogUtil.i('资源已释放，跳过重复释放');
    return;
  }
  _isDisposed = true;
  
  _timeoutTimer?.cancel();
  _timeoutTimer = null;
  _periodicCheckTimer?.cancel();
  _periodicCheckTimer = null;
  
  if (cancelToken != null && !cancelToken!.isCancelled) {
    cancelToken!.cancel('GetM3U8 disposed');
  }
  
  // 清理 URL 相关资源
  _hashFirstLoadMap.remove(Uri.parse(url).toString());
  _foundUrls.clear();
  _pageLoadedStatus.clear();
  
  // 清理 WebView 资源
  if (_isControllerInitialized && _controller != null) {
    try {
      await _disposeWebViewCompletely(_controller!);
      LogUtil.i('WebView资源清理完成');
    } catch (e, stack) {
      LogUtil.logError('释放资源时发生错误', e, stack);
    }
  } else {
    LogUtil.i(_isHtmlContent ? '_controller 未初始化或为空，跳过释放资源' : '非HTML内容，跳过WebView资源清理');
  }

  // 重置状态
  _resetControllerState();
  _httpResponseContent = null;
  _controller = null; // 显式置空
  _suggestGarbageCollection();
  LogUtil.i('资源释放完成');
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
    await controller.setNavigationDelegate(NavigationDelegate());
    await controller.loadRequest(Uri.parse('about:blank'));
    await Future.delayed(Duration(milliseconds: WEBVIEW_CLEANUP_DELAY_MS));
    await controller.clearCache();
    if (_isHtmlContent) {
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
''').catchError((e) => LogUtil.e('清理JS行为失败: $e'));
    }
    await controller.clearLocalStorage();
    await controller.runJavaScript('window.location.href = "about:blank";');
    LogUtil.i('已清理资源，并重置页面');
  } catch (e, stack) {
    LogUtil.logError('清理 WebView 时发生错误', e, stack);
  }
}

/// 验证M3U8 URL是否有效
bool _isValidM3U8Url(String url) {
  if (url.isEmpty || _foundUrls.contains(url)) return false;
  
  final lowercaseUrl = url.toLowerCase();
  if (!lowercaseUrl.contains('.' + _filePattern)) {
    LogUtil.i('URL不包含.$_filePattern扩展名');
    return false;
  }
  
  if (_invalidPatternRegex.hasMatch(lowercaseUrl)) {
    LogUtil.i('URL包含无效关键词');
    return false;
  }
  
  if (_filterRules.isNotEmpty) {
    bool matchedDomain = false;
    for (final rule in _filterRules) {
      if (url.contains(rule.domain)) {
        matchedDomain = true;
        final containsKeyword = rule.requiredKeyword.isEmpty || url.contains(rule.requiredKeyword);
        LogUtil.i('发现匹配的域名规则: ${rule.domain}');
        return containsKeyword;
      }
    }
    if (matchedDomain) return false;
  }
  
  return true;
}

/// 处理发现的M3U8 URL
Future<void> _handleM3U8Found(String url, Completer<String> completer) async {
  if (_m3u8Found || _isCancelled() || completer.isCompleted || url.isEmpty) return;
  
  String cleanedUrl = _cleanUrl(url);
  if (!_isValidM3U8Url(cleanedUrl)) return;
  
  String finalUrl = (fromParam != null && toParam != null) ? cleanedUrl.replaceAll(fromParam!, toParam!) : cleanedUrl;
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

/// 准备M3U8检测器代码
Future<String> _prepareM3U8DetectorCode() async {
  final cacheKey = 'm3u8_detector_${_filePattern}';
  if (_scriptCache.containsKey(cacheKey)) {
    return _scriptCache[cacheKey]!;
  }
  
  try {
    final script = await rootBundle.loadString('assets/js/m3u8_detector.js');
    final result = script.replaceAll('FILE_PATTERN', _filePattern);
    _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, result);
    LogUtil.i('M3U8检测器脚本加载并缓存: $cacheKey');
    return result;
  } catch (e) {
    LogUtil.e('加载M3U8检测器脚本失败: $e');
    return '(function(){console.error("M3U8检测器加载失败");})();';
  }
}

/// 返回找到的第一个有效M3U8地址，如果未找到返回ERROR
Future<String> getUrl() async {
  final completer = Completer<String>();
  
  if (_isCancelled()) {
    LogUtil.i('GetM3U8 任务在启动前被取消');
    return 'ERROR';
  }

  // 解析动态关键词规则
  final dynamicKeywords = _parseKeywords(dynamicKeywordsString);

  // 检查是否需要使用 getm3u8diy 解析
  for (final keyword in dynamicKeywords) {
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

  // 确定文件模式
  _filePattern = _determineFilePattern(url);
  LogUtil.i('检测模式: $_filePattern');

  try {
    await _initController(completer, _filePattern);
    _startTimeout(completer);
  } catch (e, stackTrace) {
    LogUtil.logError('初始化过程发生错误', e, stackTrace);
    if (!completer.isCompleted) completer.complete('ERROR');
  }

  LogUtil.i('getUrl方法执行完成');
  return completer.future;
}

/// 检查页面内容中的M3U8地址
Future<String?> _checkPageContent() async {
  if (_m3u8Found || _isCancelled()) {
    LogUtil.i(
      '跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "资源已释放"}'
    );
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

    String sample = UrlUtils.basicUrlClean(_httpResponseContent!);
    LogUtil.i('正在检测页面中的 $_filePattern 文件');

    // 使用正则表达式查找URL
    final matches = _getOrCreatePattern(_filePattern).allMatches(sample);
    LogUtil.i('正则匹配到 ${matches.length} 个结果');

    return await _processMatches(matches, sample);
  } catch (e, stackTrace) {
    LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
    return null;
  } 
}

/// 处理正则匹配结果
Future<String?> _processMatches(Iterable<Match> matches, String sample) async {
  if (matches.isEmpty) return null;
  
  final uniqueUrls = <String>{};
  for (final match in matches) {
    String url = match.group(0) ?? '';
    if (url.isNotEmpty) uniqueUrls.add(url);
  }
  
  final validUrls = <String>[];
  for (final url in uniqueUrls) {
    final cleanedUrl = _cleanUrl(url);
    if (_isValidM3U8Url(cleanedUrl)) {
      String finalUrl = (fromParam != null && toParam != null) ? cleanedUrl.replaceAll(fromParam!, toParam!) : cleanedUrl;
      validUrls.add(finalUrl);
    }
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
}
