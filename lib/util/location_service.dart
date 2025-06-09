import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/config.dart';

/// 用户位置与设备信息获取及缓存服务
class LocationService {
  /// 内存缓存用户信息
  Map<String, dynamic>? _cachedUserInfo;

  /// 本地存储用户信息键
  static const String SP_KEY_USER_INFO = 'user_all_info';
  /// 缓存有效期48小时（毫秒）
  static const int CACHE_EXPIRY_MS = 48 * 60 * 60 * 1000;

  /// 静态设备信息插件实例
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// 预定义常量字符串，优化内存分配
  static const String _unknownIP = 'Unknown IP';
  static const String _unknownCountry = 'Unknown Country';
  static const String _unknownRegion = 'Unknown Region';
  static const String _unknownCity = 'Unknown City';

  /// 静态缓存设备信息（设备信息在应用生命周期内不变）
  static Map<String, String>? _cachedDeviceInfo;

  /// 静态API配置列表
  static final List<Map<String, dynamic>> _apiList = [
    {
      'url': 'https://myip.ipip.net/json',
      'parseData': (data) {
        if (data['ret'] == 'ok' && data['data'] != null) {
          final locationData = data['data'];
          final locationArray = locationData['location'] as List<dynamic>;
          return {
            'ip': locationData['ip'] ?? _unknownIP,
            'country': locationArray.isNotEmpty ? locationArray[0] : _unknownCountry,
            'region': locationArray.length > 1 ? locationArray[1] : _unknownRegion,
            'city': locationArray.length > 2 ? locationArray[2] : _unknownCity,
            'source': 'api-1',
          };
        }
        return null;
      }
    },
    {
      'url': 'https://open.saintic.com/ip/rest',
      'parseData': (data) => {
        'ip': data['data']?['ip'] ?? _unknownIP,
        'country': data['data']?['country'] ?? _unknownCountry,
        'region': data['data']?['province'] ?? _unknownRegion,
        'city': data['data']?['city'] ?? _unknownCity,
        'source': 'api-2',
      }
    },
    {
      'url': 'http://ip-api.com/json',
      'parseData': (data) => {
        'ip': data['query'] ?? _unknownIP,
        'country': data['country'] ?? _unknownCountry,
        'region': data['regionName'] ?? _unknownRegion,
        'city': data['city'] ?? _unknownCity,
        'source': 'api-3',
      }
    }
  ];

  /// 重置内存和本地用户信息缓存
  void resetCache() {
    _cachedUserInfo = null;
    SpUtil.remove(SP_KEY_USER_INFO);
  }

  /// 解析JSON数据
  Map<String, dynamic>? _parseJson(String? data) {
    if (data?.isEmpty ?? true) return null;
    try {
      return jsonDecode(data!);
    } catch (e) {
      LogUtil.e('JSON解析失败: $e');
      return null;
    }
  }

