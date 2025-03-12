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

  /// 发送页面访问统计数据到Umami
  Future<void> sendPageView(BuildContext context, String referrer, {String? additionalPath}) async {
    try {
      // 从本地缓存读取用户数据
      String? cachedData = SpUtil.getString('user_all_info');
      Map<String, dynamic> userInfo = {}; // 用于存储解析后的用户信息

      // 解析缓存数据流程
      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          // 尝试解码JSON数据
          Map<String, dynamic> parsedData = jsonDecode(cachedData);
          if (parsedData['info'] is Map<String, dynamic>) {
            // 验证数据结构有效性
            userInfo = parsedData['info'] as Map<String, dynamic>;
          } else {
            // 数据结构异常处理
            LogUtil.e('缓存数据中 "info" 字段格式不正确');
          }
        } catch (e) {
          // JSON解析失败处理
          LogUtil.e('解析缓存用户信息失败: $e');
        }
      } else {
        // 无缓存数据时的处理
        LogUtil.i('未找到用户信息缓存，使用默认值');
      }

      // 从缓存数据提取字段，保持与LocationService默认值一致
      String screenSize = userInfo['screenSize'] ?? 'Unknown Size'; // 屏幕尺寸默认值
      String deviceInfo = userInfo['deviceInfo'] ?? 'Unknown Device'; // 设备信息默认值
      String userAgent = userInfo['userAgent'] ?? '${Config.packagename}/${Config.version} (Unknown Platform)'; // UA默认值
      
      // 位置信息处理（兼容无效数据场景）
      Map<String, dynamic> locationData = {};
      if (userInfo['location'] != null && userInfo['location'] is Map<String, dynamic>) {
        locationData = userInfo['location'] as Map<String, dynamic>;
      } else {
        // 位置数据无效时的默认配置
        locationData = {
          'ip': 'Unknown IP',
          'city': 'Unknown City',
          'region': 'Unknown Region',
          'country': 'Unknown Country',
        };
      }
      // 构建地理位置字符串
      String locationString = '${locationData['city']}, ${locationData['region']}, ${locationData['country']}';

      // 构造当前页面URL
      String url = ModalRoute.of(context)?.settings.name ?? '';
      if (additionalPath != null && additionalPath.isNotEmpty) {
        url += "/$additionalPath"; // 拼接附加路径参数
      }

      // 获取当前语言配置
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final currentLanguage = languageProvider.currentLocale?.languageCode ?? 'en'; // 默认英语

      // 构建上报数据主体
      final Map<String, dynamic> payload = {
        'payload': {
          'type': 'event',
          'website': websiteId,
          'url': url,
          'referrer': referrer,
          'hostname': hostname,
          'language': currentLanguage,
          'screen': screenSize,
          'ip': locationData['ip'],
          'location': locationString,
          'device': deviceInfo,
          'data': {
            'device_info': deviceInfo,
            'screen_size': screenSize,
            'ip': locationData['ip'],
            'location': locationString,
            'lat': locationData['lat'], // 纬度（可能为空）
            'lon': locationData['lon'], // 经度（可能为空）
          }
        },
        'type': 'event',
      };

      // 发送HTTP请求
      final response = await HttpUtil().postRequest<String>(
        umamiUrl,
        data: jsonEncode(payload), // 数据序列化为JSON
        options: Options(
          receiveTimeout: const Duration(seconds: 10), // 设置10秒接收超时
        ),
        cancelToken: CancelToken(),
      );

      // 处理响应结果
      if (response != null) {
        LogUtil.i('页面访问统计数据发送成功'); // 成功日志记录
      } else {
        LogUtil.e('发送页面访问统计数据失败，响应为空'); // 空响应错误处理
      }
    } catch (error, stackTrace) {
      // 全局异常捕获
      LogUtil.logError('发送页面访问数据时发生错误', error, stackTrace);
    }
  }
}
