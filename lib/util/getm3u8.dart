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

  /// 无效URL关键词正则
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

  /// 清理脚本常量
  static const String _CLEANUP_SCRIPT = '''
    // 停止页面加载
    window.stop();

    // 清理时间拦截器
    if (window._cleanupTimeInterceptor) {
      window._cleanupTimeInterceptor();
    }

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

    // 清理全局变量
    delete window._timeInterceptorInitialized;
    delete window._originalDate;
    delete window._originalPerformanceNow;
    delete window._originalRAF;
    delete window._originalConsoleTime;
    delete window._originalConsoleTimeEnd;
    delete window._cleanupTimeInterceptor;
  ''';

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
  
  /// 检查任务是否已取消
  bool _isCancelled() => _isDisposed || (cancelToken?.isCancelled ?? false);

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

/// 初始化WebViewController - 修改：确保 _controller 始终被赋值
Future<void> _initController(Completer<String> completer, String filePattern) async {
  try {
    LogUtil.i('开始初始化控制器');

    // 修改：立即赋值 _controller，避免未初始化
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent);
    _isControllerInitialized = true;

    // 检查页面内容类型
    try {
      final httpdata = await HttpUtil().getRequest(url, cancelToken: cancelToken);
      if (_isCancelled()) {
        LogUtil.i('HTTP 请求完成后任务被取消');
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
      
      if (httpdata != null) {
        // 存储响应内容并判断是否为HTML
        _httpResponseContent = httpdata.toString();
        _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || _httpResponseContent!.contains('<html');
        LogUtil.i('HTTP响应内容类型: ${_isHtmlContent ? 'HTML' : '非HTML'}, 当前内容: $_httpResponseContent');
        
        // 如果是 HTML 内容,先进行内容检查
        if (_isHtmlContent) {
          // 查找所有style标签的位置
          String content = _httpResponseContent!;
          int styleEndIndex = -1;
          final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
          if (styleEndMatch != null) {
            // 获取最后一个style标签的结束位置
            styleEndIndex = styleEndMatch.end;
          }
          
          // 确定检查内容
          String initialContent;
          if (styleEndIndex > 0) {
            final startIndex = styleEndIndex;
            final endIndex = startIndex + 38888 > content.length ? content.length : startIndex + 38888;
            initialContent = content.substring(startIndex, endIndex);
          } else {
            // 如果没找到style标签，则从头开始取38888字节
            initialContent = content.length > 38888 ? content.substring(0, 38888) : content;
          }
              
          if (initialContent.contains('.' + filePattern)) {  // 快速预检
            final result = await _checkPageContent(); 
            if (result != null) {
              completer.complete(result);
              return;
            }
          }
          // 标记已检查,避免 WebView 重复检查
          _isPageLoadProcessed = true;
        }
      } else {
        LogUtil.e('HttpUtil请求失败，未获取到数据，将继续尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true; // 默认当作HTML内容处理
      }
    } catch (e) {
      if (_isCancelled()) {
        if (!completer.isCompleted) completer.complete('ERROR');
        return;
      }
      LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
      _httpResponseContent = null;
      _isHtmlContent = true; // 默认当作HTML内容处理
    }

    // 非HTML内容直接处理
    if (!isHashRoute && !_isHtmlContent) {
      LogUtil.i('检测到非HTML内容，直接处理');
      _isDetectorInjected = true;  // 标记为已注入，避免后续注入
      _isControllerInitialized = true;
      // 直接调用内容检查
      final result = await _checkPageContent();
      if (result != null) {
        completer.complete(result);
        return;
      }
      completer.complete('ERROR');
      return;
    }

    // 获取时间差并注入时间拦截器（对所有页面执行）
    _cachedTimeOffset ??= await _getTimeOffset();

    // 添加基础运行时脚本(优先注入)
    final timeInterceptorScript = await _prepareTimeInterceptorCode();

    // 注册时间检查消息通道
    _controller!.addJavaScriptChannel(
      'TimeCheck',
      onMessageReceived: (JavaScriptMessage message) {
        if (_isCancelled()) return;
        try {
          final data = json.decode(message.message);
          if (data['type'] == 'timeRequest') {
            final now = DateTime.now();
            final adjustedTime = now.add(Duration(milliseconds: _cachedTimeOffset ?? 0));
            LogUtil.i('检测到时间请求: ${data['method']}，返回时间：$adjustedTime');
          }
        } catch (e) {
          LogUtil.e('处理时间检查消息失败: $e');
        }
      },
    );

    // 注册消息通道
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

    // 解析允许的资源模式
    final allowedPatterns = _parseAllowedPatterns(allowedResourcePatternsString);
    final blockedExtensions = _parseBlockedExtensions(blockedExtensionsString);

    // 导航委托
    _controller!.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) async {
          if (_isCancelled()) return;
          
          // 注入时间拦截器
          try {
            await _controller!.runJavaScript(timeInterceptorScript);
            LogUtil.i('时间拦截器脚本注入成功');
          } catch (e) {
            LogUtil.e('注入时间拦截器脚本失败: $e');
          }
          
          // 初始化全局变量
          try {
            await _controller!.runJavaScript('''
              window._videoInit = false;
              window._processedUrls = new Set();
              window._m3u8Found = false;
            ''');
          } catch (e) {
            LogUtil.e('初始化全局变量失败: $e');
          }
          
          // 注入M3U8检测器
          try {
            final detectorScript = await _prepareM3U8DetectorCode();
            await _controller!.runJavaScript(detectorScript);
            _isDetectorInjected = true;
            LogUtil.i('M3U8检测器脚本注入成功');
          } catch (e) {
            LogUtil.e('注入M3U8检测器脚本失败: $e');
          }
        },
        onNavigationRequest: (NavigationRequest request) async {
          if (_isCancelled()) return NavigationDecision.prevent;
          
          LogUtil.i('页面导航请求: ${request.url}');
          Uri? uri;
          try {
            uri = Uri.parse(request.url);
          } catch (e) {
            LogUtil.i('无效的URL，阻止加载');
            return NavigationDecision.prevent;
          }

          // 资源检查逻辑
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
              final lowercasePath = uri.path.toLowerCase();
              if (lowercasePath.contains('.' + filePattern.toLowerCase())) {
                _controller!.runJavaScript(
                  'window.M3U8Detector?.postMessage(${json.encode({
                    'type': 'url',
                    'url': request.url,
                    'source': 'navigation'
                  })});'
                ).catchError((_) {});
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
          // 检查此URL是否已经触发过页面加载完成
          if (!isHashRoute && _pageLoadedStatus.contains(url)) {
            LogUtil.i('本页面已经加载完成，跳过重复处理');
            return;
          }

          // 标记该URL已处理
          _pageLoadedStatus.add(url);
          LogUtil.i('页面加载完成: $url');

          // 基础状态检查
          if (_isCancelled() || _isClickExecuted) {
            LogUtil.i(_isCancelled() ? '资源已释放，跳过处理' : '点击已执行，跳过处理');
            return;
          }

          // 处理hash路由
          try {
            if (isHashRoute) {
              final currentUri = _parsedUri;
              String mapKey = currentUri.toString();
              _pageLoadedStatus.clear();
              _pageLoadedStatus.add(mapKey);

              int currentTriggers = _hashFirstLoadMap[mapKey] ?? 0;
              currentTriggers++;

              if (currentTriggers > 2) {
                LogUtil.i('hash路由触发超过2次，跳过处理');
                return;
              }

              _hashFirstLoadMap[mapKey] = currentTriggers;

              if (currentTriggers == 1) {
                LogUtil.i('检测到hash路由首次加载，等待第二次加载');
                return;
              }
            }
          } catch (e) {
            LogUtil.e('解析URL失败: $e');
          }

          // 处理点击操作
          if (!_isClickExecuted && clickText != null) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (!_isCancelled()) {
              final clickResult = await _executeClick();
              if (clickResult) {
                _startUrlCheckTimer(completer);
              }
            }
          }

          // 首次加载处理
          if (!_isPageLoadProcessed) {
            _isPageLoadProcessed = true;
            // 开始动态监听
            if (!_isCancelled() && !_m3u8Found) {
              _setupPeriodicCheck();
            }
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

    // 初始化完成
    await _loadUrlWithHeaders();
    LogUtil.i('WebViewController初始化完成');

  } catch (e, stackTrace) {
    LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
    _isControllerInitialized = true; // 修改说明：即使失败也设置状态，避免后续检查失败
    await _handleLoadError(completer);
  }
}

  /// 准备时间拦截器代码
  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) {
      return '(function(){})();';
    }
    
    final cacheKey = 'time_interceptor_${_cachedTimeOffset}';
    if (_scriptCache.containsKey(cacheKey)) {
      return _scriptCache[cacheKey]!;
    }
    
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

  /// 点击操作执行
  Future<bool> _executeClick() async {
    // 检查WebViewController是否已初始化
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
      String scriptWithParams;
      
      if (_scriptCache.containsKey(cacheKey)) {
        scriptWithParams = _scriptCache[cacheKey]!;
      } else {
        final script = await rootBundle.loadString('assets/js/click_handler.js');
        scriptWithParams = script
            .replaceAll('SEARCH_TEXT', clickText!)
            .replaceAll('TARGET_INDEX', '$clickIndex');
        _limitMapSize(_scriptCache, MAX_CACHE_SIZE, cacheKey, scriptWithParams);
      }
      
      await _controller!.runJavaScript(scriptWithParams);
      _isClickExecuted = true;
      LogUtil.i('点击操作执行完成，结果: 成功');
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _isClickExecuted = true;
      // 无论发生何种错误，都视为点击成功
      return true; 
    }
  }
  
