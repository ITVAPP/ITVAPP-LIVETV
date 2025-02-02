import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/getm3u8diy.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// M3U8过滤规则配置
class M3U8FilterRule {
  /// 域名关键词
  final String domain;

  /// 必须包含的关键词
  final String requiredKeyword;

  const M3U8FilterRule({
    required this.domain,
    required this.requiredKeyword,
  });

  /// 从字符串解析规则
  /// 格式: domain|keyword
  factory M3U8FilterRule.fromString(String rule) {
    final parts = rule.split('|');
    if (parts.length != 2) {
      throw FormatException('无效的规则格式: $rule，正确格式: domain|keyword');
    }
    return M3U8FilterRule(
      domain: parts[0].trim(),
      requiredKeyword: parts[1].trim(),
    );
  }
}

/// M3U8地址获取类
/// 用于从网页中提取M3U8视频流地址
class GetM3U8 {
  /// 全局规则配置字符串，在网页加载多个m3u8的时候，指定只使用符合条件的m3u8
  /// 格式: domain1|keyword1@domain2|keyword2
  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8@sxtygdy.com|tytv-hls.sxtygdy.com';

  /// 特殊规则字符串，用于动态设置监听的文件类型，格式: domain1|fileType1@domain2|fileType2
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4';

  /// 动态关键词规则字符串，符合规则使用getm3u8diy来解析
  static String dynamicKeywordsString = 'sztv123@hntv123';

  /// 目标URL
  final String url;

  /// URL参数：from值
  final String? fromParam;

  /// URL参数：to值
  final String? toParam;

  /// URL参数：要点击的文本
  final String? clickText;

  /// URL参数：点击索引（默认0）
  final int clickIndex;

  /// 超时时间(秒)
  final int timeoutSeconds;

  /// WebView控制器
  late WebViewController _controller;

  /// 是否已找到M3U8
  bool _m3u8Found = false;

  /// 已发现的URL集合
  final Set<String> _foundUrls = {};

  /// 定期检查定时器
  Timer? _periodicCheckTimer;

  /// 重试计数器
  int _retryCount = 0;

  /// 检测开始时间
  final DateTime _startTime = DateTime.now();

  /// 检查次数统计
  int _checkCount = 0;

  /// 当前检查间隔(秒)
  int _currentInterval = 1;

  /// 最大检查间隔(秒)
  static const int MAX_CHECK_INTERVAL = 3;

  /// 最大重试次数
  static const int MAX_RETRIES = 2;

  /// 重试延迟时间(秒)
  static const List<int> RETRY_DELAYS = [1, 2, 3];

  /// 无效URL关键词
  static const List<String> INVALID_URL_PATTERNS = [
    'advertisement', 'analytics', 'tracker',
    'pixel', 'beacon', 'stats', 'log'
  ];

  /// 已处理URL的最大缓存数量
  static const int MAX_CACHE_SIZE = 88;

  /// 是否已释放资源
  bool _isDisposed = false;

  /// 标记 JS 检测器是否已注入
  bool _isDetectorInjected = false;

  /// 规则列表
  final List<M3U8FilterRule> _filterRules;

  /// 是否正在进行静态检测
  bool _isStaticChecking = false;

  /// 标记页面是否已处理过加载完成事件
  bool _isPageLoadProcessed = false;

  /// 标记点击是否已执行
  bool _isClickExecuted = false;

  // 初始化状态标记
  bool _isControllerInitialized = false;

  /// 当前检测的文件类型
  String _filePattern = 'm3u8';  // 默认为 m3u8

  // 跟踪首次hash加载
  static final Map<String, int> _hashFirstLoadMap = {};

  bool isHashRoute = false;

  bool _isHtmlContent = false;

  String? _httpResponseContent;

  /// 缓存的时间差值(毫秒)
  static int? _cachedTimeOffset;

  // 添加一个变量来跟踪当前URL的加载状态
  final Map<String, bool> _pageLoadedStatus = {};

  /// 时间源配置
  static const List<Map<String, String>> TIME_APIS = [
    {
      'name': 'Aliyun API',
      'url': 'https://acs.m.taobao.com/gw/mtop.common.getTimestamp/',
    },
    {
      'name': 'Suning API',
      'url': 'https://quan.suning.com/getSysTime.do',
    },
    {
      'name': 'WorldTime API',
      'url': 'https://worldtimeapi.org/api/timezone/Asia/Shanghai',
    },
    {
      'name': 'Meituan API',
      'url': 'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime',
    }
  ];
  
  /// 构造函数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 9,
  }) : _filterRules = _parseRules(rulesString),
       // 初始化成员变量
       fromParam = _extractQueryParams(url)['from'],
       toParam = _extractQueryParams(url)['to'],
       clickText = _extractQueryParams(url)['clickText'],
       clickIndex = int.tryParse(_extractQueryParams(url)['clickIndex'] ?? '') ?? 0 {

    // 记录提取到的参数
    if (fromParam != null && toParam != null) {
      LogUtil.i('检测到URL参数替换规则: from=$fromParam, to=$toParam');
    }
    if (clickText != null) {
      LogUtil.i('检测到点击配置: text=$clickText, index=$clickIndex');
    }
  }

