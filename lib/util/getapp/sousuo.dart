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
  static const String searchKeyword = 'searchKeyword';
  static const String activeEngine = 'activeEngine';
  static const String searchSubmitted = 'searchSubmitted';
  static const String startTimeMs = 'startTimeMs';
  static const String engineSwitched = 'engineSwitched';
  static const String primaryEngineLoadFailed = 'primaryEngineLoadFailed';
  static const String lastHtmlLength = 'lastHtmlLength';
  static const String extractionCount = 'extractionCount';
  static const String stage = 'stage';
  static const String stage1StartTime = 'stage1StartTime';
  static const String stage2StartTime = 'stage2StartTime';
}

/// 解析会话类 - 处理解析逻辑和状态管理
class _ParserSession {
  final Completer<String> completer = Completer<String>();
  final List<String> foundStreams = [];
  WebViewController? controller;
  Timer? contentChangeDebounceTimer;
  
  // 状态标记
  bool isResourceCleaned = false;
  bool isTestingStarted = false;
  bool isExtractionInProgress = false;
  
  // 修改1: 提取触发标记 - 从静态变量改为实例变量，解决多实例并发问题
  bool extractionTriggered = false;
  
  // 新增：收集完成检测
  bool isCollectionFinished = false;
  Timer? noMoreChangesTimer;
  
  // 状态对象
  final Map<String, dynamic> searchState = {
    StateKeys.searchKeyword: '',
    StateKeys.activeEngine: 'primary',
    StateKeys.searchSubmitted: false,
    StateKeys.startTimeMs: DateTime.now().millisecondsSinceEpoch,
    StateKeys.engineSwitched: false,
    StateKeys.primaryEngineLoadFailed: false,
    StateKeys.lastHtmlLength: 0,
    StateKeys.extractionCount: 0,
    StateKeys.stage: ParseStage.formSubmission,
    StateKeys.stage1StartTime: DateTime.now().millisecondsSinceEpoch,
    StateKeys.stage2StartTime: 0,
  };
  
  // 全局超时计时器
  Timer? globalTimeoutTimer;
  
  // 取消监听
  StreamSubscription? cancelListener;
  
  // 取消令牌
  final CancelToken? cancelToken;

  // 优化1: 添加资源清理锁，防止并发清理
  bool _isCleaningUp = false;
  
  // 优化2: URL缓存，用于快速查找
  final Map<String, bool> _urlCache = {};
  
  _ParserSession({this.cancelToken});
  
  /// 统一的取消检查方法 - 优化重复逻辑
  bool _checkCancelledAndHandle(String context, {bool completeWithError = true}) {
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，$context');
      if (completeWithError && !completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return true;
    }
    return false;
  }
  
  /// 设置取消监听器 - 优化使用Future而不是转换为Stream
void setupCancelListener() {
  if (cancelToken != null) {
    try {
      // 立即检查当前状态
      if (cancelToken!.isCancelled && !isResourceCleaned) {
        LogUtil.i('检测到cancelToken已是取消状态，立即清理资源');
        cleanupResources(immediate: true);
        return;
      }
      
      // 设置取消监听
      cancelToken!.whenCancel.then((_) {
        LogUtil.i('检测到取消信号，立即释放所有资源');
        if (!isResourceCleaned) {
          cleanupResources(immediate: true);
        }
      });
    } catch (e) {
      LogUtil.e('设置取消监听器出错: $e');
    }
  }
}
  
  /// 优化：添加统一的计时器管理方法，减少重复代码
  Timer _safeStartTimer(Timer? currentTimer, Duration duration, Function() callback, String timerName) {
    if (currentTimer?.isActive == true) {
      currentTimer.cancel();
      LogUtil.i('$timerName已取消');
    }
    return Timer(duration, callback);
  }

  /// 设置全局超时
  void setupGlobalTimeout() {
    // 使用优化后的计时器管理方法
    globalTimeoutTimer = _safeStartTimer(
      globalTimeoutTimer, 
      Duration(seconds: SousuoParser._timeoutSeconds), 
      () {
        LogUtil.i('全局超时触发');
        
        if (_checkCancelledAndHandle('不处理全局超时')) return;
        
        // 检查收集状态
        if (!isCollectionFinished && foundStreams.isNotEmpty) {
          LogUtil.i('全局超时触发，强制结束收集，开始测试 ${foundStreams.length} 个流');
          finishCollectionAndTest();
        }
        // 检查引擎状态
        else if (searchState[StateKeys.activeEngine] == 'primary' && searchState[StateKeys.engineSwitched] == false) {
          LogUtil.i('全局超时触发，主引擎未找到流，切换备用引擎');
          switchToBackupEngine();
        } 
        // 无可用流，返回错误
        else {
          LogUtil.i('全局超时触发，无可用流');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            cleanupResources();
          }
        }
      },
      '全局超时计时器'
    );
  }
  
  /// 完成收集并开始测试
  void finishCollectionAndTest() {
    // 增加取消检查，确保任务未取消才执行
    if (_checkCancelledAndHandle('不执行收集完成', completeWithError: false)) return;
    
    if (isCollectionFinished || isTestingStarted) {
      return;
    }
    
    isCollectionFinished = true;
    LogUtil.i('收集完成，准备测试 ${foundStreams.length} 个流地址');
    
    // 取消所有检测计时器
    noMoreChangesTimer?.cancel();
    noMoreChangesTimer = null;
    
    // 开始测试
    startStreamTesting();
  }
  
  /// 设置无更多变化的检测计时器
  void setupNoMoreChangesDetection() {
    // 使用优化后的计时器管理方法
    noMoreChangesTimer = _safeStartTimer(
      noMoreChangesTimer,
      Duration(seconds: 3),
      () {
        // 添加任务取消检查
        if (_checkCancelledAndHandle('不执行无变化检测', completeWithError: false)) return;
        
        if (!isCollectionFinished && foundStreams.isNotEmpty) {
          LogUtil.i('3秒内无新变化，判定收集结束');
          finishCollectionAndTest();
        }
      },
      '无更多变化检测计时器'
    );
  }
  
  /// 优化3: 改进资源清理，增加锁机制和超时处理