/// 启动URL检查定时器
void _startUrlCheckTimer(Completer<String> completer) {
  if (_isCancelled() || completer.isCompleted) return;
  
  Timer(const Duration(milliseconds: 3800), () async {
    if (_isCancelled() || completer.isCompleted) return;
    
    if (_foundUrls.length > 0) {
      _m3u8Found = true;
      
      String selectedUrl;
      final urlsList = _foundUrls.toList(); // 转换为列表以便按索引访问
      
      if (clickIndex == 0 || clickIndex >= urlsList.length) {
        // 如果 clickIndex 是 0 或大于可用的 URL 数量，使用最后一个
        selectedUrl = urlsList.last;
        LogUtil.i('使用最后发现的URL: $selectedUrl ${clickIndex >= urlsList.length ? "(clickIndex 超出范围)" : "(clickIndex = 0)"}');
      } else {
        // 否则使用 clickIndex 指定的 URL
        selectedUrl = urlsList[clickIndex];
        LogUtil.i('使用指定索引的URL: $selectedUrl (clickIndex = $clickIndex)');
      }
      
      completer.complete(selectedUrl);
      await dispose();
    } else {
      LogUtil.i('未发现任何URL');
    }
  });
}
  
/// 处理加载错误
Future<void> _handleLoadError(Completer<String> completer) async {
  if (_isCancelled() || completer.isCompleted) return;
  
  if (_retryCount < 2) {
    _retryCount++;
    LogUtil.i('尝试重试 ($_retryCount/2)，延迟1秒');
    await Future.delayed(const Duration(seconds: 1));
    if (!_isCancelled() && !completer.isCompleted) {
      // 重置页面加载处理标记和点击执行标记
      _isPageLoadProcessed = false;
      _pageLoadedStatus.clear();  // 清理加载状态
      _isClickExecuted = false;  // 重置点击状态，允许重试时重新点击
      await _initController(completer, _filePattern);
    }
  } else if (!completer.isCompleted) {
    LogUtil.e('达到最大重试次数或已释放资源');
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
      // 修改说明：抛出异常，避免无声失败导致导航未触发
      throw Exception('URL 加载失败: $e');
    }
  }

  /// 检查控制器是否准备就绪 - 修改：适配 nullable _controller
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
    // 如果已经有定时器在运行，或者已释放资源，或者已找到M3U8，则直接返回
    if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
      LogUtil.i('跳过定期检查设置: ${_periodicCheckTimer != null ? "定时器已存在" : _isCancelled() ? "已释放资源" : "已找到M3U8"}');
      return;
    }

    // 创建新的定期检查定时器
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        // 如果已找到M3U8或已释放资源，取消定时器
        if (_m3u8Found || _isCancelled()) {
          timer.cancel();
          _periodicCheckTimer = null;
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "已释放资源"}');
          return;
        }

        _checkCount++;
        LogUtil.i('执行第$_checkCount次定期检查');

        if (!_isControllerReady()) {
          LogUtil.i('WebViewController未准备好，跳过本次检查');
          return;
        }

        try {
          // 如果JS检测器未注入，先注入
          if (!_isDetectorInjected) {
            final detectorScript = await _prepareM3U8DetectorCode();
            await _controller!.runJavaScript(detectorScript);
            _isDetectorInjected = true;
            return;
          }

          // 调用JS端的扫描函数
          await _controller!.runJavaScript('''
            if (window._m3u8DetectorInitialized) {
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

  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    if (_isCancelled() || completer.isCompleted) return;
    
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      if (_isCancelled() || completer.isCompleted) {
        LogUtil.i('${_isCancelled() ? "已释放资源" : "已完成处理"}，跳过超时处理');
        return;
      }

      if (_foundUrls.length > 0 && !completer.isCompleted) {	
        _m3u8Found = true;
        final selectedUrl = _foundUrls.toList().last;
        LogUtil.i('超时前发现URL: $selectedUrl');
        completer.complete(selectedUrl);
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
      
      await dispose();
    });
  }
  
/// 释放资源 - 修改：适配 nullable _controller
Future<void> dispose() async {
  if (_isDisposed) {
    LogUtil.i('资源已释放，跳过重复释放');
    return;
  }
  _isDisposed = true;

  // 取消计时器
  _timeoutTimer?.cancel();
  _timeoutTimer = null;
  _periodicCheckTimer?.cancel();
  _periodicCheckTimer = null;
  
  // 取消HTTP请求
  if (cancelToken != null && !cancelToken!.isCancelled) {
    cancelToken!.cancel('GetM3U8 disposed');
  }

  // 清理 URL 相关资源
  _hashFirstLoadMap.remove(Uri.parse(url).toString());
  _foundUrls.clear();
  _pageLoadedStatus.clear();

  // 清理 WebView 资源 
  if (_isControllerInitialized && _isHtmlContent && _controller != null) {
    try {
      await _controller!.setNavigationDelegate(NavigationDelegate());
      await _controller!.loadRequest(Uri.parse('about:blank'));
      await Future.delayed(const Duration(milliseconds: 300));
      await _controller!.runJavaScript(_CLEANUP_SCRIPT);
      await _controller!.clearCache();
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
  _m3u8Found = false;
  _isDetectorInjected = false;
  _isControllerInitialized = false;
  _isPageLoadProcessed = false;
  _isClickExecuted = false;

  LogUtil.i('资源释放完成');
}
  
  /// 验证M3U8 URL是否有效
  bool _isValidM3U8Url(String url) {
    // 优化1: 使用缓存避免重复验证
    if (_foundUrls.contains(url)) {
      return false;
    }

    // 优化2: 快速预检查，减少正则表达式使用
    final lowercaseUrl = url.toLowerCase();
    if (!lowercaseUrl.contains('.' + _filePattern)) {
      LogUtil.i('URL不包含.$_filePattern扩展名');
      return false;
    }

    // 验证URL是否为有效格式
    final validUrl = _parsedUri;
    if (validUrl == null) {
      LogUtil.i('无效的URL格式');
      return false;
    }

    // 优化3: 使用类级别定义的正则表达式检查无效关键词
    if (_invalidPatternRegex.hasMatch(lowercaseUrl)) {
      LogUtil.i('URL包含无效关键词');
      return false;
    }

    // 优化4: 规则检查的短路处理
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
  if (_m3u8Found || _isCancelled() || completer.isCompleted) {
    LogUtil.i(
      _m3u8Found ? '跳过URL处理: 已找到M3U8' : '跳过URL处理: 资源已释放'
    );
    return;
  }
  if (url.isEmpty) return;
  
  // 首先整理URL
  String cleanedUrl = _cleanUrl(url);
  if (!_isValidM3U8Url(cleanedUrl)) {
    LogUtil.i('URL验证失败，继续等待新的URL');
    return;
  }
  
  // 处理URL参数替换
  String finalUrl = cleanedUrl;
  if (fromParam != null && toParam != null) {
    LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
    finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
  }

  // 所有情况下都记录URL
  _foundUrls.add(finalUrl);
  
  // 如果没有点击操作,立即完成
  if (clickText == null) {
    _m3u8Found = true;
    if (!completer.isCompleted) {
      LogUtil.i('发现有效URL: $finalUrl');
      completer.complete(finalUrl);
      await dispose();
    }
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
          return streamUrl;  // 直接返回，不执行后续 WebView 解析
        } catch (e, stackTrace) {
          LogUtil.logError('getm3u8diy 获取播放地址失败，返回 ERROR', e, stackTrace);
          return 'ERROR';  // 失败也直接返回，终止后续逻辑
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
    // 使用已经处理过的HTTP响应内容
    if (_httpResponseContent == null) {
      LogUtil.e('页面内容为空，跳过检测');
      return null;
    }

    String sample = UrlUtils.basicUrlClean(_httpResponseContent!);
    LogUtil.i('正在检测页面中的 $_filePattern 文件');

    // 使用正则表达式查找URL
    final pattern = '''(?:${_protocolPattern}://|//|/)[^'"\\s,()<>{}\\[\\]]*?\\.${_filePattern}[^'"\\s,()<>{}\\[\\]]*''';
    final regex = RegExp(pattern, caseSensitive: false);
    final matches = regex.allMatches(sample);
    LogUtil.i('正则匹配到 ${matches.length} 个结果');

    // 处理匹配结果
    return await _processMatches(matches, sample);

  } catch (e, stackTrace) {
    LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
    return null;
  } 
}
  
  /// 处理正则匹配结果
Future<String?> _processMatches(Iterable<Match> matches, String sample) async {
 final uniqueUrls = <String>{};
 for (final match in matches) {
   String url = match.group(0)!;
   uniqueUrls.add(url); 
 }

 var index = 0;
 for (final url in uniqueUrls) {
   final cleanedUrl = _cleanUrl(url);
   if (_isValidM3U8Url(cleanedUrl)) {
     String finalUrl = cleanedUrl;
     if (fromParam != null && toParam != null) {
       finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
     }
     _foundUrls.add(finalUrl);

     if (clickIndex == 0) {
       _m3u8Found = true;
       LogUtil.i('页面内容中找到 $finalUrl');
       return finalUrl;
     } else if (index == clickIndex) {
       _m3u8Found = true;
       LogUtil.i('找到目标URL(index=$clickIndex): $finalUrl');
       return finalUrl;
     }
     index++;
   }
 }
 return null;
}
}
