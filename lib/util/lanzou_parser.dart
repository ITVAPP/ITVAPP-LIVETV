import 'dart:convert';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 缓存条目类
class CacheEntry {
  final String url;
  final DateTime expireTime;
  final DateTime accessTime; // 添加访问时间，用于LRU策略
  
  CacheEntry({
    required this.url,
    required this.expireTime,
    DateTime? accessTime,
  }) : accessTime = accessTime ?? DateTime.now();
  
  bool get isExpired => DateTime.now().isAfter(expireTime);
  
  // 创建访问时间更新的副本
  CacheEntry withUpdatedAccessTime() {
    return CacheEntry(
      url: url,
      expireTime: expireTime,
      accessTime: DateTime.now(),
    );
  }
}

/// 蓝奏云解析工具，用于提取蓝奏云下载链接
class LanzouParser {
  static const String baseUrl = 'https://lanzoux.com';
  static const String errorResult = 'ERROR';
  static const int maxRetries = 2;  // 最大重试次数
  
  // 定义统一的超时常量
  static const Duration requestTimeout = Duration(seconds: 8);  // 请求超时时间
  static const Duration connectTimeout = Duration(seconds: 5);  // 连接超时时间
  static const Duration receiveTimeout = Duration(seconds: 10); // 接收超时时间
  static const int cacheMaxSize = 100; // 缓存最大条目数，防止内存占用过高
  static const int cacheCleanupThreshold = 90; // 缓存清理阈值，避免频繁清理

  // 【优化】使用LinkedHashMap实现LRU缓存，保持插入顺序
  static final LinkedHashMap<String, CacheEntry> _urlCache = LinkedHashMap<String, CacheEntry>();
  // 记录上次清理时间，用于惰性清理
  static DateTime _lastCleanupTime = DateTime.now();

  // 正则表达式定义，用于匹配不同信息
  static final RegExp _pwdRegex = RegExp(r'[?&]pwd=([^&]+)'); // 匹配密码参数
  static final RegExp _lanzouUrlRegex = RegExp(r'https?://(?:[a-zA-Z\d-]+\.)?lanzou[a-z]\.com/(?:[^/]+/)?([a-zA-Z\d]+)'); // 匹配蓝奏云链接格式
  static final RegExp _iframeRegex = RegExp(r'src="(\/fn\?[a-zA-Z\d_+/=]{16,})"'); // 匹配iframe链接
  static final RegExp _typeRegex = RegExp(r'[?&]type=([^&]+)'); // 匹配文件类型参数
  
  // 【优化】将URL参数清理正则定义为静态常量，避免重复创建
  static final RegExp _urlParamsCleanRegex = RegExp(r'[?&](pwd|type)=[^&]*');
  
  // 【优化1】将sign正则表达式按使用频率排序，最常用的放在前面
  static final List<RegExp> _signRegexes = [
    RegExp(r"'sign':'([^']+)'"), // 最常见的格式，放在首位
    RegExp(r'"sign":"([^"]+)"'), // 第二常见的格式
    RegExp(r"var\s+sg\s*=\s*'([^']+)'"), // 变量赋值形式
    RegExp(r"'([a-zA-Z0-9_+-/]{50,})'"), // 长字符串匹配，放在后面
    RegExp(r"data\s*:\s*'([^']+)'") // data格式，最后检查
  ];

