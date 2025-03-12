import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/location_service.dart';

class TrafficAnalytics {
  final String hostname = Config.hostname;
  final String umamiUrl = 'https://ws.itvapp.net/api/send';
  final String websiteId = '22de1c29-4f0c-46cf-be13-e13ef6929cac';
  final LocationService _locationService = LocationService();

  /// 发送页面访问统计数据到Umami
  Future<void> sendPageView(BuildContext context, String referrer, {String? additionalPath}) async {
    try {
      // 直接从SpUtil获取信息
      String? screenSize = SpUtil.getString(LocationService.SP_KEY_SCREEN_SIZE);
      String? deviceInfo = SpUtil.getString(LocationService.SP_KEY_DEVICE_INFO);
      String? userAgent = SpUtil.getString(LocationService.SP_KEY_USER_AGENT);
      String? locationData = SpUtil.getString(LocationService.SP_KEY_LOCATION);
      
      // 如果本地存储中没有，则通过LocationService获取并保存
      if (screenSize == null || screenSize.isEmpty) {
        screenSize = _locationService.getScreenSize(context);
      }
      if (deviceInfo == null || deviceInfo.isEmpty) {
        deviceInfo = await _locationService.getDeviceInfo();
      }
      
      if (userAgent == null || userAgent.isEmpty) {
        userAgent = await _locationService.getDeviceInfo(userAgent: true);
      }
      // 解析位置信息
      Map<String, dynamic>? ipData;
      if (locationData != null && locationData.isNotEmpty) {
        try {
          Map<String, dynamic>? parsedData = jsonDecode(locationData);
          if (parsedData != null && parsedData['location'] != null) {
            ipData = parsedData['location'] as Map<String, dynamic>;
          }
        } catch (e) {
          LogUtil.e('解析位置信息失败: $e');}
      }
      // 如果本地没有位置信息或解析失败，则重新获取
      if (ipData == null) {
        ipData = await _locationService.getUserIpAndLocation();
      }
      final locationString = '${ipData['city'] ?? 'Unknown City'}, '
          '${ipData['region'] ?? 'Unknown Region'}, '
          '${ipData['country'] ?? 'Unknown Country'}';

      String url = ModalRoute.of(context)?.settings.name ?? '';
      if (additionalPath != null && additionalPath.isNotEmpty) {
        url += "/$additionalPath";
      }

      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final currentLanguage = languageProvider.currentLocale?.languageCode ?? 'en';

      final Map<String, dynamic> payload = {
        'payload': {
          'type': 'event',
          'website': websiteId,
          'url': url,
          'referrer': referrer,
          'hostname': hostname,
          'language': currentLanguage,
          'screen': screenSize,
          'ip': ipData['ip'],
          'location': locationString,
          'device': deviceInfo,
          'data': {
            'device_info': deviceInfo,
            'screen_size': screenSize,
            'ip': ipData['ip'],
            'location': locationString,
            'lat': ipData['lat'],
            'lon': ipData['lon'],}
        },
        'type': 'event',
      };

      final response = await HttpUtil().postRequest<String>(
        umamiUrl,
        data: jsonEncode(payload),
        options: Options(
          receiveTimeout: const Duration(seconds:10),
        ),
        cancelToken: CancelToken(),
      );

      if (response != null) {
        LogUtil.i('页面访问统计数据发送成功');
      } else {
        LogUtil.e('发送页面访问统计数据失败，响应为空');
      }
    } catch (error, stackTrace) {
      LogUtil.logError('发送页面访问数据时发生错误', error, stackTrace);
    }
  }
}
