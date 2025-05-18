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

  /// 状态键
  static const String searchKeyword = 'searchKeyword';           /// 搜索关键词
  static const String activeEngine = 'activeEngine';            /// 当前搜索引擎
  static const String searchSubmitted = 'searchSubmitted';      /// 表单提交状态
  static const String startTimeMs = 'startTimeMs';             /// 解析开始时间
  static const String engineSwitched = 'engineSwitched';       /// 引擎切换状态
  static const String primaryEngineLoadFailed = 'primaryEngineLoadFailed'; /// 主引擎加载失败
  static const String lastHtmlLength = 'lastHtmlLength';       /// 上次HTML长度
  static const String extractionCount = 'extractionCount';     /// 提取次数
  static const String stage = 'stage';                         /// 当前解析阶段
  static const String stage1StartTime = 'stage1StartTime';     /// 阶段1开始时间
  static const String stage2StartTime = 'stage2StartTime';     /// 阶段2开始时间

  /// 搜索引擎URL
  static const String initialEngine = 'https://www.iptv-search.com/zh-hans/search/?q='; /// 初始搜索引擎URL
  static const String primaryEngine = 'http://www.foodieguide.com/iptvsearch/';        /// 主引擎URL
  static const String backupEngine = 'https://tonkiang.us/?';                          /// 备用引擎URL

  /// 超时与等待时间
  static const int globalTimeoutSeconds = 28;         /// 全局超时（秒）
  static const int waitSeconds = 2;                  /// 页面加载等待（秒）
  static const int noMoreChangesSeconds = 2;         /// 无变化检测（秒）
  static const int domChangeWaitMs = 300;            /// DOM变化等待（毫秒）
  static const int contentChangeDebounceMs = 300;    /// 内容变化防抖（毫秒）
  static const int backupEngineLoadWaitMs = 200;     /// 备用引擎加载等待（毫秒）
  static const int cleanupRetryWaitMs = 200;         /// 清理重试等待（毫秒）
  static const int cancelListenerTimeoutMs = 500;    /// 取消监听器超时（毫秒）
  static const int emptyHtmlLoadTimeoutMs = 300;     /// 空HTML加载超时（毫秒）
  static const int webViewCleanupDelayMs = 200;      /// WebView清理延迟（毫秒）
  static const int webViewCleanupTimeoutMs = 500;    /// WebView清理超时（毫秒）

  /// 限制与阈值
  static const int maxStreams = 8;                   /// 最大媒体流数量
  static const int maxConcurrentTests = 8;           /// 最大并发测试数
  static const int minValidContentLength = 1000;     /// 最小有效内容长度
  static const int maxSearchCacheEntries = 58;       /// 搜索缓存最大条目数

  /// 流测试参数
  static const int streamCompareTimeWindowMs = 3000; /// 流响应时间窗口（毫秒）
  static const int streamFastEnoughThresholdMs = 500; /// 流快速响应阈值（毫秒）
  static const int streamTestOverallTimeoutSeconds = 6; /// 流测试整体超时（秒）

  /// 屏蔽关键词
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

/// 定时器管理类，统一管理定时器
class TimerManager {
  final Map<String, Timer> _timers = {}; /// 定时器存储
  bool _isDisposed = false;              /// 资源释放标志

  /// 创建或替换定时器
  Timer set(String key, Duration duration, Function() callback) {
    if (_isDisposed) {
      LogUtil.i('已释放，忽略定时器: $key');
      return Timer(Duration.zero, () {});
    }

    final existingTimer = _timers[key];
    if (existingTimer != null) {
      try {
        existingTimer.cancel();
      } catch (e) {
        LogUtil.e('取消定时器($key)失败: $e');
      }
    }

    final safeCallback = () {
      try {
        _timers.remove(key);
        if (!_isDisposed) callback();
      } catch (e) {
        LogUtil.e('定时器($key)回调错误: $e');
      }
    };

    try {
      final timer = Timer(duration, safeCallback);
      _timers[key] = timer;
      return timer;
    } catch (e) {
      LogUtil.e('创建定时器($key)失败: $e');
      return Timer(Duration.zero, () {});
    }
  }

  /// 创建周期性定时器
  Timer setPeriodic(String key, Duration duration, Function(Timer) callback) {
    if (_isDisposed) {
      LogUtil.i('已释放，忽略周期定时器: $key');
      return Timer(Duration.zero, () {});
    }

    cancel(key);

    try {
      final timer = Timer.periodic(duration, (timer) {
        try {
          callback(timer);
        } catch (e) {
          LogUtil.e('周期定时器($key)回调错误: $e');
          timer.cancel();
          _timers.remove(key);
        }
      });

      _timers[key] = timer;
      return timer;
    } catch (e) {
      LogUtil.e('创建周期定时器($key)失败: $e');
      return Timer(Duration.zero, () {});
    }
  }

  /// 取消指定定时器
  void cancel(String key) {
    if (_timers.containsKey(key)) {
      try {
        _timers[key]?.cancel();
        _timers.remove(key);
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
      _timers.forEach((key, timer) {
        try {
          timer.cancel();
        } catch (e) {
          LogUtil.e('取消定时器($key)失败: $e');
        }
      });
      _timers.clear();
    } catch (e) {
      LogUtil.e('取消所有定时器失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    cancelAll();
    _isDisposed = true;
  }
}

/// WebView池管理类，提升WebView复用效率
class WebViewPool {
  static final List<WebViewController> _pool = []; /// WebView控制器池
  static const int maxPoolSize = 2;               /// 最大池大小
  static final Completer<void> _initCompleter = Completer<void>(); /// 初始化完成器
  static bool _isInitialized = false;             /// 初始化标志

  /// 初始化WebView池
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);

      await controller.loadHtmlString('<html><body></body></html>');
      _pool.add(controller);

      _isInitialized = true;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      LogUtil.i('初始化完成');
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
      LogUtil.i('获取实例，剩余: ${_pool.length}');
      return controller;
    }

    LogUtil.i('池为空，创建新实例');
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent);

