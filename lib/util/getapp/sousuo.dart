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

/// 状态键常量 - 统一管理状态键，避免拼写错误
class StateKeys {
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
  
  // 提取触发标记 - 从静态变量改为实例变量，解决多实例并发问题
  bool extractionTriggered = false; // 提取触发标记
  
  // 收集完成检测
  bool isCollectionFinished = false; // 收集完成状态
  Timer? noMoreChangesTimer; // 无更多变化检测计时器
  
  // 状态对象
  final Map<String, dynamic> searchState = {
    StateKeys.searchKeyword: '', // 初始化搜索关键词
    StateKeys.activeEngine: 'primary', // 默认主引擎
    StateKeys.searchSubmitted: false, // 表单未提交
    StateKeys.startTimeMs: DateTime.now().millisecondsSinceEpoch,
    StateKeys.engineSwitched: false, // 未切换引擎
    StateKeys.primaryEngineLoadFailed: false, // 主引擎未失败
    StateKeys.lastHtmlLength: 0, // 初始HTML长度
    StateKeys.extractionCount: 0, // 初始提取次数
    StateKeys.stage: ParseStage.formSubmission, // 初始阶段
    StateKeys.stage1StartTime: DateTime.now().millisecondsSinceEpoch, // 阶段1开始
    StateKeys.stage2StartTime: 0, // 阶段2未开始
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
  
  /// 统一的取消检查方法 - 优化重复逻辑
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
  
  /// 设置取消监听器 - 优化使用Future而不是转换为Stream
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
    if (currentTimer?.isActive == true) { // 检查计时器是否活跃
      currentTimer.cancel(); // 取消现有计时器
      LogUtil.i('$timerName已取消');
    }
    return Timer(duration, callback); // 创建新计时器
  }

