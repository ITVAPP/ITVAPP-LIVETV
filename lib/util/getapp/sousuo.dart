import 'dart:async';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:flutter/services.dart' show rootBundle; // 导入rootBundle用于读取资源文件

// 解析阶段枚举 - 移至顶层
enum ParseStage {
  formSubmission,  // 阶段1: 页面加载和表单提交
  searchResults,   // 阶段2: 搜索结果处理和流测试
  completed,       // 完成
  error            // 错误
}

/// 解析会话类 - 处理解析逻辑和状态管理
class _ParserSession {
  final Completer<String> completer = Completer<String>();
  final List<String> foundStreams = [];
  WebViewController? controller;
  bool contentChangedDetected = false;
  Timer? contentChangeDebounceTimer;
  
  // 状态标记
  bool isResourceCleaned = false;
  bool isTestingStarted = false;
  bool isExtractionInProgress = false;
  
  // 优化: 新增内容变化处理锁，避免并发处理
  bool _isProcessingContentChange = false;
  
  // 提取触发标记
  static bool _extractionTriggered = false;
  
  // 状态对象
  final Map<String, dynamic> searchState = {
    'searchKeyword': '',
    'activeEngine': 'primary',
    'searchSubmitted': false,
    'startTimeMs': DateTime.now().millisecondsSinceEpoch,
    'engineSwitched': false,
    'primaryEngineLoadFailed': false,
    'lastHtmlLength': 0,
    'extractionCount': 0,
    'stage': ParseStage.formSubmission,
    'stage1StartTime': DateTime.now().millisecondsSinceEpoch,
    'stage2StartTime': 0,
  };
  
  // 全局超时计时器
  Timer? globalTimeoutTimer;
  
  // 取消监听
  StreamSubscription? cancelListener;
  
  // 取消令牌
  final CancelToken? cancelToken;
  
  _ParserSession({this.cancelToken});
  
  /// 检查是否已取消
  bool isCancelled() {
    return cancelToken?.isCancelled ?? false;
  }
  
  /// 设置取消监听器 - 优化使用Future而不是转换为Stream
  void setupCancelListener() {
    if (cancelToken != null) {
      cancelToken!.whenCancel.then((_) {
        LogUtil.i('检测到取消信号，立即释放所有资源');
        cleanupResources(immediate: true);
      });
    }
  }
  
  /// 设置全局超时
  void setupGlobalTimeout() {
    // 清除可能存在的旧计时器
    globalTimeoutTimer?.cancel();
    
    LogUtil.i('设置全局超时: ${SousuoParser._timeoutSeconds * 2}秒');
    
    // 设置全局超时计时器
    globalTimeoutTimer = Timer(Duration(seconds: SousuoParser._timeoutSeconds * 2), () {
      LogUtil.i('全局超时触发');
      
      if (isCancelled() || completer.isCompleted) return;
      
      // 检查流的状态
      if (foundStreams.isNotEmpty) {
        LogUtil.i('全局超时触发，但已找到 ${foundStreams.length} 个流，开始测试');
        startStreamTesting();
      }
      // 检查引擎状态
      else if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
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
    });
  }
  
  /// 清理资源 - 优化版本，确保资源释放的可靠性和原子性
  Future<void> cleanupResources({bool immediate = false}) async {
    // 使用同步锁避免重复清理 - 使用本地变量捕获当前状态避免竞态条件
    final bool alreadyCleaned = isResourceCleaned;
    if (alreadyCleaned) {
      LogUtil.i('资源已清理，跳过');
      return;
    }
    
    // 立即标记为已清理，防止并发调用
    isResourceCleaned = true;
    LogUtil.i('开始清理资源');
    
    try {
      // 1. 首先取消所有计时器 - 避免后续操作被计时器中断
      await _cleanTimers();
      
      // 2. 取消订阅监听器
      await _cleanListeners();
      
      // 3. 处理WebView控制器
      await _cleanController(immediate);
      
      // 4. 确保Completer正确完成
      _completeIfNeeded();
      
      LogUtil.i('所有资源清理完成');
    } catch (e) {
      LogUtil.e('清理资源过程中出错: $e');
      
      // 确保在异常情况下也完成Completer
      _completeIfNeeded();
    }
  }
  
