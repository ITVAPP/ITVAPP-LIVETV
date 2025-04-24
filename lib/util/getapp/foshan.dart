import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 佛山电视台解析器
class foshanParser {
  static const String _baseUrl = 'https://xmapi.fstv.com.cn/appapi/tv/indexaes';

  // 定义支持的频道列表，映射PHP中的$channels
  static const Map<String, Map<String, dynamic>> _channels = {
    'fszh': {'id': 3, 'name': '佛山综合'},
    'fsys': {'id': 4, 'name': '佛山影视'},
    'fsgg': {'id': 2, 'name': '佛山公共'},
    'fsnh': {'id': 5, 'name': '佛山南海'},
    'fssd': {'id': 6, 'name': '佛山顺德'},
    'fsgm': {'id': 7, 'name': '佛山高明'},
    'fsss': {'id': 8, 'name': '佛山三水'},
  };

  /// 解析佛山电视台直播流地址
  static Future<String> parse(String url) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = uri.queryParameters['clickIndex'] ?? '';

      // Map clickIndex to channel ID
      Map<String, dynamic> channelInfo; // Non-nullable
      if (clickIndex.isEmpty || !_channels.containsKey(clickIndex)) {
        // Default to 'fsgg' (ID: 2, 佛山公共)
        channelInfo = _channels['fsgg']!; // Safe since 'fsgg' exists
        LogUtil.i('无效或未提供clickIndex，使用默认频道: ${channelInfo['name']} (ID: ${channelInfo['id']})');
      } else {
        channelInfo = _channels[clickIndex]!; // Safe since key is checked
        LogUtil.i('选择的频道: ${channelInfo['name']} (ID: ${channelInfo['id']})');
      }

      final response = await _fetchChannelData();
      if (response == null || response['error_code'] != 0) {
        LogUtil.i('API请求失败或返回错误: ${response?['error_msg'] ?? '未知错误'}');
        return 'ERROR';
      }

      final channels = response['data']['channel'] as List<dynamic>?;
      if (channels == null || channels.isEmpty) {
        LogUtil.i('API响应缺少channel数据');
        return 'ERROR';
      }

      LogUtil.i('频道列表: $channels');

      String? playUrl;
      const key = 'ptfcaxhmslc4Kyrnj$lWwmkcvdze2cub';
      const iv = '352e7f4773ef5c30';

      for (var channel in channels) {
        if (channel['id'] == channelInfo['id']) {
          final stream = channel['stream'] as String?;
          if (stream == null || stream.isEmpty) {
            LogUtil.i('频道 ${channelInfo['name']} 的stream字段为空');
            return 'ERROR';
          }

          // Decrypt stream
          try {
            final encrypter = Encrypter(AES(
              Key.fromUtf8(key),
              mode: AESMode.cbc,
            ));
            final encrypted = Encrypted.fromBase64(stream);
            playUrl = encrypter.decrypt(encrypted, iv: IV.fromUtf8(iv));
            LogUtil.i('成功解密m3u8地址: $playUrl');
          } catch (e) {
            LogUtil.i('解密stream失败: $e');
            return 'ERROR';
          }
          break;
        }
      }

      if (playUrl == null || playUrl.trim().isEmpty || !playUrl.contains('.m3u8')) {
        LogUtil.i('无效的m3u8地址: $playUrl');
        return 'ERROR';
      }

      final trimmedPlayUrl = playUrl.trim();
      LogUtil.i('成功获取m3u8播放地址: $trimmedPlayUrl');
      return trimmedPlayUrl;
    } catch (e) {
      LogUtil.i('解析佛山电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取频道数据
  static Future<Map<String, dynamic>?> _fetchChannelData() async {
    try {
      final headers = {
        'APPKEY': 'xinmem3.0',
        'VERSION': '4.0.9',
        'PLATFORM': 'ANDROID',
        'SIGN': 'b2350fe63e26fbf872b424dece22bd1b',
        'Content-Type': 'application/json',
      };

      final postData = jsonEncode({});

      final response = await HttpUtil().postRequest<Map<String, dynamic>>(
        _baseUrl,
        data: postData,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

      if (response == null) {
        LogUtil.i('POST请求返回空响应');
        return null;
      }

      LogUtil.i('API响应内容: $response');
      return response;
    } catch (e) {
      LogUtil.i('获取频道数据失败: $e');
      return null;
    }
  }
}
