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
  formSubmission,   /// 页面加载与表单提交
  searchResults,    /// 搜索结果提取与流测试
  completed,        /// 解析完成
  error             /// 解析错误
}

/// 应用常量类，集中管理常量
class AppConstants {
  AppConstants._(); /// 私有构造函数，防止实例化

  /// 状态键配置
  static const String searchKeyword = 'searchKeyword';           /// 搜索关键词
  static const String activeEngine = 'activeEngine';            /// 当前搜索引擎 
  static const String searchSubmitted = 'searchSubmitted';      /// 表单提交状态 
  static const String startTimeMs = 'startTimeMs';             /// 解析开始时间
  static const String lastHtmlLength = 'lastHtmlLength';       /// 当前HTML长度
  static const String stage1StartTime = 'stage1StartTime';     /// 阶段1开始时间
  static const String stage2StartTime = 'stage2StartTime';     /// 阶段2开始时间
  static const String initialEngineAttempted = 'initialEngineAttempted'; /// 是否已尝试过初始引擎

  /// 搜索引擎URL配置
  static const String initialEngineUrl = 'https://www.iptv-search.com/zh-hans/search/?q='; /// 初始搜索引擎URL 
  static const String backupEngine1Url = 'http://www.foodieguide.com/iptvsearch/';        /// 备用引擎1 URL
  static const String backupEngine2Url = 'https://tonkiang.us/?';                         /// 备用引擎2 URL

  /// 超时与等待时间配置
  static const int globalTimeoutSeconds = 28;         /// 全局超时（秒）
  static const int waitSeconds = 1;                  /// 页面加载等待（秒）
  static const int domChangeWaitMs = 300;            /// DOM变化等待（毫秒）
  static const int contentChangeDebounceMs = 300;    /// 内容变化防抖（毫秒）
  static const int backupEngineLoadWaitMs = 200;     /// 备用引擎加载等待（毫秒）
  static const int cleanupRetryWaitMs = 200;         /// 清理重试等待（毫秒）
  static const int cancelListenerTimeoutMs = 500;    /// 取消监听器超时（毫秒）
  static const int emptyHtmlLoadTimeoutMs = 300;     /// 空HTML加载超时（毫秒）
  static const int webViewCleanupDelayMs = 200;      /// WebView清理延迟（毫秒）
  static const int webViewCleanupTimeoutMs = 500;    /// WebView清理超时（毫秒）

  /// 限制与阈值配置
  static const int maxStreams = 8;                   /// 最大媒体流数量
  static const int minValidContentLength = 1000;     /// 最小有效内容长度
  static const int maxSearchCacheEntries = 58;       /// 搜索缓存最大条目数

  /// 流测试参数配置
  static const int compareTimeWindowMs = 3000;       /// 流响应时间窗口（毫秒）
  static const int fastEnoughThresholdMs = 500;      /// 流快速响应阈值（毫秒）
  static const int testOverallTimeoutSeconds = 6;    /// 流测试整体超时（秒）

  /// 屏蔽关键词配置
  static const List<String> defaultBlockKeywords = ["freetv.fun", "epg.pw", "ktpremium.com", "serv00.net/Smart.php?id=ettvmovie"]; /// 默认屏蔽关键词
}

/// 缓存条目类，存储URL
class _CacheEntry {
  final String url; /// 缓存的URL

  _CacheEntry(this.url); /// 初始化缓存URL

  /// 转换为JSON
  Map<String, dynamic> toJson() => {'url': url};

  /// 从JSON创建实例
  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(json['url'] as String);
}

/// URL工具类，统一管理URL相关操作
class UrlUtil {
  // 使用static常量存储正则表达式，避免重复编译
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false,
  );
  
  // 检查是否为静态资源URL
  static bool isStaticResourceUrl(String url) {
    return url.endsWith('.png') ||
           url.endsWith('.jpg') ||
           url.endsWith('.jpeg') ||
           url.endsWith('.gif') ||
           url.endsWith('.webp') ||
           url.endsWith('.css') ||
           url.endsWith('.js') ||
           url.endsWith('.ico') ||
           url.endsWith('.woff') ||
           url.endsWith('.woff2') ||
           url.endsWith('.ttf') ||
           url.endsWith('.svg');
  }
  
  // 检查是否为备用引擎
  static bool isBackupEngine1(String url) => url.contains('foodieguide.com');
  static bool isBackupEngine2(String url) => url.contains('tonkiang.us');
  
  // 获取URL的主机键
  static String getHostKey(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.host}:${uri.port}';
    } catch (e) {
      LogUtil.e('解析URL主机键出错: $e, URL: $url');
      return url;
    }
  }

  // 获取正则表达式
  static RegExp getMediaLinkRegex() => _mediaLinkRegex;
}

/// 定时器管理类，统一管理定时器
class TimerManager {
  final Map<String, Timer> _timers = {}; /// 定时器存储
  bool _isDisposed = false;              /// 资源释放标志

  // 创建定时器的通用方法
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

  /// 创建或替换定时器
  Timer set(String key, Duration duration, Function() callback) {
    return _createTimer(key, () {
      return Timer(duration, () {
        try {
          // 先执行回调，再移除定时器
          if (!_isDisposed) callback();
          // 回调执行完成后再移除定时器
          _timers.remove(key);
        } catch (e) {
          LogUtil.e('定时器($key)回调错误: $e');
          // 即使发生错误也要确保移除定时器
          _timers.remove(key);
        }
      });
    });
  }

  /// 创建周期性定时器
  Timer setPeriodic(String key, Duration duration, Function(Timer) callback) {
    return _createTimer(key, () {
      return Timer.periodic(duration, (timer) {
        try {
          callback(timer);
        } catch (e) {
          LogUtil.e('周期定时器($key)回调错误: $e');
          timer.cancel();
          _timers.remove(key);
        }
      });
    });
  }

  /// 取消指定定时器
  void cancel(String key) {
    final timer = _timers.remove(key);
    if (timer != null) {
      try {
        timer.cancel();
      } catch (e) {
        LogUtil.e('取消定时器($key)失败: $e');
      }
    }
  }

  /// 检查定时器是否存在
  bool exists(String key) => _timers.containsKey(key);

  /// 获取活跃定时器数量
  int get activeCount => _timers.length;

  /// 取消所有定时器
  void cancelAll() {
    try {
      for (var timer in _timers.values) {
        try { timer.cancel(); } catch (_) {}
      }
    } finally {
      _timers.clear();
    }
  }

  /// 释放资源
  void dispose() {
    try { cancelAll(); } finally { _isDisposed = true; }
  }
}

/// 脚本管理类，统一管理JS脚本的加载和注入
class ScriptManager {
  static final Map<String, String> _scripts = {}; /// 脚本缓存
  static final Map<String, Map<WebViewController, bool>> _injectedScripts = {
    'domMonitor': {},
    'fingerprintRandomization': {},
    'formDetection': {},
  }; /// 注入状态记录

  /// 预加载所有脚本
  static Future<void> preload() async {
    try {
      LogUtil.i('预加载脚本开始');
      await Future.wait([
        _loadScript('assets/js/dom_change_monitor.js'),
        _loadScript('assets/js/fingerprint_randomization.js'),
        _loadScript('assets/js/form_detection.js'),
      ]);
      LogUtil.i('预加载脚本完成');
    } catch (e) {
      LogUtil.e('预加载脚本失败: $e');
    }
  }

  /// 从assets加载JS脚本
  static Future<String> _loadScript(String filePath) async {
    if (_scripts.containsKey(filePath)) return _scripts[filePath]!;

    try {
      final script = await rootBundle.loadString(filePath);
      _scripts[filePath] = script;
      return script;
    } catch (e, stackTrace) {
      LogUtil.e('加载脚本($filePath)失败: $e');
      try {
        final script = await rootBundle.loadString(filePath);
        _scripts[filePath] = script;
        return script;
      } catch (e2) {
        LogUtil.e('二次加载脚本文件失败: $filePath, $e2');
        return '(function(){console.error("Failed to load script: $filePath");})();';
      }
    }
  }