  /// 清理计时器 - 拆分为更小的单一职责函数
  Future<void> _cleanTimers() async {
    if (globalTimeoutTimer != null) {
      globalTimeoutTimer!.cancel();
      globalTimeoutTimer = null;
      LogUtil.i('全局超时计时器已取消');
    }
    
    if (contentChangeDebounceTimer != null) {
      contentChangeDebounceTimer!.cancel();
      contentChangeDebounceTimer = null;
      LogUtil.i('内容变化防抖计时器已取消');
    }
  }
  
  /// 清理监听器
  Future<void> _cleanListeners() async {
    if (cancelListener != null) {
      try {
        await cancelListener!.cancel();
      } catch (e) {
        LogUtil.e('取消监听器时出错: $e');
      } finally {
        cancelListener = null;
        LogUtil.i('取消监听器已清理');
      }
    }
  }
  
  /// 清理WebView控制器 - 增强错误处理
  Future<void> _cleanController(bool immediate) async {
    if (controller != null) {
      final tempController = controller; // 保存临时引用
      controller = null; // 立即清空引用避免重复清理
      
      try {
        // 尝试加载空白页面以停止当前加载
        await tempController!.loadHtmlString('<html><body></body></html>');
        
        if (!immediate) {
          // 等待短暂时间确保页面加载
          await Future.delayed(Duration(milliseconds: 100));
          // 调用WebView资源清理方法
          await SousuoParser._disposeWebView(tempController);
        }
        LogUtil.i('WebView控制器已清理');
      } catch (e) {
        LogUtil.e('清理WebView资源时出错: $e');
      }
    }
  }
  
  /// 完成Completer如果尚未完成
  void _completeIfNeeded() {
    if (!completer.isCompleted) {
      LogUtil.i('Completer未完成，强制返回ERROR');
      completer.complete('ERROR');
    }
  }
  
  /// 开始测试流链接 - 改进错误处理和资源管理
  void startStreamTesting() {
    // 防止重复测试
    if (isTestingStarted) {
      LogUtil.i('已经开始测试流链接，忽略重复测试请求');
      return;
    }
    
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
      testCancelListener = cancelToken?.whenCancel?.asStream().listen((_) {
        if (!testCancelToken.isCancelled) {
          LogUtil.i('父级cancelToken已取消，取消所有测试请求');
          testCancelToken.cancel('父级已取消');
        }
      });
    }
    
    try {
      // 改进：首先对流进行优先级排序，优先测试m3u8格式
      final prioritizedStreams = _prioritizeStreams(foundStreams);
      
      // 使用Future API的完整错误处理链
      SousuoParser._testStreamsAndGetFastest(prioritizedStreams, cancelToken: testCancelToken)
        .then((String result) {
          LogUtil.i('测试完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
          if (!completer.isCompleted) {
            completer.complete(result);
            cleanupResources();
          }
        })
        .catchError((e) {
          // 显式处理测试过程中的异常
          LogUtil.e('测试流过程中出错: $e');
          if (!completer.isCompleted) {
            completer.complete('ERROR');
            cleanupResources();
          }
        })
        .whenComplete(() {
          // 确保监听器始终被取消
          testCancelListener?.cancel();
        });
    } catch (e) {
      // 处理启动测试过程中的同步异常
      LogUtil.e('启动流测试出错: $e');
      testCancelListener?.cancel();
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
    }
  }
  
  /// 流优先级排序 - 优先测试m3u8格式
  List<String> _prioritizeStreams(List<String> streams) {
    final m3u8Streams = <String>[];
    final otherStreams = <String>[];
    
    for (final stream in streams) {
      if (stream.toLowerCase().contains('.m3u8')) {
        m3u8Streams.add(stream);
      } else {
        otherStreams.add(stream);
      }
    }
    
    // 返回排序后的列表，m3u8优先
    return [...m3u8Streams, ...otherStreams];
  }
  
  /// 切换到备用引擎
  Future<void> switchToBackupEngine() async {
    if (searchState['engineSwitched'] == true) {
      LogUtil.i('已切换到备用引擎，忽略');
      return;
    }
    
    if (isCancelled()) {
      LogUtil.i('任务已取消，不切换到备用引擎');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        await cleanupResources();
      }
      return;
    }
    
