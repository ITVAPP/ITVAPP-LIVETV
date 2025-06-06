import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' show min;
import 'package:dio/dio.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 管理应用常量
class AppConstants {
  AppConstants._(); // 私有构造函数，禁止实例化

  // 状态键
  static const String searchKeyword = 'searchKeyword';           // 搜索关键词
  static const String activeEngine = 'activeEngine';            // 当前搜索引擎
  static const String searchSubmitted = 'searchSubmitted';      // 表单提交状态
  static const String startTimeMs = 'startTimeMs';             // 解析开始时间
  static const String lastHtmlLength = 'lastHtmlLength';       // HTML长度
  static const String stage1StartTime = 'stage1StartTime';     // 阶段1开始时间
  static const String stage2StartTime = 'stage2StartTime';     // 阶段2开始时间
  static const String initialEngineAttempted = 'initialEngineAttempted'; // 初始引擎尝试标志

  // 搜索引擎URL
  static const String initialEngineUrl = 'https://iptv-search.com/zh-hans/search/?q='; // 初始搜索引擎URL
  static const String backupEngine1Url = 'http://www.foodieguide.com/iptvsearch/';        // 备用引擎1URL
  static const String backupEngine2Url = 'https://tonkiang.us/?';                         // 备用引擎2URL

  // 超时与限制
  static const int globalTimeoutSeconds = 38;         // 全局超时（秒）
  static const int maxStreams = 8;                    // 最大媒体流数
  static const int maxSearchCacheEntries = 58;       // 搜索缓存最大条目

  // 流测试参数
  static const int compareTimeWindowMs = 3000;       // 流响应时间窗口（毫秒）
  static const int testOverallTimeoutSeconds = 6;    // 流测试超时（秒）
  static const int fastStreamThresholdMs = 1000;     // 快速流阈值（毫秒）

  // 屏蔽关键词
  static const List<String> defaultBlockKeywords = ["freetv.fun", "epg.pw", "ktpremium.com", "serv00.net/Smart.php?id=ettvmovie"]; // 默认屏蔽关键词
}

/// URL操作工具
class UrlUtil {
  static final RegExp mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false,
  ); // 媒体链接正则表达式

  static final RegExp initialEngineLinkRegex = RegExp(
    r'(?:<|\\u003C)span\s+class="decrypted-link"(?:>|\\u003E)\s*(http[^<\\]+?)(?:<|\\u003C)/span',
    caseSensitive: false,
  ); // 初始引擎链接正则表达式

  static const Set<String> _staticExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.css', '.js', 
    '.ico', '.woff', '.woff2', '.ttf', '.svg'
  }; // 静态资源扩展名集合

  static bool isStaticResourceUrl(String url) => _staticExtensions.any((ext) => url.endsWith(ext)); // 检查URL是否为静态资源

  static bool isBackupEngine1(String url) => url.contains('foodieguide.com'); // 检查是否为备用引擎1
  static bool isBackupEngine2(String url) => url.contains('tonkiang.us'); // 检查是否为备用引擎2

  static String getHostKey(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.host}:${uri.port}'; // 提取URL的主机键
    } catch (e) {
      LogUtil.e('URL主机键解析失败: $url, $e');
      return url;
    }
  }
}

/// 定时器管理
class TimerManager {
  final Map<String, Timer> _timers = {}; // 定时器存储
  bool _isDisposed = false; // 资源释放标志

  Timer _createTimer(String key, Timer Function() timerCreator) {
    if (_isDisposed) {
      LogUtil.i('定时器已释放，忽略: $key');
      return Timer(Duration.zero, () {});
    }
    cancel(key);
    try {
      final timer = timerCreator();
      _timers[key] = timer;
      return timer;
    } catch (e) {
      LogUtil.e('定时器创建失败($key): $e');
      return Timer(Duration.zero, () {});
    }
  }

  Timer set(String key, Duration duration, Function() callback) => _createTimer(key, () {
    return Timer(duration, () {
      try {
        if (!_isDisposed) callback();
        _timers.remove(key);
      } catch (e) {
        LogUtil.e('定时器回调失败($key): $e');
        _timers.remove(key);
      }
    });
  }); // 创建单次定时器

  Timer setPeriodic(String key, Duration duration, Function(Timer) callback) => _createTimer(key, () {
    return Timer.periodic(duration, (timer) {
      try {
        callback(timer);
      } catch (e) {
        LogUtil.e('周期定时器回调失败($key): $e');
        timer.cancel();
        _timers.remove(key);
      }
    });
  }); // 创建周期定时器

  void cancel(String key) {
    final timer = _timers.remove(key);
    if (timer != null) {
      try {
        timer.cancel();
      } catch (e) {
        LogUtil.e('定时器取消失败($key): $e');
      }
    }
  } // 取消指定定时器

  bool exists(String key) => _timers.containsKey(key); // 检查定时器是否存在
  int get activeCount => _timers.length; // 返回活跃定时器数量

  void cancelAll() {
    try {
      for (var timer in _timers.values) timer.cancel();
    } finally {
      _timers.clear();
    }
  } // 取消所有定时器

  void dispose() {
    cancelAll();
    _isDisposed = true; // 释放定时器资源
  }
}

/// JavaScript脚本管理
class ScriptManager {
  static final Map<String, String> _scripts = {}; // 脚本缓存
  static final Map<String, Map<WebViewController, bool>> _injectedScripts = {
    'domMonitor': {},
    'fingerprintRandomization': {},
    'formDetection': {},
  }; // 脚本注入状态

