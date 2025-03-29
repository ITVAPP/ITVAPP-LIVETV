import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart'; // 添加 Dio 依赖以使用 CancelToken
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/getm3u8diy.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// URL 处理工具类
class UrlUtils {
  static const _protocolPattern = r'(?:https?)';
  // 将正则表达式提升为静态常量
  static final _escapeRegex = RegExp(r'\\(\|/|")'); // 匹配双反斜杠后跟特殊字符
  static final _multiSlashRegex = RegExp(r'/{3,}'); // 处理3+连续斜杠
  static final _htmlEntityRegex = RegExp(r'&(#?[a-z0-9]+);'); // HTML实体匹配
  static final _unicodeRegex = RegExp(r'\u([0-9a-fA-F]{4})'); // Unicode匹配

  /// 基础 URL 解码和清理
  static String basicUrlClean(String url) {
    // 去除末尾反斜杠
    if (url.endsWith(r'\')) {
      url = url.substring(0, url.length - 1);
    }

    const htmlEntities = {
      'amp': '&',
      'quot': '"',
      '#x2F': '/',
      '#47': '/',
      'lt': '<',
      'gt': '>'
    };

    // 合并多次字符串替换操作，提升性能，减少内存分配
    url = url
        .replaceAllMapped(_escapeRegex, (match) => match.group(1)!) // 提取第二个反斜杠或特殊字符
        .replaceAll(r'\/', '/') // 单独处理JavaScript转义斜杠
        .replaceAllMapped(_htmlEntityRegex, (m) => htmlEntities[m.group(1)] ?? m.group(0)!) // HTML实体替换
        .trim() // 清除首尾空格
        .replaceAll(_multiSlashRegex, '/'); // 处理3+连续斜杠

    // 只处理明确的 Unicode 转义（如 \uCH71）
    if (url.contains(r'\u')) {
      url = url.replaceAllMapped(_unicodeRegex, (match) => _parseUnicode(match.group(1)));
      LogUtil.i('Unicode 转换后: $url');
    }

    // 仅在必要时解码，且只解码一次
    if (url.contains('%')) {
      try {
        url = Uri.decodeComponent(url);
      } catch (e) {
        LogUtil.i('URL解码失败，保持原样: $e');
      }
    }

    return url;
  }

  static String _parseUnicode(String? hex) {
    try {
      return String.fromCharCode(int.parse(hex!, radix: 16));
    } catch (e) {
      return hex ?? '';
    }
  }

  /// 构建完整 URL
  static String buildFullUrl(String path, Uri baseUri) {
    if (RegExp('^${_protocolPattern}://').hasMatch(path)) {
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
    return RegExp('$_protocolPattern://').hasMatch(url);
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
  // 无效URL关键词的正则表达式
  static final _invalidPatternRegex = RegExp(
    'advertisement|analytics|tracker|pixel|beacon|stats|log',
    caseSensitive: false,
  );

  /// 全局规则配置字符串，在网页加载多个m3u8的时候，指定只使用符合条件的m3u8
  /// 格式: domain1|keyword1@domain2|keyword2
  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook=';

  /// 特殊规则字符串，用于动态设置监听的文件类型，格式: domain1|fileType1@domain2|fileType2
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4';

  /// 动态关键词规则字符串，符合规则使用getm3u8diy来解析
  static String dynamicKeywordsString = 'jinan@gansu@zhanjiang';

  /// 允许加载的资源模式字符串，用@分隔
  static const String allowedResourcePatternsString = 'r.png?t=';

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

  /// 检查次数统计
  int _checkCount = 0;

  /// 规则列表
  final List<M3U8FilterRule> _filterRules;

  /// 标记点击是否已执行
  bool _isClickExecuted = false;

  /// 初始化状态标记
  bool _isControllerInitialized = false;

  /// 当前检测的文件类型
  String _filePattern = 'm3u8'; // 将默认值移到类级别初始化，避免混淆后未赋值

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

  /// 解析后的URI对象
  late final Uri _parsedUri;

  /// 添加 CancelToken 用于取消 HTTP 请求
  final CancelToken? cancelToken;

  /// 添加释放状态标志位
  bool _isDisposed = false;

  /// 构造函数，新增 cancelToken 参数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 15,
    this.cancelToken, // 新增可选参数
  }) : _filterRules = _parseRules(rulesString),
        // 初始化成员变量
        fromParam = _extractQueryParams(url)['from'],
        toParam = _extractQueryParams(url)['to'],
        clickText = _extractQueryParams(url)['clickText'],
        clickIndex = int.tryParse(_extractQueryParams(url)['clickIndex'] ?? '') ?? 0 {
    // 在构造函数中初始化 _controller，避免 LateInitializationError
    _controller = WebViewController();

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
    return rulesString.split('@').where((rule) => rule.isNotEmpty).map(M3U8FilterRule.fromString).toList();
  }

  /// 解析动态关键词规则
  static Set<String> _parseKeywords(String keywordsString) {
    return keywordsString.split('@').map((keyword) => keyword.trim()).toSet();
  }

  /// 解析特殊规则字符串，返回 Map，其中键是域名，值是文件类型
  static Map<String, String> _parseSpecialRules(String rulesString) {
    return Map.fromEntries(rulesString.split('@').map((rule) => MapEntry(rule.split('|')[0].trim(), rule.split('|')[1].trim())));
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
    String cleanedUrl = UrlUtils.basicUrlClean(url);
    return UrlUtils.hasValidProtocol(cleanedUrl) ? cleanedUrl : UrlUtils.buildFullUrl(cleanedUrl, _parsedUri);
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
      cancelToken: cancelToken, // 使用传入的 cancelToken
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

  /// 时间拦截器代码，从外部加载
  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) {
      return '(function(){})();';
    }
    final script = await rootBundle.loadString('assets/js/time_interceptor.js');
    return script.replaceAll('TIME_OFFSET', '$_cachedTimeOffset');
  }

