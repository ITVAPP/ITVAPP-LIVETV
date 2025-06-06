import 'dart:convert';
import 'dart:math' show Random;
import 'package:crypto/crypto.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

/// 甘肃电视台解析器
class GansuParser {
  static const String _baseUrl = 'https://hlss.gstv.com.cn';
  static const String _uid = '0';
  static const String _secret = '8f60c8102d29fcd525162d02eed4566b';
  static final _random = Random();
  
  // 频道列表映射表
  static const CHANNEL_LIST = <int, List<String>>{
    0: ['/49048r/y3nga4.m3u8', '甘肃卫视'],
    1: ['/49048r/068vw9.m3u8', '影视频道'],
    2: ['/49048r/2v86i8.m3u8', '公共频道'],
    3: ['/49048r/4o7e76.m3u8', '科教频道'],
    4: ['/49048r/oj57of.m3u8', '少儿频道'],
    5: ['/49048r/y72q36.m3u8', '移动电视'],
  };
  
  /// 解析甘肃电视台直播流地址，添加 cancelToken 参数
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    try {
      final uri = Uri.parse(url);
      var clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;
      
      // 如果索引无效,使用0(甘肃卫视)
      if (!CHANNEL_LIST.containsKey(clickIndex)) {
        LogUtil.i('无效的频道索引: $clickIndex, 使用默认频道(甘肃卫视)');
        clickIndex = 0;
      }
      
      final channelInfo = CHANNEL_LIST[clickIndex]!;
      final videoPath = channelInfo[0];
      final channelName = channelInfo[1];
      LogUtil.i('正在解析频道: $channelName');
      
      final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800;
      final rand = _generateRandomString(32);
      
      final signStr = '$videoPath-$expires-$rand-$_uid-$_secret';
      LogUtil.i('签名原始字符串: $signStr');
      
      final sign = md5.convert(utf8.encode(signStr)).toString();
      LogUtil.i('生成的sign: $sign');
      
      // 使用StringBuffer优化字符串拼接
      final buffer = StringBuffer(_baseUrl)
        ..write(videoPath)
        ..write('?auth_key=')
        ..write(expires)
        ..write('-')
        ..write(rand)
        ..write('-')
        ..write(_uid)
        ..write('-')
        ..write(sign);
      
      final streamUrl = buffer.toString();
      LogUtil.i('生成的直播流地址: $streamUrl');
      return streamUrl;
      
    } catch (e) {
      LogUtil.i('解析甘肃电视台直播流失败: $e');
      return 'ERROR';
    }
  }
  
  /// 生成指定长度的随机字符串
  static String _generateRandomString(int length) {
    const chars = '0123456789abcdef';
    return List.generate(length, (index) => chars[_random.nextInt(chars.length)]).join();
  }
}
