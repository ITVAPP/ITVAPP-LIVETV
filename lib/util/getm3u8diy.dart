import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/getapp/jinan.dart';
import 'package:itvapp_live_tv/util/getapp/gansu.dart';
import 'package:itvapp_live_tv/util/getapp/zhanjiang_parser.dart';

/// m3u8地址解析器
class GetM3u8Diy {
  /// 根据 URL 获取直播流地址
  static Future<String> getStreamUrl(String url) async {
    try {
      // 如果 URL 包含 `gansu`，调用甘肃电视台解析器
      if (url.contains('gansu')) {
        return await GansuParser.parse(url);
      }
      // 调用济南电视台解析器
      else if (url.contains('jinan')) {
        return await JinanParser.parse(url);
      }
      // 调用湛江电视台解析器
      else if (url.contains('zhanjiang')) {
        return await ZhanjiangParser.parse(url);
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
