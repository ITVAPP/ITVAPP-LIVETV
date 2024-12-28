import 'package:itvapp_live_tv/util/log_util.dart';

/// HTTP请求Headers配置工具类
class HeadersConfig {
 const HeadersConfig._();
 
 static const String _chromeVersion = '128.0.0.0';
 
 static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36 OPR/114.0.0.0';
 
 /// 格式: domain1|referer1@domain2|referer2
 /// 例如: 'googlevideo|www.youtube.com@example.com|example.org'
 static String rulesString = 'googlevideo|www.youtube.com@tcdn.itouchtv.cn|www.gdtv.cn@lanosso.com|lanzoux.com@wwentua.com|lanzoux.com@btime.com|www.btime.com@kksmg.com|live.kankanews.com@wslivehls.com|www.cditv.cn@candocloud.cn|www.cditv.cn@yntv-api.yntv.cn|www.yntv.cn@api.yntv.ynradio.com|www.yntv.cn';

 /// CORS规则字符串，格式: domain1@domain2@domain3
 static String corsRulesString = 'domain.com';

 /// 基础请求头
 static const Map<String, String> _baseHeaders = {
   'user-agent': userAgent,
   'accept': '*/*',
   'accept-language': 'zh-CN,zh-TW;q=0.9,zh;q=0.8',
   'accept-encoding': '*',
   'cache-control': 'no-cache',
   'connection': 'keep-alive',
   'sec-ch-ua-platform': '"Windows"',
   'sec-ch-ua-mobile': '?0',
   'sec-fetch-user': '?1',
   'dnt': '1',
   'sec-fetch-dest': 'empty',
 };

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
         rules[domain] = 'https://$referer';
       }
     }
   }
   
   return rules;
 }

 /// 从URL中提取主机名（支持IPv6）
 static String _extractHost(String url) {
   try {
     final match = RegExp(r'://([^\[\]/]+|\[[^\]]+\])').firstMatch(url);
     if (match != null && match.groupCount >= 1) {
       return match.group(1)!;
     }
     return '';
   } catch (e) {
     return '';
   }
 }

 /// 从URL中提取协议（http/https）
 static String _extractScheme(String url) {
   try {
     final match = RegExp(r'^(https?):').firstMatch(url);
     if (match != null && match.groupCount >= 1) {
       return match.group(1)!;
     }
     return 'http';
   } catch (e) {
     return 'http';
   }
 }

 /// 根据规则获取referer
 static String? _getRefererByRules(String host) {
   final rules = _parseRules();
   
   // 移除IPv6地址的方括号进行匹配
   final cleanHost = host.replaceAll(RegExp(r'[\[\]]'), '');
   
   // 遍历规则检查host是否匹配
   for (final domain in rules.keys) {
     if (cleanHost.contains(domain)) {
       return rules[domain]!;
     }
   }
   
   return null;
 }

 /// 生成请求headers
 static Map<String, String> generateHeaders({
   required String url,
 }) {
   try {
     final encodedUrl = Uri.encodeFull(url);
     final host = _extractHost(encodedUrl);
     final scheme = _extractScheme(encodedUrl);
     
     if (host.isEmpty) {
       throw FormatException('无法解析主机名');
     }

     // 获取referer
     final customReferer = _getRefererByRules(host);
     final referer = customReferer ?? '$scheme://$host';

     // 检查是否需要CORS头
     final corsRules = corsRulesString.split('@');
     final needCors = corsRules.any((domain) => host.contains(domain));
     
     final headers = {
       ..._baseHeaders,
       'origin': referer,
       'referer': '$referer/',
       if (needCors) ...{
         'host': host,
         'sec-fetch-mode': 'cors',
         'sec-fetch-site': 'same-site',
       }
     };

     LogUtil.i('生成主机头：$headers');
     return headers;
     
   } catch (e, stackTrace) {
     LogUtil.logError('生成Headers失败，使用默认Headers', e, stackTrace);
     return _baseHeaders;
   }
 }
}
