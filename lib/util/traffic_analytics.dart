import 'dart:convert';
import 'dart:io';
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
  static const int REQUEST_TIMEOUT_SECONDS = 6; // 定义请求超时时间为常量

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
    // 优化时间计算，避免重复调用 DateTime.now()
    return DateTime.now().millisecondsSinceEpoch > (timestamp + CACHE_EXPIRY_MS);
  }

  /// 重置缓存，用于网络切换等场景
  void resetCache() {
    _cachedIpData = null;
    _cachedDeviceInfo = null;
    _cachedUserAgent = null;
    // 清理 SP 中的缓存数据，确保一致性
    SpUtil.remove(SP_KEY_LOCATION);
    LogUtil.i('已重置流量分析缓存');
  }

  /// JSON 解析的工具函数
  Map<String, dynamic>? _parseJson(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonDecode(data);
    } catch (e) {
      LogUtil.e('JSON 解析失败: $e');
      return null;
    }
  }

  /// 位置信息字符串格式化的工具函数
  String _formatLocationString(Map<String, dynamic> locationData) {
    return '${locationData['city'] ?? 'Unknown City'}, '
        '${locationData['region'] ?? 'Unknown Region'}, '
        '${locationData['country'] ?? 'Unknown Country'}';
  }

  /// 获取用户的IP地址和地理位置信息，按顺序尝试 API
  Future<Map<String, dynamic>> getUserIpAndLocation() async {
    if (_cachedIpData != null) {
      return _cachedIpData!; // 返回缓存数据
    }

    // 从 SP 中读取缓存
    String? savedLocation = SpUtil.getString(SP_KEY_LOCATION);
    if (savedLocation != null && savedLocation.isNotEmpty) {
      Map<String, dynamic>? cachedData = _parseJson(savedLocation);
      if (cachedData != null) {
        int? timestamp = cachedData['timestamp'];
        if (timestamp != null && !_isCacheExpired(timestamp)) {
          _cachedIpData = cachedData['location'];
          return _cachedIpData!;
        }
      }
    }

    final apiList = [
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

    // 按顺序尝试每个 API
    for (var api in apiList) {
      try {
        final responseData = await HttpUtil().getRequest<String>(
          api['url'] as String,
          options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),
          cancelToken: CancelToken(),
        );
        if (responseData != null) {
          Map<String, dynamic>? parsedData = _parseJson(responseData);
          if (parsedData != null) {
            final result = (api['parseData'] as dynamic Function(dynamic))(parsedData);
            _cachedIpData = result;
            final saveData = {
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'location': _cachedIpData,
            };
            LogUtil.i('缓存用户地理信息到本地: IP=${result['ip']}, Location=${_formatLocationString(result)}');
            await SpUtil.putString(SP_KEY_LOCATION, jsonEncode(saveData));
            return _cachedIpData!;
          }
        }
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败', e, stackTrace);
      }
    }

    // 如果所有 API 失败，返回默认值
    _cachedIpData = {'ip': 'Unknown IP', 'country': 'Unknown', 'region': 'Unknown', 'city': 'Unknown'};
    return _cachedIpData!;
  }

  /// 获取保存的位置信息的字符串形式
  String getLocationString() {
    String? savedLocation = SpUtil.getString(SP_KEY_LOCATION);
    if (savedLocation != null && savedLocation.isNotEmpty) {
      Map<String, dynamic>? locationData = _parseJson(savedLocation);
      if (locationData != null && locationData['location'] != null) {
        final loc = locationData['location'] as Map<String, dynamic>;
        return 'IP: ${loc['ip'] ?? 'Unknown IP'}\n'
            '国家: ${loc['country'] ?? 'Unknown'}\n'
            '地区: ${loc['region'] ?? 'Unknown'}\n'
            '城市: ${loc['city'] ?? 'Unknown'}';
      }
    }
    return '暂无位置信息';
  }

  /// 获取屏幕尺寸
  String getScreenSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return '${size.width.toInt()}x${size.height.toInt()}';
  }

  /// 获取设备信息和 User-Agent
  Future<String> getDeviceInfo({bool userAgent = false}) async {
    if (userAgent && _cachedUserAgent != null) return _cachedUserAgent!;
    if (!userAgent && _cachedDeviceInfo != null) return _cachedDeviceInfo!;

    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    try {
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
    } catch (e, stackTrace) {
      // 添加异常处理，确保未知平台时有默认值
      LogUtil.logError('获取设备信息失败', e, stackTrace);
      _cachedDeviceInfo = 'Unknown Device';
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
      final locationString = _formatLocationString(ipData);

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

      // 直接发送
      final response = await HttpUtil().postRequest<String>(
        umamiUrl,
        data: jsonEncode(payload),
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
        ),
        cancelToken: CancelToken(),
      );

      if (response != null) {
        LogUtil.i('页面访问统计数据发送成功');
      } else {
        LogUtil.e('发送页面访问统计数据失败，响应为空');
      }
    } catch (error, stackTrace) {
      LogUtil.logError('发送页面访问数据时发生错误', error, stackTrace);
    }
  }
}
