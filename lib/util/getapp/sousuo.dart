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

/// 应用常量类，集中管理关键配置参数
class AppConstants {
  AppConstants._(); // 私有构造函数
  
  // 搜索引擎URL配置
  static const String initialEngineUrl = 'https://www.iptv-search.com/zh-hans/search/?q=';  // 初始引擎
  static const String backupEngine1Url = 'http://www.foodieguide.com/iptvsearch/';         // 备用引擎1
  static const String backupEngine2Url = 'https://tonkiang.us/?';                          // 备用引擎2
  
  // 超时与等待时间配置
  static const int globalTimeoutSeconds = 28;
  static const int streamFastEnoughThresholdMs = 500;  // 优先选择<500ms响应的流
  static const int streamCompareTimeWindowMs = 3000;   // 比较窗口时间（3秒）
  static const int streamTestOverallTimeoutSeconds = 6; // 流测试最大时间限制
  
  // 限制与阈值配置
  static const int maxStreams = 8;                    // 最大媒体流数量
  static const int maxConcurrentTests = 8;            // 最大并发测试数
  static const int maxSearchCacheEntries = 58;        // 搜索缓存最大条目数
  
  // 屏蔽关键词配置
  static const List<String> defaultBlockKeywords = [
    "freetv.fun", "epg.pw", "ktpremium.com", "serv00.net/Smart.php?id=ettvmovie"
  ];
}

/// URL工具类，负责处理URL相关操作
class UrlUtil {
  // 正则表达式
  static final RegExp _m3u8Regex = RegExp(r'\.m3u8(?:\?[^"\x27]*)?', caseSensitive: false);
  
  // 初始引擎(iptv-search.com)的正则表达式
  static final RegExp _initialEngineRegex = RegExp(
    r'(?:<|\\u003C)span\s+class="decrypted-link"(?:>|\\u003E)\s*(http[^<\\]+?)(?:<|\\u003C)/span',
    caseSensitive: false
  );
  
  // 备用引擎的正则表达式
  static final RegExp _mediaLinkRegex = RegExp(
    'onclick="[a-zA-Z]+\\((?:&quot;|"|\')?((https?://[^"\']+)(?:&quot;|"|\')?)',
    caseSensitive: false,
  );
  
  // 检查是否为媒体流URL
  static bool isMediaStreamUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.m3u8') || 
           lowerUrl.contains('.flv') ||
           lowerUrl.endsWith('.ts');
  }

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
  
  // 识别搜索引擎类型
  static String identifyEngine(String url) {
    if (url.contains('iptv-search.com')) return 'initial';
    if (url.contains('foodieguide.com')) return 'backup1';
    if (url.contains('tonkiang.us')) return 'backup2';
    return 'unknown';
  }
  
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
  
  // 获取引擎对应的正则表达式
  static RegExp getRegexForEngine(String engine) {
    switch (engine) {
      case 'initial': return _initialEngineRegex;
      default: return _mediaLinkRegex;
    }
  }
}

/// 缓存条目类
class _CacheEntry {
  final String url;
  _CacheEntry(this.url);
  
  Map<String, dynamic> toJson() => {'url': url};
  factory _CacheEntry.fromJson(Map<String, dynamic> json) => 
      _CacheEntry(json['url'] as String);
}

/// 搜索缓存管理类，使用LRU策略
class SearchCache {
  static const String _cacheKey = 'search_cache_data';
  static const String _lruKey = 'search_cache_lru';
  
  final int maxEntries;
  final Map<String, _CacheEntry> _cache = LinkedHashMap<String, _CacheEntry>();
  bool _isDirty = false;
  Timer? _persistTimer;
  