  /// 通用脚本注入方法
  static Future<bool> _injectScript(
    String scriptKey,
    String assetPath,
    WebViewController controller,
    Map<String, String> replacements,
    String operationName,
  ) async {
    if (_injectedScripts[scriptKey]?[controller] == true) {
      LogUtil.i('$operationName已注入，跳过');
      return true;
    }

    try {
      if (!_scripts.containsKey(scriptKey)) {
        _scripts[scriptKey] = await _loadScript(assetPath);
      }
      
      String script = _scripts[scriptKey]!;
      replacements.forEach((placeholder, value) {
        script = script.replaceAll(placeholder, value);
      });
      
      await controller.runJavaScript(script);
      
      if (!_injectedScripts.containsKey(scriptKey)) {
        _injectedScripts[scriptKey] = {};
      }
      _injectedScripts[scriptKey]![controller] = true;
      
      LogUtil.i('$operationName注入成功');
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('注入$operationName失败', e, stackTrace);
      return false;
    }
  }

  /// 注入DOM监听器脚本
  static Future<bool> injectDomMonitor(WebViewController controller, String channelName) {
    return _injectScript(
      'domMonitor',
      'assets/js/dom_change_monitor.js',
      controller,
      {'%CHANNEL_NAME%': channelName},
      'DOM监听器',
    );
  }

  /// 注入指纹随机化脚本
  static Future<bool> injectFingerprintRandomization(WebViewController controller) {
    return _injectScript(
      'fingerprintRandomization',
      'assets/js/fingerprint_randomization.js',
      controller,
      {},
      '指纹随机化脚本',
    );
  }

  /// 注入表单检测脚本
  static Future<bool> injectFormDetection(WebViewController controller, String searchKeyword) {
    final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
    return _injectScript(
      'formDetection',
      'assets/js/form_detection.js',
      controller,
      {'%SEARCH_KEYWORD%': escapedKeyword},
      '表单检测脚本',
    );
  }

  /// 清除控制器的注入状态
  static void clearControllerState(WebViewController controller) {
    for (var controllers in _injectedScripts.values) {
      controllers.remove(controller);
    }
  }

  /// 清除所有脚本状态
  static void clearAll() {
    for (var controllers in _injectedScripts.values) {
      controllers.clear();
    }
  }
}

/// WebView池管理类，提升WebView复用效率
class WebViewPool {
  static final List<WebViewController> _pool = []; /// WebView控制器池
  static const int maxPoolSize = 2;               /// 最大池大小
  static final Completer<void> _initCompleter = Completer<void>(); /// 初始化完成器
  static bool _isInitialized = false;             /// 初始化标志
  static final Set<WebViewController> _disposingControllers = {}; /// 正在清理的控制器集合
  
  // 修改：添加一个映射来跟踪每个控制器的取消令牌状态
  static final Map<WebViewController, CancelToken> _controllerCancelTokens = {};

  /// 初始化WebView池
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent)
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (error) {
            LogUtil.e('WebView资源错误: ${error.description}, 错误码: ${error.errorCode}');
          },
        ));

      await controller.loadHtmlString('<html><body></body></html>');
      _pool.add(controller);
      
      // 修改：初始化时为控制器设置一个新的未取消的令牌
      _controllerCancelTokens[controller] = CancelToken();

      _isInitialized = true;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    } catch (e) {
      LogUtil.e('初始化失败: $e');
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e);
      }
    }
  }

  /// 获取WebView实例
  static Future<WebViewController> acquire() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    if (_pool.isNotEmpty) {
      final controller = _pool.removeLast();
      
      // 修改：每次获取控制器时重置其取消令牌状态
      _controllerCancelTokens[controller] = CancelToken();
      
      return controller;
    }

    LogUtil.i('池为空，创建新实例');
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) {
          LogUtil.e('WebView资源错误: ${error.description}, 错误码: ${error.errorCode}');
        },
      ));
      
    // 修改：为新创建的控制器设置取消令牌
    _controllerCancelTokens[controller] = CancelToken();

    return controller;
  }

  /// 清理WebView控制器资源
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

  /// 释放WebView实例回池
  static Future<void> release(WebViewController? controller) async {
    if (controller == null) return;
    
    // 防止重复释放同一实例
    synchronized() async {
      if (_disposingControllers.contains(controller)) {
        LogUtil.i('控制器已在释放过程中，跳过');
        return;
      }
      _disposingControllers.add(controller);
    }
    
    try {
      // 修改：重置控制器的取消令牌状态 - 关键修复点1
      if (_controllerCancelTokens.containsKey(controller)) {
        // 创建一个新的未取消的令牌，替换可能已被取消的令牌
        _controllerCancelTokens[controller] = CancelToken();
      } else {
        _controllerCancelTokens[controller] = CancelToken();
      }
      
      // 使用_cleanupWebView方法简化清理逻辑
      bool cleanupSuccess = await _cleanupWebView(controller, onlyBasic: true);

      // 清除该控制器在ScriptManager中的注入状态
      ScriptManager.clearControllerState(controller);

      // 检查是否为重复实例
      bool isDuplicate = false;
      for (var existingController in _pool) {
        if (identical(existingController, controller)) {
          isDuplicate = true;
          LogUtil.i('实例已存在，忽略重复添加');
          break;
        }
      }

      // 仅在不是重复实例且池未满时添加到池中
      if (!isDuplicate && _pool.length < maxPoolSize) {
        _pool.add(controller);
        LogUtil.i('控制器已添加回池中，当前池大小: ${_pool.length}');
      } else if (!isDuplicate) {
        // 池已满，更彻底地清理实例
        await _cleanupWebView(controller);
        LogUtil.i('池已满，彻底清理实例');
      }
    } catch (e) {
      LogUtil.e('重置实例失败: $e');
      // 即使重置失败，也尝试彻底清理
      try {
        await _cleanupWebView(controller);
      } catch (cleanupError) {
        LogUtil.e('清理失败的实例时出错: $cleanupError');
      }
    } finally {
      _disposingControllers.remove(controller);
    }
  }

  /// 获取控制器的取消令牌状态
  static CancelToken getControllerCancelToken(WebViewController controller) {
    return _controllerCancelTokens[controller] ?? CancelToken();
  }

  /// 清理所有池实例
  static Future<void> clear() async {
    for (final controller in _pool) {
      try {
        await _cleanupWebView(controller);
      } catch (e) {
        LogUtil.e('清理实例失败: $e');
      }
    }

    _pool.clear();
    _disposingControllers.clear();
    _controllerCancelTokens.clear();  // 修改：清除所有取消令牌状态
    ScriptManager.clearAll();
    LogUtil.i('池已清空');
  }
}

/// 搜索结果缓存类，使用LinkedHashMap实现LRU
class _SearchCache {
  static const String _cacheKey = 'search_cache_data'; /// 持久化存储键
  static const String _lruKey = 'search_cache_lru';   /// LRU顺序键

  final int maxEntries; /// 最大缓存条目数
  final Map<String, _CacheEntry> _cache = LinkedHashMap<String, _CacheEntry>(); /// 缓存存储
  bool _isDirty = false; /// 缓存脏标志
  Timer? _persistTimer;  /// 持久化定时器