    return controller;
  }

  /// 释放WebView实例回池
  static Future<void> release(WebViewController? controller) async {
    if (controller == null) return;

    try {
      await controller.loadHtmlString('<html><body></body></html>');
      await controller.clearCache();

      bool isDuplicate = false;
      for (var existingController in _pool) {
        if (identical(existingController, controller)) {
          isDuplicate = true;
          LogUtil.i('实例已存在，忽略重复添加');
          break;
        }
      }

      if (!isDuplicate && _pool.length < maxPoolSize) {
        _pool.add(controller);
        LogUtil.i('实例返回池，当前大小: ${_pool.length}');
      } else if (!isDuplicate) {
        LogUtil.i('池已满，丢弃实例');
      }
    } catch (e) {
      LogUtil.e('重置实例失败: $e');
    }
  }

  /// 清理所有池实例
  static Future<void> clear() async {
    for (final controller in _pool) {
      try {
        await controller.loadHtmlString('<html><body></body></html>');
        await controller.clearCache();
      } catch (e) {
        LogUtil.e('清理实例失败: $e');
      }
    }

    _pool.clear();
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
    if (_isDirty) _saveToPersistence();
    _persistTimer?.cancel();
    _persistTimer = null;
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
  final Map<String, dynamic> searchState = {
    AppConstants.searchKeyword: '',                       /// 搜索关键词
    AppConstants.activeEngine: 'primary',                 /// 默认主引擎
    AppConstants.searchSubmitted: false,                  /// 表单未提交
    AppConstants.startTimeMs: DateTime.now().millisecondsSinceEpoch, /// 解析开始时间
    AppConstants.engineSwitched: false,                   /// 未切换引擎
    AppConstants.primaryEngineLoadFailed: false,          /// 主引擎未失败
    AppConstants.lastHtmlLength: 0,                      /// 初始HTML长度
    AppConstants.extractionCount: 0,                     /// 初始提取次数
    AppConstants.stage: ParseStage.formSubmission,        /// 初始解析阶段
    AppConstants.stage1StartTime: DateTime.now().millisecondsSinceEpoch, /// 阶段1开始时间
    AppConstants.stage2StartTime: 0,                     /// 阶段2未开始
  };
  final Map<String, int> _lastPageFinishedTime = {};      /// 页面加载防抖映射
  StreamSubscription? cancelListener;                     /// 取消事件监听器
  final CancelToken? cancelToken;                        /// 任务取消令牌
  bool _isCleaningUp = false;                            /// 资源清理锁
  final Map<String, bool> _urlCache = {};                /// URL去重缓存
  bool isCompareDone = false;                            /// 流比较完成标志
  bool isCompareWindowStarted = false;                   /// 比较窗口启动标志

  _ParserSession({this.cancelToken, String? initialEngine}) {
    if (initialEngine != null) {
      searchState[AppConstants.activeEngine] = initialEngine; /// 设置初始引擎
    }
  }

  /// 检查任务取消状态
  @pragma('vm:prefer-inline')
  bool _isCancelled() => cancelToken?.isCancelled ?? false;

  /// 检查并处理任务取消
  bool _checkCancelledAndHandle(String context, {bool completeWithError = true}) {
    if (_isCancelled()) {
      if (completeWithError && !completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return true;
    }
    return false;
  }

  /// 选择最快响应的流
  void _selectBestStream(Map<String, int> streams, Completer<String> completer, CancelToken token) {
    if (isCompareDone || completer.isCompleted) return;
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

    if (!completer.isCompleted) {
      completer.complete(selectedStream);
    }
  }

  /// 设置取消监听器
  void setupCancelListener() {
    if (cancelToken != null) {
      try {
        if (cancelToken!.isCancelled && !isResourceCleaned) {
          LogUtil.i('检测到取消状态，清理资源');
          cleanupResources(immediate: true);
          return;
        }

        cancelListener = cancelToken!.whenCancel.then((_) {
          LogUtil.i('检测到取消信号，释放资源');
          if (!isResourceCleaned) {
            cleanupResources(immediate: true);
          }
        }).asStream().listen((_) {});
      } catch (e) {
        LogUtil.e('设置取消监听器失败: $e');
      }
    }
  }

  /// 设置全局超时
  void setupGlobalTimeout() {
    _timerManager.set(
      'globalTimeout',
      Duration(seconds: AppConstants.globalTimeoutSeconds),
      () {
        if (_checkCancelledAndHandle('全局超时')) return;

        if (!isCollectionFinished && foundStreams.isNotEmpty) {
          LogUtil.i('全局超时，结束收集，测试${foundStreams.length}个流');
          finishCollectionAndTest();
        } else if (_shouldSwitchEngine()) {
          LogUtil.i('全局超时，主引擎无流，切换备用引擎');
          switchToBackupEngine();
        } else {
          LogUtil.i('全局超时，无可用流');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            cleanupResources();
          }
        }
      },
    );
  }

  /// 完成收集并开始测试
  void finishCollectionAndTest() {
    if (_checkCancelledAndHandle('收集完成', completeWithError: false)) return;

    if (isCollectionFinished || isTestingStarted) return;

    isCollectionFinished = true;
    _timerManager.cancel('noMoreChanges');
    startStreamTesting();
  }

  /// 设置无变化检测定时器
  void setupNoMoreChangesDetection() {
    _timerManager.set(
      'noMoreChanges',
      Duration(seconds: AppConstants.noMoreChangesSeconds),
      () {
        if (_checkCancelledAndHandle('无变化检测', completeWithError: false)) return;

        if (!isCollectionFinished && foundStreams.isNotEmpty) {
          finishCollectionAndTest();
        }
      },
    );
  }

  /// 清理资源
  Future<void> cleanupResources({bool immediate = false}) async {
    if (_isCleaningUp || isResourceCleaned) {
      LogUtil.i('资源已清理或正在清理');
      return;
    }

    _isCleaningUp = true;

    try {
      isResourceCleaned = true;
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

      if (tempController != null) {
        try {
          await tempController.loadHtmlString('<html><body></body></html>').timeout(
            Duration(milliseconds: AppConstants.emptyHtmlLoadTimeoutMs),
            onTimeout: () {
              LogUtil.i('加载空页面超时');
              return;
            },
          );

          if (!immediate) {
            await WebViewPool.release(tempController);
          }
        } catch (e) {
          LogUtil.e('清理WebView失败: $e');
        }
      }

      if (!completer.isCompleted) {
        completer.complete('ERROR');
        LogUtil.i('取消时完成completer');
      }

      _urlCache.clear();
    } catch (e) {
      LogUtil.e('资源清理失败: $e');
    } finally {
      _isCleaningUp = false;
      LogUtil.i('资源清理完成');
    }
  }

  /// 执行异步操作，统一错误处理
  Future<void> _executeAsyncOperation(
    String operationName,
    Future<void> Function() operation, {
    Function? onError,
  }) async {
    try {
      if (_checkCancelledAndHandle(operationName, completeWithError: false)) return;
      await operation();
    } catch (e) {
      LogUtil.e('$operationName失败: $e');
      if (onError != null) {
        onError();
      } else if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }

  /// 测试单个流
  Future<bool> _testSingleStream(
    String streamUrl,
    Map<String, int> successfulStreams,
    Set<String> inProgressTests,
    CancelToken cancelToken,
    Completer<String> resultCompleter,
  ) async {
    if (resultCompleter.isCompleted || cancelToken.isCancelled) return false;

    inProgressTests.add(streamUrl);
    try {
      final stopwatch = Stopwatch()..start();
      final response = await HttpUtil().getRequestWithResponse(
        streamUrl,
        options: Options(
          headers: HeadersConfig.generateHeaders(url: streamUrl),
          method: 'GET',
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
        cancelToken: cancelToken,
        retryCount: 1,
      );

      final testTime = stopwatch.elapsedMilliseconds;

      if (response != null && !resultCompleter.isCompleted && !cancelToken.isCancelled) {
        bool isValidContent = true;
        if (response.data is List<int> && response.data.length > 0) {
          final contentBytes = response.data as List<int>;

          if (streamUrl.toLowerCase().contains('.m3u8') && contentBytes.length >= 5) {
            final prefix = String.fromCharCodes(contentBytes.take(5));
            if (!prefix.startsWith('#EXTM')) {
              isValidContent = false;
              LogUtil.i('流 $streamUrl 无效: 非m3u8文件');
            }
          }
        }

        if (isValidContent) {
          LogUtil.i('流 $streamUrl 测试成功，响应: ${testTime}ms');
          successfulStreams[streamUrl] = testTime;

          if (testTime < AppConstants.streamFastEnoughThresholdMs && !isCompareDone) {
            LogUtil.i('流 $streamUrl 快速响应(${testTime}ms)，立即返回');
            _selectBestStream({streamUrl: testTime}, resultCompleter, cancelToken);
            return true;
          }

          return true;
        }
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        LogUtil.e('测试流 $streamUrl 失败: $e');
      }
    } finally {
      inProgressTests.remove(streamUrl);
    }

    return false;
  }

  /// 处理所有测试完成检查
  void _handleAllTestsComplete(
    Set<String> inProgressTests,
    List<String> pendingStreams,
    Map<String, int> successfulStreams,
    bool isCompareWindowStarted,
    Completer<String> resultCompleter,
    CancelToken cancelToken,
  ) {
    if (inProgressTests.isEmpty && pendingStreams.isEmpty && !resultCompleter.isCompleted) {
      if (successfulStreams.isEmpty) {
        LogUtil.i('所有流测试失败，返回ERROR');
        resultCompleter.complete('ERROR');
      } else if (!isCompareDone && isCompareWindowStarted) {
        LogUtil.i('等待比较窗口结束');
      } else if (!isCompareDone && !isCompareWindowStarted) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      }
    }
  }

  /// 开始流测试
  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('流测试已开始，忽略重复请求');
      return;
    }

    if (_checkCancelledAndHandle('流测试', completeWithError: false)) return;

    if (foundStreams.isEmpty) {
      LogUtil.i('无流链接，无法测试');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }

    isTestingStarted = true;
    LogUtil.i('开始测试${foundStreams.length}个流');

    if (cancelToken != null && cancelToken!.isCancelled) {
      LogUtil.i('父级取消，中止测试');
      return;
    }

    _testStreamsAsync(cancelToken, null);
  }

  /// 异步测试流
  Future<void> _testStreamsAsync(CancelToken? testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      _sortStreamsByPriority();
      final result = await _testStreamsWithConcurrencyControl(foundStreams, testCancelToken ?? CancelToken());
      LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
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

  /// 带并发控制的流测试
  Future<String> _testStreamsWithConcurrencyControl(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR';

    final int maxConcurrent = AppConstants.maxConcurrentTests;
    final List<String> pendingStreams = List.from(streams);
    final Completer<String> resultCompleter = Completer<String>();
    final Set<String> inProgressTests = {};
    final Map<String, int> successfulStreams = {};

    isCompareWindowStarted = true;

    _timerManager.set(
      'compareWindow',
      Duration(milliseconds: AppConstants.streamCompareTimeWindowMs),
      () {
        if (!isCompareDone && !resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter, cancelToken);
        }
      },
    );

    _timerManager.set(
      'streamTestTimeout',
      Duration(seconds: AppConstants.streamTestOverallTimeoutSeconds),
      () {
        if (!resultCompleter.isCompleted) {
          if (successfulStreams.isNotEmpty) {
            _selectBestStream(successfulStreams, resultCompleter, cancelToken);
          } else {
            LogUtil.i('流测试超时${AppConstants.streamTestOverallTimeoutSeconds}秒');
            resultCompleter.complete('ERROR');
          }
        }
      },
    );

    void startNextTests() {
      if (resultCompleter.isCompleted) return;

      while (inProgressTests.length < maxConcurrent && pendingStreams.isNotEmpty) {
        final nextStream = pendingStreams.removeAt(0);
        _testSingleStream(
          nextStream,
          successfulStreams,
          inProgressTests,
          cancelToken,
          resultCompleter,
        ).then((success) {
          _handleAllTestsComplete(
            inProgressTests,
            pendingStreams,
            successfulStreams,
            isCompareWindowStarted,
            resultCompleter,
            cancelToken,
          );

          startNextTests();
        }).catchError((e) {
          LogUtil.e('测试流未捕获异常: $e');
          startNextTests();
        });
      }
    }

    startNextTests();

    try {
      final result = await resultCompleter.future;
      _timerManager.cancel('compareWindow');
      _timerManager.cancel('streamTestTimeout');
      return result;
    } catch (e) {
      LogUtil.e('等待测试结果失败: $e');
      return 'ERROR';
    } finally {
      _timerManager.cancel('compareWindow');
      _timerManager.cancel('streamTestTimeout');
    }
  }

  /// 按优先级排序流，优先m3u8格式
  void _sortStreamsByPriority() {
    if (foundStreams.isEmpty) return;

    try {
      foundStreams.sort((a, b) {
        bool aIsM3u8 = a.toLowerCase().contains('.m3u8');
        bool bIsM3u8 = b.toLowerCase().contains('.m3u8');
        if (aIsM3u8 && !bIsM3u8) return -1;
        if (!aIsM3u8 && bIsM3u8) return 1;
        return 0;
      });
    } catch (e) {
      LogUtil.e('排序流地址失败: $e');
    }
  }

  /// 检查是否需要切换引擎
  bool _shouldSwitchEngine() => !searchState[AppConstants.engineSwitched];

  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState[AppConstants.engineSwitched] == true) {
      LogUtil.i('已切换引擎，忽略');
      return;
    }

    await _executeAsyncOperation('切换引擎', () async {
      final String currentEngine = searchState[AppConstants.activeEngine] as String;
      final String targetEngine = (currentEngine == 'primary') ? 'backup' : 'primary';
      final String targetUrl = (targetEngine == 'primary') ? AppConstants.primaryEngine : AppConstants.backupEngine;

      LogUtil.i('从$currentEngine切换到$targetEngine引擎');

      searchState[AppConstants.activeEngine] = targetEngine;
      searchState[AppConstants.engineSwitched] = true;
      searchState[AppConstants.searchSubmitted] = false;
      searchState[AppConstants.lastHtmlLength] = 0;
      searchState[AppConstants.extractionCount] = 0;
      searchState[AppConstants.stage] = ParseStage.formSubmission;
      searchState[AppConstants.stage1StartTime] = DateTime.now().millisecondsSinceEpoch;
      isDomMonitorInjected = false;
      isFormDetectionInjected = false;
      isFingerprintRandomizationInjected = false;
      isCollectionFinished = false;
      _timerManager.cancel('noMoreChanges');
      _timerManager.cancel('globalTimeout');

      if (controller != null) {
        await controller!.loadRequest(Uri.parse(targetUrl));
        LogUtil.i('加载$targetEngine引擎: $targetUrl');
        setupGlobalTimeout();
      } else {
        LogUtil.e('WebView控制器为空');
        throw Exception('WebView控制器为空');
      }
    });
  }

  /// 处理内容变化
  void handleContentChange() {
    _timerManager.cancel('contentChangeDebounce');

    if (_checkCancelledAndHandle('内容变化', completeWithError: false) ||
        isCollectionFinished ||
        isTestingStarted ||
        isExtractionInProgress) {
      LogUtil.i('跳过内容变化处理');
      return;
    }

    _timerManager.set(
      'contentChangeDebounce',
      Duration(milliseconds: AppConstants.contentChangeDebounceMs),
      () async {
        if (controller == null ||
            completer.isCompleted ||
            _checkCancelledAndHandle('内容处理', completeWithError: false) ||
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
            bool isBackupEngine = searchState[AppConstants.activeEngine] == 'backup';

            await SousuoParser._extractMediaLinks(
              controller!,
              foundStreams,
              isBackupEngine,
              lastProcessedLength: searchState[AppConstants.lastHtmlLength],
              urlCache: _urlCache,
            );

            try {
              final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length');
              searchState[AppConstants.lastHtmlLength] = int.tryParse(result.toString()) ?? 0;
            } catch (e) {
              LogUtil.e('获取HTML长度失败: $e');
            }

            if (_checkCancelledAndHandle('提取后处理', completeWithError: false)) return;

            searchState[AppConstants.extractionCount] = searchState[AppConstants.extractionCount] + 1;
            int afterExtractCount = foundStreams.length;

            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('新增${afterExtractCount - beforeExtractCount}个链接，总数: $afterExtractCount');
              setupNoMoreChangesDetection();
              if (afterExtractCount >= AppConstants.maxStreams) {
                finishCollectionAndTest();
              }
            } else if (_shouldSwitchEngine() && afterExtractCount == 0) {
              switchToBackupEngine();
            } else if (afterExtractCount > 0) {
              setupNoMoreChangesDetection();
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
      final String scriptTemplate = await SousuoParser._loadScriptFromAssets('assets/js/dom_change_monitor.js');
      final script = scriptTemplate.replaceAll('%CHANNEL_NAME%', 'AppChannel');
      await controller!.runJavaScript(script);
      isDomMonitorInjected = true;
      LogUtil.i('注入DOM监听器成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入DOM监听器失败', e, stackTrace);
      isDomMonitorInjected = false;
    }
  }

  /// 注入表单检测脚本
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null || isFormDetectionInjected) return;

    try {
      final String scriptTemplate = await SousuoParser._loadScriptFromAssets('assets/js/form_detection.js');
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      final script = scriptTemplate.replaceAll('%SEARCH_KEYWORD%', escapedKeyword);
      await controller!.runJavaScript(script);
      isFormDetectionInjected = true;
      LogUtil.i('注入表单检测脚本成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
      isFormDetectionInjected = false;
    }
  }

  /// 注入指纹随机化脚本
  Future<void> injectFingerprintRandomization() async {
    if (controller == null || isFingerprintRandomizationInjected) return;
    try {
      final String script = await SousuoParser._loadScriptFromAssets('assets/js/fingerprint_randomization.js');
      await controller!.runJavaScript(script);
      isFingerprintRandomizationInjected = true;
      LogUtil.i('注入指纹随机化脚本成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入指纹随机化脚本失败', e, stackTrace);
    }
  }

  /// 处理页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('导航', completeWithError: false)) return;

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

    if (searchState[AppConstants.engineSwitched] == true && SousuoParser._isPrimaryEngine(pageUrl) && controller != null) {
      try {
        await controller!.loadHtmlString('<html><body></body></html>');
      } catch (e) {
        LogUtil.e('中断主引擎加载失败: $e');
      }
      return;
    }
  }

  /// 处理页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    if (_checkCancelledAndHandle('页面完成', completeWithError: false)) return;

    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastPageFinishedTime.containsKey(pageUrl)) {
      int lastTime = _lastPageFinishedTime[pageUrl]!;
      if (currentTimeMs - lastTime < AppConstants.contentChangeDebounceMs) {
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

    bool isPrimaryEngine = SousuoParser._isPrimaryEngine(pageUrl);
    bool isBackupEngine = SousuoParser._isBackupEngine(pageUrl);

    if (!isPrimaryEngine && !isBackupEngine) {
      LogUtil.i('未知页面: $pageUrl');
      return;
    }

    if (searchState[AppConstants.engineSwitched] == true && isPrimaryEngine) return;

    if (isPrimaryEngine) {
      searchState[AppConstants.activeEngine] = 'primary';
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) {
      searchState[AppConstants.activeEngine] = 'backup';
      LogUtil.i('备用引擎页面加载完成');
    }

    if (searchState[AppConstants.searchSubmitted] == true) {
      if (!isExtractionInProgress && !isTestingStarted && !isCollectionFinished) {
        if (_checkCancelledAndHandle('延迟内容处理', completeWithError: false)) return;

        _timerManager.set(
          'delayedContentChange',
          Duration(seconds: AppConstants.waitSeconds),
          () {
            LogUtil.i('备用定时器触发');
            if (controller != null &&
                !completer.isCompleted &&
                !cancelToken!.isCancelled &&
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

  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (_checkCancelledAndHandle('资源错误', completeWithError: false)) return;

    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}');

    if (error.url == null ||
        error.url!.endsWith('.png') ||
        error.url!.endsWith('.jpg') ||
        error.url!.endsWith('.gif') ||
        error.url!.endsWith('.webp') ||
        error.url!.endsWith('.css')) {
      return;
    }

    if (searchState[AppConstants.activeEngine] == 'primary' && error.url != null && error.url!.contains('tonkiang.us')) {
      bool isCriticalError = [-1, -2, -3, -6, -7, -101, -105, -106].contains(error.errorCode);

      if (isCriticalError) {
        LogUtil.i('主引擎关键错误: ${error.errorCode}');
        searchState[AppConstants.primaryEngineLoadFailed] = true;

        if (searchState[AppConstants.searchSubmitted] == false && searchState[AppConstants.engineSwitched] == false) {
          LogUtil.i('主引擎加载失败，切换备用引擎');
          switchToBackupEngine();
        }
      }
    }
  }

  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (_checkCancelledAndHandle('导航', completeWithError: false)) {
      return NavigationDecision.prevent;
    }

    if (searchState[AppConstants.engineSwitched] == true && SousuoParser._isPrimaryEngine(request.url)) {
      LogUtil.i('阻止主引擎导航');
      return NavigationDecision.prevent;
    }

    if (request.url.endsWith('.png') ||
        request.url.endsWith('.jpg') ||
        request.url.endsWith('.jpeg') ||
        request.url.endsWith('.gif') ||
        request.url.endsWith('.webp') ||
        request.url.endsWith('.css') ||
        request.url.endsWith('.svg') ||
        request.url.endsWith('.woff') ||
        request.url.endsWith('.woff2') ||
        request.url.endsWith('.ttf') ||
        request.url.endsWith('.ico') ||
        request.url.contains('google-analytics.com') ||
        request.url.contains('googletagmanager.com') ||
        request.url.contains('facebook.com') ||
        request.url.contains('twitter.com')) {
      LogUtil.i('阻止非必要资源: ${request.url}');
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  /// 处理JavaScript消息
  Future<void> handleJavaScriptMessage(JavaScriptMessage message) async {
    if (_checkCancelledAndHandle('JS消息', completeWithError: false)) return;

    LogUtil.i('收到消息: ${message.message}');

    if (controller == null) {
      LogUtil.e('控制器为空');
      return;
    }

    if (message.message == 'CONTENT_READY' || message.message == 'CONTENT_CHANGED') {
      LogUtil.i('内容变化或就绪，触发处理');
      handleContentChange();
      return;
    }

    if (message.message == 'FORM_SUBMITTED') {
      searchState[AppConstants.searchSubmitted] = true;
      searchState[AppConstants.stage] = ParseStage.searchResults;
      searchState[AppConstants.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('表单已提交');
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      if (_shouldSwitchEngine()) {
        LogUtil.i('表单处理失败，切换引擎');
        switchToBackupEngine();
      }
    } else if (message.message == 'SIMULATION_FAILED') {
      LogUtil.e('模拟真人行为失败');
    } else if (message.message.startsWith('点击了搜索输入框') ||
        message.message.startsWith('填写了搜索关键词') ||
        message.message.startsWith('点击提交按钮') ||
        message.message.startsWith('点击输入框') ||
        message.message.startsWith('点击body') ||
        message.message.startsWith('点击了随机元素') ||
        message.message.startsWith('点击页面随机位置') ||
        message.message.startsWith('填写后点击')) {
      LogUtil.i('用户交互: ${message.message}');
    } else {
      LogUtil.i('未知消息: ${message.message}');
    }
  }

  /// 开始解析流程
  Future<String> startParsing(String url) async {
    try {
      if (_isCancelled()) {
        LogUtil.i('任务已取消，返回ERROR');
        return 'ERROR';
      }

      setupCancelListener();
      setupGlobalTimeout();

      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];

      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词');
        return 'ERROR';
      }

      searchState[AppConstants.searchKeyword] = searchKeyword;

      controller = await WebViewPool.acquire();

      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: handleJavaScriptMessage,
      );

      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: handlePageStarted,
        onPageFinished: handlePageFinished,
        onWebResourceError: handleWebResourceError,
        onNavigationRequest: handleNavigationRequest,
      ));

      try {
        final String engineUrl = (searchState[AppConstants.activeEngine] == 'primary') ? AppConstants.primaryEngine : AppConstants.backupEngine;
        LogUtil.i('加载引擎: ${searchState[AppConstants.activeEngine]}');
        await controller!.loadRequest(Uri.parse(engineUrl));
      } catch (e) {
        LogUtil.e('页面加载失败: $e');
        if (searchState[AppConstants.engineSwitched] == false) {
          LogUtil.i('引擎加载失败，切换引擎');
          await switchToBackupEngine();
        }
      }

      final result = await completer.future;

      if (!_isCancelled() && !isResourceCleaned) {
        final String usedEngine = searchState[AppConstants.activeEngine] as String;
        SousuoParser._updateLastUsedEngine(usedEngine);
        int endTimeMs = DateTime.now().millisecondsSinceEpoch;
        int startMs = searchState[AppConstants.startTimeMs] as int;
        LogUtil.i('解析耗时: ${endTimeMs - startMs}ms');
      }

      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);

      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('找到${foundStreams.length}个流，尝试测试');
        try {
          _sortStreamsByPriority();
          final result = await _testStreamsWithConcurrencyControl(foundStreams, cancelToken ?? CancelToken());
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

/// CancelToken合并类，统一管理多个CancelToken
class CancelTokenMerger extends CancelToken {
  final List<CancelToken> _tokens; /// 合并的CancelToken列表
  final List<StreamSubscription> _subscriptions = []; /// 取消订阅列表

  CancelTokenMerger(this._tokens) {
    for (final token in _tokens) {
      if (token.isCancelled) {
        if (!isCancelled) cancel('组件token已取消');
        break;
      }

      final subscription = token.whenCancel.then((_) {
        if (!isCancelled) {
          LogUtil.i('组件token取消，触发合并取消');
          cancel('组件token已取消');
        }
      }).asStream().listen((_) {});

      _subscriptions.add(subscription);
    }
  }

  @override
  Future<void> cancel([Object? reason]) async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final token in _tokens) {
      if (!token.isCancelled) token.cancel(reason);
    }

    return super.cancel(reason);
  }
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  static String? _lastUsedEngine; /// 上次使用的引擎
  static final RegExp _mediaLinkRegex = RegExp(
   'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false,
  ); /// 提取媒体链接正则
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false); /// 检测m3u8链接正则
  static List<String> _blockKeywords = List.from(AppConstants.defaultBlockKeywords); /// 屏蔽关键词列表
  static final _SearchCache _searchCache = _SearchCache(); /// LRU缓存实例
  static final Map<String, String> _scriptCache = {}; /// 脚本缓存
  static final Map<String, String> _hostKeyCache = {}; /// 主机键缓存
  static const int _maxHostKeyCacheSize = 100; /// 主机键缓存最大大小
  static final Map<String, Completer<String?>> _searchCompleters = {}; /// 防止重复搜索映射
  static final Map<WebViewController, bool> _domMonitorInjectedControllers = {}; /// DOM监听器注入记录
  static final Map<WebViewController, bool> _fingerprintRandomizationInjectedControllers = {}; /// 指纹随机化脚本注入记录

  /// 初始化WebView池和预加载脚本
  static Future<void> initialize() async {
    await WebViewPool.initialize();
    await _preloadScripts();
  }

  /// 预加载所有脚本
  static Future<void> _preloadScripts() async {
    try {
      LogUtil.i('预加载脚本开始');
      await Future.wait([
        _loadScriptFromAssets('assets/js/form_detection.js'),
        _loadScriptFromAssets('assets/js/fingerprint_randomization.js'),
        _loadScriptFromAssets('assets/js/dom_change_monitor.js'),
      ]);
      LogUtil.i('预加载脚本完成');
    } catch (e) {
      LogUtil.e('预加载脚本失败: $e');
    }
  }

  /// 从assets加载JS脚本
  static Future<String> _loadScriptFromAssets(String filePath) async {
    if (_scriptCache.containsKey(filePath)) return _scriptCache[filePath]!;

    try {
      final script = await rootBundle.loadString(filePath);
      _scriptCache[filePath] = script;
      return script;
    } catch (e, stackTrace) {
      LogUtil.e('加载脚本($filePath)失败: $e');
      try {
        final script = await rootBundle.loadString(filePath);
        _scriptCache[filePath] = script;
        return script;
      } catch (e2) {
        LogUtil.e('二次加载脚本文件失败: $filePath, $e2');
        return '(function(){console.error("Failed to load script: $filePath");})();';
      }
    }
  }

  /// 设置屏蔽关键词
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      _blockKeywords = List.from(AppConstants.defaultBlockKeywords);
    }
  }

  /// 清理WebView资源
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage();
      await controller.clearCache();
      LogUtil.i('WebView清理完成');
    } catch (e) {
      LogUtil.e('WebView清理失败: $e');
    }
  }

  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) => url.contains('tonkiang.us');

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) => url.contains('foodieguide.com');

  /// 注入DOM变化监听器
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    if (_domMonitorInjectedControllers[controller] == true) {
      LogUtil.i('DOM监听器已注入，跳过');
      return;
    }

    try {
      final scriptTemplate = await _loadScriptFromAssets('assets/js/dom_change_monitor.js');
      final script = scriptTemplate.replaceAll('%CHANNEL_NAME%', channelName);
      await controller.runJavaScript(script);
      _domMonitorInjectedControllers[controller] = true;
      LogUtil.i('DOM监听器注入成功');
    } catch (e, stackTrace) {
      LogUtil.e('DOM监听器注入失败: $e');
      _domMonitorInjectedControllers[controller] = false;
    }
  }

  /// 注入指纹随机化脚本
  static Future<void> _injectFingerprintRandomization(WebViewController controller) async {
    if (_fingerprintRandomizationInjectedControllers[controller] == true) {
      LogUtil.i('指纹随机化脚本已注入，跳过');
      return;
    }

    try {
      final script = await _loadScriptFromAssets('assets/js/fingerprint_randomization.js');
      await controller.runJavaScript(script);
      _fingerprintRandomizationInjectedControllers[controller] = true;
      LogUtil.i('指纹随机化脚本注入成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入指纹随机化脚本失败', e, stackTrace);
      _fingerprintRandomizationInjectedControllers[controller] = false;
    }
  }

  /// 清理HTML字符串
  static String _cleanHtmlString(String htmlContent) {
    final length = htmlContent.length;
    if (length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) return htmlContent;

    final buffer = StringBuffer();
    final innerContent = htmlContent.substring(1, length - 1);

    int i = 0;
    final contentLength = innerContent.length;

    while (i < contentLength) {
      if (i < contentLength - 1 && innerContent[i] == '\\') {
        final nextChar = innerContent[i + 1];
        switch (nextChar) {
          case '"':
            buffer.write('"');
            i += 2;
            break;
          case 'n':
            buffer.write('\n');
            i += 2;
            break;
          case 't':
            buffer.write('\t');
            i += 2;
            break;
          case '\\':
            buffer.write('\\');
            i += 2;
            break;
          default:
            buffer.write(innerContent[i]);
            i++;
        }
      } else {
        int start = i;
        while (i < contentLength && (i >= contentLength - 1 || innerContent[i] != '\\')) i++;
        if (i > start) buffer.write(innerContent.substring(start, i));
      }
    }

    return buffer.toString();
  }

  /// 获取主机键值，使用缓存
  static String _getHostKey(String url) {
    if (_hostKeyCache.containsKey(url)) return _hostKeyCache[url]!;

    try {
      final uri = Uri.parse(url);
      final hostKey = '${uri.host}:${uri.port}';

      if (_hostKeyCache.length >= _maxHostKeyCacheSize) _hostKeyCache.remove(_hostKeyCache.keys.first);
      _hostKeyCache[url] = hostKey;

      return hostKey;
    } catch (e) {
      LogUtil.e('解析URL主机键出错: $e, URL: $url');
      return url;
    }
  }

  /// 批量处理URL
  static void _batchProcessUrls(
    Iterable<String?> urls,
    Set<String> m3u8Links,
    Set<String> otherLinks,
    Map<String, bool> hostMap,
  ) {
    for (final rawUrl in urls) {
      if (rawUrl == null || rawUrl.isEmpty) continue;

      final String mediaUrl = rawUrl
          .trim()
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp("[\")'&;]+\$"), '');

      if (mediaUrl.isEmpty || _isUrlBlocked(mediaUrl)) continue;

      try {
        final hostKey = _getHostKey(mediaUrl);
        if (hostMap.containsKey(hostKey)) continue;

        hostMap[hostKey] = true;

        final lowerUrl = mediaUrl.toLowerCase();
        final isM3u8 = lowerUrl.endsWith('.m3u8') || lowerUrl.contains('.m3u8?') || _m3u8Regex.hasMatch(mediaUrl);

        if (isM3u8) {
          m3u8Links.add(mediaUrl);
        } else {
          otherLinks.add(mediaUrl);
        }
      } catch (e) {
        LogUtil.e('URL处理失败: $mediaUrl, $e');
      }
    }
  }

  /// 提取媒体链接
  static Future<void> _extractMediaLinks(
    WebViewController controller,
    List<String> foundStreams,
    bool usingBackupEngine, {
    int lastProcessedLength = 0,
    Map<String, bool>? urlCache,
  }) async {
    try {
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      String htmlContent = _cleanHtmlString(html.toString());
      final contentLength = htmlContent.length;
      LogUtil.i('HTML获取，长度: $contentLength');

      if (lastProcessedLength > 0 && contentLength <= lastProcessedLength) {
        LogUtil.i('内容长度未增加，跳过提取');
        return;
      }

      if (lastProcessedLength > 0) {
        htmlContent = htmlContent.substring(lastProcessedLength);
        LogUtil.i('增量处理HTML，新增长度: ${htmlContent.length}');
      }

      final matches = _mediaLinkRegex.allMatches(htmlContent);
      final totalMatches = matches.length;

      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> URL: ${firstMatch.group(2)}');
      }

      final Set<String> m3u8Links = {};
      final Set<String> otherLinks = {};
      final Map<String, bool> hostMap = urlCache ?? {};

      if (urlCache == null && foundStreams.isNotEmpty) {
        for (final url in foundStreams) {
          try {
            final hostKey = _getHostKey(url);
            hostMap[hostKey] = true;
          } catch (_) {
            hostMap[url] = true;
          }
        }
      }

      final extractedUrls = matches.map((m) => m.group(2)?.trim()).toList();
      _batchProcessUrls(extractedUrls, m3u8Links, otherLinks, hostMap);

      int addedCount = 0;
      final remainingSlots = AppConstants.maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达最大链接数(${AppConstants.maxStreams})，停止添加');
        return;
      }

      for (final link in m3u8Links) {
        if (!foundStreams.contains(link)) {
          foundStreams.add(link);
          addedCount++;
          if (foundStreams.length >= AppConstants.maxStreams) {
            LogUtil.i('达到最大链接数(${AppConstants.maxStreams})，m3u8已足够');
            break;
          }
        }
      }

      if (foundStreams.length < AppConstants.maxStreams) {
        for (final link in otherLinks) {
          if (!foundStreams.contains(link)) {
            foundStreams.add(link);
            addedCount++;
            if (foundStreams.length >= AppConstants.maxStreams) {
              LogUtil.i('达到最大链接数(${AppConstants.maxStreams})');
              break;
            }
          }
        }
      }

      LogUtil.i('匹配: $totalMatches, m3u8: ${m3u8Links.length}, 其他: ${otherLinks.length}, 新增: $addedCount');

      if (addedCount == 0 && totalMatches == 0) {
        final sampleLength = htmlContent.length > AppConstants.minValidContentLength ? AppConstants.minValidContentLength : htmlContent.length;
        final debugSample = htmlContent.substring(0, sampleLength);
        final onclickRegex = RegExp(r'onclick="[^"]+"', caseSensitive: false);
        final onclickMatches = onclickRegex.allMatches(htmlContent).take(3).map((m) => m.group(0)).join(', ');
        if (onclickMatches.isNotEmpty) {
          LogUtil.i('页面onclick样本: $onclickMatches');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.e('链接提取失败: $e');
    }

    LogUtil.i('提取完成，链接总数: ${foundStreams.length}');
  }

  /// 检查URL是否包含屏蔽关键词
  static bool _isUrlBlocked(String url) {
    if (_blockKeywords.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase()));
  }

  /// 获取初始引擎
  static String _getInitialEngine() {
    try {
      if (_lastUsedEngine == null) {
        _lastUsedEngine = SpUtil.getString('last_used_engine');
        LogUtil.i('读取缓存引擎: $_lastUsedEngine');
      }

      if (_lastUsedEngine != null && _lastUsedEngine!.isNotEmpty) {
        final nextEngine = _lastUsedEngine == 'primary' ? 'backup' : 'primary';
        LogUtil.i('上次引擎: $_lastUsedEngine, 本次: $nextEngine');
        return nextEngine;
      }

      LogUtil.i('无缓存，使用主引擎');
      return 'primary';
    } catch (e) {
      LogUtil.e('获取初始引擎失败: $e');
      return 'primary';
    }
  }

  /// 更新最后使用的引擎
  static void _updateLastUsedEngine(String engine) {
    try {
      _lastUsedEngine = engine;
      SpUtil.putString('last_used_engine', engine);
      LogUtil.i('更新缓存引擎: $engine');
    } catch (e) {
      LogUtil.e('更新引擎缓存失败: $e');
    }
  }

  /// 验证缓存URL
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

  /// 使用初始引擎搜索
  static Future<String?> _searchWithInitialEngine(String keyword, CancelToken? cancelToken) async {
    final normalizedKeyword = keyword.trim().toLowerCase();

    if (_searchCompleters.containsKey(normalizedKeyword)) {
      LogUtil.i('搜索($normalizedKeyword)进行中，等待结果');
      return await _searchCompleters[normalizedKeyword]!.future;
    }

    final completer = Completer<String?>();
    _searchCompleters[normalizedKeyword] = completer;

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
          await tempController.loadHtmlString('<html><body></body></html>').timeout(
            Duration(milliseconds: AppConstants.emptyHtmlLoadTimeoutMs),
            onTimeout: () => LogUtil.i('加载空页面超时'),
          );
          await WebViewPool.release(tempController);
        } catch (e) {
          LogUtil.e('WebView清理失败: $e');
        }
      }

      LogUtil.i('初始引擎资源清理完成');
    }

    try {
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('任务已取消');
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

      final searchUrl = '${AppConstants.initialEngine}${Uri.encodeComponent(keyword)}';
      LogUtil.i('初始引擎搜索: $searchUrl');

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
          if ((message.message == 'CONTENT_READY' || message.message == 'CONTENT_CHANGED') && !contentReadyProcessed) {
            contentReadyProcessed = true;
            LogUtil.i('初始引擎内容就绪');
            if (!pageLoadCompleter.isCompleted) pageLoadCompleter.complete(searchUrl);
          }
        },
      );

      await nonNullController.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          if (url == 'about:blank') {
            LogUtil.i('加载空白页，忽略');
            return;
          }
          if (!pageLoadCompleter.isCompleted && !contentReadyProcessed) {
            LogUtil.i('初始引擎页面加载: $url');
            pageLoadCompleter.complete(url);
          }
        },
        onWebResourceError: (error) => LogUtil.e('初始引擎资源错误: ${error.description}'),
      ));

      await nonNullController.loadRequest(Uri.parse(searchUrl));

      timerManager.set(
        'injectScripts',
        Duration(milliseconds: 300),
        () async {
          if (cancelToken?.isCancelled ?? false || pageLoadCompleter.isCompleted) return;
          try {
            await _injectDomChangeMonitor(nonNullController, 'AppChannel');
            await _injectFingerprintRandomization(nonNullController);
          } catch (e) {
            LogUtil.e('初始引擎脚本注入失败: $e');
          }
        },
      );

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

      final testSession = _ParserSession(cancelToken: cancelToken);
      testSession.foundStreams.addAll(extractedUrls);

      LogUtil.i('测试初始引擎链接: ${extractedUrls.length}');
      final result = await testSession._testStreamsWithConcurrencyControl(extractedUrls, cancelToken ?? CancelToken());

      timerManager.cancel('globalTimeout');
      final finalResult = result == 'ERROR' ? null : result;

      completer.complete(finalResult);
      return finalResult;
    } catch (e, stackTrace) {
      LogUtil.e('初始引擎搜索失败: $e');
      if (!isResourceCleaned) await cleanupResources();
      completer.complete(null);
      return null;
    } finally {
      if (!isResourceCleaned) await cleanupResources();
      if (!completer.isCompleted) completer.complete(null);
      _searchCompleters.remove(normalizedKeyword);
    }
  }

  /// 执行实际解析操作
  static Future<String> _performParsing(String url, String searchKeyword, CancelToken? cancelToken, String blockKeywords) async {
    final cachedUrl = _searchCache.getUrl(searchKeyword);
    if (cachedUrl != null) {
      LogUtil.i('缓存命中: $searchKeyword -> $cachedUrl');
      if (await _validateCachedUrl(searchKeyword, cachedUrl, cancelToken)) return cachedUrl;
      LogUtil.i('缓存失效，重新搜索');
    }

    LogUtil.i('尝试初始引擎: $searchKeyword');
    final initialEngineResult = await _searchWithInitialEngine(searchKeyword, cancelToken);

    if (initialEngineResult != null) {
      LogUtil.i('初始引擎成功: $initialEngineResult');
      _searchCache.addUrl(searchKeyword, initialEngineResult);
      return initialEngineResult;
    }

    LogUtil.i('初始引擎失败，进入标准解析');
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消');
      return 'ERROR';
    }

    final initialEngine = _getInitialEngine();
    final session = _ParserSession(cancelToken: cancelToken, initialEngine: initialEngine);
    final result = await session.startParsing(url);

    if (result != 'ERROR' && searchKeyword.isNotEmpty) {
      _searchCache.addUrl(searchKeyword, result);
    }

    return result;
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    final timeoutCompleter = Completer<String>();
    Timer? globalTimer = Timer(Duration(seconds: AppConstants.globalTimeoutSeconds), () {
      LogUtil.i('全局超时');
      if (!timeoutCompleter.isCompleted) timeoutCompleter.complete('ERROR');
    });

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

      // 创建一个包装的 Completer，只在真正完成时才传递结果
      final parseResultCompleter = Completer<String>();
      
      // 异步启动实际解析流程
      _performParsing(url, searchKeyword, cancelToken, blockKeywords).then((result) {
        // 只有在整个搜索流程完成时才传递结果
        if (!parseResultCompleter.isCompleted) {
          parseResultCompleter.complete(result);
        }
      }).catchError((e) {
        if (!parseResultCompleter.isCompleted) {
          LogUtil.e('解析过程中发生异常: $e');
          parseResultCompleter.complete('ERROR');
        }
      });
      
      // Future.any 现在只会在真正完成或超时时返回
      return await Future.any([parseResultCompleter.future, timeoutCompleter.future]);
    } catch (e, stackTrace) {
      LogUtil.logError('解析过程中发生异常', e, stackTrace);
      return 'ERROR';
    } finally {
      globalTimer?.cancel();
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    await WebViewPool.clear();
    _searchCache.dispose();
    _scriptCache.clear();
    _hostKeyCache.clear();
    _domMonitorInjectedControllers.clear();
    _fingerprintRandomizationInjectedControllers.clear();
    LogUtil.i('资源释放完成');
  }
}
