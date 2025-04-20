import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers_rules.dart';

/// HTTP请求Headers配置工具类，用于生成请求头
class HeadersConfig {
  const HeadersConfig._();
  
  /// Chrome版本号
  static const String _chromeVersion = '128.0.0.0';
  
  /// 浏览器标识
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36 OPR/114.0.0.0';

  /// 通用请求头字段，提取公共部分以减少重复定义
  static const Map<String, String> _commonHeaders = {
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  /// 通用播放器请求头，用于视频播放器和流媒体服务
  static const Map<String, String> _playerHeaders = {
    ..._commonHeaders, // 合并公共字段
    'Range': 'bytes=0-',
    'user-agent': 'Dalvik/2.1.0 (Linux; U; Android 13; Redmi k80/SKQ1.211006.001)',  // 标准的安卓系统 User-Agent
    'Pragma': 'no-cache',
  };

  /// 基础请求头，用于标准HTTP请求
  static const Map<String, String> _baseHeaders = {
    ..._commonHeaders, // 合并公共字段
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Cache-Control': 'no-cache',
    'DNT': '1',
    'Sec-Fetch-Dest': 'empty',
    'sec-ch-ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
  };

  /// 缓存解析规则，避免重复计算
  static final Map<String, String> _cachedRules = _parseRules();
  
  /// 缓存排除域名列表，避免重复计算
  static final List<String> _cachedExcludeDomains = _getExcludeDomains();
  
  /// 缓存使用BetterPlayer默认请求头的域名列表
  static final List<String> _cachedDefaultHeadersDomains = _getDefaultHeadersDomains();

  /// 预编译正则表达式，提升性能
  static final RegExp _ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  static final RegExp _ipv6Pattern = RegExp(
    r'^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|'   // 标准格式
    r'^(([0-9a-fA-F]{1,4}:){0,6}::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4})$'  // 压缩格式
  );
  static final RegExp _hostPattern = RegExp(r'://([^\[\]/]+|\[[^\]]+\])');
  static final RegExp _schemePattern = RegExp(r'^(https?):');

  /// 解析规则配置，将域名关键字映射到对应的Referer
  static Map<String, String> _parseRules() {
    final rules = <String, String>{};
    
    final rulesStr = HeaderRules.rulesString;
    if (rulesStr.isEmpty) return rules;
    
    final ruleList = _splitAndFilter(rulesStr); // 使用统一工具方法
    
    for (final rule in ruleList) {
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

  /// 获取排除域名列表，这些域名将使用播放器请求头
  static List<String> _getExcludeDomains() {
    final excludeStr = HeaderRules.excludeDomainsString;
    if (excludeStr.isEmpty) return [];
    
    return _splitAndFilter(excludeStr); // 使用统一工具方法
  }

  /// 获取使用默认请求头的域名列表
  static List<String> _getDefaultHeadersDomains() {
    final defaultHeadersStr = HeaderRules.defaultHeadersDomainsString;
    if (defaultHeadersStr.isEmpty) return [];
    
    return _splitAndFilter(defaultHeadersStr); // 使用统一工具方法
  }

  /// 通用字符串分割和过滤方法，消除重复逻辑
  static List<String> _splitAndFilter(String input) {
    return input
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 检查域名是否为IP地址或在排除列表中
  static bool _isExcludedDomain(String url) {
    try {
      final host = _extractHost(url);
      
      if (host.isEmpty) return false; // 增加健壮性
      
      if (_isIpAddress(host)) {
        LogUtil.i('检测到 IP 地址：$host');
        return true;
      }
      
      return _cachedExcludeDomains.any((domain) => host.contains(domain));
    } catch (e) {
      LogUtil.logError('检查排除域名失败', e);
      return false;
    }
  }
  
  /// 检查域名是否需要使用默认请求头
  static bool _isDefaultHeadersDomain(String url) {
    try {
      final host = _extractHost(url);
      
      if (host.isEmpty) return false; // 增加健壮性
      
      return _cachedDefaultHeadersDomains.any((domain) => host.contains(domain));
    } catch (e) {
      LogUtil.logError('检查默认请求头域名失败', e);
      return false;
    }
  }
  
  /// 判断给定字符串是否为IPv4或IPv6地址
  static bool _isIpAddress(String host) {
    try {
      final cleanHost = host.replaceAll(RegExp(r'[\[\]]'), '');
      return _ipv4Pattern.hasMatch(cleanHost) || _ipv6Pattern.hasMatch(cleanHost);
    } catch (e) {
      return false;
    }
  }

  /// 从URL中提取主机名，支持IPv6格式
  static String _extractHost(String url) {
    try {
      final match = _hostPattern.firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /// 从URL中提取协议，http或https
  static String _extractScheme(String url) {
    try {
      final match = _schemePattern.firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
      return 'http';
    } catch (e) {
      return 'http';
    }
  }

  /// 根据配置规则获取Referer
  static String? _getRefererByRules(String url) {
    for (final domain in _cachedRules.keys) {
      if (url.contains(domain)) {
        return _cachedRules[domain]!;
      }
    }
    return null;
  }

  /// 生成HTTP请求头
  /// 
  /// 输入：
  ///   - url: 请求的目标URL，用于动态生成合适的请求头
  /// 输出：
  ///   - Map<String, String>: 根据URL和规则生成的HTTP请求头
  /// 逻辑：
  ///   1. 检查是否为排除域名或IP地址，若是则返回播放器请求头
  ///   2. 提取URL中的主机名、协议等信息
  ///   3. 根据规则生成Referer和CORS相关字段
  ///   4. 合并基础请求头和其他动态字段
  static Map<String, String> generateHeaders({
    required String url,
  }) {
    try {
      // 检查是否需要使用默认请求头
      if (_isDefaultHeadersDomain(url)) {
        LogUtil.i('使用 BetterPlayer 默认请求头 for URL: $url');
        return {};
      }

      if (_isExcludedDomain(url)) {
        final host = _extractHost(url);
        final playerHeadersWithHost = {
          ..._playerHeaders,
          if (host.isNotEmpty) 'Host': host, // 动态添加 Host
        };
        LogUtil.i('生成播放器通用主机头：$playerHeadersWithHost');
        return playerHeadersWithHost;
      }

      final encodedUrl = Uri.encodeFull(url);
      final host = _extractHost(encodedUrl); // 提取一次，复用
      final scheme = _extractScheme(encodedUrl);
      
      if (host.isEmpty) {
        return _baseHeaders; // 健壮性处理
      }

      final customReferer = _getRefererByRules(encodedUrl);
      final referer = customReferer ?? '$scheme://$host';

      final corsRules = _splitAndFilter(HeaderRules.corsRulesString); // 使用统一工具方法
      final needCors = corsRules.any((domain) => host.contains(domain));
      
      String secFetchSite = 'cross-site';
      if (needCors) {
        final refererHost = _extractHost(referer);
        if (refererHost.isEmpty) {
          secFetchSite = 'none';
        } else {
          final hostDomain = _extractMainDomain(host);
          final refererDomain = _extractMainDomain(refererHost);
          
          if (hostDomain == refererDomain) {
            secFetchSite = 'same-site';
          } 
        }
      }
      
      final headers = {
        ..._baseHeaders,
        'Origin': referer,
        'Referer': '$referer/',
        if (needCors) ...{
          'Host': host,
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
  
  /// 从主机名中提取主域名
  static String _extractMainDomain(String host) {
    try {
      final hostWithoutPort = host.split(':')[0];
      final parts = hostWithoutPort.split('.');
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
      }
      return host;
    } catch (e) {
      return host;
    }
  }
}