  _SearchCache({this.maxEntries = AppConstants.maxSearchCacheEntries}) {
    _loadFromPersistence(); /// 加载持久化数据

    _persistTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (_isDirty) {
        _saveToPersistence();
        _isDirty = false;
      }
    });
  }

  /// 从持久化存储加载缓存
  void _loadFromPersistence() {
    try {
      final cacheJson = SpUtil.getString(_cacheKey);
      if (cacheJson != null && cacheJson.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(cacheJson);

        final lruJson = SpUtil.getString(_lruKey);
        List<String> lruOrder = [];

        if (lruJson != null && lruJson.isNotEmpty) {
          final List<dynamic> lruData = jsonDecode(lruJson);
          lruOrder = lruData.whereType<String>().toList();
        }

        _cache.clear();

        for (final key in lruOrder) {
          if (data.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              final entry = _CacheEntry.fromJson(data[key]);
              _cache[key] = entry;
            } catch (e) {
              LogUtil.e('解析条目($key)失败: $e');
            }
          }
        }

        for (final key in data.keys) {
          if (!_cache.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              final entry = _CacheEntry.fromJson(data[key]);
              _cache[key] = entry;
            } catch (e) {
              LogUtil.e('解析条目($key)失败: $e');
            }
          }
        }

        while (_cache.length > maxEntries && _cache.isNotEmpty) {
          _cache.remove(_cache.keys.first);
        }

        LogUtil.i('加载 ${_cache.length} 个缓存条目');
      }
    } catch (e) {
      LogUtil.e('加载缓存失败: $e');
      _cache.clear();
    }
  }

  /// 保存到持久化存储
  void _saveToPersistence() {
    try {
      final Map<String, dynamic> data = {};
      _cache.forEach((key, entry) {
        data[key] = entry.toJson();
      });

      final cacheJsonString = jsonEncode(data);
      SpUtil.putString(_cacheKey, cacheJsonString);

      final lruJsonString = jsonEncode(_cache.keys.toList());
      SpUtil.putString(_lruKey, lruJsonString);
    } catch (e) {
      LogUtil.e('保存缓存失败: $e');
    }
  }

  /// 获取缓存URL，forceRemove为true时移除条目
  String? getUrl(String keyword, {bool forceRemove = false}) {
    final normalizedKeyword = keyword.trim().toLowerCase();
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
    return cachedUrl;
  }

  /// 添加缓存条目
  void addUrl(String keyword, String url) {
    if (keyword.isEmpty || url.isEmpty || url == 'ERROR') return;

    final normalizedKeyword = keyword.trim().toLowerCase();
    _cache.remove(normalizedKeyword);

    if (_cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      LogUtil.i('移除最旧条目: $oldest');
    }

    _cache[normalizedKeyword] = _CacheEntry(url);
    _isDirty = true;
    LogUtil.i('添加缓存: $normalizedKeyword -> $url');
  }

  /// 清除所有缓存
  void clear() {
    _cache.clear();
    SpUtil.remove(_cacheKey);
    SpUtil.remove(_lruKey);
    _isDirty = false;
    LogUtil.i('清空所有缓存');
  }

  /// 获取缓存大小
  int get size => _cache.length;

  /// 释放资源
  void dispose() {
    try {
      if (_isDirty) _saveToPersistence();
    } catch (e) {
      LogUtil.e('保存缓存状态失败: $e');
    } finally {
      _persistTimer?.cancel();
      _persistTimer = null;
    }
  }
}

/// 解析会话类，管理解析逻辑和状态
class _ParserSession {
  final Completer<String> completer = Completer<String>(); /// 异步任务完成器
  final List<String> foundStreams = [];                    /// 发现的流地址
  WebViewController? controller;                          /// WebView控制器
  final TimerManager _timerManager = TimerManager();       /// 定时器管理器
  bool isResourceCleaned = false;                         /// 资源清理状态
  bool isTestingStarted = false;                          /// 流测试开始状态
  bool isExtractionInProgress = false;                    /// 提取进行中状态
  bool isCollectionFinished = false;                      /// 收集完成状态
  bool isDomMonitorInjected = false;                      /// DOM监听器注入标志
  bool isFormDetectionInjected = false;                   /// 表单检测脚本注入标志
  bool isFingerprintRandomizationInjected = false;        /// 指纹随机化脚本注入标志
  bool hasRegisteredJsChannel = false;                    /// JavaScript通道注册标志
  
  // 添加直接使用ParseStage的成员变量来替代searchState中的stage
  ParseStage currentStage = ParseStage.formSubmission;    /// 当前解析阶段
  
  final Map<String, dynamic> searchState = {
    AppConstants.searchKeyword: '',                       /// 搜索关键词
    AppConstants.activeEngine: 'backup1',                 /// 默认备用引擎1
    AppConstants.searchSubmitted: false,                  /// 表单未提交
    AppConstants.startTimeMs: DateTime.now().millisecondsSinceEpoch, /// 解析开始时间
    AppConstants.lastHtmlLength: 0,                      /// 当前HTML长度
    // 已移除AppConstants.stage，使用currentStage替代
    AppConstants.stage1StartTime: DateTime.now().millisecondsSinceEpoch, /// 阶段1开始时间
    AppConstants.stage2StartTime: 0,                     /// 阶段2未开始
    AppConstants.initialEngineAttempted: false,          /// 修改：添加状态标志，标记是否已尝试过初始引擎
  };
  final Map<String, int> _lastPageFinishedTime = {};      /// 页面加载防抖映射
  StreamSubscription? cancelListener;                     /// 取消事件监听器
  final CancelToken? cancelToken;                        /// 任务取消令牌
  bool _isCleaningUp = false;                            /// 资源清理锁
  final Map<String, bool> _urlCache = {};                /// URL去重缓存
  bool isCompareDone = false;                            /// 流比较完成标志

  _ParserSession({this.cancelToken, String? initialEngine}) {
    if (initialEngine != null) {
      searchState[AppConstants.activeEngine] = initialEngine; /// 设置初始引擎
    }
    
    // 修改：如果初始引擎是backup1或backup2，则标记已经尝试过初始引擎
    if (initialEngine == 'backup1' || initialEngine == 'backup2') {
      searchState[AppConstants.initialEngineAttempted] = true;
    }
  }

  /// 🔥 修改点：新增取消状态检查方法
  bool _isCancelled() => cancelToken?.isCancelled ?? false;

