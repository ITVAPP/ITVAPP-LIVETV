import 'dart:convert';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 湛江电视台解析器
class ZhanjiangParser {
  static const String _baseUrl = 'https://www.zjwtv.com';
  static const String _referer = 'https://app.zjwtv.com/';
  static const String _suffix = '&itvapp.m3u8'; // 要追加的后缀

  /// 解析湛江电视台直播流地址
  static Future<String> parse(String url) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 获取直播流列表
      final streams = await _getStreamList();
      if (streams.isEmpty) {
        LogUtil.i('获取湛江台直播流列表失败');
        return 'ERROR';
      }

      // 根据 stream_key 查找直播流地址
      String? zhpdUrl;
      String? ggpdUrl;

      for (var stream in streams) {
        final streamKey = stream['stream_key'] as String?;
        final m3u8 = stream['m3u8'] as String?;
        if (streamKey == 'zhpd' && m3u8 != null && m3u8.isNotEmpty) {
          zhpdUrl = m3u8;
        } else if (streamKey == 'ggpd' && m3u8 != null && m3u8.isNotEmpty) {
          ggpdUrl = m3u8;
        }
      }

      // 根据 clickIndex 返回固定地址，并追加后缀
      String? playUrl;
      if (clickIndex == 1 && ggpdUrl != null) {
        playUrl = '$ggpdUrl$_suffix'; // 追加 &itvapp.m3u8
        LogUtil.i('返回湛江公共频道直播流: $playUrl');
        return playUrl;
      } else if (zhpdUrl != null) {
        playUrl = '$zhpdUrl$_suffix'; // 追加 &itvapp.m3u8
        LogUtil.i('返回湛江新闻综合频道直播流: $playUrl');
        return playUrl;
      } else {
        LogUtil.i('未找到有效直播流地址');
        return 'ERROR';
      }
    } catch (e) {
      LogUtil.i('解析湛江台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取直播流列表
  static Future<List<dynamic>> _getStreamList() async {
    const path = '/tvradio/Tv/tvList';
    final params = {
      'class_id': '5',
      'index': '1',
      'status': '2',
    };

    final result = await _sendRequest(path, params);
    if (result == null) return [];

    try {
      final code = result['code'];
      if (code != 200) {
        LogUtil.i('湛江台API返回错误码: $code');
        return [];
      }

      final data = result['data'];
      if (data == null) return [];

      final list = data['list'];
      if (list is! List) return [];

      return list;
    } catch (e) {
      LogUtil.i('解析湛江台直播流列表失败: $e');
      return [];
    }
  }

  /// 发送请求
  static Future<Map<String, dynamic>?> _sendRequest(String path, Map<String, String> params) async {
    try {
      final headers = {
        'Referer': _referer,
        'Content-Type': 'application/json',
        'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 12; Redmi K80 Build/SKQ1.211006.001)',
        'Connection': 'Keep-Alive',
        'Accept-Encoding': 'gzip',
      };

      final queryString = Uri(queryParameters: params).query;
      final fullUrl = '$_baseUrl$path?$queryString';
      LogUtil.i('发送请求: $fullUrl');
      LogUtil.i('请求头: $headers');

      final response = await HttpUtil().getRequest<String>(
        fullUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

      if (response != null) {
        return json.decode(response);
      }
    } catch (e) {
      LogUtil.i('湛江台请求失败: $e');
    }
    return null;
  }
}