  /// 构建位置信息字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    final city = locationData['city'] ?? _unknownCity;
    final region = locationData['region'] ?? _unknownRegion;
    final country = locationData['country'] ?? _unknownCountry;
    return '$city, $region, $country';
  }

  /// 获取用户完整信息，优先使用缓存
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    // 检查内存缓存
    if (_cachedUserInfo != null) {
      LogUtil.i('使用内存缓存用户信息');
      return _cachedUserInfo!;
    }

    // 检查本地缓存
    final savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo?.isNotEmpty == true) {
      final cachedData = _parseJson(savedInfo);
      if (cachedData != null) {
        final timestamp = cachedData['timestamp'];
        if (timestamp != null) {
          final currentTime = DateTime.now().millisecondsSinceEpoch;
          if (currentTime <= (timestamp + CACHE_EXPIRY_MS)) {
            _cachedUserInfo = cachedData['info'];
            LogUtil.i('使用本地缓存用户信息, 时间戳: ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
            return _cachedUserInfo!;
          }
        }
      }
    }

    try {
      // 并发获取位置和设备信息
      final futures = await Future.wait([
        _getNativeLocationInfo(),
        _fetchDeviceInfo(),
      ]);
      
      final locationInfo = futures[0] as Map<String, dynamic>;
      final deviceInfo = futures[1] as Map<String, dynamic>;
      
      // 构建用户信息
      final userInfo = {
        'location': locationInfo,
        'deviceInfo': deviceInfo['device'],
        'userAgent': deviceInfo['userAgent'],
        'screenSize': _fetchScreenSize(context),
      };

      // 缓存用户信息
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cacheData = {'timestamp': timestamp, 'info': userInfo};
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData));
      _cachedUserInfo = userInfo;
      
      // 记录获取结果
      final locationString = _formatLocationString(userInfo['location']);
      LogUtil.i('用户信息获取成功: IP=${userInfo['location']['ip']}, 位置=$locationString, 设备=${userInfo['deviceInfo']}, User-Agent=${userInfo['userAgent']}, 屏幕=${userInfo['screenSize']}');
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('用户信息获取失败: $e', e, stackTrace);
      return {'error': e.toString()};
    }
  }

  /// 获取位置信息，直接使用API定位
  Future<Map<String, dynamic>> _getNativeLocationInfo() async {
    try {
      LogUtil.i('开始API定位');
      return await _fetchLocationInfo();
    } catch (e, stackTrace) {
      LogUtil.logError('API定位失败: $e', e, stackTrace);
      return {
        'ip': _unknownIP,
        'country': _unknownCountry,
        'region': _unknownRegion,
        'city': _unknownCity,
        'source': 'default',
      };
    }
  }

  /// 顺序请求多个API获取位置信息
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
    final cancelToken = CancelToken();
    
    try {
      for (var api in _apiList) {
        try {
          // 请求API数据
          LogUtil.i('请求API: ${api['url']}');
          final responseData = await HttpUtil().getRequest<String>(
            api['url'] as String,
            cancelToken: cancelToken,
          );
          
          if (responseData != null) {
            // 解析API数据
            final parsedData = jsonDecode(responseData);
            if (parsedData != null) {
              final result = (api['parseData'] as dynamic Function(dynamic))(parsedData);
              if (result != null) {
                LogUtil.i('API定位成功: ${result['city']}, ${result['region']}, ${result['country']}');
                return result;
              }
            }
          }
          
          LogUtil.i('API数据无效，尝试下一API');
        } catch (e, stackTrace) {
          LogUtil.logError('API请求失败: ${api['url']}, 错误: $e', e, stackTrace);
        }
      }
    } finally {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('请求结束');
        LogUtil.i('清理CancelToken');
      }
    }

    LogUtil.e('所有API定位失败，返回默认值');
    return {
      'ip': _unknownIP,
      'country': _unknownCountry,
      'region': _unknownRegion,
      'city': _unknownCity,
      'source': 'default',
    };
  }

  /// 获取设备信息和User-Agent
  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    // 检查设备信息缓存
    if (_cachedDeviceInfo != null) {
      LogUtil.i('使用缓存设备信息');
      return _cachedDeviceInfo!;
    }
    
    try {
      final String deviceInfo;
      final String userAgent;
      
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        deviceInfo = '${androidInfo.model} (${androidInfo.version.release})';
        userAgent = '${Config.packagename}/${Config.version} (Android; ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        deviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})';
        userAgent = '${Config.packagename}/${Config.version} (iOS; ${iosInfo.systemVersion})';
      } else {
        deviceInfo = 'Unknown Device (${Platform.operatingSystem})';
        userAgent = '${Config.packagename}/${Config.version} (${Platform.operatingSystem})';
      }
      
      LogUtil.i('设备信息获取成功: $deviceInfo, User-Agent=$userAgent');
      
      // 缓存设备信息
      _cachedDeviceInfo = {'device': deviceInfo, 'userAgent': userAgent};
      
      return _cachedDeviceInfo!;
    } catch (e, stackTrace) {
      LogUtil.logError('设备信息获取失败: $e', e, stackTrace);
      
      // 缓存默认设备信息
      _cachedDeviceInfo = {
        'device': 'Unknown Device',
        'userAgent': '${Config.packagename}/${Config.version} (Unknown Platform)'
      };
      
      return _cachedDeviceInfo!;
    }
  }

  /// 获取屏幕尺寸
  String _fetchScreenSize(BuildContext context) {
    try {
      // 获取屏幕尺寸
      final size = MediaQuery.of(context).size;
      final screenSize = '${size.width.toInt()}x${size.height.toInt()}';
      return screenSize;
    } catch (e) {
      LogUtil.e('屏幕尺寸获取失败: $e');
      return 'Default Size (720x1280)';
    }
  }

  /// 从缓存获取指定键值
  T? _getCachedValue<T>(String key) {
    if (_cachedUserInfo?.containsKey(key) == true) {
      final value = _cachedUserInfo![key];
      if (value is T) {
        LogUtil.i('缓存获取成功: 键=$key, 值=$value');
        return value;
      }
    }
    LogUtil.i('缓存未找到: 键=$key');
    return null;
  }

  /// 获取格式化位置信息字符串
  String getLocationString() {
    LogUtil.i('获取格式化位置信息');
    final loc = _getCachedValue<Map<String, dynamic>>('location');
    if (loc != null) {
      final ip = loc['ip'] ?? _unknownIP;
      final country = loc['country'] ?? 'Unknown';
      final region = loc['region'] ?? 'Unknown';
      final city = loc['city'] ?? 'Unknown';
      final locationString = 'IP: $ip\n国家: $country\n地区: $region\n城市: $city';
      return locationString;
    }
    LogUtil.i('无位置信息可用');
    return '暂无位置信息';
  }

  /// 获取设备信息
  String getDeviceInfo() {
    final deviceInfo = _getCachedValue<String>('deviceInfo') ?? 'Unknown Device';
    LogUtil.i('设备信息: $deviceInfo');
    return deviceInfo;
  }

  /// 获取User-Agent
  String getUserAgent() {
    final userAgent = _getCachedValue<String>('userAgent') ?? '${Config.packagename}/${Config.version} (Unknown Platform)';
    LogUtil.i('User-Agent: $userAgent');
    return userAgent;
  }

  /// 获取屏幕尺寸
  String getScreenSize() {
    final screenSize = _getCachedValue<String>('screenSize') ?? 'Unknown Size';
    LogUtil.i('屏幕尺寸: $screenSize');
    return screenSize;
  }
}
