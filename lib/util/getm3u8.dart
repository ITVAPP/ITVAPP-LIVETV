import 'dart:async';
import 'dart:convert';
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
    return M3U8FilterRule(
      domain: parts[0].trim(),
      requiredKeyword: parts[1].trim(),
    );
  }
}

/// 地址获取类
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
  // 阻止加载的黑名单关键字
  static const String blockedExtensionsString = '.png@.jpg@.jpeg@.gif@.webp@.css@.woff@.woff2@.ttf@.eot@.ico@.svg@.mp3@.wav@.pdf@.doc@.docx@.swf';
  
  // 解析阻止扩展名的方法
  static List<String> _parseBlockedExtensions(String extensionsString) {
    if (extensionsString.isEmpty) return [];
    try {
      return extensionsString.split('@').map((ext) => ext.trim()).toList();
    } catch (e) {
      LogUtil.e('解析阻止的扩展名失败: $e');
      return [];
    }
  }
  
     
  // 统一的协议正则模式
  // static const _protocolPattern = r'(?:https?|rtmp|rtsp|ftp|mms|thunder)';
  static const _protocolPattern = r'(?:https?)';
  
  // 用于检查协议的正则
  static final _protocolRegex = RegExp('${_protocolPattern}://');
  
  /// 全局规则配置字符串，在网页加载多个m3u8的时候，指定只使用符合条件的m3u8
  /// 格式: domain1|keyword1@domain2|keyword2
  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook=';

  /// 特殊规则字符串，用于动态设置监听的文件类型，格式: domain1|fileType1@domain2|fileType2
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4';

  /// 动态关键词规则字符串，符合规则使用getm3u8diy来解析
  static String dynamicKeywordsString = 'jinan@gansu@zhanjiang';

  /// 允许加载的资源模式字符串，用@分隔
  static const String allowedResourcePatternsString = 'r.png?t=perf';

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
  final Set<String> _foundUrls = {};

  /// 定期检查定时器
  Timer? _periodicCheckTimer;

  /// 重试计数器
  int _retryCount = 0;

  /// 检查次数统计
  int _checkCount = 0;

  /// 无效URL关键词
  static const List<String> INVALID_URL_PATTERNS = [
    'advertisement', 'analytics', 'tracker',
    'pixel', 'beacon', 'stats', 'log'
  ];

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
  final Map<String, bool> _pageLoadedStatus = {};

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
      'name': 'WorldTime API',
      'url': 'https://worldtimeapi.org/api/timezone/Asia/Shanghai',
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
  final CancelToken? cancelToken; // 取消令牌
  
  /// 构造函数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 15,
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
      isHashRoute = false;
    }

    // 记录提取到的参数
    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL参数替换规则: from=$fromParam, to=$toParam');
    }
    if (clickText != null) {
      LogUtil.i('检测到点击配置: text=$clickText, index=$clickIndex');
    }
  }

  /// 无效URL检查的正则表达式
  static final _invalidPatternRegex = RegExp(
    INVALID_URL_PATTERNS.join('|'),
    caseSensitive: false
  );

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

  /// 解析动态关键词规则
  static Set<String> _parseKeywords(String keywordsString) {
    if (keywordsString.isEmpty) {
      return {};
    }

    try {
      return keywordsString.split('@').map((keyword) => keyword.trim()).toSet();
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

    try {
      return Map.fromEntries(
        rulesString.split('@').map((rule) {
          final parts = rule.split('|');
          return MapEntry(parts[0].trim(), parts[1].trim());
        }),
      );
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

  /// URL整理
  String _cleanUrl(String url) {
    LogUtil.i('URL整理开始，原始URL: $url');
    
    // 基础清理
    String cleanedUrl = UrlUtils.basicUrlClean(url);

    // 使用单个正则表达式检查URL
    final protocolMatches = _protocolRegex.allMatches(cleanedUrl);
    if (protocolMatches.length == 1) {
      return cleanedUrl;
    }
    
    // 多个协议,尝试提取正确URL
    if (protocolMatches.length > 1) {
      final pattern = '''(?:${_protocolPattern}://|//|/)[^'"\\s,()<>{}\\[\\]]*?\\.${_filePattern}[^'"\\s,()<>{}\\[\\]]*''';
      final urlMatches = RegExp(pattern).allMatches(cleanedUrl);
      if (urlMatches.isNotEmpty) {
        return urlMatches.first.group(0)!;
      }
    }

    // 构建完整 URL
    return UrlUtils.buildFullUrl(cleanedUrl, _parsedUri);
  }
  
  /// 获取时间差（毫秒）
  Future<int> _getTimeOffset() async {
    // 使用缓存优先
    if (_cachedTimeOffset != null) return _cachedTimeOffset!;

    final localTime = DateTime.now();
    // 按顺序尝试多个时间源
    for (final api in TIME_APIS) {
      final networkTime = await _getNetworkTime(api['url']!);
      if (networkTime != null) {
        _cachedTimeOffset = networkTime.difference(localTime).inMilliseconds;
        return _cachedTimeOffset!;
      }
    }
    return 0;
  }

  /// 从指定 API 获取网络时间
  Future<DateTime?> _getNetworkTime(String url) async {
    final response = await HttpUtil().getRequest<String>(
      url,
      retryCount: 1,
    );

    if (response == null) return null;

    try {
      final Map<String, dynamic> data = json.decode(response);

      // 根据不同API返回格式解析时间
      if (url.contains('taobao')) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']['t']));
      } else if (url.contains('suning')) {
        return DateTime.parse(data['sysTime2']);
      } else if (url.contains('worldtimeapi')) {
        return DateTime.parse(data['datetime']);
      } else if (url.contains('meituan')) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']));
      }
    } catch (e) {
      LogUtil.e('解析时间响应失败: $e');
    }
    return null;
  }

  /// 时间拦截器的代码
  String _prepareTimeInterceptorCode() {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) {
      return '(function(){})();';
    }

    return '''
    (function() {
      if (window._timeInterceptorInitialized) return;
      window._timeInterceptorInitialized = true;

      const originalDate = window.Date;
      const timeOffset = ${_cachedTimeOffset};
      let timeRequested = false;

      // 核心时间调整函数
      function getAdjustedTime() {
        if (!timeRequested) {
          timeRequested = true;
          window.TimeCheck.postMessage(JSON.stringify({
            type: 'timeRequest',
            method: 'Date'
          }));
        }
        return new originalDate(new originalDate().getTime() + timeOffset);
      }

      // 代理Date构造函数
      window.Date = function(...args) {
        return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
      };

      // 保持原型链和方法
      window.Date.prototype = originalDate.prototype;
      window.Date.now = () => {
        if (!timeRequested) {
          timeRequested = true;
          window.TimeCheck.postMessage(JSON.stringify({
            type: 'timeRequest',
            method: 'Date.now'
          }));
        }
        return getAdjustedTime().getTime();
      };
      window.Date.parse = originalDate.parse;
      window.Date.UTC = originalDate.UTC;

      // 拦截performance.now
      const originalPerformanceNow = window.performance.now.bind(window.performance);
      let perfTimeRequested = false;
      window.performance.now = () => {
        if (!perfTimeRequested) {
          perfTimeRequested = true;
          window.TimeCheck.postMessage(JSON.stringify({
            type: 'timeRequest',
            method: 'performance.now'
          }));
        }
        return originalPerformanceNow() + timeOffset;
      };

      // 媒体元素时间处理
      let mediaTimeRequested = false;
      function setupMediaElement(element) {
        if (element._timeProxied) return;
        element._timeProxied = true;

        Object.defineProperty(element, 'currentTime', {
          get: () => {
            if (!mediaTimeRequested) {
              mediaTimeRequested = true;
              window.TimeCheck.postMessage(JSON.stringify({
                type: 'timeRequest',
                method: 'media.currentTime'
              }));
            }
            return (element.getRealCurrentTime?.() ?? 0) + (timeOffset / 1000);
          },
          set: value => element.setRealCurrentTime?.(value - (timeOffset / 1000))
        });
      }

      // 监听新媒体元素
      const observer = new MutationObserver(mutations => {
        mutations.forEach(mutation => {
          mutation.addedNodes.forEach(node => {
            if (node instanceof HTMLMediaElement) setupMediaElement(node);
          });
        });
      });

      observer.observe(document.documentElement, {
        childList: true,
        subtree: true
      });

      // 初始化现有媒体元素
      document.querySelectorAll('video,audio').forEach(setupMediaElement);

      // 资源清理
      window._cleanupTimeInterceptor = () => {
        window.Date = originalDate;
        window.performance.now = originalPerformanceNow;
        observer.disconnect();
        delete window._timeInterceptorInitialized;
      };
    })();
    ''';
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
      final httpdata = await HttpUtil().getRequest(url);
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
          final styleEndMatches = RegExp(r'</style>', caseSensitive: false).allMatches(content);
          if (styleEndMatches.isNotEmpty) {
            // 获取最后一个style标签的结束位置
            styleEndIndex = styleEndMatches.last.end;
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

    // 初始化 controller - 已在上方赋值，此处配置
    final List<String> initScripts = [];
    initScripts.add(_prepareTimeInterceptorCode());

    // 添加基础运行时脚本(优先注入)
    initScripts.add('''
      window._videoInit = false;
      window._processedUrls = new Set();
      window._m3u8Found = false;
    ''');

    // M3U8检测器核心脚本
    initScripts.add(_prepareM3U8DetectorCode());

    // 注册时间检查消息通道
    _controller!.addJavaScriptChannel(
      'TimeCheck',
      onMessageReceived: (JavaScriptMessage message) {
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

    // 导航委托
    _controller!.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) async {
          // 页面开始加载时注入检测器
          for (final script in initScripts) {
            await _controller!.runJavaScript(script);
            LogUtil.i('注入脚本成功');
          }
        },
        onNavigationRequest: (NavigationRequest request) async {
          // 检查重定向时是否需要重新注入
          try {
            final currentUri = _parsedUri;
            final newUri = Uri.parse(request.url);
            if (currentUri.host != newUri.host) {
              // 域名发生变化时重新注入所有脚本
              for (final script in initScripts) {
                await _controller!.runJavaScript(script);
              }
              LogUtil.i('重定向页面的拦截器代码已重新注入');
            }
          } catch (e) {
            LogUtil.e('检查重定向URL失败: $e');
          }

          // 导航逻辑
          LogUtil.i('页面导航请求: ${request.url}');
          final uri = Uri.parse(request.url);
          if (uri == null) {
            LogUtil.i('无效的URL，阻止加载');
            return NavigationDecision.prevent;
          }

          // 资源检查逻辑
          try {
            final extension = uri.path.toLowerCase().split('.').last;
            final blockedExtensions = [
              'jpg', 'jpeg', 'png', 'gif', 'webp',
              'css', 'woff', 'woff2', 'ttf', 'eot',
              'ico', 'svg', 'mp3', 'wav',
              'pdf', 'doc', 'docx', 'swf',
            ];

            // 检查是否在阻止列表中
            if (blockedExtensions.contains(extension)) {
              // 检查是否匹配允许的模式
              if (allowedPatterns.any((pattern) => request.url.contains(pattern))) {
                LogUtil.i('允许加载匹配模式的资源: ${request.url}');
                return NavigationDecision.navigate; // 允许加载匹配的资源
              }
              LogUtil.i('阻止加载资源: ${request.url} (扩展名: $extension)');
              return NavigationDecision.prevent; // 阻止其他被屏蔽的资源
            }
          } catch (e) {
            // 获取扩展名失败，跳过扩展名检查
            LogUtil.e('提取扩展名失败: $e');
          }

          // 目标资源检查
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

          return NavigationDecision.navigate;
        },
        
        onPageFinished: (String url) async {
          // 检查此URL是否已经触发过页面加载完成
          if (!isHashRoute && _pageLoadedStatus[url] == true) {
            LogUtil.i('本页面已经加载完成，跳过重复处理');
            return;
          }

          // 标记该URL已处理
          _pageLoadedStatus[url] = true;
          LogUtil.i('页面加载完成: $url');

          // 基础状态检查
          if (_isDisposed || _isClickExecuted) {
            LogUtil.i(_isDisposed ? '资源已释放，跳过处理' : '点击已执行，跳过处理');
            return;
          }

          // 处理hash路由
          try {
            if (isHashRoute) {
              final currentUri = _parsedUri;
              String mapKey = currentUri.toString();
              _pageLoadedStatus.clear();
              _pageLoadedStatus[mapKey] = true;

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
            if (!_isDisposed) {
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
            if (!_isDisposed && !_m3u8Found) {
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
    
    // 点击操作的 JavaScript 代码
    final jsCode = '''
    (async function() {
      try {
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
                  if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return NodeFilter.FILTER_ACCEPT;
                }
                if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
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
            if (node.nodeType === Node.TEXT_NODE) {
              const text = node.textContent.trim();
              if (text === searchText) {
                matches.push({
                  text: text,
                  node: node.parentElement
                });

                if (currentIndex === targetIndex) {
                  foundNode = node.parentElement;
                  break;
                }
                currentIndex++;
              }
            }
            // 处理元素节点
            else if (node.nodeType === Node.ELEMENT_NODE) {
              const children = Array.from(node.childNodes);
              const directText = children
                .filter(child => child.nodeType === Node.TEXT_NODE)
                .map(child => child.textContent.trim())
                .join('');

              if (directText === searchText) {
                matches.push({
                  text: directText,
                  node: node
                });

                if (currentIndex === targetIndex) {
                  foundNode = node;
                  break;
                }
                currentIndex++;
              }
            }
          }

          if (!foundNode) {
            console.error('未找到匹配的元素');
            return;
          }

          try {
            // 优先点击节点本身
            const originalClass = foundNode.getAttribute('class') || '';
            foundNode.click();

            // 等待 500ms 检查 class 是否发生变化
            setTimeout(() => {
              const updatedClass = foundNode.getAttribute('class') || '';
              if (originalClass !== updatedClass) {
                console.info('节点点击成功，class 发生变化');
              } else if (foundNode.parentElement) {
                // 尝试点击父节点
                const parentOriginalClass = foundNode.parentElement.getAttribute('class') || '';
                foundNode.parentElement.click();

                setTimeout(() => {
                  const parentUpdatedClass = foundNode.parentElement.getAttribute('class') || '';
                  if (parentOriginalClass !== parentUpdatedClass) {
                    console.info('父节点点击成功，class 发生变化');
                  } 
                }, 500);
              } 
            }, 500);
          } catch (e) {
            console.error('点击操作失败:', e);
          }
        }
        findAndClick();
      } catch (e) {
        console.error('JavaScript 执行时发生错误:', e);
      }
    })();
    ''';

    try {
      // 执行点击操作
      await _controller!.runJavaScript(jsCode);
      
      // 设置点击完成标记
      _isClickExecuted = true;
      
      // 无论点击结果如何，最终都返回 true，认为点击成功
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
  Timer(const Duration(milliseconds: 3800), () async {
    if (_foundUrls.isNotEmpty) {
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
  if (_retryCount < 2 && !_isDisposed) {
    _retryCount++;
    LogUtil.i('尝试重试 ($_retryCount/2)，延迟1秒');
    await Future.delayed(const Duration(seconds: 1));
    if (!_isDisposed) {
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
  }

  /// 设定定期检查
  void _setupPeriodicCheck() {
    // 如果已经有定时器在运行，或者已释放资源，或者已找到M3U8，则直接返回
    if (_periodicCheckTimer != null || _isDisposed || _m3u8Found) {
      LogUtil.i('跳过定期检查设置: ${_periodicCheckTimer != null ? "定时器已存在" : _isDisposed ? "已释放资源" : "已找到M3U8"}');
      return;
    }

    // 创建新的定期检查定时器
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        // 如果已找到M3U8或已释放资源，取消定时器
        if (_m3u8Found || _isDisposed) {
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
            _injectM3U8Detector();
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
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () async {
      if (_isDisposed || completer.isCompleted) {
        LogUtil.i('${_isDisposed ? "已释放资源" : "已完成处理"}，跳过超时处理');
        return;
      }

      completer.complete('ERROR');
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

  // 清理 URL 相关资源
  _hashFirstLoadMap.remove(Uri.parse(url).toString());
  _periodicCheckTimer?.cancel();
  _periodicCheckTimer = null;

  // 清理 WebView 资源 
  if (_isControllerInitialized && _isHtmlContent && _controller != null) {
    try {
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
  _foundUrls.clear();
  _pageLoadedStatus.clear();
  _httpResponseContent = null;
  _controller = null; // 显式置空
  _m3u8Found = false;
  _isDetectorInjected = false;
  _isControllerInitialized = false;
  _isPageLoadProcessed = false;
  _isClickExecuted = false;

  LogUtil.i('资源释放完成');
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

  /// 注入M3U8检测器
  void _injectM3U8Detector() {
    if (_isDisposed || !_isControllerReady() || _isDetectorInjected) {
      LogUtil.i(_isDisposed ? '资源已释放，跳过注入JS' :
                !_isControllerReady() ? 'WebViewController 未初始化，无法注入JS' :
                'M3U8检测器已注入，跳过重复注入');
      return;
    }

    // 检查检测器是否正常工作
    _controller!.runJavaScript(_prepareM3U8DetectorCode()); // 修改说明：直接注入脚本
    _isDetectorInjected = true; // 修改说明：明确标记注入完成，避免定期检查跳过
    _controller!.runJavaScript('''
      if (window._m3u8DetectorInitialized) {
        checkMediaElements(document);
        efficientDOMScan();
      }
    ''').catchError((error) {
      LogUtil.e('检查M3U8检测器状态失败: $error');
    });
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