  static Future<void> preload() async {
    final stopwatch = Stopwatch()..start();
    try {
      await Future.wait([
        _loadScript('assets/js/dom_change_monitor.js'),
        _loadScript('assets/js/fingerprint_randomization.js'),
        _loadScript('assets/js/form_detection.js'),
      ]);
      LogUtil.i('脚本预加载完成，耗时: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      LogUtil.e('脚本预加载失败: $e');
    } finally {
      stopwatch.stop();
    }
  }

  static Future<String> _loadScript(String filePath) async {
    if (_scripts.containsKey(filePath)) return _scripts[filePath]!;
    try {
      final script = await rootBundle.loadString(filePath);
      _scripts[filePath] = script;
      return script;
    } catch (e) {
      LogUtil.e('脚本加载失败($filePath): $e');
      try {
        final script = await rootBundle.loadString(filePath);
        _scripts[filePath] = script;
        return script;
      } catch (e2) {
        LogUtil.e('脚本二次加载失败($filePath): $e2');
        return '(function(){console.error("Failed to load script: $filePath");})();';
      }
    }
  }

  static Future<bool> _injectScript(
    String scriptKey,
    String assetPath,
    WebViewController controller,
    Map<String, String> replacements,
    String operationName,
  ) async {
    if (_injectedScripts[scriptKey]?[controller] == true) return true;
    try {
      if (!_scripts.containsKey(assetPath)) {
        _scripts[assetPath] = await _loadScript(assetPath);
      }
      
      String script = _scripts[assetPath]!;
      if (replacements.isNotEmpty) {
        replacements.forEach((placeholder, value) => script = script.replaceAll(placeholder, value));
      }
      
      await controller.runJavaScript(script);
      _injectedScripts[scriptKey] ??= {};
      _injectedScripts[scriptKey]![controller] = true;
      LogUtil.i('$operationName 注入成功');
      return true;
    } catch (e) {
      LogUtil.e('$operationName 注入失败: $e');
      return false;
    }
  }

  static Future<void> preInjectBasicScripts(WebViewController controller) async {
    final stopwatch = Stopwatch()..start();
    try {
      unawaited(injectFingerprintRandomization(controller).catchError((e) {
        LogUtil.e('指纹随机化脚本异步注入失败: $e');
      }));
      LogUtil.i('脚本异步注入启动，耗时: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      LogUtil.e('脚本预注入失败: $e');
    } finally {
      stopwatch.stop();
    }
  }

  static Future<void> injectScriptsAsync(WebViewController controller, String searchKeyword) async {
    try {
      await Future.wait([
        injectFingerprintRandomization(controller),
        injectFormDetection(controller, searchKeyword),
      ], eagerError: false);
      LogUtil.i('批量脚本注入完成');
    } catch (e) {
      LogUtil.e('批量脚本注入失败: $e');
    }
  }

  static Future<bool> injectDomMonitor(WebViewController controller, String channelName) =>
      _injectScript('domMonitor', 'assets/js/dom_change_monitor.js', controller, {'%CHANNEL_NAME%': channelName}, 'DOM监听器'); // 注入DOM监听脚本

  static Future<bool> injectFingerprintRandomization(WebViewController controller) =>
      _injectScript('fingerprintRandomization', 'assets/js/fingerprint_randomization.js', controller, {}, '指纹随机化脚本'); // 注入指纹随机化脚本

  static Future<bool> injectFormDetection(WebViewController controller, String searchKeyword) {
    final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
    return _injectScript('formDetection', 'assets/js/form_detection.js', controller, {'%SEARCH_KEYWORD%': escapedKeyword}, '表单检测脚本'); // 注入表单检测脚本
  }

  static void clearControllerState(WebViewController controller) {
    for (var controllers in _injectedScripts.values) controllers.remove(controller); // 清除控制器脚本注入状态
  }

  static void clearAll() {
    for (var controllers in _injectedScripts.values) controllers.clear(); // 清除所有脚本注入状态
  }
}

/// WebView控制器池
class WebViewPool {
  static final List<WebViewController> _pool = []; // WebView控制器池
  static const int maxPoolSize = 2; // 最大池大小
  static final Completer<void> _initCompleter = Completer<void>(); // 初始化完成器
  static bool _isInitialized = false; // 初始化标志
  static final Set<WebViewController> _disposingControllers = {}; // 清理中的控制器

  static Future<void> initialize() async {
    if (_isInitialized) return;
    final stopwatch = Stopwatch()..start();
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      _pool.add(controller);
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    } catch (e) {
      LogUtil.e('WebView池初始化失败: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
    } finally {
      stopwatch.stop();
    }
  }

  static Future<WebViewController> acquire() async {
    if (!_isInitialized) await initialize();
    if (!_initCompleter.isCompleted) await _initCompleter.future;
    if (_pool.isNotEmpty) return _pool.removeLast();
    LogUtil.i('控制器池为空，创建新WebView');
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent);
    return controller;
  }

  static Future<bool> _cleanupWebView(WebViewController controller, {bool onlyBasic = false}) async {
    try {
      await controller.clearCache();
      if (!onlyBasic) {
        await controller.loadHtmlString('<html><body></body></html>');
        await controller.clearLocalStorage();
      }
      return true;
    } catch (e) {
      LogUtil.e('WebView清理失败: $e');
      return false;
    }
  }

  static Future<void> release(WebViewController? controller) async {
    if (controller == null || _disposingControllers.contains(controller)) return;
    _disposingControllers.add(controller);
    try {
      bool cleanupSuccess = await _cleanupWebView(controller, onlyBasic: true);
      ScriptManager.clearControllerState(controller);
      bool isDuplicate = _pool.any((existing) => identical(existing, controller));
      if (!isDuplicate && _pool.length < maxPoolSize) {
        _pool.add(controller);
      } else if (!isDuplicate) {
        await _cleanupWebView(controller);
      }
    } catch (e) {
      LogUtil.e('WebView重置失败: $e');
      try {
        await _cleanupWebView(controller);
      } catch (cleanupError) {
        LogUtil.e('WebView清理失败: $cleanupError');
      }
    } finally {
      _disposingControllers.remove(controller);
    }
  }

  static Future<void> clear() async {
    for (final controller in _pool) {
      try {
        await _cleanupWebView(controller);
      } catch (e) {
        LogUtil.e('WebView清理失败: $e');
      }
    }
    _pool.clear();
    _disposingControllers.clear();
    ScriptManager.clearAll();
  }
}

/// 搜索结果缓存
class _SearchCache {
  static const String _cacheKey = 'search_cache_data'; // 缓存数据键
  static const String _lruKey = 'search_cache_lru'; // LRU顺序键
  final int maxEntries; // 最大缓存条目数
  final LinkedHashMap<String, String> _cache = LinkedHashMap<String, String>(); // 缓存存储 - 直接存储URL字符串
  bool _isDirty = false; // 缓存脏标志
  Timer? _persistTimer; // 持久化定时器
  static final LinkedHashMap<String, String> _normalizedKeywordCache = LinkedHashMap<String, String>(); // 关键词规范化缓存
  static const int _maxNormalizedCacheSize = 50; // 规范化缓存最大条目

