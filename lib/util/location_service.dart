import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geocoding/geocoding.dart';
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
    LogUtil.i('LocationService.resetCache: 重置用户信息缓存');
  }

  /// 解析JSON字符串为Map
  Map<String, dynamic>? _parseJson(String? data) {
    if (data?.isEmpty ?? true) return null;
    try {
      return jsonDecode(data!);
    } catch (e) {
      LogUtil.e('LocationService._parseJson: JSON解析失败, 错误: $e');
      return null;
    }
  }

  /// 格式化位置信息为字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    final buffer = StringBuffer()
      ..write(locationData['city'] ?? _unknownCity)
      ..write(', ')
      ..write(locationData['region'] ?? _unknownRegion)
      ..write(', ')
      ..write(locationData['country'] ?? _unknownCountry);
    return buffer.toString();
  }

  /// 获取用户完整信息，优先使用缓存
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    LogUtil.i('LocationService.getUserAllInfo: 获取用户信息');
    if (_cachedUserInfo != null) {
      LogUtil.i('LocationService.getUserAllInfo: 返回内存缓存');
      return _cachedUserInfo!;
    }

    String? savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo != null && savedInfo.isNotEmpty) {
      Map<String, dynamic>? cachedData = _parseJson(savedInfo);
      if (cachedData != null) {
        final timestamp = cachedData['timestamp'];
        if (timestamp != null) {
          final currentTime = DateTime.now().millisecondsSinceEpoch;
          if (currentTime <= (timestamp + CACHE_EXPIRY_MS)) {
            _cachedUserInfo = cachedData['info'];
            LogUtil.i('LocationService.getUserAllInfo: 读取本地缓存, 时间戳: ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
            return _cachedUserInfo!;
          }
        }
      }
    }

    try {
      final futures = await Future.wait([
        _getNativeLocationInfo(),
        _fetchDeviceInfo(),
      ]);
      
      final locationInfo = futures[0] as Map<String, dynamic>;
      final deviceInfo = futures[1] as Map<String, dynamic>;
      
      Map<String, dynamic> userInfo = {
        'location': locationInfo,
        'deviceInfo': deviceInfo['device'],
        'userAgent': deviceInfo['userAgent'],
        'screenSize': _fetchScreenSize(context),
      };

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cacheData = {
        'timestamp': timestamp,
        'info': userInfo
      };
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData));
      _cachedUserInfo = userInfo;
      LogUtil.i('LocationService.getUserAllInfo: 获取成功, IP=${userInfo['location']['ip']}, 位置=${_formatLocationString(userInfo['location'])}, 设备=${userInfo['deviceInfo']}, User-Agent=${userInfo['userAgent']}, 屏幕=${userInfo['screenSize']}');
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('LocationService.getUserAllInfo: 获取失败, 错误: $e', e, stackTrace);
      return {'error': e.toString()};
    }
  }

  /// 获取原生地理位置，优先使用LocationManager
  Future<Map<String, dynamic>> _getNativeLocationInfo() async {
    LogUtil.i('LocationService._getNativeLocationInfo: 获取原生位置');
    Map<String, dynamic>? ipInfo;
    
    try {
      ipInfo = await _fetchIPOnly();
      LogUtil.i('LocationService._getNativeLocationInfo: IP获取成功, IP=${ipInfo['ip']}');
    } catch (e) {
      LogUtil.e('LocationService._getNativeLocationInfo: IP获取失败, 错误: $e');
      ipInfo = {'ip': _unknownIP};
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        LogUtil.i('LocationService._getNativeLocationInfo: 位置服务未启用, 回退API');
        return _fetchLocationInfo();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          LogUtil.i('LocationService._getNativeLocationInfo: 位置权限拒绝, 回退API');
          return _fetchLocationInfo();
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        LogUtil.i('LocationService._getNativeLocationInfo: 位置权限永久拒绝, 回退API');
        return _fetchLocationInfo();
      }

      return await _tryMultipleLocationApproaches(ipInfo);
      
    } catch (e, stackTrace) {
      LogUtil.logError('LocationService._getNativeLocationInfo: 原生位置获取失败, 错误: $e', e, stackTrace);
      return _fetchLocationInfo();
    }
  }

  /// 并发执行网络定位和平衡定位
  Future<Map<String, dynamic>> _tryMultipleLocationApproaches(
      Map<String, dynamic> ipInfo) async {
    LogUtil.i('LocationService._tryMultipleLocationApproaches: 并发定位');
    
    final networkCompleter = Completer<Map<String, dynamic>?>();
    final balancedCompleter = Completer<Map<String, dynamic>?>();
    
    _tryLocationMethod(LocationAccuracy.low, '网络定位').timeout(
      Duration(seconds: 3),
      onTimeout: () => throw TimeoutException('网络定位3秒超时'),
    ).then((result) {
      if (!networkCompleter.isCompleted) {
        networkCompleter.complete(result);
      }
    }).catchError((error) {
      if (!networkCompleter.isCompleted) {
        networkCompleter.complete(null);
      }
    });
    
    _tryLocationMethod(LocationAccuracy.medium, '平衡定位').timeout(
      Duration(seconds: 3),
      onTimeout: () => throw TimeoutException('平衡定位3秒超时'),
    ).then((result) {
      if (!balancedCompleter.isCompleted) {
        balancedCompleter.complete(result);
      }
    }).catchError((error) {
      if (!balancedCompleter.isCompleted) {
        balancedCompleter.complete(null);
      }
    });
    
    final results = await Future.wait([
      networkCompleter.future,
      balancedCompleter.future,
    ]);
    
    final networkResult = results[0];
    final balancedResult = results[1];
    
    if (networkResult != null) {
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 网络定位成功');
    } else {
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 网络定位失败');
    }
    
    if (balancedResult != null) {
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 平衡定位成功');
    } else {
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 平衡定位失败');
    }
    
    Map<String, dynamic>? chosenResult;
    if (balancedResult != null) {
      chosenResult = balancedResult;
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 使用平衡定位结果');
    } else if (networkResult != null) {
      chosenResult = networkResult;
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 使用网络定位结果');
    }
    
    if (chosenResult != null) {
      try {
        final locationResult = await _processLocationResult(
          chosenResult['position'], 
          ipInfo, 
          chosenResult['method']
        );
        
        if (locationResult['city'] != _unknownCity || 
            locationResult['region'] != _unknownRegion || 
            locationResult['country'] != _unknownCountry) {
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 地理编码成功, 位置=${_formatLocationString(locationResult)}');
          return locationResult;
        } else {
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 地理编码失败, 回退API');
        }
      } catch (e) {
        LogUtil.e('LocationService._tryMultipleLocationApproaches: 地理编码异常, 错误: $e');
      }
    }
    
    LogUtil.i('LocationService._tryMultipleLocationApproaches: 原生定位失败, 回退API');
    return _fetchLocationInfo();
  }

  /// 使用geolocator尝试单一定位方式
  Future<Map<String, dynamic>> _tryLocationMethod(
      LocationAccuracy accuracy,
      String methodName) async {
    LogUtil.i('LocationService._tryLocationMethod: 尝试$methodName');
    try {
      late LocationSettings locationSettings;
      
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: accuracy,
          distanceFilter: 10,
          forceLocationManager: true,
        );
      } else {
        locationSettings = LocationSettings(
          accuracy: accuracy,
          distanceFilter: 10,
        );
      }
      
      final position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      
      LogUtil.i('LocationService._tryLocationMethod: $methodName成功, 经纬度=(${position.latitude}, ${position.longitude})');
      return {
        'position': position,
        'method': methodName,
      };
      
    } catch (e) {
      LogUtil.e('LocationService._tryLocationMethod: $methodName失败, 错误: $e');
      rethrow;
    }
  }

  /// 处理定位结果并进行地理编码
  Future<Map<String, dynamic>> _processLocationResult(
      Position position, 
      Map<String, dynamic> ipInfo, 
      String methodName) async {
    LogUtil.i('LocationService._processLocationResult: 地理编码, 方法=$methodName');
    
    try {
      try {
        await setLocaleIdentifier('zh_CN');
      } catch (e) {
        LogUtil.e('LocationService._processLocationResult: 设置区域失败, 错误: $e');
      }
      
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude
      ).timeout(
        Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('地理编码2秒超时'),
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        LogUtil.i('LocationService._processLocationResult: 原生地理编码成功, 位置=${place.locality}, ${place.administrativeArea}, ${place.country}');
        return {
          'ip': ipInfo['ip'] ?? _unknownIP,
          'country': place.country ?? _unknownCountry,
          'region': place.administrativeArea ?? _unknownRegion,
          'city': place.locality ?? _unknownCity,
          'source': 'native-$methodName',
        };
      }
    } catch (e) {
      LogUtil.e('LocationService._processLocationResult: 原生地理编码失败, 错误: $e');
    }
    
    try {
      LogUtil.i('LocationService._processLocationResult: 尝试Nominatim地理编码');
      final nominatimResult = await _tryNominatimGeocoding(position.latitude, position.longitude);
      
      if (nominatimResult != null) {
        LogUtil.i('LocationService._processLocationResult: Nominatim地理编码成功, 位置=${nominatimResult['city']}, ${nominatimResult['region']}, ${nominatimResult['country']}');
        return {
          'ip': ipInfo['ip'] ?? _unknownIP,
          'country': nominatimResult['country'] ?? _unknownCountry,
          'region': nominatimResult['region'] ?? _unknownRegion,
          'city': nominatimResult['city'] ?? _unknownCity,
          'source': 'nominatim-$methodName',
        };
      }
    } catch (e) {
      LogUtil.e('LocationService._processLocationResult: Nominatim地理编码失败, 错误: $e');
    }
    
    LogUtil.i('LocationService._processLocationResult: 地理编码失败, 使用坐标信息');
    return {
      'ip': ipInfo['ip'] ?? _unknownIP,
      'country': _unknownCountry,
      'region': _unknownRegion,
      'city': _unknownCity,
      'source': 'native-partial',
    };
  }

  /// 使用Nominatim服务进行地理编码
  Future<Map<String, dynamic>?> _tryNominatimGeocoding(double latitude, double longitude) async {
    try {
      final String url = 'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$latitude&lon=$longitude&addressdetails=1&accept-language=zh-CN,zh,en';
      
      final responseData = await HttpUtil().getRequest<String>(
        url,
        cancelToken: CancelToken(),
      );
      
      if (responseData != null) {
        final data = jsonDecode(responseData);
        if (data['address'] != null) {
          final addr = data['address'];
          LogUtil.i('LocationService._tryNominatimGeocoding: 成功, 位置=${addr['city'] ?? addr['town'] ?? addr['village']}, ${addr['state'] ?? addr['province']}, ${addr['country']}');
          return {
            'country': addr['country'] ?? _unknownCountry,
            'region': addr['state'] ?? addr['province'] ?? _unknownRegion, 
            'city': addr['city'] ?? addr['town'] ?? addr['village'] ?? _unknownCity,
          };
        }
      }
    } catch (e) {
      LogUtil.e('LocationService._tryNominatimGeocoding: 失败, 错误: $e');
    }
    return null;
  }

  /// 通过API获取IP信息
  Future<Map<String, dynamic>> _fetchIPOnly() async {
    LogUtil.i('LocationService._fetchIPOnly: 请求IP信息, URL=https://myip.ipip.net/json');
    try {
      final responseData = await HttpUtil().getRequest<String>(
        'https://myip.ipip.net/json',
        cancelToken: CancelToken(),
      );
      
      if (responseData != null) {
        Map<String, dynamic>? parsedData = _parseJson(responseData);
        if (parsedData != null && parsedData['ret'] == 'ok' && 
            parsedData['data'] != null && parsedData['data']['ip'] != null) {
          LogUtil.i('LocationService._fetchIPOnly: 成功, IP=${parsedData['data']['ip']}');
          return {'ip': parsedData['data']['ip']};
        }
      }
    } catch (e) {
      LogUtil.e('LocationService._fetchIPOnly: 失败, 错误: $e');
    }
    
    LogUtil.i('LocationService._fetchIPOnly: 返回默认IP');
    return {'ip': _unknownIP};
  }

  /// 顺序请求多个API获取位置信息
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
    LogUtil.i('LocationService._fetchLocationInfo: 开始API定位');
    final cancelToken = CancelToken();
    
    try {
      for (var api in _apiList) {
        try {
          LogUtil.i('LocationService._fetchLocationInfo: 请求API, URL=${api['url']}');
          final responseData = await HttpUtil().getRequest<String>(
            api['url'] as String,
            cancelToken: cancelToken,
          );
          
          if (responseData != null) {
            Map<String, dynamic>? parsedData = _parseJson(responseData);
            if (parsedData != null) {
              final result = (api['parseData'] as dynamic Function(dynamic))(parsedData);
              if (result != null) {
                LogUtil.i('LocationService._fetchLocationInfo: 成功, 位置=${result['city']}, ${result['region']}, ${result['country']}');
                return result;
              }
            }
          }
          
          LogUtil.i('LocationService._fetchLocationInfo: API数据无效, 尝试下一API');
        } catch (e, stackTrace) {
          LogUtil.logError('LocationService._fetchLocationInfo: API请求失败, URL=${api['url']}, 错误: $e', e, stackTrace);
        }
      }
    } finally {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('请求结束');
        LogUtil.i('LocationService._fetchLocationInfo: 清理CancelToken');
      }
    }

    LogUtil.e('LocationService._fetchLocationInfo: 所有API失败, 返回默认值');
    return {
      'ip': _unknownIP, 
      'country': 'Unknown', 
      'region': 'Unknown', 
      'city': 'Unknown',
      'source': 'default',
    };
  }

  /// 获取设备信息和User-Agent
  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    LogUtil.i('LocationService._fetchDeviceInfo: 获取设备信息');
    String deviceInfo;
    String userAgent;
    
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfoPlugin.androidInfo;
        deviceInfo = '${androidInfo.model} (${androidInfo.version.release})';
        userAgent = '${Config.packagename}/${Config.version} (Android; ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfoPlugin.iosInfo;
        deviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})';
        userAgent = '${Config.packagename}/${Config.version} (iOS; ${iosInfo.systemVersion})';
      } else {
        deviceInfo = 'Unknown Device (${Platform.operatingSystem})';
        userAgent = '${Config.packagename}/${Config.version} (${Platform.operatingSystem})';
      }
      
      LogUtil.i('LocationService._fetchDeviceInfo: 成功, 设备=$deviceInfo, User-Agent=$userAgent');
      return {'device': deviceInfo, 'userAgent': userAgent};
    } catch (e, stackTrace) {
      LogUtil.logError('LocationService._fetchDeviceInfo: 失败, 错误: $e', e, stackTrace);
      return {
        'device': 'Unknown Device',
        'userAgent': '${Config.packagename}/${Config.version} (Unknown Platform)'
      };
    }
  }

  /// 获取屏幕尺寸
  String _fetchScreenSize(BuildContext context) {
    LogUtil.i('LocationService._fetchScreenSize: 获取屏幕尺寸');
    try {
      final size = MediaQuery.of(context).size;
      final screenSize = '${size.width.toInt()}x${size.height.toInt()}';
      LogUtil.i('LocationService._fetchScreenSize: 成功, 尺寸=$screenSize');
      return screenSize;
    } catch (e) {
      LogUtil.e('LocationService._fetchScreenSize: 失败, 错误: $e');
      return 'Default Size (720x1280)';
    }
  }

  /// 从缓存获取指定键值
  T? _getCachedValue<T>(String key) {
    if (_cachedUserInfo != null && _cachedUserInfo!.containsKey(key)) {
      final value = _cachedUserInfo![key];
      if (value is T) {
        LogUtil.i('LocationService._getCachedValue: 获取缓存, 键=$key, 值=$value');
        return value;
      }
    }
    LogUtil.i('LocationService._getCachedValue: 未找到缓存, 键=$key');
    return null;
  }

  /// 获取格式化位置信息字符串
  String getLocationString() {
    LogUtil.i('LocationService.getLocationString: 获取位置字符串');
    final loc = _getCachedValue<Map<String, dynamic>>('location');
    if (loc != null) {
      final buffer = StringBuffer()
        ..write('IP: ')
        ..write(loc['ip'] ?? _unknownIP)
        ..write('\n国家: ')
        ..write(loc['country'] ?? 'Unknown')
        ..write('\n地区: ')
        ..write(loc['region'] ?? 'Unknown')
        ..write('\n城市: ')
        ..write(loc['city'] ?? 'Unknown');
      final locationString = buffer.toString();
      LogUtil.i('LocationService.getLocationString: 成功, 位置=$locationString');
      return locationString;
    }
    LogUtil.i('LocationService.getLocationString: 无位置信息');
    return '暂无位置信息';
  }

  /// 获取设备信息
  String getDeviceInfo() {
    final deviceInfo = _getCachedValue<String>('deviceInfo') ?? 'Unknown Device';
    LogUtil.i('LocationService.getDeviceInfo: 设备=$deviceInfo');
    return deviceInfo;
  }

  /// 获取User-Agent
  String getUserAgent() {
    final userAgent = _getCachedValue<String>('userAgent') ?? '${Config.packagename}/${Config.version} (Unknown Platform)';
    LogUtil.i('LocationService.getUserAgent: User-Agent=$userAgent');
    return userAgent;
  }

  /// 获取屏幕尺寸
  String getScreenSize() {
    final screenSize = _getCachedValue<String>('screenSize') ?? 'Unknown Size';
    LogUtil.i('LocationService.getScreenSize: 尺寸=$screenSize');
    return screenSize;
  }
}
