import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:math' show min;
import 'package:sp_util/sp_util.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 解析阶段枚举
enum ParseStage {
  formSubmission,  /// 页面加载与表单提交
  searchResults,   /// 搜索结果处理与流测试
  completed,       /// 解析完成
  error            /// 解析错误
}

/// 应用常量类，集中管理所有常量
class AppConstants {
  AppConstants._(); /// 私有构造函数，防止实例化

  /// 状态键常量
  static const String searchKeyword = 'searchKeyword';              /// 搜索关键词
  static const String activeEngine = 'activeEngine';               /// 当前搜索引擎
  static const String searchSubmitted = 'searchSubmitted';         /// 表单提交状态
  static const String startTimeMs = 'startTimeMs';                 /// 解析开始时间
  static const String engineSwitched = 'engineSwitched';           /// 引擎切换状态
  static const String primaryEngineLoadFailed = 'primaryEngineLoadFailed'; /// 主引擎加载失败
  static const String lastHtmlLength = 'lastHtmlLength';           /// 上次HTML长度
  static const String extractionCount = 'extractionCount';         /// 提取次数
  static const String stage = 'stage';                             /// 当前解析阶段
  static const String stage1StartTime = 'stage1StartTime';         /// 阶段1开始时间
  static const String stage2StartTime = 'stage2StartTime';         /// 阶段2开始时间

  /// 搜索引擎URL
  static const String primaryEngine = 'https://tonkiang.us/?';     /// 主搜索引擎URL
  static const String backupEngine = 'http://www.foodieguide.com/iptvsearch/'; /// 备用搜索引擎URL

  /// 超时与等待时间
  static const int globalTimeoutSeconds = 30;                      /// 全局超时（秒）
  static const int waitSeconds = 2;                                /// 页面加载与提交等待（秒）
  static const int noMoreChangesSeconds = 2;                       /// 无变化检测（秒）
  static const int domChangeWaitMs = 300;                          /// DOM变化等待（毫秒）
  static const int contentChangeDebounceMs = 300;                  /// 内容变化防抖（毫秒）
  static const int flowTestWaitMs = 200;                           /// 流测试等待（毫秒）
  static const int backupEngineLoadWaitMs = 200;                   /// 切换备用引擎等待（毫秒）
  static const int cleanupRetryWaitMs = 200;                       /// 清理重试等待（毫秒）
  static const int cancelListenerTimeoutMs = 500;                  /// 取消监听器超时（毫秒）
  static const int emptyHtmlLoadTimeoutMs = 300;                   /// 空HTML加载超时（毫秒）
  static const int webViewCleanupDelayMs = 200;                    /// WebView清理延迟（毫秒）
  static const int webViewCleanupTimeoutMs = 500;                  /// WebView清理超时（毫秒）
  static const int formCheckIntervalMs = 500;                      /// 表单检查间隔（毫秒）
  static const int mouseMovementDelayMs = 30;                      /// 鼠标移动延迟（毫秒）
  static const int mouseHoverTimeMs = 100;                         /// 鼠标悬停时间（毫秒）
  static const int mousePressTimeMs = 200;                         /// 鼠标按压时间（毫秒）
  static const int actionDelayMs = 300;                            /// 操作间隔（毫秒）

  /// 限制与阈值
  static const int maxStreams = 8;                                 /// 最大媒体流数量
  static const int maxConcurrentTests = 8;                         /// 最大并发测试数
  static const int minValidContentLength = 1000;                   /// 最小有效内容长度
  static const double significantChangePercent = 5.0;              /// 显著内容变化百分比
  static const int mouseMovementSteps = 6;                         /// 鼠标移动步数
  static const int mouseMovementOffset = 10;                       /// 鼠标移动偏移量
  static const int maxSearchCacheEntries = 58;                     /// 搜索缓存最大条目数

  /// 流测试参数
  static const int streamCompareTimeWindowMs = 3000;               /// 流响应时间窗口（毫秒）
  static const int streamFastEnoughThresholdMs = 500;              /// 流快速响应阈值（毫秒）
  static const int streamTestOverallTimeoutSeconds = 6;            /// 流测试整体超时（秒）

  /// 屏蔽关键词
  static const List<String> defaultBlockKeywords = ["freetv.fun", "epg.pw", "ktpremium.com"]; /// 默认屏蔽关键词
}

/// 缓存条目类，存储URL
class _CacheEntry {
  final String url;

  _CacheEntry(this.url); /// 构造函数，初始化URL

  /// 转换为JSON用于序列化
  Map<String, dynamic> toJson() => {
    'url': url,
  };

  /// 从JSON创建实例
  factory _CacheEntry.fromJson(Map<String, dynamic> json) {
    return _CacheEntry(json['url'] as String);
  }
}

/// 定时器管理类，统一管理定时器
class TimerManager {
  final Map<String, Timer> _timers = {};
  bool _isDisposed = false;