  SearchCache({this.maxEntries = AppConstants.maxSearchCacheEntries}) {
    _loadFromPersistence();
    
    _persistTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (_isDirty) {
        _saveToPersistence();
        _isDirty = false;
      }
    });
  }
  
  // 从持久化存储加载缓存
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
        
        // 按LRU顺序恢复缓存
        for (final key in lruOrder) {
          if (data.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              _cache[key] = _CacheEntry.fromJson(data[key]);
            } catch (e) {
              LogUtil.e('解析缓存条目($key)失败: $e');
            }
          }
        }
        
        // 处理剩余项
        for (final key in data.keys) {
          if (!_cache.containsKey(key) && data[key] is Map<String, dynamic>) {
            try {
              _cache[key] = _CacheEntry.fromJson(data[key]);
            } catch (e) {
              LogUtil.e('解析缓存条目($key)失败: $e');
            }
          }
        }
        
        // 确保不超过最大容量
        while (_cache.length > maxEntries && _cache.isNotEmpty) {
          _cache.remove(_cache.keys.first);
        }
        
        LogUtil.i('已加载 ${_cache.length} 个缓存条目');
      }
    } catch (e) {
      LogUtil.e('加载缓存失败: $e');
      _cache.clear();
    }
  }
  
  // 保存到持久化存储
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
      LogUtil.i('已保存 ${_cache.length} 个缓存条目');
    } catch (e) {
      LogUtil.e('保存缓存失败: $e');
    }
  }
  
  // 获取缓存URL
  String? getUrl(String keyword, {bool forceRemove = false}) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    final entry = _cache[normalizedKeyword];
    if (entry == null) return null;
    
    if (forceRemove) {
      final url = entry.url;
      _cache.remove(normalizedKeyword);
      _isDirty = true;
      LogUtil.i('移除缓存: $normalizedKeyword -> $url');
      return null;
    }
    
    // 更新LRU顺序
    final cachedUrl = entry.url;
    _cache.remove(normalizedKeyword);
    _cache[normalizedKeyword] = entry;
    _isDirty = true;
    return cachedUrl;
  }
  
  // 添加缓存条目
  void addUrl(String keyword, String url) {
    if (keyword.isEmpty || url.isEmpty || url == 'ERROR') return;
    
    final normalizedKeyword = keyword.trim().toLowerCase();
    _cache.remove(normalizedKeyword);
    
    // LRU缓存满时移除最旧条目
    if (_cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      LogUtil.i('移除最旧缓存条目: $oldest');
    }
    
    _cache[normalizedKeyword] = _CacheEntry(url);
    _isDirty = true;
    LogUtil.i('添加缓存: $normalizedKeyword -> $url');
  }
  
  // 清除所有缓存
  void clear() {
    _cache.clear();
    SpUtil.remove(_cacheKey);
    SpUtil.remove(_lruKey);
    _isDirty = false;
    LogUtil.i('清空所有缓存');
  }
  
  // 获取缓存大小
  int get size => _cache.length;
  
  // 释放资源
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

/// 脚本管理，负责加载和注入JavaScript
class ScriptManager {
  static final Map<String, String> _scripts = {};
  
  // 从assets加载JS脚本
  static Future<String> loadScript(String filePath) async {
    if (_scripts.containsKey(filePath)) return _scripts[filePath]!;
    
    try {
      final script = await rootBundle.loadString(filePath);
      _scripts[filePath] = script;
      return script;
    } catch (e) {
      LogUtil.e('加载脚本($filePath)失败: $e');
      try {
        // 重试一次
        final script = await rootBundle.loadString(filePath);
        _scripts[filePath] = script;
        return script;
      } catch (e2) {
        LogUtil.e('二次加载脚本文件失败: $filePath, $e2');
        return '(function(){console.error("Failed to load script: $filePath");})();';
      }
    }
  }
  
  // 注入DOM监听器脚本
  static Future<bool> injectDomMonitor(WebViewController controller, String channelName) async {
    try {
      if (!_scripts.containsKey('domMonitor')) {
        _scripts['domMonitor'] = await loadScript('assets/js/dom_change_monitor.js');
      }
      
      String script = _scripts['domMonitor']!.replaceAll('%CHANNEL_NAME%', channelName);
      await controller.runJavaScript(script);
      LogUtil.i('DOM监听器注入成功');
      return true;
    } catch (e) {
      LogUtil.e('注入DOM监听器失败: $e');
      return false;
    }
  }
  
  // 注入指纹随机化脚本
  static Future<bool> injectFingerprintRandomization(WebViewController controller) async {
    try {
      if (!_scripts.containsKey('fingerprintRandomization')) {
        _scripts['fingerprintRandomization'] = await loadScript('assets/js/fingerprint_randomization.js');
      }
      
      await controller.runJavaScript(_scripts['fingerprintRandomization']!);
      LogUtil.i('指纹随机化脚本注入成功');
      return true;
    } catch (e) {
      LogUtil.e('注入指纹随机化脚本失败: $e');
      return false;
    }
  }
  
