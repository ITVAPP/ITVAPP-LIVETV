import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 通用工具类
class ParserUtils {
  /// Base64 解码函数
  static String decodeBase64(String input) {
    try {
      // 去除无效字符，确保输入字符串合法
      String cleanInput = input.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      // 补齐 Base64 长度，避免解码异常
      while (cleanInput.length % 4 != 0) {
        cleanInput += '=';
      }

      // 对输入字符串进行反转和重组
      final halfLength = cleanInput.length ~/ 2;
      final firstHalf = cleanInput.substring(0, halfLength);
      final secondHalf = cleanInput.substring(halfLength);
      final reversed = (secondHalf + firstHalf).split('').reversed.join();

      try {
        // 优先尝试解码反转后的字符串
        return utf8.decode(base64.decode(reversed));
      } on FormatException {
        // 如果反转解码失败，尝试直接解码原始字符串
        return utf8.decode(base64.decode(cleanInput));
      }
    } catch (e) {
      // 解码失败时记录日志并返回空字符串
      LogUtil.i('Base64 解码失败: $e');
      return '';
    }
  }
}

class GetM3u8Diy {
  /// 根据 URL 获取直播流地址
  ///
  /// 功能：根据 URL 判断适用的解析规则，调用对应的解析器获取直播流地址。
  static Future<String> getStreamUrl(String url) async {
    try {
      // 如果 URL 包含 `sztv.com.cn`，调用深圳卫视解析器
      if (url.contains('sztv.com.cn')) {
        return await SztvParser.parse(url);
      }
      // 如果 URL 包含 `hntv`，调用河南卫视解析器
      else if (url.contains('hntv')) {
        return await HntvParser.parse(url);
      }
      // 如果不符合任何解析规则，记录日志并返回空字符串
      LogUtil.i('未找到匹配的解析规则: $url');
      return '';
    } catch (e) {
      // 捕获解析异常并记录日志
      LogUtil.i('解析直播流地址失败: $e');
      return '';
    }
  }
}

/// 深圳卫视解析器
class SztvParser {
  /// 频道列表映射表：频道 ID -> [频道编号, CDN ID, 频道名称]
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

  /// 解析深圳卫视直播流地址
  /// 功能：根据频道 ID 获取对应的直播流地址。
  static Future<String> parse(String url) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id']; // 提取频道 ID

    // 检查频道 ID 是否在映射表中
    if (!TV_LIST.containsKey(id)) {
      LogUtil.i('无效的频道 ID');
      return '';
    }

    final channelInfo = TV_LIST[id]!; // 获取频道信息
    final liveId = channelInfo[0];
    final cdnId = channelInfo[1];

    try {
      // 获取直播密钥和 CDN 密钥
      final liveKey = await _getLiveKey(liveId);
      if (liveKey.isEmpty) return '';
      final cdnKey = await _getCdnKey(cdnId);
      if (cdnKey.isEmpty) return '';

      // 生成签名和完整的直播流地址
      final timeHex = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign = md5.convert(utf8.encode('$cdnKey/$liveId/500/$liveKey.m3u8$timeHex')).toString();

      return 'https://sztv-live.sztv.com.cn/$liveId/500/$liveKey.m3u8?sign=$sign&t=$timeHex';
    } catch (e) {
      LogUtil.i('生成深圳卫视直播流地址失败: $e');
      return '';
    }
  }

  /// 获取直播密钥
  static Future<String> _getLiveKey(String liveId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = md5.convert(utf8.encode('$timestamp$liveId' + 'cutvLiveStream|Dream2017')).toString();

    try {
      // 发送请求获取直播密钥
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
        return ParserUtils.decodeBase64(response.body);
      }
      LogUtil.i('获取直播密钥失败: HTTP ${response.statusCode}');
    } catch (e) {
      LogUtil.i('获取直播密钥时发生错误: $e');
    }
    return '';
  }

  /// 获取 CDN 密钥
  static Future<String> _getCdnKey(String cdnId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final token = md5.convert(utf8.encode('iYKkRHlmUanQGaNMIJziWOkNsztv-live.sztv.com.cn$timestamp')).toString();

    try {
      // 发送请求获取 CDN 密钥
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
        LogUtil.i('响应中未找到 CDN 密钥');
      } else {
        LogUtil.i('获取 CDN 密钥失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取 CDN 密钥时发生错误: $e');
    }
    return '';
  }
}

/// 河南卫视解析器
class HntvParser {
  static const Map<String, List<String>> TV_LIST = {
    'hnws': ['145', '河南卫视'],
    'hnds': ['141', '河南都市'],
    'hnms': ['146', '河南民生'],
    'hmfz': ['147', '河南法治'],
    'hndsj': ['148', '河南电视剧'],
    'hnxw': ['149', '河南新闻'],
    'htgw': ['150', '欢腾购物'],
    'hngg': ['151', '河南公共'],
    'hnxc': ['152', '河南乡村'],
    'hngj': ['153', '河南国际'],
    'hnly': ['154', '河南梨园'],
  };

  static Future<String> parse(String url) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id']; // 提取频道 ID

    if (!TV_LIST.containsKey(id)) {
      LogUtil.i('无效的频道 ID');
      return '';
    }

    final channelInfo = TV_LIST[id]!;
    final channelId = channelInfo[0];

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = sha256.convert(utf8.encode('6ca114a836ac7d73$timestamp')).toString();

    try {
      // 请求河南卫视数据接口
      final response = await http.get(
        Uri.parse('https://pubmod.hntv.tv/program/getAuth/live/class/program/11'),
        headers: {
          'timestamp': timestamp.toString(),
          'sign': sign,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        for (var item in data) {
          if (item['cid'].toString() == channelId) {
            return item['video_streams'][0];
          }
        }
      } else {
        LogUtil.i('获取河南电视台数据失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取河南电视台直播地址失败: $e');
    }

    return '';
  }
}