/// 无效URL检查的正则表达式
static final _invalidPatternRegex = RegExp(
  INVALID_URL_PATTERNS.join('|'),
  caseSensitive: false
);

  /// 从URL中提取查询参数，支持hash路由和普通URL
  static Map<String, String> _extractQueryParams(String url) {
    try {
      final uri = Uri.parse(url);
      Map<String, String> params = Map.from(uri.queryParameters);

      // 如果URL包含hash部分，解析hash中的参数
      if (uri.fragment.isNotEmpty) {
        // 检查fragment是否包含查询参数
        final fragmentParts = uri.fragment.split('?');
        if (fragmentParts.length > 1) {
          // 解析hash部分的查询参数
          final hashParams = Uri.splitQueryString(fragmentParts[1]);
          // 合并参数，hash部分的参数优先级更高
          params.addAll(hashParams);
        }
      }

      return params;
    } catch (e) {
      LogUtil.e('解析URL参数时发生错误: $e');
      return {};
    }
  }

  /// 执行点击操作
  Future<bool> _executeClick() async {
    // 检查WebViewController是否已初始化
    if (!_isControllerReady() || _isClickExecuted || clickText == null || clickText!.isEmpty) {
      LogUtil.i(
        !_isControllerReady()
          ? 'WebViewController 未初始化，无法执行点击'
          : _isClickExecuted
            ? '点击已执行，跳过'
            : '无点击配置，跳过'
      );
      return false;
    }

    LogUtil.i('开始执行点击操作，文本: $clickText, 索引: $clickIndex');

    final jsCode = '''
    (async function() {
      try {
        function findAndClick() {
          const searchText = '${clickText}';
          const targetIndex = ${clickIndex};

          // 获取所有文本和元素节点
          const walk = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
            {
              acceptNode: function(node) {
                if (node.nodeType === Node.ELEMENT_NODE) {
                  if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return NodeFilter.FILTER_ACCEPT;
                }
                if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
                  return NodeFilter.FILTER_ACCEPT;
                }
                return NodeFilter.FILTER_REJECT;
              }
            }
          );

          // 记录找到的匹配
          const matches = [];
          let currentIndex = 0;
          let foundNode = null;

          // 遍历节点
          let node;
          while (node = walk.nextNode()) {
            // 处理文本节点
            if (node.nodeType === Node.TEXT_NODE) {
              const text = node.textContent.trim();
              if (text === searchText) {
                matches.push({
                  text: text,
                  node: node.parentElement
                });

                if (currentIndex === targetIndex) {
                  foundNode = node.parentElement;
                  break;
                }
                currentIndex++;
              }
            }
            // 处理元素节点
            else if (node.nodeType === Node.ELEMENT_NODE) {
              const children = Array.from(node.childNodes);
              const directText = children
                .filter(child => child.nodeType === Node.TEXT_NODE)
                .map(child => child.textContent.trim())
                .join('');

              if (directText === searchText) {
                matches.push({
                  text: directText,
                  node: node
                });

                if (currentIndex === targetIndex) {
                  foundNode = node;
                  break;
                }
                currentIndex++;
              }
            }
          }

          if (!foundNode) {
            console.error('未找到匹配的元素');
            return;
          }

          try {
            // 优先点击节点本身
            const originalClass = foundNode.getAttribute('class') || '';
            foundNode.click();

            // 等待 1000ms 检查 class 是否发生变化
            setTimeout(() => {
              const updatedClass = foundNode.getAttribute('class') || '';
              if (originalClass !== updatedClass) {
                console.info('节点点击成功，class 发生变化');
              } else if (foundNode.parentElement) {
                // 尝试点击父节点
                const parentOriginalClass = foundNode.parentElement.getAttribute('class') || '';
                foundNode.parentElement.click();

                setTimeout(() => {
                  const parentUpdatedClass = foundNode.parentElement.getAttribute('class') || '';
                  if (parentOriginalClass !== parentUpdatedClass) {
                    console.info('父节点点击成功，class 发生变化');
                  } else {
                    console.error('点击后无任何变化');
                  }
                }, 1000);
              }
            }, 1000);
          } catch (e) {
            console.error('点击操作失败:', e);
          }
        }

        findAndClick();
      } catch (e) {
        console.error('JavaScript 执行时发生错误:', e);
      }
    })();
    ''';

    try {
      await _controller.runJavaScript(jsCode);
      _isClickExecuted = true; // 标记为已执行
      return true;
    } catch (e, stack) {
      LogUtil.logError('执行点击操作时发生错误', e, stack);
      _isClickExecuted = true; // 标记为已执行
      return false;
    }
  }

  /// 解析规则字符串
  static List<M3U8FilterRule> _parseRules(String rulesString) {
    if (rulesString.isEmpty) {
      return [];
    }

    try {
      return rulesString
          .split('@')
          .where((rule) => rule.isNotEmpty)
          .map((rule) => M3U8FilterRule.fromString(rule))
          .toList();
    } catch (e) {
      LogUtil.e('解析规则字符串失败: $e');
      return [];
    }
  }
  
/// 解析动态关键词规则
static Set<String> _parseKeywords(String keywordsString) {
  if (keywordsString.isEmpty) {
    return {};
  }

  try {
    return keywordsString.split('@').map((keyword) => keyword.trim()).toSet();
  } catch (e) {
    LogUtil.e('解析动态关键词规则失败: $e');
    return {};
  }
}

/// 解析特殊规则字符串
/// 返回 Map，其中键是域名，值是文件类型
static Map<String, String> _parseSpecialRules(String rulesString) {
  if (rulesString.isEmpty) {
    return {};
  }

  try {
    return Map.fromEntries(
      rulesString.split('@').map((rule) {
        final parts = rule.split('|');
        if (parts.length != 2) {
          throw FormatException('规则格式错误: $rule，正确格式: domain|fileType');
        }
        return MapEntry(parts[0].trim(), parts[1].trim());
      }),
    );
  } catch (e) {
    LogUtil.e('解析特殊规则字符串失败: $e');
    return {};
  }
}

  /// 获取时间差（毫秒）
Future<int> _getTimeOffset() async {
  // 使用缓存优先
  if (_cachedTimeOffset != null) return _cachedTimeOffset!;
  
  final localTime = DateTime.now();
  // 按顺序尝试多个时间源
  for (final api in TIME_APIS) {
    final networkTime = await _getNetworkTime(api['url']!);
    if (networkTime != null) {
      _cachedTimeOffset = networkTime.difference(localTime).inMilliseconds;
      return _cachedTimeOffset!;
    }
  }
  return 0;
}

  /// 从指定 API 获取网络时间
  Future<DateTime?> _getNetworkTime(String url) async {
    final response = await HttpUtil().getRequest<String>(
      url,
      retryCount: 1, // 减少重试次数，因为我们有多个备选API
    );

    if (response == null) return null;

    try {
      final Map<String, dynamic> data = json.decode(response);

      // 根据不同API返回格式解析时间
      if (url.contains('taobao')) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']['t']));
      } else if (url.contains('suning')) {
        return DateTime.parse(data['sysTime2']);
      } else if (url.contains('worldtimeapi')) {
        return DateTime.parse(data['datetime']);
      } else if (url.contains('meituan')) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(data['data']));
      }
    } catch (e) {
      LogUtil.e('解析时间响应失败: $e');
    }
    return null;
  }

  /// 时间拦截器的代码
