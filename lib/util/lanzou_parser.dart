import 'package:http/http.dart' as http;
import 'dart:convert';
import 'log_util.dart';

/// 蓝奏云解析工具
class LanzouParser {
  static const String baseUrl = 'https://lanzoux.com';
  static const String errorResult = 'ERROR';

  // 正则表达式定义
  static final RegExp _pwdRegex = RegExp(r'[?&]pwd=([^&]+)');
  static final RegExp _lanzouUrlRegex = RegExp(r'https?://(?:[a-zA-Z\d-]+\.)?lanzou[a-z]\.com/(?:[^/]+/)?([a-zA-Z\d]+)');
  static final RegExp _iframeRegex = RegExp(r'src="(\/fn\?[a-zA-Z\d_+/=]{16,})"');
  // 这里是修复的地方：将 RegExp 改为 List<RegExp>
  static final List<RegExp> _signRegexes = [
    RegExp(r"'sign':'([^']+)'"),
    RegExp(r'"sign":"([^"]+)"'),
    RegExp(r"var\s+sg\s*=\s*'([^']+)'"),
    RegExp(r"'([a-zA-Z0-9_+-/]{50,})'"),
    RegExp(r"data\s*:\s*'([^']+)'")
  ];

  /// 获取通用请求头
  static Map<String, String> _getHeaders(String referer) {
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      if (referer.isNotEmpty) 'Referer': referer,
    };
  }

  /// 标准化蓝奏云链接
  static String _standardizeLanzouUrl(String url) {
    final urlWithoutPwd = url.replaceAll(_pwdRegex, '');
    final match = _lanzouUrlRegex.firstMatch(urlWithoutPwd);
    if (match != null && match.groupCount >= 1) {
      final standardUrl = '$baseUrl/${match.group(1)}';
      return standardUrl;
    }
    LogUtil.i('URL标准化失败，使用原始URL');
    return urlWithoutPwd;
  }
  
  /// 提取JavaScript参数
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

    // 依次尝试不同的正则表达式匹配
    for (final regex in _signRegexes) {
      final match = regex.firstMatch(jsCode);
      if (match != null && match.groupCount >= 1) {
        final sign = match.group(1);
        LogUtil.i('成功提取sign参数: ${sign?.substring(0, 10)}...');
        return sign;
      }
    }

    // 尝试提取完整的data对象
    final dataMatch = RegExp(r'data\s*:\s*(\{[^\}]+\})').firstMatch(html);
    if (dataMatch != null) {
      final dataObj = dataMatch.group(1);
      if (dataObj != null) {
        final signMatch = RegExp(r'"sign":"([^"]+)"').firstMatch(dataObj);
        if (signMatch != null) {
          final sign = signMatch.group(1);
          return sign;
        }
      }
    }

    LogUtil.i('未能提取到sign参数');
    return null;
  }

  /// 提取下载URL从JSON响应
  static String _extractDownloadUrl(String response) {
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
      return downloadUrl;
    } catch (e) {
      LogUtil.e('解析下载URL时发生错误: $e');
      return errorResult;
    }
  }
  
  /// 发送HTTP请求
  static Future<String?> _makeRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) async {
    if (body != null) LogUtil.i('请求体: $body');

    try {
      http.Response response;
      final uri = Uri.parse(url);

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: {...headers ?? {}, 'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          );
          break;
        default:
          LogUtil.e('不支持的HTTP方法: $method');
          return null;
      }

      if (response.statusCode != 200) {
        LogUtil.i('HTTP请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final responseBody = utf8.decode(response.bodyBytes);
      return responseBody;
    } catch (e) {
      LogUtil.e('HTTP请求异常: $e');
      return null;
    }
  }

  /// 获取蓝奏云直链下载地址
  static Future<String> getLanzouUrl(String url) async {
    try {
      // 1. 从URL中提取密码
      String? pwd;
      final pwdMatch = _pwdRegex.firstMatch(url);
      if (pwdMatch != null) {
        pwd = pwdMatch.group(1);
      }

      // 2. 标准化URL
      final standardUrl = _standardizeLanzouUrl(url);
      
      // 3. 获取页面内容
      final html = await _makeRequest('GET', standardUrl, headers: _getHeaders(''));
      if (html == null) {
        LogUtil.e('获取页面内容失败');
        return errorResult;
      }

      // 4. 判断是否需要密码
      final needsPwd = html.contains('请输入密码');
      
      if (needsPwd && pwd == null) {
        LogUtil.i('需要密码但未提供密码');
        return errorResult;
      }

      // 5. 处理需要密码的情况
      if (needsPwd && pwd != null) {
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

        final pwdResult = await _makeRequest(
          'POST', 
          '$baseUrl/ajaxm.php',
          headers: _getHeaders(standardUrl),
          body: actionData
        );
        
        if (pwdResult == null || !pwdResult.contains('"zt":1')) {
          LogUtil.e('密码验证失败');
          return errorResult;
        }

        return _extractDownloadUrl(pwdResult);
      }

      // 6. 处理无密码的情况
      final iframeMatch = _iframeRegex.firstMatch(html);
      if (iframeMatch == null) {
        LogUtil.e('未找到iframe链接');
        return errorResult;
      }

      final iframePath = iframeMatch.group(1)!;
      final iframeUrl = '$baseUrl$iframePath';
      LogUtil.i('获取到iframe URL: $iframeUrl');
      
      final iframeContent = await _makeRequest(
        'GET',
        iframeUrl,
        headers: _getHeaders(standardUrl)
      );
      if (iframeContent == null) {
        LogUtil.e('获取iframe内容失败');
        return errorResult;
      }

      final sign = _extractSign(iframeContent);
      if (sign == null) {
        LogUtil.e('从iframe内容中提取sign失败');
        return errorResult;
      }

      final ajaxResult = await _makeRequest(
        'POST',
        '$baseUrl/ajaxm.php',
        headers: _getHeaders(iframeUrl),
        body: 'action=downprocess&sign=$sign&ves=1'
      );
      if (ajaxResult == null) {
        LogUtil.e('获取下载链接失败');
        return errorResult;
      }

      return _extractDownloadUrl(ajaxResult);

    } catch (e, stack) {
      LogUtil.logError('解析过程发生异常', e, stack);
      return errorResult;
    }
  }
}