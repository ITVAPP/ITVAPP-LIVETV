import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/getapp/jinan.dart';
import 'package:itvapp_live_tv/util/getapp/gansu.dart';
import 'package:itvapp_live_tv/util/getapp/xizang.dart';
import 'package:itvapp_live_tv/util/getapp/sichuan.dart';
import 'package:itvapp_live_tv/util/getapp/xishui.dart';
import 'package:itvapp_live_tv/util/getapp/yanan.dart';
import 'package:itvapp_live_tv/util/getapp/foshan.dart';

/// 定义解析器函数类型
typedef ParserFunction = Future<String> Function(String url);

/// m3u8地址解析器
class GetM3u8Diy {
  /// 解析器映射表
  static final Map<String, ParserFunction> _parsers = {
    'gansu': GansuParser.parse,
    'jinan': JinanParser.parse,
    'xizang': xizangParser.parse,
    'sichuan': SichuanParser.parse,
    'xishui': xishuiParser.parse,
    'yanan': yananParser.parse,
    'foshan': foshanParser.parse,
  };

  /// 根据 URL 获取直播流地址
  static Future<String> getStreamUrl(String url) async {
    try {
      // 查找匹配的解析器
      for (final key in _parsers.keys) {
        if (url.contains(key)) {
          return await _parsers[key]!(url);
        }
      }
      
      // 如果不符合任何解析规则，记录日志并返回错误信息
      LogUtil.i('未找到匹配的解析规则: $url');
      return 'ERROR';
    } catch (e) {
      // 捕获解析异常并记录日志
      LogUtil.i('解析直播流地址失败: $e');
      return 'ERROR';
    }
  }
  
  /// 添加新的解析器
  static void addParser(String keyword, ParserFunction parser) {
    _parsers[keyword] = parser;
  }
}
