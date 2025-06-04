import 'dart:collection';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers_rules.dart';

// HTTP 请求头配置工具类
class HeadersConfig {
  const HeadersConfig._();

  // Chrome 版本号
  static const String _chromeVersion = '128.0.0.0';

  // 浏览器用户代理
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36 OPR/114.0.0.0';

  // 通用请求头字段
  static const Map<String, String> _commonHeaders = {
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  // 播放器请求头，适用于视频流媒体
  static const Map<String, String> _playerHeaders = {
    ..._commonHeaders, // 包含通用字段
    'Range': 'bytes=0-',
    'User-Agent':
        'Dalvik/2.1.0 (Linux; U; Android 13; Redmi k80/SKQ1.211006.001)', // 模拟 Android 设备
    'Pragma': 'no-cache',
  };

  // 基础请求头，适用于标准 HTTP 请求
  static const Map<String, String> _baseHeaders = {
    ..._commonHeaders, // 包含通用字段
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
    'Cache-Control': 'no-cache',
    'DNT': '1',
    'Sec-Fetch-Dest': 'empty',
    'sec-ch-ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
  };

  // 缓存域名到 Referer 规则
  static final Map<String, String> _cachedRules = _parseRules();

  // 缓存排除域名列表
  static final List<String> _cachedExcludeDomains = _getExcludeDomains();

  // 缓存使用默认请求头的域名列表
  static final List<String> _cachedDefaultHeadersDomains =
      _getDefaultHeadersDomains();

  // 缓存域名特定请求头规则
  static final Map<String, Map<String, String>> _cachedCustomHeadersRules =
      _parseCustomHeadersRules();

  // 请求头缓存最大条目数
  static const int _maxCacheSize = 100;

  // 使用 LRU 缓存管理请求头
  static final Map<String, Map<String, String>> _headersCache = 
      LinkedHashMap<String, Map<String, String>>();

  // 缓存主机信息
  static final Map<String, Map<String, String?>> _hostInfoCache = 
      LinkedHashMap<String, Map<String, String?>>();

  // 预编译 IPv4 正则表达式
  static final RegExp _ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  // 预编译 IPv6 正则表达式
  static final RegExp _ipv6Pattern = RegExp(
      r'^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,4}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,2}[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,3}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,3}[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,2}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,4}[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,1}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}::[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}::$');

  // 提取主机名和端口的正则表达式
  static final RegExp _hostWithPortPattern =
      RegExp(r'://([^\[\]/]+|\[[^\]]+\])(?::(\d+))?');

  // 提取协议的正则表达式
  static final RegExp _schemePattern = RegExp(r'^(https?):');

  // 缓存 CORS 规则域名列表
  static final List<String> _cachedCorsRules =
      _splitAndFilter(HeaderRules.corsRulesString);

  // 解析域名到 Referer 规则
  static Map<String, String> _parseRules() {
    final rules = <String, String>{};
    final rulesStr = HeaderRules.rulesString;
    if (rulesStr.isEmpty) return rules;

    final ruleList = _splitAndFilter(rulesStr); // 分割并过滤字符串
    for (final rule in ruleList) {
      final parts = rule.split('|');
      if (parts.length == 2) {
        final domain = parts[0].trim();
        final referer = parts[1].trim();
        if (domain.isNotEmpty && referer.isNotEmpty) {
          rules[domain] = 'https://$referer'; // 构造 Referer
        }
      }
    }
    return rules;
  }

  // 解析域名特定请求头规则
  static Map<String, Map<String, String>> _parseCustomHeadersRules() {
    final rules = <String, Map<String, String>>{};
    final rulesStr = HeaderRules.customHeadersRulesString;
    if (rulesStr.isEmpty) return rules;

    final ruleList = _splitAndFilter(rulesStr); // 分割并过滤字符串
    String currentDomain = '';
    Map<String, String> currentHeaders = {};

    for (final line in ruleList) {
      if (line.startsWith('[') && line.endsWith(']')) {
        // 保存当前域名规则
        if (currentDomain.isNotEmpty && currentHeaders.isNotEmpty) {
          rules[currentDomain] = currentHeaders;
          currentHeaders = {};
        }
        currentDomain = line.substring(1, line.length - 1).trim(); // 提取域名
      } else if (line.contains(':')) {
        // 添加请求头
        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join(':').trim();
          if (key.isNotEmpty) {
            currentHeaders[key] = value;
          }
        }
      }
    }

    // 保存最后一个域名规则
    if (currentDomain.isNotEmpty && currentHeaders.isNotEmpty) {
      rules[currentDomain] = currentHeaders;
    }
    return rules;
  }

  // 获取排除域名列表
  static List<String> _getExcludeDomains() {
    final excludeStr = HeaderRules.excludeDomainsString;
    if (excludeStr.isEmpty) return [];
    return _splitAndFilter(excludeStr); // 分割并过滤字符串
  }

  // 获取默认请求头域名列表
  static List<String> _getDefaultHeadersDomains() {
    final defaultHeadersStr = HeaderRules.defaultHeadersDomainsString;
    if (defaultHeadersStr.isEmpty) return [];
    return _splitAndFilter(defaultHeadersStr); // 分割并过滤字符串
  }

