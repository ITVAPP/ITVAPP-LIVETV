import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/config.dart';

class LocationService {
  // 统一缓存数据
  Map<String, dynamic>? _cachedUserInfo;

  // 单一存储键和缓存有效期常量
  static const String SP_KEY_USER_INFO = 'user_all_info';
  static const int CACHE_EXPIRY_HOURS = 48;
  static const int CACHE_EXPIRY_MS = CACHE_EXPIRY_HOURS * 60 * 60 * 1000;
  static const int REQUEST_TIMEOUT_SECONDS = 6;

  // 检查缓存是否过期
  bool _isCacheExpired(int timestamp) {
    return DateTime.now().millisecondsSinceEpoch > (timestamp + CACHE_EXPIRY_MS);
  }

  /// 重置缓存
  void resetCache() {
    _cachedUserInfo = null;
    SpUtil.remove(SP_KEY_USER_INFO);
    LogUtil.i('已重置用户信息缓存');
  }

  /// JSON解析工具函数
  Map<String, dynamic>? _parseJson(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonDecode(data);
    } catch (e) {
      LogUtil.e('JSON解析失败: $e');
      return null;
    }
  }

  /// 格式化位置信息字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    return '${locationData['city'] ?? 'Unknown City'}, '
        '${locationData['region'] ?? 'Unknown Region'}, '
        '${locationData['country'] ?? 'Unknown Country'}';
  }

  /// 获取用户所有信息（统一接口）
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    // 检查内存缓存
    if (_cachedUserInfo != null) {
      LogUtil.i('从内存缓存读取用户信息');
      return _cachedUserInfo!;
    }

    // 检查本地存储缓存
    String? savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo != null && savedInfo.isNotEmpty) {
      Map<String, dynamic>? cachedData = _parseJson(savedInfo);
      if (cachedData != null) {
        int? timestamp = cachedData['timestamp'];
        if (timestamp != null && !_isCacheExpired(timestamp)) {
          _cachedUserInfo = cachedData['info'];
          LogUtil.i('从本地存储读取用户信息(缓存时间: ${DateTime.fromMillisecondsSinceEpoch(timestamp).toString()})');
          return _cachedUserInfo!;
        }
      }
    }

    //缓存不存在或已过期，开始获取所有信息
    LogUtil.i('开始获取用户所有信息...');
    Map<String, dynamic> userInfo = {};
    try {
      // 1. 获取位置信息
      Map<String, dynamic> locationInfo = await _fetchLocationInfo();
      userInfo['location'] = locationInfo;
      
      // 2. 获取设备信息和User-Agent
      Map<String, dynamic> deviceInfo = await _fetchDeviceInfo();
      userInfo['deviceInfo'] = deviceInfo['device'];
      userInfo['userAgent'] = deviceInfo['userAgent'];
      
      // 3. 获取屏幕尺寸
      String screenSize = _fetchScreenSize(context);
      userInfo['screenSize'] = screenSize;
      
      // 保存到本地存储
      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'info': userInfo
      };
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData));
      // 更新内存缓存
      _cachedUserInfo = userInfo;
      LogUtil.i('''用户信息:IP地址: ${locationInfo['ip']}
  地理位置: ${locationInfo['city']}, ${locationInfo['region']}, ${locationInfo['country']}
  设备信息: ${userInfo['deviceInfo']}
  User-Agent: ${userInfo['userAgent']}
  屏幕尺寸: $screenSize
  已保存到本地存储''');
      
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户信息时发生错误: $e', e, stackTrace);
      return {'error': e.toString()};
    }
  }

  /// 获取位置信息
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
    final apiList = [
      {
        'url': 'https://ip.useragentinfo.com/json',
        'parseData': (data) => {
          'ip': data['ip'] ?? 'Unknown IP',
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
            return result;
          }
        }
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败: $e', e, stackTrace);
      }
    }

    // 当所有API都失败时，记录一个统一的错误日志
    LogUtil.e('所有地理位置API请求均失败，使用默认值');
    return {'ip': 'Unknown IP', 'country': 'Unknown', 'region': 'Unknown', 'city': 'Unknown'};
  }

  /// 获取设备信息和User-Agent
  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    String deviceInfo;
    String userAgent;
    
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo = '${androidInfo.model} (${androidInfo.version.release})';
        userAgent = '${Config.packagename}/${Config.version} (Android; ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})';
        userAgent = '${Config.packagename}/${Config.version} (iOS; ${iosInfo.systemVersion})';
      } else {
        deviceInfo = Platform.operatingSystem;
        userAgent = '${Config.packagename}/${Config.version} (Unknown Platform)';
      }
      
      return {
        'device': deviceInfo,
        'userAgent': userAgent
      };
    } catch (e, stackTrace) {
      LogUtil.logError('获取设备信息失败: $e', e, stackTrace);
      return {
        'device': 'Unknown Device',
        'userAgent': '${Config.packagename}/${Config.version} (Unknown Platform)'
      };
    }
  }

  /// 获取屏幕尺寸
  String _fetchScreenSize(BuildContext context) {
    try {
      final size = MediaQuery.of(context).size;
      final screenSize = '${size.width.toInt()}x${size.height.toInt()}';
      return screenSize;
    } catch (e) {
      LogUtil.e('获取屏幕尺寸失败: $e');
      return 'Unknown Size';
    }
  }
  
  /// 获取位置信息字符串表示
  String getLocationString() {
    if (_cachedUserInfo != null && _cachedUserInfo!['location'] != null) {
      final loc = _cachedUserInfo!['location'] as Map<String, dynamic>;
      return'IP: ${loc['ip'] ?? 'Unknown IP'}\n'
          '国家: ${loc['country'] ?? 'Unknown'}\n'
          '地区: ${loc['region'] ?? 'Unknown'}\n'
          '城市: ${loc['city'] ?? 'Unknown'}';
    }
    return '暂无位置信息';
  }

  /// 获取设备信息
  String getDeviceInfo() {
    if (_cachedUserInfo != null && _cachedUserInfo!['deviceInfo'] != null) {
      return _cachedUserInfo!['deviceInfo'] as String;
    }
    return 'Unknown Device';
  }

  /// 获取User-Agent
  String getUserAgent() {
    if (_cachedUserInfo != null && _cachedUserInfo!['userAgent'] != null) {
      return _cachedUserInfo!['userAgent'] as String;
    }
    return '${Config.packagename}/${Config.version} (Unknown Platform)';
  }

  /// 获取屏幕尺寸
  String getScreenSize() {
    if (_cachedUserInfo != null && _cachedUserInfo!['screenSize'] != null) {
      return _cachedUserInfo!['screenSize'] as String;
    }
    return 'Unknown Size';
  }
}
