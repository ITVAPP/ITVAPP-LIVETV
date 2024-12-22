import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 蓝奏云解析工具，用于提取蓝奏云下载链接
class LanzouParser {
  static const String baseUrl = 'https://lanzoux.com';
  static const String errorResult = 'ERROR';

  // 正则表达式定义，用于匹配不同信息
  static final RegExp _pwdRegex = RegExp(r'[?&]pwd=([^&]+)'); // 匹配密码参数
  static final RegExp _lanzouUrlRegex = RegExp(r'https?://(?:[a-zA-Z\d-]+\.)?lanzou[a-z]\.com/(?:[^/]+/)?([a-zA-Z\d]+)'); // 匹配蓝奏云链接格式
  static final RegExp _iframeRegex = RegExp(r'src="(\/fn\?[a-zA-Z\d_+/=]{16,})"'); // 匹配iframe链接
  static final RegExp _typeRegex = RegExp(r'[?&]type=([^&]+)'); // 匹配文件类型参数
  static final List<RegExp> _signRegexes = [
    RegExp(r"'sign':'([^']+)'"),
    RegExp(r'"sign":"([^"]+)"'),
    RegExp(r"var\s+sg\s*=\s*'([^']+)'"),
    RegExp(r"'([a-zA-Z0-9_+-/]{50,})'"),
    RegExp(r"data\s*:\s*'([^']+)'")
  ];

  /// 使用HEAD请求方法获取页面重定向的最终URL，或在无重定向时直接返回输入URL
  static Future<String?> _getFinalUrl(String url) async {
    try {
      final client = http.Client();
      try {
        // 发送 HEAD 请求以获取重定向信息
        final request = http.Request('HEAD', Uri.parse(url))
          ..followRedirects = false;  // 不自动跟随重定向
        
        // 使用 HeadersConfig 替换原有的 headers
        request.headers.addAll(HeadersConfig.generateHeaders(url: url));
        
        // 发送请求
        final response = await client.send(request);
        
        // 如果是重定向状态码
        if (response.statusCode == 302 || response.statusCode == 301) {
          final redirectUrl = response.headers['location'];
          if (redirectUrl != null) {
            LogUtil.i('获取到重定向URL: $redirectUrl');
            return redirectUrl;
          }
        } else if (response.statusCode == 200) {
          // 如果直接返回200，说明这个就是最终URL
          return url;
        }
        
        LogUtil.i('未获取到重定向URL，状态码: ${response.statusCode}');
        return null;
      } finally {
        client.close();
      }
    } catch (e, stack) {
      LogUtil.logError('获取最终URL时发生错误', e, stack);
      return null;
    }
  }
  
  /// 标准化蓝奏云链接
  /// 移除链接中的密码和文件类型参数，返回一个标准化的蓝奏云链接
  static String _standardizeLanzouUrl(String url) {
    final urlWithoutPwd = url.replaceAll(_pwdRegex, ''); // 移除密码参数
    final urlWithoutType = urlWithoutPwd.replaceAll(_typeRegex, ''); // 移除类型参数
    final match = _lanzouUrlRegex.firstMatch(urlWithoutType);
    // 如果匹配成功，则返回标准化URL
    if (match != null && match.groupCount >= 1) {
      final standardUrl = '$baseUrl/${match.group(1)}';
      return standardUrl;
    }
    LogUtil.i('URL标准化失败，使用原始URL');
    return urlWithoutType;
  }
  
  /// 提取页面中的JavaScript内容
  /// 通过定位起始和结束标签提取JavaScript代码
  static String? _extractJsContent(String html) {
    final jsStart = '<script type="text/javascript">'; // JavaScript起始标签
    final jsEnd = '</script>'; // JavaScript结束标签
    
    final lastIndex = html.lastIndexOf(jsStart);
    if (lastIndex == -1) {
      LogUtil.i('未找到JavaScript标签起始位置');
      return null;
    }
    
    final startPos = lastIndex + jsStart.length; // 起始位置
    final endPos = html.indexOf(jsEnd, startPos); // 结束位置
    if (endPos == -1) {
      LogUtil.i('未找到JavaScript标签结束位置');
      return null;
    }
    
    final jsContent = html.substring(startPos, endPos); // 提取JavaScript内容
    LogUtil.i('成功提取JavaScript内容，长度: ${jsContent.length}');
    return jsContent;
  }

