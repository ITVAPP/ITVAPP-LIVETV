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
  static String dynamicKeywordsString = 'sztv.com.cn@mycustomdomain.com';

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

  /// 是否已通过静态检测找到M3U8
  bool _staticM3u8Found = false;

  /// 标记页面是否已处理过加载完成事件
  bool _isPageLoadProcessed = false;

  /// 标记点击是否已执行
  bool _isClickExecuted = false;
  
  // 初始化状态标记
  bool _isControllerInitialized = false; // 添加初始化状态标记
  
/// 当前检测的文件类型
String _filePattern = 'm3u8';  // 默认为 m3u8

// 跟踪首次hash加载
static final Map<String, int> _hashFirstLoadMap = {};

bool isHashRoute = false;

  bool _isHtmlContent = false;
  
  String? _httpResponseContent;

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
  if (!_isControllerReady()) {
    LogUtil.e('WebViewController 未初始化，无法执行点击');
    return false;
  }
  if (_isClickExecuted || clickText == null || clickText!.isEmpty) {
    LogUtil.i(_isClickExecuted ? '点击已执行，跳过' : '无点击配置，跳过');
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
    LogUtil.i('点击操作已执行，无需返回结果');
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
  LogUtil.i('1. getUrl方法开始执行');
  final completer = Completer<String>();
  
  // 解析动态关键词规则
  LogUtil.i('2. 开始解析动态关键词');
  final dynamicKeywords = _parseKeywords(dynamicKeywordsString);
  LogUtil.i('3. GetM3U8初始化开始，目标URL: $url');
  
  // 动态检查关键词
  LogUtil.i('4. 开始检查关键词匹配');
  for (final keyword in dynamicKeywords) {
    if (url.contains(keyword)) {
      LogUtil.i('5. 检测到匹配的关键词规则: $keyword，调用 getm3u8diy');
      try {
        LogUtil.i('6. 开始调用 getm3u8diy');
        final streamUrl = await GetM3u8Diy.getStreamUrl(url);
        LogUtil.i('7. 成功获取播放地址: $streamUrl');
        completer.complete(streamUrl);
        return completer.future;
      } catch (e, stackTrace) {
        LogUtil.logError('8. getm3u8diy 获取播放地址失败', e, stackTrace);
        completer.completeError('ERROR');
        return completer.future;
      }
    }
  }
  
  // 动态解析特殊规则
  LogUtil.i('9. 开始解析特殊规则');
  final specialRules = _parseSpecialRules(specialRulesString);
  _filePattern = specialRules.entries
      .firstWhere(
        (entry) => url.contains(entry.key),
        orElse: () => const MapEntry('', 'm3u8')
      )
      .value;
  LogUtil.i('10. 检测模式: ${_filePattern == "m3u8" ? "仅监听m3u8" : "监听$_filePattern"}');
  
  try {
    LogUtil.i('11. 开始初始化控制器前');	
    await _initController(completer, _filePattern);
    LogUtil.i('12. 控制器初始化完成，准备启动超时计时');
    _startTimeout(completer);
    LogUtil.i('13. 超时计时启动完成，继续执行后续逻辑');
  } catch (e, stackTrace) {
    LogUtil.logError('14. 初始化过程发生错误', e, stackTrace);
    completer.complete('ERROR');
  }
  
  LogUtil.i('15. getUrl方法执行完成，返回future');
  return completer.future;
}

  /// 初始化WebViewController
