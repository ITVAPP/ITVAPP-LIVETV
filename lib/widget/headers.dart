import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers_rules.dart';

/// HTTP请求Headers配置工具类，用于生成请求头
class HeadersConfig {
  const HeadersConfig._();

  /// Chrome版本号
  static const String _chromeVersion = '128.0.0.0';

  /// 浏览器标识
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromeVersion Safari/537.36 OPR/114.0.0.0';

  /// 通用请求头字段，提取公共部分以减少重复定义
  static const Map<String, String> _commonHeaders = {
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  /// 通用播放器请求头，用于视频播放器和流媒体服务
  static const Map<String, String> _playerHeaders = {
    ..._commonHeaders, // 合并公共字段
    'Range': 'bytes=0-',
    'User-Agent':
        'Dalvik/2.1.0 (Linux; U; Android 13; Redmi k80/SKQ1.211006.001)', // 模拟Android设备
    'Pragma': 'no-cache',
  };

  /// 基础请求头，用于标准HTTP请求
  static const Map<String, String> _baseHeaders = {
    ..._commonHeaders, // 合并公共字段
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
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
  static final List<String> _cachedDefaultHeadersDomains =
      _getDefaultHeadersDomains();

  /// 缓存域名特定请求头规则
  static final Map<String, Map<String, String>> _cachedCustomHeadersRules =
      _parseCustomHeadersRules();

  /// 请求头缓存最大条目数
  static const int _maxCacheSize = 100;

  /// 使用LinkedHashMap实现LRU缓存，简化代码
  static final Map<String, Map<String, String>> _headersCache = 
      LinkedHashMap<String, Map<String, String>>(
        equals: (a, b) => a == b,
        hashCode: (key) => key.hashCode,
      );

  /// 缓存主机信息，避免重复解析
  static final Map<String, Map<String, String?>> _hostInfoCache = 
      LinkedHashMap<String, Map<String, String?>>(
        equals: (a, b) => a == b,
        hashCode: (key) => key.hashCode,
      );

  /// 预编译IPv4正则表达式，提升匹配性能
  static final RegExp _ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  /// 预编译IPv6正则表达式，支持多种格式
  static final RegExp _ipv6Pattern = RegExp(
      r'^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,4}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,2}[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,3}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,3}[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,2}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,4}[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,1}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}::[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}::$');

  /// 提取主机名和端口的正则表达式，支持IPv6
  static final RegExp _hostWithPortPattern =
      RegExp(r'://([^\[\]/]+|\[[^\]]+\])(?::(\d+))?');

  /// 提取协议的正则表达式，支持http和https
  static final RegExp _schemePattern = RegExp(r'^(https?):');

  /// 缓存CORS规则域名列表
  static final List<String> _cachedCorsRules =
      _splitAndFilter(HeaderRules.corsRulesString);

  /// 解析规则配置，将域名关键字映射到Referer
  static Map<String, String> _parseRules() {
    final rules = <String, String>{};
    final rulesStr = HeaderRules.rulesString;
    if (rulesStr.isEmpty) return rules;

    final ruleList = _splitAndFilter(rulesStr); // 分割并过滤规则字符串
    for (final rule in ruleList) {
      final parts = rule.split('|');
      if (parts.length == 2) {
        final domain = parts[0].trim();
        final referer = parts[1].trim();
        if (domain.isNotEmpty && referer.isNotEmpty) {
          rules[domain] = 'https://$referer'; // 构造完整Referer
        }
      }
    }
    return rules;
  }

  /// 解析域名特定请求头规则，映射域名到请求头配置
  static Map<String, Map<String, String>> _parseCustomHeadersRules() {
    final rules = <String, Map<String, String>>{};
    final rulesStr = HeaderRules.customHeadersRulesString;
    if (rulesStr.isEmpty) return rules;

    final ruleList = _splitAndFilter(rulesStr); // 分割并过滤规则字符串
    String currentDomain = '';
    Map<String, String> currentHeaders = {};

    for (final line in ruleList) {
      if (line.startsWith('[') && line.endsWith(']')) {
        // 处理新的域名块
        if (currentDomain.isNotEmpty && currentHeaders.isNotEmpty) {
          rules[currentDomain] = currentHeaders; // 保存当前域名规则
          currentHeaders = {}; // 重置请求头
        }
        currentDomain = line.substring(1, line.length - 1).trim(); // 提取域名
      } else if (line.contains(':')) {
        // 处理请求头定义
        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join(':').trim(); // 合并值
          if (key.isNotEmpty) {
            currentHeaders[key] = value; // 添加请求头
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

  /// 获取排除域名列表，使用播放器请求头
  static List<String> _getExcludeDomains() {
    final excludeStr = HeaderRules.excludeDomainsString;
    if (excludeStr.isEmpty) return [];
    return _splitAndFilter(excludeStr); // 分割并过滤域名字符串
  }

  /// 获取使用默认请求头的域名列表
  static List<String> _getDefaultHeadersDomains() {
    final defaultHeadersStr = HeaderRules.defaultHeadersDomainsString;
    if (defaultHeadersStr.isEmpty) return [];
    return _splitAndFilter(defaultHeadersStr); // 分割并过滤域名字符串
  }

  /// 分割并过滤字符串，去除空行和多余空格
  static List<String> _splitAndFilter(String input) {
    if (input.isEmpty) return [];
    final result = <String>[];
    final lines = input.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        result.add(trimmed); // 仅保留非空行
      }
    }
    return result;
  }

  /// 管理请求头缓存，使用LinkedHashMap自动维护LRU
  static void _addToHeadersCache(String url, Map<String, String> headers) {
    // 如果已存在，先删除再添加以更新顺序
    _headersCache.remove(url);
    
    // 检查缓存大小
    if (_headersCache.length >= _maxCacheSize) {
      // LinkedHashMap保持插入顺序，删除第一个（最旧的）
      _headersCache.remove(_headersCache.keys.first);
    }
    
    _headersCache[url] = headers;
  }

  /// 提取并缓存URL的主机信息
  static Map<String, String?> _getCachedHostInfo(String url) {
    // 先检查缓存
    if (_hostInfoCache.containsKey(url)) {
      return _hostInfoCache[url]!;
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
        
        // 管理缓存大小
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
      LogUtil.logError('提取主机信息失败', e);
      final emptyInfo = {'host': '', 'port': null};
      _hostInfoCache[url] = emptyInfo;
      return emptyInfo;
    }
  }

  /// 检查URL域名是否在指定列表中
  static bool _isDomainInList(
    String url,
    List<String> domainList, {
    bool checkIp = false,
    Map<String, String?>? hostInfo,
  }) {
    try {
      final info = hostInfo ?? _getCachedHostInfo(url); // 复用主机信息
      final host = info['host'] ?? '';
      if (host.isEmpty) return false;
      if (checkIp && _isIpAddress(host)) return true; // 检查IP地址
      for (final domain in domainList) {
        if (host.contains(domain)) return true; // 域名匹配
      }
      return false;
    } catch (e) {
      LogUtil.logError('域名列表检查失败', e);
      return false;
    }
  }

  /// 检查域名是否为排除域名或IP地址
  static bool _isExcludedDomain(String url, [Map<String, String?>? hostInfo]) {
    return _isDomainInList(url, _cachedExcludeDomains,
        checkIp: true, hostInfo: hostInfo);
  }

  /// 检查域名是否使用默认请求头
  static bool _isDefaultHeadersDomain(String url,
      [Map<String, String?>? hostInfo]) {
    return _isDomainInList(url, _cachedDefaultHeadersDomains,
        checkIp: false, hostInfo: hostInfo);
  }

  /// 获取域名特定的自定义请求头
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
            final result = Map<String, String>.from(headers); // 复制请求头
            if (result.containsKey('Host') && result['Host']!.contains('{host}')) {
              final hostReplacement = port != null ? '$host:$port' : host;
              result['Host'] =
                  result['Host']!.replaceAll('{host}', hostReplacement); // 替换Host
            }
            return result;
          }
        }
      }
      return null;
    } catch (e) {
      LogUtil.logError('获取域名特定请求头失败', e);
      return null;
    }
  }

  /// 判断字符串是否为IPv4或IPv6地址
  static bool _isIpAddress(String host) {
    try {
      final cleanHost = host.replaceAll(RegExp(r'[\[\]]'), ''); // 移除IPv6括号
      return _ipv4Pattern.hasMatch(cleanHost) ||
          _ipv6Pattern.hasMatch(cleanHost);
    } catch (e) {
      LogUtil.logError('检查IP地址格式失败', e);
      return false;
    }
  }

  /// 提取URL的主机名和端口信息
  static Map<String, String?> _extractHostInfo(String url) {
    return _getCachedHostInfo(url); // 复用主机信息提取
  }

  /// 提取URL协议（http或https）
  static String _extractScheme(String url) {
    try {
      if (url.isEmpty) return 'http';
      if (url.startsWith('https')) return 'https'; // 快速检查https
      final match = _schemePattern.firstMatch(url);
      return match != null && match.groupCount >= 1 ? match.group(1)! : 'http';
    } catch (e) {
      LogUtil.logError('提取URL协议失败', e);
      return 'http';
    }
  }

  /// 根据规则获取Referer
  static String? _getRefererByRules(String url) {
    for (final domain in _cachedRules.keys) {
      if (url.contains(domain)) return _cachedRules[domain]!; // 返回匹配的Referer
    }
    return null;
  }

  /// 记录Headers日志信息
  static void _logHeadersInfo(String url, Map<String, String> headers, String ruleType) {
    try {
      // 构建日志信息
      final buffer = StringBuffer();
      buffer.writeln('请求地址: $url');
      buffer.writeln('请求头:');
      headers.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln('触发规则: $ruleType');
      
      // 输出日志
      LogUtil.i(buffer.toString());
    } catch (e) {
      // 日志记录失败时不影响正常流程
      LogUtil.logError('记录Headers日志失败', e);
    }
  }

  /// 生成HTTP请求头
  static Map<String, String> generateHeaders({required String url}) {
    try {
      if (url.isEmpty) {
        final headers = _baseHeaders;
        _logHeadersInfo(url, headers, '空URL，使用基础请求头');
        return headers; // 空URL返回基础请求头
      }
      
      if (_headersCache.containsKey(url)) {
        final headers = _headersCache[url]!;
        _logHeadersInfo(url, headers, '缓存Headers');
        return headers; // 返回缓存的请求头
      }

      final hostInfo = _extractHostInfo(url); // 提取主机信息
      final customHeaders = _getCustomHeadersForDomain(url, hostInfo);
      if (customHeaders != null) {
        _addToHeadersCache(url, customHeaders); // 缓存自定义请求头
        _logHeadersInfo(url, customHeaders, '域名特定自定义请求头');
        return customHeaders;
      }

      if (_isDefaultHeadersDomain(url, hostInfo)) {
        final emptyHeaders = <String, String>{};
        _addToHeadersCache(url, emptyHeaders); // 缓存空请求头
        _logHeadersInfo(url, emptyHeaders, 'BetterPlayer默认请求头');
        return emptyHeaders;
      }

      if (_isExcludedDomain(url, hostInfo)) {
        final host = hostInfo['host'] ?? '';
        final port = hostInfo['port'];
        if (host.isNotEmpty) {
          final fullHost = port != null ? '$host:$port' : host;
          final playerHeadersWithHost = {
            ..._playerHeaders,
            'Host': fullHost, // 添加动态Host
          };
          _addToHeadersCache(url, playerHeadersWithHost);
          _logHeadersInfo(url, playerHeadersWithHost, '通用播放器请求头');
          return playerHeadersWithHost;
        }
        _addToHeadersCache(url, _playerHeaders);
        _logHeadersInfo(url, _playerHeaders, '通用播放器请求头');
        return _playerHeaders; // 返回播放器请求头
      }

      final encodedUrl = Uri.encodeFull(url);
      final host = hostInfo['host'] ?? '';
      final port = hostInfo['port'];
      final scheme = _extractScheme(encodedUrl);
      if (host.isEmpty) {
        _addToHeadersCache(url, _baseHeaders);
        _logHeadersInfo(url, _baseHeaders, '主机为空，使用基础请求头');
        return _baseHeaders; // 主机为空返回基础请求头
      }

      final fullHost = port != null ? '$host:$port' : host; // 构造完整主机名
      final customReferer = _getRefererByRules(encodedUrl);
      final referer = customReferer ?? '$scheme://$fullHost';

      final needCors =
          _cachedCorsRules.any((domain) => host.contains(domain)); // 检查CORS需求
      String secFetchSite = 'cross-site';
      if (needCors) {
        final refererHostInfo = _extractHostInfo(referer);
        final refererHost = refererHostInfo['host'] ?? '';
        if (refererHost.isEmpty) {
          secFetchSite = 'none';
        } else {
          final hostDomain = _extractMainDomain(host);
          final refererDomain = _extractMainDomain(refererHost);
          if (hostDomain == refererDomain) secFetchSite = 'same-site'; // 同源检查
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
          headers['Sec-Fetch-Site'] = secFetchSite; // 添加CORS字段
        }
      }

      _addToHeadersCache(url, headers); // 缓存生成结果
      
      String ruleType = customReferer != null ? '通用请求头(自定义Referer)' : '通用请求头';
      if (needCors) {
        ruleType += '+CORS';
      }
      _logHeadersInfo(url, headers, ruleType);
      
      return headers;
    } catch (e, stackTrace) {
      LogUtil.logError('生成Headers失败，使用默认Headers', e, stackTrace);
      final headers = _baseHeaders;
      _logHeadersInfo(url, headers, '异常兜底，使用基础请求头');
      return headers; // 异常时返回基础请求头
    }
  }

  /// 提取主域名（如example.com）
  static String _extractMainDomain(String host) {
    try {
      if (host.isEmpty) return '';
      if (host.contains('[') && host.contains(']')) return host; // 处理IPv6
      final hostWithoutPort = host.split(':')[0];
      final parts = hostWithoutPort.split('.');
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}.${parts[parts.length - 1]}'; // 提取主域名
      }
      return host;
    } catch (e) {
      return host;
    }
  }

  /// 清除请求头缓存
  static void clearHeadersCache() {
    _headersCache.clear();
    _hostInfoCache.clear(); // 同时清除主机信息缓存
  }

  /// 获取当前缓存大小
  static int getCacheSize() {
    return _headersCache.length; // 返回缓存条目数
  }
}