  /// 通用HTTP请求方法，统一处理重试、超时和异常
  /// @param method 请求方法（GET/POST/HEAD）
  /// @param url 请求URL
  /// @param body 请求体数据，仅用于POST请求
  /// @param followRedirect 是否自动跟踪重定向
  /// @param cancelToken 用于取消请求的Token
  /// @return 请求响应内容或null（失败时）
  static Future<Response<dynamic>?> _makeHttpRequest(
    String method,
    String url, {
    String? body,
    bool followRedirect = true,
    CancelToken? cancelToken,
  }) async {
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        final headers = HeadersConfig.generateHeaders(url: url);
        if (method.toUpperCase() == 'POST') {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
        
        final options = Options(
          method: method.toUpperCase(),
          headers: headers,
          followRedirects: followRedirect,
          extra: {
            'connectTimeout': connectTimeout,
            'receiveTimeout': receiveTimeout,
          },
        );
        
        // 【优化】简化HTTP请求逻辑，消除switch重复代码
        Response<dynamic>? response;
        final httpUtil = HttpUtil();
        
        if (method.toUpperCase() == 'POST') {
          response = await httpUtil.postRequestWithResponse(
            url,
            data: body,
            options: options,
            cancelToken: cancelToken,
          ).timeout(requestTimeout);
        } else {
          response = await httpUtil.getRequestWithResponse(
            url,
            options: options,
            cancelToken: cancelToken,
          ).timeout(requestTimeout);
        }
        
        if (response?.statusCode == 200 || 
            response?.statusCode == 301 || 
            response?.statusCode == 302) {
          return response;
        }
        
        LogUtil.i('HTTP请求失败，状态码: ${response?.statusCode}');
      } catch (e, stack) {
        if (cancelToken?.isCancelled ?? false) {
          LogUtil.i('请求被取消: $url');
          return null;
        }
        LogUtil.logError('HTTP请求异常', e, stack);
        if (++retryCount < maxRetries) {
          // 指数退避策略
          await Future.delayed(Duration(seconds: retryCount * 2));
          continue;
        }
      }
      break;
    }
    return null;
  }
  
  /// 通用方法获取HTTP响应内容
  /// @param method 请求方法（GET/POST）
  /// @param url 请求URL
  /// @param body 请求体数据，仅用于POST请求
  /// @param cancelToken 用于取消请求的Token
  /// @return 响应内容字符串或null（失败时）
  static Future<String?> _makeRequestWithRetry(
    String method,
    String url, {
    String? body,
    CancelToken? cancelToken, 
  }) async {
    final response = await _makeHttpRequest(
      method, 
      url, 
      body: body, 
      cancelToken: cancelToken
    );
    
    return response?.data?.toString();
  }

  /// 使用HEAD请求方法获取页面重定向的最终URL，或在无重定向时直接返回输入URL
  static Future<String?> _getFinalUrl(String url, {CancelToken? cancelToken}) async {
    final response = await _makeHttpRequest(
      'HEAD', 
      url, 
      followRedirect: false, 
      cancelToken: cancelToken
    );
    
    if (response != null) {
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectUrl = response.headers.value('location');
        if (redirectUrl != null) {
          LogUtil.i('获取到重定向URL: $redirectUrl');
          return redirectUrl;
        }
      } else if (response.statusCode == 200) {
        return url;
      }
      
      LogUtil.i('未获取到重定向URL，状态码: ${response.statusCode}');
    }

    // 添加GET请求作为HEAD失败时的备用方案，提升兼容性
    final getResponse = await _makeHttpRequest('GET', url, cancelToken: cancelToken);
    if (getResponse?.statusCode == 200) return url;
    
    LogUtil.i('未获取到重定向URL，状态码: ${getResponse?.statusCode}');
    return null;
  }
  
  /// 【优化2】标准化蓝奏云链接，减少字符串操作次数
  static String _standardizeLanzouUrl(String url) {
    // 【优化】使用预定义的正则表达式，避免重复创建
    final cleanUrl = url.replaceAll(_urlParamsCleanRegex, '');
    
    final match = _lanzouUrlRegex.firstMatch(cleanUrl);
    
    if (match != null && match.groupCount >= 1) {
      return '$baseUrl/${match.group(1)}';
    }

    LogUtil.i('URL标准化失败，使用原始URL');
    return cleanUrl;
  }
  
  /// 提取页面中的JavaScript内容
  static String? _extractJsContent(String html) {
    const jsStart = '<script type="text/javascript">';
    const jsEnd = '</script>';
    
    final lastIndex = html.lastIndexOf(jsStart);
    if (lastIndex == -1) {
      LogUtil.i('未找到JavaScript标签起始位置');
      return null;
    }
    
    final startPos = lastIndex + jsStart.length;
    final endPos = html.indexOf(jsEnd, startPos);
    if (endPos == -1) {
      LogUtil.i('未找到JavaScript标签结束位置');
      return null;
    }
    
    final jsContent = html.substring(startPos, endPos);
    LogUtil.i('成功提取JavaScript内容，长度: ${jsContent.length}');
    return jsContent;
  }

  /// 【优化3】提取sign参数，优化匹配策略
  static String? _extractSign(String html) {
    final jsCode = _extractJsContent(html);
    if (jsCode == null) {
      LogUtil.i('JavaScript代码提取失败');
      return null;
    }

    // 按频率顺序匹配，大多数情况下在前两次就能匹配成功
    for (final regex in _signRegexes) {
      final match = regex.firstMatch(jsCode);
      if (match != null && match.groupCount >= 1) {
        final sign = match.group(1);
        LogUtil.i('成功提取sign参数: ${sign?.substring(0, min(10, sign?.length ?? 0))}...');
        return sign;
      }
    }

    // 备用方案：在整个HTML中搜索data对象
    final dataMatch = RegExp(r'data\s*:\s*(\{[^\}]+\})').firstMatch(html);
    if (dataMatch != null) {
      final dataObj = dataMatch.group(1);
      if (dataObj != null) {
        final signMatch = RegExp(r'"sign":"([^"]+)"').firstMatch(dataObj);
        if (signMatch != null) {
          return signMatch.group(1);
        }
      }
    }

    LogUtil.i('未能提取到sign参数');
    return null;
  }

  /// 从JSON响应中提取下载URL并获取最终直链
  static Future<String> _extractDownloadUrl(String response, {CancelToken? cancelToken}) async {
    try {
      final json = jsonDecode(response);
      if (json['zt'] != 1) {
        LogUtil.i('响应状态码不正确: ${json['zt']}');
        return errorResult;
      }

      final dom = (json['dom'] as String).replaceAll(r'\/', '/');
      final url = (json['url'] as String).replaceAll(r'\/', '/');
      
      if (dom.isEmpty || url.isEmpty) {
        LogUtil.i('dom或url为空');
        return errorResult;
      }
      
      final downloadUrl = '$dom/file/$url';
      final finalUrl = await _getFinalUrl(downloadUrl, cancelToken: cancelToken);
      if (finalUrl != null) {
        LogUtil.i('成功获取最终下载链接');
        return finalUrl;
      } else {
        LogUtil.i('未能获取最终链接，返回中转链接');
        return downloadUrl;
      }
    } catch (e, stack) {
      LogUtil.logError('解析下载URL时发生错误', e, stack);
      return errorResult;
    }
  }

  /// 【优化】惰性清理过期缓存
  static void _cleanupExpiredCache() {
    final now = DateTime.now();
    // 每小时最多清理一次，避免频繁清理
    if (now.difference(_lastCleanupTime).inHours < 1) {
      return;
    }
    
    _urlCache.removeWhere((key, entry) => entry.isExpired);
    _lastCleanupTime = now;
    LogUtil.i('已清理过期缓存，当前缓存数: ${_urlCache.length}');
  }

  /// 【优化】更新缓存访问时间，实现LRU
  static void _updateCacheAccess(String key, CacheEntry entry) {
    // 在LinkedHashMap中，删除再插入可以更新顺序
    _urlCache.remove(key);
    _urlCache[key] = entry.withUpdatedAccessTime();
  }

  /// 【优化4】管理URL缓存，优化的LRU策略实现
  /// @param url 要缓存的原始URL
  /// @param finalUrl 解析后的最终URL
  static void _manageCache(String url, String finalUrl) {
    if (finalUrl == errorResult) return;
    
    // 仅在缓存接近满时清理过期项
    if (_urlCache.length >= cacheCleanupThreshold) {
      _cleanupExpiredCache();
    }
    
    // 如果缓存达到上限，移除最早的条目（LinkedHashMap保持插入顺序）
    if (_urlCache.length >= cacheMaxSize) {
      final oldestKey = _urlCache.keys.first;
      _urlCache.remove(oldestKey);
      LogUtil.i('缓存已满，移除最久未使用的条目: $oldestKey');
    }
    
    // 添加新缓存条目，24小时有效期
    _urlCache[url] = CacheEntry(
      url: finalUrl,
      expireTime: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  /// 获取蓝奏云直链下载地址
  static Future<String> getLanzouUrl(String url, {CancelToken? cancelToken}) async {
    // 检查缓存
    final cacheEntry = _urlCache[url];
    if (cacheEntry != null && !cacheEntry.isExpired) {
      // 【优化】使用LRU更新访问顺序
      _updateCacheAccess(url, cacheEntry);
      LogUtil.i('使用缓存的URL结果');
      return cacheEntry.url;
    }

    try {
      String? filename;
      final typeMatch = _typeRegex.firstMatch(url);
      if (typeMatch != null) {
        filename = typeMatch.group(1);
        LogUtil.i('提取到文件名: $filename');
      }

      String? pwd;
      final pwdMatch = _pwdRegex.firstMatch(url);
      if (pwdMatch != null) {
        pwd = pwdMatch.group(1);
      }

      final standardUrl = _standardizeLanzouUrl(url);
      
      final html = await _makeRequestWithRetry('GET', standardUrl, cancelToken: cancelToken);
      if (html == null) {
        LogUtil.e('获取页面内容失败');
        return errorResult;
      }

      final needsPwd = html.contains('请输入密码');
      if (needsPwd && pwd == null) {
        LogUtil.i('需要密码但未提供密码');
        return errorResult;
      }

      String finalUrl;
      if (needsPwd && pwd != null) {
        finalUrl = await _handlePasswordProtectedUrl(html, pwd, filename, cancelToken: cancelToken);
      } else {
        finalUrl = await _handleNormalUrl(html, filename, cancelToken: cancelToken);
      }

      // 缓存结果
      _manageCache(url, finalUrl);
      return finalUrl;

    } catch (e, stack) {
      if (cancelToken?.isCancelled ?? false) { 
        LogUtil.i('解析被取消: $url');
        return errorResult;
      }
      LogUtil.logError('解析过程发生异常', e, stack);
      return errorResult;
    }
  }

  /// 处理需要密码的URL
  static Future<String> _handlePasswordProtectedUrl(
    String html,
    String pwd,
    String? filename,
    {CancelToken? cancelToken}
  ) async {
    var actionData = '';
    final oldData = RegExp(r"data\s*:\s*'([^']+)'").firstMatch(html)?.group(1);
    
    if (oldData != null) {
      LogUtil.i('使用老版本密码处理方式');
      actionData = '$oldData$pwd';
    } else {
      LogUtil.i('使用新版本密码处理方式');
      final sign = _extractSign(html);
      if (sign == null) {
        LogUtil.e('提取sign参数失败');
        return errorResult;
      }
      actionData = 'action=downprocess&sign=$sign&p=$pwd';
    }

    final pwdResult = await _makeRequestWithRetry(
      'POST',
      '$baseUrl/ajaxm.php',
      body: actionData,
      cancelToken: cancelToken 
    );
    
    if (pwdResult == null || !pwdResult.contains('"zt":1')) {
      LogUtil.e('密码验证失败');
      return errorResult;
    }

    final downloadUrl = await _extractDownloadUrl(pwdResult, cancelToken: cancelToken);
    if (filename != null) {
      return '$downloadUrl?$filename';
    }
    return downloadUrl;
  }

  /// 处理普通URL
  static Future<String> _handleNormalUrl(
    String html,
    String? filename,
    {CancelToken? cancelToken} 
  ) async {
    final iframeMatch = _iframeRegex.firstMatch(html);
    if (iframeMatch == null) {
      LogUtil.e('未找到iframe链接');
      return errorResult;
    }

    final iframePath = iframeMatch.group(1)!;
    final iframeUrl = '$baseUrl$iframePath';
    LogUtil.i('获取到iframe URL: $iframeUrl');
    
    final iframeContent = await _makeRequestWithRetry('GET', iframeUrl, cancelToken: cancelToken); 
    if (iframeContent == null) {
      LogUtil.e('获取iframe内容失败');
      return errorResult;
    }

    final sign = _extractSign(iframeContent);
    if (sign == null) {
      LogUtil.e('从iframe内容中提取sign失败');
      return errorResult;
    }

    final ajaxResult = await _makeRequestWithRetry(
      'POST',
      '$baseUrl/ajaxm.php',
      body: 'action=downprocess&sign=$sign&ves=1',
      cancelToken: cancelToken
    );
    
    if (ajaxResult == null) {
      LogUtil.e('获取下载链接失败');
      return errorResult;
    }

    final downloadUrl = await _extractDownloadUrl(ajaxResult, cancelToken: cancelToken);
    if (filename != null) {
      return '$downloadUrl?$filename';
    }
    return downloadUrl;
  }
  
  /// 辅助方法：返回两个数字中较小的一个
  static int min(int a, int b) => a < b ? a : b;
}
