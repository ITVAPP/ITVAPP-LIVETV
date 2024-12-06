import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart'; 
import 'package:provider/provider.dart'; 
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'log_util.dart';
import '../config.dart';

class TrafficAnalytics {
  final String hostname = Config.hostname;
  final String packagename = Config.packagename;  
  final String appversion = Config.version; 
  final String umamiUrl = 'https://ws.itvapp.net/api/send';
  final String websiteId = '22de1c29-4f0c-46cf-be13-e13ef6929cac';
  final int maxRetries = 3;

  // 用于缓存设备信息，避免重复获取
  String? _cachedDeviceInfo;
  
  // 用于缓存IP地址和地理位置信息，避免重复请求
  Map<String, dynamic>? _cachedIpData;

  // 新增: SP存储的key
  static const String SP_KEY_LOCATION = 'user_location_info';

  /// 获取用户的IP地址和地理位置信息，逐个尝试多个API
  Future<Map<String, dynamic>> getUserIpAndLocation() async {
    if (_cachedIpData != null) {
      return _cachedIpData!;  // 如果缓存存在，直接返回缓存的数据
    }

    // 新增: 尝试从SP中读取保存的数据
    String? savedLocation = SpUtil.getString(SP_KEY_LOCATION);
    if (savedLocation != null && savedLocation.isNotEmpty) {
      try {
        _cachedIpData = json.decode(savedLocation);
        return _cachedIpData!;
      } catch (e) {
        LogUtil.e('解析保存的位置信息失败: $e');
      }
    }

    final apiList = [
      {
        'url': 'https://api.vvhan.com/api/ipInfo',
        'parseData': (data) {
          return {
            'ip': data['ip'] ?? 'Unknown IP',
            'country': data['info']?['country'] ?? 'Unknown Country',  // 加强 null 检查
            'region': data['info']?['prov'] ?? 'Unknown Region',
            'city': data['info']?['city'] ?? 'Unknown City',
          };
        }
      },
      {
        'url': 'https://ip.useragentinfo.com/json',
        'parseData': (data) {
          return {
            'ip': data['ip'] ?? 'Unknown IP',
            'country': data['country'] ?? 'Unknown Country',
            'region': data['province'] ?? 'Unknown Region',
            'city': data['city'] ?? 'Unknown City',
          };
        }
      },
      {
        'url': 'https://open.saintic.com/ip/rest',
        'parseData': (data) {
          return {
            'ip': data['data']?['ip'] ?? 'Unknown IP',
            'country': data['data']?['country'] ?? 'Unknown Country',
            'region': data['data']?['province'] ?? 'Unknown Region',
            'city': data['data']?['city'] ?? 'Unknown City',
          };
        }
      },
      {
        'url': 'http://ip-api.com/json',
        'parseData': (data) {
          return {
            'ip': data['query'] ?? 'Unknown IP',
            'country': data['country'] ?? 'Unknown Country',
            'region': data['regionName'] ?? 'Unknown Region',
            'city': data['city'] ?? 'Unknown City',
            'lat': data['lat'] ?? null,  // null 检查
            'lon': data['lon'] ?? null,
          };
        }
      }
    ];

    for (var api in apiList) {
      try {
        // 设置超时限制，防止请求卡住
        final response = await http.get(Uri.parse(api['url'] as String)).timeout(Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          _cachedIpData = (api['parseData'] as dynamic Function(dynamic))(data);
          
          // 新增: 保存到SP中
          try {
            await SpUtil.putString(SP_KEY_LOCATION, json.encode(_cachedIpData));
          } catch (e) {
            LogUtil.e('保存位置信息失败: $e');
          }
          
          return _cachedIpData!;
        } else {
          LogUtil.e('API请求失败: ${api['url']} 状态码: ${response.statusCode}');
        }
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败', e, stackTrace);
      }
    }

    throw Exception('所有API请求失败，无法获取IP和地理位置信息');
  }

