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

/// 解析阶段枚举
enum ParseStage {
  formSubmission, /// 页面加载与表单提交
  searchResults,  /// 搜索结果处理与流测试
  completed,      /// 解析完成
  error           /// 解析错误
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
  static const String primaryEngine = 'http://www.foodieguide.com/iptvsearch/';        /// 主备用引擎URL
  static const String backupEngine = 'https://tonkiang.us/?';                          /// 次备用引擎URL

  /// 超时与等待时间
  static const int globalTimeoutSeconds = 28;         /// 全局超时（秒）
  static const int waitSeconds = 2;                  /// 页面加载与提交等待（秒）
  static const int noMoreChangesSeconds = 2;         /// 无变化检测（秒）
  static const int domChangeWaitMs = 300;            /// DOM变化等待（毫秒）
  static const int contentChangeDebounceMs = 300;    /// 内容变化防抖（毫秒）
  static const int backupEngineLoadWaitMs = 200;     /// 切换备用引擎等待（毫秒）
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
  static const List<String> defaultBlockKeywords = ["freetv.fun", "epg.pw", "ktpremium.com"]; /// 默认屏蔽关键词
}

/// 缓存条目类，存储URL
class _CacheEntry {
  final String url; /// 缓存URL

  _CacheEntry(this.url); /// 初始化URL

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
      LogUtil.i('TimerManager已释放，忽略定时器创建: $key');
      return Timer(Duration.zero, () {});
    }

    final existingTimer = _timers[key];
    if (existingTimer != null) {
      try {
        existingTimer.cancel();
      } catch (e) {
        LogUtil.e('取消已有定时器错误($key): $e');
      }
    }

    final safeCallback = () {
      try {
        _timers.remove(key);
        if (!_isDisposed) callback();
      } catch (e) {
        LogUtil.e('定时器回调执行错误($key): $e');
      }
    };

    try {
      final timer = Timer(duration, safeCallback);
      _timers[key] = timer;
      return timer;
    } catch (e) {
      LogUtil.e('创建定时器错误($key): $e');
      return Timer(Duration.zero, () {});
    }
  }

  /// 创建周期性定时器
  Timer setPeriodic(String key, Duration duration, Function(Timer) callback) {
    if (_isDisposed) {
      LogUtil.i('TimerManager已释放，忽略周期定时器创建: $key');
      return Timer(Duration.zero, () {});
    }

    cancel(key);

    try {
      final timer = Timer.periodic(duration, (timer) {
        try {
          callback(timer);
        } catch (e) {
          LogUtil.e('周期定时器回调执行错误($key): $e');
          timer.cancel();
          _timers.remove(key);
        }
      });

      _timers[key] = timer;
      return timer;
    } catch (e) {
      LogUtil.e('创建周期定时器错误($key): $e');
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
        LogUtil.e('取消定时器错误($key): $e');
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
          LogUtil.e('取消定时器错误($key): $e');
        }
      });
      _timers.clear();
    } catch (e) {
      LogUtil.e('取消所有定时器错误: $e');
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
      LogUtil.i('WebView池初始化完成');
    } catch (e) {
      LogUtil.e('WebView池初始化失败: $e');
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
      LogUtil.i('从WebView池获取实例，剩余: ${_pool.length}');
      return controller;
    }

    LogUtil.i('WebView池为空，创建新实例');
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

      // 检查控制器是否已在池中
      bool isDuplicate = false;
      for (var existingController in _pool) {
        if (identical(existingController, controller)) {
          isDuplicate = true;
          LogUtil.i('WebView实例已存在于池中，忽略重复添加');
          break;
        }
      }

      if (!isDuplicate && _pool.length < maxPoolSize) {
        _pool.add(controller);
        LogUtil.i('WebView实例返回池，当前池大小: ${_pool.length}');
      } else if (!isDuplicate) {
        LogUtil.i('WebView池已满，丢弃实例');
      }
    } catch (e) {
      LogUtil.e('重置WebView实例失败: $e');
    }
  }

  /// 清理所有池实例
  static Future<void> clear() async {
    for (final controller in _pool) {
      try {
        await controller.loadHtmlString('<html><body></body></html>');
        await controller.clearCache();
      } catch (e) {
        LogUtil.e('清理WebView实例失败: $e');
      }
    }

    _pool.clear();
    LogUtil.i('WebView池已清空');
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
              LogUtil.e('解析缓存条目失败: $key, $e');
            }
          }
        }

        for (final key in data.keys) {
          if (!_cache.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              final entry = _CacheEntry.fromJson(data[key]);
              _cache[key] = entry;
            } catch (e) {
              LogUtil.e('解析缓存条目失败: $key, $e');
            }
          }
        }

        while (_cache.length > maxEntries && _cache.isNotEmpty) {
          _cache.remove(_cache.keys.first);
        }

        LogUtil.i('从持久化存储加载了 ${_cache.length} 个缓存条目');
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
    if (entry == null) {
      return null;
    }

    if (forceRemove) {
      final url = entry.url;
      _cache.remove(normalizedKeyword);
      _isDirty = true;

      _saveToPersistence();

      LogUtil.i('已从缓存中移除: $normalizedKeyword -> $url');
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
    if (keyword.isEmpty || url.isEmpty || url == 'ERROR') {
      return;
    }

    final normalizedKeyword = keyword.trim().toLowerCase();

    _cache.remove(normalizedKeyword);

    if (_cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      LogUtil.i('缓存已满，移除最旧的条目: $oldest');
    }

    _cache[normalizedKeyword] = _CacheEntry(url);
    _isDirty = true;

    LogUtil.i('添加缓存: $normalizedKeyword -> $url，当前缓存数: ${_cache.length}');
  }

  /// 清除所有缓存
  void clear() {
    _cache.clear();

    SpUtil.remove(_cacheKey);
    SpUtil.remove(_lruKey);
    _isDirty = false;

    LogUtil.i('清除了所有缓存');
  }

  /// 获取缓存大小
  int get size => _cache.length;

  /// 释放资源
  void dispose() {
    if (_isDirty) {
      _saveToPersistence();
    }
    _persistTimer?.cancel();
    _persistTimer = null;
  }
}

