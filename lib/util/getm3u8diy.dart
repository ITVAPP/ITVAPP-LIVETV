import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

class getm3u8diy {
  static const Map<String, List<String>> TV_LIST = {
    'szws': ['AxeFRth', '7867', '深圳卫视'],
    'szds': ['ZwxzUXr', '7868', '都市频道'],
    'szdsj': ['4azbkoY', '7880', '电视剧频道'],
    'szcj': ['3vlcoxP', '7871', '财经频道'],
    'szse': ['1SIQj6s', '7881', '少儿频道'],
    'szyd': ['wDF6KJ3', '7869', '移动电视'],
    'szyh': ['BJ5u5k2', '7878', '宜和购物频道'],
    'szgj': ['sztvgjpd', '7944', '国际频道']
  };

  /// 获取直播流地址
  static Future<String> getStreamUrl(String url) async {
    // 解析URL参数
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id'];
    
    // 检查是否是深圳卫视域名且有效的频道ID
    if (!url.contains('sztv.com.cn') || !TV_LIST.containsKey(id)) {
      LogUtil.i('无效的URL或频道ID');
    }

    final channelInfo = TV_LIST[id]!;
    final liveId = channelInfo[0];
    final cdnId = channelInfo[1];

    try {
      // 1. 获取直播密钥
      final liveKey = await _getLiveKey(liveId);
      
      // 2. 获取CDN密钥
      final cdnKey = await _getCdnKey(cdnId);
      
      // 3. 生成最终播放URL
      final timeHex = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign = md5.convert(utf8.encode('$cdnKey/$liveId/500/$liveKey.m3u8$timeHex')).toString();
      
      return 'https://sztv-live.sztv.com.cn/$liveId/500/$liveKey.m3u8?sign=$sign&t=$timeHex';
    } catch (e) {
      LogUtil.i('获取直播流地址失败: $e');
    }
  }

  /// 获取直播密钥
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
            'at': '1'
          }
        )
      );

      if (response.statusCode == 200) {
        return _decodeBase64(response.body);
      } else {
        LogUtil.i('获取直播密钥失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取直播密钥时发生网络错误: $e');
    }
  }

  /// 获取CDN密钥
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
            't': timestamp.toString()
          }
        )
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['key'] == null) {
          LogUtil.i('响应中未找到CDN密钥');
        }
        return data['key'];
      } else {
        LogUtil.i('获取CDN密钥失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取CDN密钥时发生网络错误: $e');
    }
  }

  /// Base64解码函数
  static String _decodeBase64(String input) {
    try {
      // 清理输入字符串，移除所有非Base64字符
      String cleanInput = input.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      
      // 确保输入长度是4的倍数
      while (cleanInput.length % 4 != 0) {
        cleanInput += '=';
      }

      // 将字符串分成两半
      final halfLength = cleanInput.length ~/ 2;
      final firstHalf = cleanInput.substring(0, halfLength);
      final secondHalf = cleanInput.substring(halfLength);
      
      // 反转并拼接
      final reversed = (secondHalf + firstHalf).split('').reversed.join();
      
      // Base64解码
      try {
        return utf8.decode(base64.decode(reversed));
      } on FormatException {
        // 如果第一次解码失败，尝试直接解码原始输入
        return utf8.decode(base64.decode(cleanInput));
      }
    } catch (e) {
      LogUtil.i('Base64解码失败: $e');
    }
  }
}
