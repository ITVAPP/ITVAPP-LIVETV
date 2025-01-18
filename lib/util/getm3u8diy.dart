import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 通用工具类
class ParserUtils {
  /// Base64解码函数
  static String decodeBase64(String input) {
    try {
      String cleanInput = input.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      while (cleanInput.length % 4 != 0) {
        cleanInput += '=';
      }

      final halfLength = cleanInput.length ~/ 2;
      final firstHalf = cleanInput.substring(0, halfLength);
      final secondHalf = cleanInput.substring(halfLength);
      final reversed = (secondHalf + firstHalf).split('').reversed.join();

      try {
        return utf8.decode(base64.decode(reversed));
      } on FormatException {
        return utf8.decode(base64.decode(cleanInput));
      }
    } catch (e) {
      LogUtil.i('Base64解码失败: $e');
      return '';
    }
  }
}

class GetM3u8Diy {
  static Future<String> getStreamUrl(String url) async {
    try {
      if (url.contains('sztv.com.cn')) {
        return await SztvParser.parse(url);
      }
      // 添加其他解析规则
      LogUtil.i('未找到匹配的解析规则: $url');
      return '';
    } catch (e) {
      LogUtil.i('解析直播流地址失败: $e');
      return '';
    }
  }
}

/// 深圳卫视解析器
class SztvParser {
  static const Map<String, List<String>> TV_LIST = {
    'szws': ['AxeFRth', '7867', '深圳卫视'],
    'szds': ['ZwxzUXr', '7868', '都市频道'],
    'szdsj': ['4azbkoY', '7880', '电视剧频道'],
    'szcj': ['3vlcoxP', '7871', '财经频道'],
    'szse': ['1SIQj6s', '7881', '少儿频道'],
    'szyd': ['wDF6KJ3', '7869', '移动电视'],
    'szyh': ['BJ5u5k2', '7878', '宜和购物频道'],
    'szgj': ['sztvgjpd', '7944', '国际频道'],
  };

  static Future<String> parse(String url) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id'];

    if (!TV_LIST.containsKey(id)) {
      LogUtil.i('无效的频道ID');
      return '';
    }

    final channelInfo = TV_LIST[id]!;
    final liveId = channelInfo[0];
    final cdnId = channelInfo[1];

    try {
      final liveKey = await _getLiveKey(liveId);
      if (liveKey.isEmpty) return '';

      final cdnKey = await _getCdnKey(cdnId);
      if (cdnKey.isEmpty) return '';

      final timeHex = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign = md5.convert(utf8.encode('$cdnKey/$liveId/500/$liveKey.m3u8$timeHex')).toString();

      return 'https://sztv-live.sztv.com.cn/$liveId/500/$liveKey.m3u8?sign=$sign&t=$timeHex';
    } catch (e) {
      LogUtil.i('生成深圳卫视直播流地址失败: $e');
      return '';
    }
  }

  static Future<String> _getLiveKey(String liveId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5.convert(utf8.encode('$timestamp$liveId' + 'cutvLiveStream|Dream2017')).toString();

    try {
      final response = await http.get(
        Uri.parse('https://hls-api.sztv.com.cn/getCutvHlsLiveKey').replace(
          queryParameters: {
            't': timestamp.toString(),
            'id': liveId,
            'token': token,
            'at': '1',
          },
        ),
      );

      if (response.statusCode == 200) {
        // 使用工具类的解码方法
        return ParserUtils.decodeBase64(response.body);
      }
      LogUtil.i('获取直播密钥失败: HTTP ${response.statusCode}');
    } catch (e) {
      LogUtil.i('获取直播密钥时发生错误: $e');
    }
    return '';
  }

  static Future<String> _getCdnKey(String cdnId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final token = md5.convert(utf8.encode('iYKkRHlmUanQGaNMIJziWOkNsztv-live.sztv.com.cn$timestamp')).toString();

    try {
      final response = await http.get(
        Uri.parse('https://sttv2-api.sztv.com.cn/api/getCDNkey.php').replace(
          queryParameters: {
            'domain': 'sztv-live.sztv.com.cn',
            'page': 'https://www.sztv.com.cn/pindao/index.html?id=$cdnId',
            'token': token,
            't': timestamp.toString(),
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['key'] != null) {
          return data['key'];
        }
        LogUtil.i('响应中未找到CDN密钥');
      } else {
        LogUtil.i('获取CDN密钥失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取CDN密钥时发生错误: $e');
    }
    return '';
  }
}