Future<void> _initController(Completer<String> completer, String filePattern) async {
	
    try {
LogUtil.i('初始化.1: 开始初始化控制器');

    // 检查内容类型
    final httpdata = await HttpUtil().getRequest<String>(url);
    if (httpdata == null) {
      LogUtil.e('HttpUtil 请求失败，未获取到数据');
      _httpResponseContent = null;
      completer.complete('ERROR');
      return;
    }
    
    _isHtmlContent = httpdata.contains('<!DOCTYPE html>') || httpdata.contains('<html');
    _httpResponseContent = httpdata;
    
    if (!_isHtmlContent) {
      LogUtil.i('初始化.2.1: 检测到非HTML内容，标记为已注入状态');
      _isDetectorInjected = true;  // 标记为已注入，避免后续注入
      // 创建一个完成的定时器，避免后续定时检查
      if (_periodicCheckTimer != null) {
        _periodicCheckTimer?.cancel();  
      }
      _periodicCheckTimer = Timer(Duration.zero, () {});
      
      LogUtil.i('成功获取非 HTML 页面内容:  ${_httpResponseContent}');
      _isControllerInitialized = true; // 标记为已初始化
      
      // 直接调用 _checkPageContent() 处理
      final result = await _checkPageContent();
      if (result != null) {
        completer.complete(result);
        return;
      }
      completer.complete('ERROR');
      return;
    }
    
_controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setUserAgent(HeadersConfig.userAgent)
        ..addJavaScriptChannel(
          'M3U8Detector',
          onMessageReceived: (JavaScriptMessage message) {
            LogUtil.i('初始化.3: JS检测器发现新的URL: ${message.message}');
            _handleM3U8Found(message.message, completer);
          },
        )
         ..setNavigationDelegate(
          NavigationDelegate(
onNavigationRequest: (NavigationRequest request) {
  LogUtil.i('导航.1: 页面导航请求: ${request.url}');
  final uri = Uri.tryParse(request.url);
  if (uri == null) {
    LogUtil.i('导航.2: 无效的URL，阻止加载');
    return NavigationDecision.prevent;
  }

  // 1. 首先检查是否是需要阻止的资源
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

  // 2. 检查是否为目标资源
  try {
    final lowercasePath = uri.path.toLowerCase();
    if (lowercasePath.contains('.' + filePattern.toLowerCase())) {
      // 如果是目标资源，收集地址但不加载
      _controller.runJavaScript(
        'window.M3U8Detector?.postMessage("${request.url}");'
      ).catchError((_) {});
      return NavigationDecision.prevent;  // 阻止加载目标资源
    }
  } catch (e) {
    LogUtil.e('导航.ERR: URL检查失败: $e');
  }

  // 3. 允许其他所有请求通过
  return NavigationDecision.navigate;
},
onPageFinished: (String url) async {
	
  LogUtil.i('页面.1: 页面加载完成，当前状态：\n'
      '资源是否释放: $_isDisposed\n'
      '点击是否执行: $_isClickExecuted\n'
      '是否找到M3U8: $_m3u8Found');
      
  // 1. 基础状态检查
if (_isDisposed || _isClickExecuted) {
  LogUtil.i('页面.2: ' + (_isDisposed ? '资源已释放，跳过处理' : '点击已执行，跳过处理'));
  return;
}
  
  // 2. hash路由处理
  try {
    final uri = Uri.parse(url);
    isHashRoute = uri.fragment.isNotEmpty;
    
    if (isHashRoute) {
      // 使用完整URL作为key，确保每个URL有自己的首次加载标记
      String mapKey = uri.toString();
    // 获取当前触发次数
    int currentTriggers = _hashFirstLoadMap[mapKey] ?? 0;
    currentTriggers++;
    
    // 检查触发次数
    if (currentTriggers > 2) {
      LogUtil.i('页面.3: hash路由触发超过2次，跳过处理');
      return;
    }
    
    // 更新触发次数
    _hashFirstLoadMap[mapKey] = currentTriggers;
    
    if (currentTriggers == 1) {
      LogUtil.i('页面.4: 检测到hash路由首次加载，等待第二次加载');
      return;
    }
    }
  } catch (e) {
    LogUtil.e('页面.ERR: 解析URL失败: $e');
  }

  // 3. 点击处理
  if (!_isClickExecuted && clickText != null) {
    LogUtil.i('页面.5: 准备执行点击操作');
    await Future.delayed(Duration(milliseconds: 1000)); 
    if (!_isDisposed) {
      await _executeClick();
    }
  }
  
  // 4. 首次加载逻辑
  if (!_isPageLoadProcessed) {
    _isPageLoadProcessed = true;
    
    // 检查页面内容
   final m3u8Url = await _checkPageContent();
if (m3u8Url != null && !completer.isCompleted) {
    _m3u8Found = true;
    completer.complete(m3u8Url);
    await disposeResources();
    return;
}

    // 如果静态检查没找到，启动JS检测
    if (!_isDisposed && !_m3u8Found && !_isDetectorInjected) { 	
      _setupPeriodicCheck();
      _injectM3U8Detector();
    }
  }
},
            onWebResourceError: (WebResourceError error) async {
              // 忽略被阻止资源的错误
              if (error.errorCode == -1) {
                LogUtil.i('错误.1: 资源被阻止加载: ${error.description}');
                return;
              }

              LogUtil.e('错误.2: WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
              await _handleLoadError(completer);
            },
          ),
        );

      _isControllerInitialized = true; // 标记为已初始化
      await _loadUrlWithHeaders();
      LogUtil.i('初始化.5: WebViewController初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化.ERR: 初始化WebViewController时发生错误', e, stackTrace);
      _isControllerInitialized = false; // 标记初始化失败
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
        _isClickExecuted = false;  // 重置点击状态，允许重试时重新点击
        await _initController(completer, _filePattern);
      }
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或已释放资源');
      completer.complete('ERROR');
      await disposeResources();
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

  LogUtil.i('设置定期检查任务');

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

  /// 启动超时计时器
void _startTimeout(Completer<String> completer) {
  LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
  Future.delayed(Duration(seconds: timeoutSeconds), () async {
    if (_isDisposed) {
      LogUtil.i('已释放资源，跳过超时处理');
      return;
    }
    
    if (completer.isCompleted) {
      LogUtil.i('已完成处理，跳过超时处理');
      return;
    }
    
    // 记录当前状态
    LogUtil.i('超时触发时的状态：\n'
        '控制器初始化: $_isControllerInitialized\n'
        'JS检测器已注入: $_isDetectorInjected\n'
        '页面加载已处理: $_isPageLoadProcessed\n'
        '定时检查次数: $_checkCount');
    
    completer.complete('ERROR');
    await disposeResources();
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
  Future<void> disposeResources() async {
    // 防止重复释放
    if (_isDisposed) {
      LogUtil.i('资源已释放，跳过重复释放');
      return;
    }

    LogUtil.i('开始释放资源');
    _isDisposed = true;

  // 清理首次加载标记
  final currentUrl = Uri.parse(url).toString();
  _hashFirstLoadMap.remove(currentUrl);
  
    // 取消定时器
    if (_periodicCheckTimer != null) {
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = null;
    }
   
   if (_isControllerInitialized) {
    try {
      // 注入清理脚本，终止所有正在进行的网络请求和观察器
      await _controller.runJavaScript('''
        // 停止页面加载
        window.stop();

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

      // 重置所有标记
      _resetControllerState();

      // 清理其他资源
      _foundUrls.clear();
      LogUtil.i('资源释放完成');
    } catch (e, stack) {
      LogUtil.logError('释放资源时发生错误', e, stack);
    }
   } else {
    LogUtil.i('_controller 未初始化，跳过释放资源');
   }
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

    LogUtil.i('处理发现的URL: $url');
    if (url.isNotEmpty) {
      // 首先整理URL
      String cleanedUrl = _cleanUrl(url);
      LogUtil.i('整理后的URL: $cleanedUrl');

      if (_isValidM3U8Url(cleanedUrl)) {
        LogUtil.i('URL验证通过，标记为有效的m3u8地址');
        // 处理URL参数替换
        String finalUrl = cleanedUrl;
        if (fromParam != null && toParam != null) {
          LogUtil.i('执行URL参数替换: from=$fromParam, to=$toParam');
          finalUrl = cleanedUrl.replaceAll(fromParam!, toParam!);
          LogUtil.i('替换后的URL: $finalUrl');
        }

        _foundUrls.add(finalUrl);
        _m3u8Found = true;
        if (!completer.isCompleted) {
          completer.complete(finalUrl);
          await disposeResources();
        }
      } else {
        LogUtil.i('URL验证失败，继续等待新的URL');
      }
    }
  }

  /// 验证M3U8 URL是否有效
  bool _isValidM3U8Url(String url) {
    LogUtil.i('开始验证URL: $url');

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

        LogUtil.i('使用 HttpUtil 获取的数据进行提取: ${_filePattern}');

        String pattern = '.' + _filePattern;
        int firstPos = _httpResponseContent!.indexOf(pattern);
        if (firstPos == -1) {
          sampleResult = "NO_PATTERN";
        } else {
          int lastPos = _httpResponseContent!.lastIndexOf(pattern);
          // 计算前 100 字符的起始位置
          int start = (firstPos - 100).clamp(0, _httpResponseContent!.length);
          // 计算后 100 字符的结束位置，注意要从模式结束位置开始算
          int end = (lastPos + pattern.length + 100).clamp(0, _httpResponseContent!.length);
          sampleResult = _httpResponseContent!.substring(start, end);
        }
      } else {
        // 如果是 HTML 页面，使用 WebView 解析
        final dynamic result = await _controller.runJavaScriptReturningResult('''
          (function() {
            function decodeText(text) {
              return text
                .replace(/\\\\/g, '\\\\')
                .replace(/\\\//g, '/')
                .replace(/\\"/g, '"')
                .replace(/\\'/g, "'")
                .replace(/&quot;/g, '"')
                .replace(/&#x2F;|&#47;/g, '/')
                .replace(/&amp;/g, '&')
                .replace(/&lt;/g, '<')
                .replace(/&gt;/g, '>')
                .replace(/%[0-9a-fA-F]{2}/g, match => {
                  try { return decodeURIComponent(match); } catch(e) { return match; }
                });
            }

            const filePattern = "${RegExp.escape(_filePattern)}";
            let content = document.documentElement.innerHTML;

            if (content.length > 38888) {
              return "SIZE_EXCEEDED";
            }

            const decodedContent = decodeText(content);
            if (!decodedContent.includes('.' + filePattern)) {
              return "NO_PATTERN";
            }
            return decodedContent;
          })();
        ''');
        sampleResult = result as String?;
      }

      if (sampleResult == "SIZE_EXCEEDED") {
        LogUtil.i('页面内容较大(超过38KB)，跳过静态检测');
        return null;
      }

      if (sampleResult == "NO_PATTERN") {
        LogUtil.i('页面内容不包含.$_filePattern，跳过检测');
        return null;
      }

      if (sampleResult == null) {
        LogUtil.i('获取内容样本失败');
        return null;
      }
      
      LogUtil.i('从页面内容检测$_filePattern : $sampleResult');

      // 正则表达式
      final pattern = '''[\'"]([^\'"]*?\\.${_filePattern}[^\'"\s>]*)[\'"]|(?:^|\\s)((?:https?)://[^\\s<>]+?\\.${_filePattern}[^\\s<>]*)''';
      final regex = RegExp(pattern, caseSensitive: false);
      final matches = regex.allMatches(sampleResult);

      if (clickIndex == 0) {
        for (final match in matches) {
          // 检查两个捕获组
          String? url = match.group(1);  // 引号中的内容
          if (url == null || url.isEmpty) {
            url = match.group(2);  // 非引号的URL
          }

          if (url != null && url.isNotEmpty) {
            LogUtil.i('正则匹配到URL: $url');
            String cleanedUrl = _cleanUrl(_handleRelativePath(url));
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
        }
      } else {
        final Set<String> foundUrls = {};

        for (final match in matches) {
          String? url = match.group(1);
          if (url == null || url.isEmpty) {
            url = match.group(2);
          }

          if (url != null && url.isNotEmpty) {
            foundUrls.add(_handleRelativePath(url));
          }
        }

        LogUtil.i('页面内容中找到 ${foundUrls.length} 个潜在的M3U8地址');

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
      
      LogUtil.i('页面内容中未找到符合规则的M3U8地址，继续使用JS检测器');
      return null;	
    } catch (e, stackTrace) {
      LogUtil.logError('检查页面内容时发生错误', e, stackTrace);
      return null;
    } finally {
      _isStaticChecking = false;
    }
}

  /// 注入M3U8检测器的JavaScript代码
void _injectM3U8Detector() {
  if (_isDisposed || !_isControllerReady() || _isDetectorInjected) {
    LogUtil.i(_isDisposed ? '资源已释放，跳过注入JS' : 
              !_isControllerReady() ? 'WebViewController 未初始化，无法注入JS' :
              'M3U8检测器已注入，跳过重复注入');
    return;
  }

  LogUtil.i('开始注入m3u8检测器JS代码');
  final jsCode = '''
    (function() {
      // 避免重复初始化
      if (window._m3u8DetectorInitialized) {
        return;
      }
      window._m3u8DetectorInitialized = true;

      // 已处理的URL缓存
      const processedUrls = new Set();
      const MAX_CACHE_SIZE = 88;

      // 全局变量
      let observer = null;
      const MAX_RECURSION_DEPTH = 3;

      // URL处理函数
      function processM3U8Url(url, depth = 0) {
        if (!url || typeof url !== 'string') {
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

        if (depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) {
          return;
        }

        // 如果缓存过大，清理它
        if (processedUrls.size > MAX_CACHE_SIZE) {
          processedUrls.clear();
        }

        // 处理base64编码的URL
        if (url.includes('base64,')) {
          const base64Content = url.split('base64,')[1];
          const decodedContent = atob(base64Content);
          if (decodedContent.includes('.' + '${_filePattern}')) { 	
            processM3U8Url(decodedContent, depth + 1);
          }
        }

        if (url.includes('.' + '${_filePattern}')) {
          processedUrls.add(url);
          window.M3U8Detector.postMessage(url);
        }
      }

      // 拦截XHR请求
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSetRequestHeader = XHR.setRequestHeader;
      const originalSend = XHR.send;

      XHR.open = function() {
        this._method = arguments[0];
        this._url = arguments[1];
        this._requestHeaders = {};
        if (this._url) {
          // 检查 Content-Type
          const contentType = this._requestHeaders['content-type'];
          if (contentType && contentType.includes('flv')) {
            processM3U8Url(this._url, 0);
          }
        }
        return originalOpen.apply(this, arguments);
      };

      XHR.setRequestHeader = function(header, value) {
        this._requestHeaders[header.toLowerCase()] = value;
        return originalSetRequestHeader.apply(this, arguments);
      };

      XHR.send = function() {
        if (this._url) {
          processM3U8Url(this._url, 0);
        }
        return originalSend.apply(this, arguments);
      };

      // 拦截Fetch请求
      const originalFetch = window.fetch;
      window.fetch = function(input) {
        const url = (input instanceof Request) ? input.url : input;
        processM3U8Url(url, 0);
        return originalFetch.apply(this, arguments);
      };

      // 检查媒体元素
      function checkMediaElements(doc = document) {
        // 优先检查video元素
        doc.querySelectorAll('video').forEach(element => {
          // 首先检查video元素本身的source
          [element.src, element.currentSrc].forEach(src => {
            if (src) processM3U8Url(src, 0);
          });

          // 检查source子元素
          element.querySelectorAll('source').forEach(source => {
            const src = source.src || source.getAttribute('src');
            if (src) processM3U8Url(src, 0);
          });

          // 检查特定于文件类型的属性
          const fileTypeAttributes = [
            'src',
            'data-src',
            `data-${_filePattern}`,
            `${_filePattern}-url`,
            `data-${_filePattern}-url`,
            'data-video-url'
          ];
          
          fileTypeAttributes.forEach(attr => {
            const value = element.getAttribute(attr);
            if (value) processM3U8Url(value, 0);
          });
        });

        // 检查其他可能包含视频源的元素
        const videoContainers = doc.querySelectorAll([
          '[class*="video"]',
          '[class*="player"]',
          '[id*="video"]',
          '[id*="player"]',
          // 添加特定于文件类型的选择器
          '[class*="${_filePattern}"]',
          '[id*="${_filePattern}"]',
          '[data-${_filePattern}]',
          '[data-video-type="${_filePattern}"]'
        ].join(','));

        videoContainers.forEach(container => {
          // 检查所有data属性
          for (const attr of container.attributes) {
            if (attr.value) processM3U8Url(attr.value, 0);
          }
        });

        // 设置媒体元素变化监控
        doc.querySelectorAll('video,source').forEach(element => {
          const elementObserver = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
              if (mutation.type === 'attributes') {
                const newValue = element.getAttribute(mutation.attributeName);
                if (newValue) {
                  processM3U8Url(newValue, 0);
                }
              }
            });
          });

          elementObserver.observe(element, {
            attributes: true,
            attributeFilter: ['src', 'currentSrc', 'data-src']
          });
        });
      }

      // 高效的DOM扫描
      function efficientDOMScan() {
        // 优先扫描明显的链接
        const elements = document.querySelectorAll([
          'a[href*="${_filePattern}"]',          
          'source[src*="${_filePattern}"]',   
          'video[src*="${_filePattern}"]',    
          '[data-src*="${_filePattern}"]'      
        ].join(','));

        elements.forEach(element => {
          for (const attr of ['href', 'src', 'data-src']) {
            const value = element.getAttribute(attr);
            if (value) processM3U8Url(value, 0);
          }
        });

        // 扫描script标签中的内容
        document.querySelectorAll('script:not([src])').forEach(script => {
          const content = script.textContent;
          if (content) {
            const urlRegex = new RegExp(`https?:\\/\\/[^\\s<>"]+?\\.${_filePattern}[^\\s<>"']*`, 'g');
            const matches = content.match(urlRegex);
            if (matches) {
              matches.forEach(match => {
                processM3U8Url(match, 0);
              });
            }
          }
        });
      }

      // 设置DOM观察器
      observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          // 处理新添加的节点
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === 1) {
              // 如果是视频相关元素，优先处理
              if (node.tagName === 'VIDEO' ||
                  node.tagName === 'SOURCE' ||
                  node.matches('[class*="video"], [class*="player"]')) {
                checkMediaElements(node.parentNode);
              }

              // 检查新添加元素的所有属性
              if (node instanceof Element) {
                for (const attr of node.attributes) {
                  if (attr.value) {
                    processM3U8Url(attr.value, 0);
                  }
                }
              }
            }
          });

          // 处理属性变化
          if (mutation.type === 'attributes') {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue) {
              processM3U8Url(newValue, 0);
            }
          }
        });
      });

      // 启动观察器，设置更具体的配置
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: [
          'src', 
          'href', 
          'data-src', 
          'currentSrc',
          `data-${_filePattern}`,
          `${_filePattern}-url`,
          `data-${_filePattern}-url`
        ],
        characterData: false
      });

      // 执行初始检查
      checkMediaElements(document);
      efficientDOMScan();

      // 监听URL变化
      let urlChangeTimeout = null;
      const handleUrlChange = () => {
        if (urlChangeTimeout) {
          clearTimeout(urlChangeTimeout);
        }
        urlChangeTimeout = setTimeout(() => {
          checkMediaElements(document);
          efficientDOMScan();
        }, 100);
      };

      window.addEventListener('popstate', handleUrlChange);
      window.addEventListener('hashchange', handleUrlChange);

    })();
  ''';

  try {
    LogUtil.i('执行JS代码注入');
    _controller.runJavaScript(jsCode).then((_) {
      LogUtil.i('JS代码注入成功');
      _isDetectorInjected = true;  // 标记为已注入
    }).catchError((error) {
      LogUtil.e('JS代码注入失败: $error');
    });
  } catch (e, stackTrace) {
    LogUtil.logError('执行JS代码时发生错误', e, stackTrace);
  }
}

  Future<void> dispose() async {
    await disposeResources();
  }
}