String _prepareTimeInterceptorCode() {
 if (_cachedTimeOffset == null || _cachedTimeOffset == 0) {
   return '(function(){})();'; 
 }
 
 return '''
 (function() {
   if (window._timeInterceptorInitialized) return;
   window._timeInterceptorInitialized = true;

   const originalDate = window.Date;
   const timeOffset = ${_cachedTimeOffset};
   let timeRequested = false;

   // 核心时间调整函数
   function getAdjustedTime() {
     if (!timeRequested) {
       timeRequested = true;
       window.TimeCheck.postMessage(JSON.stringify({
         type: 'timeRequest',
         method: 'Date'
       }));
     }
     return new originalDate(new originalDate().getTime() + timeOffset);
   }

   // 代理Date构造函数
   window.Date = function(...args) {
     return args.length === 0 ? getAdjustedTime() : new originalDate(...args); 
   };

   // 保持原型链和方法
   window.Date.prototype = originalDate.prototype;
   window.Date.now = () => {
     if (!timeRequested) {
       timeRequested = true;
       window.TimeCheck.postMessage(JSON.stringify({
         type: 'timeRequest',
         method: 'Date.now'
       }));
     }
     return getAdjustedTime().getTime();
   };
   window.Date.parse = originalDate.parse;
   window.Date.UTC = originalDate.UTC;

   // 拦截performance.now 
   const originalPerformanceNow = window.performance.now.bind(window.performance);
   let perfTimeRequested = false;
   window.performance.now = () => {
     if (!perfTimeRequested) {
       perfTimeRequested = true;
       window.TimeCheck.postMessage(JSON.stringify({
         type: 'timeRequest',
         method: 'performance.now'
       }));
     }
     return originalPerformanceNow() + timeOffset;
   };

   // 媒体元素时间处理
   let mediaTimeRequested = false;
   function setupMediaElement(element) {
     if (element._timeProxied) return;
     element._timeProxied = true;
     
     Object.defineProperty(element, 'currentTime', {
       get: () => {
         if (!mediaTimeRequested) {
           mediaTimeRequested = true;
           window.TimeCheck.postMessage(JSON.stringify({
             type: 'timeRequest', 
             method: 'media.currentTime'
           }));
         }
         return (element.getRealCurrentTime?.() ?? 0) + (timeOffset / 1000);
       },
       set: value => element.setRealCurrentTime?.(value - (timeOffset / 1000))
     });
   }

   // 监听新媒体元素
   const observer = new MutationObserver(mutations => {
     mutations.forEach(mutation => {
       mutation.addedNodes.forEach(node => {
         if (node instanceof HTMLMediaElement) setupMediaElement(node);
       });
     });
   });

   observer.observe(document.documentElement, {
     childList: true,
     subtree: true
   });

   // 初始化现有媒体元素
   document.querySelectorAll('video,audio').forEach(setupMediaElement);

   // 资源清理
   window._cleanupTimeInterceptor = () => {
     window.Date = originalDate;
     window.performance.now = originalPerformanceNow;
     observer.disconnect();
     delete window._timeInterceptorInitialized;
   };
 })();
 ''';
}

  /// 初始化WebViewController
