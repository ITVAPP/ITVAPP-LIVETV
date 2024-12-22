import 'package:itvapp_live_tv/util/log_util.dart';

/// HTTP请求Headers配置工具类
class HeadersConfig {
  const HeadersConfig._();
  
  static const String _chromeVersion = '128.0.0.0';
  
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36 OPR/114.0.0.0';
  
  /// 格式: domain1|referer1@domain2|referer2
  /// 例如: 'googlevideo|www.youtube.com@example.com|example.org'
  static String rulesString = 'googlevideo|www.youtube.com';
  
  /// 解析规则字符串返回域名和对应的referer映射
  static Map<String, String> _parseRules() {
    final rules = <String, String>{};
    
    if (rulesString.isEmpty) return rules;
    
    // 按@分割多条规则
    final ruleList = rulesString.split('@');
    
    for (final rule in ruleList) {
      // 按|分割域名和referer
      final parts = rule.split('|');
      if (parts.length == 2) {
        final domain = parts[0].trim();
        final referer = parts[1].trim();
        if (domain.isNotEmpty && referer.isNotEmpty) {
          rules[domain] = 'https://$referer/';
        }
      }
    }
    
    return rules;
  }
  
  /// 根据规则获取referer
  static String _getRefererByRules(String host) {
    final rules = _parseRules();
    
    // 遍历规则检查host是否匹配
    for (final domain in rules.keys) {
      if (host.contains(domain)) {
        return rules[domain]!;
      }
    }
    
    // 不匹配规则时返回默认referer
    return null;
  }

  /// 生成请求headers
  static Map<String, String> generateHeaders({
    required String url,
  }) {
    try {
      final encodedUrl = Uri.encodeFull(url);
      final uri = Uri.parse(encodedUrl);
      
      // 获取referer
      final customReferer = _getRefererByRules(uri.host);
      final referer = customReferer ?? '${uri.scheme}://${uri.host}/';
      
      final headers = {
        'user-agent': userAgent,
        'accept': '*/*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'accept-encoding': '*',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
        'host': '${uri.host}',
        'referer': referer,
        'Pragma': 'no-cache',
        'sec-ch-ua-platform': 'Windows',
        'sec-ch-ua-mobile': '?0',
        'sec-fetch-site': 'none',
        'sec-fetch-user': '?1',
        'dnt': '1',
      };
      
      LogUtil.i('生成的Headers: $headers');
      return headers;
    } catch (e, stackTrace) {
      LogUtil.logError('生成Headers失败，使用默认Headers', e, stackTrace);
      
      return {
        'user-agent': userAgent,
        'accept': '*/*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'accept-encoding': '*',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
        'Pragma': 'no-cache',
        'sec-ch-ua-platform': 'Windows',
        'sec-ch-ua-mobile': '?0',
        'sec-fetch-site': 'none',
        'sec-fetch-user': '?1',
        'dnt': '1',
      };
    }
  }
}