  /// 设置全局超时
  void setupGlobalTimeout() {
    // 使用优化后的计时器管理方法
    globalTimeoutTimer = _safeStartTimer(
      globalTimeoutTimer, 
      Duration(seconds: SousuoParser._timeoutSeconds), // 超时时间
      () {
        LogUtil.i('全局超时触发');
        
        if (_checkCancelledAndHandle('不处理全局超时')) return; // 检查取消
        
        // 检查收集状态
        if (!isCollectionFinished && foundStreams.isNotEmpty) { // 若未完成且有流
          LogUtil.i('全局超时触发，强制结束收集，开始测试 ${foundStreams.length} 个流');
          finishCollectionAndTest(); // 结束收集并测试
        }
        // 检查引擎状态
        else if (searchState[StateKeys.activeEngine] == 'primary' && searchState[StateKeys.engineSwitched] == false) { // 主引擎未切换
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
    noMoreChangesTimer?.cancel(); // 取消无变化计时器
    noMoreChangesTimer = null; // 清空引用
    
    // 开始测试
    startStreamTesting(); // 启动流测试
  }
  
  /// 设置无更多变化的检测计时器
  void setupNoMoreChangesDetection() {
    // 使用优化后的计时器管理方法
    noMoreChangesTimer = _safeStartTimer(
      noMoreChangesTimer,
      Duration(seconds: 3), // 3秒无变化
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
      _cancelTimer(globalTimeoutTimer, '全局超时计时器'); // 取消全局计时器
      globalTimeoutTimer = null; // 清空引用
      
      _cancelTimer(contentChangeDebounceTimer, '内容变化防抖计时器'); // 取消防抖计时器
      contentChangeDebounceTimer = null; // 清空引用
      
      _cancelTimer(noMoreChangesTimer, '无更多变化检测计时器'); // 取消无变化计时器
      noMoreChangesTimer = null; // 清空引用
      
      // 取消订阅监听器
      if (cancelListener != null) { // 检查监听器存在
        try {
          bool cancelled = false; // 超时标志
          Future.delayed(Duration(milliseconds: 500), () { // 设置超时
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
            .timeout(Duration(milliseconds: 300), onTimeout: () { // 设置超时
              LogUtil.i('加载空页面超时');
              return;
            });
          
          if (!immediate) { // 非立即清理
            await Future.delayed(Duration(milliseconds: 100)); // 延迟
            
            Future.delayed(Duration(milliseconds: 600), () { // 设置超时
              if (!webviewCleaned) { // 若未清理
                LogUtil.i('WebView清理超时');
              }
            });
            
            await SousuoParser._disposeWebView(tempController) // 释放WebView
              .timeout(Duration(milliseconds: 500), onTimeout: () { // 设置超时
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
  
  /// 新增统一的计时器取消方法
  void _cancelTimer(Timer? timer, String timerName) {
    if (timer != null) { // 检查计时器存在
      try {
        timer.cancel(); // 取消计时器
        LogUtil.i('${timerName}已取消');
      } catch (e) {
        LogUtil.e('取消${timerName}时出错: $e');
      }
    }
  }
  
  /// 通用的异步操作执行方法 - 统一错误处理模式
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
    
    final int maxConcurrent = 3; // 最大并发数
    final List<String> pendingStreams = List.from(streams); // 待测试流
    final Completer<String> resultCompleter = Completer<String>(); // 结果完成器
    final Set<String> inProgressTests = {}; // 进行中的测试
    
    final timeoutTimer = Timer(Duration(seconds: 8), () { // 设置超时
      if (!resultCompleter.isCompleted) { // 若未完成
        LogUtil.i('流测试整体超时');
        resultCompleter.complete('ERROR'); 
      }
    });
    
    // 测试单个流
    Future<bool> testSingleStream(String streamUrl) async {
      if (resultCompleter.isCompleted || cancelToken.isCancelled) { // 检查状态
        return false; // 跳过
      }
      
      inProgressTests.add(streamUrl); // 标记测试中
      try {
        final stopwatch = Stopwatch()..start(); // 计时
        final response = await HttpUtil().getRequestWithResponse(
          streamUrl,
          options: Options(
            headers: HeadersConfig.generateHeaders(url: streamUrl), // 请求头
            method: 'GET', // 请求方法
            responseType: ResponseType.plain, // 响应类型
            followRedirects: true, // 跟随重定向
            validateStatus: (status) => status != null && status < 400, // 状态验证
            receiveTimeout: Duration(seconds: 4), // 接收超时
            sendTimeout: Duration(seconds: 4), // 发送超时
          ),
          cancelToken: cancelToken, // 取消令牌
          retryCount: 1, // 重试次数
        );
        
        final testTime = stopwatch.elapsedMilliseconds; // 测试耗时
        
        if (response != null && !resultCompleter.isCompleted && !cancelToken.isCancelled) { // 测试成功
          LogUtil.i('流 $streamUrl 测试成功，响应时间: ${testTime}ms');
          return true; // 返回成功
        }
      } catch (e) {
        if (!cancelToken.isCancelled) { // 若非取消导致
          LogUtil.e('测试流 $streamUrl 出错: $e');
        }
      } finally {
        inProgressTests.remove(streamUrl); // 移除测试标记
      }
      
      return false; // 测试失败
    }
    
    // 启动下一个测试
    void startNextTest() {
      if (resultCompleter.isCompleted || pendingStreams.isEmpty) { // 检查状态
        return; // 跳过
      }
      
      if (inProgressTests.length < maxConcurrent) { // 检查并发数
        final nextStream = pendingStreams.removeAt(0); // 取下一个流
        testSingleStream(nextStream).then((success) { // 测试流
          if (success && !resultCompleter.isCompleted) { // 测试成功
            resultCompleter.complete(nextStream); // 完成任务
            if (!cancelToken.isCancelled) { // 若未取消
              cancelToken.cancel('已找到可用流'); // 取消其他测试
            }
          } else { // 测试失败
            startNextTest(); // 启动下一个
          }
        });
        
        if (pendingStreams.isNotEmpty && inProgressTests.length < maxConcurrent) { // 继续测试
          startNextTest();
        }
      }
    }
    
    // 初始化测试
    for (int i = 0; i < maxConcurrent && i < pendingStreams.length; i++) { // 启动初始测试
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
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState[StateKeys.engineSwitched] == true) { // 检查是否已切换
      LogUtil.i('已切换到备用引擎，忽略');
      return;
    }
    
    await _executeAsyncOperation('切换备用引擎', () async { // 执行切换
      LogUtil.i('主引擎不可用，切换到备用引擎');
      searchState[StateKeys.activeEngine] = 'backup'; // 设置备用引擎
      searchState[StateKeys.engineSwitched] = true; // 标记已切换
      searchState[StateKeys.searchSubmitted] = false; // 重置提交状态
      searchState[StateKeys.lastHtmlLength] = 0; // 重置HTML长度
      searchState[StateKeys.extractionCount] = 0; // 重置提取次数
      
      searchState[StateKeys.stage] = ParseStage.formSubmission; // 重置阶段
      searchState[StateKeys.stage1StartTime] = DateTime.now().millisecondsSinceEpoch; // 重置时间
      
      extractionTriggered = false; // 重置提取标记
      
      isCollectionFinished = false; // 重置收集状态
      noMoreChangesTimer?.cancel(); // 取消无变化计时器
      noMoreChangesTimer = null; // 清空引用
      
      globalTimeoutTimer?.cancel(); // 取消全局计时器
      
      if (controller != null) { // 检查控制器
        try {
          await controller!.loadHtmlString('<html><body></body></html>'); // 加载空页面
          await Future.delayed(Duration(milliseconds: SousuoParser._backupEngineLoadWaitMs)); // 延迟
          
          await controller!.loadRequest(Uri.parse(SousuoParser._backupEngine)); // 加载备用引擎
          LogUtil.i('已加载备用引擎: ${SousuoParser._backupEngine}');
          
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
        isTestingStarted || 
        isExtractionInProgress || 
        extractionTriggered) { // 检查状态
      return; // 跳过
    }
    
    contentChangeDebounceTimer = _safeStartTimer(
      contentChangeDebounceTimer,
      Duration(milliseconds: SousuoParser._contentChangeDebounceMs), // 防抖时间
      () async {
        if (controller == null || 
            completer.isCompleted || 
            _checkCancelledAndHandle('取消内容处理', completeWithError: false) ||
            isCollectionFinished || 
            isTestingStarted) { // 再次检查状态
          return; // 跳过
        }
        
        isExtractionInProgress = true; // 标记提取中
        
        try {
          if (searchState[StateKeys.searchSubmitted] == true && 
              !completer.isCompleted && 
              !isTestingStarted) { // 检查提交状态
            
            extractionTriggered = true; // 标记提取触发
            
            int beforeExtractCount = foundStreams.length; // 提取前流数量
            bool isBackupEngine = searchState[StateKeys.activeEngine] == 'backup'; // 检查引擎
            
            await SousuoParser._extractMediaLinks(
              controller!, 
              foundStreams, 
              isBackupEngine,
              lastProcessedLength: searchState[StateKeys.lastHtmlLength], // 最后处理长度
              urlCache: _urlCache // 传递URL缓存
            );
            
            try {
              final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length'); // 获取HTML长度
              searchState[StateKeys.lastHtmlLength] = int.tryParse(result.toString()) ?? 0; // 更新长度
            } catch (e) {
              LogUtil.e('获取HTML长度时出错: $e');
              extractionTriggered = false; // 重置标记
            }
            
            if (_checkCancelledAndHandle('提取后取消处理', completeWithError: false)) { // 检查取消
              isExtractionInProgress = false; // 重置标记
              return;
            }
            
            searchState[StateKeys.extractionCount] = searchState[StateKeys.extractionCount] + 1; // 增加提取次数
            int afterExtractCount = foundStreams.length; // 提取后流数量
            
            if (afterExtractCount > beforeExtractCount) { // 有新流
              LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接，当前总数: ${afterExtractCount}');
              
              extractionTriggered = false; // 重置标记
              
              setupNoMoreChangesDetection(); // 设置无变化检测
              
              if (afterExtractCount >= SousuoParser._maxStreams) { // 达到最大流数
                LogUtil.i('达到最大链接数 ${SousuoParser._maxStreams}，完成收集');
                finishCollectionAndTest(); // 结束收集
              }
            } else if (searchState[StateKeys.activeEngine] == 'primary' && 
                      afterExtractCount == 0 && 
                      searchState[StateKeys.engineSwitched] == false) { // 主引擎无流
              extractionTriggered = false; // 重置标记
              LogUtil.i('主引擎无链接，切换备用引擎，重置提取标记');
              switchToBackupEngine(); // 切换引擎
            } else { // 无新流
              extractionTriggered = false; // 重置标记
              
              if (afterExtractCount > 0) { // 若有流
                setupNoMoreChangesDetection(); // 设置无变化检测
              }
            }
          } else {
            extractionTriggered = false; // 重置标记
          }
        } catch (e) {
          LogUtil.e('处理内容变化时出错: $e');
          extractionTriggered = false; // 重置标记
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
          console.log("开始注入表单检测脚本");
          
          const FORM_CHECK_INTERVAL_MS = 500; // 扫描间隔500ms
          
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
              console.log("停止表单检测");
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
          
          const MOUSE_MOVEMENT_STEPS = 5; // 鼠标移动步数
          const MOUSE_MOVEMENT_OFFSET = 8; // 鼠标移动偏移量
          const MOUSE_MOVEMENT_DELAY_MS = 30; // 鼠标移动延迟
          const MOUSE_HOVER_TIME_MS = 200; // 鼠标悬停时间
          const MOUSE_PRESS_TIME_MS = 200; // 鼠标按压时间
          const ACTION_DELAY_MS = 1000; // 操作间隔时间
          
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
                console.log("模拟真人行为已在运行中，跳过此次执行");
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
                console.log("未找到搜索输入框");
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
              
              // 模拟鼠标移动
              async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
                const steps = MOUSE_MOVEMENT_STEPS; // 移动步数
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("开始移动鼠标"); // 通知
                }
                
                for (let i = 0; i < steps; i++) { // 逐步移动
                  const progress = i / steps; // 进度
                  const offsetX = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET; // X偏移
                  const offsetY = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET; // Y偏移
                  
                  const curX = fromX + (toX - fromX) * progress + offsetX; // 当前X
                  const curY = fromY + (toY - fromY) * progress + offsetY; // 当前Y
                  
                  const mousemoveEvent = createMouseEvent('mousemove', curX, curY); // 创建移动事件
                  
                  const elementAtPoint = document.elementFromPoint(curX, curY); // 获取元素
                  if (elementAtPoint) {
                    elementAtPoint.dispatchEvent(mousemoveEvent); // 触发事件
                  } else {
                    document.body.dispatchEvent(mousemoveEvent); // 触发到body
                  }
                  
                  await new Promise(r => setTimeout(r, MOUSE_MOVEMENT_DELAY_MS)); // 延迟
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("完成鼠标移动"); // 通知
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
                    console.log("悬停操作出错: " + e);
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
                    console.log("点击操作出错: " + e);
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
                        console.log("未在指定位置找到元素，使用body");
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
                  console.log("点击操作出错: " + e);
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
                  console.log("填写搜索关键词出错: " + e);
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
                    console.log("未找到表单");
                    return false;
                  }
                  
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]'); // 查找提交按钮
                  
                  if (!submitButton) { // 无按钮
                    console.log("未找到提交按钮，直接提交表单");
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
                  console.log("点击搜索按钮出错: " + e);
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
                  console.log("模拟序列执行出错: " + e);
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
            console.log("准备提交搜索表单");
            
            const form = document.getElementById('form1'); // 获取表单
            const searchInput = document.getElementById('search'); // 获取输入框
            
            if (!form || !searchInput) { // 检查元素
              console.log("未找到有效的表单元素");
              console.log("表单数量: " + document.forms.length);
              for(let i = 0; i < document.forms.length; i++) {
                console.log("表单 #" + i + " ID: " + document.forms[i].id);
              }
              
              const inputs = document.querySelectorAll('input'); // 获取输入框
              console.log("输入框数量: " + inputs.length);
              for(let i = 0; i < inputs.length; i++) {
                console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
              }
              return false;
            }
            
            console.log("找到表单和输入框");
            
            try {
              console.log("开始模拟真人行为");
              const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword); // 模拟行为
              
              if (result) { // 模拟成功
                console.log("模拟真人行为成功");
                
                if (window.AppChannel) { // 通知Flutter
                  setTimeout(function() {
                    window.AppChannel.postMessage('FORM_SUBMITTED'); // 通知提交
                  }, 300);
                }
                
                return true;
              } else { // 模拟失败
                console.log("模拟真人行为失败，尝试常规提交");
                
                try { // 常规提交
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
                  console.log("备用提交方式也失败: " + e2);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                  }
                  return false;
                }
              }
            } catch (e) {
              console.log("模拟行为失败: " + e);
              
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
                console.log("备用提交方式也失败: " + e2);
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
              console.log("表单已找到或模拟行为正在执行，跳过此次检查");
              return;
            }
            
            const currentTime = Date.now(); // 当前时间
            console.log("[" + (currentTime - window.__formCheckState.lastCheckTime) + "ms] 执行表单检查...");
            window.__formCheckState.lastCheckTime = currentTime; // 更新时间
            
            const form = document.getElementById('form1'); // 获取表单
            const searchInput = document.getElementById('search'); // 获取输入框
            
            const forms = document.querySelectorAll('form'); // 获取所有表单
            const inputs = document.querySelectorAll('input'); // 获取所有输入框
            console.log("页面状态 - 表单总数:", forms.length, "输入框总数:", inputs.length);
            
            if (form && searchInput) { // 找到元素
              console.log("找到表单元素! 立即执行提交流程");
              window.__formCheckState.formFound = true; // 标记找到
              clearAllFormCheckInterval(); // 清理定时器
              
              (async function() { // 异步提交
                try {
                  const result = await submitSearchForm(); // 提交表单
                  if (result) {
                    console.log("表单处理成功");
                  } else {
                    console.log("表单处理失败");
                    
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED'); // 通知失败
                    }
                  }
                } catch (e) {
                  console.log("表单提交异常: " + e);
                  
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
          
          console.log("使用常量间隔 " + FORM_CHECK_INTERVAL_MS + "ms 开始定时检查表单元素");
          const intervalId = setInterval(checkFormElements, FORM_CHECK_INTERVAL_MS); // 创建定时检查
          
          window.__formCheckState.checkInterval = intervalId; // 保存ID
          window.__allFormIntervals.push(intervalId); // 添加到数组
          
          checkFormElements(); // 立即检查
          setTimeout(checkFormElements, 200); // 200ms后检查
        })();
      ''');
      
      LogUtil.i('表单检测脚本注入成功，立即开始定期扫描');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('中断导航', completeWithError: false)) return; // 检查取消
    
    if (pageUrl != 'about:blank' && searchState[StateKeys.searchSubmitted] == false) { // 检查状态
      String searchKeyword = searchState[StateKeys.searchKeyword] ?? ''; // 获取关键词
      if (searchKeyword.isEmpty) { // 若关键词为空
        LogUtil.i('搜索关键词为空，尝试从URL获取');
        try {
          final uri = Uri.parse(pageUrl); // 解析URL
          searchKeyword = uri.queryParameters['clickText'] ?? ''; // 获取关键词
        } catch (e) {
          LogUtil.e('从URL解析搜索关键词失败: $e');
        }
      }
      
      LogUtil.i('页面开始加载，立即注入表单检测脚本');
      await injectFormDetectionScript(searchKeyword); // 注入脚本
    } else if (searchState[StateKeys.searchSubmitted] == true) { // 已提交
      LogUtil.i('表单已提交，跳过注入表单检测脚本');
    }
    
    if (searchState[StateKeys.engineSwitched] == true && 
        SousuoParser._isPrimaryEngine(pageUrl) && 
        controller != null) { // 检查引擎切换
      LogUtil.i('已切换备用引擎，中断主引擎加载');
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
    final startMs = searchState[StateKeys.startTimeMs] as int; // 开始时间
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
    
    if (searchState[StateKeys.engineSwitched] == true && isPrimaryEngine) { // 已切换且为主引擎
      LogUtil.i('已切换备用引擎，忽略主引擎');
      return;
    }
    
    if (isPrimaryEngine) { // 主引擎
      searchState[StateKeys.activeEngine] = 'primary'; // 设置引擎
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) { // 备用引擎
      searchState[StateKeys.activeEngine] = 'backup'; // 设置引擎
      LogUtil.i('备用引擎页面加载完成');
    }
    
    if (searchState[StateKeys.searchSubmitted] == true) { // 已提交
      if (!isExtractionInProgress && !isTestingStarted && !extractionTriggered && !isCollectionFinished) { // 检查状态
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
    
    if (searchState[StateKeys.activeEngine] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) { // 主引擎关键错误
      
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode); // 检查错误码
      
      if (isCriticalError) { // 关键错误
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState[StateKeys.primaryEngineLoadFailed] = true; // 标记失败
        
        if (searchState[StateKeys.searchSubmitted] == false && searchState[StateKeys.engineSwitched] == false) { // 未提交且未切换
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
    
    if (searchState[StateKeys.engineSwitched] == true && SousuoParser._isPrimaryEngine(request.url)) { // 已切换且为主引擎
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
        message.message.startsWith('填写后点击')) { // 忽略特定消息
    }
    else if (message.message == 'FORM_SUBMITTED') { // 表单提交
      searchState[StateKeys.searchSubmitted] = true; // 标记提交
      
      searchState[StateKeys.stage] = ParseStage.searchResults; // 更新阶段
      searchState[StateKeys.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
      
      if (_checkCancelledAndHandle('不注入DOM监听器', completeWithError: false)) return; // 检查取消
      
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel'); // 注入DOM监听
    } else if (message.message == 'FORM_PROCESS_FAILED') { // 表单处理失败
      if (searchState[StateKeys.activeEngine] == 'primary' && searchState[StateKeys.engineSwitched] == false) { // 主引擎未切换
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
  
  /// 开始解析流程 - 优化异常处理和资源管理
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
      
      searchState[StateKeys.searchKeyword] = searchKeyword; // 设置关键词
      
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
        await controller!.loadRequest(Uri.parse(SousuoParser._primaryEngine)); // 加载主引擎
        LogUtil.i('页面加载请求已发出');
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e');
        
        if (searchState[StateKeys.engineSwitched] == false) { // 未切换
          LogUtil.i('主引擎加载失败，准备切换备用引擎');
          switchToBackupEngine(); // 切换引擎
        }
      }
      
      final result = await completer.future; // 等待结果
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      int endTimeMs = DateTime.now().millisecondsSinceEpoch; // 结束时间
      int startMs = searchState[StateKeys.startTimeMs] as int; // 开始时间
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
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用搜索引擎URL
  
  // 通用配置
  static const int _timeoutSeconds = 28; // 统一超时时间，用于表单检测和DOM变化
  static const int _maxStreams = 8; // 最大提取媒体流数量
  
  // 时间常量 - 页面和DOM相关
  static const int _waitSeconds = 2; // 页面加载和提交后等待时间
  static const int _domChangeWaitMs = 500; // DOM变化后等待时间
  
  // 时间常量 - 测试和清理相关
  static const int _flowTestWaitMs = 500; // 流测试等待时间
  static const int _backupEngineLoadWaitMs = 300; // 切换备用引擎前等待时间
  static const int _cleanupRetryWaitMs = 300; // 清理重试等待时间
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 5.0; // 显著内容变化百分比，提高敏感度
  
  // 内容变化防抖时间（毫秒）
  static const int _contentChangeDebounceMs = 300; // 内容变化防抖时间

  // 添加屏蔽关键词列表
  static List<String> _blockKeywords = ["freetv.fun", "epg.pw"]; // 屏蔽关键词列表

  // 预编译正则表达式，避免频繁创建
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:"|"|\')?((https?://[^"\']+)(?:"|"|\')?)',
    caseSensitive: false
  ); // 提取媒体链接的正则表达式

  // 预编译m3u8检测正则表达式
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false); // 检测m3u8链接的正则表达式

  /// 设置屏蔽关键词的方法
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      LogUtil.i('设置屏蔽关键词: ${_blockKeywords.join(', ')}');
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
          console.log("注入DOM变化监听器");
          
          // 获取初始内容长度
          const initialContentLength = document.body.innerHTML.length;
          console.log("初始内容长度: " + initialContentLength);
          
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
              if (changePercent > ${_significantChangePercent}) {
                console.log("检测到显著内容变化: " + changePercent.toFixed(2) + "%");
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
            console.log("延迟检查内容变化百分比: " + contentChangePct.toFixed(2) + "%");
            
            if (contentChangePct > ${_significantChangePercent}) {
              console.log("延迟检测到显著内容变化");
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
    await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面加载
    try {
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\'); // 转义搜索关键词
      final submitScript = '''
        (function() {
          console.log("查找搜索表单元素");
          
          const form = document.getElementById('form1'); // 查找表单
          const searchInput = document.getElementById('search'); // 查找输入框
          const submitButton = document.querySelector('input[name="Submit"]'); // 查找提交按钮
          
          if (!searchInput || !form) {
            console.log("未找到表单元素");
            console.log("表单数量: " + document.forms.length);
            for(let i = 0; i < document.forms.length; i++) {
              console.log("表单 #" + i + " ID: " + document.forms[i].id);
            }
            
            const inputs = document.querySelectorAll('input');
            console.log("输入框数量: " + inputs.length);
            for(let i = 0; i < inputs.length; i++) {
              console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
            }
            
            return false;
          }
          
          searchInput.value = "$escapedKeyword"; // 填写关键词
          console.log("填写关键词: " + searchInput.value);
          
          if (submitButton) {
            console.log("点击提交按钮");
            submitButton.click();
            return true;
          } else {
            console.log("未找到提交按钮，尝试其他方法");
            
            const otherSubmitButton = form.querySelector('input[type="submit"]'); // 查找其他提交按钮
            if (otherSubmitButton) {
              console.log("找到submit按钮，点击");
              otherSubmitButton.click();
              return true;
            } else {
              console.log("直接提交表单");
              form.submit();
              return true;
            }
          }
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(submitScript); // 执行提交脚本
      await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面响应
      LogUtil.i('等待响应 (${_waitSeconds}秒)');
      
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
    LogUtil.i('从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
    
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
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(1)}');
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
        if (match.groupCount >= 1) {
          String? mediaUrl = match.group(1)?.trim();
          
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            mediaUrl = mediaUrl
                .replaceAll('&', '&')
                .replaceAll('"', '"')
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
      final int remainingSlots = _maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达到最大链接数 $_maxStreams，不添加新链接');
        return;
      }
      
      for (final link in m3u8Links) {
        if (!foundStreams.contains(link)) {
          foundStreams.add(link);
          addedCount++;
          
          if (foundStreams.length >= _maxStreams) {
            LogUtil.i('达到最大链接数 $_maxStreams，m3u8链接已足够');
            break;
          }
        }
      }
      
      if (foundStreams.length < _maxStreams) {
        for (final link in otherLinks) {
          if (!foundStreams.contains(link)) {
            foundStreams.add(link);
            addedCount++;
            
            if (foundStreams.length >= _maxStreams) {
              LogUtil.i('达到最大链接数 $_maxStreams');
              break;
            }
          }
        }
      }
      
      LogUtil.i('匹配数: $totalMatches, m3u8格式: ${m3u8Links.length}, 其他格式: ${otherLinks.length}, 新增: $addedCount');
      
      if (addedCount == 0 && totalMatches == 0) {
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
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
  
  /// 测试流地址，返回最快的可用流
  static Future<String> _testStreamsAndGetFastest(List<String> streams, {CancelToken? cancelToken}) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR'; // 无流地址
    }
    
    LogUtil.i('测试 ${streams.length} 个流地址');
    
    final testCancelToken = cancelToken ?? CancelToken(); // 创建测试取消令牌
    final completer = Completer<String>();
    bool hasValidResponse = false;
    
    Timer? testTimeoutTimer;
    try {
      testTimeoutTimer = Timer(Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          LogUtil.i('流测试超时，取消所有进行中的请求');
          if (!testCancelToken.isCancelled) {
            testCancelToken.cancel('测试超时');
          }
          if (!hasValidResponse) {
            completer.complete('ERROR');
          }
        }
      }); // 设置测试超时
      
      const int maxConcurrentTests = 3; // 最大并发测试数
      final pendingStreams = List<String>.from(streams);
      final inProgressStreams = <String>{};
      
      Future<bool> testStream(String streamUrl) async {
        if (completer.isCompleted || testCancelToken.isCancelled) {
          return false; // 测试已完成或取消
        }
        
        inProgressStreams.add(streamUrl);
        try {
          final stopwatch = Stopwatch()..start();
          final response = await HttpUtil().getRequestWithResponse(
            streamUrl,
            options: Options(
              headers: HeadersConfig.generateHeaders(url: streamUrl),
              method: 'GET',
              responseType: ResponseType.plain,
              followRedirects: true,
              validateStatus: (status) => status != null && status < 400,
              receiveTimeout: Duration(seconds: 3),
              sendTimeout: Duration(seconds: 3),
            ),
            cancelToken: testCancelToken,
            retryCount: 1,
          ); // 测试流请求
          
          final responseTime = stopwatch.elapsedMilliseconds;
          
          if (response != null && !completer.isCompleted && !testCancelToken.isCancelled) {
            LogUtil.i('流 $streamUrl 响应成功: ${responseTime}ms');
            hasValidResponse = true;
            
            if (!testCancelToken.isCancelled) {
              testCancelToken.cancel('找到可用流');
            }
            
            if (!completer.isCompleted) {
              completer.complete(streamUrl); // 返回可用流
            }
            return true;
          }
        } catch (e) {
          if (!testCancelToken.isCancelled) {
            LogUtil.e('测试流 $streamUrl 出错: $e');
          }
        } finally {
          inProgressStreams.remove(streamUrl);
          
          if (!completer.isCompleted && pendingStreams.isNotEmpty) {
            final nextUrl = pendingStreams.removeAt(0);
            testStream(nextUrl); // 启动下一个测试
          } else if (inProgressStreams.isEmpty && pendingStreams.isEmpty && !completer.isCompleted) {
            LogUtil.i('所有流测试完成但未找到可用流');
            completer.complete('ERROR'); // 无可用流
          }
        }
        
        return false;
      }
      
      final initialBatchSize = min(maxConcurrentTests, streams.length);
      for (int i = 0; i < initialBatchSize; i++) {
        if (pendingStreams.isNotEmpty) {
          final url = pendingStreams.removeAt(0);
          testStream(url); // 启动初始测试
        }
      }
      
      return await completer.future; // 返回测试结果
    } finally {
      testTimeoutTimer?.cancel(); // 取消超时计时器
    }
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