    LogUtil.i('主引擎不可用，切换到备用引擎');
    searchState['activeEngine'] = 'backup';
    searchState['engineSwitched'] = true;
    searchState['searchSubmitted'] = false;
    searchState['lastHtmlLength'] = 0;
    searchState['extractionCount'] = 0;
    
    searchState['stage'] = ParseStage.formSubmission;
    searchState['stage1StartTime'] = DateTime.now().millisecondsSinceEpoch;
    
    _extractionTriggered = false;
    
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
        if (!isResourceCleaned && !completer.isCompleted) {
          LogUtil.i('加载备用引擎失败，返回ERROR');
          completer.complete('ERROR');
          await cleanupResources();
        }
      }
    } else {
      LogUtil.e('WebView控制器为空，无法切换');
      if (!isResourceCleaned && !completer.isCompleted) {
        completer.complete('ERROR');
        await cleanupResources();
      }
    }
  }
  
  /// 处理内容变化 - 优化防抖逻辑与并发控制
  void handleContentChange() {
    // 避免重复处理导致的并发问题
    if (_isProcessingContentChange) {
      LogUtil.i('内容变化处理已在进行中，跳过');
      return;
    }
    
    // 先取消现有计时器
    contentChangeDebounceTimer?.cancel();
    
    // 检查任务状态，避免不必要的处理
    if (isCancelled()) {
      LogUtil.i('任务已取消，停止处理内容变化');
      if (!completer.isCompleted) {
        completer.complete('ERROR');
        cleanupResources();
      }
      return;
    }
    
    // 处理状态检查，避免并发提取
    if (isExtractionInProgress) {
      LogUtil.i('提取操作正在进行中，跳过此次提取');
      return;
    }
    
    if (_extractionTriggered) {
      LogUtil.i('已经触发过提取操作，跳过此次提取');
      return;
    }
    
    // 标记正在处理，防止并发
    _isProcessingContentChange = true;
    
    // 使用防抖动延迟执行内容处理
    contentChangeDebounceTimer = Timer(Duration(milliseconds: SousuoParser._contentChangeDebounceMs), () {
      _processContentChangeAfterDelay();
    });
  }
  
  /// 延迟处理内容变化 - 拆分为单独的方法提高可维护性
  Future<void> _processContentChangeAfterDelay() async {
    try {
      // 再次检查状态，防止在延迟期间状态变化
      if (controller == null || completer.isCompleted || isCancelled()) {
        _isProcessingContentChange = false;
        return;
      }
      
      // 标记提取进行中，防止并发提取
      isExtractionInProgress = true;
      
      LogUtil.i('处理页面内容变化（防抖后）');
      contentChangedDetected = true;
      
      try {
        if (searchState['searchSubmitted'] == true && !completer.isCompleted && !isTestingStarted) {
          _extractionTriggered = true;
          
          int beforeExtractCount = foundStreams.length;
          bool isBackupEngine = searchState['activeEngine'] == 'backup';
          
          await SousuoParser._extractMediaLinks(
            controller!, 
            foundStreams, 
            isBackupEngine,
            lastProcessedLength: searchState['lastHtmlLength']
          );
          
          try {
            final result = await controller!.runJavaScriptReturningResult('document.documentElement.outerHTML.length');
            searchState['lastHtmlLength'] = int.tryParse(result.toString()) ?? 0;
          } catch (e) {
            LogUtil.e('获取HTML长度时出错: $e');
          }
          
          searchState['extractionCount'] = searchState['extractionCount'] + 1;
          int afterExtractCount = foundStreams.length;
          
          if (afterExtractCount > beforeExtractCount) {
            LogUtil.i('新增 ${afterExtractCount - beforeExtractCount} 个链接');
            
            if (afterExtractCount >= SousuoParser._maxStreams) {
              LogUtil.i('达到最大链接数 ${SousuoParser._maxStreams}，开始测试');
              startStreamTesting();
            }
            else if (afterExtractCount > 0) {
              LogUtil.i('提取完成，找到 ${afterExtractCount} 个链接，立即开始测试');
              startStreamTesting();
            }
          } else if (searchState['activeEngine'] == 'primary' && 
                    afterExtractCount == 0 && 
                    searchState['engineSwitched'] == false) {
            _extractionTriggered = false;
            LogUtil.i('主引擎无链接，切换备用引擎，重置提取标记');
            switchToBackupEngine();
          }
        }
      } catch (e) {
        LogUtil.e('处理内容变化时出错: $e');
      } finally {
        // 确保标记被重置，避免死锁
        isExtractionInProgress = false;
        _isProcessingContentChange = false;
      }
    } catch (e) {
      // 捕获所有异常并确保状态被重置
      LogUtil.e('内容处理延迟操作出错: $e');
      isExtractionInProgress = false;
      _isProcessingContentChange = false;
    }
  }
  
  /// 注入表单检测脚本 - 优化版本，从资源文件加载
  Future<void> injectFormDetectionScript(String searchKeyword) async {
    if (controller == null) return;
    
    try {
      // 从资源文件加载脚本模板
      final scriptTemplate = await rootBundle.loadString('assets/js/form_detection.js');
      
      // 替换脚本中的搜索关键词
      final scriptWithKeyword = scriptTemplate.replaceAll(
        '{{SEARCH_KEYWORD}}', 
        searchKeyword.replaceAll('"', '\\"')
      );
      
      // 执行脚本
      await controller!.runJavaScript(scriptWithKeyword);
      LogUtil.i('表单检测脚本注入成功');
    } catch (e, stackTrace) {
      LogUtil.logError('注入表单检测脚本失败', e, stackTrace);
    }
  }
  
  /// 处理导航事件 - 页面开始加载
  Future<void> handlePageStarted(String pageUrl) async {
    // 首先检查是否已取消，避免不必要的操作
    if (isCancelled()) {
      LogUtil.i('任务已取消，中断导航');
      cleanupResources();
      return;
    }
    
    LogUtil.i('页面开始加载: $pageUrl');
    
    // 检查是否已切换到备用引擎但尝试加载主引擎
    if (searchState['engineSwitched'] == true && 
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
    
    // 如果搜索尚未提交且不是空白页，注入表单检测脚本
    if (!searchState['searchSubmitted'] && pageUrl != 'about:blank') {
      await injectFormDetectionScript(searchState['searchKeyword']);
    }
  }
  
  /// 处理导航事件 - 页面加载完成
  Future<void> handlePageFinished(String pageUrl) async {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理页面完成事件');
      cleanupResources();
      return;
    }
    
    final currentTimeMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = searchState['startTimeMs'] as int;
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
    
    if (searchState['engineSwitched'] == true && isPrimaryEngine) {
      LogUtil.i('已切换备用引擎，忽略主引擎');
      return;
    }
    
    if (isPrimaryEngine) {
      searchState['activeEngine'] = 'primary';
      LogUtil.i('主引擎页面加载完成');
    } else if (isBackupEngine) {
      searchState['activeEngine'] = 'backup';
      LogUtil.i('备用引擎页面加载完成');
    }
    
    if (searchState['searchSubmitted'] == true) {
      if (!isExtractionInProgress && !isTestingStarted && !_extractionTriggered) {
        Timer(Duration(milliseconds: 500), () {
          if (controller != null && !completer.isCompleted && !isCancelled()) {
            LogUtil.i('页面加载完成后主动尝试提取链接');
            handleContentChange();
          }
        });
      }
    }
  }
  
  /// 处理Web资源错误
  void handleWebResourceError(WebResourceError error) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理资源错误');
      cleanupResources();
      return;
    }
    
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
    if (searchState['activeEngine'] == 'primary' && 
        error.url != null && 
        error.url!.contains('tonkiang.us')) {
      
      bool isCriticalError = [
        -1, -2, -3, -6, -7, -101, -105, -106
      ].contains(error.errorCode);
      
      if (isCriticalError) {
        LogUtil.i('主引擎关键错误，错误码: ${error.errorCode}');
        searchState['primaryEngineLoadFailed'] = true;
        
        if (searchState['searchSubmitted'] == false && searchState['engineSwitched'] == false) {
          LogUtil.i('主引擎加载失败，切换备用引擎');
          switchToBackupEngine();
        }
      }
    }
  }
  
  /// 处理导航请求
  NavigationDecision handleNavigationRequest(NavigationRequest request) {
    if (isCancelled()) {
      LogUtil.i('任务已取消，阻止所有导航');
      return NavigationDecision.prevent;
    }
    
    // 如果已切换到备用引擎，阻止主引擎导航
    if (searchState['engineSwitched'] == true && SousuoParser._isPrimaryEngine(request.url)) {
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
    if (isCancelled()) {
      LogUtil.i('任务已取消，不处理JS消息');
      cleanupResources();
      return;
    }
    
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
      LogUtil.i('表单已提交');
      searchState['searchSubmitted'] = true;
      
      searchState['stage'] = ParseStage.searchResults;
      searchState['stage2StartTime'] = DateTime.now().millisecondsSinceEpoch;
      
      SousuoParser._injectDomChangeMonitor(controller!, 'AppChannel');
    } else if (message.message == 'FORM_PROCESS_FAILED') {
      LogUtil.i('表单处理失败');
      
      if (searchState['activeEngine'] == 'primary' && searchState['engineSwitched'] == false) {
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
      LogUtil.i('页面内容变化');
      
      handleContentChange();
    }
  }
  
  /// 开始解析流程 - 优化异常处理和资源管理
  Future<String> startParsing(String url) async {
    try {
      if (isCancelled()) {
        LogUtil.i('任务已取消，不执行解析');
        return 'ERROR';
      }
      
      setupCancelListener();
      
      // 设置全局超时
      setupGlobalTimeout();
      
      LogUtil.i('从URL提取搜索关键词');
      final uri = Uri.parse(url);
      final searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('缺少搜索关键词参数 clickText');
        return 'ERROR';
      }
      
      LogUtil.i('提取到搜索关键词: $searchKeyword');
      searchState['searchKeyword'] = searchKeyword;
      
      LogUtil.i('创建WebView控制器');
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent);
      LogUtil.i('WebView控制器创建完成');
      
      LogUtil.i('设置WebView导航委托');
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
      
      LogUtil.i('JavaScript通道添加完成');
     
     try {
       LogUtil.i('开始加载页面: ${SousuoParser._primaryEngine}');
       await controller!.loadRequest(Uri.parse(SousuoParser._primaryEngine));
       LogUtil.i('页面加载请求已发出');
     } catch (e) {
       LogUtil.e('页面加载请求失败: $e');
       
       if (searchState['engineSwitched'] == false) {
         LogUtil.i('主引擎加载失败，准备切换备用引擎');
         switchToBackupEngine();
       }
     }
     
     final result = await completer.future;
     LogUtil.i('解析完成，结果: ${result == 'ERROR' ? 'ERROR' : '找到可用流'}');
     
     int endTimeMs = DateTime.now().millisecondsSinceEpoch;
     int startMs = searchState['startTimeMs'] as int;
     LogUtil.i('解析总耗时: ${endTimeMs - startMs}ms');
     
     return result;
   } catch (e, stackTrace) {
     LogUtil.logError('解析失败', e, stackTrace);
     
     if (foundStreams.isNotEmpty && !completer.isCompleted) {
       LogUtil.i('已找到 ${foundStreams.length} 个流，尝试测试');
       try {
         // 改进：使用优先级排序的流链接
         final prioritizedStreams = _prioritizeStreams(foundStreams);
         final result = await SousuoParser._testStreamsAndGetFastest(prioritizedStreams, cancelToken: cancelToken);
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
 static const int _timeoutSeconds = 13; // 统一超时时间 - 适用于表单检测和DOM变化检测
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
 static List<String> _blockKeywords = ["freetv.fun", "itvapp"];

 // 优化：预编译正则表达式，避免频繁创建
 static final RegExp _mediaLinkRegex = RegExp(
   'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
   caseSensitive: false
 );

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
 
 /// 注入DOM变化监听器 - 优化实现，从资源文件加载脚本减少页面性能开销
 static Future<void> _injectDomChangeMonitor(WebViewController controller, String channelName) async {
   try {
     // 从资源文件加载DOM监控脚本
     final scriptTemplate = await rootBundle.loadString('assets/js/dom_monitor.js');
     
     // 替换脚本中的通道名称和变化百分比
     final script = scriptTemplate
         .replaceAll('{{CHANNEL_NAME}}', channelName)
         .replaceAll('{{SIGNIFICANT_CHANGE_PERCENT}}', _significantChangePercent.toString());
     
     await controller.runJavaScript(script);
     LogUtil.i('DOM变化监听器注入成功');
   } catch (e, stackTrace) {
     LogUtil.logError('注入监听器出错', e, stackTrace);
   }
 }
 
 /// 提交搜索表单 - 优化版，从资源文件加载脚本
 static Future<bool> _submitSearchForm(WebViewController controller, String searchKeyword) async {
   await Future.delayed(Duration(seconds: _waitSeconds)); // 等待页面	
   try {
     // 从资源文件加载表单提交脚本
     final scriptTemplate = await rootBundle.loadString('assets/js/submit_form.js');
     
     // 替换脚本中的搜索关键词
     final submitScript = scriptTemplate.replaceAll(
       '{{SEARCH_KEYWORD}}', 
       searchKeyword.replaceAll('"', '\\"')
     );
     
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

 /// 提取媒体链接 - 优化版本，更高效的HTML解析和链接提取
 static Future<void> _extractMediaLinks(
   WebViewController controller, 
   List<String> foundStreams, 
   bool usingBackupEngine, 
   {int lastProcessedLength = 0}
 ) async {
   LogUtil.i('从${usingBackupEngine ? "备用" : "主"}引擎提取链接');
   
   // 优化: 检查是否已满，避免不必要的提取
   if (foundStreams.length >= _maxStreams) {
     LogUtil.i('已达到最大链接数 $_maxStreams，跳过提取');
     return;
   }
   
   try {
     // 获取页面HTML
     final html = await controller.runJavaScriptReturningResult(
       'document.documentElement.outerHTML'
     );
     
     // 处理HTML字符串
     String htmlContent = html.toString();
     final int contentLength = htmlContent.length;
     LogUtil.i('获取HTML，长度: $contentLength');
     
     // 仅当HTML内容有实质变化时才进行处理
     if (lastProcessedLength > 0 && contentLength <= lastProcessedLength) {
       LogUtil.i('内容长度未增加，跳过提取');
       return;
     }
     
     // 内容长度较小，可能无有效内容
     if (contentLength < _minValidContentLength) {
       LogUtil.i('内容长度过小 ($contentLength < $_minValidContentLength)，可能无有效内容');
     }
     
     // 清理HTML字符串
     if (htmlContent.startsWith('"') && htmlContent.endsWith('"')) {
       htmlContent = htmlContent.substring(1, htmlContent.length - 1)
                 .replaceAll('\\"', '"')
                 .replaceAll('\\n', '\n');
     }
     
     // 使用预编译的正则表达式提取链接
     final matches = _mediaLinkRegex.allMatches(htmlContent);
     final int totalMatches = matches.length;
     
     // 如果有匹配项，记录示例
     String matchSample = "";
     if (totalMatches > 0) {
       final firstMatch = matches.first;
       matchSample = "示例匹配: ${firstMatch.group(0)} -> 提取URL: ${firstMatch.group(1)}";
       LogUtil.i(matchSample);
     }
     
     // 优化: 使用集合记录已存在的主机，避免重复链接
     final Set<String> hostSet = {};
     
     // 从已有流中提取主机信息
     for (final url in foundStreams) {
       try {
         final uri = Uri.parse(url);
         hostSet.add('${uri.host}:${uri.port}');
       } catch (_) {
         // 处理无效URL
         hostSet.add(url);
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
             
             // 检查是否已添加来自同一主机的链接
             if (!hostSet.contains(hostKey)) {
               hostSet.add(hostKey);
               
               // 按格式分类
               if (mediaUrl.toLowerCase().contains('.m3u8')) {
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
       foundStreams.add(link);
       addedCount++;
       
       if (foundStreams.length >= _maxStreams) {
         LogUtil.i('达到最大链接数 $_maxStreams，m3u8链接已足够');
         break;
       }
     }
     
     // 如果m3u8链接不足，添加其他链接
     if (foundStreams.length < _maxStreams) {
       for (final link in otherLinks) {
         foundStreams.add(link);
         addedCount++;
         
         if (foundStreams.length >= _maxStreams) {
           LogUtil.i('达到最大链接数 $_maxStreams');
           break;
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
 
 /// 测试流地址并返回最快有效地址 - 优化版，改进资源管理和错误处理
 static Future<String> _testStreamsAndGetFastest(List<String> streams, {CancelToken? cancelToken}) async {
   if (streams.isEmpty) {
     LogUtil.i('无流地址，返回ERROR');
     return 'ERROR';
   }
   
   LogUtil.i('测试 ${streams.length} 个流地址');
   
   // 创建独立的测试取消令牌和完成器
   final testCancelToken = cancelToken ?? CancelToken();
   final completer = Completer<String>();
   bool hasValidResponse = false;
   
   // 设置测试超时计时器
   final testTimeoutTimer = Timer(Duration(seconds: 5), () {
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
   
   // 创建测试任务 - 优化: 分批测试以减少并发压力
   _testStreamsBatch(streams, 0, testCancelToken, completer, hasValidResponse);
   
   try {
     final result = await completer.future;
     return result;
   } finally {
     // 确保计时器被取消
     testTimeoutTimer.cancel();
     LogUtil.i('流测试完成，清理资源');
   }
 }
 
 /// 分批测试流以减少并发压力
 static void _testStreamsBatch(
   List<String> streams, 
   int startIndex, 
   CancelToken cancelToken, 
   Completer<String> completer,
   bool hasValidResponse
 ) async {
   // 批处理大小，每次测试3个流
   const int batchSize = 3;
   final int endIndex = (startIndex + batchSize) < streams.length ? 
                       (startIndex + batchSize) : streams.length;
   
   // 如果已完成或已取消，停止测试
   if (completer.isCompleted || cancelToken.isCancelled) {
     return;
   }
   
   // 获取当前批次
   final currentBatch = streams.sublist(startIndex, endIndex);
   final tasks = currentBatch.map((streamUrl) => _testSingleStream(
     streamUrl, 
     cancelToken, 
     completer,
     hasValidResponse
   )).toList();
   
   // 并行测试当前批次
   try {
     await Future.wait(tasks);
     
     // 如果还有未测试的流，且尚未找到有效流，测试下一批
     if (endIndex < streams.length && !completer.isCompleted && !cancelToken.isCancelled) {
       _testStreamsBatch(streams, endIndex, cancelToken, completer, hasValidResponse);
     } 
     // 如果已测试所有流但未找到有效流，返回ERROR
     else if (!completer.isCompleted) {
       LogUtil.i('所有流测试完成但未找到可用流');
       completer.complete('ERROR');
     }
   } catch (e) {
     LogUtil.e('批次测试出错: $e');
     
     // 确保完成器被完成
     if (!completer.isCompleted) {
       completer.complete('ERROR');
     }
   }
 }
 
 /// 测试单个流
 static Future<void> _testSingleStream(
   String streamUrl, 
   CancelToken cancelToken, 
   Completer<String> completer,
   bool hasValidResponse
 ) async {
   try {
     // 避免无效测试
     if (completer.isCompleted || cancelToken.isCancelled) return;
     
     // 测试流
     final stopwatch = Stopwatch()..start();
     final response = await HttpUtil().getRequestWithResponse(
       streamUrl,
       options: Options(
         headers: HeadersConfig.generateHeaders(url: streamUrl),
         method: 'GET',
         responseType: ResponseType.plain,
         followRedirects: true,
         validateStatus: (status) => status != null && status < 400,
         receiveTimeout: Duration(seconds: 3),  // 添加超时控制
       ),
       cancelToken: cancelToken,
       retryCount: 1,
     );
     
     // 处理成功响应
     if (response != null && !completer.isCompleted && !cancelToken.isCancelled) {
       final responseTime = stopwatch.elapsedMilliseconds;
       LogUtil.i('流 $streamUrl 响应: ${responseTime}ms');
       
       hasValidResponse = true;
       
       // 找到可用流后，取消其他测试请求
       if (!cancelToken.isCancelled) {
         LogUtil.i('找到可用流，取消其他测试请求');
         cancelToken.cancel('找到可用流');
       }
       
       // 返回此有效流
       completer.complete(streamUrl);
     }
   } catch (e) {
     // 区分取消错误和其他错误
     if (cancelToken.isCancelled) {
       LogUtil.i('测试已取消: $streamUrl');
     } else {
       LogUtil.e('测试 $streamUrl 出错: $e');
     }
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
