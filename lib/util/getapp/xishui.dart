import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 习水电视台解析器
class xishuiParser {
  // 频道列表映射表，键为 clickIndex，值为 [频道ID, 频道名称, 流地址]
  static const Map<int, List<String>> _channelList = {
    0: ['tv', '习水综合频道', 'https://ali-live.xishuirm.cn/live/app3.m3u8'],
    1: ['radios', '习水综合广播', 'https://ali-live.xishuirm.cn/live/app1.m3u8'],
  };

  static const String _baseUrl = 'https://api-cms.xishuirm.cn';
  static const String _authToken = 'a6e34f9a9cddd2714021a4bac0ac0fd2';

  /// 解析习水电视台直播流地址
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
      final m3u8Url = await _getM3u8Url(channelInfo);
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
      LogUtil.i('解析习水电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取 m3u8 播放地址
  static Future<String> _getM3u8Url(List<String> channelInfo) async {
    try {
      final channelId = channelInfo[0];
      final streamUrl = channelInfo[2];
      final encodedStreamUrl = Uri.encodeComponent(streamUrl);
      final apiUrl = '$_baseUrl/v1/mobile/channel/play_auth?stream=$encodedStreamUrl';

      // 构建请求头
      final headers = {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'zh-CN,zh-TW;q=0.9,zh;q=0.8',
        'Authorization': _authToken,
        'Connection': 'keep-alive',
        'DNT': '1',
        'Host': 'api-cms.xishuirm.cn',
        'Origin': 'https://www.xishuirm.cn',
        'Referer': 'https://www.xishuirm.cn/',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-site',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 OPR/117.0.0.0',
        'X-Requested-With': 'XMLHttpRequest',
        'sec-ch-ua': '"Not A(Brand";v="8", "Chromium";v="132", "Opera";v="117"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
      };

      LogUtil.i('发送请求: $apiUrl ，请求头: $headers');

      // 发送请求
      final response = await HttpUtil().getRequest<String>(
        apiUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
          responseType: ResponseType.plain, // 确保返回纯文本以处理 GZIP
        ),
      );

      if (response == null) {
        LogUtil.i('API 响应为空');
        return '';
      }

      LogUtil.i('API 响应内容: $response');

      // 解析响应
      final responseData = json.decode(response);
      if (responseData['code'] != 100000 || responseData['data']?['auth_key'] == null) {
        LogUtil.i('无法获取 auth_key，响应: $response');
        return '';
      }

      final authKey = responseData['data']['auth_key'] as String;

      // 构造 m3u8 地址
      final m3u8Url = '$streamUrl?auth_key=$authKey';
      LogUtil.i('构造的 m3u8 地址: $m3u8Url');

      return m3u8Url;
    } catch (e) {
      LogUtil.i('获取 m3u8 地址失败: $e');
      return '';
    }
  }
}