Future<void> _initController(Completer<String> completer, String filePattern) async {
  try {
    LogUtil.i('开始初始化控制器');

      // 先检查页面内容类型
      final httpdata = await HttpUtil().getRequest<String>(url);
      if (httpdata == null) {
        LogUtil.e('HttpUtil 请求失败，未获取到数据');
        _httpResponseContent = null;
        completer.complete('ERROR');
        return;
      } else {
        _httpResponseContent = httpdata;
      } 

      // 判断内容类型
      _isHtmlContent = httpdata.contains('<!DOCTYPE html>') || httpdata.contains('<html');
      _httpResponseContent = httpdata;
      
      // 非HTML内容直接处理
      if (!isHashRoute && !_isHtmlContent) {
        LogUtil.i('检测到非HTML内容，直接处理');
        _isDetectorInjected = true;  // 标记为已注入，避免后续注入
        _isControllerInitialized = true;
        // 直接调用内容检查
        final result = await _checkPageContent();
        if (result != null) {
          completer.complete(result);
          return;
        }
        completer.complete('ERROR');
        return;
      }
      
    // 获取时间差并注入时间拦截器（对所有页面执行）
    _cachedTimeOffset ??= await _getTimeOffset();
      
    // 初始化 controller
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(HeadersConfig.userAgent);

    // 检查内容和准备脚本 
    final List<String> initScripts = [];
    initScripts.add(_prepareTimeInterceptorCode());
    
    // 添加基础运行时脚本(优先注入)
    initScripts.add('''
      window._videoInit = false;
      window._processedUrls = new Set();
      window._m3u8Found = false;
    ''');

    // M3U8检测器核心脚本 
    initScripts.add(_prepareM3U8DetectorCode());

    // 注册时间检查消息通道
    _controller.addJavaScriptChannel(
      'TimeCheck',
      onMessageReceived: (JavaScriptMessage message) {
        try {
          final data = json.decode(message.message);
          if (data['type'] == 'timeRequest') {
            final now = DateTime.now();
            final adjustedTime = now.add(Duration(milliseconds: _cachedTimeOffset ?? 0));
            LogUtil.i('检测到时间请求: ${data['method']}，返回时间：$adjustedTime');
          }
        } catch (e) {
          LogUtil.e('处理时间检查消息失败: $e');
        }
      },
    );

    // 注册消息通道
    _controller.addJavaScriptChannel(
      'M3U8Detector',
      onMessageReceived: (JavaScriptMessage message) {
        try {
          final data = json.decode(message.message);
          if (data['type'] == 'init') {
            _isDetectorInjected = true;
          } else {
            _handleM3U8Found(data['url'] ?? message.message, completer);
          }
        } catch (e) {
          _handleM3U8Found(message.message, completer);
        }
      },
    );
    
    // 导航委托 
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) async {
          // 页面开始加载时注入检测器
          for (final script in initScripts) {
            await _controller.runJavaScript(script);
            LogUtil.i('注入脚本成功');
          }
        },
        onNavigationRequest: (NavigationRequest request) async {
          // 检查重定向时是否需要重新注入
          try {
            final currentUri = Uri.parse(url);
            final newUri = Uri.parse(request.url);
            if (currentUri.host != newUri.host) {
              // 域名发生变化时重新注入所有脚本
              for (final script in initScripts) {
                await _controller.runJavaScript(script);
              }
              LogUtil.i('重定向页面的拦截器代码已重新注入');
            }
          } catch (e) {
            LogUtil.e('检查重定向URL失败: $e');
          }

          // 原有的导航逻辑
          LogUtil.i('页面导航请求: ${request.url}');
          final uri = Uri.tryParse(request.url);
          if (uri == null) {
            LogUtil.i('无效的URL，阻止加载');
            return NavigationDecision.prevent;
          }

          // 资源检查逻辑
          try {
            final extension = uri.path.toLowerCase().split('.').last;
            final blockedExtensions = [
              'jpg', 'jpeg', 'png', 'gif', 'webp',
              'css', 'woff', 'woff2', 'ttf', 'eot',
              'ico', 'svg', 'mp3', 'wav',
              'pdf', 'doc', 'docx', 'swf',
            ];

            if (blockedExtensions.contains(extension)) {
              return NavigationDecision.prevent;
            }
          } catch (e) {
            // 如果获取扩展名失败，继续处理
          }

          // 目标资源检查
          try {
            final lowercasePath = uri.path.toLowerCase();
            if (lowercasePath.contains('.' + filePattern.toLowerCase())) {
              _controller.runJavaScript(
                'window.M3U8Detector?.postMessage(${json.encode({
                  'type': 'url',
                  'url': request.url,
                  'source': 'navigation'
                })});'
              ).catchError((_) {});
              return NavigationDecision.prevent;
            }
          } catch (e) {
            LogUtil.e('URL检查失败: $e');
          }

          return NavigationDecision.navigate;
        },
        onPageFinished: (String url) async {
          // 检查此URL是否已经触发过页面加载完成
          if (!isHashRoute && _pageLoadedStatus[url] == true) {	
            LogUtil.i('本页面已经加载完成，跳过重复处理');
            return;
          }

          // 标记该URL已处理
          _pageLoadedStatus[url] = true;
          LogUtil.i('页面加载完成: $url');

          // 基础状态检查
          if (_isDisposed || _isClickExecuted) {
            LogUtil.i(_isDisposed ? '资源已释放，跳过处理' : '点击已执行，跳过处理');
            return;
          }

          // 处理hash路由
          try {
            final uri = Uri.parse(url);
            isHashRoute = uri.fragment.isNotEmpty;

            if (isHashRoute) {
              String mapKey = uri.toString();
              _pageLoadedStatus.clear();
              _pageLoadedStatus[mapKey] = true;

              int currentTriggers = _hashFirstLoadMap[mapKey] ?? 0;
              currentTriggers++;

              if (currentTriggers > 2) {
                LogUtil.i('hash路由触发超过2次，跳过处理');
                return;
              }

              _hashFirstLoadMap[mapKey] = currentTriggers;

              if (currentTriggers == 1) {
                LogUtil.i('检测到hash路由首次加载，等待第二次加载');
                return;
              }
            }
          } catch (e) {
            LogUtil.e('解析URL失败: $e');
          }

          // 处理点击操作
          if (!_isClickExecuted && clickText != null) {
            await Future.delayed(const Duration(milliseconds: 1000));
            if (!_isDisposed) {
              await _executeClick();
            }
          }

          // 首次加载处理
          if (!_isPageLoadProcessed) {
            _isPageLoadProcessed = true;

            final m3u8Url = await _checkPageContent();
            if (m3u8Url != null && !completer.isCompleted) {
              _m3u8Found = true;
              completer.complete(m3u8Url);
              await dispose();
              return;
            }

            // 检测器已在页面加载前注入，只需要启动定期检查
            if (!_isDisposed && !_m3u8Found) {
              _setupPeriodicCheck();
            }
          }
        },
        onWebResourceError: (WebResourceError error) async {
          // 忽略被阻止资源的错误，忽略 SSL 错误，继续加载
          if (error.errorCode == -1 || error.errorCode == -6 || error.errorCode == -7) {
            LogUtil.i('资源被阻止加载: ${error.description}');
            return;
          }
          LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
          await _handleLoadError(completer);
        },
      ),
    );
    
    // 初始化完成
    _isControllerInitialized = true;
    await _loadUrlWithHeaders();
    LogUtil.i('WebViewController初始化完成');
    
  } catch (e, stackTrace) {
    LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
    _isControllerInitialized = false;
    await _handleLoadError(completer);
  }
}

  /// 处理加载错误
  Future<void> _handleLoadError(Completer<String> completer) async {
    if (_retryCount < RETRY_DELAYS.length && !_isDisposed) {
      final delaySeconds = RETRY_DELAYS[_retryCount];
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/${RETRY_DELAYS.length})，延迟${delaySeconds}秒');
      await Future.delayed(Duration(seconds: delaySeconds));
      if (!_isDisposed) {
        // 重置页面加载处理标记和点击执行标记，允许新的重试重新执行所有操作
        _isPageLoadProcessed = false;
        _pageLoadedStatus.clear();  // 清理加载状态
        _isClickExecuted = false;  // 重置点击状态，允许重试时重新点击
        await _initController(completer, _filePattern);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或已释放资源');
      completer.complete('ERROR');
      await dispose();
    }
  }

  /// 加载URL并设置headers
  Future<void> _loadUrlWithHeaders() async {
    if (!_isControllerReady()) {
      LogUtil.e('WebViewController 未初始化，无法加载URL');
      return;
    }
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      await _controller.loadRequest(Uri.parse(url), headers: headers);
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      rethrow;
    }
  }

  /// 设置定期检查
  void _setupPeriodicCheck() {
    // 如果已经有定时器在运行，或者已释放资源，或者已找到M3U8，则直接返回
    if (_periodicCheckTimer != null || _isDisposed || _m3u8Found) {
      LogUtil.i('跳过定期检查设置: ${_periodicCheckTimer != null ? "定时器已存在" : _isDisposed ? "已释放资源" : "已找到M3U8"}');
      return;
    }

    // 创建新的定期检查定时器
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        // 如果已找到M3U8或已释放资源，取消定时器
        if (_m3u8Found || _isDisposed) {
          timer.cancel();
          _periodicCheckTimer = null;
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? "M3U8已找到" : "已释放资源"}');
          return;
        }

        _checkCount++;
        LogUtil.i('执行第$_checkCount次定期检查');

        if (!_isControllerReady()) {
          LogUtil.i('WebViewController未准备好，跳过本次检查');
          return;
        }

        try {
          // 如果JS检测器未注入，先注入
          if (!_isDetectorInjected) {
            _injectM3U8Detector();
            return;
          }

          // 调用JS端的扫描函数
          await _controller.runJavaScript('''
            if (window._m3u8DetectorInitialized) {
                checkMediaElements(document);
                efficientDOMScan();
            }
          ''').catchError((error) {
            LogUtil.e('执行扫描失败: $error');
          });
        } catch (e, stack) {
          LogUtil.logError('定期检查执行出错', e, stack);
        }

        // 如果URL缓存过大，清理它
        if (_foundUrls.length > MAX_CACHE_SIZE) {
          _foundUrls.clear();
          LogUtil.i('URL缓存达到上限，已清理');
        }
      },
    );
  }

  /// 用于注入了M3U8检测器检查状态
  void _injectM3U8Detector() {
    if (_isDisposed || !_isControllerReady() || _isDetectorInjected) {
      LogUtil.i(_isDisposed ? '资源已释放，跳过注入JS' :
                !_isControllerReady() ? 'WebViewController 未初始化，无法注入JS' :
                'M3U8检测器已注入，跳过重复注入');
      return;
    }

    // 检查检测器是否正常工作
    _controller.runJavaScript('''
      if (window._m3u8DetectorInitialized) {
        checkMediaElements(document);
        efficientDOMScan();
      }
    ''').catchError((error) {
      LogUtil.e('检查M3U8检测器状态失败: $error');
    });
  }
  