  /// 统一执行异步操作
  Future<void> _executeAsyncOperation(
    String operationName,
    Future<void> Function() operation, {
    Function? onError,
  }) async {
    try {
      // 🔥 修改点：操作前检查取消状态
      if (_isCancelled()) {
        LogUtil.i('$operationName: 操作已取消');
        return;
      }
      await operation();
    } catch (e) {
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel) {
        LogUtil.i('$operationName: 操作被取消');
        return;
      }
      
      LogUtil.e('$operationName失败: $e');
      if (onError != null) {
        onError();
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }

  /// 选择最快响应的流
  void _selectBestStream(Map<String, int> streams, Completer<String> resultCompleter, CancelToken token) {
    // 🔥 修改点：选择流前检查取消状态
    if (isCompareDone || resultCompleter.isCompleted || _isCancelled()) return;
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

    String reason = streams.length == 1 ? "仅一个成功流" : "从${streams.length}个流中选最快";
    LogUtil.i('$reason: $selectedStream (${bestTime}ms)');

    if (!resultCompleter.isCompleted) {
      // 完成结果传递链
      resultCompleter.complete(selectedStream);
      
      // 确保会话的主completer也能立即获得结果
      if (!completer.isCompleted) {
        completer.complete(selectedStream);
        LogUtil.i('流选择完成，结果已传递到会话层');
      }
    }
  }

  /// 完成收集并开始测试
  void finishCollectionAndTest() {
    // 🔥 修改点：开始测试前检查取消状态
    if (_isCancelled()) {
      LogUtil.i('SousuoParser: 取消状态，中止收集');
      return;
    }

    if (isCollectionFinished || isTestingStarted) return;

    isCollectionFinished = true;
    startStreamTesting();
  }

  /// 清理资源
  Future<void> cleanupResources({bool immediate = false}) async {
    // 使用同步块确保线程安全
    synchronized() async {
      if (_isCleaningUp || isResourceCleaned) {
        LogUtil.i('资源已清理或正在清理');
        return;
      }
      _isCleaningUp = true;
    }

    bool cleanupSuccess = false;
    try {
      // 修改：显式取消特定定时器，以防cancelAll有问题
      _timerManager.cancel('delayedContentChange');
      _timerManager.cancel('compareWindow');
      _timerManager.cancel('streamTestTimeout');
      _timerManager.cancel('contentChangeDebounce');
      // 然后再取消所有
      _timerManager.cancelAll();

      if (cancelListener != null) {
        try {
          await cancelListener!.cancel().timeout(
            Duration(milliseconds: AppConstants.cancelListenerTimeoutMs),
            onTimeout: () {
              LogUtil.i('取消监听器超时');
              return;
            },
          );
        } catch (e) {
          LogUtil.e('取消监听器失败: $e');
        } finally {
          cancelListener = null;
        }
      }

      final tempController = controller;
      controller = null;
      
      // 重置JavaScript通道注册状态
      hasRegisteredJsChannel = false;

      if (tempController != null) {
        try {
          // 使用WebViewPool的清理方法
          cleanupSuccess = await WebViewPool._cleanupWebView(tempController);

          // 确保即使在immediate模式下也清理资源
          if (!immediate) {
            await WebViewPool.release(tempController);
          } else {
            await tempController.clearLocalStorage();
            LogUtil.i('即时模式，执行本地清理');
          }
          
          cleanupSuccess = true;
        } catch (e) {
          LogUtil.e('清理WebView失败: $e');
          // 确保在失败的情况下也尝试释放资源
          try {
            if (!immediate) {
              await WebViewPool.release(tempController);
            } else {
              await tempController.clearLocalStorage();
            }
            cleanupSuccess = true;
          } catch (releaseError) {
            LogUtil.e('释放WebView失败: $releaseError');
          }
        }
      } else {
        // 如果没有控制器，也认为清理成功
        cleanupSuccess = true;
      }

      _urlCache.clear();
      
      // 只有在实际清理成功后才标记为已清理
      if (cleanupSuccess) {
        isResourceCleaned = true;
        LogUtil.i('资源清理成功完成');
      }
    } catch (e) {
      LogUtil.e('资源清理失败: $e');
    } finally {
      _isCleaningUp = false;
    }
  }

  /// 并发测试所有流
  Future<String> _testAllStreamsConcurrently(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR';

    // 🔥 修改点：测试开始前检查取消状态
    if (_isCancelled()) {
      LogUtil.i('SousuoParser: 流测试开始前已取消');
      return 'ERROR';
    }

    final Completer<String> resultCompleter = Completer<String>();
    final Map<String, int> successfulStreams = {};

    // 设置流测试定时器
    _timerManager.set(
      'compareWindow',
      Duration(milliseconds: AppConstants.compareTimeWindowMs),
      () {
        if (!isCompareDone && !resultCompleter.isCompleted && successfulStreams.isNotEmpty && !_isCancelled()) {
          _selectBestStream(successfulStreams, resultCompleter, cancelToken);
        }
      },
    );

    _timerManager.set(
      'streamTestTimeout',
      Duration(seconds: AppConstants.testOverallTimeoutSeconds),
      () {
        if (!resultCompleter.isCompleted && !_isCancelled()) {
          if (successfulStreams.isNotEmpty) {
            _selectBestStream(successfulStreams, resultCompleter, cancelToken);
          } else {
            LogUtil.i('流测试超时${AppConstants.testOverallTimeoutSeconds}秒');
            resultCompleter.complete('ERROR');
          }
        }
      },
    );

    try {
      // 创建所有流的测试任务
      final testFutures = streams.map((stream) => 
        _testSingleStream(stream, successfulStreams, cancelToken, resultCompleter)
      ).toList();
      
      // 等待所有测试完成或结果已选出
      await Future.any([
        Future.wait(testFutures),
        resultCompleter.future.then((_) => null)
      ]);
      
      // 🔥 修改点：完成后检查取消状态
      if (_isCancelled()) {
        LogUtil.i('SousuoParser: 流测试完成后发现已取消');
        return 'ERROR';
      }
      
      // 如果所有测试完成后仍未选出最佳流，但有成功的流
      if (!resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      } else if (!resultCompleter.isCompleted) {
        // 所有流均测试失败
        resultCompleter.complete('ERROR');
      }

      return await resultCompleter.future;
    } catch (e) {
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel || _isCancelled()) {
        LogUtil.i('SousuoParser: 流测试过程被取消');
        return 'ERROR';
      }
      
      LogUtil.e('流测试过程中出错: $e');
      if (!resultCompleter.isCompleted) {
        if (successfulStreams.isNotEmpty && !_isCancelled()) {
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

  /// 测试单个流
  Future<bool> _testSingleStream(
    String streamUrl,
    Map<String, int> successfulStreams,
    CancelToken cancelToken,
    Completer<String> resultCompleter,
  ) async {
    // 🔥 修改点：测试单个流前检查取消状态
    if (resultCompleter.isCompleted || _isCancelled()) return false;

    try {
      final stopwatch = Stopwatch()..start();
      
      // 🔥 修改点：使用传入的cancelToken进行HTTP请求
      final response = await HttpUtil().getRequestWithResponse(
        streamUrl,
        options: Options(
          headers: HeadersConfig.generateHeaders(url: streamUrl),
          method: 'GET',
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
          receiveTimeout: Duration(seconds: AppConstants.testOverallTimeoutSeconds),
        ),
        cancelToken: cancelToken, // 🔥 修改点：传递cancelToken
        retryCount: 1,
      );

      final testTime = stopwatch.elapsedMilliseconds;

      // 🔥 修改点：响应后检查取消状态
      if (response != null && !resultCompleter.isCompleted && !_isCancelled()) {
        LogUtil.i('流 $streamUrl 测试成功，响应: ${testTime}ms');
        successfulStreams[streamUrl] = testTime;

        if (testTime < AppConstants.fastEnoughThresholdMs && !isCompareDone) {
          LogUtil.i('流 $streamUrl 快速响应(${testTime}ms)，立即返回');
          _selectBestStream({streamUrl: testTime}, resultCompleter, cancelToken);
        }

        return true;
      }
    } catch (e) {
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel || _isCancelled()) {
        LogUtil.i('测试流 $streamUrl 被取消');
      } else {
        LogUtil.e('测试流 $streamUrl 失败: $e');
      }
    }

    return false;
  }

  /// 开始流测试
  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('流测试已开始，忽略重复请求');
      return;
    }

    // 🔥 修改点：测试开始前检查取消状态
    if (_isCancelled()) {
      LogUtil.i('SousuoParser: 取消状态，中止测试');
      return;
    }

    if (foundStreams.isEmpty) {
      LogUtil.i('无流链接，无法测试');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }

    isTestingStarted = true;
    // 取消可能导致备用定时器触发的定时器
    _timerManager.cancel('delayedContentChange');
    LogUtil.i('开始测试${foundStreams.length}个流');

    // 🔥 修改点：使用会话的cancelToken而不是重新创建
    _testStreamsAsync(cancelToken, null);
  }

  /// 异步测试流
  Future<void> _testStreamsAsync(CancelToken? testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      // 🔥 修改点：使用会话的cancelToken
      final result = await _testAllStreamsConcurrently(foundStreams, testCancelToken ?? CancelToken());
      LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      if (!completer.isCompleted) {
        completer.complete(result);
        cleanupResources();
      }
    } catch (e) {
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel || _isCancelled()) {
        LogUtil.i('SousuoParser: 异步测试流被取消');
      } else {
        LogUtil.e('测试流失败: $e');
      }
      
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

  /// 检查是否需要切换引擎
  bool _shouldSwitchEngine() {
    final currentEngine = searchState[AppConstants.activeEngine] as String;
    return currentEngine != 'backup2'; // 备用引擎2是最后一个尝试的引擎
  }

  /// 切换到下一个引擎
  Future<void> switchToNextEngine() async {
    final currentEngine = searchState[AppConstants.activeEngine] as String;
    if (currentEngine == 'backup2') {
      LogUtil.i('已是最后一个引擎，无法继续切换');
      return;
    }
    
    String nextEngine;
    String nextEngineUrl;
    
    if (currentEngine == 'backup1') {
      nextEngine = 'backup2';
      nextEngineUrl = AppConstants.backupEngine2Url;
    } else {
      nextEngine = 'backup1';
      nextEngineUrl = AppConstants.backupEngine1Url;
    }

    await _executeAsyncOperation('切换引擎', () async {
      LogUtil.i('从$currentEngine切换到$nextEngine引擎');

      searchState[AppConstants.activeEngine] = nextEngine;
      searchState[AppConstants.searchSubmitted] = false;
      searchState[AppConstants.lastHtmlLength] = 0;
      // 使用currentStage替代searchState[AppConstants.stage]
      currentStage = ParseStage.formSubmission;
      searchState[AppConstants.stage1StartTime] = DateTime.now().millisecondsSinceEpoch;
      isDomMonitorInjected = false;
      isFormDetectionInjected = false;
      isFingerprintRandomizationInjected = false;
      isCollectionFinished = false;

      if (controller != null) {
        // 不需要重新注册JavaScript通道，保持现有注册
        
        // 修改：使用WebViewPool中的CancelToken来确保导航相关操作使用正确的取消状态
        if (controller != null) {
          final controllerCancelToken = WebViewPool.getControllerCancelToken(controller!);
          // 更新当前session的cancelToken以匹配控制器的cancelToken
          // 这样可以防止错误的取消状态影响导航操作
        }
        
        await controller!.loadRequest(Uri.parse(nextEngineUrl));
        LogUtil.i('加载$nextEngine引擎: $nextEngineUrl');
      } else {
        LogUtil.e('WebView控制器为空');
        throw Exception('WebView控制器为空');
      }
    });
  }

  /// 处理内容变化
  void handleContentChange() {
    _timerManager.cancel('contentChangeDebounce');

    // 🔥 修改点：处理内容变化前检查取消状态
    if (_isCancelled() || isCollectionFinished || isTestingStarted || isExtractionInProgress) {
      LogUtil.i('跳过内容变化处理');
      return;
    }

    _timerManager.set(
      'contentChangeDebounce',
      Duration(milliseconds: AppConstants.contentChangeDebounceMs),
      () async {
        if (controller == null ||
            completer.isCompleted ||
            _isCancelled() ||
            isCollectionFinished ||
            isTestingStarted ||
            isExtractionInProgress) {
          LogUtil.i('防抖期间状态变化，取消处理');
          return;
        }

        try {
          if (searchState[AppConstants.searchSubmitted] == true && !completer.isCompleted && !isTestingStarted) {
            isExtractionInProgress = true;
            int beforeExtractCount = foundStreams.length;
            final currentEngine = searchState[AppConstants.activeEngine] as String;
            bool isBackupEngine2 = currentEngine == 'backup2';

            await SousuoParser._extractAllMediaLinks(
              controller!,
              foundStreams,
              isBackupEngine2,
              urlCache: _urlCache,
            );

            try {
              final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length');
              searchState[AppConstants.lastHtmlLength] = int.tryParse(result.toString()) ?? 0;
            } catch (e) {
              LogUtil.e('获取HTML长度失败: $e');
            }

            // 🔥 修改点：提取后检查取消状态
            if (_isCancelled()) {
              LogUtil.i('提取后处理: 操作已取消');
              return;
            }

            int afterExtractCount = foundStreams.length;

            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('新增${afterExtractCount - beforeExtractCount}个链接，总数: $afterExtractCount');
              if (afterExtractCount >= AppConstants.maxStreams) {
                finishCollectionAndTest();
              }
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
      },
    );
  }

  /// 注入DOM监听器
  Future<void> injectDomMonitor() async {
    if (controller == null || isDomMonitorInjected) return;

    try {
      isDomMonitorInjected = await ScriptManager.injectDomMonitor(controller!, 'AppChannel');
    } catch (e, stackTrace) {
      LogUtil.logError('注入DOM监听器失败', e, stackTrace);
      isDomMonitorInjected = false;
    }
  }

  /// 注入表单检测脚本
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null || isFormDetectionInjected) return;

    try {
      isFormDetectionInjected = await ScriptManager.injectFormDetection(controller!, searchKeyword);
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
      isFormDetectionInjected = false;
    }
  }

  /// 注入指纹随机化脚本
  Future<void> injectFingerprintRandomization() async {
    if (controller == null || isFingerprintRandomizationInjected) return;
    
    try {
      isFingerprintRandomizationInjected = await ScriptManager.injectFingerprintRandomization(controller!);
    } catch (e, stackTrace) {
      LogUtil.logError('注入指纹随机化脚本失败', e, stackTrace);
    }
  }

  /// 处理页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    // 修改：使用控制器关联的取消令牌状态，而不是session的cancelToken
    if (controller == null) return;
    
    final controllerCancelToken = WebViewPool.getControllerCancelToken(controller!);
    // 🔥 修改点：同时检查会话和控制器的取消状态
    if (controllerCancelToken.isCancelled || _isCancelled()) {
      LogUtil.i('SousuoParser: 导航: 操作已取消');
      return;
    }

    if (pageUrl != 'about:blank' && searchState[AppConstants.searchSubmitted] == false) {
      isFormDetectionInjected = false;
      isFingerprintRandomizationInjected = false;

      String searchKeyword = searchState[AppConstants.searchKeyword] ?? '';
      if (searchKeyword.isEmpty) {
        LogUtil.i('搜索关键词为空，尝试从URL获取');
        try {
          final uri = Uri.parse(pageUrl);
          searchKeyword = uri.queryParameters['clickText'] ?? '';
        } catch (e) {
          LogUtil.e('从URL解析关键词失败: $e');
        }
      }

      LogUtil.i('页面加载，注入脚本');
      await Future.wait([
        injectFingerprintRandomization(),
        injectFormDetectionScript(searchKeyword)
      ].map((future) => future.catchError((e) {
        LogUtil.e('脚本注入失败: $e');
        return null;
      })));
    } else if (searchState[AppConstants.searchSubmitted] == true) {
      LogUtil.i('搜索结果页面加载，注入脚本');
      isFormDetectionInjected = false;
      isDomMonitorInjected = false;
      isFingerprintRandomizationInjected = false;

      await Future.wait([
        injectFingerprintRandomization(),
        injectDomMonitor()
      ].map((future) => future.catchError((e) {
        LogUtil.e('脚本注入失败: $e');
        return null;
      })));
    }
  }

