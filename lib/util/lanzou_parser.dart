import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 缓存条目类
class CacheEntry {
  final String url;
  final DateTime expireTime;
  
  CacheEntry({
    required this.url,
    required this.expireTime,
  });
  
  bool get isExpired => DateTime.now().isAfter(expireTime);
}

/// 蓝奏云解析工具，用于提取蓝奏云下载链接
class LanzouParser {
  static const String baseUrl = 'https://lanzoux.com';
  static const String errorResult = 'ERROR';
  static const int maxRetries = 2;  // 最大重试次数
  static const Duration requestTimeout = Duration(seconds: 8);  // 请求超时时间
  
  // 缓存解析结果
  static final Map<String, CacheEntry> _urlCache = <String, CacheEntry>{};

  // 正则表达式定义，用于匹配不同信息
  static final RegExp _pwdRegex = RegExp(r'[?&]pwd=([^&]+)'); // 匹配密码参数
  static final RegExp _lanzouUrlRegex = RegExp(r'https?://(?:[a-zA-Z\d-]+\.)?lanzou[a-z]\.com/(?:[^/]+/)?([a-zA-Z\d]+)'); // 匹配蓝奏云链接格式
  static final RegExp _iframeRegex = RegExp(r'src="(\/fn\?[a-zA-Z\d_+/=]{16,})"'); // 匹配iframe链接
  static final RegExp _typeRegex = RegExp(r'[?&]type=([^&]+)'); // 匹配文件类型参数
  
  // 预编译组合正则表达式，提高性能
  static final RegExp _compiledRegexes = RegExp(
    '${_pwdRegex.pattern}|${_lanzouUrlRegex.pattern}|${_iframeRegex.pattern}|${_typeRegex.pattern}',
    multiLine: true
  );

  static final List<RegExp> _signRegexes = [
    RegExp(r"'sign':'([^']+)'"),
    RegExp(r'"sign":"([^"]+)"'),
    RegExp(r"var\s+sg\s*=\s*'([^']+)'"),
    RegExp(r"'([a-zA-Z0-9_+-/]{50,})'"),
    RegExp(r"data\s*:\s*'([^']+)'")
  ];

