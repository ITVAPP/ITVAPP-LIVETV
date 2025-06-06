import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 四川电视台解析器
class SichuanParser {
  // 优化：使用List直接索引访问，避免Map查找开销
  static const List<List<String>> _channelList = [
    ['sctv1', '四川卫视'],
    ['sctv2', '四川经济'],
    ['sctv3', '四川文化旅游'],
    ['sctv4', '四川新闻'],
    ['sctv5', '四川影视文艺'],
    ['sctv6', '四川星空购物'],
    ['sctv7', '四川妇女儿童'],
    ['sctv9', '四川乡村'],
    ['kangba', '康巴卫视'],
  ];

  static const String _baseUrl = 'https://gw.scgchc.com';
  static const String _playBaseUrl = 'https://tvshow.scgchc.com';
  static const String _authToken =
      'bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOlsiU0VSVklDRV9TQ0dDLURFTU8iXSwidXNlcl9pZCI6MTkxMjUwNTg5NzAwMDg2MTY5OCwic2NvcGUiOlsiYWxsIl0sImV4cCI6MTc0NTQxNjcxMywiYXV0aG9yaXRpZXMiOlsiUk9MRV9BUFBfQ0xJRU5UX1VTRVIiXSwianRpIjoiNDFlNTgwYWEtMTVhZC00ZDEyLWI2MWYtYjYwMzhmNGQ3ZDRkIiwiY2xpZW50X2lkIjoiU0VSVklDRV9TQ0dDLUFQUCJ9.kMfmNJvCN4nNmqYjp4DfcisVMFXMKoGUTb6tUN-jglWASBsU7sxZxN0jbFf98Qa8EV75O8WgkrnLU6niKGYK-kkFxBBto-WPCRXHbmRg4VkVneqegly3AGOFDSenPUY5eD9VXtxvvnycDLv_KOJrFjhv5tZz7ykrfWKNXIqhCOBL0ksHlGIGdWNyIWZ51YNtgSuAxU93iHk4yjawjeStPEsZJ_6sBtpYw0NJk-f6o0_TRUMozOgGwGtHmipxAEYNb3zOsbPVOjZjLfbmwoYM1_9XkNkruJ-UtvMcHywiXwf9pffzv_KWIk9z5BAUHxtPfSmExyvcfAMGp_jMJs7svQ';

  /// 解析四川电视台直播流地址，添加 cancelToken 参数
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 优化：处理负数情况，使用取模运算确保索引有效，直接访问List
      final channelIndex = clickIndex < 0 ? 0 : clickIndex % _channelList.length;
      final channelInfo = _channelList[channelIndex];
      
      final channelId = channelInfo[0];
      final channelName = channelInfo[1];
      LogUtil.i('选择的频道: $channelName (ID: $channelId, clickIndex: $clickIndex)');

      // 获取 m3u8 播放地址，传递 cancelToken
      final m3u8Url = await _getM3u8Url(channelId, cancelToken: cancelToken);
      
      // 优化：合并空值检查和m3u8验证
      if (m3u8Url.isEmpty || !m3u8Url.contains('.m3u8')) {
        LogUtil.i('获取 m3u8 地址失败或地址无效: $m3u8Url');
        return 'ERROR';
      }

      LogUtil.i('成功获取 m3u8 播放地址: $m3u8Url');
      return m3u8Url;
    } catch (e) {
      LogUtil.i('解析四川电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取 m3u8 播放地址，添加 cancelToken 参数
  static Future<String> _getM3u8Url(String channelId, {CancelToken? cancelToken}) async {
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

      // 发送请求，传递 cancelToken
      final response = await HttpUtil().getRequest<String>(
        apiUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
        cancelToken: cancelToken,
      );

      if (response == null) {
        LogUtil.i('API 响应为空');
        return '';
      }

      // 解析响应
      final responseData = json.decode(response);
      final secret = responseData['data']?['secret'] as String?;

      if (secret == null || secret.isEmpty) {
        LogUtil.i('无法获取 secret');
        return '';
      }

      // 构造 m3u8 地址
      final m3u8Url = '$_playBaseUrl/hdlive/$channelId' '8f9fb5888dedbe0c6a1b/1.m3u8?$secret';
      return m3u8Url;
    } catch (e) {
      LogUtil.i('获取 m3u8 地址失败: $e');
      return '';
    }
  }
}
