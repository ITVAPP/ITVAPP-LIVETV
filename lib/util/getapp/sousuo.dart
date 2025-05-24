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

// 解析阶段枚举
enum ParseStage {
  formSubmission,   // 页面加载与表单提交
  searchResults,    // 搜索结果提取与流测试
  completed,        // 解析完成
  error             // 解析错误
}

/// 应用常量类，集中管理常量
class AppConstants {
  AppConstants._(); // 私有构造函数，防止实例化

  // 状态键
  static const String searchKeyword = 'searchKeyword';           // 搜索关键词
  static const String activeEngine = 'activeEngine';            // 当前搜索引擎
  static const String searchSubmitted = 'searchSubmitted';      // 表单提交状态
  static const String startTimeMs = 'startTimeMs';             // 解析开始时间
  static const String lastHtmlLength = 'lastHtmlLength';       // 当前HTML长度
  static const String stage1StartTime = 'stage1StartTime';     // 阶段1开始时间
  static const String stage2StartTime = 'stage2StartTime';     // 阶段2开始时间
  static const String initialEngineAttempted = 'initialEngineAttempted'; // 初始引擎尝试标志

  // 搜索引擎URL
  static const String initialEngineUrl = 'https://www.iptv-search.com/zh-hans/search/?q='; // 初始搜索引擎URL
  static const String backupEngine1Url = 'http://www.foodieguide.com/iptvsearch/';        // 备用引擎1 URL
  static const String backupEngine2Url = 'https://tonkiang.us/?';                         // 备用引擎2 URL

  // 超时与等待时间
  static const int globalTimeoutSeconds = 28;         // 全局超时（秒）
  static const int maxStreams = 8;                    // 最大媒体流数量
  static const int minValidContentLength = 1000;     // 最小有效内容长度
  static const int maxSearchCacheEntries = 58;       // 搜索缓存最大条目数

  // 流测试参数
  static const int compareTimeWindowMs = 3000;       // 流响应时间窗口（毫秒）
  static const int testOverallTimeoutSeconds = 6;    // 流测试整体超时（秒）

  // 屏蔽关键词
  static const List<String> defaultBlockKeywords = ["freetv.fun", "epg.pw", "ktpremium.com", "serv00.net/Smart.php?id=ettvmovie"]; // 默认屏蔽关键词
}

/// 缓存条目类，存储URL
class _CacheEntry {
  final String url; // 缓存的URL

  _CacheEntry(this.url); // 初始化缓存URL

  Map<String, dynamic> toJson() => {'url': url}; // 转换为JSON

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(json['url'] as String); // 从JSON创建实例
}

/// URL工具类，管理URL操作
class UrlUtil {
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false,
  ); // 媒体链接正则表达式

  static const Set<String> _staticExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.css', '.js', 
    '.ico', '.woff', '.woff2', '.ttf', '.svg'
  }; // 静态资源扩展名

  static bool isStaticResourceUrl(String url) => _staticExtensions.any((ext) => url.endsWith(ext)); // 检查是否为静态资源URL

  static bool isBackupEngine1(String url) => url.contains('foodieguide.com'); // 检查是否为备用引擎1
  static bool isBackupEngine2(String url) => url.contains('tonkiang.us'); // 检查是否为备用引擎2

  static String getHostKey(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.host}:${uri.port}'; // 提取URL主机键
    } catch (e) {
      LogUtil.e('解析URL主机键失败: $url, 错误: $e');
      return url;
    }
  }

  static RegExp getMediaLinkRegex() => _mediaLinkRegex; // 获取媒体链接正则表达式
}

/// 定时器管理类，统一管理定时器
class TimerManager {
  final Map<String, Timer> _timers = {}; // 定时器存储
  bool _isDisposed = false; // 资源释放标志

  Timer _createTimer(String key, Timer Function() timerCreator) {
    if (_isDisposed) {
      LogUtil.i('已释放，忽略定时器: $key');
      return Timer(Duration.zero, () {});
    }
    cancel(key);
    try {
      final timer = timerCreator();
      _timers[key] = timer;
      return timer;
    } catch (e) {
      LogUtil.e('创建定时器($key)失败: $e');
      return Timer(Duration.zero, () {});
    }
  }