  _SearchCache({this.maxEntries = AppConstants.maxSearchCacheEntries}) {
    _loadFromPersistence();
    _persistTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (_isDirty) {
        _saveToPersistence();
        _isDirty = false;
      }
    }); // 定时持久化缓存
  }

  static String _normalizeKeyword(String keyword) {
    if (_normalizedKeywordCache.containsKey(keyword)) {
      final normalized = _normalizedKeywordCache.remove(keyword)!;
      _normalizedKeywordCache[keyword] = normalized;
      return normalized;
    }
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.toLowerCase();
    if (_normalizedKeywordCache.length >= _maxNormalizedCacheSize) {
      _normalizedKeywordCache.remove(_normalizedKeywordCache.keys.first);
    }
    _normalizedKeywordCache[keyword] = normalized;
    return normalized; // 规范化搜索关键词
  }

  void _loadFromPersistence() {
    try {
      final cacheJson = SpUtil.getString(_cacheKey);
      if (cacheJson != null && cacheJson.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(cacheJson);
        final lruJson = SpUtil.getString(_lruKey);
        List<String> lruOrder = [];
        if (lruJson != null && lruJson.isNotEmpty) lruOrder = (jsonDecode(lruJson) as List<dynamic>).whereType<String>().toList();
        _cache.clear();
        
        // 直接加载URL字符串
        for (final key in lruOrder) {
          if (data.containsKey(key)) {
            final value = data[key];
            if (value is String) {
              _cache[key] = value;
            } else if (value is Map && value.containsKey('url')) {
              // 兼容旧版本数据
              _cache[key] = value['url'] as String;
            }
          }
        }
        for (final key in data.keys) {
          if (!_cache.containsKey(key)) {
            final value = data[key];
            if (value is String) {
              _cache[key] = value;
            } else if (value is Map && value.containsKey('url')) {
              // 兼容旧版本数据
              _cache[key] = value['url'] as String;
            }
          }
        }
        while (_cache.length > maxEntries && _cache.isNotEmpty) _cache.remove(_cache.keys.first);
        LogUtil.i('缓存加载完成: ${_cache.length}条');
      }
    } catch (e) {
      LogUtil.e('缓存加载失败: $e');
      _cache.clear();
    }
  }

  void _saveToPersistence() {
    try {
      SpUtil.putString(_cacheKey, jsonEncode(_cache));
      SpUtil.putString(_lruKey, jsonEncode(_cache.keys.toList()));
    } catch (e) {
      LogUtil.e('缓存保存失败: $e');
    }
  }

  String? getUrl(String keyword, {bool forceRemove = false}) {
    final normalizedKeyword = _normalizeKeyword(keyword);
    if (normalizedKeyword.isEmpty) return null;
    final url = _cache[normalizedKeyword];
    if (url == null) return null;
    if (forceRemove) {
      _cache.remove(normalizedKeyword);
      _isDirty = true;
      _saveToPersistence();
      LogUtil.i('移除缓存: $normalizedKeyword -> $url');
      return null;
    }
    if (_cache.length > 1) {
      _cache.remove(normalizedKeyword);
      _cache[normalizedKeyword] = url;
    }
    _isDirty = true;
    return url; // 获取缓存的URL
  }

  void addUrl(String keyword, String url) {
    if (keyword.isEmpty || url.isEmpty || url == 'ERROR') return;
    final normalizedKeyword = _normalizeKeyword(keyword);
    if (normalizedKeyword.isEmpty) return;
    _cache.remove(normalizedKeyword);
    if (_cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      LogUtil.i('移除最旧缓存: $oldest');
    }
    _cache[normalizedKeyword] = url;
    _isDirty = true;
    LogUtil.i('添加缓存: $normalizedKeyword -> $url');
  }

  void clear() {
    _cache.clear();
    SpUtil.remove(_cacheKey);
    SpUtil.remove(_lruKey);
    _isDirty = false;
    LogUtil.i('清空缓存');
  }

  int get size => _cache.length; // 返回缓存条目数

  void dispose() {
    try {
      if (_isDirty) _saveToPersistence();
    } catch (e) {
      LogUtil.e('缓存保存失败: $e');
    } finally {
      _persistTimer?.cancel();
      _persistTimer = null;
    }
  }
}

/// 解析会话管理
class _ParserSession {
  final Completer<String> completer = Completer<String>(); // 异步任务完成器
  final List<String> foundStreams = []; // 发现的流地址
  WebViewController? controller; // WebView控制器
  final TimerManager _timerManager = TimerManager(); // 定时器管理
  bool isResourceCleaned = false; // 资源清理状态
  bool isTestingStarted = false; // 流测试开始标志
  bool isExtractionInProgress = false; // 链接提取进行中
  bool isCollectionFinished = false; // 链接收集完成
  bool hasRegisteredJsChannel = false; // JS通道注册标志
  final Map<String, dynamic> searchState = {
    AppConstants.searchKeyword: '', // 搜索关键词
    AppConstants.activeEngine: 'backup1', // 默认搜索引擎
    AppConstants.searchSubmitted: false, // 表单提交状态
    AppConstants.startTimeMs: DateTime.now().millisecondsSinceEpoch, // 解析开始时间
    AppConstants.lastHtmlLength: 0, // HTML内容长度
    AppConstants.stage1StartTime: DateTime.now().millisecondsSinceEpoch, // 阶段1开始时间
    AppConstants.stage2StartTime: 0, // 阶段2开始时间
    AppConstants.initialEngineAttempted: false, // 初始引擎尝试标志
  };
  final Map<String, int> _lastPageFinishedTime = {}; // 页面加载防抖记录
  StreamSubscription? cancelListener; // 取消操作监听器
  final CancelToken? cancelToken; // 取消请求令牌
  bool _isCleaningUp = false; // 清理锁
  final Set<String> _urlCache = {}; // URL去重缓存
  bool isCompareDone = false; // 流比较完成标志

  _ParserSession({this.cancelToken, String? initialEngine}) {
    if (initialEngine != null) searchState[AppConstants.activeEngine] = initialEngine;
    if (initialEngine == 'backup1' || initialEngine == 'backup2') searchState[AppConstants.initialEngineAttempted] = true;
  }

  bool get isCancelled => cancelToken?.isCancelled ?? false; // 检查任务是否取消
  
  bool _isValidForOperation() => controller != null && !completer.isCompleted && !isCancelled; // 验证操作有效性

  Future<String?> _safeRunJavaScript(String script, {String? defaultValue}) async {
    try {
      final result = await controller!.runJavaScriptReturningResult(script);
      return result?.toString() ?? defaultValue;
    } catch (e) {
      LogUtil.e('JavaScript执行失败: $e');
      return defaultValue;
    }
  }