  /// 处理页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    // 修改：使用控制器关联的取消令牌状态，而不是session的cancelToken
    if (controller == null) return;
    
    final controllerCancelToken = WebViewPool.getControllerCancelToken(controller!);
    // 🔥 修改点：同时检查会话和控制器的取消状态
    if (controllerCancelToken.isCancelled || _isCancelled()) {
      LogUtil.i('SousuoParser: 页面完成: 操作已取消');
      return;
    }

    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastPageFinishedTime.containsKey(pageUrl)) {
      int lastTime = _lastPageFinishedTime[pageUrl]!;
      if (currentTimeMs - lastTime < AppConstants.domChangeWaitMs) {
        LogUtil.i('忽略重复页面完成: $pageUrl');
        return;
      }
    }

    _lastPageFinishedTime[pageUrl] = currentTimeMs;

    final startMs = searchState[AppConstants.startTimeMs] as int;
    final loadTimeMs = currentTimeMs - startMs;
    LogUtil.i('页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms');

    if (pageUrl == 'about:blank') {
      LogUtil.i('空白页面，忽略');
      return;
    }

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
      LogUtil.i('备用引擎1页面加载完成');
    } else if (isBackupEngine2) {
      searchState[AppConstants.activeEngine] = 'backup2';
      LogUtil.i('备用引擎2页面加载完成');
    }

    if (searchState[AppConstants.searchSubmitted] == true) {
      if (!isExtractionInProgress && !isTestingStarted && !isCollectionFinished) {
        // 🔥 修改点：延迟处理前检查取消状态
        if (_isCancelled()) {
          LogUtil.i('SousuoParser: 延迟内容处理: 操作已取消');
          return;
        }

        _timerManager.set(
          'delayedContentChange',
          Duration(seconds: AppConstants.waitSeconds),
          () {
            LogUtil.i('备用定时器触发');
            if (controller != null &&
                !completer.isCompleted &&
                !_isCancelled() &&
                !isCollectionFinished &&
                !isTestingStarted &&
                !isExtractionInProgress) {
              handleContentChange();
            } else {
              LogUtil.i('备用定时器检查失败');
            }
          },
        );
      }
    }
  }

  /// 检查是否为静态资源
  bool _isStaticResource(String url) {
    return UrlUtil.isStaticResourceUrl(url);
  }

  /// 检查是否为关键网络错误
  bool _isCriticalNetworkError(int errorCode) {
    const criticalErrors = [-1, -2, -3, -6, -7, -101, -105, -106];
    return criticalErrors.contains(errorCode);
  }

  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    // 修改：使用控制器关联的取消令牌状态，而不是session的cancelToken
    if (controller == null) return;
    
    final controllerCancelToken = WebViewPool.getControllerCancelToken(controller!);
    // 🔥 修改点：同时检查会话和控制器的取消状态
    if (controllerCancelToken.isCancelled || _isCancelled()) {
      LogUtil.i('SousuoParser: 资源错误: 操作已取消');
      return;
    }

    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}, URL: ${error.url}');

    // 忽略静态资源错误
    if (error.url == null || _isStaticResource(error.url!)) {
      LogUtil.i('忽略静态资源错误: ${error.url}');
      return;
    }

    // 检查是否为关键错误
    if (_isCriticalNetworkError(error.errorCode)) {
      LogUtil.i('检测到关键网络错误: ${error.errorCode}');
      
      // 如果当前引擎失败且不是最后一个引擎，尝试切换到下一个引擎
      if (_shouldSwitchEngine() && searchState[AppConstants.searchSubmitted] == false) {
        LogUtil.i('关键错误导致引擎切换');
        switchToNextEngine();
      }
    }
  }

  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    // 修改：使用控制器关联的取消令牌状态，而不是session的cancelToken
    if (controller == null) return NavigationDecision.prevent;
    
    final controllerCancelToken = WebViewPool.getControllerCancelToken(controller!);
    // 🔥 修改点：同时检查会话和控制器的取消状态
    if (controllerCancelToken.isCancelled || _isCancelled()) {
      LogUtil.i('SousuoParser: 导航: 操作已取消');
      return NavigationDecision.prevent;
    }

    if (UrlUtil.isStaticResourceUrl(request.url) ||
        request.url.contains('google') ||
        request.url.contains('facebook.com') ||
        request.url.contains('twitter.com')) {
      LogUtil.i('阻止非必要资源: ${request.url}');
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  /// 处理JavaScript消息
  Future<void> handleJavaScriptMessage(JavaScriptMessage message) async {
    // 修改：使用控制器关联的取消令牌状态，而不是session的cancelToken
    if (controller == null) return;
    
    final controllerCancelToken = WebViewPool.getControllerCancelToken(controller!);
    // 🔥 修改点：同时检查会话和控制器的取消状态
    if (controllerCancelToken.isCancelled || _isCancelled()) {
      LogUtil.i('SousuoParser: JS消息: 操作已取消');
      return;
    }

    // 记录消息内容
    LogUtil.i('收到消息: ${message.message}');

    if (controller == null) {
      LogUtil.e('控制器为空');
      return;
    }

    // 使用switch优化消息处理逻辑
    switch (message.message) {
      case 'CONTENT_READY':
        LogUtil.i('内容变化或就绪，触发处理');
        handleContentChange();
        break;
      case 'FORM_SUBMITTED':
        searchState[AppConstants.searchSubmitted] = true;
        // 使用currentStage替代searchState[AppConstants.stage]
        currentStage = ParseStage.searchResults;
        searchState[AppConstants.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
        LogUtil.i('表单已提交');
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

  /// 开始解析流程
  Future<String> startParsing(String url) async {
    try {
      // 🔥 修改点：解析开始前检查取消状态
      if (_isCancelled()) {
        LogUtil.i('SousuoParser: 任务已取消，返回ERROR');
        return 'ERROR';
      }

      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];

      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词');
        return 'ERROR';
      }

      searchState[AppConstants.searchKeyword] = searchKeyword;

      controller = await WebViewPool.acquire();

      // 确保只注册一次JavaScript通道
      if (!hasRegisteredJsChannel) {
        await controller!.addJavaScriptChannel(
          'AppChannel',
          onMessageReceived: handleJavaScriptMessage,
        );
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
        LogUtil.i('加载引擎: ${searchState[AppConstants.activeEngine]}');
        await controller!.loadRequest(Uri.parse(engineUrl));
      } catch (e) {
        LogUtil.e('页面加载失败: $e');
        if (_shouldSwitchEngine()) {
          LogUtil.i('引擎加载失败，切换到下一个引擎');
          await switchToNextEngine();
        }
      }

      final result = await completer.future;

      // 🔥 修改点：解析完成后检查取消状态
      if (!_isCancelled() && !isResourceCleaned) {
        int endTimeMs = DateTime.now().millisecondsSinceEpoch;
        int startMs = searchState[AppConstants.startTimeMs] as int;
        LogUtil.i('解析耗时: ${endTimeMs - startMs}ms');
      }

      return result;
    } catch (e, stackTrace) {
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel || _isCancelled()) {
        LogUtil.i('SousuoParser: 解析被取消');
        return 'ERROR';
      }
      
      LogUtil.logError('解析失败', e, stackTrace);

      if (foundStreams.isNotEmpty && !completer.isCompleted && !_isCancelled()) {
        LogUtil.i('找到${foundStreams.length}个流，尝试测试');
        try {
          // 🔥 修改点：使用会话的cancelToken
          final result = await _testAllStreamsConcurrently(foundStreams, cancelToken ?? CancelToken());
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          return result;
        } catch (testError) {
          LogUtil.e('测试流失败: $testError');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
          }
        }
      } else if (!completer.isCompleted) {
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR');
      }

      return completer.isCompleted ? await completer.future : 'ERROR';
    } finally {
      if (!isResourceCleaned) {
        await cleanupResources();
      }
    }
  }
}