  /// 检查取消状态的工具方法，仅依赖 cancelToken
  bool _isCancelled() {
    return cancelToken?.isCancelled ?? false;
  }

  /// 初始化WebViewController
  Future<void> _initController(Completer<String> completer, String filePattern) async {
    if (_isCancelled()) {
      LogUtil.i('初始化控制器前任务被取消');
      completer.complete('ERROR');
      return;
    }

    try {
      LogUtil.i('开始初始化控制器');

      // 设置 _isControllerInitialized，确保状态正确
      _isControllerInitialized = true;

      // 检查页面内容类型
      try {
        final httpdata = await HttpUtil().getRequest(
          url,
          cancelToken: cancelToken, // 使用传入的 cancelToken
        );
        if (_isCancelled()) {
          LogUtil.i('HTTP 请求完成后任务被取消');
          completer.complete('ERROR');
          return;
        }
        if (httpdata != null) {
          // 存储响应内容并判断是否为HTML
          _httpResponseContent = httpdata.toString();
          _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || _httpResponseContent!.contains('<html');
          LogUtil.i('HTTP响应内容类型: ${_isHtmlContent ? 'HTML' : '非HTML'}, 当前内容: $_httpResponseContent');

          // 如果是 HTML 内容,先进行内容检查
          if (_isHtmlContent) {
            String content = _httpResponseContent!;
            int styleEndIndex = -1;
            final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
            if (styleEndMatch != null) {
              // 获取第一个style标签的结束位置
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

            if (initialContent.contains('.' + filePattern)) { // 快速预检
              final result = await _checkPageContent();
              if (result != null) {
                completer.complete(result);
                return;
              }
            }
          }
        } else {
          LogUtil.e('HttpUtil请求失败，未获取到数据，将继续尝试WebView加载');
          _httpResponseContent = null;
          _isHtmlContent = true; // 默认当作HTML内容处理
        }
      } catch (e) {
        if (_isCancelled()) {
          LogUtil.i('HTTP 请求失败后任务被取消');
          completer.complete('ERROR');
          return;
        }
        LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true; // 默认当作HTML内容处理
      }

      // 非HTML内容直接处理
      if (!isHashRoute && !_isHtmlContent) {
        LogUtil.i('检测到非HTML内容，直接处理');
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

      // 初始化 controller
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);

      // 检查内容和准备脚本
      final List<String> initScripts = [];
      final timeInterceptorCode = await _prepareTimeInterceptorCode();
      initScripts.add(timeInterceptorCode);
      initScripts.add('''
window._videoInit = false;
window._processedUrls = new Set();
window._m3u8Found = false;
''');
      final m3u8DetectorCode = await _prepareM3U8DetectorCode();
      initScripts.add(m3u8DetectorCode);

      // 定义脚本名称映射，便于日志记录
      final scriptNames = [
        '时间拦截器脚本 (time_interceptor.js)',
        '点击处理脚本 (click_handler.js)',
        'M3U8检测器脚本 (m3u8_detector.js)',
      ];

      // 注册时间检查消息通道
      _controller.addJavaScriptChannel(
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

      // M3U8Detector 通道
      _controller.addJavaScriptChannel(
        'M3U8Detector',
        onMessageReceived: (JavaScriptMessage message) {
          if (_isCancelled()) return;
          try {
            final data = json.decode(message.message);
            _handleM3U8Found(data['type'] == 'init' ? null : (data['url'] ?? message.message), completer);
          } catch (e) {
            _handleM3U8Found(message.message, completer);
          }
        },
      );

      // 解析允许的资源模式
      final allowedPatterns = _parseAllowedPatterns(allowedResourcePatternsString);

      // 导航委托
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) async {
            if (_isCancelled()) {
              LogUtil.i('页面开始加载时任务被取消: $url');
              return;
            }
            for (int i = 0; i < initScripts.length; i++) {
              await _controller.runJavaScript(initScripts[i]);
              LogUtil.i('注入脚本成功: ${scriptNames[i]}');
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            if (_isCancelled()) {
              LogUtil.i('导航请求时任务被取消: ${request.url}');
              return NavigationDecision.prevent;
            }
            try {
              final currentUri = _parsedUri;
              final newUri = Uri.parse(request.url);
              if (currentUri.host != newUri.host) {
                // 域名发生变化时重新注入所有脚本
                for (int i = 0; i < initScripts.length; i++) {
                  await _controller.runJavaScript(initScripts[i]);
                  LogUtil.i('重定向页面注入脚本成功: ${scriptNames[i]}');
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
                _controller.runJavaScript(
                  'window.M3U8Detector?.postMessage(${json.encode({
                    'type': 'url',
                    'url': request.url,
                    'source': 'navigation'
                  })});'
                ).catchError(() {});
                return NavigationDecision.prevent;
              }
            } catch (e) {
              LogUtil.e('URL检查失败: $e');
            }

            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) async {
            if (_isCancelled()) {
              LogUtil.i('页面加载完成时任务被取消: $url');
              return;
            }
            // 避免重复状态管理
            if (!isHashRoute && _pageLoadedStatus[url] == true) {
              LogUtil.i('本页面已经加载完成，跳过重复处理');
              return;
            }

            // 标记该URL已处理
            _pageLoadedStatus[url] = true;
            LogUtil.i('页面加载完成: $url');

            // 基础状态检查
            if (_isClickExecuted) {
              LogUtil.i('点击已执行，跳过处理');
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
              if (!_isCancelled()) {
                final clickResult = await _executeClick();
                if (clickResult) {
                  _startUrlCheckTimer(completer);
                }
              }
            }

            // 首次加载处理
            if (!_isCancelled() && !_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
              _setupPeriodicCheck();
            }
          },
          onWebResourceError: (WebResourceError error) async {
            if (_isCancelled()) {
              LogUtil.i('资源错误时任务被取消: ${error.description}');
              return;
            }
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
      _isControllerInitialized = true; // 即使失败也设置状态，避免后续检查失败
      await _handleLoadError(completer);
    }
  }