  void _selectBestStream(Map<String, int> streams, Completer<String> resultCompleter, CancelToken token) {
    if (isCompareDone || resultCompleter.isCompleted) return;
    isCompareDone = true;
    String selectedStream = '';
    int bestTime = 999999;
    streams.forEach((stream, time) {
      if (time < bestTime) {
        bestTime = time;
        selectedStream = stream;
      }
    });
    if (selectedStream.isEmpty) return;
    LogUtil.i('选择最快流: $selectedStream (${bestTime}ms)');
    if (!resultCompleter.isCompleted) {
      resultCompleter.complete(selectedStream);
      if (!completer.isCompleted) completer.complete(selectedStream);
    }
  }

  void finishCollectionAndTest() {
    if (isCancelled) {
      LogUtil.i('任务已取消，停止收集');
      return;
    }
    if (isCollectionFinished || isTestingStarted) return;
    isCollectionFinished = true;
    startStreamTesting();
  }

  Future<void> cleanupResources({bool immediate = false}) async {
    if (_isCleaningUp || isResourceCleaned) return;
    _isCleaningUp = true;
    bool cleanupSuccess = false;
    try {
      _timerManager.cancelAll();
      if (cancelListener != null) {
        try {
          await cancelListener!.cancel().timeout(Duration(milliseconds: 500), onTimeout: () => LogUtil.i('取消监听器超时'));
        } catch (e) {
          LogUtil.e('监听器取消失败: $e');
        } finally {
          cancelListener = null;
        }
      }
      final tempController = controller;
      controller = null;
      hasRegisteredJsChannel = false;
      if (tempController != null) {
        cleanupSuccess = await WebViewPool._cleanupWebView(tempController);
        if (!immediate) {
          await WebViewPool.release(tempController);
        } else {
          await tempController.clearLocalStorage();
          LogUtil.i('即时清理本地存储');
        }
      } else {
        cleanupSuccess = true;
      }
      _urlCache.clear();
      if (cleanupSuccess) {
        isResourceCleaned = true;
        LogUtil.i('资源清理完成');
      }
    } catch (e) {
      LogUtil.e('资源清理失败: $e');
    } finally {
      _isCleaningUp = false;
    }
  }

  Future<String> _testAllStreamsConcurrently(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR';
    final Completer<String> resultCompleter = Completer<String>();
    final Map<String, int> successfulStreams = {};
    final Completer<String> fastResultCompleter = Completer<String>();
    
    _timerManager.set('compareWindow', Duration(milliseconds: AppConstants.compareTimeWindowMs), () {
      if (!isCompareDone && !resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      }
    }); // 设置流比较时间窗口
    _timerManager.set('streamTestTimeout', Duration(seconds: AppConstants.testOverallTimeoutSeconds), () {
      if (!resultCompleter.isCompleted) {
        if (successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter, cancelToken);
        } else {
          LogUtil.i('流测试超时: ${AppConstants.testOverallTimeoutSeconds}秒');
          resultCompleter.complete('ERROR');
        }
      }
    }); // 设置流测试超时
    try {
      final testFutures = streams.map((stream) => 
        _testSingleStream(stream, successfulStreams, cancelToken, resultCompleter, fastResultCompleter)).toList();
      
      await Future.any([
        fastResultCompleter.future.then((result) {
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(result);
          }
        }),
        Future.wait(testFutures),
        resultCompleter.future.then((_) => null)
      ]);
      
