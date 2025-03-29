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

/// URL 处理工具类
class UrlUtils {
  static const _protocolPattern = r'(?:https?)';
  static final _escapeRegex = RegExp(r'\\(\|/|")');
  static final _multiSlashRegex = RegExp(r'/{3,}');
  static final _htmlEntityRegex = RegExp(r'&(#?[a-z0-9]+);');
  static final _unicodeRegex = RegExp(r'\u([0-9a-fA-F]{4})');

  static final Map<String, String> _urlCleanCache = {};

  static String basicUrlClean(String url) {
    if (_urlCleanCache.containsKey(url)) {
      return _urlCleanCache[url]!;
    }

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

    final combinedRegex = RegExp(
      r'\\(\|/|")|\/|&(#?[a-z0-9]+);|/{3,}|\u([0-9a-fA-F]{4})',
      multiLine: true,
    );
    url = url.replaceAllMapped(combinedRegex, (match) {
      final group = match.group(0)!;
      if (group.startsWith(r'\\')) {
        return match.group(1)!;
      } else if (group == r'\/') {
        return '/';
      } else if (group.startsWith('&')) {
        return htmlEntities[match.group(1)] ?? group;
      } else if (group.startsWith('///')) {
        return '/';
      } else if (group.startsWith(r'\u')) {
        return _parseUnicode(match.group(1));
      }
      return group;
    }).trim();

    if (url.contains('%')) {
      try {
        url = Uri.decodeComponent(url);
      } catch (e) {
        LogUtil.i('URL解码失败，保持原样: $e');
      }
    }

    _urlCleanCache[url] = url;
    return url;
  }

  static String _parseUnicode(String? hex) {
    try {
      return String.fromCharCode(int.parse(hex!, radix: 16));
    } catch (e) {
      return hex ?? '';
    }
  }

  static String buildFullUrl(String path, Uri baseUri) {
    if (RegExp('^${_protocolPattern}://').hasMatch(path)) {
      return path;
    }

    if (path.startsWith('//')) {
      return '${baseUri.scheme}://${path.replaceFirst('//', '')}';
    }

    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '${baseUri.scheme}://${baseUri.host}/$cleanPath';
  }

  static bool hasValidProtocol(String url) {
    return RegExp('$_protocolPattern://').hasMatch(url);
  }
}

/// M3U8过滤规则配置
class M3U8FilterRule {
  final String domain;
  final String requiredKeyword;

  const M3U8FilterRule({
    required this.domain,
    required this.requiredKeyword,
  });

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
  static final _invalidPatternRegex = RegExp(
    'advertisement|analytics|tracker|pixel|beacon|stats|log',
    caseSensitive: false,
  );

  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com@tvlive.yntv.cn|chunks_dvr_range@appwuhan.com|playlist.m3u8@hbtv.com.cn/new-|aalook=';
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4';
  static String dynamicKeywordsString = 'jinan@gansu@zhanjiang';
  static const String allowedResourcePatternsString = 'r.png?t=';

  final String url;
  final String? fromParam;
  final String? toParam;
  final String? clickText;
  final int clickIndex;
  final int timeoutSeconds;

  late WebViewController _controller;
  bool _m3u8Found = false;
  // 修复：显式指定类型为 _LimitedSet<String>
  final Set<String> _foundUrls = _LimitedSet<String>(100);
  Timer? _periodicCheckTimer;
  int _retryCount = 0;
  int _checkCount = 0;
  final List<M3U8FilterRule> _filterRules;
  bool _isClickExecuted = false;
  bool _isControllerInitialized = false;
  String _filePattern = 'm3u8';
  static final Map<String, int> _hashFirstLoadMap = {};
  bool isHashRoute = false;
  bool _isHtmlContent = false;
  String? _httpResponseContent;
  static int? _cachedTimeOffset;
  // 修复：显式指定类型为 _LimitedMap<String, bool>
  final Map<String, bool> _pageLoadedStatus = _LimitedMap<String, bool>(100);

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