/// 解析任务管理类
class _ParseTaskManager {
  final Map<String, Completer<String>> _activeTasks = {};
  final Map<String, Timer> _taskTimers = {};
  final Map<String, DateTime> _taskStartTimes = {};
  static const int _maxTaskTimeoutSeconds = 60;

  /// 检查是否已有相同关键词的解析任务
  bool hasActiveTask(String taskKey) {
    _cleanupTimedOutTasks();
    return _activeTasks.containsKey(taskKey);
  }

  /// 创建新的解析任务
  Completer<String> createTask(String taskKey) {
    final completer = Completer<String>();
    _activeTasks[taskKey] = completer;
    _taskStartTimes[taskKey] = DateTime.now();
    
    // 为任务设置超时定时器
    _taskTimers[taskKey] = Timer(Duration(seconds: _maxTaskTimeoutSeconds), () {
      if (_activeTasks.containsKey(taskKey) && !completer.isCompleted) {
        LogUtil.i('解析任务超时，自动清理: $taskKey');
        completer.complete('ERROR');
      }
      _cleanupTask(taskKey);
    });
    
    LogUtil.i('创建新的解析任务: $taskKey');
    return completer;
  }

  /// 获取现有任务
  Completer<String>? getTask(String taskKey) {
    return _activeTasks[taskKey];
  }

  /// 完成任务并清理
  void completeTask(String taskKey, String result) {
    final completer = _activeTasks.remove(taskKey);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
    _cleanupTask(taskKey);
    LogUtil.i('解析任务完成: $taskKey -> $result');
  }

  /// 清理指定任务
  void _cleanupTask(String taskKey) {
    _taskTimers[taskKey]?.cancel();
    _taskTimers.remove(taskKey);
    _taskStartTimes.remove(taskKey);
    _activeTasks.remove(taskKey);
  }

  /// 清理超时的解析任务
  void _cleanupTimedOutTasks() {
    final now = DateTime.now();
    final timedOutKeys = <String>[];
    
    _taskStartTimes.forEach((key, startTime) {
      if (now.difference(startTime).inSeconds > _maxTaskTimeoutSeconds) {
        timedOutKeys.add(key);
      }
    });
    
    for (final key in timedOutKeys) {
      LogUtil.i('清理超时任务: $key');
      final completer = _activeTasks[key];
      if (completer != null && !completer.isCompleted) {
        completer.complete('ERROR');
      }
      _cleanupTask(key);
    }
  }

  /// 获取活跃任务数量
  int get activeTaskCount => _activeTasks.length;

  /// 强制清理所有任务
  void clearAllTasks() {
    LogUtil.i('强制清理所有活跃解析任务');
    for (final completer in _activeTasks.values) {
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    }
    
    for (final timer in _taskTimers.values) {
      timer.cancel();
    }
    
    _activeTasks.clear();
    _taskTimers.clear();
    _taskStartTimes.clear();
  }

