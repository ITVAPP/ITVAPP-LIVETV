import 'package:itvapp_live_tv/util/log_util.dart';

/// HTTP请求Headers配置工具类
class HeadersConfig {
  // 私有构造函数
  const HeadersConfig._();
  
  // Chrome 版本号
  static const String _chromeVersion = '121.0.0.0';
  
  // User-Agent
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36';

  /// 生成通用请求headers，模拟浏览器行为
  static Map<String, String> generateHeaders({
    required String url,
  }) {
    final uri = Uri.parse(url);
    final headers = {
      'User-Agent': _userAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Host': uri.host,
      'Origin': uri.origin,
      'Referer': uri.origin,
      'Connection': 'keep-alive'
    };
    LogUtil.i('生成的Headers: $headers');
    return headers;
  }
}
