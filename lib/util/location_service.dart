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
  /// 用户位置与设备信息缓存，存储键值对
  Map<String, dynamic>? _cachedUserInfo;

  /// 本地存储用户信息的键名
  static const String SP_KEY_USER_INFO = 'user_all_info';
  /// 缓存有效期，48小时（毫秒）
  static const int CACHE_EXPIRY_MS = 48 * 60 * 60 * 1000;

  /// 设备信息插件实例，获取设备相关信息
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// 默认IP地址未知值
  static const String _unknownIP = 'Unknown IP';
  /// 默认国家未知值
  static const String _unknownCountry = 'Unknown Country';
  /// 默认地区未知值
  static const String _unknownRegion = 'Unknown Region';
  /// 默认城市未知值
  static const String _unknownCity = 'Unknown City';

  /// 静态缓存设备信息，应用生命周期内不变
  static Map<String, String>? _cachedDeviceInfo;

  /// 默认位置信息，静态复用避免重复创建
  static final Map<String, dynamic> _defaultLocationInfo = {
    'ip': _unknownIP,
    'country': _unknownCountry,
    'region': _unknownRegion,
    'city': _unknownCity,
    'source': 'default',
  };

  /// 位置信息API配置列表
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

  /// 解析JSON字符串为Map对象
  Map<String, dynamic>? _parseJson(String? data) {
    if (data?.isEmpty ?? true) return null;
    try {
      return jsonDecode(data!);
    } catch (e) {
      LogUtil.e('JSON解析失败: $e');
      return null;
    }
  }

  /// 格式化位置信息为字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    final city = locationData['city'] ?? _unknownCity;
    final region = locationData['region'] ?? _unknownRegion;
    final country = locationData['country'] ?? _unknownCountry;
    return '$city, $region, $country';
  }

  /// 获取用户完整信息，优先从缓存读取，过期则重新获取
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    /// 检查内存缓存
    if (_cachedUserInfo != null) {
      LogUtil.i('命中内存缓存用户信息');
      return _cachedUserInfo!;
    }

    /// 检查本地缓存
    final savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo?.isNotEmpty == true) {
      final cachedData = _parseJson(savedInfo);
      if (cachedData != null) {
        final timestamp = cachedData['timestamp'];
        if (timestamp != null) {
          final currentTime = DateTime.now().millisecondsSinceEpoch;
          if (currentTime <= (timestamp + CACHE_EXPIRY_MS)) {
            _cachedUserInfo = cachedData['info'];
            LogUtil.i('命中本地缓存用户信息, 时间戳: ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
            return _cachedUserInfo!;
          }
        }
      }
    }

    try {
      /// 并发获取位置和设备信息
      final futures = await Future.wait([
        _getNativeLocationInfo(),
        _fetchDeviceInfo(),
      ]);
      
      final locationInfo = futures[0] as Map<String, dynamic>;
      final deviceInfo = futures[1] as Map<String, dynamic>;
      
      /// 构建用户信息
      final userInfo = {
        'location': locationInfo,
        'deviceInfo': deviceInfo['device'],
        'userAgent': deviceInfo['userAgent'],
        'screenSize': _fetchScreenSize(context),
      };

      /// 缓存用户信息
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cacheData = {'timestamp': timestamp, 'info': userInfo};
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData));
      _cachedUserInfo = userInfo;
      
      /// 记录用户信息获取结果
      final logBuffer = StringBuffer()
        ..write('用户信息获取成功: IP=')
        ..write(userInfo['location']['ip'])
        ..write(', 位置=')
        ..write(_formatLocationString(userInfo['location']))
        ..write(', 设备=')
        ..write(userInfo['deviceInfo'])
        ..write(', User-Agent=')
        ..write(userInfo['userAgent'])
        ..write(', 屏幕=')
        ..write(userInfo['screenSize']);
      LogUtil.i(logBuffer.toString());
      
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.e('用户信息获取失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 通过API获取用户位置信息
  Future<Map<String, dynamic>> _getNativeLocationInfo() async {
    try {
      LogUtil.i('开始请求位置信息API');
      return await _fetchLocationInfo();
    } catch (e, stackTrace) {
      LogUtil.e('位置信息获取失败: $e');
      return _defaultLocationInfo;
    }
  }

  /// 顺序请求多个API获取位置信息
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
    final cancelToken = CancelToken();
    
    try {
      for (var api in _apiList) {
        try {
          /// 请求API数据
          LogUtil.i('请求位置API: ${api['url']}');
          final responseData = await HttpUtil().getRequest<String>(
            api['url'] as String,
            cancelToken: cancelToken,
          );
          
          if (responseData != null) {
            /// 解析API响应数据
            final parsedData = jsonDecode(responseData);
            if (parsedData != null) {
              final result = (api['parseData'] as dynamic Function(dynamic))(parsedData);
              if (result != null) {
                /// 记录成功获取的位置信息
                final logBuffer = StringBuffer()
                  ..write('位置API成功: ')
                  ..write(result['city'])
                  ..write(', ')
                  ..write(result['region'])
                  ..write(', ')
                  ..write(result['country']);
                LogUtil.i(logBuffer.toString());
                return result;
              }
            }
          }
          
          LogUtil.i('API数据无效: ${api['url']}');
        } catch (e, stackTrace) {
          LogUtil.e('位置API请求失败: ${api['url']}, 错误: $e');
        }
      }
    } finally {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('请求结束');
      }
    }

    LogUtil.e('所有位置API失败，返回默认位置信息');
    return _defaultLocationInfo;
  }

  /// 获取设备信息和User-Agent
  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    /// 检查设备信息缓存
    if (_cachedDeviceInfo != null) {
      LogUtil.i('命中设备信息缓存');
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
      
      /// 记录设备信息获取结果
      LogUtil.i('设备信息获取成功: $deviceInfo, User-Agent=$userAgent');
      
      /// 缓存设备信息
      _cachedDeviceInfo = {'device': deviceInfo, 'userAgent': userAgent};
      
      return _cachedDeviceInfo!;
    } catch (e, stackTrace) {
      LogUtil.e('设备信息获取失败: $e');
      
      /// 缓存默认设备信息
      _cachedDeviceInfo = {
        'device': 'Unknown Device',
        'userAgent': '${Config.packagename}/${Config.version} (Unknown Platform)'
      };
      
      return _cachedDeviceInfo!;
    }
  }

  /// 获取屏幕分辨率
  String _fetchScreenSize(BuildContext context) {
    try {
      /// 获取屏幕尺寸
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
        LogUtil.i('缓存命中: 键=$key, 值=$value');
        return value;
      }
    }
    LogUtil.i('缓存未命中: 键=$key');
    return null;
  }

  /// 获取格式化后的位置信息字符串
  String getLocationString() {
    LogUtil.i('获取格式化位置信息字符串');
    final loc = _getCachedValue<Map<String, dynamic>>('location');
    if (loc != null) {
      final ip = loc['ip'] ?? _unknownIP;
      final country = loc['country'] ?? 'Unknown';
      final region = loc['region'] ?? 'Unknown';
      final city = loc['city'] ?? 'Unknown';
      /// 格式化位置信息
      final buffer = StringBuffer()
        ..write('IP: ')
        ..write(ip)
        ..write('\n国家: ')
        ..write(country)
        ..write('\n地区: ')
        ..write(region)
        ..write('\n城市: ')
        ..write(city);
      return buffer.toString();
    }
    LogUtil.i('无可用位置信息');
    return '暂无位置信息';
  }

  /// 获取设备信息字符串
  String getDeviceInfo() {
    final deviceInfo = _getCachedValue<String>('deviceInfo') ?? 'Unknown Device';
    LogUtil.i('获取设备信息: $deviceInfo');
    return deviceInfo;
  }

  /// 获取User-Agent字符串
  String getUserAgent() {
    final userAgent = _getCachedValue<String>('userAgent') ?? '${Config.packagename}/${Config.version} (Unknown Platform)';
    LogUtil.i('获取User-Agent: $userAgent');
    return userAgent;
  }

  /// 获取屏幕分辨率字符串
  String getScreenSize() {
    final screenSize = _getCachedValue<String>('screenSize') ?? 'Unknown Size';
    LogUtil.i('获取屏幕分辨率: $screenSize');
    return screenSize;
  }
}