/// 返回找到的第一个有效M3U8地址，如果未找到返回ERROR
  Future<String> getUrl() async {
    final completer = Completer<String>();

    // 解析动态关键词规则
    final dynamicKeywords = _parseKeywords(dynamicKeywordsString);

    // 检查是否需要使用 getm3u8diy 解析
    for (final keyword in dynamicKeywords) {
      if (url.contains(keyword)) {
        try {
          final streamUrl = await GetM3u8Diy.getStreamUrl(url);
          LogUtil.i('getm3u8diy 返回结果: $streamUrl');
          return streamUrl;  // 直接返回，不执行后续 WebView 解析
        } catch (e, stackTrace) {
          LogUtil.logError('getm3u8diy 获取播放地址失败，返回 ERROR', e, stackTrace);
          return 'ERROR';  // 失败也直接返回，终止后续逻辑
        }
      }
    }

    // 动态解析特殊规则
    final specialRules = _parseSpecialRules(specialRulesString);
    _filePattern = specialRules.entries
        .firstWhere(
          (entry) => url.contains(entry.key),
          orElse: () => const MapEntry('', 'm3u8')
        )
        .value;
    LogUtil.i('检测模式: ${_filePattern == "m3u8" ? "仅监听m3u8" : "监听$_filePattern"}');

    try {
      await _initController(completer, _filePattern);
      _startTimeout(completer);
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      completer.complete('ERROR');
    }

    LogUtil.i('getUrl方法执行完成');
    return completer.future;
  }

