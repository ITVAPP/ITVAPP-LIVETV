import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 四川电视台解析器
class SichuanParser {
  // 频道列表映射表，键为 clickIndex，值为 [频道ID, 频道名称]
  static const Map<int, List<String>> _channelList = {
    0: ['sctv1', '四川卫视'],
    1: ['sctv2', '四川经济'],
    2: ['sctv3', '四川文化旅游'],
    3: ['sctv4', '四川新闻'],
    4: ['sctv5', '四川影视文艺'],
    5: ['sctv6', '四川星空购物'],
    6: ['sctv7', '四川妇女儿童'],
    7: ['sctv9', '四川乡村'],
    8: ['kangba', '康巴卫视'],
  };

  static const String _baseUrl = 'https://gw.scgchc.com';
  static const String _playBaseUrl = 'https://tvshow.scgchc.com';
  static const String _authToken =
      'bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOlsiU0VSVklDRV9TQ0dDLURFTU8iXSwidXNlcl9pZCI6MTgyNTk5MDQyODI0NDE4MDk5NCwic2NvcGUiOlsiYWxsIl0sImV4cCI6MTc0NDcwMTkwOSwiYXV0aG9yaXRpZXMiOlsiUk9MRV9BUFBfQ0xJRU5UX1VTRVIiXSwianRpIjoiYWY4Y2U3ZGEtYjEwZC00NWZlLWI4OGEtYmQwMTk3MTVjMmJmIiwiY2xpZW50X2lkIjoiU0VSVklDRV9TQ0dDLUFQUCJ9.R_BmQLsMbcwOZLCBmUWVOx1IF4vg5LaQeYV6KtneiXO-boarYD5BZDmgK3vqBPDutcwLcvyDdYmBpw5iCE1Ea0pAsC2mAFTDwoeUdjcZypuvJbXLwiWccbvCGxTyf6t2T9YraTxf7XJl0jhtUPweLLk3ogQnINyWqRJ1aNYdZKDJ6a15OXk9GkHyzfF5xmGF0y8pjLvzSCHhUD6UcFkQaXttOXoklfdpzAXgdzlm_MuQMsOk8TL1rVBEX3UQoBeqkZUBOTO_FmvhI6nqWTdR6hV2gAce4fKAoiWtTnp9ThxeroXfUV3zqc_Q7vx_AQGjPp-ISwFao2XpmNxzuJ00lw';

  /// 解析四川电视台直播流地址
  static Future<String> parse(String url) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 获取频道信息
      final channelInfo = _channelList[clickIndex] ?? _channelList[0]; // 超出范围使用第一个频道
      if (channelInfo == null) {
        LogUtil.i('无效的 clickIndex: $clickIndex');
        return 'ERROR';
      }

      final channelId = channelInfo[0];
      final channelName = channelInfo[1];
      LogUtil.i('选择的频道: $channelName (ID: $channelId, clickIndex: $clickIndex)');

      // 获取 m3u8 播放地址
      final m3u8Url = await _getM3u8Url(channelId);
      if (m3u8Url.isEmpty) {
        LogUtil.i('获取 m3u8 地址失败');
        return 'ERROR';
      }

      final trimmedM3u8Url = m3u8Url.trim();
      LogUtil.i('修剪后的 m3u8Url: "$trimmedM3u8Url"');

      // 验证地址
      if (trimmedM3u8Url.isEmpty || !trimmedM3u8Url.contains('.m3u8')) {
        LogUtil.i('地址不包含 m3u8: $trimmedM3u8Url');
        return 'ERROR';
      }

      LogUtil.i('成功获取 m3u8 播放地址: $trimmedM3u8Url');
      return trimmedM3u8Url;
    } catch (e) {
      LogUtil.i('解析四川电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取 m3u8 播放地址
  static Future<String> _getM3u8Url(String channelId) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final streamName = Uri.encodeComponent('/hdlive/$channelId' '8f9fb5888dedbe0c6a1b/1.m3u8');
      final apiUrl = '$_baseUrl/app/v1/anti/getLiveSecret?streamName=$streamName&txTime=$timestamp';

      // 构建请求头
      final headers = {
        'Authorization': _authToken,
        'Referer': 'https://www.sctv.com/',
        'User-Agent': 'AppleCoreMedia/1.0.0.15F79 (iPhone; U; CPU OS 11_4 like Mac OS X; zh_cn)',
      };

      LogUtil.i('发送请求: $apiUrl');
      LogUtil.i('请求头: $headers');

      // 发送请求
      final response = await HttpUtil().getRequest<String>(
        apiUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

      if (response == null) {
        LogUtil.i('API 响应为空');
        return '';
      }

      LogUtil.i('API 响应内容: $response');

      // 解析响应
      final responseData = json.decode(response);
      final secret = responseData['data']?['secret'] as String?;

      if (secret == null || secret.isEmpty) {
        LogUtil.i('无法获取 secret');
        return '';
      }

      // 构造 m3u8 地址
      final m3u8Url = '$_playBaseUrl/hdlive/$channelId' '8f9fb5888dedbe0c6a1b/1.m3u8?$secret';
      LogUtil.i('构造的 m3u8 地址: $m3u8Url');

      return m3u8Url;
    } catch (e) {
      LogUtil.i('获取 m3u8 地址失败: $e');
      return '';
    }
  }
}