  /// 创建或替换定时器
  Timer set(String key, Duration duration, Function() callback) {
    if (_isDisposed) {
      LogUtil.w('TimerManager已释放，忽略定时器创建: $key');
      return Timer(Duration.zero, () {});
    }

    cancel(key);

    try {
      final timer = Timer(duration, () {
        try {
          _timers.remove(key);
          callback();
        } catch (e) {
          LogUtil.e('定时器回调执行错误($key): $e');
        }
      });

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
      LogUtil.w('TimerManager已释放，忽略周期定时器创建: $key');
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
  bool exists(String key) {
    return _timers.containsKey(key);
  }

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
  static final List<WebViewController> _pool = [];
  static const int maxPoolSize = 2; /// 最大池大小
  static final Completer<void> _initCompleter = Completer<void>();
  static bool _isInitialized = false;

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

      if (_pool.length < maxPoolSize) {
        _pool.add(controller);
        LogUtil.i('WebView实例返回池，当前池大小: ${_pool.length}');
      } else {
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
  static const String _lruKey = 'search_cache_lru';    /// LRU顺序键

  final int maxEntries;
  final Map<String, _CacheEntry> _cache = LinkedHashMap<String, _CacheEntry>();
  bool _isDirty = false;
  Timer? _persistTimer;

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

      LogUtil.i('保存了 ${data.length} 个缓存条目到持久化存储');
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

/// 解析会话类 - 处理解析逻辑和状态管理
class _ParserSession {
  final Completer<String> completer = Completer<String>(); // 异步任务完成器
  final List<String> foundStreams = []; // 发现的流地址
  WebViewController? controller; // WebView控制器
  
  // 使用TimerManager替代散落的定时器
  final TimerManager _timerManager = TimerManager();
  
  // 状态标记
  bool isResourceCleaned = false; // 资源清理状态
  bool isTestingStarted = false; // 流测试开始状态
  bool isExtractionInProgress = false; // 提取进行中状态
  
  // 收集完成检测
  bool isCollectionFinished = false; // 收集完成状态
  
  // 状态对象
  final Map<String, dynamic> searchState = {
    AppConstants.searchKeyword: '', // 初始化搜索关键词
    AppConstants.activeEngine: 'primary', // 默认主引擎
    AppConstants.searchSubmitted: false, // 表单未提交
    AppConstants.startTimeMs: DateTime.now().millisecondsSinceEpoch,
    AppConstants.engineSwitched: false, // 未切换引擎
    AppConstants.primaryEngineLoadFailed: false, // 主引擎未失败
    AppConstants.lastHtmlLength: 0, // 初始HTML长度
    AppConstants.extractionCount: 0, // 初始提取次数
    AppConstants.stage: ParseStage.formSubmission, // 初始阶段
    AppConstants.stage1StartTime: DateTime.now().millisecondsSinceEpoch, // 阶段1开始
    AppConstants.stage2StartTime: 0, // 阶段2未开始
  };
  
  // 取消监听
  StreamSubscription? cancelListener; // 取消事件监听器
  
  // 取消令牌
  final CancelToken? cancelToken; // 任务取消令牌

  // 添加资源清理锁，防止并发清理
  bool _isCleaningUp = false; // 资源清理锁
  
  // URL缓存，用于快速查找
  final Map<String, bool> _urlCache = {}; // URL去重缓存
  
  // 流比较完成标志 - 从局部变量升级为类属性
  bool isCompareDone = false; // 是否已完成比较
  
  // 构造函数，修改为接受初始引擎
  _ParserSession({this.cancelToken, String? initialEngine}) {
    // 如果指定了初始引擎，则使用它
    if (initialEngine != null) {
      searchState[AppConstants.activeEngine] = initialEngine;
    }
  }
  
  /// 统一的取消检查方法
  bool _checkCancelledAndHandle(String context, {bool completeWithError = true}) {
    if (cancelToken?.isCancelled ?? false) { // 检查任务是否取消
      if (completeWithError && !completer.isCompleted) { // 若需错误完成
        completer.complete('ERROR'); // 标记任务错误
        cleanupResources(); // 清理资源
      }
      return true; // 返回取消状态
    }
    return false; // 未取消
  }
  
  /// 改进的流选择方法
  void _selectBestStream(Map<String, int> streams, Completer<String> completer, CancelToken token) {
    if (isCompareDone || completer.isCompleted) return;
    isCompareDone = true;
    
    // 找出响应最快的流
    String selectedStream = '';
    int bestTime = 999999;
    
    streams.forEach((stream, time) {
      if (time < bestTime) {
        bestTime = time;
        selectedStream = stream;
      }
    });
    
    if (selectedStream.isEmpty) return;
    
    // 标记选择原因
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
    if (cancelToken != null) { // 检查取消令牌存在
      try {
        // 立即检查当前状态
        if (cancelToken!.isCancelled && !isResourceCleaned) { // 若已取消且未清理
          LogUtil.i('检测到cancelToken已是取消状态，立即清理资源');
          cleanupResources(immediate: true); // 立即清理
          return;
        }
        
        // 设置取消监听
        cancelListener = cancelToken!.whenCancel.then((_) { // 监听取消事件
          LogUtil.i('检测到取消信号，立即释放所有资源');
          if (!isResourceCleaned) { // 若未清理
            cleanupResources(immediate: true); // 立即清理
          }
        }).asStream().listen((_) {}); // 转为流并监听
      } catch (e) {
        LogUtil.e('设置取消监听器出错: $e');
      }
    }
  }

  /// 设置全局超时
  void setupGlobalTimeout() {
    _timerManager.set(
      'globalTimeout', 
      Duration(seconds: AppConstants.globalTimeoutSeconds), // 超时时间
      () {
        if (_checkCancelledAndHandle('不处理全局超时')) return; // 检查取消
        
        // 检查收集状态
        if (!isCollectionFinished && foundStreams.isNotEmpty) { // 若未完成且有流
          LogUtil.i('全局超时触发，强制结束收集，开始测试 ${foundStreams.length} 个流');
          finishCollectionAndTest(); // 结束收集并测试
        }
        // 检查引擎状态
        else if (_shouldSwitchEngine()) { // 主引擎未切换
          LogUtil.i('全局超时触发，主引擎未找到流，切换备用引擎');
          switchToBackupEngine(); // 切换备用引擎
        } 
        // 无可用流，返回错误
        else {
          LogUtil.i('全局超时触发，无可用流');
          if (!completer.isCompleted) { // 若未完成
            completer.complete('ERROR'); 
            cleanupResources(); // 清理资源
          }
        }
      }
    );
  }
  
  /// 完成收集并开始测试
  void finishCollectionAndTest() {
    if (_checkCancelledAndHandle('不执行收集完成', completeWithError: false)) return; // 检查取消
    
    if (isCollectionFinished || isTestingStarted) { // 若已完成或测试开始
      return; // 跳过
    }
    
    isCollectionFinished = true; // 标记收集完成
    
    // 取消无变化检测定时器
    _timerManager.cancel('noMoreChanges');
    
    // 开始测试
    startStreamTesting(); // 启动流测试
  }
  
  /// 设置无更多变化的检测计时器
  void setupNoMoreChangesDetection() {
    _timerManager.set(
      'noMoreChanges',
      Duration(seconds: AppConstants.noMoreChangesSeconds), // 3秒无变化
      () {
        if (_checkCancelledAndHandle('不执行无变化检测', completeWithError: false)) return; // 检查取消
        
        if (!isCollectionFinished && foundStreams.isNotEmpty) { // 若未完成且有流
          finishCollectionAndTest(); // 结束收集并测试
        }
      }
    );
  }
  
  /// 改进的资源清理
  Future<void> cleanupResources({bool immediate = false}) async {
    if (_isCleaningUp || isResourceCleaned) { // 检查清理状态
      LogUtil.i('资源已清理或正在清理中，跳过');
      return;
    }
    
    _isCleaningUp = true; // 标记清理中
    
    try {
      isResourceCleaned = true; // 标记资源已清理
      
      // 清理计时器
      _timerManager.cancelAll();
      
      // 清理监听器
      if (cancelListener != null) { // 检查监听器存在
        try {
          await cancelListener!.cancel().timeout(
            Duration(milliseconds: AppConstants.cancelListenerTimeoutMs), 
            onTimeout: () {
              LogUtil.i('取消监听器超时');
              return;
            }
          );
          LogUtil.i('取消监听器已清理');
        } catch (e) {
          LogUtil.e('取消监听器时出错: $e');
        } finally {
          cancelListener = null; // 清空引用
        }
      }
      
      // 清理WebView
      final tempController = controller; // 临时引用
      controller = null; // 清空引用
      
      if (tempController != null) { // 检查控制器存在
        try {
          await tempController.loadHtmlString('<html><body></body></html>') // 加载空页面
            .timeout(Duration(milliseconds: AppConstants.emptyHtmlLoadTimeoutMs), onTimeout: () {
              LogUtil.i('加载空页面超时');
              return;
            });
          
          // 使用WebView池回收控制器
          if (!immediate) { // 非立即清理
            await WebViewPool.release(tempController);
          }
        } catch (e) {
          LogUtil.e('清理WebView控制器出错: $e');
        }
      }
      
      // 处理未完成的Completer
      if (!completer.isCompleted) { // 若未完成
        completer.complete('ERROR'); 
      }
      
      _urlCache.clear(); // 清空URL缓存
    } catch (e) {
      LogUtil.e('资源清理过程中出错: $e');
    } finally {
      _isCleaningUp = false; // 重置清理标志
      LogUtil.i('所有资源清理完成');
    }
  }
  
  /// 异步操作执行方法 - 统一错误处理模式
  Future<void> _executeAsyncOperation(
    String operationName,
    Future<void> Function() operation,
    {Function? onError}
  ) async {
    try {
      if (_checkCancelledAndHandle('不执行$operationName', completeWithError: false)) return; // 检查取消
      await operation(); // 执行操作
    } catch (e) {
      LogUtil.e('$operationName 出错: $e');
      if (onError != null) { // 若有错误处理
        onError(); // 执行错误处理
      } else if (!completer.isCompleted) { // 若未完成
        completer.complete('ERROR'); 
        cleanupResources(); // 清理资源
      }
    }
  }
  
  /// 改进的流测试方法
Future<bool> _testSingleStream(
  String streamUrl, 
  Map<String, int> successfulStreams, 
  Set<String> inProgressTests, 
  CancelToken cancelToken, 
  Completer<String> resultCompleter
) async {
  if (resultCompleter.isCompleted || cancelToken.isCancelled) {
    return false;
  }
  
  inProgressTests.add(streamUrl);
  try {
    // 直接执行GET请求测试
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
      // 检查响应内容有效性
      bool isValidContent = true;
      if (response.data is List<int> && response.data.length > 0) {
        final contentBytes = response.data as List<int>;
        
        // 检查m3u8文件有效性
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
        
        // 记录成功的流
        successfulStreams[streamUrl] = testTime;
        
        // 如果响应时间小于阈值，立即返回
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
  
  /// 处理所有测试完成的检查（从嵌套函数提取）
  void _handleAllTestsComplete(
    Set<String> inProgressTests,
    List<String> pendingStreams,
    Map<String, int> successfulStreams,
    bool isCompareWindowStarted,
    Completer<String> resultCompleter,
    CancelToken cancelToken
  ) {
    if (inProgressTests.isEmpty && pendingStreams.isEmpty && !resultCompleter.isCompleted) {
      // 如果没有成功流，直接返回ERROR
      if (successfulStreams.isEmpty) {
        LogUtil.i('所有流测试完成，均失败，返回ERROR');
        resultCompleter.complete('ERROR');
      }
      // 如果有成功流但比较窗口尚未结束，等待窗口
      else if (!isCompareDone && isCompareWindowStarted) {
        LogUtil.i('所有流测试完成，等待比较窗口结束后选择');
      }
      // 如果有成功流且没启动比较窗口，立即选择
      else if (!isCompareDone && !isCompareWindowStarted) {
        _selectBestStream(successfulStreams, resultCompleter, cancelToken);
      }
    }
  }
  
  /// 改进流测试策略，增加并发控制和优先级处理
  void startStreamTesting() {
    if (isTestingStarted) { // 检查测试是否开始
      LogUtil.i('已经开始测试流链接，忽略重复测试请求');
      return;
    }
    
    if (_checkCancelledAndHandle('不执行流测试', completeWithError: false)) return; // 检查取消
    
    if (foundStreams.isEmpty) { // 检查是否有流
      LogUtil.i('没有找到流链接，无法开始测试');
      if (!completer.isCompleted) { // 若未完成
        completer.complete('ERROR'); 
        cleanupResources(); // 清理资源
      }
      return;
    }
    
    isTestingStarted = true; // 标记测试开始
    LogUtil.i('开始测试 ${foundStreams.length} 个流链接');
    
    final testCancelToken = CancelToken(); // 创建测试取消令牌
    
    // 监听父级cancelToken的取消事件
    StreamSubscription? testCancelListener;
    if (cancelToken != null) { // 检查父级令牌
      if (cancelToken!.isCancelled && !testCancelToken.isCancelled) { // 若父级已取消
        LogUtil.i('父级cancelToken已是取消状态，立即取消测试');
        testCancelToken.cancel('父级已取消'); // 取消测试
      } else {
        testCancelListener = cancelToken!.whenCancel.then((_) { // 监听父级取消
          if (!testCancelToken.isCancelled) { // 若测试未取消
            LogUtil.i('父级cancelToken已取消，取消所有测试请求');
            testCancelToken.cancel('父级已取消'); // 取消测试
          }
        }).asStream().listen((_) {}); // 转为流并监听
      }
    }
    
    _testStreamsAsync(testCancelToken, testCancelListener); // 异步测试流
  }
  
  /// 改进流测试异步方法，增加并发控制
  Future<void> _testStreamsAsync(CancelToken testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      _sortStreamsByPriority(); // 按优先级排序流
      
      final result = await _testStreamsWithConcurrencyControl(foundStreams, testCancelToken); // 并发测试
      
      LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      if (!completer.isCompleted) { // 若未完成
        completer.complete(result); // 完成任务
        cleanupResources(); // 清理资源
      }
    } catch (e) {
      LogUtil.e('测试流过程中出错: $e');
      if (!completer.isCompleted) { // 若未完成
        completer.complete('ERROR'); 
        cleanupResources(); // 清理资源
      }
    } finally {
      try {
        await testCancelListener?.cancel(); // 取消监听器
      } catch (e) {
        LogUtil.e('取消测试监听器时出错: $e');
      }
    }
  }

  /// 带并发控制的流测试方法
  Future<String> _testStreamsWithConcurrencyControl(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR'; // 无流返回错误
    
    final int maxConcurrent = AppConstants.maxConcurrentTests; // 最大并发数
    final List<String> pendingStreams = List.from(streams); // 待测试流
    final Completer<String> resultCompleter = Completer<String>(); // 结果完成器
    final Set<String> inProgressTests = {}; // 进行中的测试
    
    // 存储成功流和响应时间
    final Map<String, int> successfulStreams = {}; // 成功的流和它们的响应时间
    bool isCompareWindowStarted = false; // 是否已启动比较窗口
    
    // 全局超时计时器
    final timeoutTimer = Timer(Duration(seconds: AppConstants.streamTestOverallTimeoutSeconds), () {
      if (!resultCompleter.isCompleted) {
        // 超时检查 - 如果有成功流，选择最快的；否则返回ERROR
        if (successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter, cancelToken);
        } else {
          LogUtil.i('流测试整体超时${AppConstants.streamTestOverallTimeoutSeconds}秒，返回ERROR');
          resultCompleter.complete('ERROR');
        }
      }
    });
    
    // 启动比较窗口
    void startCompareWindow() {
      if (!isCompareWindowStarted && !isCompareDone) {
        isCompareWindowStarted = true;
        
        Timer(Duration(milliseconds: AppConstants.streamCompareTimeWindowMs), () {
          if (!isCompareDone && !resultCompleter.isCompleted) {
            // 比较窗口结束，选择最佳流
            _selectBestStream(successfulStreams, resultCompleter, cancelToken);
          }
        });
      }
    }
    
    // 启动下一批测试
    void startNextTests() {
      if (resultCompleter.isCompleted) return;
      
      while (inProgressTests.length < maxConcurrent && pendingStreams.isNotEmpty) {
        final nextStream = pendingStreams.removeAt(0);
        _testSingleStream(
          nextStream, 
          successfulStreams, 
          inProgressTests, 
          cancelToken, 
          resultCompleter
        ).then((success) {
          if (success && !isCompareWindowStarted) {
            startCompareWindow();
          }
          
          // 检查是否所有测试都完成
          _handleAllTestsComplete(
            inProgressTests,
            pendingStreams,
            successfulStreams,
            isCompareWindowStarted,
            resultCompleter,
            cancelToken
          );
          
          startNextTests();
        });
      }
    }
    
    // 启动初始测试
    startNextTests();
    
    try {
      final result = await resultCompleter.future;
      timeoutTimer.cancel();
      return result;
    } catch (e) {
      LogUtil.e('等待流测试结果时出错: $e');
      return 'ERROR';
    } finally {
      timeoutTimer.cancel();
    }
  }
  
  /// 新增流排序方法，优先测试m3u8格式
  void _sortStreamsByPriority() {
    if (foundStreams.isEmpty) return; // 无流跳过
    
    try {
      foundStreams.sort((a, b) { // 按m3u8优先排序
        bool aIsM3u8 = a.toLowerCase().contains('.m3u8'); // 检查a是否m3u8
        bool bIsM3u8 = b.toLowerCase().contains('.m3u8'); // 检查b是否m3u8
        
        if (aIsM3u8 && !bIsM3u8) return -1; // a优先
        if (!aIsM3u8 && bIsM3u8) return 1;  // b优先
        return 0; // 保持原序
      });
    } catch (e) {
      LogUtil.e('排序流地址时出错: $e');
    }
  }
  
  /// 检查是否应该切换引擎
  bool _shouldSwitchEngine() {
    return !searchState[AppConstants.engineSwitched];
  }
  
  /// 切换到备用引擎 - 简化版本
  Future<void> switchToBackupEngine() async {
    if (searchState[AppConstants.engineSwitched] == true) { // 检查是否已切换
      LogUtil.i('已切换过引擎，忽略');
      return;
    }
    
    await _executeAsyncOperation('切换引擎', () async { // 执行切换
      final String currentEngine = searchState[AppConstants.activeEngine] as String;
      final String targetEngine = (currentEngine == 'primary') ? 'backup' : 'primary';
      final String targetUrl = (targetEngine == 'primary') ? AppConstants.primaryEngine : AppConstants.backupEngine;
      
      LogUtil.i('从 $currentEngine 引擎切换到 $targetEngine 引擎');
      
      // 更新状态
      searchState[AppConstants.activeEngine] = targetEngine; // 设置目标引擎
      searchState[AppConstants.engineSwitched] = true; // 标记已切换
      searchState[AppConstants.searchSubmitted] = false; // 重置提交状态
      searchState[AppConstants.lastHtmlLength] = 0; // 重置HTML长度
      searchState[AppConstants.extractionCount] = 0; // 重置提取次数
      searchState[AppConstants.stage] = ParseStage.formSubmission; // 重置阶段
      searchState[AppConstants.stage1StartTime] = DateTime.now().millisecondsSinceEpoch; // 重置时间
      
      isCollectionFinished = false; // 重置收集状态
      _timerManager.cancel('noMoreChanges'); // 取消无变化计时器
      _timerManager.cancel('globalTimeout'); // 取消全局计时器
      
      if (controller != null) { // 检查控制器
        await controller!.loadHtmlString('<html><body></body></html>'); // 加载空页面
        await Future.delayed(Duration(milliseconds: AppConstants.backupEngineLoadWaitMs)); // 延迟
        
        await controller!.loadRequest(Uri.parse(targetUrl)); // 加载目标引擎
        LogUtil.i('已加载 $targetEngine 引擎: $targetUrl');
        
        setupGlobalTimeout(); // 设置新的全局超时
      } else {
        LogUtil.e('WebView控制器为空，无法切换');
        throw Exception('WebView控制器为空'); // 抛出异常
      }
    });
  }
  
  /// 优化内容变化处理 - 使用定时器管理
  void handleContentChange() {
    _timerManager.cancel('contentChangeDebounce'); // 取消现有计时器
    
    if (_checkCancelledAndHandle('停止处理内容变化', completeWithError: false) || 
        isCollectionFinished || 
        isTestingStarted) { // 检查状态
      return; // 跳过
    }
    
    _timerManager.set(
      'contentChangeDebounce',
      Duration(milliseconds: AppConstants.contentChangeDebounceMs), // 防抖时间
      () async {
        if (controller == null || 
            completer.isCompleted || 
            _checkCancelledAndHandle('取消内容处理', completeWithError: false) ||
            isCollectionFinished || 
            isTestingStarted) { // 再次检查状态
          return; // 跳过
        }
        
        try {
          if (searchState[AppConstants.searchSubmitted] == true && 
              !completer.isCompleted && 
              !isTestingStarted) { // 检查提交状态
            
            // 使用try-finally确保标记重置
            bool extractionTriggered = false;
            try {
              extractionTriggered = true;
              
              int beforeExtractCount = foundStreams.length; // 提取前流数量
              bool isBackupEngine = searchState[AppConstants.activeEngine] == 'backup'; // 检查引擎
              
              // 改进提取方法，支持增量处理
              await SousuoParser._extractMediaLinks(
                controller!, 
                foundStreams, 
                isBackupEngine,
                lastProcessedLength: searchState[AppConstants.lastHtmlLength], // 最后处理长度
                urlCache: _urlCache // 传递URL缓存
              );
              
              try {
                final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length'); // 获取HTML长度
                searchState[AppConstants.lastHtmlLength] = int.tryParse(result.toString()) ?? 0; // 更新长度
              } catch (e) {
                LogUtil.e('获取HTML长度时出错: $e');
              }
              
              if (_checkCancelledAndHandle('提取后取消处理', completeWithError: false)) { // 检查取消
                return;
              }
              
              searchState[AppConstants.extractionCount] = searchState[AppConstants.extractionCount] + 1; // 增加提取次数
              int afterExtractCount = foundStreams.length; // 提取后流数量
              
              if (afterExtractCount > beforeExtractCount) { // 有新流
                LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接，当前总数: ${afterExtractCount}');
                
                setupNoMoreChangesDetection(); // 设置无变化检测
                
                if (afterExtractCount >= AppConstants.maxStreams) { // 达到最大流数
                  finishCollectionAndTest(); // 结束收集
                }
              } else if (_shouldSwitchEngine() && 
                        afterExtractCount == 0) { // 当前引擎无流
                switchToBackupEngine(); // 切换引擎
              } else { // 无新流
                if (afterExtractCount > 0) { // 若有流
                  setupNoMoreChangesDetection(); // 设置无变化检测
                }
              }
            } finally {
              // 确保标记被重置
              if (extractionTriggered) {
                extractionTriggered = false;
              }
            }
          }
        } catch (e) {
          LogUtil.e('处理内容变化时出错: $e');
        } finally {
          isExtractionInProgress = false; // 重置标记
        }
      }
    );
  }
  
  /// 预编译JavaScript脚本 - 简化版
  static const String _formDetectionScriptTemplate = '''
    (function() {
      try { 
        const FORM_CHECK_INTERVAL_MS = %FORM_CHECK_INTERVAL_MS%; 
        
        window.__formCheckState = { 
          formFound: false, 
          checkInterval: null, 
          searchKeyword: "%SEARCH_KEYWORD%", 
          lastCheckTime: Date.now(), 
          backupTimerId: null  
        };
        
        window.__humanBehaviorSimulationRunning = false;
        
        function clearAllFormCheckInterval() {
          try {
            if (window.__formCheckState.checkInterval) {
              clearInterval(window.__formCheckState.checkInterval);
              window.__formCheckState.checkInterval = null;
            }
            
            if (window.__formCheckState.backupTimerId) {
              clearTimeout(window.__formCheckState.backupTimerId);
              window.__formCheckState.backupTimerId = null;
            }
            
            try {
              if (window.__allFormIntervals) {
                window.__allFormIntervals.forEach(id => clearInterval(id));
                window.__allFormIntervals = [];
              }
            } catch (e) {}
          } catch (e) {}
        }
        
        const MOUSE_MOVEMENT_STEPS = %MOUSE_MOVEMENT_STEPS%;
        const MOUSE_MOVEMENT_OFFSET = %MOUSE_MOVEMENT_OFFSET%;
        const MOUSE_MOVEMENT_DELAY_MS = %MOUSE_MOVEMENT_DELAY_MS%;
        const MOUSE_HOVER_TIME_MS = %MOUSE_HOVER_TIME_MS%;
        const MOUSE_PRESS_TIME_MS = %MOUSE_PRESS_TIME_MS%;
        const ACTION_DELAY_MS = %ACTION_DELAY_MS%;
        
        function createMouseEvent(type, x, y, buttons) {
          return new MouseEvent(type, {
            'view': window,
            'bubbles': true,
            'cancelable': true,
            'clientX': x,
            'clientY': y,
            'buttons': buttons || 0
          });
        }
        
        function simulateHumanBehavior(searchKeyword) {
          return new Promise((resolve) => {
            if (window.__humanBehaviorSimulationRunning) {
              if (window.AppChannel) {
                window.AppChannel.postMessage("模拟真人行为已在运行中，跳过");
              }
              return resolve(false);
            }
            
            window.__humanBehaviorSimulationRunning = true;
            
            const searchInput = document.getElementById('search');
            
            if (!searchInput) {
              if (window.AppChannel) {
                window.AppChannel.postMessage("未找到搜索输入框");
              }
              window.__humanBehaviorSimulationRunning = false;
              return resolve(false);
            }
            
            let lastX = window.innerWidth / 2;
            let lastY = window.innerHeight / 2;
            
            function getInputPosition() {
              const rect = searchInput.getBoundingClientRect();
              return {
                top: rect.top,
                left: rect.left,
                right: rect.right,
                bottom: rect.bottom,
                width: rect.width,
                height: rect.height
              };
            }
            
            async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
              const steps = MOUSE_MOVEMENT_STEPS + Math.floor(Math.random() * 3);
              
              const distance = Math.sqrt(Math.pow(toX - fromX, 2) + Math.pow(toY - fromY, 2));
              const variance = distance * 0.15;
              
              const cp1x = fromX + (toX - fromX) * 0.4 + (Math.random() * 2 - 1) * variance;
              const cp1y = fromY + (toY - fromY) * 0.2 + (Math.random() * 2 - 1) * variance;
              const cp2x = fromX + (toX - fromX) * 0.8 + (Math.random() * 2 - 1) * variance;
              const cp2y = fromY + (toY - fromY) * 0.7 + (Math.random() * 2 - 1) * variance;
              
              for (let i = 0; i < steps; i++) {
                const t = i / steps;
                
                const easedT = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
                
                const bx = Math.pow(1-easedT, 3) * fromX + 
                        3 * Math.pow(1-easedT, 2) * easedT * cp1x + 
                        3 * (1-easedT) * Math.pow(easedT, 2) * cp2x + 
                        Math.pow(easedT, 3) * toX;
                        
                const by = Math.pow(1-easedT, 3) * fromY + 
                        3 * Math.pow(1-easedT, 2) * easedT * cp1y + 
                        3 * (1-easedT) * Math.pow(easedT, 2) * cp2y + 
                        Math.pow(easedT, 3) * toY;
                
                const jitterAmount = Math.max(1, distance * 0.005);
                const jitterX = (Math.random() * 2 - 1) * jitterAmount;
                const jitterY = (Math.random() * 2 - 1) * jitterAmount;
                
                const curX = bx + jitterX;
                const curY = by + jitterY;
                
                const mousemoveEvent = createMouseEvent('mousemove', curX, curY);
                
                const elementAtPoint = document.elementFromPoint(curX, curY);
                if (elementAtPoint) {
                  elementAtPoint.dispatchEvent(mousemoveEvent);
                } else {
                  document.body.dispatchEvent(mousemoveEvent);
                }
                
                const stepDelay = MOUSE_MOVEMENT_DELAY_MS * (0.8 + Math.random() * 0.4);
                await new Promise(r => setTimeout(r, stepDelay));
              }
            }
            
            async function addRandomScrolling() {
              if (Math.random() < 0.7) {
                const scrollDirection = Math.random() < 0.6 ? 1 : -1;
                const scrollAmount = Math.floor(10 + Math.random() * 100) * scrollDirection;
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("执行随机滚动: " + scrollAmount + "px");
                }
                
                const scrollSteps = 5 + Math.floor(Math.random() * 5);
                const scrollStep = scrollAmount / scrollSteps;
                
                for (let i = 0; i < scrollSteps; i++) {
                  const easedStep = Math.sin((i / scrollSteps) * Math.PI) * scrollStep;
                  window.scrollBy(0, easedStep);
                  await new Promise(r => setTimeout(r, 30 + Math.random() * 20));
                }
                
                if (Math.random() < 0.4) {
                  await new Promise(r => setTimeout(r, 200 + Math.random() * 300));
                  for (let i = 0; i < scrollSteps; i++) {
                    const easedStep = Math.sin((i / scrollSteps) * Math.PI) * scrollStep * -1;
                    window.scrollBy(0, easedStep);
                    await new Promise(r => setTimeout(r, 30 + Math.random() * 20));
                  }
                }
                
                await new Promise(r => setTimeout(r, 150 + Math.random() * 200));
              }
            }

            async function simulateHover(targetElement, x, y) {
              return new Promise((hoverResolve) => {
                try {
                  const mouseoverEvent = createMouseEvent('mouseover', x, y);
                  targetElement.dispatchEvent(mouseoverEvent);
                  
                  const hoverTime = MOUSE_HOVER_TIME_MS;
                  
                  setTimeout(() => {
                    hoverResolve();
                  }, hoverTime);
                } catch (e) {
                  hoverResolve();
                }
              });
            }
            
            async function simulateClick(targetElement, x, y, useDblClick = false) {
              return new Promise((clickResolve) => {
                try {
                  const mousedownEvent1 = createMouseEvent('mousedown', x, y, 1);
                  targetElement.dispatchEvent(mousedownEvent1);
                  
                  const pressTime = MOUSE_PRESS_TIME_MS;
                  
                  setTimeout(() => {
                    const mouseupEvent1 = createMouseEvent('mouseup', x, y, 0);
                    targetElement.dispatchEvent(mouseupEvent1);
                    
                    const clickEvent1 = createMouseEvent('click', x, y);
                    targetElement.dispatchEvent(clickEvent1);
                    
                    if (useDblClick) {
                      const dblClickDelayTime = 150;
                      
                      setTimeout(() => {
                        const mousedownEvent2 = createMouseEvent('mousedown', x, y, 1);
                        targetElement.dispatchEvent(mousedownEvent2);
                        
                        setTimeout(() => {
                          const mouseupEvent2 = createMouseEvent('mouseup', x, y, 0);
                          targetElement.dispatchEvent(mouseupEvent2);
                          
                          const clickEvent2 = createMouseEvent('click', x, y);
                          targetElement.dispatchEvent(clickEvent2);
                          
                          const dblClickEvent = createMouseEvent('dblclick', x, y);
                          targetElement.dispatchEvent(dblClickEvent);
                          
                          if (targetElement === searchInput) {
                            searchInput.focus();
                          }
                          
                          lastX = x;
                          lastY = y;
                          
                          clickResolve();
                        }, pressTime);
                      }, dblClickDelayTime);
                    } else {
                      if (targetElement === searchInput) {
                        searchInput.focus();
                      }
                      
                      lastX = x;
                      lastY = y;
                      
                      clickResolve();
                    }
                  }, pressTime);
                  
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击操作出错: " + e);
                  }
                  clickResolve();
                }
              });
            }
            
            async function clickTarget(isInputBox) {
              try {
                const pos = getInputPosition();
                let targetX, targetY, elementDescription;
                let targetElement = null;
                
                if (isInputBox) {
                  targetX = pos.left + pos.width * 0.5;
                  targetY = pos.top + pos.height * 0.5;
                  elementDescription = "输入框";
                  targetElement = searchInput;
                } else {
                  targetX = pos.left + pos.width * 0.5;
                  targetY = Math.max(pos.top - 25, 5);
                  elementDescription = "输入框上方空白处";
                  
                  targetElement = document.elementFromPoint(targetX, targetY);
                  
                  if (!targetElement) {
                    for (let attempt = 1; attempt <= 5; attempt++) {
                      targetY += 2;
                      targetElement = document.elementFromPoint(targetX, targetY);
                      if (targetElement) break;
                    }
                    
                    if (!targetElement) {
                      targetElement = document.body;
                    }
                  }
                }
                
                await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                await simulateHover(targetElement, targetX, targetY);
                await simulateClick(targetElement, targetX, targetY, !isInputBox);
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("点击" + elementDescription + "完成");
                }
                
                return true;
              } catch (e) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage("点击操作出错: " + e);
                }
                return false;
              }
            }
            
            async function fillSearchInput() {
              try {
                searchInput.value = '';
                searchInput.value = searchKeyword;
                
                const inputEvent = new Event('input', { bubbles: true, cancelable: true });
                searchInput.dispatchEvent(inputEvent);
                
                const changeEvent = new Event('change', { bubbles: true, cancelable: true });
                searchInput.dispatchEvent(changeEvent);
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword);
                }
                
                return true;
              } catch (e) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage("填写搜索关键词出错: " + e);
                }
                return false;
              }
            }
            
            async function clickSearchButton() {
              try {
                const form = document.getElementById('form1');
                if (!form) {
                  return false;
                }
                
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                
                if (!submitButton) {
                  form.submit();
                  return true;
                }
                
                const rect = submitButton.getBoundingClientRect();
                const targetX = rect.left + rect.width * 0.5;
                const targetY = rect.top + rect.height * 0.5;
                
                await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                await simulateHover(submitButton, targetX, targetY);
                await simulateClick(submitButton, targetX, targetY, false);
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("点击搜索按钮完成");
                }
                
                return true;
              } catch (e) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage("点击搜索按钮出错: " + e);
                }
                
                try {
                  const form = document.getElementById('form1');
                  if (form) form.submit();
                } catch (e2) {}
                
                return false;
              }
            }
            
            async function executeSequence() {
              try {
                await addRandomScrolling();
                
                await clickTarget(true);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                
                await clickTarget(false);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                
                await clickTarget(true);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                
                await clickTarget(false);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                
                await clickTarget(true);
                await fillSearchInput();
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                
                await clickTarget(false);
                await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                
                await clickSearchButton();
                
                window.__humanBehaviorSimulationRunning = false;
                
                resolve(true);
              } catch (e) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage("模拟序列执行出错: " + e);
                }
                window.__humanBehaviorSimulationRunning = false;
                resolve(false);
              }
            }
            
            executeSequence();
          });
        }
        
        async function submitSearchForm() {
          const form = document.getElementById('form1');
          const searchInput = document.getElementById('search');
          
          if (!form || !searchInput) {
            return false;
          }
          
          try {
            const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);
            
            if (result) {
              if (window.AppChannel) {
                setTimeout(function() {
                  window.AppChannel.postMessage('FORM_SUBMITTED');
                }, 300);
              }
              
              return true;
            } else {
              try {
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                if (submitButton) {
                  submitButton.click();
                } else {
                  form.submit();
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_SUBMITTED');
                }
                
                return true;
              } catch (e2) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                }
                return false;
              }
            }
          } catch (e) {
            if (window.AppChannel) {
              window.AppChannel.postMessage('SIMULATION_FAILED');
            }
            
            try {
              const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
              if (submitButton) {
                submitButton.click();
              } else {
                form.submit();
              }
              
              if (window.AppChannel) {
                window.AppChannel.postMessage('FORM_SUBMITTED');
              }
              
              return true;
            } catch (e2) {
              if (window.AppChannel) {
                window.AppChannel.postMessage('FORM_PROCESS_FAILED');
              }
              return false;
            }
          }
        }
        
        function checkFormElements() {
          try {
            if (window.__formCheckState.formFound || window.__humanBehaviorSimulationRunning) {
              return;
            }
            
            const currentTime = Date.now();
            window.__formCheckState.lastCheckTime = currentTime;
            
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            
            if (form && searchInput) {
              window.__formCheckState.formFound = true;
              clearAllFormCheckInterval();
              
              (async function() {
                try {
                  const result = await submitSearchForm();
                  if (!result) {
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                    }
                  }
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  }
                }
              })();
            }
          } catch (e) {}
        }
        
        function setupBackupTimer() {
          if (window.__formCheckState.backupTimerId) {
            clearTimeout(window.__formCheckState.backupTimerId);
          }
          
          window.__formCheckState.backupTimerId = setTimeout(function backupCheck() {
            if (!window.__formCheckState.formFound) {
              checkFormElements();
              
              if (!window.__formCheckState.checkInterval) {
                setupMainTimer();
              }
              
              window.__formCheckState.backupTimerId = setTimeout(backupCheck, FORM_CHECK_INTERVAL_MS * 1.5);
            }
          }, FORM_CHECK_INTERVAL_MS * 1.5);
        }
        
        function setupMainTimer() {
          if (window.__formCheckState.checkInterval) {
            clearInterval(window.__formCheckState.checkInterval);
          }
          
          if (!window.__allFormIntervals) {
            window.__allFormIntervals = [];
          }
          
          const intervalId = setInterval(checkFormElements, FORM_CHECK_INTERVAL_MS);
          window.__formCheckState.checkInterval = intervalId;
          window.__allFormIntervals.push(intervalId);
        }
        
        clearAllFormCheckInterval();
        setupMainTimer();
        setupBackupTimer();
        
        checkFormElements();
        
        if (document.readyState !== 'complete') {
          window.addEventListener('load', function() {
            if (!window.__formCheckState.formFound) {
              checkFormElements();
            }
          });
        }
      } catch (e) {
        setTimeout(function() {
          try {
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            if (form && searchInput) {
              const keyword = "%SEARCH_KEYWORD%";
              searchInput.value = keyword;
              form.submit();
              if (window.AppChannel) {
                window.AppChannel.postMessage('FORM_SUBMITTED');
              }
            }
          } catch (innerError) {}
        }, 1000);
      }
    })();
  ''';
  
  /// 指纹随机化预编译脚本 - 简化版
  static const String _fingerprintRandomizationScript = '''
    (function() {
      // 1. 随机修改Canvas指纹
      const originalGetContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function(contextType) {
        const context = originalGetContext.apply(this, arguments);
        if (contextType === '2d') {
          const originalFillText = context.fillText;
          context.fillText = function() {
            context.rotate(Math.random() * 0.0001);
            const result = originalFillText.apply(this, arguments);
            context.rotate(-Math.random() * 0.0001);
            return result;
          };
        }
        return context;
      };
      
      // 2. 随机修改视口信息
      const viewportScale = (0.97 + Math.random() * 0.06).toFixed(2);
      const meta = document.querySelector('meta[name="viewport"]');
      if (meta) {
        meta.content = "width=device-width, initial-scale=" + viewportScale + ", maximum-scale=1.0";
      } else {
        const newMeta = document.createElement('meta');
        newMeta.name = 'viewport';
        newMeta.content = "width=device-width, initial-scale=" + viewportScale + ", maximum-scale=1.0";
        if (document.head) document.head.appendChild(newMeta);
      }
      
      // 3. 生成随机屏幕信息
      const originalWidth = window.screen.width;
      const originalHeight = window.screen.height;
      const offsetX = Math.floor(Math.random() * 4);
      const offsetY = Math.floor(Math.random() * 4);
      
      Object.defineProperty(screen, 'width', {
        get: function() { return originalWidth + offsetX; }
      });
      
      Object.defineProperty(screen, 'height', {
        get: function() { return originalHeight + offsetY; }
      });
      
      // 4. 添加随机化的浏览器会话ID
      if (!window.sessionStorage.getItem('_sid')) {
        const randomId = Math.random().toString(36).substring(2, 15);
        window.sessionStorage.setItem('_sid', randomId);
      }
    })();
  ''';
  
  /// DOM变化监听器预编译脚本 - 简化版
  static const String _domChangeMonitorScriptTemplate = '''
    (function() {
      const initialContentLength = document.body.innerHTML.length;
      
      let lastNotificationTime = Date.now();
      let lastContentLength = initialContentLength;
      let debounceTimeout = null;
      
      const notifyContentChange = function() {
        if (debounceTimeout) {
          clearTimeout(debounceTimeout);
        }
        
        debounceTimeout = setTimeout(function() {
          const now = Date.now();
          if (now - lastNotificationTime < 1000) {
            return;
          }
          
          const currentContentLength = document.body.innerHTML.length;
          const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;
          
          if (changePercent > %SIGNIFICANT_CHANGE_PERCENT%) {
            lastNotificationTime = now;
            lastContentLength = currentContentLength;
            %CHANNEL_NAME%.postMessage('CONTENT_CHANGED');
          }
          
          debounceTimeout = null;
        }, 200);
      };
      
      const observer = new MutationObserver(function(mutations) {
        let hasRelevantChanges = false;
        
        for (let i = 0; i < mutations.length; i++) {
          const mutation = mutations[i];
          if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
            for (let j = 0; j < mutation.addedNodes.length; j++) {
              const node = mutation.addedNodes[j];
              if (node.nodeType === 1 && (node.tagName === 'DIV' || 
                                          node.tagName === 'TABLE' || 
                                          node.tagName === 'UL' || 
                                          node.tagName === 'IFRAME')) {
                hasRelevantChanges = true;
                break;
              }
            }
            if (hasRelevantChanges) break;
          }
        }
        
        if (hasRelevantChanges) {
          notifyContentChange();
        }
      });
      
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: false,
        characterData: false
      });
      
      setTimeout(function() {
        const currentContentLength = document.body.innerHTML.length;
        const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
        
        if (contentChangePct > %SIGNIFICANT_CHANGE_PERCENT%) {
          %CHANNEL_NAME%.postMessage('CONTENT_CHANGED');
          lastContentLength = currentContentLength;
          lastNotificationTime = Date.now();
        }
      }, 1000);
    })();
  ''';
  
  /// 注入表单检测脚本 - 使用预编译模板
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return; // 检查控制器
    try {
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\'); // 转义关键词
      
      // 替换模板变量
      final script = _formDetectionScriptTemplate
          .replaceAll('%FORM_CHECK_INTERVAL_MS%', AppConstants.formCheckIntervalMs.toString())
          .replaceAll('%SEARCH_KEYWORD%', escapedKeyword)
          .replaceAll('%MOUSE_MOVEMENT_STEPS%', AppConstants.mouseMovementSteps.toString())
          .replaceAll('%MOUSE_MOVEMENT_OFFSET%', AppConstants.mouseMovementOffset.toString())
          .replaceAll('%MOUSE_MOVEMENT_DELAY_MS%', AppConstants.mouseMovementDelayMs.toString())
          .replaceAll('%MOUSE_HOVER_TIME_MS%', AppConstants.mouseHoverTimeMs.toString())
          .replaceAll('%MOUSE_PRESS_TIME_MS%', AppConstants.mousePressTimeMs.toString())
          .replaceAll('%ACTION_DELAY_MS%', AppConstants.actionDelayMs.toString());
      
      await controller!.runJavaScript(script);
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 增加随机化浏览器指纹的注入脚本 - 使用预编译脚本
  Future<void> injectFingerprintRandomization() async {
    if (controller == null) return;
    try {
      await controller!.runJavaScript(_fingerprintRandomizationScript);
      LogUtil.i('注入指纹随机化脚本成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入指纹随机化脚本失败', e, stackTrace);
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('中断导航', completeWithError: false)) return; // 检查取消
    
    if (pageUrl != 'about:blank' && searchState[AppConstants.searchSubmitted] == false) { // 检查状态
      String searchKeyword = searchState[AppConstants.searchKeyword] ?? ''; // 获取关键词
      if (searchKeyword.isEmpty) { // 若关键词为空
        LogUtil.i('搜索关键词为空，尝试从URL获取');
        try {
          final uri = Uri.parse(pageUrl); // 解析URL
          searchKeyword = uri.queryParameters['clickText'] ?? ''; // 获取关键词
        } catch (e) {
          LogUtil.e('从URL解析搜索关键词失败: $e');
        }
      }
      
      // 先注入指纹随机化
      await injectFingerprintRandomization();
      
      LogUtil.i('页面开始加载，立即注入表单检测脚本');
      await injectFormDetectionScript(searchKeyword); // 注入脚本
    } else if (searchState[AppConstants.searchSubmitted] == true) { // 已提交
      LogUtil.i('表单已提交，跳过注入表单检测脚本');
    }
    
    if (searchState[AppConstants.engineSwitched] == true && 
        SousuoParser._isPrimaryEngine(pageUrl) && 
        controller != null) { // 检查引擎切换
      try {
        await controller!.loadHtmlString('<html><body></body></html>'); // 加载空页面
      } catch (e) {
        LogUtil.e('中断主引擎加载时出错: $e');
      }
      return;
    }
  }
  
  /// 处理导航事件 - 页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    if (_checkCancelledAndHandle('不处理页面完成事件', completeWithError: false)) return; // 检查取消
    
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch; // 当前时间
    final startMs = searchState[AppConstants.startTimeMs] as int; // 开始时间
    final loadTimeMs = currentTimeMs - startMs; // 加载耗时
    LogUtil.i('页面加载完成: $pageUrl, 耗时: ${loadTimeMs}ms');

    if (pageUrl == 'about:blank') { // 空白页面
      LogUtil.i('空白页面，忽略');
      return;
    }
    
    if (controller == null) { // 检查控制器
      LogUtil.e('WebView控制器为空');
      return;
    }
    
    bool isPrimaryEngine = SousuoParser._isPrimaryEngine(pageUrl); // 检查主引擎
    bool isBackupEngine = SousuoParser._isBackupEngine(pageUrl); // 检查备用引擎
    
    if (!isPrimaryEngine && !isBackupEngine) { // 未知页面
      LogUtil.i('未知页面: $pageUrl');
      return;
    }
    
    if (searchState[AppConstants.engineSwitched] == true && isPrimaryEngine) { // 已切换且为主引擎
      return;
    }
    
    if (isPrimaryEngine) { // 主引擎
      searchState[AppConstants.activeEngine] = 'primary'; // 设置引擎
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) { // 备用引擎
      searchState[AppConstants.activeEngine] = 'backup'; // 设置引擎
      LogUtil.i('备用引擎页面加载完成');
    }
    
    if (searchState[AppConstants.searchSubmitted] == true) { // 已提交
      if (!isExtractionInProgress && !isTestingStarted && !isCollectionFinished) { // 检查状态
        if (_checkCancelledAndHandle('不执行延迟内容变化处理', completeWithError: false)) return; // 检查取消
        
        _timerManager.set(
          'delayedContentChange',
          Duration(milliseconds: 500),
          () {
            if (controller != null && 
                !completer.isCompleted && 
                !cancelToken!.isCancelled && 
                !isCollectionFinished) { // 再次检查
              handleContentChange(); // 处理内容变化
            }
          }
        );
      }
    }
  }
  
  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (_checkCancelledAndHandle('不处理资源错误', completeWithError: false)) return; // 检查取消
    
    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}');
    
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.webp') || 
        error.url!.endsWith('.css')) { // 忽略非关键资源
      return;
    }
    
    if (searchState[AppConstants.activeEngine] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) { // 主引擎关键错误
      
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode); // 检查错误码
      
      if (isCriticalError) { // 关键错误
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState[AppConstants.primaryEngineLoadFailed] = true; // 标记失败
        
        if (searchState[AppConstants.searchSubmitted] == false && searchState[AppConstants.engineSwitched] == false) { // 未提交且未切换
          LogUtil.i('主引擎加载失败，切换备用引擎');
          switchToBackupEngine(); // 切换引擎
        }
      }
    }
  }
  
  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (_checkCancelledAndHandle('阻止所有导航', completeWithError: false)) { // 检查取消
      return NavigationDecision.prevent; // 阻止导航
    }
    
    if (searchState[AppConstants.engineSwitched] == true && SousuoParser._isPrimaryEngine(request.url)) { // 已切换且为主引擎
      LogUtil.i('阻止主引擎导航');
      return NavigationDecision.prevent; // 阻止
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
        request.url.contains('twitter.com')) { // 非必要资源
      LogUtil.i('阻止加载非必要资源: ${request.url}');
      return NavigationDecision.prevent; // 阻止
    }
    
    return NavigationDecision.navigate; // 允许导航
  }
  