String _prepareM3U8DetectorCode() {
  return '''
  (function() {
    if (window._m3u8DetectorInitialized) return;
    window._m3u8DetectorInitialized = true;

    const processedUrls = new Set();
    const MAX_CACHE_SIZE = 88;
    const MAX_RECURSION_DEPTH = 3;
    let observer = null;

    function processVideoUrl(url, depth = 0) {
      if (!url || typeof url !== 'string') return;
  
      if (url.startsWith('/')) {
        const baseUrl = new URL(window.location.href);
        url = baseUrl.protocol + '//' + baseUrl.host + url;
      } else if (!url.startsWith('http')) {
        const baseUrl = new URL(window.location.href);
        url = new URL(url, baseUrl).toString();
      }

      if (depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) return;
      
      if (processedUrls.size > MAX_CACHE_SIZE) {
        processedUrls.clear();
      }

      if (url.includes('base64,')) {
        const base64Content = url.split('base64,')[1];
        const decodedContent = atob(base64Content);
        if (decodedContent.includes('.' + '${_filePattern}')) {
          processVideoUrl(decodedContent, depth + 1);
        }
      }

      if (url.includes('.' + '${_filePattern}')) {
        processedUrls.add(url);
        window.M3U8Detector.postMessage(url);
      }
    }

    // MediaSource拦截
    if (window.MediaSource) {
      const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        const supportedTypes = {
          'm3u8': ['application/x-mpegURL', 'application/vnd.apple.mpegURL'],
          'flv': ['video/x-flv', 'application/x-flv', 'flv-application/octet-stream'],
          'mp4': ['video/mp4', 'application/mp4']
        };

        const currentSupportedTypes = supportedTypes['${_filePattern}'] || [];
        if (currentSupportedTypes.some(type => mimeType.includes(type))) {
          processVideoUrl(this.url, 0);
        }
        return originalAddSourceBuffer.call(this, mimeType);
      };
    }

    // XHR拦截
    const XHR = XMLHttpRequest.prototype;
    const originalOpen = XHR.open;
    const originalSend = XHR.send;

    XHR.open = function() {
      this._url = arguments[1];
      return originalOpen.apply(this, arguments);
    };

    XHR.send = function() {
      if (this._url) processVideoUrl(this._url, 0);
      return originalSend.apply(this, arguments);
    };

    // Fetch拦截
    const originalFetch = window.fetch;
    window.fetch = function(input) {
      const url = (input instanceof Request) ? input.url : input;
      processVideoUrl(url, 0);
      return originalFetch.apply(this, arguments);
    };

    function checkMediaElements(root = document) {
      // 使用Set去重
      const processedElements = new Set();
      
      // 优化选择器
      const selector = [
        'video',
        'source',
        '[class*="video"]',
        '[class*="player"]',
        `[class*="${_filePattern}"]`,
        `[data-${_filePattern}]`
      ].join(',');

      root.querySelectorAll(selector).forEach(element => {
        if (processedElements.has(element)) return;
        processedElements.add(element);

        const attributes = [
          'src', 'data-src',
          `data-${_filePattern}`,
          `${_filePattern}-url`,
          `data-${_filePattern}-url`,
          'data-video-url'
        ];

        attributes.forEach(attr => {
          const value = element.getAttribute(attr);
          if (value) processVideoUrl(value, 0);
        });

        if (element.tagName === 'VIDEO') {
          [element.src, element.currentSrc].forEach(src => {
            if (src) processVideoUrl(src, 0);
          });

          element.querySelectorAll('source').forEach(source => {
            const src = source.src || source.getAttribute('src');
            if (src) processVideoUrl(src, 0);
          });
        }
      });
    }

    function efficientDOMScan() {
      const selector = [
        `a[href*="${_filePattern}"]`,
        `source[src*="${_filePattern}"]`,
        `video[src*="${_filePattern}"]`,
        `[data-src*="${_filePattern}"]`
      ].join(',');

      // 使用requestAnimationFrame分批处理
      requestAnimationFrame(() => {
        const elements = document.querySelectorAll(selector);
        const processElements = (startIndex) => {
          const endIndex = Math.min(startIndex + 50, elements.length);
          
          for (let i = startIndex; i < endIndex; i++) {
            const element = elements[i];
            ['href', 'src', 'data-src'].forEach(attr => {
              const value = element.getAttribute(attr);
              if (value) processVideoUrl(value, 0);
            });
          }
          
          if (endIndex < elements.length) {
            requestAnimationFrame(() => processElements(endIndex));
          }
        };
        
        processElements(0);
      });

      // 优化脚本内容扫描
      document.querySelectorAll('script:not([src])').forEach(script => {
        if (script.textContent) {
          const content = script.textContent;
          const searchPattern = '.' + '${_filePattern}';
          
          let startIndex = content.indexOf(searchPattern);
          while (startIndex !== -1) {
            // 向前查找URL的开始
            let urlStart = startIndex;
            while (urlStart > 0) {
              const char = content[urlStart - 1];
              if (char === '"' || char === "'" || char === ' ' || char === '\\n') {
                break;
              }
              urlStart--;
            }
            
            // 向后查找URL的结束
            let urlEnd = startIndex;
            while (urlEnd < content.length) {
              const char = content[urlEnd];
              if (char === '"' || char === "'" || char === ' ' || char === '\\n') {
                break;
              }
              urlEnd++;
            }
            
            const possibleUrl = content.substring(urlStart, urlEnd).trim();
            if (possibleUrl.includes('http')) {
              processVideoUrl(possibleUrl, 0);
            }
            
            startIndex = content.indexOf(searchPattern, urlEnd);
          }
        }
      });
    }

    // 使用MutationObserver监听DOM变化
    observer = new MutationObserver(mutations => {
      const processQueue = new Set();

      mutations.forEach(mutation => {
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === 1) {
            if (node.tagName === 'VIDEO' ||
                node.tagName === 'SOURCE' ||
                node.matches('[class*="video"], [class*="player"]')) {
              processQueue.add(node);
            }
            
            if (node instanceof Element) {
              for (const attr of node.attributes) {
                if (attr.value) processQueue.add(attr.value);
              }
            }
          }
        });

        if (mutation.type === 'attributes') {
          const newValue = mutation.target.getAttribute(mutation.attributeName);
          if (newValue) processQueue.add(newValue);
        }
      });

      // 批量处理队列
      requestIdleCallback(() => {
        processQueue.forEach(item => {
          if (typeof item === 'string') {
            processVideoUrl(item, 0);
          } else {
            checkMediaElements(item.parentNode || document);
          }
        });
      }, { timeout: 1000 });
    });

    // 设置观察选项
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: [
        'src', 'href', 'data-src', 'currentSrc',
        `data-${_filePattern}`,
        `${_filePattern}-url`,
        `data-${_filePattern}-url`
      ]
    });

    // URL变化处理
    let urlChangeTimeout = null;
    const handleUrlChange = () => {
      if (urlChangeTimeout) clearTimeout(urlChangeTimeout);
      urlChangeTimeout = setTimeout(() => {
        checkMediaElements(document);
        efficientDOMScan();
      }, 100);
    };

    window.addEventListener('popstate', handleUrlChange);
    window.addEventListener('hashchange', handleUrlChange);

    // 初始扫描
    requestIdleCallback(() => {
      checkMediaElements(document);
      efficientDOMScan();
    }, { timeout: 2000 });
    
    // 清理函数
    window._cleanupM3U8Detector = () => {
      observer.disconnect();
      window.removeEventListener('popstate', handleUrlChange);
      window.removeEventListener('hashchange', handleUrlChange);
      if (urlChangeTimeout) clearTimeout(urlChangeTimeout);
      delete window._m3u8DetectorInitialized;
    };
  })();
  ''';
}
  
  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () async {
      if (_isDisposed || completer.isCompleted) {
        LogUtil.i('${_isDisposed ? "已释放资源" : "已完成处理"}，跳过超时处理');
        return;
      }

      completer.complete('ERROR');
      await dispose();
    });
  }

  bool _isControllerReady() {
    if (!_isControllerInitialized || _isDisposed) {
      LogUtil.i('Controller 未初始化或资源已释放，操作跳过');
      return false;
    }
    return true;
  }

  void _resetControllerState() {
    _isControllerInitialized = false;
    _isDetectorInjected = false;
    _isPageLoadProcessed = false;
    _isClickExecuted = false;
    _m3u8Found = false;
  }

  /// 释放资源
  Future<void> dispose() async {
    // 防止重复释放
    if (_isDisposed) {
      LogUtil.i('资源已释放，跳过重复释放');
      return;
    }

    _isDisposed = true;

    // 清理首次加载标记
    final currentUrl = Uri.parse(url).toString();
    _hashFirstLoadMap.remove(currentUrl);

    // 取消定时器
    if (_periodicCheckTimer != null) {
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = null;
    }

    // HTML页面才需要清理WebView相关资源
    if (_isHtmlContent && _isControllerInitialized) {
      try {
        // 注入清理脚本，终止所有正在进行的网络请求和观察器
        await _controller.runJavaScript('''
          // 停止页面加载
          window.stop();

          // 清理时间拦截器
          if (window._cleanupTimeInterceptor) {
            window._cleanupTimeInterceptor();
          }

          // 清理所有活跃的XHR请求
          const activeXhrs = window._activeXhrs || [];
          activeXhrs.forEach(xhr => xhr.abort());

          // 清理所有Fetch请求
          if (window._abortController) {
            window._abortController.abort();
          }

          // 清理所有定时器
          const highestTimeoutId = window.setTimeout(() => {}, 0);
          for (let i = 0; i <= highestTimeoutId; i++) {
            window.clearTimeout(i);
            window.clearInterval(i);
          }

          // 清理所有事件监听器
          window.removeEventListener('scroll', window._scrollHandler);
          window.removeEventListener('popstate', window._urlChangeHandler);
          window.removeEventListener('hashchange', window._urlChangeHandler);

          // 清理M3U8检测器
          if(window._cleanupM3U8Detector) {
            window._cleanupM3U8Detector();
          }

          // 终止所有正在进行的MediaSource操作
          if (window.MediaSource) {
            const mediaSources = document.querySelectorAll('video source');
            mediaSources.forEach(source => {
              const mediaElement = source.parentElement;
              if (mediaElement) {
                mediaElement.pause();
                mediaElement.removeAttribute('src');
                mediaElement.load();
              }
            });
          }

          // 清理所有websocket连接
          const sockets = window._webSockets || [];
          sockets.forEach(socket => socket.close());

          // 停止所有进行中的网络请求
          if (window.performance && window.performance.getEntries) {
            const resources = window.performance.getEntries().filter(e =>
              e.initiatorType === 'xmlhttprequest' ||
              e.initiatorType === 'fetch' ||
              e.initiatorType === 'beacon'
            );
            resources.forEach(resource => {
              if (resource.duration === 0) {
                try {
                  const controller = new AbortController();
                  controller.abort();
                } catch(e) {}
              }
            });
          }

          // 清理所有未完成的图片加载
          document.querySelectorAll('img').forEach(img => {
            if (!img.complete) {
              img.src = '';
            }
          });

          // 清理全局变量
          delete window._timeInterceptorInitialized;
          delete window._originalDate;
          delete window._originalPerformanceNow;
          delete window._originalRAF;
          delete window._originalConsoleTime;
          delete window._originalConsoleTimeEnd;
          delete window._cleanupTimeInterceptor;
        ''');

        // 清空WebView缓存
        await _controller.clearCache();
        LogUtil.i('WebView资源清理完成');
      } catch (e, stack) {
        LogUtil.logError('释放资源时发生错误', e, stack);
      }
    } else {
      LogUtil.i(_isHtmlContent ? '_controller 未初始化，跳过释放资源' : '非HTML内容，跳过WebView资源清理');
    }

    // 重置所有标记和清理通用资源
    _resetControllerState();
    _foundUrls.clear();
    _pageLoadedStatus.clear();
    _httpResponseContent = null;
    _isStaticChecking = false;
    _m3u8Found = false;
    _isDetectorInjected = false;
    _isControllerInitialized = false;
    _isPageLoadProcessed = false;
    _isClickExecuted = false;

    LogUtil.i('资源释放完成');
  }
  
  /// 处理发现的M3U8 URL
  Future<void> _handleM3U8Found(String url, Completer<String> completer) async {
    if ((clickText != null && !_isClickExecuted) || _m3u8Found || _isDisposed) {
      LogUtil.i(
        clickText != null && !_isClickExecuted ? '点击操作未完成，忽略URL: $url' :
        _m3u8Found ? '跳过URL处理: 已找到M3U8' :
        '跳过URL处理: 资源已释放'
      );
      return;
    }

    if (url.isNotEmpty) {
      // 首先整理URL
      String cleanedUrl = _cleanUrl(url);

      if (_isValidM3U8Url(cleanedUrl)) {
        // 处理URL参数替换
        String finalUrl = cleanedUrl;
        if (fromParam != null && toParam != null) {
          LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
          finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
        }

        _foundUrls.add(finalUrl);
        _m3u8Found = true;
        if (!completer.isCompleted) {
          completer.complete(finalUrl);
          await dispose();
        }
      } else {
        LogUtil.i('URL验证失败，继续等待新的URL');
      }
    }
  }

