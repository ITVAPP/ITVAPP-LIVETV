import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart' as location;
import 'package:geocoding/geocoding.dart';
import 'package:sp_util/sp_util.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/config.dart';

// LocationService 类用于获取和缓存用户位置、设备信息
class LocationService {
  Map<String, dynamic>? _cachedUserInfo; // 内存中的用户信息缓存

  static const String SP_KEY_USER_INFO = 'user_all_info'; // 本地存储用户信息键
  static const int CACHE_EXPIRY_HOURS = 48; // 缓存有效期（小时）
  static const int CACHE_EXPIRY_MS = 172800000; // 缓存有效期（毫秒）
  static const int REQUEST_TIMEOUT_SECONDS = 5; // 请求超时时间（秒）

  // 重置内存和本地缓存
  void resetCache() {
    _cachedUserInfo = null;
    SpUtil.remove(SP_KEY_USER_INFO); // 移除本地存储的用户信息
    LogUtil.i('已重置用户信息缓存');
  }

  // 解析 JSON 字符串为 Map
  Map<String, dynamic>? _parseJson(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonDecode(data); // 解析 JSON 数据
    } catch (e) {
      LogUtil.e('JSON 解析失败: $e');
      return null;
    }
  }

  // 格式化位置信息为字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    final buffer = StringBuffer();
    buffer.write(locationData['city'] ?? 'Unknown City');
    buffer.write(', ');
    buffer.write(locationData['region'] ?? 'Unknown Region');
    buffer.write(', ');
    buffer.write(locationData['country'] ?? 'Unknown Country');
    return buffer.toString();
  }

  // 获取用户所有信息，优先使用缓存
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    if (_cachedUserInfo != null) {
      LogUtil.i('从内存缓存读取用户信息');
      return _cachedUserInfo!; // 返回内存中的缓存数据
    }

    String? savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo != null && savedInfo.isNotEmpty) {
      Map<String, dynamic>? cachedData = _parseJson(savedInfo);
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      if (cachedData != null && cachedData['timestamp'] != null && 
          currentTime <= (cachedData['timestamp'] + CACHE_EXPIRY_MS)) {
        _cachedUserInfo = cachedData['info']; // 更新内存缓存
        LogUtil.i('从本地存储读取用户信息 (缓存时间: ${DateTime.fromMillisecondsSinceEpoch(cachedData['timestamp']).toString()})');
        return _cachedUserInfo!;
      }
    }

    LogUtil.i('开始获取用户所有信息...');
    Map<String, dynamic> userInfo = {};
    try {
      userInfo['location'] = await _getNativeLocationInfo(); // 获取原生位置信息
      Map<String, dynamic> deviceInfo = await _fetchDeviceInfo(); // 获取设备信息
      userInfo['deviceInfo'] = deviceInfo['device'];
      userInfo['userAgent'] = deviceInfo['userAgent'];
      userInfo['screenSize'] = _fetchScreenSize(context); // 获取屏幕尺寸

      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch, // 记录缓存时间戳
        'info': userInfo
      };
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData)); // 保存到本地存储
      _cachedUserInfo = userInfo; // 更新内存缓存
      LogUtil.i('''用户信息: IP地址: ${userInfo['location']['ip'] ?? 'N/A'}
  地理位置: ${_formatLocationString(userInfo['location'])}
  设备信息: ${userInfo['deviceInfo']}
  User-Agent: ${userInfo['userAgent']}
  屏幕尺寸: ${userInfo['screenSize']}
  已保存到本地存储''');
      
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户信息失败: $e', e, stackTrace);
      return {'error': e.toString()}; // 返回错误信息
    }
  }

  // 获取原生地理位置信息，失败时回退到 API
  Future<Map<String, dynamic>> _getNativeLocationInfo() async {
    Map<String, dynamic>? ipInfo;
    
    try {
      ipInfo = await _fetchIPOnly(); // 提前获取 IP 信息
    } catch (e) {
      LogUtil.e('获取 IP 信息失败: $e');
      ipInfo = {'ip': 'Unknown IP'};
    }
    
    location.Location locationInstance = location.Location(); // 初始化位置服务

    bool serviceEnabled;
    try {
      serviceEnabled = await locationInstance.serviceEnabled(); // 检查位置服务是否启用
      if (!serviceEnabled) {
        serviceEnabled = await locationInstance.requestService(); // 请求启用位置服务
        if (!serviceEnabled) {
          LogUtil.i('位置服务未启用，回退到 API');
          return _fetchLocationInfo(); // 回退到 API 获取位置
        }
      }

      location.PermissionStatus permission = await locationInstance.hasPermission(); // 检查位置权限
      if (permission == location.PermissionStatus.denied) {
        permission = await locationInstance.requestPermission(); // 请求位置权限
        if (permission == location.PermissionStatus.denied) {
          LogUtil.i('位置权限被拒绝，回退到 API');
          return _fetchLocationInfo(); // 回退到 API 获取位置
        }
      }
      
      if (permission == location.PermissionStatus.deniedForever) {
        LogUtil.i('位置权限永久拒绝，回退到 API');
        return _fetchLocationInfo(); // 回退到 API 获取位置
      }

      location.LocationData position = await locationInstance.getLocation().timeout(
        Duration(seconds: REQUEST_TIMEOUT_SECONDS), // 设置位置获取超时
        onTimeout: () => throw TimeoutException('获取位置超时'),
      );
      
      if (position.latitude == null || position.longitude == null) {
        throw Exception('位置数据无效（经纬度为空）');
      }
      
      LogUtil.i('获取设备位置: 经度=${position.longitude}, 纬度=${position.latitude}');
      
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude!, 
          position.longitude!,
          locale: 'zh_CN' // 使用中文地理编码
        );
        
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          return {
            'ip': ipInfo['ip'] ?? 'Unknown IP',
            'country': place.country ?? 'Unknown Country',
            'region': place.administrativeArea ?? 'Unknown Region',
            'city': place.locality ?? 'Unknown City',
            'source': 'native', // 标记原生数据来源
          };
        }
      } catch (e) {
        LogUtil.e('地理编码失败: $e，使用坐标和 IP');
        return {
          'ip': ipInfo['ip'] ?? 'Unknown IP',
          'country': 'Unknown Country',
          'region': 'Unknown Region',
          'city': 'Unknown City',
          'source': 'native-partial', // 标记部分原生数据
        };
      }
    } catch (e, stackTrace) {
      LogUtil.logError('原生位置获取失败: $e', e, stackTrace);
    }
    
    LogUtil.i('原生位置获取失败，回退到 API');
    return _fetchLocationInfo(); // 回退到 API 获取位置
  }

  // 通过 API 获取 IP 信息
  Future<Map<String, dynamic>> _fetchIPOnly() async {
    try {
      final responseData = await HttpUtil().getRequest<String>(
        'https://ip.useragentinfo.com/json',
        options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),
        cancelToken: CancelToken(),
      );
      
      if (responseData != null) {
        Map<String, dynamic>? parsedData = _parseJson(responseData);
        if (parsedData != null && parsedData['ip'] != null) {
          return {'ip': parsedData['ip']}; // 返回 IP 信息
        }
      }
    } catch (e) {
      LogUtil.e('获取 IP 信息失败: $e');
    }
    
    return {'ip': 'Unknown IP'}; // 返回默认 IP
  }

  // 并行请求多个 API 获取位置信息
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
    final apiList = [
      {
        'url': 'https://ip.useragentinfo.com/json',
        'parseData': (data) => {
          'ip': data['ip'] ?? 'Unknown IP',
          'country': data['country'] ?? 'Unknown Country',
          'region': data['province'] ?? 'Unknown Region',
          'city': data['city'] ?? 'Unknown City',
          'source': 'api-1', // 标记 API 数据来源
        }
      },
      {
        'url': 'https://open.saintic.com/ip/rest',
        'parseData': (data) => {
          'ip': data['data']?['ip'] ?? 'Unknown IP',
          'country': data['data']?['country'] ?? 'Unknown Country',
          'region': data['data']?['province'] ?? 'Unknown Region',
          'city': data['data']?['city'] ?? 'Unknown City',
          'source': 'api-2', // 标记 API 数据来源
        }
      },
      {
        'url': 'http://ip-api.com/json',
        'parseData': (data) => {
          'ip': data['query'] ?? 'Unknown IP',
          'country': data['country'] ?? 'Unknown Country',
          'region': data['regionName'] ?? 'Unknown Region',
          'city': data['city'] ?? 'Unknown City',
          'source': 'api-3', // 标记 API 数据来源
        }
      }
    ];

    final cancelToken = CancelToken(); // 创建统一取消令牌
    
    final timeoutFuture = Future.delayed(Duration(seconds: REQUEST_TIMEOUT_SECONDS * 2)).then((_) {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('并行请求超时');
        return null;
      }
    });

    final requests = apiList.map((api) async {
      try {
        final responseData = await HttpUtil().getRequest<String>(
          api['url'] as String,
          options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),
          cancelToken: cancelToken,
        );
        if (responseData != null) {
          Map<String, dynamic>? parsedData = _parseJson(responseData);
          if (parsedData != null) {
            return (api['parseData'] as dynamic Function(dynamic))(parsedData); // 解析 API 响应
          }
        }
        return null;
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败: $e', e, stackTrace);
        return null;
      }
    }).toList();

    final allFutures = [...requests, timeoutFuture];
    
    try {
      final results = await Future.wait(requests);
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('请求已完成'); // 取消超时保护
      }
      
      for (var result in results) {
        if (result != null) return result; // 返回首个成功结果
      }
    } catch (e) {
      LogUtil.e('并行位置请求失败: $e');
    }

    LogUtil.e('所有位置 API 请求失败，使用默认值');
    return {
      'ip': 'Unknown IP', 
      'country': 'Unknown', 
      'region': 'Unknown', 
      'city': 'Unknown',
      'source': 'default', // 标记默认数据
    };
  }

  // 获取设备信息和 User-Agent
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
        deviceInfo = 'Unknown Device (${Platform.operatingSystem})'; // 其他平台设备信息
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

  // 获取屏幕尺寸
  String _fetchScreenSize(BuildContext context) {
    try {
      final size = MediaQuery.of(context).size;
      return '${size.width.toInt()}x${size.height.toInt()}'; // 返回屏幕宽高
    } catch (e) {
      LogUtil.e('获取屏幕尺寸失败: $e');
      return 'Default Size (720x1280)'; // 默认屏幕尺寸
    }
  }

  // 从缓存中获取指定键的值
  T? _getCachedValue<T>(String key) {
    if (_cachedUserInfo != null && _cachedUserInfo!.containsKey(key)) {
      final value = _cachedUserInfo![key];
      if (value is T) return value; // 返回类型匹配的缓存值
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
    return '暂无位置信息'; // 无位置信息时的默认值
  }

  // 获取设备信息
  String getDeviceInfo() {
    return _getCachedValue<String>('deviceInfo') ?? 'Unknown Device'; // 返回缓存的设备信息
  }

  // 获取 User-Agent
  String getUserAgent() {
    return _getCachedValue<String>('userAgent') ?? '${Config.packagename}/${Config.version} (Unknown Platform)';
  }

  // 获取屏幕尺寸
  String getScreenSize() {
    return _getCachedValue<String>('screenSize') ?? 'Unknown Size'; // 返回缓存的屏幕尺寸
  }
}
