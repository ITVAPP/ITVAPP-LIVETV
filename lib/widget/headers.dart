import 'package:itvapp_live_tv/util/log_util.dart';

/// HTTP请求Headers配置工具类
class HeadersConfig {
  const HeadersConfig._();
  
  static const String _chromeVersion = '121.0.0.0';
  
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36';

  /// 生成通用请求headers，模拟浏览器行为
  static Map<String, String> generateHeaders({
    required String url,
  }) {
    try {
      // 对 URL 进行编码处理
      final encodedUrl = Uri.encodeFull(url);
      final uri = Uri.parse(encodedUrl);
      
      // 构建 origin: 只包含 scheme 和 host
      final origin = '${uri.scheme}://${uri.host}';
      
      final headers = {
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Host': uri.host,
        'Origin': origin,
        'Referer': origin,
        'Connection': 'keep-alive'
      };
      
      LogUtil.i('生成的Headers: $headers');
      return headers;
    } catch (e, stackTrace) {
      LogUtil.logError('生成Headers失败，使用默认Headers', e, stackTrace);
      
      return {
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive'
      };
    }
  }
}