/// 检查页面内容中的M3U8地址
Future<String?> _checkPageContent() async {
  if (!_isControllerReady() || _m3u8Found || _isDisposed) {
    LogUtil.i(
      !_isControllerReady()
        ? 'WebViewController 未初始化，无法检查页面内容'
        : '跳过页面内容检查: ${_m3u8Found ? "已找到M3U8" : "资源已释放"}',
      tag: !_isControllerReady() ? 'ERROR' : 'INFO'
    );
    return null;
  }
  _isStaticChecking = true;

  try {
    String? sampleResult;
    
    // 如果是非 HTML 页面，直接使用 HttpUtil 获取的数据
    if (!isHashRoute && !_isHtmlContent) {	
      if (_httpResponseContent == null) {
        LogUtil.e('非 HTML 页面数据为空，跳过检测');
        return null;
      }

      // 性能优化1: 使用更高效的字符串搜索
      String pattern = '.' + _filePattern;
      int firstPos = _httpResponseContent!.indexOf(pattern);
      if (firstPos == -1) {
        LogUtil.i('页面内容不包含.$_filePattern，跳过检测');
        return null;
      }

      // 性能优化2: 只处理目标区域的内容，减少内存使用
      int lastPos = _httpResponseContent!.lastIndexOf(pattern);
      int start = (firstPos - 100).clamp(0, _httpResponseContent!.length);
      int end = (lastPos + pattern.length + 100).clamp(0, _httpResponseContent!.length);
      sampleResult = _httpResponseContent!.substring(start, end);
    } else {
      // HTML页面处理优化
      final dynamic result = await _controller.runJavaScriptReturningResult('''
        (function() {
          const filePattern = "${RegExp.escape(_filePattern)}";
          const pattern = '.' + filePattern;
          
          // 性能优化3: 只获取必要的HTML内容
          const videoElements = document.querySelectorAll('video, source, [type*="video"]');
          let content = Array.from(videoElements).map(el => el.outerHTML).join('');
          
          // 如果在视频元素中没找到，再检查完整HTML
          if (!content.includes(pattern)) {
            content = document.documentElement.innerHTML;
          }

          if (content.length > 38888) {
            // 性能优化4: 大内容分块处理
            const chunks = [];
            for (let i = 0; i < content.length; i += 38888) {
              const chunk = content.slice(i, i + 38888);
              if (chunk.includes(pattern)) {
                chunks.push(chunk);
              }
            }
            return chunks.length > 0 ? chunks.join('') : "NO_PATTERN";
          }

          return content.includes(pattern) ? content : "NO_PATTERN";
        })();
      ''');

      // HTML页面特殊情况处理
      if (result == "NO_PATTERN") {
        LogUtil.i('页面内容不包含.$_filePattern，跳过检测');
        return null;
      }
      
      sampleResult = result as String?;
    }

    if (sampleResult == null) {
      LogUtil.i('获取内容样本失败');
      return null;
    }

    // 处理JSON转义字符
    String sample = sampleResult.toString()
      .replaceAll(r'\\\\', '\\')  // 处理双反斜杠
      .replaceAll(r'\\/', '/')   // 处理转义斜杠
      .replaceAll(r'\\"', '"')   // 处理转义双引号
      .replaceAll(r'\/', '/');   // 处理转义斜杠

    // 处理Unicode转义序列
    sample = sample.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      try {
        return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
      } catch (e) {
        return match.group(0)!;
      }
    });

    // 处理HTML实体
    sample = sample
      .replaceAll('&quot;', '"')  // 双引号
      .replaceAll('&#x2F;', '/') // 斜杠
      .replaceAll('&#47;', '/')  // 斜杠
      .replaceAll('&amp;', '&')  // &
      .replaceAll('&lt;', '<')   // 小于号
      .replaceAll('&gt;', '>');  // 大于号

    // URL解码
    if (sample.contains('%')) {
      try {
        sample = Uri.decodeComponent(sample);
      } catch (e) {
        LogUtil.i('URL解码失败，保持原样: $e');
      }
    }

    LogUtil.i('正在检测页面中的 $_filePattern 文件');

    // 优化5: 使用预编译的正则表达式提高性能
    final pattern = '''(?:https?://|//|/)[^'"\\s]*?\\.${_filePattern}[^'"\\s]*''';
    final regex = RegExp(pattern, caseSensitive: false);
    final matches = regex.allMatches(sample);
    LogUtil.i('正则匹配到 ${matches.length} 个结果');

    // 优化6: URL去重和批量验证
    if (clickIndex == 0) {
      final uniqueUrls = <String>{};
      for (final match in matches) {
        String url = match.group(0)!;
        String cleanedUrl = _handleRelativePath(url);
        uniqueUrls.add(cleanedUrl);
      }

      for (final url in uniqueUrls) {
        if (_isValidM3U8Url(url)) {
          String finalUrl = url;
          if (fromParam != null && toParam != null) {
            finalUrl = url.replaceAll(fromParam!, toParam!);
          }
          _foundUrls.add(finalUrl);
          _m3u8Found = true;
          LogUtil.i('页面内容中找到 $finalUrl');
          return finalUrl;
        }
      }
    } else {
      final uniqueUrls = <String>{};
      for (final match in matches) {
        String url = match.group(0)!;
        uniqueUrls.add(_handleRelativePath(url));
      }

      int index = 0;
      for (final url in uniqueUrls) {
        String cleanedUrl = _cleanUrl(url);
        if (_isValidM3U8Url(cleanedUrl)) {
          String finalUrl = cleanedUrl;
          if (fromParam != null && toParam != null) {
            finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
          }
          _foundUrls.add(finalUrl);
          if (index == clickIndex) {
            _m3u8Found = true;
            LogUtil.i('找到目标URL(index=$clickIndex): $finalUrl');
            return finalUrl;
          }
          index++;
        }
      }
    }

    LogUtil.i('页面内容中未找到符合规则的地址，继续使用JS检测器');
    return null;
  } catch (e, stackTrace) {
    LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
    return null;
  } finally {
    _isStaticChecking = false;
  }
}