  /// 处理JavaScript消息
  void handleJavaScriptMessage(JavaScriptMessage message) {
    if (_checkCancelledAndHandle('不处理JS消息', completeWithError: false)) return; // 检查取消
    
    LogUtil.i('收到消息: ${message.message}');
    
    if (controller == null) { // 检查控制器
      LogUtil.e('控制器为空，无法处理消息');
      return;
    }
    
    if (message.message.startsWith('点击输入框上方') || 
        message.message.startsWith('点击body') ||
        message.message.startsWith('点击了随机元素') ||
        message.message.startsWith('点击页面随机位置') ||
        message.message.startsWith('执行随机滚动') ||
        message.message.startsWith('填写后点击')) { // 忽略特定消息
    }
    else if (message.message == 'FORM_SUBMITTED') { // 表单提交
      searchState[AppConstants.searchSubmitted] = true; // 标记提交
      
      searchState[AppConstants.stage] = ParseStage.searchResults; // 更新阶段
      searchState[AppConstants.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
      
      if (_checkCancelledAndHandle('不注入DOM监听器', completeWithError: false)) return; // 检查取消
      
      // 使用预编译模板注入DOM监听器
      final script = _domChangeMonitorScriptTemplate
          .replaceAll('%SIGNIFICANT_CHANGE_PERCENT%', AppConstants.significantChangePercent.toString())
          .replaceAll('%CHANNEL_NAME%', 'AppChannel');
      controller!.runJavaScript(script);
    } else if (message.message == 'FORM_PROCESS_FAILED') { // 表单处理失败
      if (_shouldSwitchEngine()) { // 主引擎未切换
        LogUtil.i('当前引擎表单处理失败，切换到另一个引擎');
        switchToBackupEngine(); // 切换引擎
      }
    } else if (message.message == 'SIMULATION_FAILED') { // 模拟失败
      LogUtil.e('模拟真人行为失败');
    } else if (message.message.startsWith('模拟真人行为') ||
                message.message.startsWith('点击了搜索输入框') ||
                message.message.startsWith('填写了搜索关键词') ||
                message.message.startsWith('点击提交按钮')) { // 忽略特定消息
    } else if (message.message == 'CONTENT_CHANGED') { // 内容变化
      handleContentChange(); // 处理变化
    }
  }
  
  /// 开始解析流程 - 使用WebView池
  Future<String> startParsing(String url) async {
    try {
      if (_checkCancelledAndHandle('不执行解析')) { // 检查取消
        return 'ERROR'; // 返回错误
      }
      
      setupCancelListener(); // 设置取消监听
      
      setupGlobalTimeout(); // 设置全局超时
      
      final uri = Uri.parse(url); // 解析URL
      final searchKeyword = uri.queryParameters['clickText']; // 获取关键词
      
      if (searchKeyword == null || searchKeyword.isEmpty) { // 检查关键词
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR'; // 返回错误
      }
      
      searchState[AppConstants.searchKeyword] = searchKeyword; // 设置关键词
      
      // 从WebView池获取控制器
      controller = await WebViewPool.acquire();
      
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: handlePageStarted, // 页面开始
        onPageFinished: handlePageFinished, // 页面完成
        onWebResourceError: handleWebResourceError, // 资源错误
        onNavigationRequest: handleNavigationRequest, // 导航请求
      ));
      
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: handleJavaScriptMessage, // JS消息
      );
      