  Timer set(String key, Duration duration, Function() callback) => _createTimer(key, () {
    return Timer(duration, () {
      try {
        if (!_isDisposed) callback();
        _timers.remove(key);
      } catch (e) {
        LogUtil.e('定时器($key)回调错误: $e');
        _timers.remove(key);
      }
    });
  }); // 创建单次定时器

  Timer setPeriodic(String key, Duration duration, Function(Timer) callback) => _createTimer(key, () {
    return Timer.periodic(duration, (timer) {
      try {
        callback(timer);
      } catch (e) {
        LogUtil.e('周期定时器($key)回调错误: $e');
        timer.cancel();
        _timers.remove(key);
      }
    });
  }); // 创建周期性定时器

  void cancel(String key) {
    final timer = _timers.remove(key);
    if (timer != null) {
      try {
        timer.cancel();
      } catch (e) {
        LogUtil.e('取消定时器($key)失败: $e');
      }
    }
  } // 取消指定定时器

  bool exists(String key) => _timers.containsKey(key); // 检查定时器是否存在
  int get activeCount => _timers.length; // 获取活跃定时器数量
  void cancelAll() {
    try {
      for (var timer in _timers.values) timer.cancel();
    } finally {
      _timers.clear();
    }
  } // 取消所有定时器
  void dispose() {
    cancelAll();
    _isDisposed = true; // 释放资源
  }
}

/// 脚本管理类，管理JS脚本加载和注入
class ScriptManager {
  static final Map<String, String> _scripts = {}; // 脚本缓存
  static final Map<String, Map<WebViewController, bool>> _injectedScripts = {
    'domMonitor': {},
    'fingerprintRandomization': {},
    'formDetection': {},
  }; // 注入状态记录

  static Future<void> preload() async {
    try {
      await Future.wait([
        _loadScript('assets/js/dom_change_monitor.js'),
        _loadScript('assets/js/fingerprint_randomization.js'),
        _loadScript('assets/js/form_detection.js'),
      ]);
      LogUtil.i('脚本预加载完成');
    } catch (e) {
      LogUtil.e('脚本预加载失败: $e');
    }
  }

  static Future<String> _loadScript(String filePath) async {
    if (_scripts.containsKey(filePath)) return _scripts[filePath]!;
    try {
      final script = await rootBundle.loadString(filePath);
      _scripts[filePath] = script;
      return script;
    } catch (e) {
      LogUtil.e('加载脚本($filePath)失败: $e');
      try {
        final script = await rootBundle.loadString(filePath);
        _scripts[filePath] = script;
        return script;
      } catch (e2) {
        LogUtil.e('二次加载脚本($filePath)失败: $e2');
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
      if (!_scripts.containsKey(scriptKey)) _scripts[scriptKey] = await _loadScript(assetPath);
      String script = _scripts[scriptKey]!;
      replacements.forEach((placeholder, value) => script = script.replaceAll(placeholder, value));
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

  static Future<bool> injectDomMonitor(WebViewController controller, String channelName) =>
      _injectScript('domMonitor', 'assets/js/dom_change_monitor.js', controller, {'%CHANNEL_NAME%': channelName}, 'DOM监听器'); // 注入DOM监听器脚本

  static Future<bool> injectFingerprintRandomization(WebViewController controller) =>
      _injectScript('fingerprintRandomization', 'assets/js/fingerprint_randomization.js', controller, {}, '指纹随机化脚本'); // 注入指纹随机化脚本

  static Future<bool> injectFormDetection(WebViewController controller, String searchKeyword) {
    final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
    return _injectScript('formDetection', 'assets/js/form_detection.js', controller, {'%SEARCH_KEYWORD%': escapedKeyword}, '表单检测脚本'); // 注入表单检测脚本
  }

  static void clearControllerState(WebViewController controller) {
    for (var controllers in _injectedScripts.values) controllers.remove(controller); // 清除控制器的注入状态
  }

  static void clearAll() {
    for (var controllers in _injectedScripts.values) controllers.clear(); // 清除所有脚本状态
  }
}

/// WebView池管理类，提升WebView复用效率
class WebViewPool {
  static final List<WebViewController> _pool = []; // WebView控制器池
  static const int maxPoolSize = 2; // 最大池大小
  static final Completer<void> _initCompleter = Completer<void>(); // 初始化完成器
  static bool _isInitialized = false; // 初始化标志
  static final Set<WebViewController> _disposingControllers = {}; // 正在清理的控制器集合

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent)
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (error) => LogUtil.e('WebView资源错误: ${error.description}, 错误码: ${error.errorCode}'),
        ));
      await controller.loadHtmlString('<html><body></body></html>');
      _pool.add(controller);
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    } catch (e) {
      LogUtil.e('WebView池初始化失败: $e');
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
    }
  }

  static Future<WebViewController> acquire() async {
    if (!_isInitialized) await initialize();
    if (!_initCompleter.isCompleted) await _initCompleter.future;
    if (_pool.isNotEmpty) return _pool.removeLast();
    LogUtil.i('池为空，创建新WebView');
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) => LogUtil.e('WebView资源错误: ${error.description}, 错误码: ${error.errorCode}'),
      ));
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
    if (controller == null) return;
    if (_disposingControllers.contains(controller)) return;
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
        LogUtil.e('清理WebView失败: $cleanupError');
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
        LogUtil.e('清理WebView失败: $e');
      }
    }
    _pool.clear();
    _disposingControllers.clear();
    ScriptManager.clearAll();
    LogUtil.i('WebView池已清空');
  }
}

