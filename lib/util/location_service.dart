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
  /// 缓存有效期（小时）
  static const int CACHE_EXPIRY_HOURS = 48;
  /// 缓存有效期（毫秒）- 自动计算避免硬编码错误
  static const int CACHE_EXPIRY_MS = CACHE_EXPIRY_HOURS * 60 * 60 * 1000;
  /// 请求超时时间（秒）
  static const int REQUEST_TIMEOUT_SECONDS = 5;

  /// 静态设备信息插件实例
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// 静态API配置列表
  static final List<Map<String, dynamic>> _apiList = [
    {
      'url': 'https://myip.ipip.net/json',
      'parseData': (data) {
        if (data['ret'] == 'ok' && data['data'] != null) {
          final locationData = data['data'];
          final locationArray = locationData['location'] as List<dynamic>;
          return {
            'ip': locationData['ip'] ?? 'Unknown IP',
            'country': locationArray.isNotEmpty ? locationArray[0] : 'Unknown Country',
            'region': locationArray.length > 1 ? locationArray[1] : 'Unknown Region',
            'city': locationArray.length > 2 ? locationArray[2] : 'Unknown City',
            'source': 'api-1',
          };
        }
        return null;
      }
    },
    {
      'url': 'https://open.saintic.com/ip/rest',
      'parseData': (data) => {
        'ip': data['data']?['ip'] ?? 'Unknown IP',
        'country': data['data']?['country'] ?? 'Unknown Country',
        'region': data['data']?['province'] ?? 'Unknown Region',
        'city': data['data']?['city'] ?? 'Unknown City',
        'source': 'api-2',
      }
    },
    {
      'url': 'http://ip-api.com/json',
      'parseData': (data) => {
        'ip': data['query'] ?? 'Unknown IP',
        'country': data['country'] ?? 'Unknown Country',
        'region': data['regionName'] ?? 'Unknown Region',
        'city': data['city'] ?? 'Unknown City',
        'source': 'api-3',
      }
    }
  ];

  /// 重置内存和本地用户信息缓存
  void resetCache() {
    _cachedUserInfo = null;
    SpUtil.remove(SP_KEY_USER_INFO);
    LogUtil.i('LocationService.resetCache: 用户信息缓存已重置');
  }

  /// 解析JSON数据
  Map<String, dynamic>? _parseJson(String? data) {
    if (data?.isEmpty ?? true) return null;
    try {
      return jsonDecode(data!);
    } catch (e) {
      LogUtil.e('LocationService._parseJson: JSON解析失败: $e');
      return null;
    }
  }

  /// 格式化位置信息为字符串
  String _formatLocationString(Map<String, dynamic> locationData) {
    return '${locationData['city'] ?? 'Unknown City'}, '
           '${locationData['region'] ?? 'Unknown Region'}, '
           '${locationData['country'] ?? 'Unknown Country'}';
  }

  /// 获取用户所有信息，优先使用缓存
  Future<Map<String, dynamic>> getUserAllInfo(BuildContext context) async {
    LogUtil.i('LocationService.getUserAllInfo: 开始获取用户信息');
    if (_cachedUserInfo != null) {
      LogUtil.i('LocationService.getUserAllInfo: 返回内存缓存数据');
      return _cachedUserInfo!;
    }

    String? savedInfo = SpUtil.getString(SP_KEY_USER_INFO);
    if (savedInfo != null && savedInfo.isNotEmpty) {
      Map<String, dynamic>? cachedData = _parseJson(savedInfo);
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      if (cachedData != null && cachedData['timestamp'] != null && 
          currentTime <= (cachedData['timestamp'] + CACHE_EXPIRY_MS)) {
        _cachedUserInfo = cachedData['info'];
        LogUtil.i('LocationService.getUserAllInfo: 从本地缓存读取用户信息, 时间戳: ${DateTime.fromMillisecondsSinceEpoch(cachedData['timestamp'])}');
        return _cachedUserInfo!;
      }
    }

    try {
      Map<String, dynamic> userInfo = {};
      userInfo['location'] = await _getNativeLocationInfo();
      Map<String, dynamic> deviceInfo = await _fetchDeviceInfo();
      userInfo['deviceInfo'] = deviceInfo['device'];
      userInfo['userAgent'] = deviceInfo['userAgent'];
      userInfo['screenSize'] = _fetchScreenSize(context);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cacheData = {
        'timestamp': timestamp,
        'info': userInfo
      };
      await SpUtil.putString(SP_KEY_USER_INFO, jsonEncode(cacheData));
      _cachedUserInfo = userInfo;
      LogUtil.i('LocationService.getUserAllInfo: 用户信息获取成功: IP=${userInfo['location']['ip'] ?? 'N/A'}, 位置=${_formatLocationString(userInfo['location'])}, 设备=${userInfo['deviceInfo']}, User-Agent=${userInfo['userAgent']}, 屏幕=${userInfo['screenSize']}');
      return userInfo;
    } catch (e, stackTrace) {
      LogUtil.logError('LocationService.getUserAllInfo: 获取用户信息失败: $e', e, stackTrace);
      return {'error': e.toString()};
    }
  }

  /// 修改：获取原生地理位置，使用geolocator强制LocationManager
  Future<Map<String, dynamic>> _getNativeLocationInfo() async {
    LogUtil.i('LocationService._getNativeLocationInfo: 开始获取原生位置');
    Map<String, dynamic>? ipInfo;
    
    try {
      ipInfo = await _fetchIPOnly();
      LogUtil.i('LocationService._getNativeLocationInfo: IP获取成功: ${ipInfo['ip']}');
    } catch (e) {
      LogUtil.e('LocationService._getNativeLocationInfo: IP获取失败: $e');
      ipInfo = {'ip': 'Unknown IP'};
    }

    try {
      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        LogUtil.i('LocationService._getNativeLocationInfo: 位置服务未启用，回退到API');
        return _fetchLocationInfo();
      }

      // 检查和请求权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          LogUtil.i('LocationService._getNativeLocationInfo: 位置权限被拒绝，回退到API');
          return _fetchLocationInfo();
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        LogUtil.i('LocationService._getNativeLocationInfo: 位置权限永久拒绝，回退到API');
        return _fetchLocationInfo();
      }

      return await _tryMultipleLocationApproaches(ipInfo);
      
    } catch (e, stackTrace) {
      LogUtil.logError('LocationService._getNativeLocationInfo: 原生位置获取失败: $e', e, stackTrace);
      return _fetchLocationInfo();
    }
  }

  /// 修改：并发执行网络定位和平衡定位
  Future<Map<String, dynamic>> _tryMultipleLocationApproaches(
      Map<String, dynamic> ipInfo) async {
    LogUtil.i('LocationService._tryMultipleLocationApproaches: 开始并发定位策略');
    
    // 同时发起网络定位和平衡定位，统一3秒超时
    final futures = [
      _tryLocationMethod(LocationAccuracy.low, '网络定位').timeout(
        Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('网络定位3秒超时'),
      ),
      _tryLocationMethod(LocationAccuracy.medium, '平衡定位').timeout(
        Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('平衡定位3秒超时'),
      ),
    ];
    
    // 等待所有定位请求完成（包括失败的）
    final results = await Future.wait(
      futures.map((future) => future.catchError((error) => {'error': error})),
    );
    
    Map<String, dynamic>? networkResult;
    Map<String, dynamic>? balancedResult;
    
    // 分析结果
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      if (result is Map<String, dynamic> && !result.containsKey('error')) {
        if (i == 0) {
          networkResult = result;
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 网络定位成功');
        } else {
          balancedResult = result;
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 平衡定位成功');
        }
      } else {
        if (i == 0) {
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 网络定位失败');
        } else {
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 平衡定位失败');
        }
      }
    }
    
    // 决策逻辑：优先使用平衡定位，其次网络定位
    Map<String, dynamic>? chosenResult;
    if (balancedResult != null) {
      chosenResult = balancedResult;
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 选择平衡定位结果');
    } else if (networkResult != null) {
      chosenResult = networkResult;
      LogUtil.i('LocationService._tryMultipleLocationApproaches: 选择网络定位结果');
    }
    
    // 如果有可用的定位结果，尝试地理编码
    if (chosenResult != null) {
      try {
        final locationResult = await _processLocationResult(
          chosenResult['position'], 
          ipInfo, 
          chosenResult['method']
        );
        
        // 检查地理编码是否成功
        if (locationResult['city'] != 'Unknown City' || 
            locationResult['region'] != 'Unknown Region' || 
            locationResult['country'] != 'Unknown Country') {
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 地理编码成功');
          return locationResult;
        } else {
          LogUtil.i('LocationService._tryMultipleLocationApproaches: 地理编码失败，回退到API');
        }
      } catch (e) {
        LogUtil.i('LocationService._tryMultipleLocationApproaches: 地理编码异常: $e，回退到API');
      }
    }
    
    LogUtil.i('LocationService._tryMultipleLocationApproaches: 所有原生定位失败，回退到API定位');
    return _fetchLocationInfo();
  }

  /// 修改：尝试单一定位方式，使用geolocator
  Future<Map<String, dynamic>> _tryLocationMethod(
      LocationAccuracy accuracy,
      String methodName) async {
    LogUtil.i('LocationService._tryLocationMethod: 尝试$methodName');
    try {
      // 关键：根据平台创建LocationSettings，强制使用Android LocationManager
      late LocationSettings locationSettings;
      
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: accuracy,
          distanceFilter: 10,
          // 强制使用LocationManager，不使用Google Play Services
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
      
      LogUtil.i('LocationService._tryLocationMethod: $methodName 成功: 经度=${position.longitude}, 纬度=${position.latitude}');
      return {
        'position': position,
        'method': methodName,
      };
      
    } catch (e) {
      LogUtil.i('LocationService._tryLocationMethod: $methodName 失败: $e');
      rethrow;
    }
  }

  /// 修改：处理定位结果并进行地理编码，增加Nominatim作为中间fallback
  Future<Map<String, dynamic>> _processLocationResult(
      Position position, 
      Map<String, dynamic> ipInfo, 
      String methodName) async {
    LogUtil.i('LocationService._processLocationResult: 开始地理编码，方法: $methodName');
    
    // 方案1：尝试原生地理编码
    try {
      try {
        await setLocaleIdentifier('zh_CN');
      } catch (e) {
        LogUtil.e('LocationService._processLocationResult: 设置地理编码区域失败: $e');
      }
      
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude
      ).timeout(
        Duration(seconds: 2), // 地理编码也缩短超时时间
        onTimeout: () => throw TimeoutException('地理编码2秒超时'),
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        LogUtil.i('LocationService._processLocationResult: $methodName 原生地理编码成功: ${place.locality}, ${place.administrativeArea}, ${place.country}');
        return {
          'ip': ipInfo['ip'] ?? 'Unknown IP',
          'country': place.country ?? 'Unknown Country',
          'region': place.administrativeArea ?? 'Unknown Region',
          'city': place.locality ?? 'Unknown City',
          'source': 'native-$methodName',
        };
      }
    } catch (e) {
      LogUtil.e('LocationService._processLocationResult: 原生地理编码失败: $e');
    }
    
    // 方案2：尝试Nominatim免费地理编码服务
    try {
      LogUtil.i('LocationService._processLocationResult: 尝试Nominatim地理编码');
      final nominatimResult = await _tryNominatimGeocoding(position.latitude, position.longitude);
      
      if (nominatimResult != null) {
        LogUtil.i('LocationService._processLocationResult: $methodName Nominatim地理编码成功: ${nominatimResult['city']}, ${nominatimResult['region']}, ${nominatimResult['country']}');
        return {
          'ip': ipInfo['ip'] ?? 'Unknown IP',
          'country': nominatimResult['country'] ?? 'Unknown Country',
          'region': nominatimResult['region'] ?? 'Unknown Region',
          'city': nominatimResult['city'] ?? 'Unknown City',
          'source': 'nominatim-$methodName',
        };
      }
    } catch (e) {
      LogUtil.e('LocationService._processLocationResult: Nominatim地理编码失败: $e');
    }
    
    // 方案3：所有地理编码都失败，返回Unknown（让上层回退到API）
    LogUtil.i('LocationService._processLocationResult: $methodName 所有地理编码失败，使用坐标信息');
    return {
      'ip': ipInfo['ip'] ?? 'Unknown IP',
      'country': 'Unknown Country',
      'region': 'Unknown Region',
      'city': 'Unknown City',
      'source': 'native-partial',
    };
  }

  /// 新增：Nominatim地理编码实现
  Future<Map<String, dynamic>?> _tryNominatimGeocoding(double latitude, double longitude) async {
    try {
      final String url = 'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$latitude&lon=$longitude&addressdetails=1&accept-language=zh-CN,zh,en';
      
      final responseData = await HttpUtil().getRequest<String>(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          headers: {
            'User-Agent': '${Config.packagename}/${Config.version}', // Nominatim要求设置User-Agent
          },
        ),
      );
      
      if (responseData != null) {
        final data = jsonDecode(responseData);
        if (data['address'] != null) {
          final addr = data['address'];
          return {
            'country': addr['country'] ?? 'Unknown Country',
            'region': addr['state'] ?? addr['province'] ?? 'Unknown Region', 
            'city': addr['city'] ?? addr['town'] ?? addr['village'] ?? 'Unknown City',
          };
        }
      }
    } catch (e) {
      LogUtil.e('LocationService._tryNominatimGeocoding: $e');
    }
    return null;
  }

  /// 通过API获取IP信息
  Future<Map<String, dynamic>> _fetchIPOnly() async {
    LogUtil.i('LocationService._fetchIPOnly: 开始获取IP信息');
    try {
      final responseData = await HttpUtil().getRequest<String>(
        'https://myip.ipip.net/json',
        options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),
        cancelToken: CancelToken(),
      );
      
      if (responseData != null) {
        Map<String, dynamic>? parsedData = _parseJson(responseData);
        if (parsedData != null && parsedData['ret'] == 'ok' && 
            parsedData['data'] != null && parsedData['data']['ip'] != null) {
          LogUtil.i('LocationService._fetchIPOnly: IP获取成功: ${parsedData['data']['ip']}');
          return {'ip': parsedData['data']['ip']};
        }
      }
    } catch (e) {
      LogUtil.e('LocationService._fetchIPOnly: IP获取失败: $e');
    }
    
    LogUtil.i('LocationService._fetchIPOnly: 返回默认IP');
    return {'ip': 'Unknown IP'};
  }

  /// 通过多个API顺序请求位置信息
  Future<Map<String, dynamic>> _fetchLocationInfo() async {
    LogUtil.i('LocationService._fetchLocationInfo: 开始API位置请求');
    for (var api in _apiList) {
      final cancelToken = CancelToken();
      
      try {
        LogUtil.i('LocationService._fetchLocationInfo: 请求API: ${api['url']}');
        final responseData = await HttpUtil().getRequest<String>(
          api['url'] as String,
          options: Options(receiveTimeout: const Duration(seconds: REQUEST_TIMEOUT_SECONDS)),
          cancelToken: cancelToken,
        );
        
        if (responseData != null) {
          Map<String, dynamic>? parsedData = _parseJson(responseData);
          if (parsedData != null) {
            final result = (api['parseData'] as dynamic Function(dynamic))(parsedData);
            if (result != null) {
              LogUtil.i('LocationService._fetchLocationInfo: API ${api['url']} 获取成功: ${result['city']}, ${result['region']}, ${result['country']}');
              return result;
            }
          }
        }
        
        LogUtil.i('LocationService._fetchLocationInfo: API ${api['url']} 数据无效，尝试下一个');
      } catch (e, stackTrace) {
        LogUtil.logError('LocationService._fetchLocationInfo: API ${api['url']} 请求失败: $e', e, stackTrace);
      } finally {
        if (!cancelToken.isCancelled) {
          cancelToken.cancel('请求结束');
          LogUtil.i('LocationService._fetchLocationInfo: 清理API ${api['url']} CancelToken');
        }
      }
    }

    LogUtil.e('LocationService._fetchLocationInfo: 所有API请求失败，返回默认值');
    return {
      'ip': 'Unknown IP', 
      'country': 'Unknown', 
      'region': 'Unknown', 
      'city': 'Unknown',
      'source': 'default',
    };
  }

  /// 获取设备信息和User-Agent
  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    LogUtil.i('LocationService._fetchDeviceInfo: 开始获取设备信息');
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
      
      LogUtil.i('LocationService._fetchDeviceInfo: 设备信息获取成功: $deviceInfo, User-Agent: $userAgent');
      return {'device': deviceInfo, 'userAgent': userAgent};
    } catch (e, stackTrace) {
      LogUtil.logError('LocationService._fetchDeviceInfo: 设备信息获取失败: $e', e, stackTrace);
      return {
        'device': 'Unknown Device',
        'userAgent': '${Config.packagename}/${Config.version} (Unknown Platform)'
      };
    }
  }

  /// 获取屏幕尺寸
  String _fetchScreenSize(BuildContext context) {
    LogUtil.i('LocationService._fetchScreenSize: 开始获取屏幕尺寸');
    try {
      final size = MediaQuery.of(context).size;
      final screenSize = '${size.width.toInt()}x${size.height.toInt()}';
      LogUtil.i('LocationService._fetchScreenSize: 屏幕尺寸获取成功: $screenSize');
      return screenSize;
    } catch (e) {
      LogUtil.e('LocationService._fetchScreenSize: 屏幕尺寸获取失败: $e');
      return 'Default Size (720x1280)';
    }
  }

  /// 从缓存获取指定键值
  T? _getCachedValue<T>(String key) {
    if (_cachedUserInfo != null && _cachedUserInfo!.containsKey(key)) {
      final value = _cachedUserInfo![key];
      if (value is T) {
        LogUtil.i('LocationService._getCachedValue: 获取缓存值: $key=$value');
        return value;
      }
    }
    LogUtil.i('LocationService._getCachedValue: 未找到缓存值: $key');
    return null;
  }

  /// 获取格式化位置信息字符串
  String getLocationString() {
    LogUtil.i('LocationService.getLocationString: 获取格式化位置信息');
    final loc = _getCachedValue<Map<String, dynamic>>('location');
    if (loc != null) {
      final locationString = 'IP: ${loc['ip'] ?? 'Unknown IP'}\n'
          '国家: ${loc['country'] ?? 'Unknown'}\n'
          '地区: ${loc['region'] ?? 'Unknown'}\n'
          '城市: ${loc['city'] ?? 'Unknown'}';
      LogUtil.i('LocationService.getLocationString: 位置信息: $locationString');
      return locationString;
    }
    LogUtil.i('LocationService.getLocationString: 无位置信息');
    return '暂无位置信息';
  }

  /// 获取设备信息
  String getDeviceInfo() {
    final deviceInfo = _getCachedValue<String>('deviceInfo') ?? 'Unknown Device';
    LogUtil.i('LocationService.getDeviceInfo: 设备信息: $deviceInfo');
    return deviceInfo;
  }

  /// 获取User-Agent  
  String getUserAgent() {
    final userAgent = _getCachedValue<String>('userAgent') ?? '${Config.packagename}/${Config.version} (Unknown Platform)';
    LogUtil.i('LocationService.getUserAgent: User-Agent: $userAgent');
    return userAgent;
  }

  /// 获取屏幕尺寸
  String getScreenSize() {
    final screenSize = _getCachedValue<String>('screenSize') ?? 'Unknown Size';
    LogUtil.i('LocationService.getScreenSize: 屏幕尺寸: $screenSize');
    return screenSize;
  }
}