/// 验证M3U8 URL是否有效
bool _isValidM3U8Url(String url) {
  // 优化1: 使用缓存避免重复验证
  if (_foundUrls.contains(url)) {
    return false;
  }

  // 优化2: 快速预检查，减少正则表达式使用
  final lowercaseUrl = url.toLowerCase();
  if (!lowercaseUrl.contains('.' + _filePattern)) {
    LogUtil.i('URL不包含.$_filePattern扩展名');
    return false;
  }

  // 验证URL是否为有效格式
  final validUrl = Uri.tryParse(url);
  if (validUrl == null) {
    LogUtil.i('无效的URL格式');
    return false;
  }

  // 优化3: 使用类级别定义的正则表达式检查无效关键词
  if (_invalidPatternRegex.hasMatch(lowercaseUrl)) {
    LogUtil.i('URL包含无效关键词');
    return false;
  }

  // 优化4: 规则检查的短路处理
  if (_filterRules.isNotEmpty) {
    bool matchedDomain = false;
    for (final rule in _filterRules) {
      if (url.contains(rule.domain)) {
        matchedDomain = true;
        final containsKeyword = url.contains(rule.requiredKeyword);
        LogUtil.i('发现匹配的域名规则: ${rule.domain}');
        return containsKeyword;
      }
    }
    if (matchedDomain) return false;
  }

  return true;
}

  /// URL整理
  String _cleanUrl(String url) {
    LogUtil.i('URL整理开始，原始URL: $url');

    // 如果以\开头，则去除
    if (url.length > 0 && url[url.length - 1] == '\\') {
      url = url.substring(0, url.length - 1);
    }

    // 先处理基本的字符清理
    String cleanedUrl = url.trim()
      .replaceAll(r'\s*\\s*$', '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x2F;', '/')
      .replaceAll('&#47;', '/')
      .replaceAll('+', '%20');

    // 只替换3个或更多的连续斜杠，保留双斜杠
    cleanedUrl = cleanedUrl.replaceAll(RegExp(r'/{3,}'), '/');

    // 保护协议中的双斜杠
    cleanedUrl = cleanedUrl.replaceAll(RegExp(r'(?<!:)//'), '/');

    // 如果已经是完整URL则直接返回
    if (RegExp(r'^(?:https?|rtmp|rtsp|ftp|mms|thunder)://').hasMatch(cleanedUrl)) {
      return cleanedUrl;
    }

    try {
      final baseUri = Uri.parse(this.url);

      if (cleanedUrl.startsWith('//')) {
        // 如果以//开头，去除//和域名部分(如果有)
        String cleanPath = cleanedUrl.substring(2);
        if (cleanPath.contains('/')) {
          // 如果包含域名，去除域名部分
          cleanPath = cleanPath.substring(cleanPath.indexOf('/'));
        }
        // 确保路径以/开头
        cleanPath = cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath;
        cleanedUrl = '${baseUri.scheme}://${baseUri.host}/$cleanPath';
      } else {
        // 处理以/开头或不以/开头的URL
        String cleanPath = cleanedUrl.startsWith('/') ? cleanedUrl.substring(1) : cleanedUrl;
        cleanedUrl = '${baseUri.scheme}://${baseUri.host}/$cleanPath';
      }
    } catch (e) {
      LogUtil.e('URL整理失败: $e');
    }

    return cleanedUrl;
  }

  /// 处理相对路径,转换为完整URL
  String _handleRelativePath(String path) {
    LogUtil.i('处理相对路径开始，原始URL: $path');

    // 检查是否是完整 URL (包含协议://)
    if (RegExp(r'^(?:https?|rtmp|rtsp|ftp|mms|thunder)://').hasMatch(path)) {
      return path;
    }

    // 如果以 // 开头,说明是省略协议的完整URL
    if (path.startsWith('//')) {
      final baseUri = Uri.parse(url);
      return '${baseUri.scheme}:$path';
    }

    try {
      final baseUri = Uri.parse(url);
      String cleanPath = path.startsWith('/') ? path.substring(1) : path;
      return _cleanUrl('${baseUri.scheme}://${baseUri.host}/$cleanPath');
    } catch (e) {
      LogUtil.e('处理相对路径失败: $e');
      return path;
    }
  }
}