  /// 新增: 获取保存的位置信息的字符串形式
  String getLocationString() {
    String? savedLocation = SpUtil.getString(SP_KEY_LOCATION);
    if (savedLocation != null && savedLocation.isNotEmpty) {
      try {
        Map<String, dynamic> locationData = json.decode(savedLocation);
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

  /// 获取设备信息（详细的设备型号、系统版本等）
  Future<String> getDeviceInfo() async {
    if (_cachedDeviceInfo != null) {
      return _cachedDeviceInfo!;  // 如果缓存不为空，直接返回
    }

    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
      _cachedDeviceInfo = '${androidInfo.model} (${androidInfo.version.release})';
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
      _cachedDeviceInfo = '${iosInfo.utsname.machine} (${iosInfo.systemVersion})';
    } else {
      _cachedDeviceInfo = Platform.operatingSystem;
    }
    return _cachedDeviceInfo!;
  }

  /// 发送页面访问统计数据到 Umami，带重试机制
  Future<void> sendPageView(BuildContext context, String referrer, {String? additionalPath}) async {
    final String screenSize = getScreenSize(context);
    final String deviceInfo = await getDeviceInfo();  // 使用 getDeviceInfo 方法

    // 获取当前页面的路由名作为 URL
    String url = ModalRoute.of(context)?.settings.name ?? '';

    // 如果有 additionalPath，则将其追加到 URL 中
    if (additionalPath != null && additionalPath.isNotEmpty) {
      url += "/$additionalPath";
    }

    // 动态生成 User-Agent，包含应用版本信息和应用名称
    String userAgent;
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      userAgent = '$packagename/$appversion (Android; ${androidInfo.version.release})';  
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await DeviceInfoPlugin().iosInfo;
      userAgent = '$packagename/$appversion (iOS; ${iosInfo.systemVersion})'; 
    } else {
      userAgent = '$packagename/$appversion (Unknown Platform)'; 
    }

    // 获取当前语言设置
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final currentLanguage = languageProvider.currentLocale?.languageCode ?? 'en';  // 使用当前设置的语言

    try {
      final Map<String, dynamic> ipData = await getUserIpAndLocation();

      // 构造要发送的统计数据
      final Map<String, dynamic> payload = {
        'payload': {  // 调整为嵌套结构
          'type': 'event',
          'website': websiteId,
          'url': url,  // 当前页面 URL
          'referrer': referrer,  // 来源位置
          'hostname': hostname,  // 使用 Config 中的 hostname
          'language': currentLanguage, 
          'screen': screenSize,
          'ip': ipData['ip'],
          'location': '${ipData['city']}, ${ipData['region']}, ${ipData['country']}',
          'device': deviceInfo,
          'data': {
            'device_info': deviceInfo,
            'screen_size': screenSize,
            'ip': ipData['ip'],
            'location': '${ipData['city']}, ${ipData['region']}, ${ipData['country']}',
            'lat': ipData['lat'],
            'lon': ipData['lon'],
          }
        },
        'type': 'event',
      };

      // 发送请求时设置 User-Agent
      await _sendWithRetry(payload, userAgent);

    } catch (error, stackTrace) {
      LogUtil.logError('获取用户 IP 或发送页面访问数据时发生错误', error, stackTrace);
    }
  }

  /// 带重试机制的发送方法，使用指数退避策略进行优化
  Future<void> _sendWithRetry(Map<String, dynamic> payload, String userAgent) async {
    int attempt = 0;
    bool success = false;
    int delayInSeconds = 2;  // 初始重试延迟

    while (attempt < maxRetries && !success) {
      attempt++;
      try {
        final response = await http.post(
          Uri.parse(umamiUrl),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': userAgent,
          },
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          LogUtil.i('页面访问统计数据发送成功');
          success = true;
        } else {
          LogUtil.e('页面访问统计数据发送失败: ${response.statusCode}');
        }
      } catch (error, stackTrace) {
        LogUtil.logError('发送数据时发生错误，正在进行第 $attempt 次重试', error, stackTrace);
      }

      if (!success && attempt < maxRetries) {
        await Future.delayed(Duration(seconds: delayInSeconds));
        delayInSeconds *= 2;  // 指数级增加延迟时间
      }
    }

    if (!success) {
      LogUtil.e('达到最大重试次数，发送失败');
    }
  }
}