  // 注入表单检测脚本
  static Future<bool> injectFormDetection(WebViewController controller, String searchKeyword) async {
    try {
      if (!_scripts.containsKey('formDetection')) {
        _scripts['formDetection'] = await loadScript('assets/js/form_detection.js');
      }
      
      final escapedKeyword = searchKeyword.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      String script = _scripts['formDetection']!.replaceAll('%SEARCH_KEYWORD%', escapedKeyword);
      await controller.runJavaScript(script);
      LogUtil.i('表单检测脚本注入成功');
      return true;
    } catch (e) {
      LogUtil.e('注入表单检测脚本失败: $e');
      return false;
    }
  }
}

/// WebView管理类
class WebViewManager {
  static Future<WebViewController> createController() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) {
          LogUtil.e('WebView资源错误: ${error.description}, 错误码: ${error.errorCode}');
        },
      ));
    
    return controller;
  }
  
  // 清理WebView控制器资源
  static Future<bool> cleanupController(WebViewController controller) async {
    try {
      await controller.clearCache();
      await controller.loadHtmlString('<html><body></body></html>');
      await controller.clearLocalStorage();
      return true;
    } catch (e) {
      LogUtil.e('WebView清理失败: $e');
      return false;
    }
  }
}

/// 主解析器类
class IPTVParser {
  // 搜索缓存实例
  static final SearchCache _searchCache = SearchCache();
  
  // 屏蔽关键词
  static List<String> _blockKeywords = AppConstants.defaultBlockKeywords;
  
  /// 初始化方法，预加载脚本资源
  static Future<void> initialize() async {
    try {
      await ScriptManager.loadScript('assets/js/dom_change_monitor.js');
      await ScriptManager.loadScript('assets/js/fingerprint_randomization.js');
      await ScriptManager.loadScript('assets/js/form_detection.js');
      LogUtil.i('初始化完成，脚本预加载成功');
    } catch (e) {
      LogUtil.e('初始化失败: $e');
    }
  }
  
  /// 设置屏蔽关键词
  static void setBlockKeywords(String keywords) {
    if (keywords.isNotEmpty) {
      _blockKeywords = keywords.split('@@').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } else {
      _blockKeywords = AppConstants.defaultBlockKeywords;
    }
    LogUtil.i('已设置 ${_blockKeywords.length} 个屏蔽关键词');
  }
  
  /// 检查URL是否包含屏蔽关键词
  static bool isUrlBlocked(String url) {
    final lowerUrl = url.toLowerCase();
    return _blockKeywords.any((keyword) => lowerUrl.contains(keyword.toLowerCase()));
  }
  
  /// 从HTML提取媒体链接
  static List<String> extractMediaLinks(String html, String engineType) {
    final Set<String> uniqueUrls = {};
    final List<String> foundStreams = [];
    final Map<String, bool> hostMap = {};
    
    try {
      // 根据引擎类型选择不同的提取正则
      final regex = UrlUtil.getRegexForEngine(engineType);
      final matches = regex.allMatches(html);
      
      for (final match in matches) {
        final mediaUrl = match.group(1)
            ?.trim()
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll(RegExp("[\")'&;]+\$"), '');
        
        if (mediaUrl == null || mediaUrl.isEmpty || isUrlBlocked(mediaUrl)) continue;
        
        // 去重处理
        if (uniqueUrls.contains(mediaUrl)) continue;
        uniqueUrls.add(mediaUrl);
        
        // 按主机键去重
        try {
          final hostKey = UrlUtil.getHostKey(mediaUrl);
          if (hostMap.containsKey(hostKey)) continue;
          hostMap[hostKey] = true;
        } catch (e) {
          LogUtil.e('处理URL主机键失败: $mediaUrl, $e');
        }
        
        foundStreams.add(mediaUrl);
        if (foundStreams.length >= AppConstants.maxStreams) break;
      }
      
      // 优先排序m3u8格式
      foundStreams.sort((a, b) {
        bool aIsM3u8 = a.toLowerCase().contains('.m3u8');
        bool bIsM3u8 = b.toLowerCase().contains('.m3u8');
        if (aIsM3u8 && !bIsM3u8) return -1;
        if (!aIsM3u8 && bIsM3u8) return 1;
        return 0;
      });
      
      LogUtil.i('提取到 ${foundStreams.length} 个媒体链接');
      return foundStreams;
    } catch (e) {
      LogUtil.e('提取媒体链接失败: $e');
      return foundStreams;
    }
  }
  
