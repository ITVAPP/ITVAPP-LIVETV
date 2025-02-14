import 'package:itvapp_live_tv/util/log_util.dart';

/// HTTP请求Headers配置工具类
class HeadersConfig {
 const HeadersConfig._();
 
 static const String _chromeVersion = '128.0.0.0';
 
 static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36 OPR/114.0.0.0';
 
 /// 格式: domain1|referer1@domain2|referer2
 /// 例如: 'googlevideo|www.youtube.com@example.com|example.org'
 static String rulesString = 'googlevideo|www.youtube.com@tcdn.itouchtv.cn|www.gdtv.cn@lanosso.com|lanzoux.com@wwentua.com|lanzoux.com@btime.com|www.btime.com@kksmg.com|live.kankanews.com@iqilu|v.iqilu.com@cditvcn|www.cditv.cn@candocloud.cn|www.cditv.cn@hwapi.yntv.net|cloudxyapi.yntv.net@tvlive.yntv.cn|www.yntv.cn@api.yntv.ynradio.com|www.ynradio.cn@i0834.cn|www.ls666.com@dzxw.net|www.dzrm.cn@zyrb.com.cn|www.sczytv.com@ningxiahuangheyun.com|www.nxtv.com.cn@quklive.com|www.qukanvideo.com@yuexitv|www.yuexitv.com@ahsxrm|www.ahsxrm.cn@liangtv.cn|tv.gxtv.cn@gxtv.cn|www.gxtv.cn@lcxw.cn|www.lcxw.cn@sxtygdy.com|www.sxtygdy.com@sxrtv.com|www.sxrtv.com@tv_radio_47447|live.lzgd.com.cn@51742.hlsplay.aodianyun.com|www.yltvb.com@pubmod.hntv.tv|static.hntv.tv@tvcdn.stream3.hndt.com|static.hntv.tv@jiujiang|www.jjntv.cn@sztv.com.cn|www.sztv.com.cn@jxtvcn.com.cn|www.jxntv.cn@ahtv.cn|www.ahtv.cn@cloudvdn.com|*.jstv.com@hoolo.tv|tv.hoolo.tv@cztv.com|www.cztv.com@cztvcloud.com|www.cztv.com@cjyun.org|app.cjyun.org.cn';

 /// CORS规则字符串，格式: domain1@domain2@domain3
 static String corsRulesString = 'itvapp.net@file.lcxw.cn@51742.hlsplay.aodianyun.com@pubmod.hntv.tv@tvlive.yntv.cn@jxtvcn.com.cn@hls-api.sztv.com.cn@sttv2-api.sztv.com.cn@yun-live.jxtvcn.com.cn@mapi.ahtv.cn@tytv-hls.sxtygdy.com@mapi.hoolo.tv@cjyun.org';

 /// 在此列表中的域名将使用通用播放器请求头，格式: domain1@domain2@domain3
 static String excludeDomainsString = 'loulannews@chinamobile.com@hwapi.yunshicloud.com@live.nctv.top@cbg.cn@zztv.tv';

 /// 通用播放器请求头
 static const Map<String, String> _playerHeaders = {
  'Accept': '*/*',
  'Accept-Language': '*',
  'Connection': 'keep-alive',
  'range': 'bytes=0-',  // 支持分片下载
  'user-agent': 'Dalvik/2.1.0 (Linux; U; Android 13) ExoPlayerLib/2.18.7',  // 标准的安卓系统 User-Agent
 };