/// 解析会话类，处理解析逻辑和状态管理
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

  final Map<String, int> _lastPageFinishedTime = {};      /// 页面加载完成防抖映射
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

    String reason = streams.length == 1 ? "只有一个成功流" : "从${streams.length}个成功流中选择最快的";
    LogUtil.i('$reason: $selectedStream (${bestTime}ms)');

    if (!completer.isCompleted) {
      completer.complete(selectedStream);
      if (!token.isCancelled) {
        token.cancel('已找到最佳流');
      }
    }
  }

  /// 设置取消监听器
  void setupCancelListener() {
    if (cancelToken != null) {
      try {
        if (cancelToken!.isCancelled && !isResourceCleaned) {
          LogUtil.i('检测到cancelToken已是取消状态，立即清理资源');
          cleanupResources(immediate: true);
          return;
        }

        cancelListener = cancelToken!.whenCancel.then((_) {
          LogUtil.i('检测到取消信号，立即释放所有资源');
          if (!isResourceCleaned) {
            cleanupResources(immediate: true);
          }
        }).asStream().listen((_) {});
      } catch (e) {
        LogUtil.e('设置取消监听器出错: $e');
      }
    }
  }

  /// 设置全局超时
  void setupGlobalTimeout() {
    _timerManager.set(
      'globalTimeout',
      Duration(seconds: AppConstants.globalTimeoutSeconds),
      () {
        if (_checkCancelledAndHandle('不处理全局超时')) return;

        if (!isCollectionFinished && foundStreams.isNotEmpty) {
          LogUtil.i('全局超时触发，强制结束收集，开始测试 ${foundStreams.length} 个流');
          finishCollectionAndTest();
        } else if (_shouldSwitchEngine()) {
          LogUtil.i('全局超时触发，主引擎未找到流，切换备用引擎');
          switchToBackupEngine();
        } else {
          LogUtil.i('全局超时触发，无可用流');
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
    if (_checkCancelledAndHandle('不执行收集完成', completeWithError: false)) return;

    if (isCollectionFinished || isTestingStarted) {
      return;
    }

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
        if (_checkCancelledAndHandle('不执行无变化检测', completeWithError: false)) return;

        if (!isCollectionFinished && foundStreams.isNotEmpty) {
          finishCollectionAndTest();
        }
      },
    );
  }

  /// 清理资源
  Future<void> cleanupResources({bool immediate = false}) async {
    if (_isCleaningUp || isResourceCleaned) {
      LogUtil.i('资源已清理或正在清理中，跳过');
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
          LogUtil.e('取消监听器时出错: $e');
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
          LogUtil.e('清理WebView控制器出错: $e');
        }
      }

      // 修改：确保completer被完成，防止流程继续
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        LogUtil.i('取消时完成completer，确保流程终止');
      }

      _urlCache.clear();
    } catch (e) {
      LogUtil.e('资源清理过程中出错: $e');
    } finally {
      _isCleaningUp = false;
      LogUtil.i('所有资源清理完成，流程已终止');
    }
  }

  /// 执行异步操作，统一错误处理
  Future<void> _executeAsyncOperation(
    String operationName,
    Future<void> Function() operation, {
    Function? onError,
  }) async {
    try {
      if (_checkCancelledAndHandle('不执行$operationName', completeWithError: false)) return;
      await operation();
    } catch (e) {
      LogUtil.e('$operationName 出错: $e');
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
    if (resultCompleter.isCompleted || cancelToken.isCancelled) {
      return false;
    }

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
              LogUtil.i('流 $streamUrl 内容无效: 不是有效的m3u8文件');
            }
          }
        }

        if (isValidContent) {
          LogUtil.i('流 $streamUrl 测试成功，响应时间: ${testTime}ms');
          successfulStreams[streamUrl] = testTime;

          if (testTime < AppConstants.streamFastEnoughThresholdMs && !isCompareDone) {
            LogUtil.i('流 $streamUrl 响应足够快 (${testTime}ms < ${AppConstants.streamFastEnoughThresholdMs}ms)，立即返回');
            _selectBestStream({streamUrl: testTime}, resultCompleter, cancelToken);
            return true;
          }

          return true;
        }
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        LogUtil.e('测试流 $streamUrl 出错: $e');
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
        LogUtil.i('所有流测试完成，均失败，返回ERROR');
        resultCompleter.complete('ERROR');
      } else if (!isCompareDone && isCompareWindowStarted) {
        LogUtil.i('所有流测试完成，等待比较窗口结束后选择');
      } else if (!isCompareDone && !isCompareWindowStarted) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      }
    }
  }

  /// 开始流测试
  void startStreamTesting() {
    if (isTestingStarted) {
      LogUtil.i('已经开始测试流链接，忽略重复测试请求');
      return;
    }

    if (_checkCancelledAndHandle('不执行流测试', completeWithError: false)) return;

    if (foundStreams.isEmpty) {
      LogUtil.i('没有找到流链接，无法开始测试');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }

    isTestingStarted = true;
    LogUtil.i('开始测试 ${foundStreams.length} 个流链接');

    final testCancelToken = CancelToken();

    StreamSubscription? testCancelListener;
    if (cancelToken != null) {
      if (cancelToken!.isCancelled && !testCancelToken.isCancelled) {
        LogUtil.i('父级cancelToken已是取消状态，立即取消测试');
        testCancelToken.cancel('父级已取消');
      } else {
        testCancelListener = cancelToken!.whenCancel.then((_) {
          if (!testCancelToken.isCancelled) {
            LogUtil.i('父级cancelToken已取消，取消所有测试请求');
            testCancelToken.cancel('父级已取消');
          }
        }).asStream().listen((_) {});
      }
    }

    _testStreamsAsync(testCancelToken, testCancelListener);
  }

  /// 异步测试流
  Future<void> _testStreamsAsync(CancelToken testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      _sortStreamsByPriority();
      final result = await _testStreamsWithConcurrencyControl(foundStreams, testCancelToken);
      LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      if (!completer.isCompleted) {
        completer.complete(result);
        cleanupResources();
      }
    } catch (e) {
      LogUtil.e('测试流过程中出错: $e');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    } finally {
      try {
        await testCancelListener?.cancel();
      } catch (e) {
        LogUtil.e('取消测试监听器时出错: $e');
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
            LogUtil.i('流测试整体超时${AppConstants.streamTestOverallTimeoutSeconds}秒，返回ERROR');
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
      LogUtil.e('等待流测试结果时出错: $e');
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
      LogUtil.e('排序流地址时出错: $e');
    }
  }

  /// 检查是否需要切换引擎
  bool _shouldSwitchEngine() => !searchState[AppConstants.engineSwitched];

  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState[AppConstants.engineSwitched] == true) {
      LogUtil.i('已切换过引擎，忽略');
      return;
    }

    await _executeAsyncOperation('切换引擎', () async {
      final String currentEngine = searchState[AppConstants.activeEngine] as String;
      final String targetEngine = (currentEngine == 'primary') ? 'backup' : 'primary';
      final String targetUrl = (targetEngine == 'primary') ? AppConstants.primaryEngine : AppConstants.backupEngine;

      LogUtil.i('从 $currentEngine 引擎切换到 $targetEngine 引擎');

      searchState[AppConstants.activeEngine] = targetEngine;
      searchState[AppConstants.engineSwitched] = true;
      searchState[AppConstants.searchSubmitted] = false;
      searchState[AppConstants.lastHtmlLength] = 0;
      searchState[AppConstants.extractionCount] = 0;
      searchState[AppConstants.stage] = ParseStage.formSubmission;
      searchState[AppConstants.stage1StartTime] = DateTime.now().millisecondsSinceEpoch;
      isDomMonitorInjected = false;
      isFormDetectionInjected = false;
      isCollectionFinished = false;
      _timerManager.cancel('noMoreChanges');
      _timerManager.cancel('globalTimeout');

      if (controller != null) {
        await controller!.loadRequest(Uri.parse(targetUrl));
        LogUtil.i('已加载 $targetEngine 引擎: $targetUrl');
        setupGlobalTimeout();
      } else {
        LogUtil.e('WebView控制器为空，无法切换');
        throw Exception('WebView控制器为空');
      }
    });
  }

  /// 处理内容变化 - 修改版
  void handleContentChange() {
    _timerManager.cancel('contentChangeDebounce');

    // 增强初始检查，避免不必要处理
    if (_checkCancelledAndHandle('停止处理内容变化', completeWithError: false) || 
        isCollectionFinished || isTestingStarted || isExtractionInProgress) {
      LogUtil.i('跳过内容变化处理: 收集已完成或测试已开始或提取进行中');
      return;
    }

    _timerManager.set(
      'contentChangeDebounce',
      Duration(milliseconds: AppConstants.contentChangeDebounceMs),
      () async {
        // 再次检查状态，防止在防抖期间状态发生变化
        if (controller == null || completer.isCompleted || 
            _checkCancelledAndHandle('取消内容处理', completeWithError: false) || 
            isCollectionFinished || isTestingStarted || isExtractionInProgress) {
          LogUtil.i('防抖期间状态已变化，取消内容处理');
          return;
        }

        try {
          if (searchState[AppConstants.searchSubmitted] == true && !completer.isCompleted && !isTestingStarted) {
            isExtractionInProgress = true;  // 设置提取标志
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
              LogUtil.e('获取HTML长度时出错: $e');
            }

            if (_checkCancelledAndHandle('提取后取消处理', completeWithError: false)) {
              return;
            }

            searchState[AppConstants.extractionCount] = searchState[AppConstants.extractionCount] + 1;
            int afterExtractCount = foundStreams.length;

            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接，当前总数: ${afterExtractCount}');
              setupNoMoreChangesDetection();
              if (afterExtractCount >= AppConstants.maxStreams) {
                finishCollectionAndTest();
              }
            } else if (_shouldSwitchEngine() && afterExtractCount == 0) {
              switchToBackupEngine();
            } else {
              if (afterExtractCount > 0) {
                setupNoMoreChangesDetection();
              }
            }
          }
        } catch (e) {
          LogUtil.e('处理内容变化时出错: $e');
        } finally {
          isExtractionInProgress = false;
        }
      },
    );
  }

  /// 注入DOM监听器 - 修改使用增强版监控脚本
  Future<void> injectDomMonitor() async {
    if (controller == null || isDomMonitorInjected) return;

    try {
      // 使用增强版DOM监控脚本
      final String scriptTemplate = await SousuoParser._loadScriptFromAssets('assets/js/dom_change_monitor.js');
      final script = scriptTemplate.replaceAll('%CHANNEL_NAME%', 'AppChannel');
      await controller!.runJavaScript(script);
      isDomMonitorInjected = true;
      LogUtil.i('注入增强版DOM监听器成功');
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
    if (controller == null) return;
    try {
      final String script = await SousuoParser._loadScriptFromAssets('assets/js/fingerprint_randomization.js');
      await controller!.runJavaScript(script);
      LogUtil.i('注入指纹随机化脚本成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入指纹随机化脚本失败', e, stackTrace);
    }
  }

  /// 处理页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('中断导航', completeWithError: false)) return;

    if (pageUrl != 'about:blank' && searchState[AppConstants.searchSubmitted] == false) {
      isFormDetectionInjected = false;

      String searchKeyword = searchState[AppConstants.searchKeyword] ?? '';
      if (searchKeyword.isEmpty) {
        LogUtil.i('搜索关键词为空，尝试从URL获取');
        try {
          final uri = Uri.parse(pageUrl);
          searchKeyword = uri.queryParameters['clickText'] ?? '';
        } catch (e) {
          LogUtil.e('从URL解析搜索关键词失败: $e');
        }
      }

      LogUtil.i('页面开始加载，并行注入脚本');
      await Future.wait([
        injectFingerprintRandomization(),
        injectFormDetectionScript(searchKeyword)
      ].map((future) => future.catchError((e) {
        LogUtil.e('脚本注入失败: $e');
        return null;
      })));
      LogUtil.i('脚本注入完成');
    } else if (searchState[AppConstants.searchSubmitted] == true) {
      LogUtil.i('搜索结果页面开始加载，并行注入脚本');
      isFormDetectionInjected = false;
      isDomMonitorInjected = false;

      await Future.wait([
        injectFingerprintRandomization(),
        injectDomMonitor()
      ].map((future) => future.catchError((e) {
        LogUtil.e('脚本注入失败: $e');
        return null;
      })));
      LogUtil.i('DOM监听器和指纹随机化注入完成');
    }

    if (searchState[AppConstants.engineSwitched] == true && SousuoParser._isPrimaryEngine(pageUrl) && controller != null) {
      try {
        await controller!.loadHtmlString('<html><body></body></html>');
      } catch (e) {
        LogUtil.e('中断主引擎加载时出错: $e');
      }
      return;
    }
  }

  /// 处理页面加载完成 - 修改备用定时器逻辑
  Future<void> handlePageFinished(String pageUrl) async {
    if (_checkCancelledAndHandle('不处理页面完成事件', completeWithError: false)) return;

    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastPageFinishedTime.containsKey(pageUrl)) {
      int lastTime = _lastPageFinishedTime[pageUrl]!;
      if (currentTimeMs - lastTime < AppConstants.contentChangeDebounceMs) {
        LogUtil.i('忽略短时间内重复的页面完成事件: $pageUrl');
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

    if (searchState[AppConstants.engineSwitched] == true && isPrimaryEngine) {
      return;
    }

    if (isPrimaryEngine) {
      searchState[AppConstants.activeEngine] = 'primary';
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) {
      searchState[AppConstants.activeEngine] = 'backup';
      LogUtil.i('备用引擎页面加载完成');
    }

    if (searchState[AppConstants.searchSubmitted] == true) {
      if (!isExtractionInProgress && !isTestingStarted && !isCollectionFinished) {
        if (_checkCancelledAndHandle('不执行延迟内容变化处理', completeWithError: false)) return;

        _timerManager.set(
          'delayedContentChange',
          Duration(seconds: AppConstants.waitSeconds),
          () {
            LogUtil.i('备用定时器触发（DOM监听器可能未及时响应）');
            // 增强回调内的状态检查
            if (controller != null && !completer.isCompleted && 
                !cancelToken!.isCancelled && !isCollectionFinished && 
                !isTestingStarted && !isExtractionInProgress) {
              handleContentChange();
            } else {
              LogUtil.i('备用定时器检查失败，跳过处理');
            }
          },
        );
      }
    }
  }

  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (_checkCancelledAndHandle('不处理资源错误', completeWithError: false)) return;

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
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
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
    if (_checkCancelledAndHandle('阻止所有导航', completeWithError: false)) {
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
      LogUtil.i('阻止加载非必要资源: ${request.url}');
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  /// 处理JavaScript消息 - 修改添加CONTENT_READY消息处理
  Future<void> handleJavaScriptMessage(JavaScriptMessage message) async {
    if (_checkCancelledAndHandle('不处理JS消息', completeWithError: false)) return;

    LogUtil.i('收到消息: ${message.message}');

    if (controller == null) {
      LogUtil.e('控制器为空，无法处理消息');
      return;
    }

    // 添加对CONTENT_READY和CONTENT_CHANGED消息的统一处理
    if (message.message == 'CONTENT_READY' || message.message == 'CONTENT_CHANGED') {
      LogUtil.i('收到内容变化或就绪通知，触发内容处理');
      handleContentChange();
      return;
    }

    if (message.message == 'FORM_SUBMITTED') {
      searchState[AppConstants.searchSubmitted] = true;
      searchState[AppConstants.stage] = ParseStage.searchResults;
      searchState[AppConstants.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('表单已提交，准备处理结果');
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      if (_shouldSwitchEngine()) {
        LogUtil.i('当前引擎表单处理失败，切换到另一个引擎');
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
      LogUtil.i('用户交互消息: ${message.message}');
    } else {
      // 添加处理未知类型消息的分支，确保所有消息都被记录
      LogUtil.i('收到未知类型消息: ${message.message}');
    }
  }

  /// 开始解析流程
  Future<String> startParsing(String url) async {
    try {
      // 修改：在开始时明确检查取消状态
      if (_isCancelled()) {
        LogUtil.i('任务已被取消，立即返回ERROR');
        return 'ERROR';
      }

      setupCancelListener();
      setupGlobalTimeout();

      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];

      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }

      searchState[AppConstants.searchKeyword] = searchKeyword;

      controller = await WebViewPool.acquire();

      final fingerprintScript = await SousuoParser._loadScriptFromAssets('assets/js/fingerprint_randomization.js');
      final formScriptTemplate = await SousuoParser._loadScriptFromAssets('assets/js/form_detection.js');
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      final formScript = formScriptTemplate.replaceAll('%SEARCH_KEYWORD%', escapedKeyword);

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
        LogUtil.i('加载引擎: ${searchState[AppConstants.activeEngine]}, URL: $engineUrl');
        await controller!.loadRequest(Uri.parse(engineUrl));
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e');
        if (searchState[AppConstants.engineSwitched] == false) {
          LogUtil.i('引擎加载失败，准备切换到另一个引擎');
          await switchToBackupEngine();
        }
      }

      final result = await completer.future;
      
      // 修改：仅在非取消状态下执行收尾工作
      if (!_isCancelled() && !isResourceCleaned) {
        final String usedEngine = searchState[AppConstants.activeEngine] as String;
        SousuoParser._updateLastUsedEngine(usedEngine);
        int endTimeMs = DateTime.now().millisecondsSinceEpoch;
        int startMs = searchState[AppConstants.startTimeMs] as int;
        LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
      }

      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);

      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
        try {
          _sortStreamsByPriority();
          final result = await _testStreamsWithConcurrencyControl(foundStreams, cancelToken ?? CancelToken());
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          return result;
        } catch (testError) {
          LogUtil.e('测试流时出错: $testError');
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
  final List<CancelToken> _tokens;
  final List<StreamSubscription> _subscriptions = [];

  CancelTokenMerger(this._tokens) {
    for (final token in _tokens) {
      if (token.isCancelled) {
        if (!isCancelled) {
          cancel('组件token已取消');
        }
        break;
      }

      final subscription = token.whenCancel.then((_) {
        if (!isCancelled) {
          LogUtil.i('组件token取消，触发合并token取消');
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
      if (!token.isCancelled) {
        token.cancel(reason);
      }
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
  static final Map<String, String> _scriptCache = {};       /// 脚本缓存
  static final Map<String, String> _hostKeyCache = {};      /// 主机键缓存
  static const int _maxHostKeyCacheSize = 100;             /// 主机键缓存最大大小
  
  // 添加防止重复搜索的映射
  static final Map<String, Completer<String?>> _searchCompleters = {};

  /// 初始化WebView池和预加载脚本
  static Future<void> initialize() async {
    await WebViewPool.initialize();
    await _preloadScripts();
  }

  /// 预加载所有脚本
  static Future<void> _preloadScripts() async {
    try {
      LogUtil.i('开始预加载脚本...');
      await Future.wait([
        _loadScriptFromAssets('assets/js/form_detection.js'),
        _loadScriptFromAssets('assets/js/fingerprint_randomization.js'),
        _loadScriptFromAssets('assets/js/dom_change_monitor.js'), // 修改为预加载增强版DOM监控脚本
      ]);
      LogUtil.i('脚本预加载完成');
    } catch (e) {
      LogUtil.e('脚本预加载失败: $e');
    }
  }

  /// 从assets加载JS脚本
  static Future<String> _loadScriptFromAssets(String filePath) async {
    if (_scriptCache.containsKey(filePath)) {
      return _scriptCache[filePath]!;
    }

    try {
      final script = await rootBundle.loadString(filePath);
      _scriptCache[filePath] = script;
      return script;
    } catch (e, stackTrace) {
      LogUtil.logError('加载脚本文件失败: $filePath', e, stackTrace);
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
    } catch (e) {
      LogUtil.e('清理WebView出错: $e');
    }
  }

  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) => url.contains('tonkiang.us');

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) => url.contains('foodieguide.com');

  /// 注入DOM变化监听器 - 修改为使用增强版监控脚本
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      final String scriptTemplate = await _loadScriptFromAssets('assets/js/dom_change_monitor.js');
      final script = scriptTemplate.replaceAll('%CHANNEL_NAME%', channelName);
      await controller.runJavaScript(script);
      LogUtil.i('注入增强版DOM监听器成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace);
    }
  }

  /// 清理HTML字符串
  static String _cleanHtmlString(String htmlContent) {
    final int length = htmlContent.length;
    if (length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) {
      return htmlContent;
    }

    final buffer = StringBuffer();
    final innerContent = htmlContent.substring(1, length - 1);

    int i = 0;
    final int contentLength = innerContent.length;

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
        while (i < contentLength && (i >= contentLength - 1 || innerContent[i] != '\\')) {
          i++;
        }
        if (i > start) {
          buffer.write(innerContent.substring(start, i));
        }
      }
    }

    return buffer.toString();
  }

  /// 获取主机键值，使用缓存
  static String _getHostKey(String url) {
    if (_hostKeyCache.containsKey(url)) {
      return _hostKeyCache[url]!;
    }

    try {
      final uri = Uri.parse(url);
      final String hostKey = '${uri.host}:${uri.port}';

      if (_hostKeyCache.length >= _maxHostKeyCacheSize) {
        _hostKeyCache.remove(_hostKeyCache.keys.first);
      }
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
    const m3u8Suffix = '.m3u8';
    const m3u8Query = '.m3u8?';

    for (final rawUrl in urls) {
      if (rawUrl == null || rawUrl.isEmpty) continue;

      final String mediaUrl = rawUrl
          .trim()
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp("[\")'&;]+\$"), '');

      if (mediaUrl.isEmpty || _isUrlBlocked(mediaUrl)) continue;

      try {
        final String hostKey = _getHostKey(mediaUrl);
        if (hostMap.containsKey(hostKey)) continue;

        hostMap[hostKey] = true;

        final String lowerUrl = mediaUrl.toLowerCase();
        final bool isM3u8 = lowerUrl.endsWith(m3u8Suffix) ||
            lowerUrl.contains(m3u8Query) ||
            _m3u8Regex.hasMatch(mediaUrl);

        if (isM3u8) {
          m3u8Links.add(mediaUrl);
        } else {
          otherLinks.add(mediaUrl);
        }
      } catch (e) {
        LogUtil.e('处理URL出错: $e, URL: $mediaUrl');
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
      final int contentLength = htmlContent.length;
      LogUtil.i('获取HTML，长度: $contentLength');

      if (lastProcessedLength > 0) {
        if (contentLength <= lastProcessedLength) {
          LogUtil.i('内容长度未增加，跳过提取');
          return;
        }
        htmlContent = htmlContent.substring(lastProcessedLength);
        LogUtil.i('增量处理HTML，新增部分长度: ${htmlContent.length}');
      }

      final matches = _mediaLinkRegex.allMatches(htmlContent);
      final int totalMatches = matches.length;

      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(2)}');
      }

      final Set<String> m3u8Links = {};
      final Set<String> otherLinks = {};
      final Map<String, bool> hostMap = urlCache ?? {};

      if (urlCache == null && foundStreams.isNotEmpty) {
        for (final url in foundStreams) {
          try {
            final String hostKey = _getHostKey(url);
            hostMap[hostKey] = true;
          } catch (_) {
            hostMap[url] = true;
          }
        }
      }

      final extractedUrls = <String?>[];
      for (final match in matches) {
        if (match.groupCount >= 2) {
          extractedUrls.add(match.group(2)?.trim());
        }
      }

      _batchProcessUrls(extractedUrls, m3u8Links, otherLinks, hostMap);

      int addedCount = 0;
      final int remainingSlots = AppConstants.maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达到最大链接数 ${AppConstants.maxStreams}，不添加新链接');
        return;
      }

      for (final link in m3u8Links) {
        if (!foundStreams.contains(link)) {
          foundStreams.add(link);
          addedCount++;
          if (foundStreams.length >= AppConstants.maxStreams) {
            LogUtil.i('达到最大链接数 ${AppConstants.maxStreams}，m3u8链接已足够');
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
              LogUtil.i('达到最大链接数 ${AppConstants.maxStreams}');
              break;
            }
          }
        }
      }

      LogUtil.i('匹配数: $totalMatches, m3u8格式: ${m3u8Links.length}, 其他格式: ${otherLinks.length}, 新增: $addedCount');

      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > AppConstants.minValidContentLength ? AppConstants.minValidContentLength : htmlContent.length;
        String debugSample = htmlContent.substring(0, sampleLength);
        final onclickRegex = RegExp('onclick="[^"]+"', caseSensitive: false);
        final onclickMatches = onclickRegex.allMatches(htmlContent).take(3).map((m) => m.group(0)).join(', ');
        if (onclickMatches.isNotEmpty) {
          LogUtil.i('页面中的onclick样本: $onclickMatches');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取链接出错', e, stackTrace);
    }

    LogUtil.i('提取完成，链接数: ${foundStreams.length}');
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
        LogUtil.i('从缓存读取上次使用引擎: $_lastUsedEngine');
      }

      if (_lastUsedEngine != null && _lastUsedEngine!.isNotEmpty) {
        String nextEngine = (_lastUsedEngine == 'primary') ? 'backup' : 'primary';
        LogUtil.i('上次使用 $_lastUsedEngine 引擎，本次使用 $nextEngine 引擎');
        return nextEngine;
      }

      LogUtil.i('无缓存记录，默认使用主引擎');
      return 'primary';
    } catch (e) {
      LogUtil.e('获取初始引擎出错: $e');
      return 'primary';
    }
  }

  /// 更新最后使用的引擎
  static void _updateLastUsedEngine(String engine) {
    try {
      _lastUsedEngine = engine;
      SpUtil.putString('last_used_engine', engine);
      LogUtil.i('更新缓存的最后使用引擎: $engine');
    } catch (e) {
      LogUtil.e('更新引擎缓存出错: $e');
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
        LogUtil.i('缓存UR 验证成功: $url');
        return true;
      } else {
        LogUtil.i('缓存URL验证失败，从缓存中移除');
        _searchCache.getUrl(keyword, forceRemove: true);
        return false;
      }
    } catch (e) {
      LogUtil.i('缓存URL验证出错: $e，从缓存中移除');
      _searchCache.getUrl(keyword, forceRemove: true);
      return false;
    }
  }

  /// 使用初始引擎搜索 - 修改使用增强版DOM监控
  static Future<String?> _searchWithInitialEngine(String keyword, CancelToken? cancelToken) async {
    // 检查搜索请求是否已在进行中，避免重复搜索
    final normalizedKeyword = keyword.trim().toLowerCase();
    
    if (_searchCompleters.containsKey(normalizedKeyword)) {
      LogUtil.i('搜索[$normalizedKeyword]已在进行中，等待结果');
      return await _searchCompleters[normalizedKeyword]!.future;
    }
    
    final completer = Completer<String?>();
    _searchCompleters[normalizedKeyword] = completer;
    
    WebViewController? controller;
    bool isResourceCleaned = false;
    final TimerManager timerManager = TimerManager();

    Future<void> cleanupResources() async {
      if (isResourceCleaned) return;
      isResourceCleaned = true;

      timerManager.cancelAll();

      final tempController = controller;
      controller = null;

      if (tempController != null) {
        try {
          // 移除stopLoading调用，直接加载空白页
          await tempController.loadHtmlString('<html><body></body></html>').timeout(
            Duration(milliseconds: AppConstants.emptyHtmlLoadTimeoutMs),
            onTimeout: () {
              LogUtil.i('加载空页面超时');
              return;
            },
          );

          await WebViewPool.release(tempController);
        } catch (e) {
          LogUtil.e('清理WebView控制器出错: $e');
        }
      }
      
      LogUtil.i('初始引擎资源已完全清理');
    }

    try {
      if (cancelToken?.isCancelled ?? false) {
        completer.complete(null);
        _searchCompleters.remove(normalizedKeyword);
        return null;
      }

      final resultCompleter = Completer<String?>();
      timerManager.set(
        'globalTimeout',
        Duration(seconds: AppConstants.globalTimeoutSeconds),
        () {
          LogUtil.i('[初始引擎] 全局超时触发');
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(null);
          }
        },
      );

      final String searchUrl = '${AppConstants.initialEngine}${Uri.encodeComponent(keyword)}';
      LogUtil.i('使用初始引擎搜索: $searchUrl');

      controller = await WebViewPool.acquire();
      if (controller == null) {
        LogUtil.e('无法获取WebView控制器');
        timerManager.cancel('globalTimeout');
        completer.complete(null);
        _searchCompleters.remove(normalizedKeyword);
        return null;
      }

      final nonNullController = controller!;
      final pageLoadCompleter = Completer<String>();
      bool contentReadyProcessed = false;

      // 处理JavaScript消息
      await nonNullController.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('初始引擎收到消息: ${message.message}');
          
          // 处理内容就绪和内容变化消息
          if ((message.message == 'CONTENT_READY' || message.message == 'CONTENT_CHANGED') && !contentReadyProcessed) {
            contentReadyProcessed = true;
            LogUtil.i('初始引擎内容已准备就绪');
            if (!pageLoadCompleter.isCompleted) {
              pageLoadCompleter.complete(searchUrl);
            }
          } else {
            // 记录其他类型的消息
            LogUtil.i('初始引擎收到其他类型消息: ${message.message}');
          }
        },
      );

      await nonNullController.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (String url) {
          if (url == 'about:blank') {
            LogUtil.i('初始引擎页面加载完成: about:blank (忽略)');
            return;
          }

          if (!pageLoadCompleter.isCompleted && !contentReadyProcessed) {
            LogUtil.i('初始引擎页面加载完成: $url');
            pageLoadCompleter.complete(url);
          }
        },
        onWebResourceError: (WebResourceError error) {
          LogUtil.e('初始引擎资源错误: ${error.description}');
        },
      ));

      await nonNullController.loadRequest(Uri.parse(searchUrl));
      
      // 注入增强版DOM监控脚本
      Timer(Duration(milliseconds: 300), () async {
        if (cancelToken?.isCancelled ?? false || pageLoadCompleter.isCompleted) return;
        
        try {
          final String scriptTemplate = await _loadScriptFromAssets('assets/js/dom_change_monitor.js');
          final script = scriptTemplate.replaceAll('%CHANNEL_NAME%', 'AppChannel');
          await nonNullController.runJavaScript(script);
          LogUtil.i('向初始引擎注入增强版DOM监控脚本成功');
        } catch (e) {
          LogUtil.e('初始引擎脚本注入失败: $e');
        }
      });

      String loadedUrl;
      try {
        loadedUrl = await pageLoadCompleter.future;
      } catch (e) {
        LogUtil.e('初始引擎页面加载失败: $e');
        await cleanupResources();
        completer.complete(null);
        _searchCompleters.remove(normalizedKeyword);
        return null;
      }

      // 减少额外等待时间，从2秒降低到1秒
      await Future.delayed(Duration(seconds: 1));

      String html;
      try {
        final result = await nonNullController.runJavaScriptReturningResult('document.documentElement.outerHTML');
        html = _cleanHtmlString(result.toString());
        // 预处理HTML内容，处理Unicode转义字符
        html = html.replaceAll('\\u003C', '<').replaceAll('\\u003E', '>');
        LogUtil.i('初始引擎HTML长度: ${html.length}');
      } catch (e) {
        LogUtil.e('获取HTML内容失败: $e');
        await cleanupResources();
        completer.complete(null);
        _searchCompleters.remove(normalizedKeyword);
        return null;
      }

      final List<String> extractedUrls = [];
      // 更新正则表达式，处理Unicode转义字符
      final RegExp linkRegex = RegExp(
        r'(?:<|\\u003C)span\s+class="decrypted-link"(?:>|\\u003E)\s*(http[^<\\]+?)(?:<|\\u003C)/span',
        caseSensitive: false,
      );
      final matches = linkRegex.allMatches(html);

      for (final match in matches) {
        if (match.groupCount >= 1) {
          final String? url = match.group(1)?.trim();
          if (url != null && url.isNotEmpty && !_isUrlBlocked(url)) {
            extractedUrls.add(url);
            if (extractedUrls.length >= AppConstants.maxStreams) {
              break;
            }
          }
        }
      }

      await cleanupResources();

      LogUtil.i('从初始引擎提取到 ${extractedUrls.length} 个链接');

      if (extractedUrls.isEmpty) {
        LogUtil.i('初始引擎未找到有效链接');
        completer.complete(null);
        _searchCompleters.remove(normalizedKeyword);
        return null;
      }

      final testSession = _ParserSession(cancelToken: cancelToken);
      testSession.foundStreams.addAll(extractedUrls);

      LogUtil.i('测试初始引擎提取的 ${extractedUrls.length} 个链接');
      final result = await testSession._testStreamsWithConcurrencyControl(extractedUrls, cancelToken ?? CancelToken());

      timerManager.cancel('globalTimeout');
      final finalResult = result == 'ERROR' ? null : result;
      
      completer.complete(finalResult);
      _searchCompleters.remove(normalizedKeyword);
      return finalResult;
    } catch (e, stackTrace) {
      LogUtil.logError('初始引擎WebView搜索失败', e, stackTrace);
      if (!isResourceCleaned) {
        await cleanupResources();
      }
      completer.completeError(e);
      _searchCompleters.remove(normalizedKeyword);
      return null;
    } finally {
      // 确保无论如何都完成资源清理
      if (!isResourceCleaned) {
        await cleanupResources();
      }
      
      // 确保completer被完成
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      
      // 移除搜索映射
      _searchCompleters.remove(normalizedKeyword);
    }
  }

  /// 解析搜索页面并提取媒体流地址 - 修改的方法
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    // 使用传入的cancelToken或创建一个新的
    final effectiveCancelToken = cancelToken ?? CancelToken();
    
    Timer? globalTimer = Timer(Duration(seconds: AppConstants.globalTimeoutSeconds), () {
      if (!effectiveCancelToken.isCancelled) {
        LogUtil.i('全局超时触发，取消所有操作');
        effectiveCancelToken.cancel('全局超时');
      }
    });

    try {
      if (blockKeywords.isNotEmpty) {
        setBlockKeywords(blockKeywords);
      }

      String? searchKeyword;
      try {
        final uri = Uri.parse(url);
        searchKeyword = uri.queryParameters['clickText'];
      } catch (e) {
        LogUtil.e('提取搜索关键词失败: $e');
      }

      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无法获取搜索关键词');
        return 'ERROR';
      }

      final cachedUrl = _searchCache.getUrl(searchKeyword);
      if (cachedUrl != null) {
        LogUtil.i('从缓存获取结果: $searchKeyword -> $cachedUrl');
        bool isValid = await _validateCachedUrl(searchKeyword, cachedUrl, effectiveCancelToken);
        if (isValid) {
          return cachedUrl;
        } else {
          LogUtil.i('缓存URL失效，执行新搜索');
        }
      }

      LogUtil.i('尝试使用初始引擎搜索: $searchKeyword');
      final initialEngineResult = await _searchWithInitialEngine(searchKeyword, effectiveCancelToken);

      if (initialEngineResult != null) {
        LogUtil.i('初始引擎搜索成功: $initialEngineResult');
        _searchCache.addUrl(searchKeyword, initialEngineResult);
        return initialEngineResult;
      }

      LogUtil.i('初始引擎搜索失败，回退到标准解析流程');

      // 修改：检查Token状态，避免启动已被取消的标准解析流程
      if (effectiveCancelToken.isCancelled) {
        LogUtil.i('检测到取消状态，不执行标准解析流程，原因: ${effectiveCancelToken.cancelError}');
        return 'ERROR';
      }

      String initialEngine = _getInitialEngine();
      final session = _ParserSession(cancelToken: effectiveCancelToken, initialEngine: initialEngine);
      final result = await session.startParsing(url);

      if (result != 'ERROR' && searchKeyword.isNotEmpty) {
        _searchCache.addUrl(searchKeyword, result);
      }

      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析过程中发生异常', e, stackTrace);
      return 'ERROR';
    } finally {
      globalTimer?.cancel();
      globalTimer = null;
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    await WebViewPool.clear();
    _searchCache.dispose();
    _scriptCache.clear();
    _hostKeyCache.clear();
  }
}
