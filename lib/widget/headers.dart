import 'package:itvapp_live_tv/util/log_util.dart';

/// HTTP请求Headers配置工具类
class HeadersConfig {
  const HeadersConfig._();
  
  static const String _chromeVersion = '121.0.0.0';
  
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36';
  
  /// 生成请求headers
  static Map<String, String> generateHeaders({
    required String url,
  }) {
    try {
      final encodedUrl = Uri.encodeFull(url);
      final uri = Uri.parse(encodedUrl);
      
      final headers = {
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Host': uri.host,
        'Referer': '${uri.scheme}://${uri.host}/',
        'Pragma': 'no-cache',
        'Sec-Fetch-Site': 'same-site',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
      };
      
      LogUtil.i('生成的Headers: $headers');
      return headers;
    } catch (e, stackTrace) {
      LogUtil.logError('生成Headers失败，使用默认Headers', e, stackTrace);
      
      // 提供默认的 headers
      return {
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Pragma': 'no-cache',
      };
    }
  }
}
