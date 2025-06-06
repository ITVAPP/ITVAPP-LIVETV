import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 延安电视台解析器
class yananParser {
  static const String _baseUrl = 'https://api1.yanews.cn';

  /// 解析延安电视台直播流地址，添加 cancelToken 参数
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 获取内容列表，传递 cancelToken
      final channels = await _getChannelList(cancelToken: cancelToken);
      if (channels.isEmpty) {
        LogUtil.i('获取频道列表失败');
        return 'ERROR';
      }

      // 优化：处理负数情况，使用取模运算确保索引有效
      final channelIndex = clickIndex < 0 ? 0 : clickIndex % channels.length;
      final channel = channels[channelIndex];

      final playUrl = channel['play_url'] as String?;
      
      // 优化：合并空值检查和m3u8验证，只trim一次
      if (playUrl == null || playUrl.isEmpty) {
        LogUtil.i('播放地址为空');
        return 'ERROR';
      }
      
      final trimmedUrl = playUrl.trim();
      if (!trimmedUrl.contains('.m3u8')) {
        LogUtil.i('播放地址不包含 m3u8: $trimmedUrl');
        return 'ERROR';
      }

      LogUtil.i('成功获取播放地址: "$trimmedUrl"');
      return trimmedUrl;
    } catch (e) {
      LogUtil.i('解析延安电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取频道列表，添加 cancelToken 参数
  static Future<List<dynamic>> _getChannelList({CancelToken? cancelToken}) async {
    final path = '/peony/v1/content';
    final params = {
      'gid': 'LZkmpMDK',
      'pagesize': '20',
      'pageindex': '1',
      'group_type': 'nav h2',
    };

    // 传递 cancelToken
    final result = await _sendRequest(path, params, cancelToken: cancelToken);
    if (result == null) return [];

    try {
      final data = result['data'];
      if (data == null || data['posts'] == null || data['posts'].isEmpty) {
        LogUtil.i('内容列表为空或无 posts 数据');
        return [];
      }

      // 提取第一个 post 中的 channels 数组
      final posts = data['posts'] as List<dynamic>;
      final firstPost = posts[0];
      final channels = firstPost['channels'] as List<dynamic>?;

      if (channels == null || channels.isEmpty) {
        LogUtil.i('频道列表为空');
        return [];
      }

      LogUtil.i('成功获取频道列表: $channels');
      return channels;
    } catch (e) {
      LogUtil.i('解析频道列表失败: $e');
      return [];
    }
  }

  /// 发送请求，添加 cancelToken 参数
  static Future<Map<String, dynamic>?> _sendRequest(
    String path, 
    Map<String, String> params, 
    {CancelToken? cancelToken}
  ) async {
    try {
      // 生成13位毫秒级时间戳
      final msTimestamp = DateTime.now().millisecondsSinceEpoch;

      // 构建请求头
      final headers = {
        'Host': 'api1.yanews.cn',
        'x-timestamp': msTimestamp.toString(),
        'authorization':
            'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcHBpZCI6MSwiZGV2aWNlX2lkIjoiODYyMDYwOTEtZjQ1NS00ZTI2LThhNGItZmE1NDY4ZTQwNWIyIiwiZXhwIjoxNzUyODEzMjE5LCJpYXQiOjE3NDUwMzcyMTksImlzcyI6IjlwNnlqdW9hVnhuMFZ3d21TdHRJY20zWEp3bWNmUkNrIiwianRpIjoiYkFRWHpUblRFZCIsImxvZ2luX3RpbWUiOjE3NDUwMzcyMTksIm1wX3VpZCI6IiIsIm5iZiI6MTc0NTAzNzIxOSwicGxhdGZvcm0iOiJtb2JpbGUiLCJzaXRlIjo0LCJzdWIiOiJhbm9ueW1vdXMiLCJ1aWQiOiJhbm9ueW1vdXMifQ.qN-BwqEvrWEfM4EU2rkDZD-5LE9qOJc-e3daekTiUe8',
        'x-request-id': '86206091-f455-4e26-8a4b-fa5468e405b2',
        'x-platform': 'Android',
        'x-brand': 'Redmi',
        'x-device-model': 'Redmi K80',
        'x-version': '12',
        'accept-encoding': 'gzip',
        'user-agent': 'okhttp/4.10.0',
      };

      // 构建完整URL
      final queryString = Uri(queryParameters: params).query;
      final fullUrl = '$_baseUrl$path?$queryString';

      LogUtil.i('发送请求: $fullUrl');

      // 发送请求，传递 cancelToken
      final response = await HttpUtil().getRequest<String>(
        fullUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
        cancelToken: cancelToken,
      );

      if (response != null) {
        LogUtil.i('API 响应内容: $response');
        return json.decode(response);
      }
    } catch (e) {
      LogUtil.i('请求失败: $e');
    }
    return null;
  }
}