 /// 基础请求头
 static const Map<String, String> _baseHeaders = {
   'Accept': '*/*',
   'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
   'Accept-Encoding': 'gzip, deflate, br, zstd',
   'Cache-Control': 'no-cache',
   'Connection': 'keep-alive',
   'DNT': '1',
   'Sec-Fetch-Dest': 'empty',
   'sec-ch-ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
   'sec-ch-ua-mobile': '?0',
   'sec-ch-ua-platform': '"Windows"',
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

 /// 获取排除域名列表
 static List<String> _getExcludeDomains() {
   if (excludeDomainsString.isEmpty) return [];
   return excludeDomainsString
     .split('@')
     .map((e) => e.trim())
     .where((e) => e.isNotEmpty)
     .toList();
 }

 /// 检查域名是否在排除列表中，或者是 IP 地址
 static bool _isExcludedDomain(String url) {
   try {
     final host = _extractHost(url);
     
     // 如果是 IP 地址，返回 true
     if (_isIpAddress(host)) {
       LogUtil.i('检测到 IP 地址：$host');
       return true;
     }
     
     // 检查是否在排除域名列表中
     final excludeDomains = _getExcludeDomains();
     return excludeDomains.any((domain) => host.contains(domain));
   } catch (e) {
     LogUtil.logError('检查排除域名失败', e);
     return false;
   }
 }
 
 /// 检查是否是 IP 地址
 static bool _isIpAddress(String host) {
   try {
     // 去除可能的 IPv6 方括号
     final cleanHost = host.replaceAll(RegExp(r'[\[\]]'), '');
     
     // IPv4 模式
     final ipv4Pattern = RegExp(
       r'^(\d{1,3}\.){3}\d{1,3}$'
     );
     
     // IPv6 模式
     final ipv6Pattern = RegExp(
       r'^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|'   // 标准格式
       r'^(([0-9a-fA-F]{1,4}:){0,6}::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4})$'  // 压缩格式
     );
     
     return ipv4Pattern.hasMatch(cleanHost) || ipv6Pattern.hasMatch(cleanHost);
   } catch (e) {
     return false;
   }
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
static String? _getRefererByRules(String url) {
   final rules = _parseRules();
   
   // 检查完整URL中是否包含关键字
   for (final domain in rules.keys) {
     if (url.contains(domain)) {
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
     // 首先检查是否在排除列表中
     if (_isExcludedDomain(url)) {
       LogUtil.i('生成播放器通用主机头：$_playerHeaders');
       return _playerHeaders;
     }

     final encodedUrl = Uri.encodeFull(url);
     final host = _extractHost(encodedUrl);
     final scheme = _extractScheme(encodedUrl);
     
     if (host.isEmpty) {
       throw FormatException('无法解析主机名');
     }

     // 获取referer
     final customReferer = _getRefererByRules(encodedUrl);
     final referer = customReferer ?? '$scheme://$host';

     // 检查是否需要CORS头
     final corsRules = corsRulesString.split('@');
     final needCors = corsRules.any((domain) => host.contains(domain));
     
    // 判断 referer 和 host 是否同站点
    String secFetchSite = 'cross-site';  // 默认值
    if (needCors) {
      final refererHost = _extractHost(referer);
      if (refererHost.isEmpty) {
        secFetchSite = 'none';
      } else {
        // 提取主域名进行比较
        final hostDomain = _extractMainDomain(host);
        final refererDomain = _extractMainDomain(refererHost);
        
        if (hostDomain == refererDomain) {
          secFetchSite = 'same-site';
        } 
      }
    }
    
     // 修改后的 headers map 定义
     final headers = {
       ..._baseHeaders,
       'Origin': referer,
       'Referer': '$referer/',
       if (needCors) ...{
         'Host': host,
         // 只有当不是 cross-site 时才添加这些头部
         if (secFetchSite != 'cross-site') ...{
           'Sec-Fetch-Mode': 'cors',
           'Sec-Fetch-Site': secFetchSite,
         },
       }, 
       'User-Agent': userAgent,
     };

     LogUtil.i('生成主机头：$headers');
     return headers;
     
   } catch (e, stackTrace) {
     LogUtil.logError('生成Headers失败，使用默认Headers', e, stackTrace);
     return _baseHeaders;
   }
 }
 
 /// 提取主域名
 static String _extractMainDomain(String host) {
   try {
     final hostWithoutPort = host.split(':')[0];
     final parts = hostWithoutPort.split('.');
     if (parts.length >= 2) {
       // 返回最后两段作为主域名
       return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
     }
     return host;
   } catch (e) {
     return host;
   }
 }

}
