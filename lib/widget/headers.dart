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
    LogUtil.i('开始生成Headers，URL: $url');
    
    final uri = Uri.parse(url);
    LogUtil.i('解析URL: origin=${uri.origin}, host=${uri.host}');
    
    final headers = {
      // 核心浏览器标识
      'User-Agent': _userAgent,
      
      // 内容协商
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      
      // 缓存控制
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      
      // 来源信息
      'Origin': uri.origin,
      'Referer': uri.origin,
      'Host': uri.host,
      
      // 连接控制
      'Connection': 'keep-alive',
      
      // 安全相关
      'Sec-Ch-Ua': '"Not A(Brand";v="99", "Google Chrome";v="$_chromeVersion", "Chromium";v="$_chromeVersion"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"Windows"',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
    };

    LogUtil.i('生成的Headers: $headers');
    return headers;
  }
}