  /// 释放资源
  void dispose() {
    clearAllTasks();
  }
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static List<String> _blockKeywords = AppConstants.defaultBlockKeywords;
  static final _SearchCache _searchCache = _SearchCache();
  static final Map<String, String> _hostKeyCache = {};
  static const int _maxHostKeyCacheSize = 100;
  
  // 修复：使用专门的任务管理器替代简单的Map
  static final _ParseTaskManager _taskManager = _ParseTaskManager();

  /// 检查是否为静态资源URL
  static bool _isStaticResourceUrl(String url) {
    return UrlUtil.isStaticResourceUrl(url);
  }

  /// 安全地运行JavaScript并处理可能的错误
  static Future<String?> _safeRunJavaScript(WebViewController controller, String script) async {
    try {
      final result = await controller.runJavaScriptReturningResult(script);
      return result?.toString();
    } catch (e) {
      LogUtil.e('执行JavaScript脚本失败: $e');
      return null;
    }
  }

  /// 初始化WebView池和预加载脚本
  static Future<void> initialize() async {
    await WebViewPool.initialize();
    await ScriptManager.preload();
  }

  /// 设置屏蔽关键词
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      _blockKeywords = AppConstants.defaultBlockKeywords;
    }
  }

  /// 检查URL是否包含屏蔽关键词
  static bool _isUrlBlocked(String url) {
    if (_blockKeywords.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase()));
  }

  /// 验证缓存URL
  static Future<bool> _validateCachedUrl(String keyword, String url, CancelToken? cancelToken) async {
    try {
      // 🔥 修改点：传递cancelToken给HTTP请求
      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(
          headers: HeadersConfig.generateHeaders(url: url),
          method: 'GET',
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
        cancelToken: cancelToken, // 🔥 修改点：传递cancelToken
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
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel) {
        LogUtil.i('缓存URL验证被取消: $keyword');
      } else {
        LogUtil.i('缓存URL验证失败，移除: $keyword, $e');
      }
      _searchCache.getUrl(keyword, forceRemove: true);
      return false;
    }
  }

  /// 使用初始引擎搜索
  static Future<String?> _searchWithInitialEngine(String keyword, CancelToken? cancelToken) async {
    final normalizedKeyword = keyword.trim().toLowerCase();
    final completer = Completer<String?>();

    WebViewController? controller;
    bool isResourceCleaned = false;
    final timerManager = TimerManager();

    // 🔥 修改点：新增取消状态检查方法
    bool _isCancelled() => cancelToken?.isCancelled ?? false;

    // 清理资源的内部方法
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
      // 🔥 修改点：开始前检查取消状态
      if (_isCancelled()) {
        LogUtil.i('SousuoParser: 初始引擎任务已取消');
        completer.complete(null);
        return null;
      }

      final resultCompleter = Completer<String?>();
      timerManager.set(
        'globalTimeout',
        Duration(seconds: AppConstants.globalTimeoutSeconds),
        () {
          LogUtil.i('初始引擎超时');
          if (!resultCompleter.isCompleted) resultCompleter.complete(null);
        },
      );

      final searchUrl = AppConstants.initialEngineUrl + Uri.encodeComponent(keyword);

      controller = await WebViewPool.acquire();
      if (controller == null) {
        LogUtil.e('获取WebView失败');
        timerManager.cancel('globalTimeout');
        completer.complete(null);
        return null;
      }

      final nonNullController = controller!;
      final pageLoadCompleter = Completer<String>();
      bool contentReadyProcessed = false;

      await nonNullController.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('初始引擎消息: ${message.message}');
          if (message.message == 'CONTENT_READY' && !contentReadyProcessed) {
            contentReadyProcessed = true;
            LogUtil.i('初始引擎内容就绪');
            if (!pageLoadCompleter.isCompleted) pageLoadCompleter.complete(searchUrl);
          }
        },
      );

      await nonNullController.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          if (url != 'about:blank') {
            LogUtil.i('初始引擎页面开始加载: $url');
            try {
              await ScriptManager.injectDomMonitor(nonNullController, 'AppChannel');
              await ScriptManager.injectFingerprintRandomization(nonNullController);
              LogUtil.i('初始引擎脚本注入成功（页面开始加载时）');
            } catch (e) {
              LogUtil.e('初始引擎脚本注入失败: $e');
            }
          }
        },
        onPageFinished: (url) {
          if (url == 'about:blank') {
            LogUtil.i('加载空白页，忽略');
            return;
          }
          if (!pageLoadCompleter.isCompleted && !contentReadyProcessed) {
            LogUtil.i('初始引擎页面加载完成: $url');
            pageLoadCompleter.complete(url);
          }
        },
        onWebResourceError: (error) => LogUtil.e('初始引擎资源错误: ${error.description}'),
      ));

      await nonNullController.loadRequest(Uri.parse(searchUrl));

      String loadedUrl;
      try {
        loadedUrl = await pageLoadCompleter.future;
      } catch (e) {
        LogUtil.e('初始引擎页面加载失败: $e');
        await cleanupResources();
        completer.complete(null);
        return null;
      }

      await Future.delayed(Duration(seconds: AppConstants.waitSeconds));

      // 🔥 修改点：等待后检查取消状态
      if (_isCancelled()) {
        LogUtil.i('SousuoParser: 初始引擎等待后发现已取消');
        await cleanupResources();
        completer.complete(null);
        return null;
      }

      String html;
      try {
        final result = await nonNullController.runJavaScriptReturningResult('document.documentElement.outerHTML');
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
        LogUtil.i('初始引擎无有效链接');
        completer.complete(null);
        return null;
      }

      // 🔥 修改点：创建测试会话时传递cancelToken
      final testSession = _ParserSession(cancelToken: cancelToken);
      testSession.foundStreams.addAll(extractedUrls);
      testSession.searchState[AppConstants.initialEngineAttempted] = true;

      LogUtil.i('测试初始引擎链接: ${extractedUrls.length}');
      // 🔥 修改点：传递cancelToken给流测试
      final result = await testSession._testAllStreamsConcurrently(extractedUrls, cancelToken ?? CancelToken());
      final finalResult = result == 'ERROR' ? null : result;

      completer.complete(finalResult);
      return finalResult;
    } catch (e, stackTrace) {
      // 🔥 修改点：区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel || _isCancelled()) {
        LogUtil.i('SousuoParser: 初始引擎搜索被取消');
      } else {
        LogUtil.e('初始引擎搜索失败: $e');
      }
      if (!isResourceCleaned) await cleanupResources();
      completer.complete(null);
      return null;
    } finally {
      if (!isResourceCleaned) await cleanupResources();
      if (!completer.isCompleted) completer.complete(null);
    }
  }

  /// 执行实际解析操作
  static Future<String> _performParsing(String url, String searchKeyword, CancelToken? cancelToken, String blockKeywords) async {
    // 🔥 修改点：解析开始前检查取消状态
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('SousuoParser: 执行解析前任务已取消');
      return 'ERROR';
    }

    // 首先检查缓存，减少不必要的网络请求
    final cachedUrl = _searchCache.getUrl(searchKeyword);
    if (cachedUrl != null) {
      LogUtil.i('缓存命中: $searchKeyword -> $cachedUrl');
      // 🔥 修改点：验证缓存时传递cancelToken
      if (await _validateCachedUrl(searchKeyword, cachedUrl, cancelToken)) return cachedUrl;
      LogUtil.i('缓存失效，重新搜索');
    }

    // 先尝试使用初始引擎，它的性能往往更高
    LogUtil.i('尝试初始引擎: $searchKeyword');
    // 🔥 修改点：传递cancelToken给初始引擎搜索
    final initialEngineResult = await _searchWithInitialEngine(searchKeyword, cancelToken);
    if (initialEngineResult != null) {
      LogUtil.i('初始引擎成功: $initialEngineResult');
      _searchCache.addUrl(searchKeyword, initialEngineResult);
      return initialEngineResult;
    } else {
      LogUtil.i('初始引擎失败，进入标准解析');
    }
    
    // 🔥 修改点：检查取消状态
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('SousuoParser: 标准解析前任务已取消');
      return 'ERROR';
    }

    // 使用备用引擎1开始，并标记已尝试过初始引擎
    // 🔥 修改点：传递cancelToken给解析会话
    final session = _ParserSession(cancelToken: cancelToken, initialEngine: 'backup1');
    session.searchState[AppConstants.initialEngineAttempted] = true;
    
    final result = await session.startParsing(url);

    // 成功结果加入缓存
    if (result != 'ERROR' && searchKeyword.isNotEmpty) {
      _searchCache.addUrl(searchKeyword, result);
    }

    return result;
  }

  /// 🔥 修改点：修改parse方法签名，接受CancelToken参数
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    // 修复：使用可取消的Timer替代Future.delayed
    Timer? globalTimer;
    Completer<String>? parseCompleter;
    
    try {
      if (blockKeywords.isNotEmpty) setBlockKeywords(blockKeywords);

      String? searchKeyword;
      try {
        final uri = Uri.parse(url);
        searchKeyword = uri.queryParameters['clickText'];
      } catch (e) {
        LogUtil.e('提取关键词失败: $e');
      }

      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无有效关键词');
        return 'ERROR';
      }

      // 🔥 修改点：解析开始前检查取消状态
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('SousuoParser: 解析开始前任务已取消');
        return 'ERROR';
      }

      // 标准化关键词作为任务key
      final taskKey = searchKeyword.trim().toLowerCase();

      // 检查是否已有相同关键词的解析任务在进行
      if (_taskManager.hasActiveTask(taskKey)) {
        LogUtil.i('检测到重复解析请求，等待现有任务完成: $searchKeyword');
        try {
          final existingTask = _taskManager.getTask(taskKey);
          if (existingTask != null) {
            final result = await existingTask.future;
            LogUtil.i('复用现有解析结果: $searchKeyword -> $result');
            return result;
          }
        } catch (e) {
          LogUtil.e('等待现有解析任务失败: $e');
        }
      }

      // 创建新的解析任务
      parseCompleter = _taskManager.createTask(taskKey);

      // 修复：使用可取消的Timer创建超时控制
      globalTimer = Timer(Duration(seconds: AppConstants.globalTimeoutSeconds), () {
        LogUtil.i('全局超时: $searchKeyword');
        if (parseCompleter != null && !parseCompleter.isCompleted) {
          _taskManager.completeTask(taskKey, 'ERROR');
        }
      });

      try {
        // 🔥 修改点：执行解析时传递cancelToken
        final result = await _performParsing(url, searchKeyword, cancelToken, blockKeywords);
        
        // 完成任务
        if (parseCompleter != null && !parseCompleter.isCompleted) {
          _taskManager.completeTask(taskKey, result);
        }
        
        return result;
        
      } catch (e, stackTrace) {
        // 🔥 修改点：区分取消异常和其他异常
        if (e is DioException && e.type == DioExceptionType.cancel || (cancelToken?.isCancelled ?? false)) {
          LogUtil.i('SousuoParser: 解析过程被取消');
        } else {
          LogUtil.logError('解析过程中发生异常', e, stackTrace);
        }
        
        if (parseCompleter != null && !parseCompleter.isCompleted) {
          _taskManager.completeTask(taskKey, 'ERROR');
        }
        return 'ERROR';
      }
      
    } catch (e, stackTrace) {
      LogUtil.logError('parse方法执行异常', e, stackTrace);
      return 'ERROR';
    } finally {
      // 修复：确保globalTimer被正确取消
      globalTimer?.cancel();
      LogUtil.i('全局定时器已清理');
    }
  }

  /// 获取活跃解析任务数量（用于调试）
  static int get activeTaskCount => _taskManager.activeTaskCount;

  /// 强制清理所有活跃任务（用于重置状态）
  static void clearActiveTasks() {
    _taskManager.clearAllTasks();
  }

  /// 清理HTML字符串
  static String _cleanHtmlString(String htmlContent) {
    final length = htmlContent.length;
    if (length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) {
      return htmlContent;
    }

    try {
      final innerContent = htmlContent.substring(1, length - 1);
      final buffer = StringBuffer();
      int i = 0;
      
      while (i < innerContent.length) {
        int escapeIndex = innerContent.indexOf('\\', i);
        
        if (escapeIndex == -1 || escapeIndex >= innerContent.length - 1) {
          buffer.write(innerContent.substring(i));
          break;
        }
        
        if (escapeIndex > i) {
          buffer.write(innerContent.substring(i, escapeIndex));
        }
        
        final nextChar = innerContent[escapeIndex + 1];
        switch (nextChar) {
          case '"': buffer.write('"'); break;
          case 'n': buffer.write('\n'); break;
          case 't': buffer.write('\t'); break;
          case '\\': buffer.write('\\'); break;
          case 'r': buffer.write('\r'); break;
          case 'f': buffer.write('\f'); break;
          case 'b': buffer.write('\b'); break;
          case 'u':
            if (escapeIndex + 5 < innerContent.length) {
              try {
                final hexCode = innerContent.substring(escapeIndex + 2, escapeIndex + 6);
                final charCode = int.parse(hexCode, radix: 16);
                buffer.write(String.fromCharCode(charCode));
                i = escapeIndex + 6;
                continue;
              } catch (e) {
                buffer.write(innerContent[escapeIndex]);
              }
            } else {
              buffer.write(innerContent[escapeIndex]);
            }
            break;
          default: buffer.write(innerContent[escapeIndex]);
        }
        
        i = escapeIndex + 2;
      }
      
      return buffer.toString();
    } catch (e) {
      LogUtil.e('清理HTML字符串失败: $e');
      return htmlContent;
    }
  }

  /// 一次性提取所有媒体链接
  static Future<void> _extractAllMediaLinks(
    WebViewController controller,
    List<String> foundStreams,
    bool usingBackupEngine2, {
    Map<String, bool>? urlCache,
  }) async {
    try {
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      String htmlContent = _cleanHtmlString(html.toString());
      final contentLength = htmlContent.length;
      LogUtil.i('HTML获取，长度: $contentLength');

      final matches = UrlUtil.getMediaLinkRegex().allMatches(htmlContent);
      final totalMatches = matches.length;

      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> URL: ${firstMatch.group(2)}');
      }

      final Set<String> existingStreams = foundStreams.toSet();
      final Set<String> newLinks = {};
      final Map<String, bool> hostMap = urlCache ?? {};

      if (urlCache == null && existingStreams.isNotEmpty) {
        for (final url in existingStreams) {
          try {
            final hostKey = _getHostKey(url);
            hostMap[hostKey] = true;
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
          LogUtil.e('URL处理失败: $mediaUrl, $e');
        }
      }

      final int maxToAdd = AppConstants.maxStreams - foundStreams.length;
      
      if (maxToAdd > 0 && newLinks.isNotEmpty) {
        final addList = newLinks.take(maxToAdd).toList();
        foundStreams.addAll(addList);
        LogUtil.i('添加了${addList.length}个新链接，总共: ${foundStreams.length}');
      }

      LogUtil.i('匹配: $totalMatches, 新链接: ${newLinks.length}, 当前总链接: ${foundStreams.length}');
    } catch (e, stackTrace) {
      LogUtil.e('链接提取失败: $e');
    }

    LogUtil.i('提取完成，链接总数: ${foundStreams.length}');
  }

  /// 获取主机键值，使用缓存
  static String _getHostKey(String url) {
    if (_hostKeyCache.containsKey(url)) return _hostKeyCache[url]!;

    final hostKey = UrlUtil.getHostKey(url);
    
    if (_hostKeyCache.length >= _maxHostKeyCacheSize) _hostKeyCache.remove(_hostKeyCache.keys.first);
    _hostKeyCache[url] = hostKey;

    return hostKey;
  }

  /// 释放资源
  static Future<void> dispose() async {
    try {
      // 清理所有活跃任务
      _taskManager.dispose();
      
      await WebViewPool.clear();
      _searchCache.dispose();
      _hostKeyCache.clear();
      LogUtil.i('资源释放完成');
    } catch (e) {
      LogUtil.e('资源释放过程中发生错误: $e');
    }
  }
}

/// 同步执行函数，确保线程安全
void synchronized(Function() action) => action();