      try {
        // 获取当前激活的引擎并加载对应URL
        final String engineUrl = (searchState[AppConstants.activeEngine] == 'primary') ? 
                                AppConstants.primaryEngine : AppConstants.backupEngine;
        
        LogUtil.i('加载引擎: ${searchState[AppConstants.activeEngine]}, URL: $engineUrl');
        await controller!.loadRequest(Uri.parse(engineUrl)); // 加载引擎
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e');
        
        if (searchState[AppConstants.engineSwitched] == false) { // 未切换
          LogUtil.i('引擎加载失败，准备切换到另一个引擎');
          switchToBackupEngine(); // 切换引擎
        }
      }
      
      final result = await completer.future; // 等待结果
      final String usedEngine = searchState[AppConstants.activeEngine] as String;
      SousuoParser._updateLastUsedEngine(usedEngine); // 更新缓存的最后使用引擎
      int endTimeMs = DateTime.now().millisecondsSinceEpoch; // 结束时间
      int startMs = searchState[AppConstants.startTimeMs] as int; // 开始时间
      LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
      
      return result; // 返回结果
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);
      
      if (foundStreams.isNotEmpty && !completer.isCompleted) { // 有流且未完成
        LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
        try {
          _sortStreamsByPriority(); // 排序流
          
          final result = await _testStreamsWithConcurrencyControl(foundStreams, cancelToken ?? CancelToken()); // 测试流
          if (!completer.isCompleted) { // 若未完成
            completer.complete(result); // 完成任务
          }
          return result; // 返回结果
        } catch (testError) {
          LogUtil.e('测试流时出错: $testError');
          if (!completer.isCompleted) { // 若未完成
            completer.complete('ERROR'); 
          }
        }
      } else if (!completer.isCompleted) { // 无流
        LogUtil.i('无流地址，返回ERROR');
        completer.complete('ERROR'); 
      }
      
      return completer.isCompleted ? await completer.future : 'ERROR'; // 返回结果
    } finally {
      if (!isResourceCleaned) { // 若未清理
        await cleanupResources(); // 清理资源
      }
    }
  }
}

