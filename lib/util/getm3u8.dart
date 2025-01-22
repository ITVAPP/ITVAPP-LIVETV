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
  static String rulesString = 'setv.sh.cn|programme10_ud@kanwz.net|playlist.m3u8';

  /// 特殊规则字符串，用于动态设置监听的文件类型，格式: domain1|fileType1@domain2|fileType2
  static String specialRulesString = 'nctvcloud.com|flv@mydomaint.com|mp4';

  /// 动态关键词规则字符串，符合规则使用getm3u8diy来解析
  static String dynamicKeywordsString = 'sztv123';
  
  /// 缓存的时间差（毫秒）
  static int? _cachedTimeOffset;

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

  /// 重试计数器
  int _retryCount = 0;

  /// 检测开始时间
  final DateTime _startTime = DateTime.now();

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

  /// 是否已通过静态检测找到M3U8
  bool _staticM3u8Found = false;

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

  // 添加一个变量来跟踪当前URL的加载状态
  final Map<String, bool> _pageLoadedStatus = {};

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

/// 获取时间差（毫秒）
  Future<int> _getTimeOffset() async {
    try {
      const TIME_APIS = [
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
      final localTime = DateTime.now();
      
      // 按顺序尝试所有时间源
      for (final api in TIME_APIS) {
        try {
          final networkTime = await _getNetworkTime(api['url']!);
          if (networkTime != null) {
            final offset = networkTime.difference(localTime).inMilliseconds;
            LogUtil.i('获取到时间差: ${offset}ms，来源: ${api['name']}');
            return offset;
          }
        } catch (e) {
          LogUtil.i('${api['name']} 获取时间失败: $e');
          continue;
        }
      }
      
      LogUtil.i('所有时间源都失败了，使用默认时间差 0');
      return 0;
    } catch (e) {
      LogUtil.e('获取时间差时发生错误: $e');
      return 0;
    }
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

  /// 初始化时间差
  Future<int> _initTimeOffset() async {
      // 如果已有缓存的时间差，直接返回
      if (_cachedTimeOffset != null) {
          return _cachedTimeOffset!;
      }

      // 获取新的时间差
      final newOffset = await _getTimeOffset();
      _cachedTimeOffset = newOffset;
      return newOffset;
  }

  /// 获取当前准确时间
  DateTime getCurrentTime() {
    final now = DateTime.now();
    if (_cachedTimeOffset == null) {
      return now;
    }
    final adjustedTime = now.add(Duration(milliseconds: _cachedTimeOffset!));
    LogUtil.i('返回调整后时间: ${adjustedTime.toString()}');
    return adjustedTime;
  }
  
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

  /// URL整理
  String _cleanUrl(String url) {
    LogUtil.i('URL整理开始，原始URL: $url');

    // 先处理基本的字符清理
    String cleanedUrl = url.trim()
      .replaceAll(r'\s*\\s*$', '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x2F;', '/')
      .replaceAll('&#47;', '/')
      .replaceAll('+', '%20');

    // 修复：只替换3个或更多的连续斜杠，保留双斜杠
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
      LogUtil.i('超时计时启动完成，继续执行后续逻辑');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      completer.complete('ERROR');
    }

    LogUtil.i('getUrl方法执行完成');
    return completer.future;
  }

  /// 初始化WebViewController
  Future<void> _initController(Completer<String> completer, String filePattern) async {
    try {
      LogUtil.i('开始初始化控制器');

      // 获取时间差
      final timeOffset = await _initTimeOffset();
      LogUtil.i('当前时间差: ${timeOffset}ms');

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
        LogUtil.i('准备处理非HTML内容');
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

      // HTML内容处理 - 初始化WebViewController
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(HeadersConfig.userAgent)
        ..addJavaScriptChannel(
          'M3U8Detector',
          onMessageReceived: (JavaScriptMessage message) {
            LogUtil.i('JS检测器发现新的URL: ${message.message}');
            _handleM3U8Found(message.message, completer);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
             onPageStarted: (String url) async {
               LogUtil.i('页面开始加载: $url');
              // 在页面开始加载时注入JS
               if (!_isDetectorInjected) {
                 try {
                   await _injectM3U8Detector();
                   _isDetectorInjected = true;
                   LogUtil.i('JS注入成功');
                 } catch (e) {
                   LogUtil.e('JS注入失败: $e');
                 }
               }
             },
onNavigationRequest: (NavigationRequest request) {
 LogUtil.i('页面导航请求: ${request.url}');
 
 // 先过滤掉明显的图片等静态资源
 final resourceExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp', 
                     '.css', '.woff', '.woff2', '.ttf', '.eot',
                     '.ico', '.svg', '.mp3', '.wav', 
                     '.pdf', '.doc', '.docx', '.swf', '.xml'];
                     
 if(resourceExt.any((ext) => request.url.toLowerCase().contains(ext))) {
   return NavigationDecision.prevent;
 }

 // 检查是否包含目标文件类型(如.m3u8)                    
 if(request.url.toLowerCase().contains('.' + filePattern.toLowerCase())) {
   LogUtil.i('发现目标文件: ${request.url}');
   _handleM3U8Found(request.url, completer);
   return NavigationDecision.prevent;
 }

 // 允许其他请求通过
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
                return;
              }

              // hash路由处理
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

              // 执行点击操作
              if (!_isClickExecuted && clickText != null) {
                await Future.delayed(Duration(milliseconds: 1000));
                if (!_isDisposed) {
                  await _executeClick();
                }
              }

              // 内容检查
              if (!_isPageLoadProcessed) {
                _isPageLoadProcessed = true;

                final m3u8Url = await _checkPageContent();
                if (m3u8Url != null && !completer.isCompleted) {
                  _m3u8Found = true;
                  completer.complete(m3u8Url);
                  await dispose();
                  return;
                }
              }
            },
            onWebResourceError: (WebResourceError error) async {
              // 忽略被阻止资源的错误
              if (error.errorCode == -1) {
                LogUtil.i('资源被阻止加载: ${error.description}');
                return;
              }

              LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
              await _handleLoadError(completer);
            },
          ),
        );

      // 标记控制器初始化状态
      _isControllerInitialized = true;

      // 然后再加载页面
      await _loadUrlWithHeaders();
      LogUtil.i('页面加载请求已发送');

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

Future<void> _injectM3U8Detector() async {
  if (_isDisposed || !_isControllerReady() || _isDetectorInjected) {
    LogUtil.i(_isDisposed ? '资源已释放，跳过注入JS' :
              !_isControllerReady() ? 'WebViewController 未初始化，无法注入JS' :
              'M3U8检测器已注入，跳过重复注入');
    return;
  }

  LogUtil.i('开始注入m3u8检测器JS代码');
  
  final timeOffset = _cachedTimeOffset ?? 0;
  
  final jsCode = '''
    (function() {
      if (window._m3u8DetectorInitialized) {
        return;
      }
      window._m3u8DetectorInitialized = true;

      // 劫持时间获取方法
      const timeOffset = ${timeOffset};
      const originalDate = window.Date;

      function getAdjustedTime() {
        const now = new originalDate();
        return new originalDate(now.getTime() + timeOffset);
      }
      
      // 替换原生Date对象
      window.Date = function(...args) {
        if (args.length === 0) {
          const now = new originalDate();
          return new originalDate(now.getTime() + timeOffset);
        } else if (args.length === 1) {
          const arg = args[0];
          if (arg instanceof originalDate) {
            return new originalDate(arg.getTime());
          } else if (typeof arg === 'number') {
            const isTimestamp = arg > 1000000000000;
            return new originalDate(isTimestamp ? arg : arg + timeOffset);
          }
        }
        return new originalDate(...args);
      };

      window.Date.prototype = originalDate.prototype;
      window.Date.now = function() {
        return originalDate.now() + timeOffset;
      };
      window.Date.parse = originalDate.parse;
      window.Date.UTC = originalDate.UTC;

      Object.defineProperty(window, 'Date', {
        writable: false,
        configurable: false
      });

      // 已处理的URL缓存 
      const processedUrls = new Set();
      const MAX_CACHE_SIZE = 88;

      // URL处理函数
      function processM3U8Url(url) {
        if (!url || typeof url !== 'string' || processedUrls.has(url)) {
          return;
        }

        // 处理相对路径
        if (url.startsWith('/')) {
          const baseUrl = new URL(window.location.href);
          url = baseUrl.protocol + '//' + baseUrl.host + url;
        } else if (!url.startsWith('http')) {
          const baseUrl = new URL(window.location.href);
          url = new URL(url, baseUrl).toString();
        }

        // 如果缓存过大，清理它
        if (processedUrls.size > MAX_CACHE_SIZE) {
          processedUrls.clear();
        }

        // 核心判断：只关注是否包含目标文件类型
        if (url.includes('.' + '${_filePattern}')) {
          processedUrls.add(url);
          window.M3U8Detector.postMessage(url);
        }

        // 处理base64编码的URL  
        if (url.includes('base64,')) {
          try {
            const base64Content = url.split('base64,')[1];
            const decodedContent = atob(base64Content);
            if (decodedContent.includes('.' + '${_filePattern}')) {
              const matches = decodedContent.match(new RegExp('[^\\\\s\'"]+\\.${_filePattern}[^\\\\s\'"]*', 'g'));
              if (matches) {
                matches.forEach(match => {
                  if (!processedUrls.has(match)) {
                    processedUrls.add(match);
                    window.M3U8Detector.postMessage(match);
                  }
                });
              }
            }
          } catch (e) {
            console.error('Base64解码失败:', e);
          }
        }
      }

      // 【新增】网络请求监听 - Fetch API
      const originalFetch = window.fetch;
      window.fetch = function(input, init = {}) {
        try {
          const url = input instanceof Request ? input.url : input;
          processM3U8Url(url);
          
          return originalFetch.apply(this, arguments).then(response => {
            const contentType = response.headers.get('content-type');
            if (contentType && (
              contentType.includes('mpegurl') || 
              contentType.includes('vnd.apple.mpegurl') ||
              contentType.includes('x-mpegurl')
            )) {
              processM3U8Url(url);
              // 检查重定向后的URL
              processM3U8Url(response.url);
            }
            return response;
          }).catch(error => {
            throw error;
          });
        } catch (e) {
          return originalFetch.apply(this, arguments);
        }
      };

      // 【新增】XHR监听
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSend = XHR.send;

      // 存储活跃的XHR请求，用于清理
      window._activeXhrs = window._activeXhrs || [];

      XHR.open = function() {
        this._url = arguments[1];
        return originalOpen.apply(this, arguments);
      };

      XHR.send = function() {
        if (this._url) {
          processM3U8Url(this._url);
          
          // 添加到活跃请求列表
          window._activeXhrs.push(this);
          
          // 请求完成时从活跃列表移除
          const onComplete = () => {
            const index = window._activeXhrs.indexOf(this);
            if (index > -1) {
              window._activeXhrs.splice(index, 1);
            }
          };
          
          this.addEventListener('readystatechange', () => {
            if (this.readyState === 4) {
              const contentType = this.getResponseHeader('content-type');
              if (contentType && (
                contentType.includes('mpegurl') || 
                contentType.includes('vnd.apple.mpegurl') ||
                contentType.includes('x-mpegurl')
              )) {
                processM3U8Url(this._url);
                
                // 检查重定向后的URL
                const responseURL = this.responseURL;
                if (responseURL && responseURL !== this._url) {
                  processM3U8Url(responseURL);
                }
              }
              onComplete();
            }
          });
          
          // 处理错误和中止事件
          this.addEventListener('error', onComplete);
          this.addEventListener('abort', onComplete);
        }
        return originalSend.apply(this, arguments);
      };

      // MediaSource监听 - 修改后的版本，支持多种文件类型
      if (window.MediaSource) {
        const originalCreateObjectURL = URL.createObjectURL;
        const originalRevokeObjectURL = URL.revokeObjectURL;
        const activeMediaSources = new Set();
        
        // 处理buffer范围的公共函数
        function processBufferRanges(buffer, errorContext = '处理buffer') {
          if (!buffer.buffered || buffer.buffered.length === 0) return;
          
          try {
            for (let i = 0; i < buffer.buffered.length; i++) {
              const start = buffer.buffered.start(i);
              const end = buffer.buffered.end(i);
              const prefix = window.location.href.replace(/\/[^/]*\$/, '/');
              const potentialUrl = `${prefix}stream_${Math.floor(start)}_${Math.floor(end)}.${_filePattern}`;
              processM3U8Url(potentialUrl);
            }
          } catch (e) {
            console.error(`${errorContext}时发生错误:`, e);
          }
        }

        // 处理所有sourceBuffers的公共函数
        function processSourceBuffers(mediaSource) {
          const sourceBuffers = mediaSource.sourceBuffers;
          for (let i = 0; i < sourceBuffers.length; i++) {
            const buffer = sourceBuffers[i];
            if (buffer.mode) {
              processM3U8Url(buffer.mode);
            }
            processBufferRanges(buffer);
          }
        }

        // 重写createObjectURL以捕获MediaSource实例
        URL.createObjectURL = function(obj) {
          if (obj instanceof MediaSource) {
            activeMediaSources.add(obj);
            
            // 监听sourceopen事件
            obj.addEventListener('sourceopen', () => processSourceBuffers(obj));

            // 监听sourceended事件
            obj.addEventListener('sourceended', () => {
              const sourceBuffers = obj.sourceBuffers;
              for (let i = 0; i < sourceBuffers.length; i++) {
                processBufferRanges(sourceBuffers[i], '处理结束buffer');
              }
            });

            // 处理buffer更新
            const originalAddSourceBuffer = obj.addSourceBuffer;
            obj.addSourceBuffer = function(mimeType) {
              const buffer = originalAddSourceBuffer.call(this, mimeType);
              buffer.addEventListener('updateend', () => {
                processBufferRanges(buffer, '处理buffer更新');
              });
              return buffer;
            };
          }
          return originalCreateObjectURL.call(this, obj);
        };

        // 重写revokeObjectURL以清理MediaSource实例
        URL.revokeObjectURL = function(url) {
          activeMediaSources.forEach(ms => {
            if (ms.readyState === 'open') {
              try {
                ms.endOfStream();
              } catch (e) {}
            }
          });
          return originalRevokeObjectURL.call(this, url);
        };
      }

      // 监听所有媒体元素
      function observeMediaElements() {
        const mediaElements = document.querySelectorAll('video, audio');
        mediaElements.forEach(media => {
          if (!media._observed) {
            media._observed = true;
            
            // 监听source元素变化
            const observer = new MutationObserver(mutations => {
              mutations.forEach(mutation => {
                if (mutation.type === 'childList') {
                  mutation.addedNodes.forEach(node => {
                    if (node.nodeName === 'SOURCE') {
                      processM3U8Url(node.src);
                    }
                  });
                } else if (mutation.type === 'attributes') {
                  if (mutation.attributeName === 'src') {
                    processM3U8Url(media.src);
                  }
                }
              });
            });
            
            observer.observe(media, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ['src']
            });

            // 监听media事件
            ['loadstart', 'loadedmetadata', 'play', 'playing', 'canplay', 'canplaythrough'].forEach(event => {
              media.addEventListener(event, () => {
                processM3U8Url(media.src);
                processM3U8Url(media.currentSrc);
                if (media.srcObject instanceof MediaSource) {
                  try {
                    const url = URL.createObjectURL(media.srcObject);
                    processM3U8Url(url);
                  } catch (e) {}
                }
                Array.from(media.querySelectorAll('source')).forEach(source => {
                  processM3U8Url(source.src);
                });
              });
            });
          }
        });
      }

      // 定期检查新的媒体元素
      const mediaObserverInterval = setInterval(observeMediaElements, 1000);

      // 监听DOM变化
      const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          // 处理属性变化
          if (mutation.type === 'attributes') {
            Array.from(mutation.target.attributes).forEach(attr => {
              const value = attr.value;
              if (value && typeof value === 'string') {
                processM3U8Url(value);
              }
            });
          }

          // 处理节点添加
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === Node.ELEMENT_NODE) {
              const elements = node.querySelectorAll('*');
              elements.forEach((element) => {
                // 检查元素的所有属性
                Array.from(element.attributes).forEach(attr => {
                  const value = attr.value;
                  if (value && typeof value === 'string') {
                    processM3U8Url(value);
                  }
                });
              });
            }
          });
        });
      });

      // 启动观察器
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true
      });

      // 清理函数
      window._cleanupM3U8Detector = function() {
        observer.disconnect();
        clearInterval(mediaObserverInterval);
        processedUrls.clear();
        activeMediaSources?.clear();
        // 【新增】清理活跃的XHR请求
        if (window._activeXhrs) {
          window._activeXhrs.forEach(xhr => {
            try {
              xhr.abort();
            } catch (e) {
              console.error('中止XHR请求时发生错误:', e);
            }
          });
          window._activeXhrs = [];
        }
      };

    })();
  ''';

  try {
    await _controller.runJavaScript(jsCode);
    LogUtil.i('JS代码注入成功');
    _isDetectorInjected = true;
  } catch (e, stackTrace) {
    LogUtil.logError('执行JS代码时发生错误', e, stackTrace);
    rethrow;
  }
}

/// 释放资源
Future<void> dispose() async {
 // 防止重复释放 
 if (_isDisposed) {
   LogUtil.i('资源已释放，跳过重复释放');
   return;
 }

 // HTML页面才需要清理WebView相关资源
 if (_isHtmlContent && _isControllerInitialized) {
   try {
     // 移除 JS channel
     await _controller.removeJavaScriptChannel('M3U8Detector');
     
     // 注入清理脚本，终止所有正在进行的网络请求和观察器
     await _controller.runJavaScript('''
       // 停止页面加载
       window.stop();
       // 移除 M3U8Detector
       window.M3U8Detector = null;
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

 // 清理首次加载标记
 final currentUrl = Uri.parse(url).toString();
 _hashFirstLoadMap.remove(currentUrl);

 // 重置所有标记和清理通用资源（无论是否HTML页面都需要）
 _resetControllerState();
 _foundUrls.clear();
 _pageLoadedStatus.clear();
 _httpResponseContent = null;
 _isStaticChecking = false;
 _staticM3u8Found = false;
 _m3u8Found = false;
 _isDetectorInjected = false;
 _isControllerInitialized = false;
 _isPageLoadProcessed = false;
 _isClickExecuted = false;

 // 最后才标记为已释放
 _isDisposed = true;
 
 LogUtil.i('资源释放完成');
}

  /// 处理发现的M3U8 URL
  Future<void> _handleM3U8Found(String url, Completer<String> completer) async {
    // 处理日志消息
    if (url.startsWith('LOG:')) {
      // 根据不同类型的日志进行处理
      if (url.startsWith('LOG:SCAN:')) {
        LogUtil.i('扫描状态: ${url.substring(9)}');
        return;
      } else if (url.startsWith('LOG:ERROR:')) {
        LogUtil.e('扫描错误: ${url.substring(10)}');
        return;
      } else if (url.startsWith('LOG:TIME:')) {
        LogUtil.i(url.substring(9));
        return;
      }
      return;
    }
  
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

  /// 验证M3U8 URL是否有效
  bool _isValidM3U8Url(String url) {

    // 验证URL是否为有效格式
    final validUrl = Uri.tryParse(url);
    if (validUrl == null) {
      LogUtil.i('无效的URL格式');
      return false;
    }

    // 检查文件扩展名 - 使用 _filePattern
    if (!url.toLowerCase().contains('.' + _filePattern)) {
      LogUtil.i('URL不包含.$_filePattern扩展名');
      return false;
    }

    // 检查是否包含无效关键词
    final lowercaseUrl = url.toLowerCase();
    for (final pattern in INVALID_URL_PATTERNS) {
      if (lowercaseUrl.contains(pattern)) {
        LogUtil.i('URL包含无效关键词: $pattern');
        return false;
      }
    }

    // 应用过滤规则
    if (_filterRules.isNotEmpty) {
      // 查找匹配的规则
      for (final rule in _filterRules) {
        if (url.contains(rule.domain)) {
          final containsKeyword = url.contains(rule.requiredKeyword);
          LogUtil.i('发现匹配的域名规则: ${rule.domain}');
          LogUtil.i(containsKeyword
            ? 'URL包含所需关键词: ${rule.requiredKeyword}'
            : 'URL不包含所需关键词: ${rule.requiredKeyword}'
          );
          return containsKeyword; // 对于匹配的域名，必须包含指定关键词才返回true
        }
      }
    }
    return true;
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
      if (!_isHtmlContent) {
        if (_httpResponseContent == null) {
          LogUtil.e('非 HTML 页面数据为空，跳过检测');
          return null;
        }
        String pattern = '.' + _filePattern;
        int firstPos = _httpResponseContent!.indexOf(pattern);
        if (firstPos == -1) {
          LogUtil.i('页面内容不包含.$_filePattern，跳过检测');
          return null;
        }

        int lastPos = _httpResponseContent!.lastIndexOf(pattern);
        // 计算前 100 字符的起始位置
        int start = (firstPos - 100).clamp(0, _httpResponseContent!.length);
        // 计算后 100 字符的结束位置，注意要从模式结束位置开始算
        int end = (lastPos + pattern.length + 100).clamp(0, _httpResponseContent!.length);
        sampleResult = _httpResponseContent!.substring(start, end);
      } else {
        // 如果是 HTML 页面，使用 WebView 解析
        final dynamic result = await _controller.runJavaScriptReturningResult('''
          (function() {
            const filePattern = "${RegExp.escape(_filePattern)}";
            let content = document.documentElement.innerHTML;

            if (content.length > 38888) {
              return "SIZE_EXCEEDED";
            }

            if (!content.includes('.' + filePattern)) {
              return "NO_PATTERN";
            }
            return content;
          })();
        ''');
        sampleResult = result as String?;

        // HTML页面特殊情况处理
        if (sampleResult == "SIZE_EXCEEDED") {
          LogUtil.i('页面内容较大(超过38KB)，跳过静态检测');
          return null;
        }

        if (sampleResult == "NO_PATTERN") {
          LogUtil.i('页面内容不包含.$_filePattern，跳过检测');
          return null;
        }
      }

      if (sampleResult == null) {
        LogUtil.i('获取内容样本失败');
        return null;
      }

      LogUtil.i('开始处理页面内容');

      // 处理JSON转义字符
      String sample = sampleResult.toString()
        .replaceAll(r'\\\\', '\\')  // 处理双反斜杠
        .replaceAll(r'\\/', '/')  // 处理转义斜杠
        .replaceAll(r'\\"', '"')  // 处理转义双引号
        .replaceAll(r'\/', '/');  // 处理转义斜杠

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
        .replaceAll('&#x2F;', '/')  // 斜杠
        .replaceAll('&#47;', '/')  // 斜杠
        .replaceAll('&amp;', '&')  // &
        .replaceAll('&lt;', '<')  // 小于号
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

      // 修改后的正则表达式 - 匹配所有形式的URL到下一个引号或空格
      final pattern = '''(?:https?://|//|/)[^'"\\s]*?\\.${_filePattern}[^'"\\s]*''';
      final regex = RegExp(pattern, caseSensitive: false);
      final matches = regex.allMatches(sample);
      LogUtil.i('正则匹配到 ${matches.length} 个结果');

      if (clickIndex == 0) {
        for (final match in matches) {
          String url = match.group(0)!;  // 直接获取完整匹配
          String cleanedUrl = _handleRelativePath(url);
          if (_isValidM3U8Url(cleanedUrl)) {
            String finalUrl = cleanedUrl;
            if (fromParam != null && toParam != null) {
              finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
            }
            _foundUrls.add(finalUrl);
            _staticM3u8Found = true;
            _m3u8Found = true;
            LogUtil.i('页面内容中找到 $finalUrl');
            return finalUrl;
          }
        }
      } else {
        final Set<String> foundUrls = {};

        for (final match in matches) {
          String url = match.group(0)!;  // 直接获取完整匹配
          foundUrls.add(_handleRelativePath(url));
        }
        int index = 0;
        for (final url in foundUrls) {
          String cleanedUrl = _cleanUrl(url);
          if (_isValidM3U8Url(cleanedUrl)) {
            String finalUrl = cleanedUrl;
            if (fromParam != null && toParam != null) {
              finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
            }
            _foundUrls.add(finalUrl);
            if (index == clickIndex) {
              _staticM3u8Found = true;
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
}
