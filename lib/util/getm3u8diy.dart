import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

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
      return 'ERROR';
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
      return 'ERROR';
    } catch (e) {
      // 捕获解析异常并记录日志
      LogUtil.i('解析直播流地址失败: $e');
      return 'ERROR';
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
      return 'ERROR';
    }

    final channelInfo = TV_LIST[id]!; // 获取频道信息
    final liveId = channelInfo[0];
    final cdnId = channelInfo[1];

    try {
      // 获取直播密钥和 CDN 密钥
      final liveKey = await _getLiveKey(liveId);
      if (liveKey.isEmpty) return 'ERROR';
      final cdnKey = await _getCdnKey(cdnId);
      if (cdnKey.isEmpty) return 'ERROR';

      // 生成签名和完整的直播流地址
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timeHex = timestamp.toRadixString(16); // 转换为16进制
      final sign = md5.convert(utf8.encode('$cdnKey/$liveId/500/$liveKey.m3u8$timestamp')).toString();

      return 'https://sztv-live.sztv.com.cn/$liveId/500/$liveKey.m3u8?sign=$sign&t=$timeHex';
    } catch (e) {
      LogUtil.i('生成深圳卫视直播流地址失败: $e');
      return 'ERROR';
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
        headers: HeadersConfig.generateHeaders(
          url: 'https://hls-api.sztv.com.cn/getCutvHlsLiveKey',
        ),
      );

      if (response.statusCode == 200) {
        return ParserUtils.decodeBase64(response.body);
      }
      LogUtil.i('获取直播密钥失败: HTTP ${response.statusCode}');
    } catch (e) {
      LogUtil.i('获取直播密钥时发生错误: $e');
    }
    return 'ERROR';
  }

  /// 获取 CDN 密钥
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
      headers: HeadersConfig.generateHeaders(
        url: 'https://sttv2-api.sztv.com.cn/api/getCDNkey.php',
      ),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // 根据实际返回的JSON结构进行解析
      if (data != null && data['status'] == 'ok' && data['key'] != null) {
        LogUtil.i('成功获取CDN密钥');
        return data['key'];
      }
      LogUtil.i('响应格式不符合预期: ${response.body}');
    } else {
      LogUtil.i('获取 CDN 密钥失败: HTTP ${response.statusCode}');
    }
  } catch (e) {
    LogUtil.i('获取 CDN 密钥时发生错误: $e');
  }
  return 'ERROR';
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
      LogUtil.i('无效的频道 ID: $id');
      return 'ERROR';
    }

    final channelInfo = TV_LIST[id]!;
    final channelId = channelInfo[0];

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = sha256.convert(utf8.encode('6ca114a836ac7d73$timestamp')).toString();

    final requestUrl = 'https://pubmod.hntv.tv/program/getAuth/live/class/program/11';
    final headers = {
      'timestamp': timestamp.toString(),
      'sign': sign,
      ...HeadersConfig.generateHeaders(url: requestUrl),
    };

    // 记录请求信息，方便调试
    LogUtil.i('正在请求河南电视台直播流: $requestUrl');
    LogUtil.i('请求 Headers: $headers');

    try {
      final response = await http.get(Uri.parse(requestUrl), headers: headers);

      // 记录 HTTP 状态码
      LogUtil.i('HTTP 状态码: ${response.statusCode}');

      // 记录完整的响应 Body，避免 JSON 结构出错时无法调试
      LogUtil.i('响应 Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);

        // 确保 data 字段存在并且是列表
        if (jsonResponse.containsKey('data') && jsonResponse['data'] is List) {
          final List<dynamic> channels = jsonResponse['data'];

          LogUtil.i('返回的频道数量: ${channels.length}');

          for (var item in channels) {
            // 记录每个频道的 ID 和名称
            LogUtil.i('频道 ID: ${item['cid']}, 频道名称: ${item['title']}');

            if (item['cid'].toString() == channelId) {
              LogUtil.i('匹配的频道 ID 找到: $channelId');

              // 确保 video_streams 存在并且是列表
              if (item['video_streams'] is List && (item['video_streams'] as List).isNotEmpty) {
                LogUtil.i('找到直播流 URL: ${item['video_streams'][0]}');
                return item['video_streams'][0].toString();
              } else {
                LogUtil.i('频道 $channelId 没有可用的视频流');
              }
            }
          }

          LogUtil.i('未找到匹配的频道信息: 可能频道 ID 发生变化');
        } else {
          LogUtil.i('JSON 结构不符合预期: ${response.body}');
        }
      } else {
        LogUtil.i('获取河南电视台数据失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取河南电视台直播地址失败: $e');
    }

    return 'ERROR';
  }
}
