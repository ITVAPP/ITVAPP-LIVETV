import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

class TrafficAnalytics {
  final String hostname = Config.hostname;
  final String packagename = Config.packagename;
  final String appversion = Config.version;
  final String umamiUrl = 'https://ws.itvapp.net/api/send';
  final String websiteId = '22de1c29-4f0c-46cf-be13-e13ef6929cac';
  final int maxRetries = 3;

  // 用于缓存设备信息和 User-Agent，避免重复获取
  String? _cachedDeviceInfo;
  String? _cachedUserAgent;
  // 用于缓存IP地址和地理位置信息
  Map<String, dynamic>? _cachedIpData;

  // SP存储的key和缓存有效期常量
  static const String SP_KEY_LOCATION = 'user_location_info';
  static const int CACHE_EXPIRY_HOURS = 48;
  static const int CACHE_EXPIRY_MS = CACHE_EXPIRY_HOURS * 60 * 60 * 1000; // 预计算缓存过期时间（毫秒）

  // 检查缓存是否过期
  bool _isCacheExpired(int timestamp) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return currentTime > (timestamp + CACHE_EXPIRY_MS);
  }

  /// 重置缓存，用于网络切换等场景
  void resetCache() {
    _cachedIpData = null;
    _cachedDeviceInfo = null;
    _cachedUserAgent = null;
    LogUtil.i('已重置流量分析缓存');
  }

  /// 获取用户的IP地址和地理位置信息，使用并行请求优化
  Future<Map<String, dynamic>> getUserIpAndLocation() async {
    if (_cachedIpData != null) {
      return _cachedIpData!; // 返回缓存数据
    }

    // 从SP中读取缓存
    String? savedLocation = SpUtil.getString(SP_KEY_LOCATION);
    if (savedLocation != null && savedLocation.isNotEmpty) {
      try {
        Map<String, dynamic> cachedData = jsonDecode(savedLocation);
        int? timestamp = cachedData['timestamp'];
        if (timestamp != null && !_isCacheExpired(timestamp)) {
          _cachedIpData = cachedData['location'];
          return _cachedIpData!;
        }
      } catch (e) {
        LogUtil.e('解析保存的位置信息失败: $e');
      }
    }

    final apiList = [
      {
        'url': 'https://whois.pconline.com.cn/ipJson.jsp?ip=&json=true',
        'parseData': (data) => {
              'ip': data['ip'] ?? 'Unknown IP',
              'region': data['pro'] ?? 'Unknown Region',
              'country': data['region'] ?? '中国',
              'city': data['city'] ?? 'Unknown City',
            }
      },
      {
        'url': 'https://ip.useragentinfo.com/json',
        'parseData': (data) => {
              'ip': data['ip'] ?? 'Unknown IP',
              'country': data['country'] ?? 'Unknown Country',
              'region': data['province'] ?? 'Unknown Region',
              'city': data['city'] ?? 'Unknown City',
            }
      },
      {
        'url': 'https://open.saintic.com/ip/rest',
        'parseData': (data) => {
              'ip': data['data']?['ip'] ?? 'Unknown IP',
              'country': data['data']?['country'] ?? 'Unknown Country',
              'region': data['data']?['province'] ?? 'Unknown Region',
              'city': data['data']?['city'] ?? 'Unknown City',
            }
      },
      {
        'url': 'http://ip-api.com/json',
        'parseData': (data) => {
              'ip': data['query'] ?? 'Unknown IP',
              'country': data['country'] ?? 'Unknown Country',
              'region': data['regionName'] ?? 'Unknown Region',
              'city': data['city'] ?? 'Unknown City',
              'lat': data['lat'],
              'lon': data['lon'],
            }
      }
    ];

    // 并行请求所有API，选择第一个成功的响应
    final futures = apiList.map((api) async {
      try {
        final responseData = await HttpUtil().getRequest<String>(
          api['url'] as String,
          options: Options(receiveTimeout: const Duration(seconds: 5)),
          cancelToken: CancelToken(),
        );
        if (responseData != null) {
          dynamic parsedData;
          if (responseData is String) {
            try {
              parsedData = jsonDecode(responseData); // 尝试解析为 JSON
            } catch (e) {
              LogUtil.i('响应数据是字符串但不是 JSON: $responseData');
              return null; // 如果字符串不是 JSON，返回 null
            }
          } else if (responseData is Map<String, dynamic>) {
            parsedData = responseData; // 直接使用 Map
          } else if (responseData is List<dynamic>) {
            // 如果返回的是数组，取第一个元素（根据需求调整）
            if (responseData.isNotEmpty && responseData[0] is Map<String, dynamic>) {
              parsedData = responseData[0];
            } else {
              LogUtil.i('响应数据是数组但内容不符合预期: $responseData');
              return null;
            }
          } else {
            LogUtil.i('不支持的响应数据类型: $responseData');
            return null; // 其他类型暂不处理
          }

          // 确保 parsedData 是 Map<String, dynamic> 后再调用 parseData
          if (parsedData is Map<String, dynamic>) {
            return (api['parseData'] as dynamic Function(dynamic))(parsedData);
          } else {
            LogUtil.e('解析后的数据不是 Map<String, dynamic>: $parsedData');
            return null;
          }
        }
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败', e, stackTrace);
      }
      return null;
    }).toList();

    final results = await Future.wait(futures);
    for (var result in results) {
      if (result != null) {
        _cachedIpData = result;
        final saveData = {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'location': _cachedIpData,
        };
        // 在缓存到本地时记录地理信息到日志
        LogUtil.i('缓存用户地理信息到本地: IP=${result['ip']}, Location=${result['city']}, ${result['region']}, ${result['country']}');
        await SpUtil.putString(SP_KEY_LOCATION, jsonEncode(saveData));
        return _cachedIpData!;
      }
    }
    // 如果所有API失败，返回默认值
    _cachedIpData = {'ip': 'Unknown IP', 'country': 'Unknown', 'region': 'Unknown', 'city': 'Unknown'};
    return _cachedIpData!;
  }

  /// 获取保存的位置信息的字符串形式
  String getLocationString() {
    String? savedLocation = SpUtil.getString(SP_KEY_LOCATION);
    if (savedLocation != null && savedLocation.isNotEmpty) {
      try {
        Map<String, dynamic> locationData = jsonDecode(savedLocation);
        return 'IP: ${locationData['ip']}\n'
            '国家: ${locationData['country']}\n'
            '地区: ${locationData['region']}\n'
            '城市: ${locationData['city']}';
      } catch (e) {
        LogUtil.e('解析位置信息失败: $e');
      }
    }
    return '暂无位置信息';
  }

  /// 获取屏幕尺寸
  String getScreenSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return '${size.width.toInt()}x${size.height.toInt()}';
  }

  /// 获取设备信息和User-Agent
  Future<String> getDeviceInfo({bool userAgent = false}) async {
    if (userAgent && _cachedUserAgent != null) return _cachedUserAgent!;
    if (!userAgent && _cachedDeviceInfo != null) return _cachedDeviceInfo!;

    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
      _cachedDeviceInfo = '${androidInfo.model} (${androidInfo.version.release})';
      _cachedUserAgent = '$packagename/$appversion (Android; ${androidInfo.version.release})';
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
      _cachedDeviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})';
      _cachedUserAgent = '$packagename/$appversion (iOS; ${iosInfo.systemVersion})';
    } else {
      _cachedDeviceInfo = Platform.operatingSystem;
      _cachedUserAgent = '$packagename/$appversion (Unknown Platform)';
    }
    return userAgent ? _cachedUserAgent! : _cachedDeviceInfo!;
  }

  /// 发送页面访问统计数据到 Umami
  Future<void> sendPageView(BuildContext context, String referrer, {String? additionalPath}) async {
    final String screenSize = getScreenSize(context);
    final String deviceInfo = await getDeviceInfo();
    final String userAgent = await getDeviceInfo(userAgent: true);

    String url = ModalRoute.of(context)?.settings.name ?? '';
    if (additionalPath != null && additionalPath.isNotEmpty) {
      url += "/$additionalPath";
    }

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final currentLanguage = languageProvider.currentLocale?.languageCode ?? 'en';

    try {
      final Map<String, dynamic> ipData = await getUserIpAndLocation();
      final locationString = '${ipData['city']}, ${ipData['region']}, ${ipData['country']}';

      final Map<String, dynamic> payload = {
        'payload': {
          'type': 'event',
          'website': websiteId,
          'url': url,
          'referrer': referrer,
          'hostname': hostname,
          'language': currentLanguage,
          'screen': screenSize,
          'ip': ipData['ip'],
          'location': locationString,
          'device': deviceInfo,
          'data': {
            'device_info': deviceInfo,
            'screen_size': screenSize,
            'ip': ipData['ip'],
            'location': locationString,
            'lat': ipData['lat'],
            'lon': ipData['lon'],
          }
        },
        'type': 'event',
      };

      await _sendWithRetry(payload, userAgent);
    } catch (error, stackTrace) {
      LogUtil.logError('发送页面访问数据时发生错误', error, stackTrace);
    }
  }

  /// 带重试机制的发送方法，设置最大延迟
  Future<void> _sendWithRetry(Map<String, dynamic> payload, String userAgent) async {
    int attempt = 0;
    bool success = false;
    int delayInSeconds = 2;
    const int maxDelayInSeconds = 10;

    while (attempt < maxRetries && !success) {
      attempt++;
      try {
        final response = await HttpUtil().postRequest<String>(
          umamiUrl,
          data: jsonEncode(payload),
          options: Options(
            receiveTimeout: const Duration(seconds: 10),
          ),
          cancelToken: CancelToken(),
        );

        if (response != null) {
          LogUtil.i('页面访问统计数据发送成功，尝试次数: $attempt');
          success = true;
        } else {
          throw Exception('响应数据为空');
        }
      } catch (error, stackTrace) {
        LogUtil.logError('发送数据时发生错误，第 $attempt 次重试', error, stackTrace);
        if (attempt >= maxRetries) {
          LogUtil.e('达到最大重试次数 ($maxRetries)，发送失败，最终错误: $error');
          return; // 达到最大重试次数后退出
        }
        delayInSeconds = delayInSeconds * 2 > maxDelayInSeconds ? maxDelayInSeconds : delayInSeconds * 2;
        LogUtil.i('等待 $delayInSeconds 秒后进行第 ${attempt + 1} 次重试');
        await Future.delayed(Duration(seconds: delayInSeconds));
      }
    }
  }
}