/// 搜索结果缓存类，支持关键词规范化
class _SearchCache {
  static const String _cacheKey = 'search_cache_data'; // 持久化存储键
  static const String _lruKey = 'search_cache_lru'; // LRU顺序键
  final int maxEntries; // 最大缓存条目数
  final Map<String, _CacheEntry> _cache = LinkedHashMap<String, _CacheEntry>(); // 缓存存储
  bool _isDirty = false; // 缓存脏标志
  Timer? _persistTimer; // 持久化定时器
  static final Map<String, String> _normalizedKeywordCache = <String, String>{}; // 关键词规范化缓存

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
    if (_normalizedKeywordCache.containsKey(keyword)) return _normalizedKeywordCache[keyword]!;
    final normalized = keyword.trim().toLowerCase();
    if (_normalizedKeywordCache.length >= 50) _normalizedKeywordCache.remove(_normalizedKeywordCache.keys.first);
    _normalizedKeywordCache[keyword] = normalized;
    return normalized; // 规范化关键词
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
        for (final key in lruOrder) {
          if (data.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              _cache[key] = _CacheEntry.fromJson(data[key]);
            } catch (e) {
              LogUtil.e('解析缓存($key)失败: $e');
            }
          }
        }
        for (final key in data.keys) {
          if (!_cache.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              _cache[key] = _CacheEntry.fromJson(data[key]);
            } catch (e) {
              LogUtil.e('解析缓存($key)失败: $e');
            }
          }
        }
        while (_cache.length > maxEntries && _cache.isNotEmpty) _cache.remove(_cache.keys.first);
        LogUtil.i('加载缓存: ${_cache.length}条');
      }
    } catch (e) {
      LogUtil.e('加载缓存失败: $e');
      _cache.clear();
    }
  }

  void _saveToPersistence() {
    try {
      final Map<String, dynamic> data = {};
      _cache.forEach((key, entry) => data[key] = entry.toJson());
      SpUtil.putString(_cacheKey, jsonEncode(data));
      SpUtil.putString(_lruKey, jsonEncode(_cache.keys.toList()));
    } catch (e) {
      LogUtil.e('保存缓存失败: $e');
    }
  }

  String? getUrl(String keyword, {bool forceRemove = false}) {
    final normalizedKeyword = _normalizeKeyword(keyword);
    final entry = _cache[normalizedKeyword];
    if (entry == null) return null;
    if (forceRemove) {
      final url = entry.url;
      _cache.remove(normalizedKeyword);
      _isDirty = true;
      _saveToPersistence();
      LogUtil.i('移除缓存: $normalizedKeyword -> $url');
      return null;
    }
    final cachedUrl = entry.url;
    _cache.remove(normalizedKeyword);
    _cache[normalizedKeyword] = entry;
    _isDirty = true;
    return cachedUrl; // 获取缓存URL
  }

  void addUrl(String keyword, String url) {
    if (keyword.isEmpty || url.isEmpty || url == 'ERROR') return;
    final normalizedKeyword = _normalizeKeyword(keyword);
    _cache.remove(normalizedKeyword);
    if (_cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      LogUtil.i('移除最旧缓存: $oldest');
    }
    _cache[normalizedKeyword] = _CacheEntry(url);
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

  int get size => _cache.length; // 获取缓存大小
  void dispose() {
    try {
      if (_isDirty) _saveToPersistence();
    } catch (e) {
      LogUtil.e('保存缓存失败: $e');
    } finally {
      _persistTimer?.cancel();
      _persistTimer = null;
    }
  }
}