  late final Uri _parsedUri;
  final CancelToken? cancelToken;
  bool _isDisposed = false;
  static final Map<String, String> _scriptCache = {};

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
      _parsedUri = Uri.parse(url);
      isHashRoute = _parsedUri.fragment.isNotEmpty;
    } catch (e) {
      LogUtil.e('解析URL失败: $e');
      isHashRoute = false;
    }

    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL参数替换规则: from=$fromParam, to=$toParam');
    }
    if (clickText != null) {
      LogUtil.i('检测到点击配置: text=$clickText, index=$clickIndex');
    }
  }

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

  static List<T> _parseStringList<T>(String input, T Function(String) parser, {String separator = '@'}) {
    return input.split(separator).where((item) => item.isNotEmpty).map(parser).toList();
  }

  static List<M3U8FilterRule> _parseRules(String rulesString) {
    return _parseStringList(rulesString, M3U8FilterRule.fromString);
  }

  static Set<String> _parseKeywords(String keywordsString) {
    return _parseStringList(keywordsString, (s) => s.trim()).toSet();
  }

  static Map<String, String> _parseSpecialRules(String rulesString) {
    return Map.fromEntries(
      _parseStringList(rulesString, (rule) {
        final parts = rule.split('|');
        return MapEntry(parts[0].trim(), parts[1].trim());
      }),
    );
  }

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

  String _cleanUrl(String url) {
    String cleanedUrl = UrlUtils.basicUrlClean(url);
    return UrlUtils.hasValidProtocol(cleanedUrl) ? cleanedUrl : UrlUtils.buildFullUrl(cleanedUrl, _parsedUri);
  }

  Future<int> _getTimeOffset() async {
    if (_cachedTimeOffset != null) return _cachedTimeOffset!;

    final localTime = DateTime.now();
    final futures = TIME_APIS.map((api) => _getNetworkTime(api['url']!).timeout(Duration(seconds: 5), onTimeout: () => null)).toList();
    final results = await Future.wait(futures);

    for (final networkTime in results) {
      if (networkTime != null) {
        _cachedTimeOffset = networkTime.difference(localTime).inMilliseconds;
        return _cachedTimeOffset!;
      }
    }
    return 0;
  }

  Future<DateTime?> _getNetworkTime(String url) async {
    final response = await HttpUtil().getRequest<String>(
      url,
      retryCount: 1,
      cancelToken: cancelToken,
    );

    if (response == null) return null;

    try {
      final Map<String, dynamic> data = json.decode(response);

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

  Future<String> _prepareTimeInterceptorCode() async {
    if (_cachedTimeOffset == null || _cachedTimeOffset == 0) {
      return '(function(){})();';
    }
    const scriptKey = 'time_interceptor.js';
    final cacheKey = '$scriptKey:$_cachedTimeOffset';
    if (_scriptCache.containsKey(cacheKey)) {
      return _scriptCache[cacheKey]!;
    }
    final script = await rootBundle.loadString('assets/js/$scriptKey');
    final result = script.replaceAll('TIME_OFFSET', '$_cachedTimeOffset');
    _scriptCache[cacheKey] = result;
    return result;
  }

  bool _isCancelled() {
    return cancelToken?.isCancelled ?? false;
  }

  Future<void> _initController(Completer<String> completer, String filePattern) async {
    if (_isCancelled()) {
      LogUtil.i('初始化控制器前任务被取消');
      completer.complete('ERROR');
      return;
    }

    try {
      LogUtil.i('开始初始化控制器');

      _setControllerState(initialized: true);

      if (!_isControllerInitialized) {
        _controller = WebViewController();
      }

      try {
        final httpdata = await HttpUtil().getRequest(
          url,
          cancelToken: cancelToken,
        );
        if (_isCancelled()) {
          LogUtil.i('HTTP 请求完成后任务被取消');
          completer.complete('ERROR');
          return;
        }
        if (httpdata != null) {
          _httpResponseContent = httpdata.toString();
          _isHtmlContent = _httpResponseContent!.contains('<!DOCTYPE html>') || _httpResponseContent!.contains('<html');
          LogUtil.i('HTTP响应内容类型: ${_isHtmlContent ? 'HTML' : '非HTML'}, 当前内容: $_httpResponseContent');

          if (_isHtmlContent) {
            String content = _httpResponseContent!;
            int styleEndIndex = -1;
            final styleEndMatch = RegExp(r'</style>', caseSensitive: false).firstMatch(content);
            if (styleEndMatch != null) {
              styleEndIndex = styleEndMatch.end;
            }

            String initialContent;
            if (styleEndIndex > 0) {
              final startIndex = styleEndIndex;
              final endIndex = startIndex + 38888 > content.length ? content.length : startIndex + 38888;
              initialContent = content.substring(startIndex, endIndex);
            } else {
              initialContent = content.length > 38888 ? content.substring(0, 38888) : content;
            }

            if (initialContent.contains('.' + filePattern)) {
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
          _isHtmlContent = true;
        }
      } catch (e) {
        if (_isCancelled()) {
          LogUtil.i('HTTP 请求失败后任务被取消');
          completer.complete('ERROR');
          return;
        }
        LogUtil.e('HttpUtil请求发生异常: $e，将继续尝试WebView加载');
        _httpResponseContent = null;
        _isHtmlContent = true;
      }

      if (!isHashRoute && !_isHtmlContent) {
        LogUtil.i('检测到非HTML内容，直接处理');
        _setControllerState(initialized: true);
        final result = await _checkPageContent();
        if (result != null) {
          completer.complete(result);
          return;
        }
        completer.complete('ERROR');
        return;
      }

      _cachedTimeOffset ??= await _getTimeOffset();

      _controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);

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

      final scriptNames = [
        '时间拦截器脚本 (time_interceptor.js)',
        '点击处理脚本 (click_handler.js)',
        'M3U8检测器脚本 (m3u8_detector.js)',
      ];

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

      final allowedPatterns = _parseAllowedPatterns(allowedResourcePatternsString);

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
                for (int i = 0; i < initScripts.length; i++) {
                  await _controller.runJavaScript(initScripts[i]);
                  LogUtil.i('重定向页面注入脚本成功: ${scriptNames[i]}');
                }
                LogUtil.i('重定向页面的拦截器代码已重新注入');
              }
            } catch (e) {
              LogUtil.e('检查重定向URL失败: $e');
            }

            LogUtil.i('页面导航请求: ${request.url}');
            final uri = Uri.parse(request.url);
            if (uri == null) {
              LogUtil.i('无效的URL，阻止加载');
              return NavigationDecision.prevent;
            }

            try {
              final extension = uri.path.toLowerCase().split('.').last;
              final blockedExtensions = [
                'jpg', 'jpeg', 'png', 'gif', 'webp',
                'css', 'woff', 'woff2', 'ttf', 'eot',
                'ico', 'svg', 'mp3', 'wav',
                'pdf', 'doc', 'docx', 'swf',
              ];

              if (blockedExtensions.contains(extension)) {
                if (allowedPatterns.any((pattern) => request.url.contains(pattern))) {
                  LogUtil.i('允许加载匹配模式的资源: ${request.url}');
                  return NavigationDecision.navigate;
                }
                LogUtil.i('阻止加载资源: ${request.url} (扩展名: $extension)');
                return NavigationDecision.prevent;
              }
            } catch (e) {
              LogUtil.e('提取扩展名失败: $e');
            }

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
            if (!isHashRoute && _pageLoadedStatus[url] == true) {
              LogUtil.i('本页面已经加载完成，跳过重复处理');
              return;
            }

            _pageLoadedStatus[url] = true;
            LogUtil.i('页面加载完成: $url');

            if (_isClickExecuted) {
              LogUtil.i('点击已执行，跳过处理');
              return;
            }

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

            if (!_isClickExecuted && clickText != null) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (!_isCancelled()) {
                final clickResult = await _executeClick();
                if (clickResult) {
                  _startUrlCheckTimer(completer);
                }
              }
            }

            if (!_isCancelled() && !_m3u8Found && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
              _setupPeriodicCheck();
            }
          },
          onWebResourceError: (WebResourceError error) async {
            if (_isCancelled()) {
              LogUtil.i('资源错误时任务被取消: ${error.description}');
              return;
            }
            if (error.errorCode == -1 || error.errorCode == -6 || error.errorCode == -7) {
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
      _setControllerState(initialized: true);
      await _handleLoadError(completer);
    }
  }

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

    const scriptKey = 'click_handler.js';
    final cacheKey = '$scriptKey:$clickText:$clickIndex';
    String scriptWithParams;
    if (_scriptCache.containsKey(cacheKey)) {
      scriptWithParams = _scriptCache[cacheKey]!;
    } else {
      final jsCode = await rootBundle.loadString('assets/js/$scriptKey');
      scriptWithParams = jsCode
          .replaceAll('SEARCH_TEXT', clickText!)
          .replaceAll('TARGET_INDEX', '$clickIndex');
      _scriptCache[cacheKey] = scriptWithParams;
    }

    try {
      await _controller.runJavaScript(scriptWithParams);
      _setControllerState(clickExecuted: true);
      LogUtil.i('点击操作执行完成，结果: 成功');
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _setControllerState(clickExecuted: true);
      return true;
    }
  }

  void _startUrlCheckTimer(Completer<String> completer) {
    Timer(const Duration(milliseconds: 3800), () async {
      if (_foundUrls.isNotEmpty) {
        _m3u8Found = true;

        String selectedUrl;
        final urlsList = _foundUrls.toList();

        if (clickIndex == 0 || clickIndex >= urlsList.length) {
          selectedUrl = urlsList.last;
          LogUtil.i('使用最后发现的URL: $selectedUrl ${clickIndex >= urlsList.length ? "(clickIndex 超出范围)" : "(clickIndex = 0)"}');
        } else {
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

  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_retryCount < 2 && _isActive()) {
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/2)，延迟1秒');
      await Future.delayed(const Duration(seconds: 1));
      if (_isActive()) {
        _pageLoadedStatus.clear();
        _setControllerState(clickExecuted: false);
        await _initController(completer, _filePattern);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或任务已取消');
      completer.complete('ERROR');
      await dispose();
    }
  }

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
      throw Exception('URL 加载失败: $e');
    }
  }

  bool _isControllerReady() {
    if (!_isActive()) {
      LogUtil.i('Controller 未初始化或任务已取消，操作跳过');
      return false;
    }
    return true;
  }

  bool _isActive() {
    return _isControllerInitialized && !_isDisposed && !_isCancelled();
  }

  void _setControllerState({bool? initialized, bool? clickExecuted, bool? m3u8Found}) {
    if (initialized != null) _isControllerInitialized = initialized;
    if (clickExecuted != null) _isClickExecuted = clickExecuted;
    if (m3u8Found != null) _m3u8Found = m3u8Found;
  }

  void _resetControllerState() {
    _setControllerState(initialized: false, clickExecuted: false, m3u8Found: false);
  }

  void _setupPeriodicCheck() {
    // 修复：将 Concealer 改为 null
    if (_periodicCheckTimer != null || !_isActive() || _m3u8Found) {
      LogUtil.i('跳过定期检查设置: ${_periodicCheckTimer != null ? "定时器已存在" : !_isActive() ? "任务被取消或未初始化" : "已找到M3U8"}');
      return;
    }

    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        if (_m3u8Found || !_isActive()) {
          timer.cancel();
          _periodicCheckTimer = null;
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "任务被取消或未初始化"}');
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

  void _startTimeout(Completer<String> completer) {
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () async {
      if (!_isActive() || completer.isCompleted) {
        LogUtil.i('${!_isActive() ? "任务已取消或未初始化" : "已完成处理"}，跳过超时处理');
        return;
      }

      completer.complete('ERROR');
      await dispose();
    });
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    if (cancelToken != null && !cancelToken!.isCancelled) {
      cancelToken!.cancel('GetM3U8 disposed');
      LogUtil.i('已取消所有未完成的 HTTP 请求');
    }

    _hashFirstLoadMap.remove(Uri.parse(url).toString());
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    _foundUrls.clear();
    _pageLoadedStatus.clear();
    _scriptCache.clear();

    if (_isControllerInitialized) {
      await disposeWebView(_controller);
    } else {
      LogUtil.i('WebViewController 未初始化，跳过清理');
    }

    _resetControllerState();
    _httpResponseContent = null;
    LogUtil.i('资源释放完成: ${DateTime.now()}');
  }

  Future<void> disposeWebView(WebViewController controller) async {
    try {
      await controller.setNavigationDelegate(NavigationDelegate());
      LogUtil.i('导航委托已重置为默认');

      await controller.loadRequest(Uri.parse('about:blank'));
      LogUtil.i('已加载空白页面，清空内容并中断加载');

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
''');
        LogUtil.i('已清理 JS 和动态行为');
      }

      await controller.clearCache();
      await controller.clearLocalStorage();
      LogUtil.i('已清理缓存和本地存储');
    } catch (e, stack) {
      LogUtil.logError('清理 WebView 时发生错误', e, stack);
    }
  }

  bool _isValidM3U8Url(String url) {
    if (_foundUrls.contains(url)) {
      return false;
    }

    final lowercaseUrl = url.toLowerCase();
    if (!lowercaseUrl.contains('.' + _filePattern)) {
      LogUtil.i('URL不包含.$_filePattern扩展名');
      return false;
    }

    if (_invalidPatternRegex.hasMatch(lowercaseUrl)) {
      LogUtil.i('URL包含无效关键词');
      return false;
    }

    final validUrl = _parsedUri;
    if (validUrl == null) {
      LogUtil.i('无效的URL格式');
      return false;
    }

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

  Future<void> _handleM3U8Found(String? url, Completer<String> completer) async {
    if (_m3u8Found || !_isActive() || url == null || url.isEmpty) {
      return;
    }

    String cleanedUrl = _cleanUrl(url);
    if (!_isValidM3U8Url(cleanedUrl)) {
      return;
    }

    String finalUrl = cleanedUrl;
    if (fromParam != null && toParam != null) {
      LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
      finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
    }

    _foundUrls.add(finalUrl);

    if (clickText == null) {
      _setControllerState(m3u8Found: true);
      if (!completer.isCompleted) {
        LogUtil.i('发现有效URL: $finalUrl');
        completer.complete(finalUrl);
        await dispose();
      }
    } else {
      LogUtil.i('点击逻辑触发，记录URL: $finalUrl, 等待计时结束');
    }
  }

  Future<String> getUrl() async {
    final completer = Completer<String>();

    if (_isCancelled()) {
      LogUtil.i('GetM3U8 任务在启动前被取消');
      return 'ERROR';
    }

    final dynamicKeywords = _parseKeywords(dynamicKeywordsString);

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

  Future<String?> _checkPageContent() async {
    if (_m3u8Found || !_isActive()) {
      LogUtil.i(
        '跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "任务被取消或未初始化"}'
      );
      return null;
    }

    if (clickText != null && !_isClickExecuted) {
      LogUtil.i('点击操作未完成，跳过页面内容检查');
      return null;
    }

    try {
      if (_httpResponseContent == null) {
        LogUtil.e('页面内容为空，跳过检测');
        return null;
      }

      String sample = UrlUtils.basicUrlClean(_httpResponseContent!);
      LogUtil.i('正在检测页面中的 $_filePattern 文件');

      // 修复：修正正则表达式语法，确保引号正确闭合
      final pattern = RegExp(
        r'(?:https?://|//|/)[^'"\\s,()<>{}\\[\\]]*?\\.${_filePattern}[^'"\\s,()<>{}\\[\\]]*',
        caseSensitive: false,
      );
      final matches = pattern.allMatches(sample);
      LogUtil.i('正则匹配到 ${matches.length} 个结果');

      return await _processMatches(matches, sample);
    } catch (e, stackTrace) {
      LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
      return null;
    }
  }

  Future<String?> _processMatches(Iterable<Match> matches, String sample) async {
    final uniqueUrls = <String>{};
    for (final match in matches) {
      String url = match.group(0)!;
      uniqueUrls.add(url);
    }

    final validUrls = <String>[];
    for (final url in uniqueUrls) {
      final cleanedUrl = _cleanUrl(url);
      if (_isValidM3U8Url(cleanedUrl)) {
        String finalUrl = cleanedUrl;
        if (fromParam != null && toParam != null) {
          finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
        }
        validUrls.add(finalUrl);
      }
    }

    if (validUrls.isEmpty) {
      return null;
    }

    if (clickIndex >= 0 && clickIndex < validUrls.length) {
      _setControllerState(m3u8Found: true);
      LogUtil.i('找到目标URL(index=$clickIndex): ${validUrls[clickIndex]}');
      return validUrls[clickIndex];
    } else {
      _setControllerState(m3u8Found: true);
      LogUtil.i('clickIndex=$clickIndex 超出范围(共${validUrls.length}个地址)，返回第一个地址: ${validUrls[0]}');
      return validUrls[0];
    }
  }

  Future<String> _prepareM3U8DetectorCode() async {
    const scriptKey = 'm3u8_detector.js';
    final cacheKey = '$scriptKey:$_filePattern';
    if (_scriptCache.containsKey(cacheKey)) {
      return _scriptCache[cacheKey]!;
    }
    final script = await rootBundle.loadString('assets/js/$scriptKey');
    final result = script.replaceAll('FILE_PATTERN', _filePattern);
    _scriptCache[cacheKey] = result;
    return result;
  }
}

// 修复：显式指定泛型类型并继承 SetBase
class _LimitedSet<T> extends SetBase<T> {
  final int _maxSize;
  final List<T> _items = [];

  _LimitedSet(this._maxSize);

  @override
  bool add(T value) {
    if (_items.contains(value)) return false;
    if (_items.length >= _maxSize) {
      _items.removeAt(0);
    }
    _items.add(value);
    return true;
  }

  @override
  bool contains(Object? element) => _items.contains(element);

  @override
  Iterator<T> get iterator => _items.iterator;

  @override
  int get length => _items.length;

  @override
  T? lookup(Object? element) => _items.contains(element) ? element as T : null;

  @override
  bool remove(Object? value) => _items.remove(value);

  @override
  Set<T> toSet() => _items.toSet();

  @override
  void clear() => _items.clear();
}

// 修复：显式指定泛型类型并继承 MapBase
class _LimitedMap<K, V> extends MapBase<K, V> {
  final int _maxSize;
  final Map<K, V> _map = {};
  final List<K> _keys = [];

  _LimitedMap(this._maxSize);

  @override
  V? operator [](Object? key) => _map[key];

  @override
  void operator []=(K key, V value) {
    if (_map.containsKey(key)) {
      _map[key] = value;
      return;
    }
    if (_keys.length >= _maxSize) {
      final oldestKey = _keys.removeAt(0);
      _map.remove(oldestKey);
    }
    _keys.add(key);
    _map[key] = value;
  }

  @override
  void clear() {
    _map.clear();
    _keys.clear();
  }

  @override
  Iterable<K> get keys => _keys;

  @override
  V? remove(Object? key) {
    final value = _map.remove(key);
    if (value != null) _keys.remove(key);
    return value;
  }
}
