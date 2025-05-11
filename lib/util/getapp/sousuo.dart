import 'dart:async';
import 'package:dio/dio.dart';
import 'dart:math' show min;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

// 解析阶段枚举 - 移至顶层
enum ParseStage {
  formSubmission,  // 阶段1: 页面加载和表单提交
  searchResults,   // 阶段2: 搜索结果处理和流测试
  completed,       // 完成
  error            // 错误
}

/// 常量管理类 - 集中管理所有应用常量
class AppConstants {
  // 私有构造函数防止实例化
  AppConstants._();
  
  /// 状态键常量
  static class StateKeys {
    static const String searchKeyword = 'searchKeyword'; // 搜索关键词
    static const String activeEngine = 'activeEngine'; // 当前搜索引擎
    static const String searchSubmitted = 'searchSubmitted'; // 表单提交状态
    static const String startTimeMs = 'startTimeMs'; // 解析开始时间
    static const String engineSwitched = 'engineSwitched'; // 引擎切换状态
    static const String primaryEngineLoadFailed = 'primaryEngineLoadFailed'; // 主引擎加载失败
    static const String lastHtmlLength = 'lastHtmlLength'; // 上次HTML长度
    static const String extractionCount = 'extractionCount'; // 提取次数
    static const String stage = 'stage'; // 当前解析阶段
    static const String stage1StartTime = 'stage1StartTime'; // 阶段1开始时间
    static const String stage2StartTime = 'stage2StartTime'; // 阶段2开始时间
  }
  
  /// 搜索引擎URLs
  static class Engines {
    static const String primary = 'https://tonkiang.us/?'; // 主搜索引擎
    static const String backup = 'http://www.foodieguide.com/iptvsearch/'; // 备用搜索引擎
  }
  
  /// 超时和等待时间常量
  static class Timeouts {
    // 一般超时
    static const int globalTimeoutSeconds = 28; // 全局超时秒数
    
    // 等待时间
    static const int waitSeconds = 2; // 页面加载和提交后等待秒数
    static const int noMoreChangesSeconds = 3; // 无更多变化检测秒数
    static const int domChangeWaitMs = 300; // DOM变化后等待毫秒
    static const int contentChangeDebounceMs = 300; // 内容变化防抖毫秒
    static const int flowTestWaitMs = 500; // 流测试等待毫秒
    static const int backupEngineLoadWaitMs = 500; // 切换备用引擎前等待毫秒
    static const int cleanupRetryWaitMs = 300; // 清理重试等待毫秒
    
    // 清理相关超时
    static const int cancelListenerTimeoutMs = 500; // 取消监听器超时毫秒
    static const int emptyHtmlLoadTimeoutMs = 300; // 空HTML加载超时毫秒
    static const int webViewCleanupDelayMs = 200; // WebView清理延迟毫秒
    static const int webViewCleanupTimeoutMs = 500; // WebView清理超时毫秒
    
    // JavaScript相关超时
    static const int formCheckIntervalMs = 500; // 表单检查间隔毫秒
    static const int mouseMovementDelayMs = 30; // 鼠标移动延迟毫秒
    static const int mouseHoverTimeMs = 100; // 鼠标悬停时间毫秒
    static const int mousePressTimeMs = 200; // 鼠标按压时间毫秒
    static const int actionDelayMs = 1000; // 操作间隔时间毫秒
  }
  
  /// 限制和阈值常量
  static class Limits {
    static const int maxStreams = 6; // 最大提取媒体流数量
    static const int maxConcurrentTests = 6; // 最大并发测试数
    static const int minValidContentLength = 1000; // 最小有效内容长度
    static const double significantChangePercent = 5.0; // 显著内容变化百分比
    
    // JavaScript相关参数
    static const int mouseMovementSteps = 5; // 鼠标移动步数
    static const int mouseMovementOffset = 8; // 鼠标移动偏移量
  }
}

/// 解析会话类 - 处理解析逻辑和状态管理
class _ParserSession {
  final Completer<String> completer = Completer<String>(); // 异步任务完成器
  final List<String> foundStreams = []; // 发现的流地址
  WebViewController? controller; // WebView控制器
  Timer? contentChangeDebounceTimer; // 内容变化防抖计时器
  
  // 状态标记
  bool isResourceCleaned = false; // 资源清理状态
  bool isTestingStarted = false; // 流测试开始状态
  bool isExtractionInProgress = false; // 提取进行中状态
  
  // 收集完成检测
  bool isCollectionFinished = false; // 收集完成状态
  Timer? noMoreChangesTimer; // 无更多变化检测计时器
  
  // 状态对象
  final Map<String, dynamic> searchState = {
    AppConstants.StateKeys.searchKeyword: '', // 初始化搜索关键词
    AppConstants.StateKeys.activeEngine: 'primary', // 默认主引擎
    AppConstants.StateKeys.searchSubmitted: false, // 表单未提交
    AppConstants.StateKeys.startTimeMs: DateTime.now().millisecondsSinceEpoch,
    AppConstants.StateKeys.engineSwitched: false, // 未切换引擎
    AppConstants.StateKeys.primaryEngineLoadFailed: false, // 主引擎未失败
    AppConstants.StateKeys.lastHtmlLength: 0, // 初始HTML长度
    AppConstants.StateKeys.extractionCount: 0, // 初始提取次数
    AppConstants.StateKeys.stage: ParseStage.formSubmission, // 初始阶段
    AppConstants.StateKeys.stage1StartTime: DateTime.now().millisecondsSinceEpoch, // 阶段1开始
    AppConstants.StateKeys.stage2StartTime: 0, // 阶段2未开始
  };
  
  // 全局超时计时器
  Timer? globalTimeoutTimer; // 全局超时控制
  
  // 取消监听
  StreamSubscription? cancelListener; // 取消事件监听器
  
  // 取消令牌
  final CancelToken? cancelToken; // 任务取消令牌

  // 添加资源清理锁，防止并发清理
  bool _isCleaningUp = false; // 资源清理锁
  
  // URL缓存，用于快速查找
  final Map<String, bool> _urlCache = {}; // URL去重缓存
  
  _ParserSession({this.cancelToken}); // 构造函数，接受取消令牌
  
