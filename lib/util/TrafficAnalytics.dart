import 'dart:convert';
import 'dart:io'; // 导入 dart:io 来获取设备操作系统信息
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

/**
 * 使用说明：
 * 1. 初始化 TrafficAnalytics 类
 *    在页面中实例化 TrafficAnalytics 类，用于调用统计功能。
 *
 *    示例：
 *    final TrafficAnalytics trafficAnalytics = TrafficAnalytics();
 *
 * 2. 调用 sendPageView 方法记录页面访问
 *    在页面加载时，调用 sendPageView 方法将页面的访问数据发送到 Umami 进行统计。
 *    需要传入 BuildContext、页面的 url 和 referrer（引荐来源）。
 *
 *    示例：
 *    trafficAnalytics.sendPageView(context, 'https://your-app-domain.com/home', 'https://referrer.com');
 *
 * 3. IP 和位置信息自动获取
 *    TrafficAnalytics 类会自动获取用户的 IP 地址和地理位置信息，并将这些信息与页面的 URL 一起发送到 Umami。
 *
 * 4. 屏幕尺寸自动获取
 *    TrafficAnalytics 类会根据设备的 MediaQuery 自动获取当前屏幕的宽高，并发送到 Umami 进行记录。
 */

class TrafficAnalytics {
  // Umami API 端点
  final String umamiUrl = 'https://umami.yourdomain.com/api/collect'; 
  // 从 Umami 控制台获取的 websiteId
  final String websiteId = 'your-website-id'; 
  // 最大重试次数
  final int maxRetries = 3;

  /// 获取用户的IP地址和地理位置信息
  Future<Map<String, dynamic>> getUserIpAndLocation() async {
    // 发送请求获取用户IP和地理信息
    final response = await http.get(Uri.parse('http://ip-api.com/json'));
    
    if (response.statusCode == 200) {
      // 成功获取到数据，返回解析后的数据
      final data = json.decode(response.body);
      return {
        'ip': data['query'],
        'country': data['country'],
        'region': data['regionName'],
        'city': data['city'],
        'lat': data['lat'],
        'lon': data['lon'],
      };
    } else {
      // 请求失败，抛出异常
      throw Exception('获取 IP 和地理位置信息失败');
    }
  }

  /// 获取屏幕尺寸
  String getScreenSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 返回屏幕宽高字符串
    return '${size.width.toInt()}x${size.height.toInt()}';
  }

  /// 获取设备信息（操作系统类型）
  String getDeviceInfo() {
    return Platform.operatingSystem;  // 返回当前操作系统 (Android, iOS, etc.)
  }

  /// 发送页面访问统计数据到 Umami，带重试机制
  Future<void> sendPageView(BuildContext context, String url, String referrer) async {
    final String screenSize = getScreenSize(context); // 获取屏幕尺寸
    final String deviceInfo = getDeviceInfo(); // 获取设备信息

    try {
      final Map<String, dynamic> ipData = await getUserIpAndLocation(); // 获取IP和地理位置

      // 构造要发送的统计数据
      final Map<String, dynamic> payload = {
        'type': 'pageview',
        'payload': {
          'website': websiteId,
          'url': url,
          'referrer': referrer,
          'hostname': 'your-app-domain.com',
          'language': 'en-US',  // 语言可以根据实际情况调整
          'screen': screenSize,  // 屏幕尺寸
          'ip': ipData['ip'],  // 用户IP
          'location': '${ipData['city']}, ${ipData['region']}, ${ipData['country']}',  // 用户地理位置信息
          'coordinates': '${ipData['lat']}, ${ipData['lon']}',  // 经纬度
          'device': deviceInfo,  // 设备信息
        }
      };

      await _sendWithRetry(payload); // 调用重试机制发送数据

    } catch (error) {
      print('获取用户 IP 或发送页面访问数据时发生错误: $error');  // 打印错误信息
    }
  }

  /// 带重试机制的发送方法
  Future<void> _sendWithRetry(Map<String, dynamic> payload) async {
    int attempt = 0;
    bool success = false;

    while (attempt < maxRetries && !success) {
      attempt++;
      try {
        // 发送POST请求到 Umami
        final response = await http.post(
          Uri.parse(umamiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );

        // 判断请求是否成功
        if (response.statusCode == 200) {
          print('页面访问统计数据发送成功');  // 打印成功信息
          success = true;  // 成功后跳出循环
        } else {
          print('页面访问统计数据发送失败: ${response.statusCode}');  // 打印失败状态码
        }
      } catch (error) {
        print('发送数据时发生错误，正在进行第 $attempt 次重试: $error');  // 打印错误并重试
      }

      // 如果发送失败且未达到最大重试次数，等待一段时间再尝试
      if (!success && attempt < maxRetries) {
        await Future.delayed(Duration(seconds: 2));
      }
    }

    if (!success) {
      print('达到最大重试次数，发送失败');
    }
  }
}