/// 电视直播源搜索引擎解析器
class SousuoParser {
  // 添加静态变量，用于存储上次使用的引擎
  static String? _lastUsedEngine;
  
  // 预编译正则表达式，避免频繁创建
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false
  ); // 提取媒体链接的正则表达式

  // 预编译m3u8检测正则表达式
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false); // 检测m3u8链接的正则表达式

  // 添加屏蔽关键词列表
  static List<String> _blockKeywords = List.from(AppConstants.defaultBlockKeywords);
  
  // 改进LRU缓存
  static final _SearchCache _searchCache = _SearchCache();

  // 初始化WebView池
  static Future<void> initialize() async {
    await WebViewPool.initialize();
  }

  /// 设置屏蔽关键词的方法
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      _blockKeywords = List.from(AppConstants.defaultBlockKeywords); // 重置为默认值
    }
  }

  /// 清理WebView资源，确保异常处理
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
    } catch (e) {
      LogUtil.e('清理WebView出错: $e');
    }
  }
  
  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us'); // 判断是否为主引擎URL
  }

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com'); // 判断是否为备用引擎URL
  }
  
  /// 注入DOM变化监听器，使用预编译脚本
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      final script = _ParserSession._domChangeMonitorScriptTemplate
          .replaceAll('%SIGNIFICANT_CHANGE_PERCENT%', AppConstants.significantChangePercent.toString())
          .replaceAll('%CHANNEL_NAME%', channelName);
      
      await controller.runJavaScript(script);
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace);
    }
  }
  
  /// 改进HTML字符串清理，减少内存分配
  static String _cleanHtmlString(String htmlContent) {
    final int length = htmlContent.length;
    if (length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) {
      return htmlContent; // 快速返回无需清理的情况
    }
    
    // 预分配适当大小的StringBuffer以减少内存再分配
    final buffer = StringBuffer(length);
    final innerContent = htmlContent.substring(1, length - 1); // 去除首尾引号
    
    int i = 0;
    while (i < innerContent.length) {
      if (i < innerContent.length - 1 && innerContent[i] == '\\') {
        final nextChar = innerContent[i + 1];
        if (nextChar == '"') {
          buffer.write('"');
          i += 2;
        } else if (nextChar == 'n') {
          buffer.write('\n');
          i += 2;
        } else if (nextChar == 't') {
          buffer.write('\t');
          i += 2;
        } else if (nextChar == '\\') {
          buffer.write('\\');
          i += 2;
        } else {
          buffer.write(innerContent[i++]);
        }
      } else {
        buffer.write(innerContent[i++]);
      }
    }
    
    return buffer.toString(); // 返回清理后的字符串
  }
  
  /// 改进提取媒体链接，支持增量处理和更高效的URL管理
  static Future<void> _extractMediaLinks(
    WebViewController controller, 
    List<String> foundStreams, 
    bool usingBackupEngine, 
    {int lastProcessedLength = 0, 
     Map<String, bool>? urlCache}
  ) async {
    try {
      final html = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML'
      ); // 获取页面HTML
      
      String htmlContent = _cleanHtmlString(html.toString()); // 清理HTML字符串
      final int contentLength = htmlContent.length;
      LogUtil.i('获取HTML，长度: $contentLength');
      
      if (lastProcessedLength > 0) {
        if (contentLength <= lastProcessedLength) {
          LogUtil.i('内容长度未增加，跳过提取');
          return; // 内容无变化，跳过
        }
        
        // 仅处理新增的内容 - 增量处理
        htmlContent = htmlContent.substring(lastProcessedLength);
        LogUtil.i('增量处理HTML，新增部分长度: ${htmlContent.length}');
      }
      
      // 使用预编译的正则表达式提取链接
      final matches = _mediaLinkRegex.allMatches(htmlContent);
      final int totalMatches = matches.length;
      
      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(2)}');
      }
      
      // 初始化URL去重缓存
      final Map<String, bool> hostMap = urlCache ?? {};
      
      if (urlCache == null && foundStreams.isNotEmpty) {
        for (final url in foundStreams) {
          try {
            final uri = Uri.parse(url);
            hostMap['${uri.host}:${uri.port}'] = true; // 构建缓存
          } catch (_) {
            hostMap[url] = true;
          }
        }
      }
      
      // 预先分配空间，减少动态扩容
      final List<String> m3u8Links = [];
      final List<String> otherLinks = [];
      
      // 单次遍历处理所有匹配
      for (final match in matches) {
        if (match.groupCount >= 2) {
          String? mediaUrl = match.group(2)?.trim();
          
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            // 高效清理URL
            if (mediaUrl.contains('&amp;') || mediaUrl.contains('&quot;') || mediaUrl.endsWith(RegExp("[\")'&;]+"))) {
              mediaUrl = mediaUrl
                  .replaceAll('&amp;', '&')
                  .replaceAll('&quot;', '"')
                  .replaceAll(RegExp("[\")'&;]+\$"), '');
            }
            
            // 快速屏蔽检查
            if (_isUrlBlocked(mediaUrl)) {
              continue; // 跳过屏蔽链接
            }
            
            try {
              final uri = Uri.parse(mediaUrl);
              final String hostKey = '${uri.host}:${uri.port}';
              
              if (!hostMap.containsKey(hostKey)) {
                hostMap[hostKey] = true;
                
                // 使用预编译正则快速检查m3u8
                if (_m3u8Regex.hasMatch(mediaUrl)) {
                  m3u8Links.add(mediaUrl); // 添加m3u8链接
                } else {
                  otherLinks.add(mediaUrl); // 添加其他链接
                }
              }
            } catch (e) {
              LogUtil.e('解析URL出错: $e, URL: $mediaUrl');
            }
          }
        }
      }
      
      // 添加链接处理 - 优先添加m3u8
      int addedCount = 0;
      final int remainingSlots = AppConstants.maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达到最大链接数 ${AppConstants.maxStreams}，不添加新链接');
        return;
      }
      
      // 优先添加m3u8链接
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
      
      // 如果还有空位，添加其他链接
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
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase())); // 检查URL是否含屏蔽词
  }

  /// 获取初始引擎 - 交替使用引擎提高成功率
  static String _getInitialEngine() {
    try {
      // 尝试从SpUtil获取上次使用的引擎
      if (_lastUsedEngine == null) {
        // 尝试从缓存恢复
        _lastUsedEngine = SpUtil.getString('last_used_engine');
        LogUtil.i('从缓存读取上次使用引擎: $_lastUsedEngine');
      }
      
      // 如果有缓存，则使用另一个引擎
      if (_lastUsedEngine != null && _lastUsedEngine!.isNotEmpty) {
        // 使用另一个引擎
        String nextEngine = (_lastUsedEngine == 'primary') ? 'backup' : 'primary';
        LogUtil.i('上次使用 $_lastUsedEngine 引擎，本次使用 $nextEngine 引擎');
        return nextEngine;
      }
      
      // 默认使用主引擎
      LogUtil.i('无缓存记录，默认使用主引擎');
      return 'primary';
    } catch (e) {
      LogUtil.e('获取初始引擎出错: $e');
      return 'primary'; // 出错时默认使用主引擎
    }
  }
  
  /// 更新最后使用的引擎
  static void _updateLastUsedEngine(String engine) {
    try {
      // 更新内存缓存
      _lastUsedEngine = engine;
      
      // 更新SpUtil缓存
      SpUtil.putString('last_used_engine', engine);
      LogUtil.i('更新缓存的最后使用引擎: $engine');
    } catch (e) {
      LogUtil.e('更新引擎缓存出错: $e');
    }
  }
  
  /// 改进缓存URL验证方法，使用HEAD请求减少流量
  static Future<bool> _validateCachedUrl(String keyword, String url, CancelToken? cancelToken) async {
    try {
      final getResponse = await HttpUtil().getRequestWithResponse(
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
      
      if (getResponse != null) {
        LogUtil.i('缓存URL GET验证成功: $url');
        return true;
      } else {
        // URL已失效，从缓存中移除
        LogUtil.i('缓存URL验证失败，从缓存中移除');
        _searchCache.getUrl(keyword, forceRemove: true);
        return false;
      }
    } catch (e) {
      // URL已失效或网络问题，从缓存中移除
      LogUtil.i('缓存URL验证出错: $e，从缓存中移除');
      _searchCache.getUrl(keyword, forceRemove: true);
      return false;
    }
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    if (blockKeywords.isNotEmpty) {
      setBlockKeywords(blockKeywords); // 设置屏蔽关键词
    }
    
    // 尝试从URL中提取关键词
    String? searchKeyword;
    try {
      final uri = Uri.parse(url);
      searchKeyword = uri.queryParameters['clickText'];
    } catch (e) {
      LogUtil.e('提取搜索关键词失败: $e');
    }
    
    // 如果有关键词，尝试从缓存获取结果
    if (searchKeyword != null && searchKeyword.isNotEmpty) {
      final cachedUrl = _searchCache.getUrl(searchKeyword);
      if (cachedUrl != null) {
        LogUtil.i('从缓存获取结果: $searchKeyword -> $cachedUrl');
        
        // 同步验证缓存的URL是否仍然有效
        bool isValid = await _validateCachedUrl(searchKeyword, cachedUrl, cancelToken);
        
        if (isValid) {
          return cachedUrl; // 验证成功才返回
        } else {
          LogUtil.i('缓存URL失效，执行新搜索');
          // 不返回，继续执行后面的正常搜索流程
        }
      }
    }
    
    // 获取初始引擎
    String initialEngine = _getInitialEngine();
    
    // 缓存未命中或验证失败，执行正常搜索
    final session = _ParserSession(cancelToken: cancelToken, initialEngine: initialEngine);
    final result = await session.startParsing(url);
    
    // 搜索成功，更新缓存
    if (result != 'ERROR' && searchKeyword != null && searchKeyword.isNotEmpty) {
      _searchCache.addUrl(searchKeyword, result);
    }
    
    return result;
  }
  
  /// 释放资源
  static Future<void> dispose() async {
    await WebViewPool.clear();
    _searchCache.dispose();
  }
}