/// 解析会话类，管理解析逻辑和状态
class _ParserSession {
  final Completer<String> completer = Completer<String>(); // 异步任务完成器
  final List<String> foundStreams = []; // 发现的流地址
  WebViewController? controller; // WebView控制器
  final TimerManager _timerManager = TimerManager(); // 定时器管理器
  bool isResourceCleaned = false; // 资源清理状态
  bool isTestingStarted = false; // 流测试开始状态
  bool isExtractionInProgress = false; // 提取进行中状态
  bool isCollectionFinished = false; // 收集完成状态
  bool hasRegisteredJsChannel = false; // JavaScript通道注册标志
  ParseStage currentStage = ParseStage.formSubmission; // 当前解析阶段
  final Map<String, dynamic> searchState = {
    AppConstants.searchKeyword: '', // 搜索关键词
    AppConstants.activeEngine: 'backup1', // 默认备用引擎1
    AppConstants.searchSubmitted: false, // 表单未提交
    AppConstants.startTimeMs: DateTime.now().millisecondsSinceEpoch, // 解析开始时间
    AppConstants.lastHtmlLength: 0, // 当前HTML长度
    AppConstants.stage1StartTime: DateTime.now().millisecondsSinceEpoch, // 阶段1开始时间
    AppConstants.stage2StartTime: 0, // 阶段2未开始
    AppConstants.initialEngineAttempted: false, // 初始引擎尝试标志
  };
  final Map<String, int> _lastPageFinishedTime = {}; // 页面加载防抖映射
  StreamSubscription? cancelListener; // 取消事件监听器
  final CancelToken? cancelToken; // 任务取消令牌
  bool _isCleaningUp = false; // 资源清理锁
  final Map<String, bool> _urlCache = {}; // URL去重缓存
  bool isCompareDone = false; // 流比较完成标志

  _ParserSession({this.cancelToken, String? initialEngine}) {
    if (initialEngine != null) searchState[AppConstants.activeEngine] = initialEngine; // 设置初始引擎
    if (initialEngine == 'backup1' || initialEngine == 'backup2') searchState[AppConstants.initialEngineAttempted] = true; // 标记初始引擎尝试
  }

  bool get isCancelled => cancelToken?.isCancelled ?? false; // 检查取消状态

  Future<String?> _safeRunJavaScript(String script, {String? defaultValue}) async {
    try {
      final result = await controller!.runJavaScriptReturningResult(script);
      return result?.toString() ?? defaultValue;
    } catch (e) {
      LogUtil.e('执行JavaScript失败: $e');
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
      if (!completer.isCompleted) {
        completer.complete(selectedStream);
        LogUtil.i('流选择结果已传递');
      }
    }
  }

