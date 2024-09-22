import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'log_util.dart'; 

class TrafficAnalytics {
  final String umamiUrl = 'https://umami.yourdomain.com/api/collect';
  final String websiteId = 'your-website-id';
  final int maxRetries = 3;

  /// 获取用户的IP地址和地理位置信息，逐个尝试多个API
  Future<Map<String, dynamic>> getUserIpAndLocation() async {
    // 定义要使用的API列表，按照优先级排列
    final apiList = [
      {
        'url': 'https://api.vvhan.com/api/ipInfo',
        'parseData': (data) {
          return {
            'ip': data['ip'] ?? 'Unknown IP',
            'country': data['info']['country'] ?? 'Unknown Country',
            'region': data['info']['prov'] ?? 'Unknown Region',
            'city': data['info']['city'] ?? 'Unknown City',
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
            'ip': data['data']['ip'] ?? 'Unknown IP',
            'country': data['data']['country'] ?? 'Unknown Country',
            'region': data['data']['province'] ?? 'Unknown Region',
            'city': data['data']['city'] ?? 'Unknown City',
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
            // 在这里增加了null检查，确保lat和lon解析失败时不会出错
            'lat': data.containsKey('lat') ? data['lat'] : null,
            'lon': data.containsKey('lon') ? data['lon'] : null,
          };
        }
      }
    ];

    for (var api in apiList) {
      try {
        // 发送请求到当前API
        final response = await http.get(Uri.parse(api['url']));
        if (response.statusCode == 200) {
          // 成功获取到数据，解析并返回
          final data = json.decode(response.body);
          return api['parseData'](data);
        } else {
          LogUtil.e('API请求失败: ${api['url']} 状态码: ${response.statusCode}');
        }
      } catch (e, stackTrace) {
        LogUtil.logError('请求 ${api['url']} 失败', e, stackTrace);
      }
    }

    // 如果所有API都失败，抛出异常
    throw Exception('所有API请求失败，无法获取IP和地理位置信息');
  }

  /// 获取屏幕尺寸
  String getScreenSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return '${size.width.toInt()}x${size.height.toInt()}';
  }

  /// 获取设备信息（操作系统类型）
  String getDeviceInfo() {
    return Platform.operatingSystem;
  }

  /// 发送页面访问统计数据到 Umami，带重试机制
  Future<void> sendPageView(BuildContext context, String url, String referrer) async {
    final String screenSize = getScreenSize(context);
    final String deviceInfo = getDeviceInfo();

    try {
      final Map<String, dynamic> ipData = await getUserIpAndLocation();

      // 构造要发送的统计数据
      final Map<String, dynamic> payload = {
        'type': 'pageview',
        'payload': {
          'website': websiteId,
          'url': url,
          'referrer': referrer,
          'hostname': 'your-app-domain.com',
          'language': 'en-US',
          'screen': screenSize,
          'ip': ipData['ip'],
          // 在地理位置信息中处理可能缺失的字段
          'location': '${ipData['city']}, ${ipData['region']}, ${ipData['country']}',
          // 确保当lat和lon为null时不会导致错误
          'coordinates': (ipData['lat'] != null && ipData['lon'] != null)
              ? '${ipData['lat']}, ${ipData['lon']}'
              : '',
          'device': deviceInfo,
        }
      };

      await _sendWithRetry(payload);

    } catch (error, stackTrace) {
      LogUtil.logError('获取用户 IP 或发送页面访问数据时发生错误', error, stackTrace);
    }
  }

  /// 带重试机制的发送方法
  Future<void> _sendWithRetry(Map<String, dynamic> payload) async {
    int attempt = 0;
    bool success = false;

    while (attempt < maxRetries && !success) {
      attempt++;
      try {
        final response = await http.post(
          Uri.parse(umamiUrl),
          headers: {'Content-Type': 'application/json'},
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
        await Future.delayed(Duration(seconds: 2));
      }
    }

    if (!success) {
      LogUtil.e('达到最大重试次数，发送失败');
    }
  }
}