      if (!resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      } else if (!resultCompleter.isCompleted) {
        resultCompleter.complete('ERROR');
      }
      return await resultCompleter.future;
    } catch (e) {
      LogUtil.e('流测试失败: $e');
      if (!resultCompleter.isCompleted) {
        if (successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter, cancelToken);
          return await resultCompleter.future;
        }
        resultCompleter.complete('ERROR');
      }
      return await resultCompleter.future;
    } finally {
      _timerManager.cancel('compareWindow');
      _timerManager.cancel('streamTestTimeout');
    }
  }

  bool _isDirectStreamUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.flv') || 
           lowerUrl.contains('.mp4') || 
           lowerUrl.contains('.ts') ||
           lowerUrl.contains('.m3u8') ||
           lowerUrl.contains('.avi') ||
           lowerUrl.contains('.mkv') ||
           lowerUrl.contains('.webm') ||
           lowerUrl.contains('.mov') ||
           lowerUrl.contains('.wmv') ||
           lowerUrl.contains('.mpg') ||
           lowerUrl.contains('.mpeg') ||
           lowerUrl.contains('.3gp') ||
           lowerUrl.startsWith('rtmp:') ||
           lowerUrl.startsWith('rtsp:'); // 检查URL是否为直接流地址
  }

  Future<bool> _testSingleStream(
    String streamUrl,
    Map<String, int> successfulStreams,
    CancelToken cancelToken,
    Completer<String> resultCompleter,
    Completer<String> fastResultCompleter,
  ) async {
    if (resultCompleter.isCompleted || cancelToken.isCancelled) return false;
    try {
      final stopwatch = Stopwatch()..start();
      final response = await HttpUtil().getRequestWithResponse(
        streamUrl,
        options: Options(
          headers: HeadersConfig.generateHeaders(url: streamUrl),
          method: 'GET',
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
          receiveTimeout: Duration(seconds: AppConstants.testOverallTimeoutSeconds),
        ),
        cancelToken: cancelToken,
        retryCount: 1,
      );
      final testTime = stopwatch.elapsedMilliseconds;
      if (response != null && !resultCompleter.isCompleted && !cancelToken.isCancelled) {
        if (!_isDirectStreamUrl(streamUrl)) {
          final responseData = response.data as String;
          if (responseData.isEmpty || !responseData.trim().startsWith('#EXTM3U')) {
            LogUtil.i('流格式无效: $streamUrl');
            return false;
          }
        }
        successfulStreams[streamUrl] = testTime;
        
        if (testTime < AppConstants.fastStreamThresholdMs && !isCompareDone && !fastResultCompleter.isCompleted) {
          LogUtil.i('发现快速流: $streamUrl (${testTime}ms)');
          fastResultCompleter.complete(streamUrl);
          _selectBestStream({streamUrl: testTime}, resultCompleter, cancelToken);
        }
        return true;
      }
    } catch (e) {
      if (!cancelToken.isCancelled) LogUtil.e('流测试失败: $streamUrl, $e');
    }
    return false;
  }

  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('流测试已开始，忽略重复请求');
      return;
    }
    if (isCancelled) {
      LogUtil.i('任务已取消，停止测试');
      return;
    }
    if (foundStreams.isEmpty) {
      LogUtil.i('无流链接，测试中止');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }
    isTestingStarted = true;
    _timerManager.cancel('delayedContentChange');
    LogUtil.i('开始测试流: ${foundStreams.length}个');
    if (cancelToken != null && cancelToken!.isCancelled) {
      LogUtil.i('任务取消，停止测试');
      return;
    }
    _testStreamsAsync(cancelToken, null);
  }

  Future<void> _testStreamsAsync(CancelToken? testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      final result = await _testAllStreamsConcurrently(foundStreams, testCancelToken ?? CancelToken());
      if (!completer.isCompleted) {
        completer.complete(result);
        cleanupResources();
      }
    } catch (e) {
      LogUtil.e('流测试失败: $e');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    } finally {
      try {
        await testCancelListener?.cancel();
      } catch (e) {
        LogUtil.e('测试监听器取消失败: $e');
      }
    }
  }

  bool _shouldSwitchEngine() {
    final currentEngine = searchState[AppConstants.activeEngine] as String;
    return currentEngine != 'backup2'; // 检查是否可切换到下一引擎
  }

  Future<void> switchToNextEngine() async {
    final currentEngine = searchState[AppConstants.activeEngine] as String;
    if (currentEngine == 'backup2') {
      LogUtil.i('已是最后引擎，无法切换');
      return;
    }
    String nextEngine = currentEngine == 'backup1' ? 'backup2' : 'backup1';
    String nextEngineUrl = currentEngine == 'backup1' ? AppConstants.backupEngine2Url : AppConstants.backupEngine1Url;
    try {
      if (isCancelled) {
        LogUtil.i('任务已取消，停止切换');
        return;
      }
      LogUtil.i('切换引擎: $currentEngine -> $nextEngine');
      searchState[AppConstants.activeEngine] = nextEngine;
      searchState[AppConstants.searchSubmitted] = false;
      searchState[AppConstants.lastHtmlLength] = 0;
      searchState[AppConstants.stage1StartTime] = DateTime.now().millisecondsSinceEpoch;
      isCollectionFinished = false;
      if (controller != null) {
        ScriptManager.clearControllerState(controller!);
        LogUtil.i('清理ScriptManager状态');
        await controller!.loadRequest(Uri.parse(nextEngineUrl));
        LogUtil.i('加载引擎: $nextEngine ($nextEngineUrl)');
      } else {
        LogUtil.e('WebView控制器为空');
        throw Exception('WebView控制器为空');
      }
    } catch (e) {
      LogUtil.e('引擎切换失败: $e');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }

  void handleContentChange() {
    _timerManager.cancel('contentChangeDebounce');
    _timerManager.cancel('delayedContentChange');
    if (isCancelled || isTestingStarted || isExtractionInProgress) return;
    _timerManager.set('contentChangeDebounce', Duration(milliseconds: 500), () async {
      if (!_isValidForOperation() || isTestingStarted || isExtractionInProgress) return;
      try {
        if (searchState[AppConstants.searchSubmitted] == true && !completer.isCompleted && !isTestingStarted) {
          isExtractionInProgress = true;
          int beforeExtractCount = foundStreams.length;
          final currentEngine = searchState[AppConstants.activeEngine] as String;
          bool isBackupEngine2 = currentEngine == 'backup2';
          await SousuoParser._extractAllMediaLinks(controller!, foundStreams, isBackupEngine2, urlCache: _urlCache);
          final htmlLengthStr = await _safeRunJavaScript('document.documentElement.outerHTML.length', defaultValue: '0');
          searchState[AppConstants.lastHtmlLength] = int.tryParse(htmlLengthStr ?? '0') ?? 0;
          if (isCancelled) {
            LogUtil.i('提取中止: 任务取消');
            return;
          }
          int afterExtractCount = foundStreams.length;
          if (afterExtractCount > beforeExtractCount) {
            if (afterExtractCount >= AppConstants.maxStreams) finishCollectionAndTest();
          } else if (_shouldSwitchEngine() && afterExtractCount == 0) {
            switchToNextEngine();
          } else if (afterExtractCount > 0) {
            finishCollectionAndTest();
          }
        }
      } catch (e) {
        LogUtil.e('内容变化处理失败: $e');
      } finally {
        isExtractionInProgress = false;
      }
    }); // 防抖处理内容变化
  }

  Future<void> handlePageStarted(String pageUrl) async {
    if (controller == null || isCancelled) return;
    if (searchState[AppConstants.searchSubmitted] == false) {
      String searchKeyword = searchState[AppConstants.searchKeyword] ?? '';
      if (searchKeyword.isEmpty) {
        try {
          final uri = Uri.parse(pageUrl);
          searchKeyword = uri.queryParameters['clickText'] ?? '';
        } catch (e) {
          LogUtil.e('关键词解析失败: $e');
        }
      }
      unawaited(ScriptManager.injectScriptsAsync(controller!, searchKeyword)); // 异步注入所有脚本
    } else {
      ScriptManager.clearControllerState(controller!);
      unawaited(ScriptManager.injectDomMonitor(controller!, 'AppChannel').catchError((e) {
        LogUtil.e('DOM监听脚本注入失败: $e');
      })); // 异步注入DOM监听脚本
    }
  }

  Future<void> handlePageFinished(String pageUrl) async {
    if (controller == null || isCancelled) return;
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastPageFinishedTime.containsKey(pageUrl) && currentTimeMs - _lastPageFinishedTime[pageUrl]! < 300) return;
    _lastPageFinishedTime[pageUrl] = currentTimeMs;
    final startMs = searchState[AppConstants.startTimeMs] as int;
    LogUtil.i('备用引擎页面加载完成: $pageUrl, 耗时: ${currentTimeMs - startMs}ms');
    if (pageUrl == 'about:blank') return;
    if (controller == null) {
      LogUtil.e('WebView控制器为空');
      return;
    }
    bool isBackupEngine1 = UrlUtil.isBackupEngine1(pageUrl);
    bool isBackupEngine2 = UrlUtil.isBackupEngine2(pageUrl);
    if (!isBackupEngine1 && !isBackupEngine2) {
      LogUtil.i('未知页面: $pageUrl');
      return;
    }
    if (isBackupEngine1) {
      searchState[AppConstants.activeEngine] = 'backup1';
    } else if (isBackupEngine2) {
      searchState[AppConstants.activeEngine] = 'backup2';
    }
    if (searchState[AppConstants.searchSubmitted] == true && !isExtractionInProgress && !isTestingStarted && !isCollectionFinished && !isCancelled) {
      _timerManager.set('delayedContentChange', Duration(milliseconds: 500), () {
        if (_isValidForOperation()) {
          LogUtil.i('触发延迟内容变化');
          handleContentChange();
        }
      }); // 延迟处理内容变化
    }
  }

  bool _isCriticalNetworkError(int errorCode) => const [-1, -2, -3, -6, -7, -101, -105, -106].contains(errorCode); // 检查是否为关键网络错误

  void handleWebResourceError(WebResourceError error) {
    if (controller == null || isCancelled) return;
    LogUtil.e('资源错误: ${error.description}, 码: ${error.errorCode}, URL: ${error.url}');
    if (error.url == null || UrlUtil.isStaticResourceUrl(error.url!)) return;
    if (_isCriticalNetworkError(error.errorCode) && _shouldSwitchEngine() && searchState[AppConstants.searchSubmitted] == false) {
      LogUtil.i('关键网络错误，切换引擎');
      switchToNextEngine();
    }
  }

  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (controller == null || isCancelled) return NavigationDecision.prevent;
    if (UrlUtil.isStaticResourceUrl(request.url) || request.url.contains('google') || request.url.contains('facebook.com') || request.url.contains('twitter.com')) {
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate; // 处理导航请求
  }

  Future<void> handleJavaScriptMessage(JavaScriptMessage message) async {
    if (controller == null || isCancelled) return;
    LogUtil.i('收到JS消息: ${message.message}');
    switch (message.message) {
      case 'CONTENT_READY':
        handleContentChange();
        break;
      case 'CONTENT_ERROR':
        LogUtil.e('DOM监听器超时，页面加载失败');
        if (_shouldSwitchEngine()) {
          LogUtil.i('切换到下一引擎');
          switchToNextEngine();
        } else {
          LogUtil.i('已是最后引擎，返回错误');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            cleanupResources();
          }
        }
        break;
      case 'FORM_SUBMITTED':
        searchState[AppConstants.searchSubmitted] = true;
        searchState[AppConstants.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
        break;
      case 'FORM_PROCESS_FAILED':
        if (_shouldSwitchEngine()) {
          LogUtil.i('表单处理失败，切换引擎');
          switchToNextEngine();
        }
        break;
      case 'SIMULATION_FAILED':
        LogUtil.e('模拟真人行为失败');
        break;
    }
  }

  Future<String> startParsing(String url) async {
    try {
      if (isCancelled) {
        LogUtil.i('任务已取消，返回ERROR');
        return 'ERROR';
      }
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无有效关键词');
        return 'ERROR';
      }
      searchState[AppConstants.searchKeyword] = searchKeyword;
      
      controller = await WebViewPool.acquire();
      
      if (!hasRegisteredJsChannel) {
        await controller!.addJavaScriptChannel('AppChannel', onMessageReceived: handleJavaScriptMessage);
        hasRegisteredJsChannel = true;
      }
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: handlePageStarted,
        onPageFinished: handlePageFinished,
        onWebResourceError: handleWebResourceError,
        onNavigationRequest: handleNavigationRequest,
      ));
      try {
        final String engineUrl = (searchState[AppConstants.activeEngine] == 'backup1') ? 
            AppConstants.backupEngine1Url : AppConstants.backupEngine2Url;
        LogUtil.i('加载引擎: ${searchState[AppConstants.activeEngine]} ($engineUrl)');
        await controller!.loadRequest(Uri.parse(engineUrl));
      } catch (e) {
        LogUtil.e('页面加载失败: $e');
        if (_shouldSwitchEngine()) {
          LogUtil.i('引擎加载失败，切换引擎');
          await switchToNextEngine();
        }
      }
      final result = await completer.future;
      if (!isCancelled && !isResourceCleaned) {
        LogUtil.i('解析耗时: ${DateTime.now().millisecondsSinceEpoch - (searchState[AppConstants.startTimeMs] as int)}ms');
      }
      return result;
    } catch (e, stackTrace) {
      LogUtil.e('解析失败: $e, 堆栈: $stackTrace');
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('测试已有流: ${foundStreams.length}个');
        try {
          final result = await _testAllStreamsConcurrently(foundStreams, cancelToken ?? CancelToken());
          if (!completer.isCompleted) completer.complete(result);
          return result;
        } catch (testError) {
          LogUtil.e('流测试失败: $testError');
          if (!completer.isCompleted) completer.complete('ERROR');
        }
      } else if (!completer.isCompleted) {
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR');
      }
      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!isResourceCleaned) await cleanupResources();
    }
  }
}