  /// 点击操作执行，从外部加载JS
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

    final jsCode = await rootBundle.loadString('assets/js/click_handler.js');
    final scriptWithParams = jsCode
        .replaceAll('SEARCH_TEXT', clickText!) // 替换占位符
        .replaceAll('TARGET_INDEX', '$clickIndex');

    try {
      await _controller.runJavaScript(scriptWithParams);
      _isClickExecuted = true;
      LogUtil.i('点击操作执行完成，结果: 成功');
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _isClickExecuted = true;
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
    if (_retryCount < 2 && !_isCancelled()) {
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/2)，延迟1秒');
      await Future.delayed(const Duration(seconds: 1));
      if (!_isCancelled()) {
        // 重置页面加载处理标记和点击执行标记
        _pageLoadedStatus.clear(); // 清理加载状态
        _isClickExecuted = false; // 重置点击状态，允许重试时重新点击
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
      await _controller.loadRequest(_parsedUri, headers: headers);
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      // 避免无声失败导致导航未触发
      throw Exception('URL 加载失败: $e');
    }
  }

  /// 检查控制器是否准备就绪
  bool _isControllerReady() {
    if (!_isControllerInitialized || _isCancelled()) {
      LogUtil.i('Controller 未初始化或任务已取消，操作跳过');
      return false;
    }
    return true;
  }