  /// 统一的取消检查方法
  bool _checkCancelledAndHandle(String context, {bool completeWithError = true}) {
    if (cancelToken?.isCancelled ?? false) { // 检查任务是否取消
      LogUtil.i('任务已取消，$context');
      if (completeWithError && !completer.isCompleted) { // 若需错误完成
        completer.complete('ERROR'); // 标记任务错误
        cleanupResources(); // 清理资源
      }
      return true; // 返回取消状态
    }
    return false; // 未取消
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
        cancelToken!.whenCancel.then((_) { // 监听取消事件
          LogUtil.i('检测到取消信号，立即释放所有资源');
          if (!isResourceCleaned) { // 若未清理
            cleanupResources(immediate: true); // 立即清理
          }
        });
      } catch (e) {
        LogUtil.e('设置取消监听器出错: $e');
      }
    }
  }
  
  /// 添加统一的计时器管理方法
  Timer _safeStartTimer(Timer? currentTimer, Duration duration, Function() callback, String timerName) {
    if (currentTimer?.isActive == true) { // 检查定时器是否活跃
      currentTimer?.cancel(); // 使用空安全取消
    }
    return Timer(duration, callback); // 创建新定时器
  }

  /// 设置全局超时
  void setupGlobalTimeout() {
    globalTimeoutTimer = _safeStartTimer(
      globalTimeoutTimer, 
      Duration(seconds: AppConstants.Timeouts.globalTimeoutSeconds), // 超时时间
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
      },
      '全局超时计时器' // 计时器名称
    );
  }
  
  /// 完成收集并开始测试
  void finishCollectionAndTest() {
    if (_checkCancelledAndHandle('不执行收集完成', completeWithError: false)) return; // 检查取消
    
    if (isCollectionFinished || isTestingStarted) { // 若已完成或测试开始
      return; // 跳过
    }
    
    isCollectionFinished = true; // 标记收集完成
    LogUtil.i('收集完成，准备测试 ${foundStreams.length} 个流地址');
    
    // 取消所有检测计时器
    _cleanupTimer(noMoreChangesTimer, '无更多变化检测计时器'); // 取消无变化计时器
    noMoreChangesTimer = null; // 清空引用
    
    // 开始测试
    startStreamTesting(); // 启动流测试
  }
  
  /// 设置无更多变化的检测计时器
  void setupNoMoreChangesDetection() {
    // 使用优化后的计时器管理方法
    noMoreChangesTimer = _safeStartTimer(
      noMoreChangesTimer,
      Duration(seconds: AppConstants.Timeouts.noMoreChangesSeconds), // 3秒无变化
      () {
        if (_checkCancelledAndHandle('不执行无变化检测', completeWithError: false)) return; // 检查取消
        
        if (!isCollectionFinished && foundStreams.isNotEmpty) { // 若未完成且有流
          LogUtil.i('3秒内无新变化，判定收集结束');
          finishCollectionAndTest(); // 结束收集并测试
        }
      },
      '无更多变化检测计时器' // 计时器名称
    );
  }
  
  /// 改进资源清理，增加锁机制和超时处理
  Future<void> cleanupResources({bool immediate = false}) async {
    if (_isCleaningUp || isResourceCleaned) { // 检查清理状态
      LogUtil.i('资源已清理或正在清理中，跳过');
      return;
    }
    
    _isCleaningUp = true; // 标记清理中
    
    try {
      isResourceCleaned = true; // 标记资源已清理
      
      // 按优先级清理资源
      _cleanupTimer(globalTimeoutTimer, '全局超时计时器'); // 取消全局计时器
      globalTimeoutTimer = null; // 清空引用
      
      _cleanupTimer(contentChangeDebounceTimer, '内容变化防抖计时器'); // 取消防抖计时器
      contentChangeDebounceTimer = null; // 清空引用
      
      _cleanupTimer(noMoreChangesTimer, '无更多变化检测计时器'); // 取消无变化计时器
      noMoreChangesTimer = null; // 清空引用
      
      // 取消订阅监听器
      if (cancelListener != null) { // 检查监听器存在
        try {
          bool cancelled = false; // 超时标志
          Future.delayed(Duration(milliseconds: AppConstants.Timeouts.cancelListenerTimeoutMs), () { // 设置超时
            if (!cancelled) { // 若未取消
              LogUtil.i('取消监听器超时');
              cancelListener = null; // 清空引用
            }
          });
          
          await cancelListener!.cancel(); // 取消监听
          cancelled = true; // 标记已取消
          LogUtil.i('取消监听器已清理');
        } catch (e) {
          LogUtil.e('取消监听器时出错: $e');
        } finally {
          cancelListener = null; // 清空引用
        }
      }
      
      // WebView清理
      if (controller != null) { // 检查控制器存在
        final tempController = controller; // 临时引用
        controller = null; // 清空引用
        
        try {
          bool webviewCleaned = false; // WebView清理标志
          
          await tempController!.loadHtmlString('<html><body></body></html>') // 加载空页面
            .timeout(Duration(milliseconds: AppConstants.Timeouts.emptyHtmlLoadTimeoutMs), onTimeout: () { // 设置超时
              LogUtil.i('加载空页面超时');
              return;
            });
          
          if (!immediate) { // 非立即清理
            await Future.delayed(Duration(milliseconds: AppConstants.Timeouts.webViewCleanupDelayMs)); // 延迟
            
            Future.delayed(Duration(milliseconds: AppConstants.Timeouts.webViewCleanupTimeoutMs), () { // 设置超时
              if (!webviewCleaned) { // 若未清理
                LogUtil.i('WebView清理超时');
              }
            });
            
            await SousuoParser._disposeWebView(tempController) // 释放WebView
              .timeout(Duration(milliseconds: AppConstants.Timeouts.webViewCleanupTimeoutMs), onTimeout: () { // 设置超时
                LogUtil.i('WebView资源释放超时');
                return;
              });
            
            webviewCleaned = true; // 标记清理完成
          }
          
          LogUtil.i('WebView控制器已清理');
        } catch (e) {
          LogUtil.e('清理WebView控制器出错: $e');
        }
      }
      
      // 处理未完成的Completer
      try {
        if (!completer.isCompleted) { // 若未完成
          completer.complete('ERROR'); 
        }
      } catch (e) {
        LogUtil.e('完成Completer时出错: $e');
      }
      
      _urlCache.clear(); // 清空URL缓存
    } catch (e) {
      LogUtil.e('资源清理过程中出错: $e');
    } finally {
      _isCleaningUp = false; // 重置清理标志
      LogUtil.i('所有资源清理完成');
    }
  }
  
  /// 计时器取消方法
  void _cleanupTimer(Timer? timer, String timerName) {
    if (timer != null) { // 检查计时器存在
      try {
        timer.cancel(); // 取消计时器
        LogUtil.i('${timerName}已取消');
      } catch (e) {
        LogUtil.e('取消${timerName}时出错: $e');
      }
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
        cancelToken!.whenCancel.then((_) { // 监听父级取消
          if (!testCancelToken.isCancelled) { // 若测试未取消
            LogUtil.i('父级cancelToken已取消，取消所有测试请求');
            testCancelToken.cancel('父级已取消'); // 取消测试
          }
        }).catchError((e) {
          LogUtil.e('监听取消事件出错: $e');
        });
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
  
  /// 新增带并发控制的流测试方法
  Future<String> _testStreamsWithConcurrencyControl(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR'; // 无流返回错误
    
    final int maxConcurrent = AppConstants.Limits.maxConcurrentTests; // 最大并发数
    final List<String> pendingStreams = List.from(streams); // 待测试流
    final Completer<String> resultCompleter = Completer<String>(); // 结果完成器
    final Set<String> inProgressTests = {}; // 进行中的测试
    
    // 修改：减少超时时间，提高响应速度
    final timeoutTimer = Timer(Duration(seconds: 10), () {
      if (!resultCompleter.isCompleted) {
        LogUtil.i('流测试整体超时，返回ERROR');
        resultCompleter.complete('ERROR');
      }
    });
    
    // 测试单个流
    Future<bool> testSingleStream(String streamUrl) async {
      if (resultCompleter.isCompleted || cancelToken.isCancelled) {
        return false; // 已完成或已取消，跳过
      }
      
      inProgressTests.add(streamUrl); // 标记测试中
      try {
        final stopwatch = Stopwatch()..start(); // 计时
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl),
            method: 'GET',
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
          cancelToken: cancelToken,
        );
        
        final testTime = stopwatch.elapsedMilliseconds; // 测试耗时
        
        if (response != null && !resultCompleter.isCompleted && !cancelToken.isCancelled) {
          LogUtil.i('流 $streamUrl 测试成功，响应时间: ${testTime}ms');
          return true; // 返回成功
        }
      } catch (e) {
        if (!cancelToken.isCancelled) {
          LogUtil.e('测试流 $streamUrl 出错: $e');
        }
      } finally {
        inProgressTests.remove(streamUrl); // 移除测试标记
        
        // 新增：所有测试完成但未找到可用流时，返回ERROR
        if (inProgressTests.isEmpty && pendingStreams.isEmpty && !resultCompleter.isCompleted) {
          LogUtil.i('所有流测试完成，均失败，返回ERROR');
          resultCompleter.complete('ERROR');
        }
      }
      
      return false; // 测试失败
    }
    
    // 启动下一个测试
    void startNextTest() {
      if (resultCompleter.isCompleted || pendingStreams.isEmpty) {
        return; // 已完成或无待测流，跳过
      }
      
      if (inProgressTests.length < maxConcurrent) {
        final nextStream = pendingStreams.removeAt(0); // 取下一个流
        testSingleStream(nextStream).then((success) {
          if (success && !resultCompleter.isCompleted) {
            LogUtil.i('第一个流测试成功，立即返回：$nextStream');
            resultCompleter.complete(nextStream); // 完成任务
            timeoutTimer.cancel(); // 修改：立即取消超时计时器
            if (!cancelToken.isCancelled) {
              cancelToken.cancel('已找到可用流'); // 取消其他测试
            }
          } else {
            startNextTest(); // 测试失败，启动下一个
          }
        });
        
        if (pendingStreams.isNotEmpty && inProgressTests.length < maxConcurrent) {
          startNextTest();
        }
      }
    }
    
    // 初始化测试，启动最大并发数的测试
    for (int i = 0; i < maxConcurrent && i < pendingStreams.length; i++) {
      startNextTest();
    }
    
    try {
      final result = await resultCompleter.future; // 等待结果
      timeoutTimer.cancel(); // 取消超时
      return result; // 返回结果
    } catch (e) {
      LogUtil.e('等待流测试结果时出错: $e');
      return 'ERROR'; // 返回错误
    } finally {
      timeoutTimer.cancel(); // 确保取消超时
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
      
      LogUtil.i('流地址已按优先级排序，m3u8优先');
    } catch (e) {
      LogUtil.e('排序流地址时出错: $e');
    }
  }
  
  /// 检查是否应该切换引擎
  bool _shouldSwitchEngine() {
    return searchState[AppConstants.StateKeys.activeEngine] == 'primary' && 
           searchState[AppConstants.StateKeys.engineSwitched] == false;
  }
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState[AppConstants.StateKeys.engineSwitched] == true) { // 检查是否已切换
      LogUtil.i('已切换到备用引擎，忽略');
      return;
    }
    
    await _executeAsyncOperation('切换备用引擎', () async { // 执行切换
      searchState[AppConstants.StateKeys.activeEngine] = 'backup'; // 设置备用引擎
      searchState[AppConstants.StateKeys.engineSwitched] = true; // 标记已切换
      searchState[AppConstants.StateKeys.searchSubmitted] = false; // 重置提交状态
      searchState[AppConstants.StateKeys.lastHtmlLength] = 0; // 重置HTML长度
      searchState[AppConstants.StateKeys.extractionCount] = 0; // 重置提取次数
      
      searchState[AppConstants.StateKeys.stage] = ParseStage.formSubmission; // 重置阶段
      searchState[AppConstants.StateKeys.stage1StartTime] = DateTime.now().millisecondsSinceEpoch; // 重置时间
      
      isCollectionFinished = false; // 重置收集状态
      _cleanupTimer(noMoreChangesTimer, '无更多变化检测计时器'); // 取消无变化计时器
      noMoreChangesTimer = null; // 清空引用
      
      globalTimeoutTimer?.cancel(); // 取消全局计时器
      
      if (controller != null) { // 检查控制器
        try {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空页面
          await Future.delayed(Duration(milliseconds: AppConstants.Timeouts.backupEngineLoadWaitMs)); // 延迟
          
          await controller!.loadRequest(Uri.parse(AppConstants.Engines.backup)); // 加载备用引擎
          LogUtil.i('已加载备用引擎: ${AppConstants.Engines.backup}');
          
          setupGlobalTimeout(); // 设置新的全局超时
        } catch (e) {
          LogUtil.e('加载备用引擎时出错: $e');
          throw e; // 抛出异常
        }
      } else {
        LogUtil.e('WebView控制器为空，无法切换');
        throw Exception('WebView控制器为空'); // 抛出异常
      }
    });
  }
  
  /// 优化内容变化处理，减少不必要的处理和内存分配
  void handleContentChange() {
    contentChangeDebounceTimer?.cancel(); // 取消现有计时器
    
    if (_checkCancelledAndHandle('停止处理内容变化', completeWithError: false) || 
        isCollectionFinished || 
        isTestingStarted) { // 检查状态
      return; // 跳过
    }
    
    contentChangeDebounceTimer = _safeStartTimer(
      contentChangeDebounceTimer,
      Duration(milliseconds: AppConstants.Timeouts.contentChangeDebounceMs), // 防抖时间
      () async {
        if (controller == null || 
            completer.isCompleted || 
            _checkCancelledAndHandle('取消内容处理', completeWithError: false) ||
            isCollectionFinished || 
            isTestingStarted) { // 再次检查状态
          return; // 跳过
        }
        
        try {
          if (searchState[AppConstants.StateKeys.searchSubmitted] == true && 
              !completer.isCompleted && 
              !isTestingStarted) { // 检查提交状态
            
            // 使用try-finally确保标记重置
            bool extractionTriggered = false;
            try {
              extractionTriggered = true;
              
              int beforeExtractCount = foundStreams.length; // 提取前流数量
              bool isBackupEngine = searchState[AppConstants.StateKeys.activeEngine] == 'backup'; // 检查引擎
              
              await SousuoParser._extractMediaLinks(
                controller!, 
                foundStreams, 
                isBackupEngine,
                lastProcessedLength: searchState[AppConstants.StateKeys.lastHtmlLength], // 最后处理长度
                urlCache: _urlCache // 传递URL缓存
              );
              
              try {
                final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length'); // 获取HTML长度
                searchState[AppConstants.StateKeys.lastHtmlLength] = int.tryParse(result.toString()) ?? 0; // 更新长度
              } catch (e) {
                LogUtil.e('获取HTML长度时出错: $e');
              }
              
              if (_checkCancelledAndHandle('提取后取消处理', completeWithError: false)) { // 检查取消
                return;
              }
              
              searchState[AppConstants.StateKeys.extractionCount] = searchState[AppConstants.StateKeys.extractionCount] + 1; // 增加提取次数
              int afterExtractCount = foundStreams.length; // 提取后流数量
              
              if (afterExtractCount > beforeExtractCount) { // 有新流
                LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接，当前总数: ${afterExtractCount}');
                
                setupNoMoreChangesDetection(); // 设置无变化检测
                
                if (afterExtractCount >= AppConstants.Limits.maxStreams) { // 达到最大流数
                  LogUtil.i('达到最大链接数 ${AppConstants.Limits.maxStreams}，完成收集');
                  finishCollectionAndTest(); // 结束收集
                }
              } else if (_shouldSwitchEngine() && 
                        afterExtractCount == 0) { // 主引擎无流
                LogUtil.i('主引擎无链接，切换备用引擎');
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
      },
      '内容变化防抖计时器' // 计时器名称
    );
  }
  
  /// 注入表单检测脚本
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return; // 检查控制器
    try {
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\'); // 转义关键词
      
      await controller!.runJavaScript('''
        (function() {
          const FORM_CHECK_INTERVAL_MS = ${AppConstants.Timeouts.formCheckIntervalMs}; // 扫描间隔500ms
          
          window.__formCheckState = { // 表单检查状态
            formFound: false, // 表单是否找到
            checkInterval: null, // 检查定时器
            searchKeyword: "$escapedKeyword", // 搜索关键词
            lastCheckTime: Date.now() // 最后检查时间
          };
          
          window.__humanBehaviorSimulationRunning = false; // 模拟行为标志
          
          // 清理所有检查定时器
          function clearAllFormCheckInterval() {
            if (window.__formCheckState.checkInterval) { // 检查定时器
              clearInterval(window.__formCheckState.checkInterval); // 取消
              window.__formCheckState.checkInterval = null; // 清空
            }
            
            try {
              if (window.__allFormIntervals) { // 清理所有定时器
                window.__allFormIntervals.forEach(id => clearInterval(id)); // 取消
                window.__allFormIntervals = []; // 清空
              }
            } catch (e) {
              console.log("清理旧定时器失败:" + e);
            }
          }
          
          const MOUSE_MOVEMENT_STEPS = ${AppConstants.Limits.mouseMovementSteps}; // 鼠标移动步数
          const MOUSE_MOVEMENT_OFFSET = ${AppConstants.Limits.mouseMovementOffset}; // 鼠标移动偏移量
          const MOUSE_MOVEMENT_DELAY_MS = ${AppConstants.Timeouts.mouseMovementDelayMs}; // 鼠标移动延迟
          const MOUSE_HOVER_TIME_MS = ${AppConstants.Timeouts.mouseHoverTimeMs}; // 鼠标悬停时间
          const MOUSE_PRESS_TIME_MS = ${AppConstants.Timeouts.mousePressTimeMs}; // 鼠标按压时间
          const ACTION_DELAY_MS = ${AppConstants.Timeouts.actionDelayMs}; // 操作间隔时间
          
          // 创建鼠标事件
          function createMouseEvent(type, x, y, buttons) {
            return new MouseEvent(type, { // 返回鼠标事件
              'view': window,
              'bubbles': true,
              'cancelable': true,
              'clientX': x,
              'clientY': y,
              'buttons': buttons || 0
            });
          }
          
          // 模拟真人行为
          function simulateHumanBehavior(searchKeyword) {
            return new Promise((resolve) => {
              if (window.__humanBehaviorSimulationRunning) { // 检查运行状态
                if (window.AppChannel) {
                  window.AppChannel.postMessage("模拟真人行为已在运行中，跳过"); // 通知
                }
                return resolve(false); // 跳过
              }
              
              window.__humanBehaviorSimulationRunning = true; // 标记运行
              
              if (window.AppChannel) {
                window.AppChannel.postMessage('开始模拟真人行为'); // 通知
              }
              
              const searchInput = document.getElementById('search'); // 获取输入框
              
              if (!searchInput) { // 检查输入框
                if (window.AppChannel) {
                  window.AppChannel.postMessage("未找到搜索输入框"); // 通知
                }
                window.__humanBehaviorSimulationRunning = false; // 重置
                return resolve(false);
              }
              
              let lastX = window.innerWidth / 2; // 初始X坐标
              let lastY = window.innerHeight / 2; // 初始Y坐标
              
              // 获取输入框位置
              function getInputPosition() {
                const rect = searchInput.getBoundingClientRect(); // 获取位置
                return {
                  top: rect.top,
                  left: rect.left,
                  right: rect.right,
                  bottom: rect.bottom,
                  width: rect.width,
                  height: rect.height
                };
              }
              
              // 模拟鼠标移动 - 改进的贝塞尔曲线和自然加速度
              async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
                // 随机增加步数，使移动更自然
                const steps = MOUSE_MOVEMENT_STEPS + Math.floor(Math.random() * 3);
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("开始移动鼠标"); // 通知
                }
                
                // 生成贝塞尔曲线控制点（更自然的曲线）
                const distance = Math.sqrt(Math.pow(toX - fromX, 2) + Math.pow(toY - fromY, 2));
                const variance = distance * 0.15; // 控制曲线随机弯曲程度
                
                // 两个控制点，形成三次贝塞尔曲线
                const cp1x = fromX + (toX - fromX) * 0.4 + (Math.random() * 2 - 1) * variance;
                const cp1y = fromY + (toY - fromY) * 0.2 + (Math.random() * 2 - 1) * variance;
                const cp2x = fromX + (toX - fromX) * 0.8 + (Math.random() * 2 - 1) * variance;
                const cp2y = fromY + (toY - fromY) * 0.7 + (Math.random() * 2 - 1) * variance;
                
                for (let i = 0; i < steps; i++) {
                  // 基础进度
                  const t = i / steps;
                  
                  // 缓动函数 - 开始慢，中间快，结束慢
                  const easedT = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
                  
                  // 贝塞尔曲线计算公式
                  const bx = Math.pow(1-easedT, 3) * fromX + 
                          3 * Math.pow(1-easedT, 2) * easedT * cp1x + 
                          3 * (1-easedT) * Math.pow(easedT, 2) * cp2x + 
                          Math.pow(easedT, 3) * toX;
                          
                  const by = Math.pow(1-easedT, 3) * fromY + 
                          3 * Math.pow(1-easedT, 2) * easedT * cp1y + 
                          3 * (1-easedT) * Math.pow(easedT, 2) * cp2y + 
                          Math.pow(easedT, 3) * toY;
                  
                  // 添加微小的随机抖动（手部自然抖动）
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
                  
                  // 随机化每步的延迟，模拟不均匀移动速度
                  const stepDelay = MOUSE_MOVEMENT_DELAY_MS * (0.8 + Math.random() * 0.4);
                  await new Promise(r => setTimeout(r, stepDelay));
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("完成鼠标移动");
                }
              }
              
              // 随机滚动页面，模拟真实浏览
              async function addRandomScrolling() {
                // 70%几率执行随机滚动
                if (Math.random() < 0.7) {
                  // 随机决定滚动方向和距离
                  const scrollDirection = Math.random() < 0.6 ? 1 : -1;
                  const scrollAmount = Math.floor(10 + Math.random() * 100) * scrollDirection;
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage(`执行随机滚动: ${scrollAmount}px`);
                  }
                  
                  // 自然滚动动画
                  const scrollSteps = 5 + Math.floor(Math.random() * 5);
                  const scrollStep = scrollAmount / scrollSteps;
                  
                  for (let i = 0; i < scrollSteps; i++) {
                    const easedStep = Math.sin((i / scrollSteps) * Math.PI) * scrollStep;
                    window.scrollBy(0, easedStep);
                    await new Promise(r => setTimeout(r, 30 + Math.random() * 20));
                  }
                  
                  // 有时滚动回原位
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
              
              // 模拟鼠标悬停
              async function simulateHover(targetElement, x, y) {
                return new Promise((hoverResolve) => {
                  try {
                    const mouseoverEvent = createMouseEvent('mouseover', x, y); // 创建悬停事件
                    targetElement.dispatchEvent(mouseoverEvent); // 触发事件
                    
                    const hoverTime = MOUSE_HOVER_TIME_MS; // 悬停时间
                    
                    setTimeout(() => {
                      hoverResolve(); // 完成悬停
                    }, hoverTime);
                  } catch (e) {
                    hoverResolve(); // 继续流程
                  }
                });
              }
              
              // 模拟点击
              async function simulateClick(targetElement, x, y) {
                return new Promise((clickResolve) => {
                  try {
                    const mousedownEvent = createMouseEvent('mousedown', x, y, 1); // 创建按下事件
                    targetElement.dispatchEvent(mousedownEvent); // 触发事件
                    
                    const pressTime = MOUSE_PRESS_TIME_MS; // 按压时间
                    
                    setTimeout(() => { // 延迟释放
                      const mouseupEvent = createMouseEvent('mouseup', x, y, 0); // 创建释放事件
                      targetElement.dispatchEvent(mouseupEvent); // 触发事件
                      
                      const clickEvent = createMouseEvent('click', x, y); // 创建点击事件
                      targetElement.dispatchEvent(clickEvent); // 触发事件
                      
                      if (targetElement === searchInput) { // 若为输入框
                        searchInput.focus(); // 聚焦
                      }
                      
                      lastX = x; // 更新X坐标
                      lastY = y; // 更新Y坐标
                      
                      clickResolve(); // 完成点击
                    }, pressTime);
                    
                  } catch (e) {
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("点击操作出错: " + e); // 通知
                    }
                    clickResolve(); // 继续流程
                  }
                });
              }
              
              // 点击目标元素
              async function clickTarget(isInputBox) {
                try {
                  const pos = getInputPosition(); // 获取位置
                  let targetX, targetY, elementDescription;
                  let targetElement = null;
                  
                  if (isInputBox) { // 点击输入框
                    targetX = pos.left + pos.width * 0.5; // 居中X
                    targetY = pos.top + pos.height * 0.5; // 居中Y
                    elementDescription = "输入框"; // 描述
                    targetElement = searchInput; // 目标元素
                  } else { // 点击上方
                    targetX = pos.left + pos.width * 0.5; // 居中X
                    targetY = Math.max(pos.top - 25, 5); // 上方25px
                    elementDescription = "输入框上方空白处"; // 描述
                    
                    targetElement = document.elementFromPoint(targetX, targetY); // 获取元素
                    
                    if (!targetElement) { // 若无元素
                      for (let attempt = 1; attempt <= 5; attempt++) { // 尝试调整
                        targetY += 2; // 下移2px
                        targetElement = document.elementFromPoint(targetX, targetY); // 重新获取
                        if (targetElement) break; // 找到退出
                      }
                      
                      if (!targetElement) { // 仍无元素
                        targetElement = document.body; // 使用body
                      }
                    }
                  }
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击" + elementDescription); // 通知
                  }
                  
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY); // 移动鼠标
                  await simulateHover(targetElement, targetX, targetY); // 悬停
                  await simulateClick(targetElement, targetX, targetY); // 点击
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击" + elementDescription + "完成"); // 通知
                  }
                  
                  return true;
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击操作出错: " + e); // 通知
                  }
                  return false;
                }
              }
              
              // 填写搜索关键词
              async function fillSearchInput() {
                try {
                  searchInput.value = ''; // 清空输入框
                  searchInput.value = searchKeyword; // 填写关键词
                  
                  const inputEvent = new Event('input', { bubbles: true, cancelable: true }); // 创建输入事件
                  searchInput.dispatchEvent(inputEvent); // 触发事件
                  
                  const changeEvent = new Event('change', { bubbles: true, cancelable: true }); // 创建变更事件
                  searchInput.dispatchEvent(changeEvent); // 触发事件
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword); // 通知
                  }
                  
                  return true;
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写搜索关键词出错: " + e); // 通知
                  }
                  return false;
                }
              }
              
              // 点击搜索按钮
              async function clickSearchButton() {
                try {
                  const form = document.getElementById('form1'); // 获取表单
                  if (!form) { // 检查表单
                    return false;
                  }
                  
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找提交按钮
                  
                  if (!submitButton) { // 无按钮
                    form.submit(); // 直接提交
                    return true;
                  }
                  
                  const rect = submitButton.getBoundingClientRect(); // 获取按钮位置
                  const targetX = rect.left + rect.width * 0.5; // 居中X
                  const targetY = rect.top + rect.height * 0.5; // 居中Y
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击搜索按钮"); // 通知
                  }
                  
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY); // 移动鼠标
                  await simulateHover(submitButton, targetX, targetY); // 悬停
                  await simulateClick(submitButton, targetX, targetY); // 点击
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮完成"); // 通知
                  }
                  
                  return true;
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮出错: " + e); // 通知
                  }
                  
                  try { // 备用提交
                    const form = document.getElementById('form1'); // 重新获取
                    if (form) form.submit(); // 提交
                  } catch (e2) {
                    console.log("备用提交方式也失败: " + e2);
                  }
                  
                  return false;
                }
              }
              
              // 执行模拟序列
              async function executeSequence() {
                try {
                  // 随机滚动页面，增加真实性
                  await addRandomScrolling();
                  
                  await clickTarget(true); // 点击输入框
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 延迟
                  
                  await clickTarget(false); // 点击上方
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 延迟
                  
                  await clickTarget(true); // 再次点击输入框
                  await fillSearchInput(); // 填写关键词
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 延迟
                  
                  await clickTarget(false); // 点击上方
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 延迟
                  
                  await clickSearchButton(); // 点击搜索按钮
                  
                  window.__humanBehaviorSimulationRunning = false; // 重置标志
                  
                  resolve(true);
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("模拟序列执行出错: " + e); // 通知
                  }
                  window.__humanBehaviorSimulationRunning = false; // 重置
                  resolve(false);
                }
              }
              
              executeSequence(); // 开始模拟
            });
          }
          
          // 提交搜索表单
          async function submitSearchForm() {
            const form = document.getElementById('form1'); // 获取表单
            const searchInput = document.getElementById('search'); // 获取输入框
            
            if (!form || !searchInput) { // 检查元素
              for(let i = 0; i < document.forms.length; i++) {
              }
              
              const inputs = document.querySelectorAll('input'); // 获取输入框
              for(let i = 0; i < inputs.length; i++) {
              }
              return false;
            }
            
            try {
              const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword); // 模拟行为
              
              if (result) { // 模拟成功
                if (window.AppChannel) { // 通知Flutter
                  setTimeout(function() {
                    window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知提交
                  }, 300);
                }
                
                return true;
              } else { // 模拟失败
                try {
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找按钮
                  if (submitButton) {
                    submitButton.click(); // 点击按钮
                  } else {
                    form.submit(); // 直接提交
                  }
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知
                  }
                  
                  return true;
                } catch (e2) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                  }
                  return false;
                }
              }
            } catch (e) {
              if (window.AppChannel) {
                window.AppChannel.postMessage('SIMULATION_FAILED'); // 通知失败
              }
              
              try { // 常规提交
                const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找按钮
                if (submitButton) {
                  submitButton.click(); // 点击
                } else {
                  form.submit(); // 直接提交
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知
                }
                
                return true;
              } catch (e2) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                }
                return false;
              }
            }
          }
          
          // 检查表单元素
          function checkFormElements() {
            if (window.__formCheckState.formFound || window.__humanBehaviorSimulationRunning) { // 检查状态
              return;
            }
            
            const currentTime = Date.now(); // 当前时间
            window.__formCheckState.lastCheckTime = currentTime; // 更新时间
            
            const form = document.getElementById('form1'); // 获取表单
            const searchInput = document.getElementById('search'); // 获取输入框
            
            const forms = document.querySelectorAll('form'); // 获取所有表单
            const inputs = document.querySelectorAll('input'); // 获取所有输入框
            
            if (form && searchInput) { // 找到元素
              window.__formCheckState.formFound = true; // 标记找到
              clearAllFormCheckInterval(); // 清理定时器
              
              (async function() { // 异步提交
                try {
                  const result = await submitSearchForm(); // 提交表单
                  if (result) {
                    console.log("表单处理成功");
                  } else {
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                    }
                  }
                } catch (e) {
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                  }
                }
              })();
            } else { // 未找到
              if (!form) console.log("未找到form元素");
              if (!searchInput) console.log("未找到search输入框");
            }
          }
          
          clearAllFormCheckInterval(); // 清理旧定时器
          
          if (!window.__allFormIntervals) { // 初始化定时器数组
            window.__allFormIntervals = [];
          }
          
          const intervalId = setInterval(checkFormElements, FORM_CHECK_INTERVAL_MS); // 创建定时检查
          
          window.__formCheckState.checkInterval = intervalId; // 保存ID
          window.__allFormIntervals.push(intervalId); // 添加到数组
          
          checkFormElements(); // 立即检查
          setTimeout(checkFormElements, 200); // 200ms后检查
        })();
      ''');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 增加随机化浏览器指纹的注入脚本
  Future<void> injectFingerprintRandomization() async {
    if (controller == null) return;
    try {
      await controller!.runJavaScript('''
        (function() {
          // 1. 随机修改Canvas指纹
          const originalGetContext = HTMLCanvasElement.prototype.getContext;
          HTMLCanvasElement.prototype.getContext = function(contextType) {
            const context = originalGetContext.apply(this, arguments);
            if (contextType === '2d') {
              const originalFillText = context.fillText;
              context.fillText = function() {
                // 在fillText时添加极小的随机变化
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
            meta.content = `width=device-width, initial-scale=${viewportScale}, maximum-scale=1.0`;
          } else {
            const newMeta = document.createElement('meta');
            newMeta.name = 'viewport';
            newMeta.content = `width=device-width, initial-scale=${viewportScale}, maximum-scale=1.0`;
            if (document.head) document.head.appendChild(newMeta);
          }
          
          // 3. 生成随机屏幕信息
          // 对原始值做微小偏移，避免检测
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
      ''');
      LogUtil.i('注入指纹随机化脚本成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入指纹随机化脚本失败', e, stackTrace);
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('中断导航', completeWithError: false)) return; // 检查取消
    
    if (pageUrl != 'about:blank' && searchState[AppConstants.StateKeys.searchSubmitted] == false) { // 检查状态
      String searchKeyword = searchState[AppConstants.StateKeys.searchKeyword] ?? ''; // 获取关键词
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
    } else if (searchState[AppConstants.StateKeys.searchSubmitted] == true) { // 已提交
      LogUtil.i('表单已提交，跳过注入表单检测脚本');
    }
    
    if (searchState[AppConstants.StateKeys.engineSwitched] == true && 
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
    final startMs = searchState[AppConstants.StateKeys.startTimeMs] as int; // 开始时间
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
    
    if (searchState[AppConstants.StateKeys.engineSwitched] == true && isPrimaryEngine) { // 已切换且为主引擎
      return;
    }
    
    if (isPrimaryEngine) { // 主引擎
      searchState[AppConstants.StateKeys.activeEngine] = 'primary'; // 设置引擎
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) { // 备用引擎
      searchState[AppConstants.StateKeys.activeEngine] = 'backup'; // 设置引擎
      LogUtil.i('备用引擎页面加载完成');
    }
    
    if (searchState[AppConstants.StateKeys.searchSubmitted] == true) { // 已提交
      if (!isExtractionInProgress && !isTestingStarted && !isCollectionFinished) { // 检查状态
        if (_checkCancelledAndHandle('不执行延迟内容变化处理', completeWithError: false)) return; // 检查取消
          
        Timer(Duration(milliseconds: 500), () { // 延迟处理
          if (controller != null && 
              !completer.isCompleted && 
              !cancelToken!.isCancelled && 
              !isCollectionFinished) { // 再次检查
            handleContentChange(); // 处理内容变化
          }
        });
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
    
    if (searchState[AppConstants.StateKeys.activeEngine] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) { // 主引擎关键错误
      
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode); // 检查错误码
      
      if (isCriticalError) { // 关键错误
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState[AppConstants.StateKeys.primaryEngineLoadFailed] = true; // 标记失败
        
        if (searchState[AppConstants.StateKeys.searchSubmitted] == false && searchState[AppConstants.StateKeys.engineSwitched] == false) { // 未提交且未切换
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
    
    if (searchState[AppConstants.StateKeys.engineSwitched] == true && SousuoParser._isPrimaryEngine(request.url)) { // 已切换且为主引擎
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
      searchState[AppConstants.StateKeys.searchSubmitted] = true; // 标记提交
      
      searchState[AppConstants.StateKeys.stage] = ParseStage.searchResults; // 更新阶段
      searchState[AppConstants.StateKeys.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
      
      if (_checkCancelledAndHandle('不注入DOM监听器', completeWithError: false)) return; // 检查取消
      
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel'); // 注入DOM监听
    } else if (message.message == 'FORM_PROCESS_FAILED') { // 表单处理失败
      if (_shouldSwitchEngine()) { // 主引擎未切换
        LogUtil.i('主引擎表单处理失败，切换备用引擎');
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
  
  /// 开始解析流程
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
      
      searchState[AppConstants.StateKeys.searchKeyword] = searchKeyword; // 设置关键词
      
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted) // 启用JS
        ..setUserAgent(HeadersConfig.userAgent); // 设置UA
      
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
        await controller!.loadRequest(Uri.parse(AppConstants.Engines.primary)); // 加载主引擎
        LogUtil.i('页面加载请求已发出');
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e');
        
        if (searchState[AppConstants.StateKeys.engineSwitched] == false) { // 未切换
          LogUtil.i('主引擎加载失败，准备切换备用引擎');
          switchToBackupEngine(); // 切换引擎
        }
      }
      
      final result = await completer.future; // 等待结果
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      int endTimeMs = DateTime.now().millisecondsSinceEpoch; // 结束时间
      int startMs = searchState[AppConstants.StateKeys.startTimeMs] as int; // 开始时间
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
  // 预编译正则表达式，避免频繁创建
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false
  ); // 提取媒体链接的正则表达式

  // 预编译m3u8检测正则表达式
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false); // 检测m3u8链接的正则表达式

  // 添加屏蔽关键词列表
  static List<String> _blockKeywords = ["freetv.fun", "epg.pw"]; // 屏蔽关键词列表

  /// 设置屏蔽关键词的方法
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      _blockKeywords = [];
    }
  }

  /// 清理WebView资源，确保异常处理
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
      LogUtil.i('清理WebView完成');
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
  
  /// 注入DOM变化监听器，优化性能
  static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
    try {
      await controller.runJavaScript('''
        (function() {
          // 获取初始内容长度
          const initialContentLength = document.body.innerHTML.length;
          
          // 跟踪状态
          let lastNotificationTime = Date.now();
          let lastContentLength = initialContentLength;
          let debounceTimeout = null;
          
          // 防抖动通知内容变化
          const notifyContentChange = function() {
            if (debounceTimeout) {
              clearTimeout(debounceTimeout);
            }
            
            debounceTimeout = setTimeout(function() {
              const now = Date.now();
              if (now - lastNotificationTime < 1000) {
                return; // 忽略频繁通知
              }
              
              // 计算内容变化百分比
              const currentContentLength = document.body.innerHTML.length;
              const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;
              
              // 超过阈值时通知
              if (changePercent > ${AppConstants.Limits.significantChangePercent}) {
                lastNotificationTime = now;
                lastContentLength = currentContentLength;
                ${channelName}.postMessage('CONTENT_CHANGED');
              }
              
              debounceTimeout = null;
            }, 200); // 200ms防抖延迟
          };
          
          // 创建性能优化的MutationObserver
          const observer = new MutationObserver(function(mutations) {
            let hasRelevantChanges = false;
            
            // 检查有意义的变化
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
            
            // 触发通知
            if (hasRelevantChanges) {
              notifyContentChange();
            }
          });
          
          // 配置观察者
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: false,
            characterData: false
          });
          
          // 延迟检查内容变化
          setTimeout(function() {
            const currentContentLength = document.body.innerHTML.length;
            const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
            
            if (contentChangePct > ${AppConstants.Limits.significantChangePercent}) {
              ${channelName}.postMessage('CONTENT_CHANGED');
              lastContentLength = currentContentLength;
              lastNotificationTime = Date.now();
            }
          }, 1000);
        })();
      '''); // 注入JavaScript监听DOM变化
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
    await Future.delayed(Duration(seconds: AppConstants.Timeouts.waitSeconds)); // 等待页面加载
    try {
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\'); // 转义搜索关键词
      final submitScript = '''
        (function() {
          
          const form = document.getElementById('form1'); // 查找表单
          const searchInput = document.getElementById('search'); // 查找输入框
          const submitButton = document.querySelector('input[name="Submit"]'); // 查找提交按钮
          
          if (!searchInput || !form) {
            for(let i = 0; i < document.forms.length; i++) {
            }
            
            const inputs = document.querySelectorAll('input');
            for(let i = 0; i < inputs.length; i++) {
            }
            
            return false;
          }
          
          searchInput.value = "$escapedKeyword"; // 填写关键词
          
          if (submitButton) {
            submitButton.click();
            return true;
          } else {
            const otherSubmitButton = form.querySelector('input[type="submit"]'); // 查找其他提交按钮
            if (otherSubmitButton) {
              otherSubmitButton.click();
              return true;
            } else {
              form.submit();
              return true;
            }
          }
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(submitScript); // 执行提交脚本
      await Future.delayed(Duration(seconds: AppConstants.Timeouts.waitSeconds)); // 等待页面响应
      return result.toString().toLowerCase() == 'true'; // 返回提交结果
    } catch (e, stackTrace) {
      LogUtil.logError('提交表单出错', e, stackTrace);
      return false;
    }
  }

  /// 检查URL是否包含屏蔽关键词
  static bool _isUrlBlocked(String url) {
    if (_blockKeywords.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase())); // 检查URL是否含屏蔽词
  }

  /// 清理HTML字符串，优化内存分配
  static String _cleanHtmlString(String htmlContent) {
    if (htmlContent.length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) {
      return htmlContent; // 快速返回无需清理的情况
    }
    
    final buffer = StringBuffer(htmlContent.length); // 预分配StringBuffer
    final innerContent = htmlContent.substring(1, htmlContent.length - 1); // 去除首尾引号
    
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
  
  /// 提取媒体链接，优化URL处理和缓存
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
      
      if (lastProcessedLength > 0 && contentLength <= lastProcessedLength) {
        LogUtil.i('内容长度未增加，跳过提取');
        return; // 内容无变化，跳过
      }
      
      final matches = _mediaLinkRegex.allMatches(htmlContent); // 提取链接
      final int totalMatches = matches.length;
      
      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(2)}');
      }
      
      final Map<String, bool> hostMap = urlCache ?? {}; // 初始化URL缓存
      
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
      
      final List<String> m3u8Links = []; // 存储m3u8链接
      final List<String> otherLinks = []; // 存储其他链接
      
      for (final match in matches) {
        if (match.groupCount >= 2) {
          String? mediaUrl = match.group(2)?.trim();
          
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            mediaUrl = mediaUrl
                .replaceAll('&amp;', '&')
                .replaceAll('&quot;', '"')
                .replaceAll(RegExp("[\")'&;]+\$"), ''); // 清理URL
            
            if (_isUrlBlocked(mediaUrl)) {
              LogUtil.i('跳过包含屏蔽关键词的链接: $mediaUrl');
              continue; // 跳过屏蔽链接
            }
            
            try {
              final uri = Uri.parse(mediaUrl);
              final String hostKey = '${uri.host}:${uri.port}';
              
              if (!hostMap.containsKey(hostKey)) {
                hostMap[hostKey] = true;
                
                if (_m3u8Regex.hasMatch(mediaUrl)) {
                  m3u8Links.add(mediaUrl); // 添加m3u8链接
                  LogUtil.i('提取到m3u8链接: $mediaUrl');
                } else {
                  otherLinks.add(mediaUrl); // 添加其他链接
                  LogUtil.i('提取到其他格式链接: $mediaUrl');
                }
              }
            } catch (e) {
              LogUtil.e('解析URL出错: $e, URL: $mediaUrl');
            }
          }
        }
      }
      
      int addedCount = 0;
      final int remainingSlots = AppConstants.Limits.maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达到最大链接数 ${AppConstants.Limits.maxStreams}，不添加新链接');
        return;
      }
      
      for (final link in m3u8Links) {
        if (!foundStreams.contains(link)) {
          foundStreams.add(link);
          addedCount++;
          
          if (foundStreams.length >= AppConstants.Limits.maxStreams) {
            LogUtil.i('达到最大链接数 ${AppConstants.Limits.maxStreams}，m3u8链接已足够');
            break;
          }
        }
      }
      
      if (foundStreams.length < AppConstants.Limits.maxStreams) {
        for (final link in otherLinks) {
          if (!foundStreams.contains(link)) {
            foundStreams.add(link);
            addedCount++;
            
            if (foundStreams.length >= AppConstants.Limits.maxStreams) {
              LogUtil.i('达到最大链接数 ${AppConstants.Limits.maxStreams}');
              break;
            }
          }
        }
      }
      
      LogUtil.i('匹配数: $totalMatches, m3u8格式: ${m3u8Links.length}, 其他格式: ${otherLinks.length}, 新增: $addedCount');
      
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > AppConstants.Limits.minValidContentLength ? AppConstants.Limits.minValidContentLength : htmlContent.length;
        String debugSample = htmlContent.substring(0, sampleLength);
        final onclickRegex = RegExp('onclick="[^"]+"', caseSensitive: false);
        final onclickMatches = onclickRegex.allMatches(htmlContent).take(3).map((m) => m.group(0)).join(', ');
        
        LogUtil.i('无链接，HTML片段: $debugSample');
        if (onclickMatches.isNotEmpty) {
          LogUtil.i('页面中的onclick样本: $onclickMatches');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取链接出错', e, stackTrace);
    }
    
    LogUtil.i('提取完成，链接数: ${foundStreams.length}');
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    if (blockKeywords.isNotEmpty) {
      setBlockKeywords(blockKeywords); // 设置屏蔽关键词
    }
    
    final session = _ParserSession(cancelToken: cancelToken); // 创建解析会话
    return await session.startParsing(url); // 开始解析
  }
}