  // 分割并过滤字符串
  static List<String> _splitAndFilter(String input) {
    if (input.isEmpty) return [];
    final result = <String>[];
    final lines = input.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        result.add(trimmed); // 保留非空行
      }
    }
    return result;
  }

  // 管理请求头 LRU 缓存
  static void _addToHeadersCache(String url, Map<String, String> headers) {
    _headersCache.remove(url); // 更新缓存顺序
    
    // 限制缓存大小
    if (_headersCache.length >= _maxCacheSize) {
      _headersCache.remove(_headersCache.keys.first);
    }
    
    _headersCache[url] = headers;
  }

  // 提取并缓存主机信息
  static Map<String, String?> _getCachedHostInfo(String url) {
    if (_hostInfoCache.containsKey(url)) {
      return _hostInfoCache[url]!; // 返回缓存
    }
    
    try {
      if (url.isEmpty || (!url.contains('http://') && !url.contains('https://'))) {
        final emptyInfo = {'host': '', 'port': null};
        _hostInfoCache[url] = emptyInfo;
        return emptyInfo;
      }
      
      final match = _hostWithPortPattern.firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        final host = match.group(1)!;
        final port = match.groupCount >= 2 ? match.group(2) : null;
        final info = {'host': host, 'port': port};
        
        // 限制缓存大小
        if (_hostInfoCache.length >= _maxCacheSize) {
          _hostInfoCache.remove(_hostInfoCache.keys.first);
        }
        _hostInfoCache[url] = info;
        
        return info;
      }
      
      final emptyInfo = {'host': '', 'port': null};
      _hostInfoCache[url] = emptyInfo;
      return emptyInfo;
    } catch (e) {
      LogUtil.logError('安全记录主机信息提取错误', e);
      final emptyInfo = {'host': '', 'port': null};
      _hostInfoCache[url] = emptyInfo;
      return emptyInfo;
    }
  }

  // 检查域名是否在指定列表中
  static bool _isDomainInList(
    String url,
    List<String> domainList, {
    bool checkIp = false,
    Map<String, String?>? hostInfo,
  }) {
    try {
      final info = hostInfo ?? _getCachedHostInfo(url);
      final host = info['host'] ?? '';
      if (host.isEmpty) return false;
      if (checkIp && _isIpAddress(host)) return true;
      for (final domain in domainList) {
        if (host.contains(domain)) return true;
      }
      return false;
    } catch (e) {
      LogUtil.logError('安全记录域名检查错误', e);
      return false;
    }
  }

  // 检查是否为排除域名或 IP
  static bool _isExcludedDomain(String url, [Map<String, String?>? hostInfo]) {
    return _isDomainInList(url, _cachedExcludeDomains,
        checkIp: true, hostInfo: hostInfo);
  }

  // 检查是否使用默认请求头
  static bool _isDefaultHeadersDomain(String url,
      [Map<String, String?>? hostInfo]) {
    return _isDomainInList(url, _cachedDefaultHeadersDomains,
        checkIp: false, hostInfo: hostInfo);
  }

  // 获取域名特定请求头
  static Map<String, String>? _getCustomHeadersForDomain(String url,
      [Map<String, String?>? hostInfo]) {
    try {
      final info = hostInfo ?? _getCachedHostInfo(url);
      final host = info['host'] ?? '';
      final port = info['port'];
      if (host.isEmpty) return null;
      for (final domainKey in _cachedCustomHeadersRules.keys) {
        if (host.contains(domainKey)) {
          final headers = _cachedCustomHeadersRules[domainKey];
          if (headers != null && headers.isNotEmpty) {
            final result = Map<String, String>.from(headers);
            if (result.containsKey('Host') && result['Host']!.contains('{host}')) {
              final hostReplacement = port != null ? '$host:$port' : host;
              result['Host'] = result['Host']!.replaceAll('{host}', hostReplacement);
            }
            return result;
          }
        }
      }
      return null;
    } catch (e) {
      LogUtil.logError('安全记录自定义请求头获取错误', e);
      return null;
    }
  }

  // 判断是否为 IP 地址
  static bool _isIpAddress(String host) {
    try {
      final cleanHost = host.replaceAll(RegExp(r'[\[\]]'), '');
      return _ipv4Pattern.hasMatch(cleanHost) ||
          _ipv6Pattern.hasMatch(cleanHost);
    } catch (e) {
      LogUtil.logError('安全记录 IP 地址检查错误', e);
      return false;
    }
  }

  // 提取主机名和端口
  static Map<String, String?> _extractHostInfo(String url) {
    return _getCachedHostInfo(url); // 使用缓存提取
  }

  // 提取 URL 协议
  static String _extractScheme(String url) {
    try {
      if (url.isEmpty) return 'http';
      if (url.startsWith('https')) return 'https';
      final match = _schemePattern.firstMatch(url);
      return match != null && match.groupCount >= 1 ? match.group(1)! : 'http';
    } catch (e) {
      LogUtil.logError('安全记录协议提取错误', e);
      return 'http';
    }
  }

  // 根据规则获取 Referer
  static String? _getRefererByRules(String url) {
    for (final domain in _cachedRules.keys) {
      if (url.contains(domain)) return _cachedRules[domain]!;
    }
    return null;
  }

  // 记录请求头日志
  static void _logHeadersInfo(String url, Map<String, String> headers, String ruleType) {
    try {
      final buffer = StringBuffer();
      buffer.writeln('请求地址: $url');
      buffer.writeln('请求头:');
      headers.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln('触发规则: $ruleType');
      
      LogUtil.i(buffer.toString());
    } catch (e) {
      LogUtil.logError('安全记录日志错误', e);
    }
  }

  // 生成 HTTP 请求头
  static Map<String, String> generateHeaders({required String url}) {
    try {
      if (url.isEmpty) {
        final headers = _baseHeaders;
        _logHeadersInfo(url, headers, '空 URL，使用基础请求头');
        return headers;
      }
      
      if (_headersCache.containsKey(url)) {
        final headers = _headersCache[url]!;
        _logHeadersInfo(url, headers, '缓存请求头');
        return headers;
      }

      final hostInfo = _extractHostInfo(url);
      final customHeaders = _getCustomHeadersForDomain(url, hostInfo);
      if (customHeaders != null) {
        _addToHeadersCache(url, customHeaders);
        _logHeadersInfo(url, customHeaders, '域名特定请求头');
        return customHeaders;
      }

      if (_isDefaultHeadersDomain(url, hostInfo)) {
        final emptyHeaders = <String, String>{};
        _addToHeadersCache(url, emptyHeaders);
        _logHeadersInfo(url, emptyHeaders, '使用BetterPlayer默认请求头');
        return emptyHeaders;
      }

      if (_isExcludedDomain(url, hostInfo)) {
        final host = hostInfo['host'] ?? '';
        final port = hostInfo['port'];
        if (host.isNotEmpty) {
          final fullHost = port != null ? '$host:$port' : host;
          final playerHeadersWithHost = {
            ..._playerHeaders,
            'Host': fullHost,
          };
          _addToHeadersCache(url, playerHeadersWithHost);
          _logHeadersInfo(url, playerHeadersWithHost, '播放器请求头');
          return playerHeadersWithHost;
        }
        _addToHeadersCache(url, _playerHeaders);
        _logHeadersInfo(url, _playerHeaders, '播放器请求头');
        return _playerHeaders;
      }

      final encodedUrl = Uri.encodeFull(url);
      final host = hostInfo['host'] ?? '';
      final port = hostInfo['port'];
      final scheme = _extractScheme(encodedUrl);
      if (host.isEmpty) {
        _addToHeadersCache(url, _baseHeaders);
        _logHeadersInfo(url, _baseHeaders, '无主机，使用基础请求头');
        return _baseHeaders;
      }

      final fullHost = port != null ? '$host:$port' : host;
      final customReferer = _getRefererByRules(encodedUrl);
      final referer = customReferer ?? '$scheme://$fullHost';

      final needCors =
          _cachedCorsRules.any((domain) => host.contains(domain));
      String secFetchSite = 'cross-site';
      if (needCors) {
        final refererHostInfo = _extractHostInfo(referer);
        final refererHost = refererHostInfo['host'] ?? '';
        if (refererHost.isEmpty) {
          secFetchSite = 'none';
        } else {
          final hostDomain = _extractMainDomain(host);
          final refererDomain = _extractMainDomain(refererHost);
          if (hostDomain == refererDomain) secFetchSite = 'same-site';
        }
      }

      final Map<String, String> headers = {
        ..._baseHeaders,
        'Origin': referer,
        'Referer': '$referer/',
        'User-Agent': userAgent,
      };

      if (needCors) {
        headers['Host'] = fullHost;
        if (secFetchSite != 'cross-site') {
          headers['Sec-Fetch-Mode'] = 'cors';
          headers['Sec-Fetch-Site'] = secFetchSite;
        }
      }

      _addToHeadersCache(url, headers);
      
      String ruleType = customReferer != null ? '通用请求头(自定义 Referer)' : '通用请求头';
      if (needCors) {
        ruleType += '+CORS';
      }
      _logHeadersInfo(url, headers, ruleType);
      
      return headers;
    } catch (e, stackTrace) {
      LogUtil.logError('安全记录请求头生成错误', e, stackTrace);
      final headers = _baseHeaders;
      _logHeadersInfo(url, headers, '异常使用基础请求头');
      return headers;
    }
  }

  // 提取主域名
  static String _extractMainDomain(String host) {
    try {
      if (host.isEmpty) return '';
      if (host.contains('[') && host.contains(']')) return host;
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

  // 清除请求头缓存
  static void clearHeadersCache() {
    _headersCache.clear();
    _hostInfoCache.clear(); // 清除主机信息缓存
  }

  // 获取缓存条目数
  static int getCacheSize() {
    return _headersCache.length;
  }
}