  /// 重置控制器状态
  void _resetControllerState() {
    _isControllerInitialized = false;
    _isClickExecuted = false;
    _m3u8Found = false;
  }

  /// 定期检查，从外部加载M3U8检测器
  void _setupPeriodicCheck() {
    if (_periodicCheckTimer != null || _isCancelled() || _m3u8Found) {
      LogUtil.i('跳过定期检查设置: ${_periodicCheckTimer != null ? "定时器已存在" : _isCancelled() ? "任务被取消" : "已找到M3U8"}');
      return;
    }

    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
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
          await _controller.runJavaScript('''
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

  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () async {
      if (_isCancelled() || completer.isCompleted) {
        LogUtil.i('${_isCancelled() ? "任务已取消" : "已完成处理"}，跳过超时处理');
        return;
      }

      completer.complete('ERROR');
      await dispose();
    });
  }

  /// 释放资源，增强取消能力
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    // 取消所有未完成的 HTTP 请求
    if (cancelToken != null && !cancelToken!.isCancelled) {
      cancelToken!.cancel('GetM3U8 disposed');
      LogUtil.i('已取消所有未完成的 HTTP 请求');
    }

    // 彻底清理所有集合，优化内存使用
    _hashFirstLoadMap.remove(Uri.parse(url).toString());
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    _foundUrls.clear();
    _pageLoadedStatus.clear();

    // 清理 WebView 资源
    if (_isControllerInitialized) {
      await disposeWebView(_controller);
    } else {
      LogUtil.i('WebViewController 未初始化，跳过清理');
    }

    // 重置状态并清理集合
    _resetControllerState();
    _httpResponseContent = null;
    _m3u8Found = false;
    _isControllerInitialized = false;
    _isClickExecuted = false;
    LogUtil.i('资源释放完成: ${DateTime.now()}'); // 添加结束时间戳
  }

  /// 清理 WebView 相关活动
  Future<void> disposeWebView(WebViewController controller) async {
    try {
      // 1. 重置导航委托，避免后续加载触发旧回调
      await controller.setNavigationDelegate(NavigationDelegate());
      LogUtil.i('导航委托已重置为默认');

      // 2. 加载空白页面，清空内容并中断加载
      await controller.loadRequest(Uri.parse('about:blank'));
      LogUtil.i('已加载空白页面，清空内容并中断加载');

      // 3. 清理 JS 和动态行为
      if (_isHtmlContent) {
        await controller.runJavaScript('''
window.stop(); // 停止页面加载和 JS 执行
document.documentElement.innerHTML = ''; // 清空整个 HTML
window.onload = null; // 移除 onload 事件
window.onerror = null; // 移除错误处理
// 清理所有定时器和间隔器
(function() {
var ids = Object.keys(window).filter(k => typeof window[k] === 'number' && window[k] > 0);
ids.forEach(id => { clearTimeout(id); clearInterval(id); });
})();
// 移除所有事件监听器
window.removeEventListener('load', null, true);
window.removeEventListener('unload', null, true);
''');
        LogUtil.i('已清理 JS 和动态行为');
      }

      // 4. 清理缓存和存储
      await controller.clearCache();
      await controller.clearLocalStorage();
      LogUtil.i('已清理缓存和本地存储');
    } catch (e, stack) {
      LogUtil.logError('清理 WebView 时发生错误', e, stack);
    }
  }

  /// 验证M3U8 URL是否有效
  bool _isValidM3U8Url(String url) {
    // 使用缓存避免重复验证
    if (_foundUrls.contains(url)) {
      return false;
    }

    // 快速预检查，减少正则表达式使用
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

    // 检查无效关键词
    if (_invalidPatternRegex.hasMatch(lowercaseUrl)) {
      LogUtil.i('URL包含无效关键词');
      return false;
    }

    // 规则检查的短路处理
    if (_filterRules.isNotEmpty) {
      bool matchedDomain = false;
      for (final rule in _filterRules) {
        if (url.contains(rule.domain)) {
          matchedDomain = true;
          final containsKeyword = url.contains(rule.requiredKeyword);
          return containsKeyword;
        }
      }
      if (matchedDomain) return false;
    }

    return true;
  }

  /// 处理发现的M3U8 URL
  Future<void> _handleM3U8Found(String? url, Completer<String> completer) async {
    if (_m3u8Found || _isCancelled() || url == null || url.isEmpty) {
      return;
    }

    // 首先整理URL
    String cleanedUrl = _cleanUrl(url);
    if (!_isValidM3U8Url(cleanedUrl)) {
      return; // URL验证失败，继续等待新的URL
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
          return streamUrl; // 直接返回，不执行后续 WebView 解析
        } catch (e, stackTrace) {
          LogUtil.logError('getm3u8diy 获取播放地址失败，返回 ERROR', e, stackTrace);
          return 'ERROR'; // 失败也直接返回，终止后续逻辑
        }
      }
    }

    // 动态解析特殊规则
    final specialRules = _parseSpecialRules(specialRulesString);
    _filePattern = specialRules.entries
        .firstWhere(
          (entry) => url.contains(entry.key),
          orElse: () => const MapEntry('', 'm3u8')
        )
        .value;
    LogUtil.i('检测模式: ${_filePattern == "m3u8" ? "仅监听m3u8" : "监听$_filePattern"}');

    try {
      await _initController(completer, _filePattern);
      _startTimeout(completer);
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      completer.complete('ERROR');
    }

    LogUtil.i('getUrl方法执行完成');
    return completer.future;
  }

  /// 检查页面内容中的M3U8地址
  Future<String?> _checkPageContent() async {
    if (_m3u8Found || _isCancelled()) {
      LogUtil.i(
        '跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "任务被取消"}'
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
      final pattern = '''(?:${UrlUtils._protocolPattern}://|//|/)[^'"\\s,()<>{}\\[\\]]*?\\.${_filePattern}[^'"\\s,()<>{}\\[\\]]*''';
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

    final validUrls = <String>[]; // 存储有效URL
    for (final url in uniqueUrls) {
      final cleanedUrl = _cleanUrl(url);
      if (_isValidM3U8Url(cleanedUrl)) {
        String finalUrl = cleanedUrl;
        if (fromParam != null && toParam != null) {
          finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
        }
        validUrls.add(finalUrl); // 添加到有效URL列表
      }
    }

    if (validUrls.isEmpty) {
      return null; // 无有效URL
    }

    // 如果 clickIndex 在范围内，返回对应URL；否则返回第一个
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

  /// 准备M3U8检测器代码，从外部加载
  Future<String> _prepareM3U8DetectorCode() async {
    final script = await rootBundle.loadString('assets/js/m3u8_detector.js');
    return script.replaceAll('FILE_PATTERN', _filePattern);
  }
}