  /// 使用HEAD请求方法获取页面重定向的最终URL，或在无重定向时直接返回输入URL
  static Future<String?> _getFinalUrl(String url) async {
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        final response = await HttpUtil().getRequestWithResponse(
          url,
          options: Options(
            method: 'HEAD',
            headers: HeadersConfig.generateHeaders(url: url),
            followRedirects: false,
            connectTimeout: const Duration(seconds: 5), // 自定义连接超时
            receiveTimeout: const Duration(seconds: 8), // 自定义接收超时
          ),
        ).timeout(requestTimeout); // 添加超时处理
        
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
      } catch (e, stack) {
        LogUtil.logError('获取最终URL时发生错误', e, stack);
        if (++retryCount < maxRetries) {
          await Future.delayed(Duration(seconds: retryCount * 2));  // 指数退避
          continue;
        }
      }
      break;
    }
    return null;
  }
  
  /// 标准化蓝奏云链接
  static String _standardizeLanzouUrl(String url) {
    final buffer = StringBuffer();
    final urlWithoutPwd = url.replaceAll(_pwdRegex, '');
    final urlWithoutType = urlWithoutPwd.replaceAll(_typeRegex, '');
    final match = _lanzouUrlRegex.firstMatch(urlWithoutType);
    
    if (match != null && match.groupCount >= 1) {
      buffer
        ..write(baseUrl)
        ..write('/')
        ..write(match.group(1));
      return buffer.toString();
    }
    LogUtil.i('URL标准化失败，使用原始URL');
    return urlWithoutType;
  }
  
  /// 提取页面中的JavaScript内容
  static String? _extractJsContent(String html) {
    final jsStart = '<script type="text/javascript">';
    final jsEnd = '</script>';
    
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

  /// 提取sign参数
  static String? _extractSign(String html) {
    final jsCode = _extractJsContent(html);
    if (jsCode == null) {
      LogUtil.i('JavaScript代码提取失败');
      return null;
    }

    for (final regex in _signRegexes) {
      final match = regex.firstMatch(jsCode);
      if (match != null && match.groupCount >= 1) {
        final sign = match.group(1);
        LogUtil.i('成功提取sign参数: ${sign?.substring(0, 10)}...');
        return sign;
      }
    }

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
  static Future<String> _extractDownloadUrl(String response) async {
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
      final finalUrl = await _getFinalUrl(downloadUrl);
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

  /// 发送HTTP请求并处理响应
  static Future<String?> _makeRequestWithRetry(
    String method,
    String url, {
    String? body,
  }) async {
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        final headers = HeadersConfig.generateHeaders(url: url);
        if (method.toUpperCase() == 'POST') {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }

        final response = method.toUpperCase() == 'POST'
            ? await HttpUtil().postRequestWithResponse(
                url,
                data: body,
                options: Options(
                  headers: headers,
                  connectTimeout: const Duration(seconds: 5), // 自定义连接超时
                  receiveTimeout: const Duration(seconds: 8), // 自定义接收超时
                ),
              ).timeout(requestTimeout)
            : await HttpUtil().getRequestWithResponse(
                url,
                options: Options(
                  headers: headers,
                  connectTimeout: const Duration(seconds: 5), // 自定义连接超时
                  receiveTimeout: const Duration(seconds: 8), // 自定义接收超时
                ),
              ).timeout(requestTimeout);

        if (response != null && response.statusCode == 200) {
          return response.data as String;
        }
        
        LogUtil.i('HTTP请求失败，状态码: ${response?.statusCode}');
      } catch (e) {
        LogUtil.e('HTTP请求异常: $e');
        if (++retryCount < maxRetries) {
          await Future.delayed(Duration(seconds: retryCount * 2));
          continue;
        }
      }
      break;
    }
    return null;
  }

  /// 获取蓝奏云直链下载地址
  static Future<String> getLanzouUrl(String url) async {
    // 检查缓存
    final cacheEntry = _urlCache[url];
    if (cacheEntry != null && !cacheEntry.isExpired) {
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
      
      final html = await _makeRequestWithRetry('GET', standardUrl);
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
        finalUrl = await _handlePasswordProtectedUrl(html, pwd, filename);
      } else {
        finalUrl = await _handleNormalUrl(html, filename);
      }

      // 缓存结果（24小时有效期）
      if (finalUrl != errorResult) {
        _urlCache[url] = CacheEntry(
          url: finalUrl,
          expireTime: DateTime.now().add(const Duration(hours: 24)),
        );
      }

      return finalUrl;

    } catch (e, stack) {
      LogUtil.logError('解析过程发生异常', e, stack);
      return errorResult;
    }
  }

  /// 处理需要密码的URL
  static Future<String> _handlePasswordProtectedUrl(
    String html,
    String pwd,
    String? filename,
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
      body: actionData
    );
    
    if (pwdResult == null || !pwdResult.contains('"zt":1')) {
      LogUtil.e('密码验证失败');
      return errorResult;
    }

    final downloadUrl = await _extractDownloadUrl(pwdResult);
    if (filename != null) {
      return '$downloadUrl?$filename';
    }
    return downloadUrl;
  }

  /// 处理普通URL
  static Future<String> _handleNormalUrl(String html, String? filename) async {
    final iframeMatch = _iframeRegex.firstMatch(html);
    if (iframeMatch == null) {
      LogUtil.e('未找到iframe链接');
      return errorResult;
    }

    final iframePath = iframeMatch.group(1)!;
    final iframeUrl = '$baseUrl$iframePath';
    LogUtil.i('获取到iframe URL: $iframeUrl');
    
    final iframeContent = await _makeRequestWithRetry('GET', iframeUrl);
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
      body: 'action=downprocess&sign=$sign&ves=1'
    );
    
    if (ajaxResult == null) {
      LogUtil.e('获取下载链接失败');
      return errorResult;
    }

    final downloadUrl = await _extractDownloadUrl(ajaxResult);
    if (filename != null) {
      return '$downloadUrl?$filename';
    }
    return downloadUrl;
  }
}
