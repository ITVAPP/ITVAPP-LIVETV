import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

class TrafficAnalytics {
  final String hostname = Config.hostname;
  final String umamiUrl = 'https://ws.itvapp.net/api/send';
  final String websiteId = '22de1c29-4f0c-46cf-be13-e13ef6929cac';

  // 定义默认位置数据的常量，避免重复赋值
  static const Map<String, String> _defaultLocationData = {
    'ip': 'Unknown IP',
    'city': 'Unknown City',
    'region': 'Unknown Region',
    'country': 'Unknown Country',
  };

  /// 发送页面访问统计数据到Umami
  Future<void> sendPageView(BuildContext context, {String? referrer, String? additionalPath}) async { // 修改：将 referrer 改为可选参数
    try {
      // 从缓存解析用户信息
      String? cachedData = SpUtil.getString('user_all_info');
      Map<String, dynamic> userInfo = {}; // 用于存储解析后的用户信息

      // 解析缓存中的用户信息
      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          // 解码JSON数据
          Map<String, dynamic> parsedData = jsonDecode(cachedData);
          if (parsedData['info'] is Map<String, dynamic>) {
            // 验证并提取用户信息
            userInfo = parsedData['info'] as Map<String, dynamic>;
          } else {
            // 记录数据结构异常
            LogUtil.e('用户信息格式错误');
          }
        } catch (e) {
          // 记录解析失败
          LogUtil.e('用户信息解析失败: $e');
        }
      } else {
        // 记录无缓存数据
        LogUtil.i('无用户信息缓存，使用默认值');
      }

      // 提取屏幕尺寸、设备信息和用户代理
      String screenSize = userInfo['screenSize'] ?? 'Unknown Size'; // 屏幕尺寸默认值
      String deviceInfo = userInfo['deviceInfo'] ?? 'Unknown Device'; // 设备信息默认值
      String userAgent = userInfo['userAgent'] ?? '${Config.packagename}/${Config.version} (Unknown Platform)'; // UA默认值
      
      // 构建位置信息
      Map<String, dynamic> locationData;
      if (userInfo['location'] != null && userInfo['location'] is Map<String, dynamic>) {
        // 合并默认值和实际位置数据
        locationData = {..._defaultLocationData, ...userInfo['location']};
      } else {
        locationData = _defaultLocationData;
      }
      // 构造地理位置字符串
      String locationString = '${locationData['city']}, ${locationData['region']}, ${locationData['country']}';

      // 构造当前页面URL
      String url = ModalRoute.of(context)?.settings.name ?? '';
      if (additionalPath != null && additionalPath.isNotEmpty) {
        url += "/$additionalPath"; // 拼接附加路径参数
      }

      // 获取当前语言配置
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final currentLanguage = languageProvider.currentLocale?.languageCode ?? 'en'; // 默认英语

      // 设置默认referrer
      final String effectiveReferrer = referrer ?? 'livetv.itvapp.net';

      // 构建上报数据主体
      final Map<String, dynamic> payload = {
        'payload': {
          'type': 'event',
          'website': websiteId,
          'url': url,
          'referrer': effectiveReferrer, // 使用传入的 referrer 或默认值
          'hostname': hostname,
          'language': currentLanguage,
          'screen': screenSize,
          'ip': locationData['ip'],
          'userAgent': userAgent, 
          'country': locationData['country'], // 统一从 locationData 获取
          'region': locationData['region'],
          'city': locationData['city'],
          'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
          'data': {
            'device_info': deviceInfo, 
            'location': locationString, 
          }
        },
        'type': 'event',
      };

      // 发送HTTP请求
      final response = await _sendRequestWithRetry(
        umamiUrl,
        payload,
        retries: 2, // 最多重试2次
      );

      // 处理响应结果
      if (response != null) {
        LogUtil.i('页面访问统计发送成功');
      } else {
        LogUtil.e('页面访问统计发送失败，响应为空');
      }
    } catch (error, stackTrace) {
      // 记录全局异常
      LogUtil.logError('页面访问数据发送错误', error, stackTrace);
    }
  }

  /// 发送带重试机制的HTTP请求
  Future<String?> _sendRequestWithRetry(
    String url,
    Map<String, dynamic> payload, {
    required int retries,
  }) async {
    int attempt = 0;
    // 定义递增延迟
    final delays = [Duration.zero, Duration(milliseconds: 500), Duration(seconds: 1), Duration(seconds: 2)];
    
    while (attempt <= retries) {
      try {
        // 执行HTTP POST请求
        final response = await HttpUtil().postRequest<String>(
          url,
          data: jsonEncode(payload), // 数据序列化为JSON
          options: Options(
            receiveTimeout: const Duration(seconds: 10), // 设置10秒接收超时
          ),
          cancelToken: CancelToken(),
        );
        return response; // 成功则返回结果
      } catch (e) {
        attempt++;
        if (attempt > retries) {
          // 记录重试失败
          LogUtil.e('HTTP请求失败，达最大重试次数: $e');
          return null; // 达到最大重试次数，返回null
        }
        // 应用递增延迟
        await Future.delayed(delays[attempt]);
        // 记录重试尝试
        LogUtil.i('HTTP请求失败，第$attempt次重试');
      }
    }
    return null; // 默认返回null
  }
}