  /// 提取sign参数
  /// 尝试使用多个正则表达式匹配JavaScript代码内的sign信息
  static String? _extractSign(String html) {
    final jsCode = _extractJsContent(html);
    if (jsCode == null) {
      LogUtil.i('JavaScript代码提取失败');
      return null;
    }

    // 尝试依次使用不同的正则表达式匹配
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

  /// 修改：从JSON响应中提取下载URL并获取最终直链
  /// 在解析成功的JSON响应中提取下载链接并解析最终的直链URL
  static Future<String> _extractDownloadUrl(String response) async {
    try {
      final json = jsonDecode(response);
      if (json['zt'] != 1) {
        LogUtil.i('响应状态码不正确: ${json['zt']}');
        return errorResult;
      }

      // 替换反斜杠
      final dom = (json['dom'] as String).replaceAll(r'\/', '/');
      final url = (json['url'] as String).replaceAll(r'\/', '/');
      
      if (dom.isEmpty || url.isEmpty) {
        LogUtil.i('dom或url为空');
        return errorResult;
      }
      
      // 先获取中转下载链接
      final downloadUrl = '$dom/file/$url';
      
      // 获取最终直链
      final finalUrl = await _getFinalUrl(downloadUrl);
      if (finalUrl != null) {
        LogUtil.i('成功获取最终下载链接');
        return finalUrl;
      } else {
        LogUtil.i('未能获取最终链接，返回中转链接');
        return downloadUrl;  // 如果获取失败，返回中转链接作为后备方案
      }
    } catch (e, stack) {
      LogUtil.logError('解析下载URL时发生错误', e, stack);
      return errorResult;
    }
  }
  
  /// 根据请求方法发送GET或POST请求，并处理响应
  static Future<String?> _makeRequest(
    String method,
    String url, {
    String? body,
  }) async {
    if (body != null) LogUtil.i('请求体: $body');

    try {
      http.Response response;
      final uri = Uri.parse(url);

      // 使用 HeadersConfig 生成基础 headers
      final headers = HeadersConfig.generateHeaders(url: url);
      
      // 对于POST请求，添加额外的Content-Type header
      if (method.toUpperCase() == 'POST') {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
      }

      // 根据请求方法选择处理逻辑
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body,
          );
          break;
        default:
          LogUtil.e('不支持的HTTP方法: $method');
          return null;
      }

      // 检查响应状态码
      if (response.statusCode != 200) {
        LogUtil.i('HTTP请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final responseBody = utf8.decode(response.bodyBytes); // 处理响应体
      return responseBody;
    } catch (e) {
      LogUtil.e('HTTP请求异常: $e');
      return null;
    }
  }

  /// 获取蓝奏云直链下载地址
  /// 通过分析和请求URL，获取可以直接下载的链接
  static Future<String> getLanzouUrl(String url) async {
    try {
      // 1. 检查并提取type参数，即文件名
      String? filename;
      final typeMatch = _typeRegex.firstMatch(url);
      if (typeMatch != null) {
        filename = typeMatch.group(1);
        LogUtil.i('提取到文件名: $filename');
      }

      // 2. 从URL中提取密码
      String? pwd;
      final pwdMatch = _pwdRegex.firstMatch(url);
      if (pwdMatch != null) {
        pwd = pwdMatch.group(1); // 提取密码
      }

      // 3. 标准化URL
      final standardUrl = _standardizeLanzouUrl(url);
      
      // 4. 获取页面内容
      final html = await _makeRequest('GET', standardUrl);
      if (html == null) {
        LogUtil.e('获取页面内容失败');
        return errorResult;
      }

      // 5. 判断是否需要密码
      final needsPwd = html.contains('请输入密码');
      
      // 如果需要密码但未提供，返回错误
      if (needsPwd && pwd == null) {
        LogUtil.i('需要密码但未提供密码');
        return errorResult;
      }

      // 6. 处理需要密码的情况
      if (needsPwd && pwd != null) {
        var actionData = '';
        // 检查是否使用老版本密码处理方式
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

        // 发送POST请求进行密码验证
        final pwdResult = await _makeRequest(
          'POST', 
          '$baseUrl/ajaxm.php',
          body: actionData
        );
        
        if (pwdResult == null || !pwdResult.contains('"zt":1')) {
          LogUtil.e('密码验证失败');
          return errorResult;
        }

        // 解析最终下载链接
        final downloadUrl = await _extractDownloadUrl(pwdResult);
        // 如果提取到文件名，将其附加到下载链接
        if (filename != null) {
          return '$downloadUrl?$filename';
        }
        return downloadUrl;
      }

      // 7. 处理无需密码的情况
      final iframeMatch = _iframeRegex.firstMatch(html);
      if (iframeMatch == null) {
        LogUtil.e('未找到iframe链接');
        return errorResult;
      }

      final iframePath = iframeMatch.group(1)!;
      final iframeUrl = '$baseUrl$iframePath';
      LogUtil.i('获取到iframe URL: $iframeUrl');
      
      // 请求iframe的内容
      final iframeContent = await _makeRequest('GET', iframeUrl);
      if (iframeContent == null) {
        LogUtil.e('获取iframe内容失败');
        return errorResult;
      }

      // 从iframe内容中提取sign参数
      final sign = _extractSign(iframeContent);
      if (sign == null) {
        LogUtil.e('从iframe内容中提取sign失败');
        return errorResult;
      }

      // 发送请求获取下载链接
      final ajaxResult = await _makeRequest(
        'POST',
        '$baseUrl/ajaxm.php',
        body: 'action=downprocess&sign=$sign&ves=1'
      );
      if (ajaxResult == null) {
        LogUtil.e('获取下载链接失败');
        return errorResult;
      }

      // 解析最终下载链接
      final downloadUrl = await _extractDownloadUrl(ajaxResult);
      // 如果提取到文件名，将其附加到下载链接
      if (filename != null) {
        return '$downloadUrl?$filename';
      }
      return downloadUrl;

    } catch (e, stack) {
      LogUtil.logError('解析过程发生异常', e, stack);
      return errorResult;
    }
  }
}