  /// 测试流地址并返回最快的可用流
  static Future<String> testStreams(List<String> streams, CancelToken cancelToken) async {
    if (streams.isEmpty) return 'ERROR';
    
    final Completer<String> resultCompleter = Completer<String>();
    final Map<String, int> successfulStreams = {};
    bool isComplete = false;
    
    // 比较窗口定时器
    Timer? compareWindowTimer = Timer(Duration(milliseconds: AppConstants.streamCompareTimeWindowMs), () {
      if (!isComplete && !resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
        _selectBestStream(successfulStreams, resultCompleter);
      }
    });
    
    // 整体超时定时器
    Timer? overallTimeoutTimer = Timer(Duration(seconds: AppConstants.streamTestOverallTimeoutSeconds), () {
      if (!resultCompleter.isCompleted) {
        if (successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter);
        } else {
          LogUtil.i('流测试整体超时');
          resultCompleter.complete('ERROR');
        }
      }
    });
    
    // 选择最佳流的辅助函数
    void _selectBestStream(Map<String, int> streams, Completer<String> completer) {
      if (isComplete || completer.isCompleted) return;
      isComplete = true;
      
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
      
      completer.complete(selectedStream);
    }
    
    try {
      // 批量处理流测试
      final int maxConcurrent = AppConstants.maxConcurrentTests;
      
      for (int i = 0; i < streams.length && !resultCompleter.isCompleted; i += maxConcurrent) {
        final end = (i + maxConcurrent < streams.length) ? i + maxConcurrent : streams.length;
        final batch = streams.sublist(i, end);
        
        final testFutures = batch.map((stream) async {
          if (resultCompleter.isCompleted || cancelToken.isCancelled) return false;
          
          try {
            final stopwatch = Stopwatch()..start();
            final response = await HttpUtil().getRequestWithResponse(
              stream,
              options: Options(
                headers: HeadersConfig.generateHeaders(url: stream),
                method: 'GET',
                responseType: ResponseType.bytes,
                followRedirects: true,
                validateStatus: (status) => status != null && status >= 200 && status < 400,
                receiveTimeout: Duration(seconds: AppConstants.streamTestOverallTimeoutSeconds),
              ),
              cancelToken: cancelToken,
              retryCount: 1,
            );
            
            final testTime = stopwatch.elapsedMilliseconds;
            
            if (response != null && !resultCompleter.isCompleted && !cancelToken.isCancelled) {
              bool isValidContent = true;
              
              // 验证m3u8文件内容
              if (stream.toLowerCase().contains('.m3u8') && 
                  response.data is List<int> && 
                  (response.data as List<int>).isNotEmpty) {
                final contentBytes = response.data as List<int>;
                
                if (contentBytes.length >= 5) {
                  final prefix = String.fromCharCodes(contentBytes.take(5));
                  if (!prefix.startsWith('#EXTM')) {
                    isValidContent = false;
                    LogUtil.i('流 $stream 无效: 非m3u8文件');
                  }
                }
              }
              
              if (isValidContent) {
                LogUtil.i('流 $stream 测试成功，响应: ${testTime}ms');
                successfulStreams[stream] = testTime;
                
                // 如果响应时间小于阈值，立即返回
                if (testTime < AppConstants.streamFastEnoughThresholdMs && !isComplete) {
                  LogUtil.i('流 $stream 快速响应(${testTime}ms)，立即返回');
                  _selectBestStream({stream: testTime}, resultCompleter);
                }
                
                return true;
              }
            }
          } catch (e) {
            if (!cancelToken.isCancelled) {
              LogUtil.e('测试流 $stream 失败: $e');
            }
          }
          
          return false;
        }).toList();
        
        // 使用Future.wait处理批次测试
        await Future.wait(testFutures);
        
        if (resultCompleter.isCompleted) break;
      }
      
      // 如果所有测试完成后仍未选出最佳流，但有成功的流
      if (!resultCompleter.isCompleted && successfulStreams.isNotEmpty) {
        _selectBestStream(successfulStreams, resultCompleter);
      } else if (!resultCompleter.isCompleted) {
        // 所有流均测试失败
        resultCompleter.complete('ERROR');
      }
      
      return await resultCompleter.future;
    } catch (e) {
      LogUtil.e('流测试过程中出错: $e');
      if (!resultCompleter.isCompleted) {
        if (successfulStreams.isNotEmpty) {
          _selectBestStream(successfulStreams, resultCompleter);
          return await resultCompleter.future;
        }
        resultCompleter.complete('ERROR');
      }
      return await resultCompleter.future;
    } finally {
      compareWindowTimer.cancel();
      overallTimeoutTimer.cancel();
    }
  }
  
  /// 验证缓存URL是否有效
  static Future<bool> validateCachedUrl(String keyword, String url, CancelToken? cancelToken) async {
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
  
  /// 使用初始引擎(iptv-search.com)搜索
  static Future<String?> searchWithInitialEngine(String keyword, CancelToken? cancelToken) async {
    WebViewController? controller;
    
    try {
      LogUtil.i('使用初始引擎(iptv-search.com)搜索: $keyword');
      
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('任务已取消');
        return null;
      }
      
      // 初始引擎直接通过URL参数传递查询
      final searchUrl = AppConstants.initialEngineUrl + Uri.encodeComponent(keyword);
      controller = await WebViewManager.createController();
      
      // 创建搜索完成信号
      final pageLoadCompleter = Completer<void>();
      bool contentReady = false;
      
      // 添加JavaScript通道
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('初始引擎消息: ${message.message}');
          if (message.message == 'CONTENT_READY' && !contentReady) {
            contentReady = true;
            if (!pageLoadCompleter.isCompleted) {
              pageLoadCompleter.complete();
            }
          }
        },
      );
      
      // 设置导航委托
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          LogUtil.i('初始引擎页面开始加载: $url');
          // 初始引擎只需注入监听脚本
          await ScriptManager.injectDomMonitor(controller!, 'AppChannel');
          await ScriptManager.injectFingerprintRandomization(controller!);
        },
        onPageFinished: (url) {
          LogUtil.i('初始引擎页面加载完成: $url');
          if (!pageLoadCompleter.isCompleted && !contentReady) {
            // 设置延迟，确保内容完全加载
            Future.delayed(Duration(seconds: 2), () {
              if (!pageLoadCompleter.isCompleted) {
                pageLoadCompleter.complete();
              }
            });
          }
        },
        onWebResourceError: (error) => LogUtil.e('初始引擎资源错误: ${error.description}'),
      ));
      
      // 加载搜索页面
      await controller.loadRequest(Uri.parse(searchUrl));
      
      // 等待页面加载完成
      await pageLoadCompleter.future.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          LogUtil.i('初始引擎加载超时');
          return;
        }
      );
      
      // 获取HTML内容
      final htmlResult = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      final html = htmlResult.toString()
          .replaceAll(r'\u003C', '<')
          .replaceAll(r'\u003E', '>');
      
      LogUtil.i('初始引擎HTML获取完成，长度: ${html.length}');
      
      // 使用初始引擎专用的正则表达式提取媒体链接
      final List<String> extractedLinks = extractMediaLinks(html, 'initial');
      
      if (extractedLinks.isEmpty) {
        LogUtil.i('初始引擎未找到媒体链接');
        return null;
      }
      
      // 测试提取的流
      final result = await testStreams(extractedLinks, cancelToken ?? CancelToken());
      return result == 'ERROR' ? null : result;
    } catch (e) {
      LogUtil.e('初始引擎搜索失败: $e');
      return null;
    } finally {
      if (controller != null) {
        try {
          await WebViewManager.cleanupController(controller);
        } catch (e) {
          LogUtil.e('清理初始引擎WebView失败: $e');
        }
      }
    }
  }
  
  /// 使用备用引擎搜索
  static Future<String?> searchWithBackupEngine(
      String keyword, String engineUrl, String engineName, CancelToken? cancelToken) async {
    WebViewController? controller;
    
    try {
      LogUtil.i('使用$engineName搜索: $keyword');
      
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('任务已取消');
        return null;
      }
      
      controller = await WebViewManager.createController();
      
      // 创建搜索完成信号
      final Completer<bool> formSubmittedCompleter = Completer<bool>();
      final Completer<void> contentReadyCompleter = Completer<void>();
      bool formSubmitted = false;
      bool contentReady = false;
      
      // 添加JavaScript通道，处理表单提交和内容就绪等消息
      await controller.addJavaScriptChannel(
        'AppChannel',
        onMessageReceived: (JavaScriptMessage message) {
          LogUtil.i('$engineName消息: ${message.message}');
          
          switch (message.message) {
            case 'FORM_SUBMITTED':
              formSubmitted = true;
              if (!formSubmittedCompleter.isCompleted) {
                formSubmittedCompleter.complete(true);
              }
              break;
            case 'CONTENT_READY':
              contentReady = true;
              if (!contentReadyCompleter.isCompleted) {
                contentReadyCompleter.complete();
              }
              break;
            case 'FORM_PROCESS_FAILED':
              if (!formSubmittedCompleter.isCompleted) {
                formSubmittedCompleter.complete(false);
              }
              break;
          }
        },
      );
      
      // 设置导航委托
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          LogUtil.i('$engineName页面开始加载: $url');
          
          if (!formSubmitted) {
            // 表单阶段：注入表单处理和指纹随机化脚本
            await ScriptManager.injectFingerprintRandomization(controller!);
            await ScriptManager.injectFormDetection(controller!, keyword);
          } else {
            // 结果阶段：注入DOM监听和指纹随机化脚本
            await ScriptManager.injectFingerprintRandomization(controller!);
            await ScriptManager.injectDomMonitor(controller!, 'AppChannel');
          }
        },
        onPageFinished: (url) {
          LogUtil.i('$engineName页面加载完成: $url');
          
          // 如果表单未提交且未超时，等待表单自动提交
          if (!formSubmitted && !formSubmittedCompleter.isCompleted) {
            // 延迟检查表单提交状态
            Future.delayed(Duration(seconds: 5), () {
              if (!formSubmittedCompleter.isCompleted) {
                LogUtil.i('表单提交超时，标记失败');
                formSubmittedCompleter.complete(false);
              }
            });
          }
          
          // 如果已提交表单但内容未就绪，设置超时
          if (formSubmitted && !contentReadyCompleter.isCompleted) {
            Future.delayed(Duration(seconds: 3), () {
              if (!contentReadyCompleter.isCompleted) {
                LogUtil.i('内容就绪超时，继续处理');
                contentReadyCompleter.complete();
              }
            });
          }
        },
        onWebResourceError: (error) => LogUtil.e('$engineName资源错误: ${error.description}'),
      ));
      
      // 加载引擎页面
      await controller.loadRequest(Uri.parse(engineUrl));
      
      // 等待表单提交
      final isFormSubmitSuccess = await formSubmittedCompleter.future.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          LogUtil.i('表单提交等待超时');
          return false;
        }
      );
      
      if (!isFormSubmitSuccess) {
        LogUtil.i('$engineName表单提交失败');
        return null;
      }
      
      // 等待内容就绪
      await contentReadyCompleter.future.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          LogUtil.i('内容就绪等待超时');
          return;
        }
      );
      
      // 获取HTML内容
      final htmlResult = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
      final html = htmlResult.toString();
      
      LogUtil.i('$engineName HTML获取完成，长度: ${html.length}');
      
      // 使用标准引擎的正则表达式提取媒体链接
      final List<String> extractedLinks = extractMediaLinks(html, 'backup');
      
      if (extractedLinks.isEmpty) {
        LogUtil.i('$engineName未找到媒体链接');
        return null;
      }
      
      // 测试提取的流
      final result = await testStreams(extractedLinks, cancelToken ?? CancelToken());
      return result == 'ERROR' ? null : result;
    } catch (e) {
      LogUtil.e('$engineName搜索失败: $e');
      return null;
    } finally {
      if (controller != null) {
        try {
          await WebViewManager.cleanupController(controller);
        } catch (e) {
          LogUtil.e('清理$engineName WebView失败: $e');
        }
      }
    }
  }
  
  /// 主解析方法 - 实现用户指定的流程图逻辑
  static Future<String> parse(String url, {CancelToken? cancelToken, String blockKeywords = ''}) async {
    // 1. 从URL提取搜索关键词(clickText参数)
    String? searchKeyword;
    try {
      final uri = Uri.parse(url);
      searchKeyword = uri.queryParameters['clickText'];
      
      if (searchKeyword == null || searchKeyword.isEmpty) {
        LogUtil.e('无效搜索关键词');
        return 'ERROR';
      }
      
      LogUtil.i('解析开始: $searchKeyword');
    } catch (e) {
      LogUtil.e('URL解析失败: $e');
      return 'ERROR';
    }
    
    // 设置屏蔽关键词
    if (blockKeywords.isNotEmpty) {
      setBlockKeywords(blockKeywords);
    }
    
    // 2. 启动全局超时计时器
    final timeoutCompleter = Completer<String>();
    Timer? globalTimer = Timer(Duration(seconds: AppConstants.globalTimeoutSeconds), () {
      LogUtil.i('全局超时触发');
      if (!timeoutCompleter.isCompleted) {
        timeoutCompleter.complete('ERROR');
      }
    });
    
    try {
      // 3. 检查搜索缓存
      final cachedUrl = _searchCache.getUrl(searchKeyword);
      if (cachedUrl != null) {
        LogUtil.i('缓存命中: $searchKeyword -> $cachedUrl');
        
        // 4. 验证缓存的URL是否有效
        if (await validateCachedUrl(searchKeyword, cachedUrl, cancelToken)) {
          LogUtil.i('缓存URL有效，直接返回');
          globalTimer.cancel();
          return cachedUrl;
        }
        
        LogUtil.i('缓存验证失败，继续搜索');
      }
      
      // 5. 使用初始引擎(iptv-search.com)尝试搜索
      LogUtil.i('使用初始引擎(iptv-search.com)搜索');
      final initialResult = await searchWithInitialEngine(searchKeyword, cancelToken);
      
      // 检查任务是否已取消
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('任务已取消');
        return 'ERROR';
      }
      
      if (initialResult != null) {
        LogUtil.i('初始引擎搜索成功: $initialResult');
        _searchCache.addUrl(searchKeyword, initialResult);
        globalTimer.cancel();
        return initialResult;
      }
      
      // 6. 使用备用引擎1(foodieguide.com)搜索
      LogUtil.i('使用备用引擎1(foodieguide.com)搜索');
      final backup1Result = await searchWithBackupEngine(
          searchKeyword, 
          AppConstants.backupEngine1Url, 
          "备用引擎1(foodieguide.com)", 
          cancelToken);
      
      // 检查任务是否已取消
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('任务已取消');
        return 'ERROR';
      }
      
      if (backup1Result != null) {
        LogUtil.i('备用引擎1搜索成功: $backup1Result');
        _searchCache.addUrl(searchKeyword, backup1Result);
        globalTimer.cancel();
        return backup1Result;
      }
      
      // 7. 使用备用引擎2(tonkiang.us)搜索
      LogUtil.i('使用备用引擎2(tonkiang.us)搜索');
      final backup2Result = await searchWithBackupEngine(
          searchKeyword, 
          AppConstants.backupEngine2Url, 
          "备用引擎2(tonkiang.us)", 
          cancelToken);
      
      if (backup2Result != null) {
        LogUtil.i('备用引擎2搜索成功: $backup2Result');
        _searchCache.addUrl(searchKeyword, backup2Result);
        globalTimer.cancel();
        return backup2Result;
      }
      
      // 8. 所有引擎都失败，返回错误
      LogUtil.i('所有引擎搜索失败');
      return 'ERROR';
    } catch (e) {
      LogUtil.e('解析过程中发生异常: $e');
      return 'ERROR';
    } finally {
      globalTimer?.cancel();
    }
  }
  
  /// 清理缓存
  static void clearCache() {
    _searchCache.clear();
  }
  
  /// 释放资源
  static void dispose() {
    _searchCache.dispose();
  }
}