  void finishCollectionAndTest() {
    if (isCancelled) {
      LogUtil.i('任务取消，中止收集');
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
      _timerManager.cancel('delayedContentChange');
      _timerManager.cancel('compareWindow');
      _timerManager.cancel('streamTestTimeout');
      _timerManager.cancel('contentChangeDebounce');
      _timerManager.cancelAll();
      if (cancelListener != null) {
        try {
          await cancelListener!.cancel().timeout(Duration(milliseconds: 500), onTimeout: () => LogUtil.i('取消监听器超时'));
        } catch (e) {
          LogUtil.e('取消监听器失败: $e');
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
          LogUtil.i('即时模式清理本地存储');
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
    _timerManager.set('compareWindow', Duration(milliseconds: AppConstants.compareTimeWindowMs), () {
      if (!isCompareDone && !resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      }
    }); // 设置比较窗口定时器
    _timerManager.set('streamTestTimeout', Duration(seconds: AppConstants.testOverallTimeoutSeconds), () {
      if (!resultCompleter.isCompleted) {
        if (successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter, cancelToken);
        } else {
          LogUtil.i('流测试超时: ${AppConstants.testOverallTimeoutSeconds}秒');
          resultCompleter.complete('ERROR');
        }
      }
    }); // 设置测试超时定时器
    try {
      final testFutures = streams.map((stream) => 
        _testSingleStream(stream, successfulStreams, cancelToken, resultCompleter)).toList();
      await Future.any([Future.wait(testFutures), resultCompleter.future.then((_) => null)]);
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
           lowerUrl.startsWith('rtsp:');
  }

  Future<bool> _testSingleStream(
    String streamUrl,
    Map<String, int> successfulStreams,
    CancelToken cancelToken,
    Completer<String> resultCompleter,
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
        // 如果不是直接的流格式，需要检查内容
        if (!_isDirectStreamUrl(streamUrl)) {
          final responseData = response.data as String;
          if (responseData.isEmpty || !responseData.trim().startsWith('#EXTM3U')) {
            LogUtil.i('流内容格式无效: $streamUrl');
            return false;
          }
        }
        successfulStreams[streamUrl] = testTime;
        if (testTime < 1000 && !isCompareDone) {
          _selectBestStream({streamUrl: testTime}, resultCompleter, cancelToken);
        }
        return true;
      }
    } catch (e) {
      if (!cancelToken.isCancelled) LogUtil.e('流测试失败: $streamUrl, 错误: $e');
    }
    return false;
  }

  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('流测试已开始，忽略重复请求');
      return;
    }
    if (isCancelled) {
      LogUtil.i('任务取消，中止测试');
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
      LogUtil.i('任务取消，中止测试');
      return;
    }
    _testStreamsAsync(cancelToken, null);
  }

  Future<void> _testStreamsAsync(CancelToken? testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      final result = await _testAllStreamsConcurrently(foundStreams, testCancelToken ?? CancelToken());
      LogUtil.i('测试完成: ${result == 'ERROR' ? '无可用流' : '找到可用流'}');
      if (!completer.isCompleted) {
        completer.complete(result);
        cleanupResources();
      }
    } catch (e) {
      LogUtil.e('测试流失败: $e');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    } finally {
      try {
        await testCancelListener?.cancel();
      } catch (e) {
        LogUtil.e('取消测试监听器失败: $e');
      }
    }
  }

  bool _shouldSwitchEngine() {
    final currentEngine = searchState[AppConstants.activeEngine] as String;
    return currentEngine != 'backup2'; // 检查是否需要切换引擎
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
        LogUtil.i('任务取消，停止切换引擎');
        return;
      }
      LogUtil.i('切换引擎: $currentEngine -> $nextEngine');
      searchState[AppConstants.activeEngine] = nextEngine;
      searchState[AppConstants.searchSubmitted] = false;
      searchState[AppConstants.lastHtmlLength] = 0;
      currentStage = ParseStage.formSubmission;
      searchState[AppConstants.stage1StartTime] = DateTime.now().millisecondsSinceEpoch;
      isCollectionFinished = false;
      if (controller != null) {
        ScriptManager.clearControllerState(controller!);
        LogUtil.i('清理ScriptManager控制器状态');
        await controller!.loadRequest(Uri.parse(nextEngineUrl));
        LogUtil.i('加载引擎: $nextEngine ($nextEngineUrl)');
      } else {
        LogUtil.e('WebView控制器为空');
        throw Exception('WebView控制器为空');
      }
    } catch (e) {
      LogUtil.e('切换引擎失败: $e');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }

  void handleContentChange() {
    _timerManager.cancel('contentChangeDebounce');
    if (isCancelled || isTestingStarted || isExtractionInProgress) return;
    _timerManager.set('contentChangeDebounce', Duration(milliseconds: 1000), () async {
      if (controller == null || completer.isCompleted || isCancelled || isTestingStarted || isExtractionInProgress) return;
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
            LogUtil.i('新增链接: ${afterExtractCount - beforeExtractCount}, 总数: $afterExtractCount');
            if (afterExtractCount >= AppConstants.maxStreams) finishCollectionAndTest();
          } else if (_shouldSwitchEngine() && afterExtractCount == 0) {
            switchToNextEngine();
          } else if (afterExtractCount > 0) {
            finishCollectionAndTest();
          }
        }
      } catch (e) {
        LogUtil.e('处理内容变化失败: $e');
      } finally {
        isExtractionInProgress = false;
      }
    }); // 设置内容变化防抖定时器
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
          LogUtil.e('解析关键词失败: $e');
        }
      }
      await Future.wait([
        ScriptManager.injectFingerprintRandomization(controller!),
        ScriptManager.injectFormDetection(controller!, searchKeyword)
      ].map((future) => future.catchError((e) {
        LogUtil.e('脚本注入失败: $e');
        return null;
      })));
    }
  }

  Future<void> handlePageFinished(String pageUrl) async {
    if (controller == null || isCancelled) return;
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastPageFinishedTime.containsKey(pageUrl) && currentTimeMs - _lastPageFinishedTime[pageUrl]! < 300) return;
    _lastPageFinishedTime[pageUrl] = currentTimeMs;
    final startMs = searchState[AppConstants.startTimeMs] as int;
    LogUtil.i('页面加载完成: $pageUrl, 耗时: ${currentTimeMs - startMs}ms');
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
      _timerManager.set('delayedContentChange', Duration(seconds: 1), () {
        if (controller != null && !completer.isCompleted && !isCancelled && !isCollectionFinished && !isTestingStarted && !isExtractionInProgress) {
          LogUtil.i('触发延迟内容变化处理');
          handleContentChange();
        }
      }); // 设置延迟内容变化定时器
    }
  }

  bool _isStaticResource(String url) => UrlUtil.isStaticResourceUrl(url); // 检查是否为静态资源

  bool _isCriticalNetworkError(int errorCode) => const [-1, -2, -3, -6, -7, -101, -105, -106].contains(errorCode); // 检查关键网络错误

  void handleWebResourceError(WebResourceError error) {
    if (controller == null || isCancelled) return;
    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url}');
    if (error.url == null || _isStaticResource(error.url!)) return;
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
    LogUtil.i('收到JavaScript消息: ${message.message}');
    switch (message.message) {
      case 'CONTENT_READY':
        _timerManager.cancel('delayedContentChange'); // 取消延迟兜底
        handleContentChange();
        break;
      case 'FORM_SUBMITTED':
      	searchState[AppConstants.searchSubmitted] = true;
        currentStage = ParseStage.searchResults;
        searchState[AppConstants.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
        // 表单提交后延迟1秒注入结果页面脚本
        _timerManager.set('delayedScriptInjection', Duration(seconds: 1), () async {
          if (controller != null && !isCancelled) {
            ScriptManager.clearControllerState(controller!);
            await Future.wait([
              ScriptManager.injectDomMonitor(controller!, 'AppChannel')
            ].map((future) => future.catchError((e) {
              LogUtil.e('脚本注入失败: $e');
              return null;
            })));
          }
        });
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
        LogUtil.i('任务取消，返回ERROR');
        return 'ERROR';
      }
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无有效搜索关键词');
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
        LogUtil.i('尝试测试已有流: ${foundStreams.length}个');
        try {
          final result = await _testAllStreamsConcurrently(foundStreams, cancelToken ?? CancelToken());
          if (!completer.isCompleted) completer.complete(result);
          return result;
        } catch (testError) {
          LogUtil.e('测试流失败: $testError');
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

/// 任务状态跟踪类，用于调试统计
class _ParseTaskTracker {
  static final Map<String, DateTime> _activeTasks = {};

  static void startTask(String taskKey) {
    _activeTasks[taskKey] = DateTime.now();
    LogUtil.i('开始搜索任务: $taskKey');
  }

  static void endTask(String taskKey) {
    final startTime = _activeTasks.remove(taskKey);
    if (startTime != null) {
      LogUtil.i('任务完成: $taskKey, 耗时: ${DateTime.now().difference(startTime).inMilliseconds}ms');
    }
  }

  static int get activeTaskCount => _activeTasks.length; // 获取活跃任务数量
  static void clearAll() => _activeTasks.clear(); // 清理任务跟踪
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static List<String> _blockKeywords = AppConstants.defaultBlockKeywords;
  static final _SearchCache _searchCache = _SearchCache();
  static final LinkedHashMap<String, String> _hostKeyCache = LinkedHashMap<String, String>();
  static final _ParseTaskTracker _taskTracker = _ParseTaskTracker();

  static bool _isStaticResourceUrl(String url) => UrlUtil.isStaticResourceUrl(url); // 检查静态资源URL

  static Future<void> initialize() async {
    await WebViewPool.initialize();
    await ScriptManager.preload();
    LogUtil.i('解析器初始化完成');
  }

  static void setBlockKeywords(String keywords) {
    _blockKeywords = keywords.isNotEmpty 
        ? keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() 
        : AppConstants.defaultBlockKeywords; // 设置屏蔽关键词
  }

  static bool _isUrlBlocked(String url) {
    if (_blockKeywords.isEmpty) return false;
    return _blockKeywords.any((keyword) => url.toLowerCase().contains(keyword.toLowerCase())); // 检查URL是否被屏蔽
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
      LogUtil.i('缓存URL验证失败，移除: $keyword, 错误: $e');
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
          LogUtil.e('WebView清理失败: $e');
          try {
            await WebViewPool.release(tempController);
          } catch (releaseError) {
            LogUtil.e('释放WebView失败: $releaseError');
          }
        }
      }
      LogUtil.i('初始引擎资源清理完成');
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
          LogUtil.i('初始引擎内容就绪');
          if (!pageLoadCompleter.isCompleted) pageLoadCompleter.complete(searchUrl);
        }
      });
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          if (url != 'about:blank') {
            LogUtil.i('初始引擎页面加载: $url');
            try {
              await Future.wait([
                ScriptManager.injectDomMonitor(controller!, 'AppChannel'),
                ScriptManager.injectFingerprintRandomization(controller!)
              ].map((future) => future.catchError((e) {
                LogUtil.e('初始引擎脚本注入失败: $e');
                return null;
              })));
              LogUtil.i('初始引擎脚本注入成功');
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
        html = _cleanHtmlString(result.toString()).replaceAll(r'\u003C', '<').replaceAll(r'\u003E', '>');
        LogUtil.i('初始引擎HTML长度: ${html.length}');
      } catch (e) {
        LogUtil.e('获取HTML失败: $e');
        await cleanupResources();
        completer.complete(null);
        return null;
      }
      final List<String> extractedUrls = [];
      final linkRegex = RegExp(
        r'(?:<|\\u003C)span\s+class="decrypted-link"(?:>|\\u003E)\s*(http[^<\\]+?)(?:<|\\u003C)/span',
        caseSensitive: false,
      );
      final matches = linkRegex.allMatches(html);
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
    String? taskKey;
    try {
      if (blockKeywords.isNotEmpty) setBlockKeywords(blockKeywords);
      String? searchKeyword;
      try {
        final uri = Uri.parse(url);
        searchKeyword = uri.queryParameters['clickText'];
      } catch (e) {
        LogUtil.e('提取关键词失败: $e');
        return 'ERROR';
      }
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无有效关键词');
        return 'ERROR';
      }
      taskKey = searchKeyword.trim().toLowerCase();
      _ParseTaskTracker.startTask(taskKey);
      final Completer<String> timeoutCompleter = Completer<String>();
      globalTimer = Timer(Duration(seconds: AppConstants.globalTimeoutSeconds), () {
        LogUtil.i('全局超时: $taskKey');
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
      if (taskKey != null) _ParseTaskTracker.endTask(taskKey);
    }
  }

  static int get activeTaskCount => _ParseTaskTracker.activeTaskCount; // 获取活跃任务数量
  static void clearActiveTasks() => _ParseTaskTracker.clearAll(); // 清理活跃任务

  static String _cleanHtmlString(String htmlContent) {
    final length = htmlContent.length;
    if (length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) return htmlContent;
    try {
      final innerContent = htmlContent.substring(1, length - 1);
      final buffer = StringBuffer();
      for (int i = 0; i < innerContent.length; i++) {
        if (innerContent[i] == '\\' && i + 1 < innerContent.length) {
          final nextChar = innerContent[i + 1];
          switch (nextChar) {
            case '"': buffer.write('"'); i++; break;
            case 'n': buffer.write('\n'); i++; break;
            case 't': buffer.write('\t'); i++; break;
            case '\\': buffer.write('\\'); i++; break;
            case 'r': buffer.write('\r'); i++; break;
            case 'f': buffer.write('\f'); i++; break;
            case 'b': buffer.write('\b'); i++; break;
            case 'u':
              if (i + 5 < innerContent.length) {
                try {
                  final hexCode = innerContent.substring(i + 2, i + 6);
                  final charCode = int.parse(hexCode, radix: 16);
                  buffer.write(String.fromCharCode(charCode));
                  i += 5;
                } catch (e) {
                  buffer.write(innerContent[i]);
                  i++;
                }
              } else {
                buffer.write(innerContent[i]);
                i++;
              }
              break;
            default: 
              buffer.write(innerContent[i]);
              i++;
              break;
          }
        } else {
          buffer.write(innerContent[i]);
        }
      }
      return buffer.toString();
    } catch (e) {
      LogUtil.e('清理HTML失败: $e');
      return htmlContent;
    }
  }

  static Future<void> _extractAllMediaLinks(
    WebViewController controller,
    List<String> foundStreams,
    bool usingBackupEngine2, {
    Map<String, bool>? urlCache,
  }) async {
    try {
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      String htmlContent = _cleanHtmlString(html.toString());
      LogUtil.i('获取HTML，长度: ${htmlContent.length}');
      final matches = UrlUtil.getMediaLinkRegex().allMatches(htmlContent);
      final totalMatches = matches.length;
      if (totalMatches > 0) LogUtil.i('示例匹配: ${matches.first.group(0)} -> URL: ${matches.first.group(2)}');
      final Set<String> existingStreams = foundStreams.toSet();
      final Set<String> newLinks = {};
      final Map<String, bool> hostMap = urlCache ?? {};
      if (urlCache == null && existingStreams.isNotEmpty) {
        for (final url in existingStreams) {
          try {
            hostMap[_getHostKey(url)] = true;
          } catch (_) {
            hostMap[url] = true;
          }
        }
      }
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
          if (hostMap.containsKey(hostKey)) continue;
          hostMap[hostKey] = true;
          newLinks.add(mediaUrl);
        } catch (e) {
          LogUtil.e('处理URL失败: $mediaUrl, 错误: $e');
        }
      }
      final int maxToAdd = AppConstants.maxStreams - foundStreams.length;
      if (maxToAdd > 0 && newLinks.isNotEmpty) {
        final addList = newLinks.take(maxToAdd).toList();
        foundStreams.addAll(addList);
        LogUtil.i('添加新链接: ${addList.length}, 总数: ${foundStreams.length}');
      }
      LogUtil.i('提取完成: 匹配${totalMatches}个, 新链接${newLinks.length}, 总数${foundStreams.length}');
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
    if (_hostKeyCache.length >= 100) _hostKeyCache.remove(_hostKeyCache.keys.first);
    _hostKeyCache[url] = hostKey;
    return hostKey; // 获取主机键值
  }

  static Future<void> dispose() async {
    try {
      _ParseTaskTracker.clearAll();
      await WebViewPool.clear();
      _searchCache.dispose();
      _hostKeyCache.clear();
      LogUtil.i('资源释放完成');
    } catch (e) {
      LogUtil.e('资源释放失败: $e');
    }
  }
}
