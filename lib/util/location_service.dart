import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/config.dart';

// LocationService 类用于获取和缓存用户位置、设备等信息
class LocationService {
  Map<String, dynamic>? _cachedUserInfo; // 内存中的用户信息缓存

  static const String SP_KEY_USER_INFO = 'user_all_info'; // 本地存储键
  static const int CACHE_EXPIRY_HOURS = 48; // 缓存有效期（小时）
  static const int CACHE_EXPIRY_MS = CACHE_EXPIRY_HOURS * 60 * 60 * 1000; // 缓存有效期（毫秒）
  static const int REQUEST_TIMEOUT_SECONDS = 5; // 请求超时时间（秒）

  // 检查缓存是否过期
  bool _isCacheExpired(int timestamp) {
    return DateTime.now().millisecondsSinceEpoch > (timestamp + CACHE_EXPIRY_MS); // 比较当前时间与缓存到期时间
  }

  // 重置内存和本地缓存
  void resetCache() {
    _cachedUserInfo = null;
    SpUtil.remove(SP_KEY_USER_INFO); // 删除本地存储中的缓存
    LogUtil.i('已重置用户信息缓存');
  }

  // 解析 JSON 数据
  Map<String, dynamic>? _parseJson(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonDecode(data); // 尝试解析 JSON
    } catch (e) {
      LogUtil.e('JSON解析失败: $e');
      return null;
    }
  }

  // 格式化位置信息为字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    return '${locationData['city'] ?? 'Unknown City'}, '
        '${locationData['region'] ?? 'Unknown Region'}, '
        '${locationData['country'] ?? 'Unknown Country'}';
  }

  // 获取用户所有信息，优先使用缓存
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    if (_cachedUserInfo != null) {
      LogUtil.i('从内存缓存读取用户信息');
      return _cachedUserInfo!; // 返回内存缓存
    }

    String? savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo != null && savedInfo.isNotEmpty) {
      Map<String, dynamic>? cachedData = _parseJson(savedInfo);
      if (cachedData != null && cachedData['timestamp'] != null && !_isCacheExpired(cachedData['timestamp'])) {
        _cachedUserInfo = cachedData['info']; // 更新内存缓存
        LogUtil.i('从本地存储读取用户信息(缓存时间: ${DateTime.fromMillisecondsSinceEpoch(cachedData['timestamp']).toString()})');
        return _cachedUserInfo!;
      }
    }

    LogUtil.i('开始获取用户所有信息...');
    Map<String, dynamic> userInfo = {};
    try {
      userInfo['location'] = await _fetchLocationInfo(); // 获取位置信息
      Map<String, dynamic> deviceInfo = await _fetchDeviceInfo(); // 获取设备信息
      userInfo['deviceInfo'] = deviceInfo['device'];
      userInfo['userAgent'] = deviceInfo['userAgent'];
      userInfo['screenSize'] = _fetchScreenSize(context); // 获取屏幕尺寸

      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch, // 添加时间戳
        'info': userInfo
      };
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData)); // 保存到本地存储
      _cachedUserInfo = userInfo; // 更新内存缓存
      LogUtil.i('''用户信息:IP地址: ${userInfo['location']['ip']}
  地理位置: ${_formatLocationString(userInfo['location'])}
  设备信息: ${userInfo['deviceInfo']}
  User-Agent: ${userInfo['userAgent']}
  屏幕尺寸: ${userInfo['screenSize']}
  已保存到本地存储''');
      
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户信息时发生错误: $e', e, stackTrace);
      return {'error': e.toString()}; // 返回错误信息
    }
  }

  // 并行请求位置信息，优化性能
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
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

    final requests = apiList.map((api) async {
      try {
        final responseData = await HttpUtil().getRequest<String>(
          api['url'] as String,
          options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),
          cancelToken: CancelToken(), // 支持请求取消
        );
        if (responseData != null) {
          Map<String, dynamic>? parsedData = _parseJson(responseData);
          if (parsedData != null) {
            return (api['parseData'] as dynamic Function(dynamic))(parsedData); // 解析响应数据
          }
        }
        return null;
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败: $e', e, stackTrace);
        return null;
      }
    }).toList();

    final results = await Future.wait(requests); // 等待所有请求完成
    for (var result in results) {
      if (result != null) return result; // 返回第一个成功结果
    }

    LogUtil.e('所有地理位置API请求均失败，使用默认值');
    return {'ip': 'Unknown IP', 'country': 'Unknown', 'region': 'Unknown', 'city': 'Unknown'}; // 默认值
  }

  // 获取设备信息和 User-Agent，支持多平台
  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    String deviceInfo;
    String userAgent;
    
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo = '${androidInfo.model} (${androidInfo.version.release})'; // Android 设备信息
        userAgent = '${Config.packagename}/${Config.version} (Android; ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})'; // iOS 设备信息
        userAgent = '${Config.packagename}/${Config.version} (iOS; ${iosInfo.systemVersion})';
      } else {
        deviceInfo = 'Unknown Device (${Platform.operatingSystem})'; // 其他平台默认值
        userAgent = '${Config.packagename}/${Config.version} (${Platform.operatingSystem})';
      }
      
      return {'device': deviceInfo, 'userAgent': userAgent};
    } catch (e, stackTrace) {
      LogUtil.logError('获取设备信息失败: $e', e, stackTrace);
      return {
        'device': 'Unknown Device',
        'userAgent': '${Config.packagename}/${Config.version} (Unknown Platform)' // 默认 User-Agent
      };
    }
  }

  // 获取屏幕尺寸，带默认值
  String _fetchScreenSize(BuildContext context) {
    try {
      final size = MediaQuery.of(context).size;
      return '${size.width.toInt()}x${size.height.toInt()}'; // 返回宽x高格式
    } catch (e) {
      LogUtil.e('获取屏幕尺寸失败: $e');
      return 'Default Size (720x1280)'; // 默认尺寸
    }
  }

  // 从缓存中获取指定键的值
  T? _getCachedValue<T>(String key) {
    if (_cachedUserInfo != null && _cachedUserInfo!.containsKey(key)) {
      final value = _cachedUserInfo![key];
      if (value is T) return value; // 类型匹配时返回
    }
    return null;
  }

  // 获取格式化的位置信息字符串
  String getLocationString() {
    final loc = _getCachedValue<Map<String, dynamic>>('location');
    if (loc != null) {
      return 'IP: ${loc['ip'] ?? 'Unknown IP'}\n'
          '国家: ${loc['country'] ?? 'Unknown'}\n'
          '地区: ${loc['region'] ?? 'Unknown'}\n'
          '城市: ${loc['city'] ?? 'Unknown'}';
    }
    return '暂无位置信息'; // 无缓存时返回
  }

  // 获取设备信息
  String getDeviceInfo() {
    return _getCachedValue<String>('deviceInfo') ?? 'Unknown Device'; // 从缓存获取或返回默认值
  }

  // 获取 User-Agent
  String getUserAgent() {
    return _getCachedValue<String>('userAgent') ?? '${Config.packagename}/${Config.version} (Unknown Platform)';
  }

  // 获取屏幕尺寸
  String getScreenSize() {
    return _getCachedValue<String>('screenSize') ?? 'Unknown Size'; // 从缓存获取或返回默认值
  }
}
