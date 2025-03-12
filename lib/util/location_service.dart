import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

class LocationService {
  //缓存数据
  Map<String, dynamic>? _cachedIpData;
  String? _cachedDeviceInfo;
  String? _cachedUserAgent;

  // SP存储的key和缓存有效期常量
  static const String SP_KEY_LOCATION = 'user_location_info';
  static const String SP_KEY_DEVICE_INFO = 'user_device_info';
  static const String SP_KEY_USER_AGENT = 'user_user_agent';
  static const String SP_KEY_SCREEN_SIZE = 'user_screen_size';
  static const int CACHE_EXPIRY_HOURS = 48;
  static const int CACHE_EXPIRY_MS = CACHE_EXPIRY_HOURS * 60 * 60 * 1000;
  static const int REQUEST_TIMEOUT_SECONDS = 6;

  //检查缓存是否过期
  bool _isCacheExpired(int timestamp) {
    return DateTime.now().millisecondsSinceEpoch > (timestamp + CACHE_EXPIRY_MS);
  }

  /// 重置缓存
  void resetCache() {
    _cachedIpData = null;
    _cachedDeviceInfo = null;
    _cachedUserAgent = null;SpUtil.remove(SP_KEY_LOCATION);
    SpUtil.remove(SP_KEY_DEVICE_INFO);
    SpUtil.remove(SP_KEY_USER_AGENT);
    SpUtil.remove(SP_KEY_SCREEN_SIZE);LogUtil.i('已重置地理位置和设备信息缓存');
  }

  /// JSON解析工具函数
  Map<String, dynamic>? _parseJson(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonDecode(data);
    } catch (e) {
      LogUtil.e('JSON 解析失败: $e');
      return null;
    }
  }

  /// 格式化位置信息字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    return '${locationData['city'] ?? 'Unknown City'}, '
        '${locationData['region'] ?? 'Unknown Region'}, '
        '${locationData['country'] ?? 'Unknown Country'}';
  }

  /// 获取用户的IP地址和地理位置信息
  Future<Map<String, dynamic>> getUserIpAndLocation() async {
    if (_cachedIpData != null) {
      return _cachedIpData!;
    }

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
        'parseData': (data) => {'ip': data['ip'] ?? 'Unknown IP',
              'country': data['country'] ?? 'Unknown Country',
              'region': data['province'] ?? 'Unknown Region',
              'city': data['city'] ?? 'Unknown City',}},
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
              'city': data['city'] ?? 'Unknown City','lat': data['lat'],
              'lon': data['lon'],
            }
      }
    ];

    for (var api in apiList) {
      try {
        final responseData = await HttpUtil().getRequest<String>(
          api['url'] as String,
          options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),cancelToken: CancelToken(),
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
            await SpUtil.putString(SP_KEY_LOCATION, jsonEncode(saveData));return _cachedIpData!;
          }
        }
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败', e, stackTrace);
      }
    }

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
        return 'IP: ${loc['ip'] ?? 'Unknown IP'}\n''国家: ${loc['country'] ?? 'Unknown'}\n'
            '地区: ${loc['region'] ?? 'Unknown'}\n'
            '城市: ${loc['city'] ?? 'Unknown'}';
      }
    }
    return '暂无位置信息';
  }

  /// 获取屏幕尺寸
  String getScreenSize(BuildContext context) {
    // 先尝试从本地存储中读取
    String? savedScreenSize = SpUtil.getString(SP_KEY_SCREEN_SIZE);
    if (savedScreenSize != null && savedScreenSize.isNotEmpty) {
      return savedScreenSize;
    }

    // 如果没有缓存，则获取并保存
    final size = MediaQuery.of(context).size;
    final screenSize = '${size.width.toInt()}x${size.height.toInt()}';
    
    // 保存到本地存储
    SpUtil.putString(SP_KEY_SCREEN_SIZE, screenSize);
    LogUtil.i('缓存屏幕尺寸到本地: $screenSize');
    return screenSize;
  }

  /// 获取设备信息和User-Agent
  Future<String> getDeviceInfo({bool userAgent = false}) async {
    if (userAgent) {
      String? savedUserAgent = SpUtil.getString(SP_KEY_USER_AGENT);
      if (savedUserAgent != null && savedUserAgent.isNotEmpty) {
        _cachedUserAgent = savedUserAgent;
        return _cachedUserAgent!;
      }
    } else {
      String? savedDeviceInfo = SpUtil.getString(SP_KEY_DEVICE_INFO);
      if (savedDeviceInfo != null && savedDeviceInfo.isNotEmpty) {
        _cachedDeviceInfo = savedDeviceInfo;
        return _cachedDeviceInfo!;
      }
    }

    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
        _cachedDeviceInfo = '${androidInfo.model} (${androidInfo.version.release})';
        _cachedUserAgent = '${Config.packagename}/${Config.version} (Android; ${androidInfo.version.release})';} else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
        _cachedDeviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})';
        _cachedUserAgent = '${Config.packagename}/${Config.version} (iOS; ${iosInfo.systemVersion})';
      } else {
        _cachedDeviceInfo = Platform.operatingSystem;
        _cachedUserAgent = '${Config.packagename}/${Config.version} (Unknown Platform)';
      }
      
      // 保存到本地存储
      await SpUtil.putString(SP_KEY_DEVICE_INFO, _cachedDeviceInfo!);
      await SpUtil.putString(SP_KEY_USER_AGENT, _cachedUserAgent!);
      
      LogUtil.i('缓存设备信息到本地: $_cachedDeviceInfo');
      LogUtil.i('缓存User-Agent到本地: $_cachedUserAgent');} catch (e, stackTrace) {
      LogUtil.logError('获取设备信息失败', e, stackTrace);_cachedDeviceInfo = 'Unknown Device';
      _cachedUserAgent = '${Config.packagename}/${Config.version} (Unknown Platform)';
      // 即使失败也保存默认值
      await SpUtil.putString(SP_KEY_DEVICE_INFO, _cachedDeviceInfo!);
      await SpUtil.putString(SP_KEY_USER_AGENT, _cachedUserAgent!);
    }
    return userAgent ? _cachedUserAgent! : _cachedDeviceInfo!;
  }
}