Future<void> cleanupResources({bool immediate = false}) async {
  // 使用双重检查锁防止并发清理
  if (_isCleaningUp || isResourceCleaned) {
    LogUtil.i('资源已清理或正在清理中，跳过');
    return;
  }
  
  // 标记清理中状态
  _isCleaningUp = true;
  
  try {
    // 快速标记资源已清理，防止并发调用
    isResourceCleaned = true;
    
    // 按优先级清理资源：先轻量级资源，后重量级资源
    // 1. 取消所有计时器(最轻量级操作)
    _cancelTimer(globalTimeoutTimer, '全局超时计时器');
    globalTimeoutTimer = null;
    
    _cancelTimer(contentChangeDebounceTimer, '内容变化防抖计时器');
    contentChangeDebounceTimer = null;
    
    _cancelTimer(noMoreChangesTimer, '无更多变化检测计时器');
    noMoreChangesTimer = null;
    
    // 2. 取消订阅监听器(中等开销操作)
    if (cancelListener != null) {
      try {
        // 添加超时处理，确保不会永久阻塞
        bool cancelled = false;
        Future.delayed(Duration(milliseconds: 500), () {
          if (!cancelled) {
            LogUtil.i('取消监听器超时');
            cancelListener = null;
          }
        });
        
        await cancelListener!.cancel();
        cancelled = true;
        LogUtil.i('取消监听器已清理');
      } catch (e) {
        LogUtil.e('取消监听器时出错: $e');
      } finally {
        cancelListener = null;
      }
    }
    
    // 3. WebView清理(最重量级操作)
    if (controller != null) {
      final tempController = controller;
      controller = null; // 立即清空引用避免重复清理
      
      try {
        // 使用超时机制，避免WebView清理阻塞
        bool webviewCleaned = false;
        
        // 先尝试加载空页面减少资源占用
        await tempController!.loadHtmlString('<html><body></body></html>')
          .timeout(Duration(milliseconds: 300), onTimeout: () {
            LogUtil.i('加载空页面超时');
            return;
          });
        
        if (!immediate) {
          // 延迟短暂时间后再释放资源
          await Future.delayed(Duration(milliseconds: 100));
          
          // 添加超时保护
          Future.delayed(Duration(milliseconds: 600), () {
            if (!webviewCleaned) {
              LogUtil.i('WebView清理超时');
            }
          });
          
          await SousuoParser._disposeWebView(tempController)
            .timeout(Duration(milliseconds: 500), onTimeout: () {
              LogUtil.i('WebView资源释放超时');
              return;
            });
          
          webviewCleaned = true;
        }
        
        LogUtil.i('WebView控制器已清理');
      } catch (e) {
        LogUtil.e('清理WebView控制器出错: $e');
      }
    }
    
    // 4. 处理未完成的Completer
    try {
      if (!completer.isCompleted) {
        completer.complete('ERROR');
      }
    } catch (e) {
      LogUtil.e('完成Completer时出错: $e');
    }
    
    // 清空URL缓存
    _urlCache.clear();
  } catch (e) {
    LogUtil.e('资源清理过程中出错: $e');
  } finally {
    // 确保清理标志被重置
    _isCleaningUp = false;
    LogUtil.i('所有资源清理完成');
  }
}
  
  /// 修改3: 新增统一的计时器取消方法
  void _cancelTimer(Timer? timer, String timerName) {
    if (timer != null) {
      try {
        timer.cancel();
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
  
  /// 优化4: 改进流测试策略，增加并发控制和优先级处理
  void startStreamTesting() {
    // 防止重复测试
    if (isTestingStarted) {
      LogUtil.i('已经开始测试流链接，忽略重复测试请求');
      return;
    }
    
    // 添加任务取消检查
    if (_checkCancelledAndHandle('不执行流测试', completeWithError: false)) return;
    
    // 检查是否有流可测试
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
    
    // 创建专用的测试取消令牌，确保与父级cancelToken联动
    final testCancelToken = CancelToken();
    
    // 监听父级cancelToken的取消事件
    StreamSubscription? testCancelListener;
    if (cancelToken != null) {
      // 先检查当前状态
      if (cancelToken!.isCancelled && !testCancelToken.isCancelled) {
        LogUtil.i('父级cancelToken已是取消状态，立即取消测试');
        testCancelToken.cancel('父级已取消');
      } else {
        // 使用then替代asStream，减少开销
        cancelToken!.whenCancel.then((_) {
          if (!testCancelToken.isCancelled) {
            LogUtil.i('父级cancelToken已取消，取消所有测试请求');
            testCancelToken.cancel('父级已取消');
          }
        }).catchError((e) {
          LogUtil.e('监听取消事件出错: $e');
        });
      }
    }
    
    // 使用优化的异步测试方法
    _testStreamsAsync(testCancelToken, testCancelListener);
  }
  
  /// 优化5: 改进流测试异步方法，增加并发控制
  Future<void> _testStreamsAsync(CancelToken testCancelToken, StreamSubscription? testCancelListener) async {
    try {
      // 对流进行优先级排序
      _sortStreamsByPriority();
      
      // 优化: 改进流测试策略，控制并发数量
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
      // 确保监听器始终被取消
      try {
        await testCancelListener?.cancel();
      } catch (e) {
        LogUtil.e('取消测试监听器时出错: $e');
      }
    }
  }
  
  /// 优化6: 新增带并发控制的流测试方法
  Future<String> _testStreamsWithConcurrencyControl(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR';
    
    // 优化: 控制并发数量，避免资源耗尽
    final int maxConcurrent = 3; // 最大并发请求数
    final List<String> pendingStreams = List.from(streams);
    final Completer<String> resultCompleter = Completer<String>();
    final Set<String> inProgressTests = {}; // 跟踪进行中的测试
    
    // 设置安全超时
    final timeoutTimer = Timer(Duration(seconds: 8), () {
      if (!resultCompleter.isCompleted) {
        LogUtil.i('流测试整体超时');
        resultCompleter.complete('ERROR');
      }
    });
    
    // 定义测试单个流的函数
    Future<bool> testSingleStream(String streamUrl) async {
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
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
            // 添加合理的超时设置
            receiveTimeout: Duration(seconds: 4),
            sendTimeout: Duration(seconds: 4),
          ),
          cancelToken: cancelToken,
          retryCount: 1,
        );
        
        final testTime = stopwatch.elapsedMilliseconds;
        
        if (response != null && !resultCompleter.isCompleted && !cancelToken.isCancelled) {
          LogUtil.i('流 $streamUrl 测试成功，响应时间: ${testTime}ms');
          return true;
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
    
    // 启动下一个测试
    void startNextTest() {
      // 如果已完成或没有更多流，不启动新测试
      if (resultCompleter.isCompleted || pendingStreams.isEmpty) {
        return;
      }
      
      // 如果当前测试数量小于最大并发数，启动新测试
      if (inProgressTests.length < maxConcurrent) {
        final nextStream = pendingStreams.removeAt(0);
        testSingleStream(nextStream).then((success) {
          if (success && !resultCompleter.isCompleted) {
            // 测试成功，完成整体测试并返回结果
            resultCompleter.complete(nextStream);
            // 取消其他正在进行的测试
            if (!cancelToken.isCancelled) {
              cancelToken.cancel('已找到可用流');
            }
          } else {
            // 测试失败，启动下一个
            startNextTest();
          }
        });
        
        // 如果还有流且并发数未达上限，继续启动测试
        if (pendingStreams.isNotEmpty && inProgressTests.length < maxConcurrent) {
          startNextTest();
        }
      }
    }
    
    // 初始化测试过程，启动初始批次测试
    for (int i = 0; i < maxConcurrent && i < pendingStreams.length; i++) {
      startNextTest();
    }
    
    // 等待结果并清理
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
  
  /// 优化: 新增流排序方法，优先测试m3u8格式
  void _sortStreamsByPriority() {
    if (foundStreams.isEmpty) return;
    
    try {
      // 按m3u8 > 其他优先级排序
      foundStreams.sort((a, b) {
        bool aIsM3u8 = a.toLowerCase().contains('.m3u8');
        bool bIsM3u8 = b.toLowerCase().contains('.m3u8');
        
        if (aIsM3u8 && !bIsM3u8) return -1; // a优先
        if (!aIsM3u8 && bIsM3u8) return 1;  // b优先
        return 0; // 保持原顺序
      });
      
      LogUtil.i('流地址已按优先级排序，m3u8优先');
    } catch (e) {
      LogUtil.e('排序流地址时出错: $e');
      // 出错时不影响后续流程
    }
  }
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState[StateKeys.engineSwitched] == true) {
      LogUtil.i('已切换到备用引擎，忽略');
      return;
    }
    
    await _executeAsyncOperation('切换备用引擎', () async {
      LogUtil.i('主引擎不可用，切换到备用引擎');
      searchState[StateKeys.activeEngine] = 'backup';
      searchState[StateKeys.engineSwitched] = true;
      searchState[StateKeys.searchSubmitted] = false;
      searchState[StateKeys.lastHtmlLength] = 0;
      searchState[StateKeys.extractionCount] = 0;
      
      searchState[StateKeys.stage] = ParseStage.formSubmission;
      searchState[StateKeys.stage1StartTime] = DateTime.now().millisecondsSinceEpoch;
      
      // 修改6: 使用实例变量而不是静态变量
      extractionTriggered = false;
      
      // 重置收集状态
      isCollectionFinished = false;
      noMoreChangesTimer?.cancel();
      noMoreChangesTimer = null;
      
      // 重置全局超时
      globalTimeoutTimer?.cancel();
      
      if (controller != null) {
        try {
          await controller!.loadHtmlString('<html><body></body></html>');
          await Future.delayed(Duration(milliseconds: SousuoParser._backupEngineLoadWaitMs));
          
          await controller!.loadRequest(Uri.parse(SousuoParser._backupEngine));
          LogUtil.i('已加载备用引擎: ${SousuoParser._backupEngine}');
          
          // 设置新的全局超时
          setupGlobalTimeout();
        } catch (e) {
          LogUtil.e('加载备用引擎时出错: $e');
          throw e; // 重新抛出异常，让统一的错误处理进行处理
        }
      } else {
        LogUtil.e('WebView控制器为空，无法切换');
        throw Exception('WebView控制器为空');
      }
    });
  }
  
  /// 优化7: 优化内容变化处理，减少不必要的处理和内存分配
  void handleContentChange() {
    // 先取消现有计时器
    contentChangeDebounceTimer?.cancel();
    
    // 优化：合并重复的条件检查，减少重复评估
    // 检查任务状态，避免不必要的处理
    if (_checkCancelledAndHandle('停止处理内容变化', completeWithError: false) || 
        isCollectionFinished || 
        isTestingStarted || 
        isExtractionInProgress || 
        extractionTriggered) {
      return;
    }
    
    // 使用优化后的计时器管理方法
    contentChangeDebounceTimer = _safeStartTimer(
      contentChangeDebounceTimer,
      Duration(milliseconds: SousuoParser._contentChangeDebounceMs),
      () async {
        // 再次检查状态，防止在延迟期间状态变化
        if (controller == null || 
            completer.isCompleted || 
            _checkCancelledAndHandle('取消内容处理', completeWithError: false) ||
            isCollectionFinished || 
            isTestingStarted) {
          return;
        }
        
        // 标记提取进行中，防止并发提取
        isExtractionInProgress = true;
        
        try {
          if (searchState[StateKeys.searchSubmitted] == true && 
              !completer.isCompleted && 
              !isTestingStarted) {
            
            // 修改8: 使用实例变量而不是静态变量
            extractionTriggered = true;
            
            int beforeExtractCount = foundStreams.length;
            bool isBackupEngine = searchState[StateKeys.activeEngine] == 'backup';
            
            // 优化: 传递URL缓存到提取方法，加速URL去重
            await SousuoParser._extractMediaLinks(
              controller!, 
              foundStreams, 
              isBackupEngine,
              lastProcessedLength: searchState[StateKeys.lastHtmlLength],
              urlCache: _urlCache  // 传递URL缓存
            );
            
            try {
              final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length');
              searchState[StateKeys.lastHtmlLength] = int.tryParse(result.toString()) ?? 0;
            } catch (e) {
              LogUtil.e('获取HTML长度时出错: $e');
              // 确保状态一致性
              extractionTriggered = false;
            }
            
            // 防止取消状态下继续执行
            if (_checkCancelledAndHandle('提取后取消处理', completeWithError: false)) {
              isExtractionInProgress = false;
              return;
            }
            
            searchState[StateKeys.extractionCount] = searchState[StateKeys.extractionCount] + 1;
            int afterExtractCount = foundStreams.length;
            
            if (afterExtractCount > beforeExtractCount) {
              LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接，当前总数: ${afterExtractCount}');
              
              // 修改9: 使用实例变量而不是静态变量
              extractionTriggered = false;
              
              // 设置或重置无更多变化检测
              setupNoMoreChangesDetection();
              
              // 检查是否达到最大数量
              if (afterExtractCount >= SousuoParser._maxStreams) {
                LogUtil.i('达到最大链接数 ${SousuoParser._maxStreams}，完成收集');
                finishCollectionAndTest();
              }
            } else if (searchState[StateKeys.activeEngine] == 'primary' && 
                      afterExtractCount == 0 && 
                      searchState[StateKeys.engineSwitched] == false) {
              // 修改10: 使用实例变量而不是静态变量
              extractionTriggered = false;
              LogUtil.i('主引擎无链接，切换备用引擎，重置提取标记');
              switchToBackupEngine();
            } else {
              // 如果没有新增链接，继续等待
              // 修改11: 使用实例变量而不是静态变量
              extractionTriggered = false;
              
              // 如果已有地址，设置无更多变化检测
              if (afterExtractCount > 0) {
                setupNoMoreChangesDetection();
              }
            }
          } else {
            // 确保在所有分支中重置提取标记
            extractionTriggered = false;
          }
        } catch (e) {
          LogUtil.e('处理内容变化时出错: $e');
          // 确保出错时也重置提取标记
          extractionTriggered = false;
        } finally {
          // 确保标记被重置，避免死锁
          isExtractionInProgress = false;
        }
      },
      '内容变化防抖计时器'
    );
  }
  
  /// 注入表单检测脚本 - 修改：立即开始检测，定期扫描
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return;
    try {
      // 对搜索关键词进行安全转义
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      
      await controller!.runJavaScript('''
        (function() {
          console.log("开始注入表单检测脚本");
          
          // 定义常量：扫描间隔时间（毫秒）
          const FORM_CHECK_INTERVAL_MS = 500;  // 常量化，每500毫秒扫描一次
          
          // 存储检查状态
          window.__formCheckState = {
            formFound: false,
            checkInterval: null,
            searchKeyword: "$escapedKeyword",
            lastCheckTime: Date.now()
          };
          
          // 添加全局执行标志，防止重复执行模拟人类行为
          window.__humanBehaviorSimulationRunning = false;
          
          // 强制清理所有可能存在的检查定时器
          function clearAllFormCheckInterval() {
            // 清理当前状态的定时器
            if (window.__formCheckState.checkInterval) {
              clearInterval(window.__formCheckState.checkInterval);
              window.__formCheckState.checkInterval = null;
              console.log("停止表单检测");
            }
            
            // 尝试清理所有可能的相关定时器
            try {
              // 清理所有interval
              if (window.__allFormIntervals) {
                window.__allFormIntervals.forEach(id => clearInterval(id));
                window.__allFormIntervals = [];
              }
            } catch (e) {
              console.log("清理旧定时器失败:" + e);
            }
          }
          
          // 定义人类行为模拟常量
          const MOUSE_MOVEMENT_STEPS = 5;        // 鼠标移动步数（次数）
          const MOUSE_MOVEMENT_OFFSET = 8;       // 鼠标移动偏移量（像素）
          const MOUSE_MOVEMENT_DELAY_MS = 30;    // 鼠标移动延迟（毫秒）
          const MOUSE_HOVER_TIME_MS = 200;       // 鼠标悬停时间（毫秒）
          const MOUSE_PRESS_TIME_MS = 200;       // 鼠标按压时间（毫秒）
          const ACTION_DELAY_MS = 1000;          // 操作间隔时间（毫秒）
          
          // 优化8: 提取通用事件创建函数减少代码重复
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
          
          // 改进后的模拟真人行为函数
          function simulateHumanBehavior(searchKeyword) {
            return new Promise((resolve) => {
              // 检查是否已在运行，防止重复执行
              if (window.__humanBehaviorSimulationRunning) {
                console.log("模拟真人行为已在运行中，跳过此次执行");
                if (window.AppChannel) {
                  window.AppChannel.postMessage("模拟真人行为已在运行中，跳过");
                }
                return resolve(false);
              }
              
              // 设置运行标志
              window.__humanBehaviorSimulationRunning = true;
              
              if (window.AppChannel) {
                window.AppChannel.postMessage('开始模拟真人行为');
              }
              
              // 获取搜索输入框
              const searchInput = document.getElementById('search');
              
              if (!searchInput) {
                console.log("未找到搜索输入框");
                if (window.AppChannel) {
                  window.AppChannel.postMessage("未找到搜索输入框");
                }
                window.__humanBehaviorSimulationRunning = false; // 重置标志
                return resolve(false);
              }
              
              // 跟踪上一次点击的位置，用于模拟鼠标移动
              let lastX = window.innerWidth / 2;
              let lastY = window.innerHeight / 2;
              
              // 获取输入框的位置和大小
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
              
              // 模拟鼠标移动轨迹，使用固定步数和固定延迟
              async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
                const steps = MOUSE_MOVEMENT_STEPS; // 固定步数
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("开始移动鼠标");
                }
                
                for (let i = 0; i < steps; i++) {
                  const progress = i / steps;
                  // 使用固定偏移量
                  const offsetX = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET;
                  const offsetY = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET;
                  
                  const curX = fromX + (toX - fromX) * progress + offsetX;
                  const curY = fromY + (toY - fromY) * progress + offsetY;
                  
                  // 使用通用函数创建事件
                  const mousemoveEvent = createMouseEvent('mousemove', curX, curY);
                  
                  const elementAtPoint = document.elementFromPoint(curX, curY);
                  if (elementAtPoint) {
                    elementAtPoint.dispatchEvent(mousemoveEvent);
                  } else {
                    document.body.dispatchEvent(mousemoveEvent);
                  }
                  
                  await new Promise(r => setTimeout(r, MOUSE_MOVEMENT_DELAY_MS)); // 固定延迟
                }
                
                if (window.AppChannel) {
                  window.AppChannel.postMessage("完成鼠标移动");
                }
              }
              
              // 模拟鼠标悬停，使用固定时间
              async function simulateHover(targetElement, x, y) {
                return new Promise((hoverResolve) => {
                  try {
                    // 使用通用函数创建事件
                    const mouseoverEvent = createMouseEvent('mouseover', x, y);
                    targetElement.dispatchEvent(mouseoverEvent);
                    
                    // 固定悬停时间
                    const hoverTime = MOUSE_HOVER_TIME_MS;
                    
                    setTimeout(() => {
                      hoverResolve();
                    }, hoverTime);
                  } catch (e) {
                    console.log("悬停操作出错: " + e);
                    hoverResolve();
                  }
                });
              }
              
              // 完整的点击操作，使用固定按压时间
              async function simulateClick(targetElement, x, y) {
                return new Promise((clickResolve) => {
                  try {
                    // 创建并触发mousedown事件
                    const mousedownEvent = createMouseEvent('mousedown', x, y, 1);
                    targetElement.dispatchEvent(mousedownEvent);
                    
                    // 固定按压时间
                    const pressTime = MOUSE_PRESS_TIME_MS;
                    
                    // 持续按压一段时间后释放
                    setTimeout(() => {
                      // 创建并触发mouseup事件
                      const mouseupEvent = createMouseEvent('mouseup', x, y, 0);
                      targetElement.dispatchEvent(mouseupEvent);
                      
                      // 创建并触发click事件
                      const clickEvent = createMouseEvent('click', x, y);
                      targetElement.dispatchEvent(clickEvent);
                      
                      // 如果目标是输入框，确保获得焦点
                      if (targetElement === searchInput) {
                        searchInput.focus();
                      }
                      
                      // 更新最后点击位置
                      lastX = x;
                      lastY = y;
                      
                      // 解析点击操作完成
                      clickResolve();
                    }, pressTime);
                    
                  } catch (e) {
                    console.log("点击操作出错: " + e);
                    if (window.AppChannel) {
                      window.AppChannel.postMessage("点击操作出错: " + e);
                    }
                    clickResolve(); // 即使出错也继续流程
                  }
                });
              }
              
              // 获取输入框或输入框上方随机位置，并点击
              async function clickTarget(isInputBox) {
                try {
                  const pos = getInputPosition();
                  let targetX, targetY, elementDescription;
                  let targetElement = null;
                  
                  if (isInputBox) {
                    // 输入框内部位置 (居中位置)
                    targetX = pos.left + pos.width * 0.5;
                    targetY = pos.top + pos.height * 0.5;
                    elementDescription = "输入框";
                    
                    // 输入框肯定是有效元素
                    targetElement = searchInput;
                  } else {
                    // 输入框上方25px的固定位置
                    targetX = pos.left + pos.width * 0.5; // 输入框宽度中心
                    targetY = Math.max(pos.top - 25, 5); // 上方25px，确保不小于5px
                    elementDescription = "输入框上方空白处";
                    
                    // 尝试获取该位置的元素
                    targetElement = document.elementFromPoint(targetX, targetY);
                    
                    // 确保我们找到有效元素，如果没有则稍微调整位置
                    if (!targetElement) {
                      // 尝试向下移动一点
                      for (let attempt = 1; attempt <= 5; attempt++) {
                        // 每次往下移动2px
                        targetY += 2;
                        targetElement = document.elementFromPoint(targetX, targetY);
                        if (targetElement) break;
                      }
                      
                      // 如果仍然没找到，使用body
                      if (!targetElement) {
                        console.log("未在指定位置找到元素，使用body");
                        targetElement = document.body;
                      }
                    }
                  }
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击" + elementDescription);
                  }
                  
                  // 先移动鼠标到目标位置
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                  
                  // 短暂悬停
                  await simulateHover(targetElement, targetX, targetY);
                  
                  // 执行点击操作
                  await simulateClick(targetElement, targetX, targetY);
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击" + elementDescription + "完成");
                  }
                  
                  return true;
                } catch (e) {
                  console.log("点击操作出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击操作出错: " + e);
                  }
                  return false;
                }
              }
              
              // 填写搜索关键词
              async function fillSearchInput() {
                try {
                  // 先清空输入框
                  searchInput.value = '';
                  
                  // 填写整个关键词
                  searchInput.value = searchKeyword;
                  
                  // 触发input事件
                  const inputEvent = new Event('input', { bubbles: true, cancelable: true });
                  searchInput.dispatchEvent(inputEvent);
                  
                  // 触发change事件
                  const changeEvent = new Event('change', { bubbles: true, cancelable: true });
                  searchInput.dispatchEvent(changeEvent);
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword);
                  }
                  
                  return true;
                } catch (e) {
                  console.log("填写搜索关键词出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("填写搜索关键词出错: " + e);
                  }
                  return false;
                }
              }
              
              // 点击搜索按钮
              async function clickSearchButton() {
                try {
                  const form = document.getElementById('form1');
                  if (!form) {
                    console.log("未找到表单");
                    return false;
                  }
                  
                  // 查找提交按钮
                  const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
                  
                  if (!submitButton) {
                    console.log("未找到提交按钮，直接提交表单");
                    form.submit();
                    return true;
                  }
                  
                  // 获取按钮位置
                  const rect = submitButton.getBoundingClientRect();
                  
                  // 按钮内居中位置
                  const targetX = rect.left + rect.width * 0.5;
                  const targetY = rect.top + rect.height * 0.5;
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("准备点击搜索按钮");
                  }
                  
                  // 先移动鼠标到按钮位置
                  await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
                  
                  // 悬停在按钮上
                  await simulateHover(submitButton, targetX, targetY);
                  
                  // 执行点击操作
                  await simulateClick(submitButton, targetX, targetY);
                  
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮完成");
                  }
                  
                  return true;
                } catch (e) {
                  console.log("点击搜索按钮出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("点击搜索按钮出错: " + e);
                  }
                  
                  // 出错时尝试直接提交表单
                  try {
                    const form = document.getElementById('form1');
                    if (form) form.submit();
                  } catch (e2) {
                    console.log("备用提交方式也失败: " + e2);
                  }
                  
                  return false;
                }
              }
              
              // 执行完整的模拟操作序列，使用固定延迟
              async function executeSequence() {
                try {
                  // 1. 点击输入框本身
                  await clickTarget(true); // true表示点击输入框
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 2. 点击输入框上方空白处
                  await clickTarget(false); // false表示点击输入框上方
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 3. 再次点击输入框并输入
                  await clickTarget(true);
                  await fillSearchInput();
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 4. 点击输入框上方空白处
                  await clickTarget(false);
                  await new Promise(r => setTimeout(r, ACTION_DELAY_MS));
                  
                  // 5. 最后点击搜索按钮
                  await clickSearchButton();
                  
                  // 执行完成后重置运行标志
                  window.__humanBehaviorSimulationRunning = false;
                  
                  resolve(true);
                } catch (e) {
                  console.log("模拟序列执行出错: " + e);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage("模拟序列执行出错: " + e);
                  }
                  // 确保标志被重置
                  window.__humanBehaviorSimulationRunning = false;
                  resolve(false);
                }
              }
              
              // 开始执行模拟序列
              executeSequence();
            });
          }
          
          // 修改后的表单提交流程，直接使用模拟真人行为函数
          async function submitSearchForm() {
            console.log("准备提交搜索表单");
            
            const form = document.getElementById('form1'); // 所有引擎统一使用相同ID选择器
            const searchInput = document.getElementById('search'); // 所有引擎统一使用相同ID选择器
            
            if (!form || !searchInput) {
              console.log("未找到有效的表单元素");
              // 记录页面状态，方便调试
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
            
            console.log("找到表单和输入框");
            
            // 执行模拟真人行为（包含所有所需步骤）
            try {
              console.log("开始模拟真人行为");
              const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);
              
              if (result) {
                console.log("模拟真人行为成功");
                
                // 通知Flutter表单已提交
                if (window.AppChannel) {
                  setTimeout(function() {
                    window.AppChannel.postMessage('FORM_SUBMITTED');
                  }, 300);
                }
                
                return true;
              } else {
                console.log("模拟真人行为失败，尝试常规提交");
                
                // 尝试常规提交方式
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
                  console.log("备用提交方式也失败: " + e2);
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  }
                  return false;
                }
              }
            } catch (e) {
              console.log("模拟行为失败: " + e);
              
              // 即使模拟行为失败，我们也继续提交表单
              if (window.AppChannel) {
                window.AppChannel.postMessage('SIMULATION_FAILED');
              }
              
              // 尝试常规提交方式
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
                console.log("备用提交方式也失败: " + e2);
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                }
                return false;
              }
            }
          }
          
          // 修改: 改进表单检测函数，支持更早的检测
          function checkFormElements() {
            // 如果表单已找到或模拟行为正在执行，跳过此次检查
            if (window.__formCheckState.formFound || window.__humanBehaviorSimulationRunning) {
              console.log("表单已找到或模拟行为正在执行，跳过此次检查");
              return;
            }
            
            // 记录每次检查的时间
            const currentTime = Date.now();
            console.log("[" + (currentTime - window.__formCheckState.lastCheckTime) + "ms] 执行表单检查...");
            window.__formCheckState.lastCheckTime = currentTime;
            
            // 检查表单元素
            const form = document.getElementById('form1');
            const searchInput = document.getElementById('search');
            
            // 记录DOM状态
            const forms = document.querySelectorAll('form');
            const inputs = document.querySelectorAll('input');
            console.log("页面状态 - 表单总数:", forms.length, "输入框总数:", inputs.length);
            
            if (form && searchInput) {
              console.log("找到表单元素! 立即执行提交流程");
              window.__formCheckState.formFound = true;
              clearAllFormCheckInterval();  // 清理所有定时器
              
              // 使用立即执行的异步函数包装
              (async function() {
                try {
                  const result = await submitSearchForm();
                  if (result) {
                    console.log("表单处理成功");
                  } else {
                    console.log("表单处理失败");
                    
                    // 通知Flutter表单处理失败
                    if (window.AppChannel) {
                      window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                    }
                  }
                } catch (e) {
                  console.log("表单提交异常: " + e);
                  
                  // 通知Flutter表单处理失败
                  if (window.AppChannel) {
                    window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                  }
                }
              })();
            } else {
              // 记录缺失的元素
              if (!form) console.log("未找到form元素");
              if (!searchInput) console.log("未找到search输入框");
            }
          }
          
          // 立即清理旧定时器
          clearAllFormCheckInterval();
          
          // 记录所有新创建的interval id
          if (!window.__allFormIntervals) {
            window.__allFormIntervals = [];
          }
          
          // 创建新的定时检查
          console.log("使用常量间隔 " + FORM_CHECK_INTERVAL_MS + "ms 开始定时检查表单元素");
          const intervalId = setInterval(checkFormElements, FORM_CHECK_INTERVAL_MS);
          
          // 保存interval id用于后续清理
          window.__formCheckState.checkInterval = intervalId;
          window.__allFormIntervals.push(intervalId);
          
          // 立即执行第一次检查（无延迟）
          checkFormElements();
          
          // 防止页面状态不稳定，再次检查
          setTimeout(checkFormElements, 100);  // 100ms后再检查一次
          setTimeout(checkFormElements, 200);  // 200ms后再检查一次
        })();
      ''');
      
      LogUtil.i('表单检测脚本注入成功，立即开始定期扫描');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    if (_checkCancelledAndHandle('中断导航', completeWithError: false)) return;
    
    // 修改点1: 添加表单提交状态检查，避免在结果页注入表单检测脚本
    if (pageUrl != 'about:blank' && searchState[StateKeys.searchSubmitted] == false) {
      // 确保searchKeyword已设置，使用默认值防止空值
      String searchKeyword = searchState[StateKeys.searchKeyword] ?? '';
      if (searchKeyword.isEmpty) {
        LogUtil.i('搜索关键词为空，尝试从URL获取');
        try {
          final uri = Uri.parse(pageUrl);
          searchKeyword = uri.queryParameters['clickText'] ?? '';
        } catch (e) {
          LogUtil.e('从URL解析搜索关键词失败: $e');
        }
      }
      
      LogUtil.i('页面开始加载，立即注入表单检测脚本');
      await injectFormDetectionScript(searchKeyword);
    } else if (searchState[StateKeys.searchSubmitted] == true) {
      LogUtil.i('表单已提交，跳过注入表单检测脚本');
    }
    
    // 检查是否已切换到备用引擎但尝试加载主引擎
    if (searchState[StateKeys.engineSwitched] == true && 
        SousuoParser._isPrimaryEngine(pageUrl) && 
        controller != null) {
      LogUtil.i('已切换备用引擎，中断主引擎加载');
      try {
        await controller!.loadHtmlString('<html><body></body></html>');
      } catch (e) {
        LogUtil.e('中断主引擎加载时出错: $e');
      }
      return;
    }
  }
  
  /// 处理导航事件 - 页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    if (_checkCancelledAndHandle('不处理页面完成事件', completeWithError: false)) return;
    
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = searchState[StateKeys.startTimeMs] as int;
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
    
    if (searchState[StateKeys.engineSwitched] == true && isPrimaryEngine) {
      LogUtil.i('已切换备用引擎，忽略主引擎');
      return;
    }
    
    if (isPrimaryEngine) {
      searchState[StateKeys.activeEngine] = 'primary';
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) {
      searchState[StateKeys.activeEngine] = 'backup';
      LogUtil.i('备用引擎页面加载完成');
    }
    
    // 页面加载完成后，即使表单已提交，也可能需要重新检测
    // 但只在特定条件下重新注入
    if (searchState[StateKeys.searchSubmitted] == true) {
      // 修改12: 使用实例变量而不是静态变量
      if (!isExtractionInProgress && !isTestingStarted && !extractionTriggered && !isCollectionFinished) {
        // 增加取消检查，确保任务未取消才执行延迟触发
        if (_checkCancelledAndHandle('不执行延迟内容变化处理', completeWithError: false)) return;
          
        Timer(Duration(milliseconds: 500), () {
          if (controller != null && 
              !completer.isCompleted && 
              !cancelToken!.isCancelled && 
              !isCollectionFinished) {
            handleContentChange();
          }
        });
      }
    }
  }
  
  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (_checkCancelledAndHandle('不处理资源错误', completeWithError: false)) return;
    
    LogUtil.e('资源错误: ${error.description}, 错误码: ${error.errorCode}');
    
    // 忽略一些非关键资源的错误
    if (error.url == null || 
        error.url!.endsWith('.png') || 
        error.url!.endsWith('.jpg') || 
        error.url!.endsWith('.gif') || 
        error.url!.endsWith('.webp') || 
        error.url!.endsWith('.css')) {
      return;
    }
    
    // 主引擎出现关键错误时切换到备用引擎
    if (searchState[StateKeys.activeEngine] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) {
      
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode);
      
      if (isCriticalError) {
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState[StateKeys.primaryEngineLoadFailed] = true;
        
        if (searchState[StateKeys.searchSubmitted] == false && searchState[StateKeys.engineSwitched] == false) {
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
    
    // 如果已切换到备用引擎，阻止主引擎导航
    if (searchState[StateKeys.engineSwitched] == true && SousuoParser._isPrimaryEngine(request.url)) {
      LogUtil.i('阻止主引擎导航');
      return NavigationDecision.prevent;
    }
    
    // 阻止加载非必要资源，提高性能
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
  
  /// 处理JavaScript消息
  void handleJavaScriptMessage(JavaScriptMessage message) {
    if (_checkCancelledAndHandle('不处理JS消息', completeWithError: false)) return;
    
    LogUtil.i('收到消息: ${message.message}');
    
    if (controller == null) {
      LogUtil.e('控制器为空，无法处理消息');
      return;
    }
    
    if (message.message.startsWith('点击输入框上方') || 
        message.message.startsWith('点击body') ||
        message.message.startsWith('点击了随机元素') ||
        message.message.startsWith('点击页面随机位置') ||
        message.message.startsWith('填写后点击')) {
    }
    else if (message.message == 'FORM_SUBMITTED') {
      searchState[StateKeys.searchSubmitted] = true;
      
      searchState[StateKeys.stage] = ParseStage.searchResults;
      searchState[StateKeys.stage2StartTime] = DateTime.now().millisecondsSinceEpoch;
      
      // 注入DOM监听器前先检查取消状态
      if (_checkCancelledAndHandle('不注入DOM监听器', completeWithError: false)) return;
      
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel');
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      
      if (searchState[StateKeys.activeEngine] == 'primary' && searchState[StateKeys.engineSwitched] == false) {
        LogUtil.i('主引擎表单处理失败，切换备用引擎');
        switchToBackupEngine();
      }
    } else if (message.message == 'SIMULATION_FAILED') {
      LogUtil.e('模拟真人行为失败');
    } else if (message.message.startsWith('模拟真人行为') ||
                message.message.startsWith('点击了搜索输入框') ||
                message.message.startsWith('填写了搜索关键词') ||
                message.message.startsWith('点击提交按钮')) {
    } else if (message.message == 'CONTENT_CHANGED') {
      handleContentChange();
    }
  }
  
  /// 开始解析流程 - 优化异常处理和资源管理
  Future<String> startParsing(String url) async {
    try {
      if (_checkCancelledAndHandle('不执行解析')) {
        return 'ERROR';
      }
      
      setupCancelListener();
      
      // 设置全局超时
      setupGlobalTimeout();
      
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      searchState[StateKeys.searchKeyword] = searchKeyword;
      
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      
      await controller!.setNavigationDelegate(NavigationDelegate(
        onPageStarted: handlePageStarted,
        onPageFinished: handlePageFinished,
        onWebResourceError: handleWebResourceError,
        onNavigationRequest: handleNavigationRequest,
      ));
      
      await controller!.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: handleJavaScriptMessage,
      );
      
      try {
        await controller!.loadRequest(Uri.parse(SousuoParser._primaryEngine));
        LogUtil.i('页面加载请求已发出');
      } catch (e) {
        LogUtil.e('页面加载请求失败: $e');
        
        if (searchState[StateKeys.engineSwitched] == false) {
          LogUtil.i('主引擎加载失败，准备切换备用引擎');
          switchToBackupEngine();
        }
      }
      
      final result = await completer.future;
      LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
      
      int endTimeMs = DateTime.now().millisecondsSinceEpoch;
      int startMs = searchState[StateKeys.startTimeMs] as int;
      LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
      
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('解析失败', e, stackTrace);
      
      if (foundStreams.isNotEmpty && !completer.isCompleted) {
        LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
        try {
          // 优化: 对流进行排序，优先测试m3u8格式
          _sortStreamsByPriority();
          
          // 使用优化的测试方法，控制并发
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

/// 电视直播源搜索引擎解析器 
class SousuoParser {
  // 搜索引擎URLs
  static const String _primaryEngine = 'https://tonkiang.us/?'; // 主搜索引擎URL
  static const String _backupEngine = 'http://www.foodieguide.com/iptvsearch/'; // 备用引擎URL
  
  // 通用配置
  static const int _timeoutSeconds = 28; // 统一超时时间 - 适用于表单检测和DOM变化检测
  static const int _maxStreams = 8; // 最大提取的媒体流数量
  
  // 时间常量 - 页面和DOM相关
  static const int _waitSeconds = 2; // 页面加载和提交后等待时间
  static const int _domChangeWaitMs = 500; // DOM变化后等待时间
  
  // 时间常量 - 测试和清理相关
  static const int _flowTestWaitMs = 500; // 流测试等待时间
  static const int _backupEngineLoadWaitMs = 300; // 切换备用引擎前等待时间
  static const int _cleanupRetryWaitMs = 300; // 清理重试等待时间
  
  // 内容检查相关常量
  static const int _minValidContentLength = 1000; // 最小有效内容长度
  static const double _significantChangePercent = 5.0; // 显著内容变化百分比 - 从10%改为5%，提高敏感度
  
  // 内容变化防抖时间(毫秒)
  static const int _contentChangeDebounceMs = 300;

  // 添加屏蔽关键词列表
  static List<String> _blockKeywords = ["freetv.fun", "epg.pw"];

  // 优化：预编译正则表达式，避免频繁创建
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false
  );

  // 新增：预编译m3u8检测正则表达式
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false);

  /// 设置屏蔽关键词的方法
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      LogUtil.i('设置屏蔽关键词: ${_blockKeywords.join(', ')}');
    } else {
      _blockKeywords = [];
    }
  }

  /// 清理WebView资源 - 优化版，确保异常处理
  static Future<void> _disposeWebView(WebViewController controller) async {
    try {
      await controller.clearLocalStorage(); // 清除本地存储
      await controller.clearCache(); // 清除缓存
      LogUtil.i('清理WebView完成');
    } catch (e) {
      LogUtil.e('清理WebView出错: $e');
      // 继续执行，不抛出异常，确保清理过程不会中断
    }
  }
  
  /// 检查URL是否为主引擎
  static bool _isPrimaryEngine(String url) {
    return url.contains('tonkiang.us');
  }

  /// 检查URL是否为备用引擎
  static bool _isBackupEngine(String url) {
    return url.contains('foodieguide.com');
  }
  
  /// 注入DOM变化监听器 - 优化实现，减少页面性能开销
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
          
          // 优化的内容变化通知函数 - 使用防抖动减少不必要的通知
          const notifyContentChange = function() {
            if (debounceTimeout) {
              clearTimeout(debounceTimeout);
            }
            
            debounceTimeout = setTimeout(function() {
              const now = Date.now();
              // 检查距离上次通知的时间是否足够长
              if (now - lastNotificationTime < 1000) {
                return; // 忽略过于频繁的通知
              }
              
              // 获取当前内容长度
              const currentContentLength = document.body.innerHTML.length;
              
              // 计算内容变化百分比
              const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;
              
              // 只有变化超过阈值时才通知
              if (changePercent > ${_significantChangePercent}) {
                console.log("检测到显著内容变化: " + changePercent.toFixed(2) + "%");
                
                // 更新状态
                lastNotificationTime = now;
                lastContentLength = currentContentLength;
                
                // 通知应用内容变化
                ${channelName}.postMessage('CONTENT_CHANGED');
              }
              
              debounceTimeout = null;
            }, 200); // 200ms防抖动延迟
          };
          
          // 创建性能优化的MutationObserver
          const observer = new MutationObserver(function(mutations) {
            // 快速检查是否有相关变化
            let hasRelevantChanges = false;
            
            // 只检查有意义的变化
            for (let i = 0; i < mutations.length; i++) {
              const mutation = mutations[i];
              
              // 检查是否为内容或结构变化
              if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                // 检查添加的节点是否包含实质性内容
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
            
            // 只有检测到相关变化时才触发通知
            if (hasRelevantChanges) {
              notifyContentChange();
            }
          });
          
          // 配置观察者 - 只观察必要的变化
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: false,
            characterData: false
          });
          
          // 页面加载后延迟检查一次内容
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
      ''');
    } catch (e, stackTrace) {
      LogUtil.logError('注入监听器出错', e, stackTrace);
    }
  }
  
  /// 提交搜索表单
  static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
     await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面	
    try {
      // 对搜索关键词进行安全转义
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      
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
      
      await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面
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
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase()));
  }

  /// 优化: 改进HTML字符串清理方法，减少字符串复制和内存分配
  static String _cleanHtmlString(String htmlContent) {
    // 快速检查不需要清理的情况
    if (htmlContent.length < 3 || !htmlContent.startsWith('"') || !htmlContent.endsWith('"')) {
      return htmlContent;
    }
    
    // 预分配合适容量的StringBuffer，减少内部扩容操作
    final buffer = StringBuffer(htmlContent.length);
    final innerContent = htmlContent.substring(1, htmlContent.length - 1);
    
    // 一次遍历完成所有替换，避免多次字符串创建
    int i = 0;
    while (i < innerContent.length) {
      if (i < innerContent.length - 1 && innerContent[i] == '\\') {
        final nextChar = innerContent[i + 1];
        if (nextChar == '"') {
          buffer.write('"');
          i += 2; // 跳过转义序列
        } else if (nextChar == 'n') {
          buffer.write('\n');
          i += 2; // 跳过转义序列
        } else if (nextChar == 't') {
          buffer.write('\t');
          i += 2; // 跳过转义序列
        } else if (nextChar == '\\') {
          buffer.write('\\');
          i += 2; // 跳过转义序列
        } else {
          buffer.write(innerContent[i++]);
        }
      } else {
        buffer.write(innerContent[i++]);
      }
    }
    
    return buffer.toString();
  }
  
  /// 优化: 提取媒体链接 - 改进版，更高效的URL处理和缓存
  static Future<void> _extractMediaLinks(
    WebViewController controller, 
    List<String> foundStreams, 
    bool usingBackupEngine, 
    {int lastProcessedLength = 0, 
     Map<String, bool>? urlCache}
  ) async {
    LogUtil.i('从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
    
    try {
      // 获取页面HTML
      final html = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML'
      );
      
      // 处理HTML字符串
      String htmlContent = _cleanHtmlString(html.toString());
      final int contentLength = htmlContent.length;
      LogUtil.i('获取HTML，长度: $contentLength');
      
      // 仅当HTML内容有实质变化时才进行处理
      if (lastProcessedLength > 0 && contentLength <= lastProcessedLength) {
        LogUtil.i('内容长度未增加，跳过提取');
        return;
      }
      
      // 使用预编译的正则表达式提取链接
      final matches = _mediaLinkRegex.allMatches(htmlContent);
      final int totalMatches = matches.length;
      
      // 如果有匹配项，记录示例并直接内联打印
      if (totalMatches > 0) {
        final firstMatch = matches.first;
        LogUtil.i('示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(1)}');
      }
      
      // 优化: 使用或创建URL缓存
      final Map<String, bool> hostMap = urlCache ?? {};
      
      // 如果没有传入缓存但有已存在的流，从中构建缓存
      if (urlCache == null && foundStreams.isNotEmpty) {
        for (final url in foundStreams) {
          try {
            final uri = Uri.parse(url);
            hostMap['${uri.host}:${uri.port}'] = true;
          } catch (_) {
            // 处理无效URL
            hostMap[url] = true;
          }
        }
      }
      
      // 分类存储链接
      final List<String> m3u8Links = [];
      final List<String> otherLinks = [];
      
      // 处理匹配的URL
      for (final match in matches) {
        if (match.groupCount >= 1) {
          String? mediaUrl = match.group(1)?.trim();
          
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            // 一次性清理URL
            mediaUrl = mediaUrl
                .replaceAll('&amp;', '&')
                .replaceAll('&quot;', '"')
                .replaceAll(RegExp("[\")'&;]+\$"), '');
            
            // 检查URL是否包含屏蔽关键词
            if (_isUrlBlocked(mediaUrl)) {
              LogUtil.i('跳过包含屏蔽关键词的链接: $mediaUrl');
              continue;
            }
            
            try {
              final uri = Uri.parse(mediaUrl);
              final String hostKey = '${uri.host}:${uri.port}';
              
              // 使用URL缓存检查重复，避免重复的O(n)操作
              if (!hostMap.containsKey(hostKey)) {
                hostMap[hostKey] = true;
                
                // 优化: 直接使用预编译正则表达式检查m3u8
                if (_m3u8Regex.hasMatch(mediaUrl)) {
                  m3u8Links.add(mediaUrl);
                  LogUtil.i('提取到m3u8链接: $mediaUrl');
                } else {
                  otherLinks.add(mediaUrl);
                  LogUtil.i('提取到其他格式链接: $mediaUrl');
                }
              }
            } catch (e) {
              LogUtil.e('解析URL出错: $e, URL: $mediaUrl');
            }
          }
        }
      }
      
      // 优先添加m3u8链接，再添加其他链接
      int addedCount = 0;
      
      // 计算可添加的最大数量
      final int remainingSlots = _maxStreams - foundStreams.length;
      if (remainingSlots <= 0) {
        LogUtil.i('已达到最大链接数 $_maxStreams，不添加新链接');
        return;
      }
      
      // 添加m3u8链接
      for (final link in m3u8Links) {
        if (!foundStreams.contains(link)) { // 确保不添加重复链接
          foundStreams.add(link);
          addedCount++;
          
          if (foundStreams.length >= _maxStreams) {
            LogUtil.i('达到最大链接数 $_maxStreams，m3u8链接已足够');
            break;
          }
        }
      }
      
      // 如果m3u8链接不足，添加其他链接
      if (foundStreams.length < _maxStreams) {
        for (final link in otherLinks) {
          if (!foundStreams.contains(link)) { // 确保不添加重复链接
            foundStreams.add(link);
            addedCount++;
            
            if (foundStreams.length >= _maxStreams) {
              LogUtil.i('达到最大链接数 $_maxStreams');
              break;
            }
          }
        }
      }
      
      // 输出汇总信息
      LogUtil.i('匹配数: $totalMatches, m3u8格式: ${m3u8Links.length}, 其他格式: ${otherLinks.length}, 新增: $addedCount');
      
      // 调试输出
      if (addedCount == 0 && totalMatches == 0) {
        // 记录HTML片段和onclick属性
        int sampleLength = htmlContent.length > _minValidContentLength ? _minValidContentLength : htmlContent.length;
        String debugSample = htmlContent.substring(0, sampleLength);
        
        // 尝试找出所有onclick属性
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
  
  /// 优化: 改进流测试策略，支持并发控制和快速检测
  static Future<String> _testStreamsAndGetFastest(List<String> streams, {CancelToken? cancelToken}) async {
    if (streams.isEmpty) {
      LogUtil.i('无流地址，返回ERROR');
      return 'ERROR';
    }
    
    LogUtil.i('测试 ${streams.length} 个流地址');
    
    // 创建独立的测试取消令牌
    final testCancelToken = cancelToken ?? CancelToken();
    final completer = Completer<String>();
    bool hasValidResponse = false;
    
    // 设置测试超时计时器
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
      });
      
      // 优化: 控制并发请求数量
      const int maxConcurrentTests = 3;
      final pendingStreams = List<String>.from(streams);
      final inProgressStreams = <String>{};
      
      // 测试单个流的函数
      Future<bool> testStream(String streamUrl) async {
        if (completer.isCompleted || testCancelToken.isCancelled) {
          return false;
        }
        
        inProgressStreams.add(streamUrl);
        try {
          // 优化: 添加请求超时控制
          final stopwatch = Stopwatch()..start();
          final response = await HttpUtil().getRequestWithResponse(
            streamUrl,
            options: Options(
              headers: HeadersConfig.generateHeaders(url: streamUrl),
              method: 'GET',
              responseType: ResponseType.plain,
              followRedirects: true,
              validateStatus: (status) => status != null && status < 400,
              // 设置合理的请求超时
              receiveTimeout: Duration(seconds: 3),
              sendTimeout: Duration(seconds: 3),
            ),
            cancelToken: testCancelToken,
            retryCount: 1,
          );
          
          final responseTime = stopwatch.elapsedMilliseconds;
          
          if (response != null && !completer.isCompleted && !testCancelToken.isCancelled) {
            LogUtil.i('流 $streamUrl 响应成功: ${responseTime}ms');
            hasValidResponse = true;
            
            // 找到可用流后，取消其他测试请求
            if (!testCancelToken.isCancelled) {
              testCancelToken.cancel('找到可用流');
            }
            
            // 返回此有效流
            if (!completer.isCompleted) {
              completer.complete(streamUrl);
            }
            return true;
          }
        } catch (e) {
          if (!testCancelToken.isCancelled) {
            LogUtil.e('测试流 $streamUrl 出错: $e');
          }
        } finally {
          inProgressStreams.remove(streamUrl);
          
          // 启动下一个测试
          if (!completer.isCompleted && pendingStreams.isNotEmpty) {
            final nextUrl = pendingStreams.removeAt(0);
            testStream(nextUrl);
          } else if (inProgressStreams.isEmpty && pendingStreams.isEmpty && !completer.isCompleted) {
            // 所有测试完成但没有成功，返回错误
            LogUtil.i('所有流测试完成但未找到可用流');
            completer.complete('ERROR');
          }
        }
        
        return false;
      }
      
      // 启动初始批次测试
      final initialBatchSize = min(maxConcurrentTests, streams.length);
      for (int i = 0; i < initialBatchSize; i++) {
        if (pendingStreams.isNotEmpty) {
          final url = pendingStreams.removeAt(0);
          testStream(url);
        }
      }
      
      return await completer.future;
    } finally {
      // 确保计时器被取消
      testTimeoutTimer?.cancel();
    }
  }

  /// 解析搜索页面并提取媒体流地址
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    // 设置屏蔽关键词
    if (blockKeywords.isNotEmpty) {
      setBlockKeywords(blockKeywords);
    }
    
    // 创建解析会话并开始解析
    final session = _ParserSession(cancelToken: cancelToken);
    return await session.startParsing(url);
  }
}