/// 直播源搜索引擎解析器
class SousuoParser {
  static Set<String> _blockKeywordsSet = AppConstants.defaultBlockKeywords.map((k) => k.toLowerCase()).toSet(); // 屏蔽关键词集合
  static final _SearchCache _searchCache = _SearchCache(); // 搜索结果缓存
  static final LinkedHashMap<String, String> _hostKeyCache = LinkedHashMap<String, String>(); // 主机键缓存
  static final Map<String, String> _urlLowerCaseCache = {}; // URL小写缓存
  static const int _maxUrlCacheSize = 100; // 最大URL缓存条目
  static const int _maxHostKeyCacheSize = 100; // 最大主机键缓存条目

  static Future<void> initialize() async {
    final stopwatch = Stopwatch()..start();
    LogUtil.i('解析器初始化开始');
    try {
      await Future.wait([
        WebViewPool.initialize(),
        ScriptManager.preload(),
      ]);
      LogUtil.i('解析器初始化完成，耗时: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      LogUtil.e('解析器初始化失败: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  static void setBlockKeywords(String keywords) {
    final List<String> keywordList = keywords.isNotEmpty 
        ? keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() 
        : AppConstants.defaultBlockKeywords;
    _blockKeywordsSet = keywordList.map((k) => k.toLowerCase()).toSet();
    _urlLowerCaseCache.clear();
  }

  static bool _isUrlBlocked(String url) {
    if (_blockKeywordsSet.isEmpty) return false;
    String lowerUrl;
    if (_urlLowerCaseCache.containsKey(url)) {
      lowerUrl = _urlLowerCaseCache[url]!;
    } else {
      lowerUrl = url.toLowerCase();
      if (_urlLowerCaseCache.length >= _maxUrlCacheSize) {
        _urlLowerCaseCache.remove(_urlLowerCaseCache.keys.first);
      }
      _urlLowerCaseCache[url] = lowerUrl;
    }
    return _blockKeywordsSet.any((keyword) => lowerUrl.contains(keyword)); // 检查URL是否包含屏蔽关键词
  }

  static Future<bool> _validateCachedUrl(String keyword, String url, CancelToken? cancelToken) async {
    try {
      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(
          headers: HeadersConfig.generateHeaders(url: url),
          method: 'GET',
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
        cancelToken: cancelToken,
      );
      if (response != null) {
        LogUtil.i('缓存URL验证成功: $url');
        return true;
      } else {
        LogUtil.i('缓存URL验证失败，移除: $keyword');
        _searchCache.getUrl(keyword, forceRemove: true);
        return false;
      }
    } catch (e) {
      LogUtil.i('缓存URL验证失败，移除: $keyword, $e');
      _searchCache.getUrl(keyword, forceRemove: true);
      return false;
    }
  }

  static Future<String?> _searchWithInitialEngine(String keyword, CancelToken? cancelToken) async {
    final normalizedKeyword = keyword.trim().toLowerCase();
    final completer = Completer<String?>();
    WebViewController? controller;
    bool isResourceCleaned = false;
    final timerManager = TimerManager();

    Future<void> cleanupResources() async {
      if (isResourceCleaned) return;
      isResourceCleaned = true;
      timerManager.cancelAll();
      final tempController = controller;
      controller = null;
      if (tempController != null) {
        try {
          await WebViewPool.release(tempController);
        } catch (e) {
          LogUtil.e('WebView释放失败: $e');
          try {
            await WebViewPool.release(tempController);
          } catch (releaseError) {
            LogUtil.e('WebView释放失败: $releaseError');
          }
        }
      }
    }

    try {
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('任务取消');
        completer.complete(null);
        return null;
      }
      final resultCompleter = Completer<String?>();
      timerManager.set('globalTimeout', Duration(seconds: AppConstants.globalTimeoutSeconds), () {
        LogUtil.i('初始引擎超时');
        if (!resultCompleter.isCompleted) resultCompleter.complete(null);
      });
      final searchUrl = AppConstants.initialEngineUrl + Uri.encodeComponent(keyword);
      
      controller = await WebViewPool.acquire();
      
      if (controller == null) {
        LogUtil.e('获取WebView失败');
        timerManager.cancel('globalTimeout');
        completer.complete(null);
        return null;
      }
      
      final pageLoadCompleter = Completer<String>();
      bool contentReadyProcessed = false;
      
      await controller!.addJavaScriptChannel('AppChannel', onMessageReceived: (JavaScriptMessage message) {
        LogUtil.i('初始引擎消息: ${message.message}');
        if (message.message == 'CONTENT_READY' && !contentReadyProcessed) {
          contentReadyProcessed = true;
          if (!pageLoadCompleter.isCompleted) pageLoadCompleter.complete(searchUrl);
        } else if (message.message == 'CONTENT_ERROR') {
          LogUtil.e('初始引擎DOM监听器超时');
          if (!resultCompleter.isCompleted) resultCompleter.complete(null);
          if (!pageLoadCompleter.isCompleted) pageLoadCompleter.completeError('页面加载失败');
        }
      });
      
      unawaited(ScriptManager.preInjectBasicScripts(controller!).catchError((e) {
        LogUtil.e('初始引擎脚本预注入失败: $e');
      })); // 异步预注入基础脚本
      
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          if (url != 'about:blank') {
            LogUtil.i('初始引擎页面加载: $url');
            try {
              unawaited(ScriptManager.injectDomMonitor(controller!, 'AppChannel').catchError((e) {
                LogUtil.e('初始引擎DOM监听脚本注入失败: $e');
              })); // 异步注入DOM监听脚本
            } catch (e) {
              LogUtil.e('初始引擎脚本注入失败: $e');
            }
          }
        },
        onPageFinished: (url) {
          if (url == 'about:blank') return;
          if (!pageLoadCompleter.isCompleted && !contentReadyProcessed) {
            LogUtil.i('初始引擎页面加载完成: $url');
            pageLoadCompleter.complete(url);
          }
        },
        onWebResourceError: (error) => LogUtil.e('初始引擎资源错误: ${error.description}'),
      ));
      await controller!.loadRequest(Uri.parse(searchUrl));
      String loadedUrl;
      try {
        loadedUrl = await pageLoadCompleter.future;
      } catch (e) {
        LogUtil.e('初始引擎页面加载失败: $e');
        await cleanupResources();
        completer.complete(null);
        return null;
      }
      await Future.delayed(Duration(seconds: 1));
      String html;
      try {
        final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML');
        html = _cleanHtmlString(result.toString());
        LogUtil.i('初始引擎HTML长度: ${html.length}');
      } catch (e) {
        LogUtil.e('获取HTML失败: $e');
        await cleanupResources();
        completer.complete(null);
        return null;
      }
      final List<String> extractedUrls = [];
      final matches = UrlUtil.initialEngineLinkRegex.allMatches(html);
      for (final match in matches) {
        final url = match.group(1)?.trim();
        if (url != null && url.isNotEmpty && !_isUrlBlocked(url)) {
          extractedUrls.add(url);
          if (extractedUrls.length >= AppConstants.maxStreams) break;
        }
      }
      await cleanupResources();
      LogUtil.i('初始引擎提取链接: ${extractedUrls.length}');
      if (extractedUrls.isEmpty) {
        completer.complete(null);
        return null;
      }
      final testSession = _ParserSession(cancelToken: cancelToken);
      testSession.foundStreams.addAll(extractedUrls);
      testSession.searchState[AppConstants.initialEngineAttempted] = true;
      LogUtil.i('测试初始引擎链接: ${extractedUrls.length}');
      final result = await testSession._testAllStreamsConcurrently(extractedUrls, cancelToken ?? CancelToken());
      final finalResult = result == 'ERROR' ? null : result;
      completer.complete(finalResult);
      return finalResult;
    } catch (e) {
      LogUtil.e('初始引擎搜索失败: $e');
      if (!isResourceCleaned) await cleanupResources();
      completer.complete(null);
      return null;
    } finally {
      if (!isResourceCleaned) await cleanupResources();
      if (!completer.isCompleted) completer.complete(null);
    }
  }

  static Future<String> _performParsing(String url, String searchKeyword, CancelToken? cancelToken, String blockKeywords) async {
    final cachedUrl = _searchCache.getUrl(searchKeyword);
    if (cachedUrl != null) {
      LogUtil.i('缓存命中: $searchKeyword -> $cachedUrl');
      if (await _validateCachedUrl(searchKeyword, cachedUrl, cancelToken)) return cachedUrl;
      LogUtil.i('缓存失效，重新搜索');
    }
    final initialEngineResult = await _searchWithInitialEngine(searchKeyword, cancelToken);
    if (initialEngineResult != null) {
      LogUtil.i('初始引擎成功: $initialEngineResult');
      _searchCache.addUrl(searchKeyword, initialEngineResult);
      return initialEngineResult;
    } else {
      LogUtil.i('初始引擎失败，进入标准解析');
    }
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务取消');
      return 'ERROR';
    }
    final session = _ParserSession(cancelToken: cancelToken, initialEngine: 'backup1');
    session.searchState[AppConstants.initialEngineAttempted] = true;
    final result = await session.startParsing(url);
    if (result != 'ERROR' && searchKeyword.isNotEmpty) _searchCache.addUrl(searchKeyword, result);
    return result;
  }

  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    Timer? globalTimer;
    String result = 'ERROR';
    try {
      if (blockKeywords.isNotEmpty) setBlockKeywords(blockKeywords);
      String? searchKeyword;
      try {
        final uri = Uri.parse(url);
        searchKeyword = uri.queryParameters['clickText'];
      } catch (e) {
        LogUtil.e('关键词提取失败: $e');
        return 'ERROR';
      }
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无有效关键词');
        return 'ERROR';
      }
      
      LogUtil.i('开始任务: $searchKeyword');
      
      final Completer<String> timeoutCompleter = Completer<String>();
      globalTimer = Timer(Duration(seconds: AppConstants.globalTimeoutSeconds), () {
        LogUtil.i('全局超时: $searchKeyword');
        if (!timeoutCompleter.isCompleted) timeoutCompleter.complete('ERROR');
      });
      try {
        final parseResult = _performParsing(url, searchKeyword, cancelToken, blockKeywords);
        result = await Future.any([parseResult, timeoutCompleter.future]);
        return result;
      } catch (e) {
        LogUtil.e('解析失败: $e');
        result = 'ERROR';
        return result;
      }
    } catch (e) {
      LogUtil.e('parse方法异常: $e');
      result = 'ERROR';
      return result;
    } finally {
      globalTimer?.cancel();
    }
  }

  static String _cleanHtmlString(String htmlContent) {
    final length = htmlContent.length;
    if (length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) return htmlContent;
    
    try {
      String innerContent = htmlContent.substring(1, length - 1);
      innerContent = innerContent
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '\t')
          .replaceAll(r'\\', '\\')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\f', '\f')
          .replaceAll(r'\b', '\b')
          .replaceAll(r'\u003C', '<')
          .replaceAll(r'\u003E', '>');
      
      if (innerContent.contains(r'\u')) {
        final buffer = StringBuffer();
        for (int i = 0; i < innerContent.length; i++) {
          if (i + 5 < innerContent.length && 
              innerContent[i] == '\\' && 
              innerContent[i + 1] == 'u') {
            try {
              final hexCode = innerContent.substring(i + 2, i + 6);
              final charCode = int.parse(hexCode, radix: 16);
              buffer.write(String.fromCharCode(charCode));
              i += 5;
            } catch (e) {
              buffer.write(innerContent[i]);
            }
          } else {
            buffer.write(innerContent[i]);
          }
        }
        return buffer.toString();
      }
      
      return innerContent;
    } catch (e) {
      LogUtil.e('HTML清理失败: $e');
      return htmlContent;
    }
  }

  static Future<void> _extractAllMediaLinks(
    WebViewController controller,
    List<String> foundStreams,
    bool usingBackupEngine2, {
    Set<String>? urlCache,
  }) async {
    try {
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      String htmlContent = _cleanHtmlString(html.toString());
      LogUtil.i('获取HTML，长度: ${htmlContent.length}');
      final matches = UrlUtil.mediaLinkRegex.allMatches(htmlContent);
      final totalMatches = matches.length;
      if (totalMatches > 0) LogUtil.i('示例匹配: ${matches.first.group(0)} -> URL: ${matches.first.group(2)}');
      final Set<String> hostMap = urlCache ?? {};
      if (urlCache == null && foundStreams.isNotEmpty) {
        for (final url in foundStreams) {
          try {
            hostMap.add(_getHostKey(url));
          } catch (_) {
            hostMap.add(url);
          }
        }
      }
      final List<String> newLinks = [];
      for (final match in matches) {
        final rawUrl = match.group(2)?.trim();
        if (rawUrl == null || rawUrl.isEmpty) continue;
        final String mediaUrl = rawUrl
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll(RegExp("[\")'&;]+\$"), '');
        if (mediaUrl.isEmpty || _isUrlBlocked(mediaUrl)) continue;
        try {
          final hostKey = _getHostKey(mediaUrl);
          if (hostMap.contains(hostKey)) continue;
          hostMap.add(hostKey);
          newLinks.add(mediaUrl);
        } catch (e) {
          LogUtil.e('URL处理失败: $mediaUrl, $e');
        }
      }
      final int maxToAdd = AppConstants.maxStreams - foundStreams.length;
      if (maxToAdd > 0 && newLinks.isNotEmpty) {
        final addList = newLinks.take(maxToAdd).toList();
        foundStreams.addAll(addList);
      }
      LogUtil.i('链接提取完成: 匹配${totalMatches}个, 新链接${newLinks.length}, 总数${foundStreams.length}');
    } catch (e) {
      LogUtil.e('链接提取失败: $e');
    }
  }

  static String _getHostKey(String url) {
    if (_hostKeyCache.containsKey(url)) {
      final hostKey = _hostKeyCache.remove(url)!;
      _hostKeyCache[url] = hostKey;
      return hostKey;
    }
    final hostKey = UrlUtil.getHostKey(url);
    if (_hostKeyCache.length >= _maxHostKeyCacheSize) {
      _hostKeyCache.remove(_hostKeyCache.keys.first);
    }
    _hostKeyCache[url] = hostKey;
    return hostKey; // 返回URL主机键
  }

  static Future<void> dispose() async {
    try {
      await WebViewPool.clear();
      _searchCache.dispose();
      _hostKeyCache.clear();
      _urlLowerCaseCache.clear();
      LogUtil.i('资源释放完成');
    } catch (e) {
      LogUtil.e('资源释放失败: $e');
    }
  }
}
