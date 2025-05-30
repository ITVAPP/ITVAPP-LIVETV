import 'dart:async';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/getapp/sousuo.dart';
import 'package:itvapp_live_tv/util/getapp/jinan.dart';
import 'package:itvapp_live_tv/util/getapp/gansu.dart';
import 'package:itvapp_live_tv/util/getapp/xizang.dart';
import 'package:itvapp_live_tv/util/getapp/sichuan.dart';
import 'package:itvapp_live_tv/util/getapp/xishui.dart';
import 'package:itvapp_live_tv/util/getapp/yanan.dart';
import 'package:itvapp_live_tv/util/getapp/foshan.dart';
import 'package:itvapp_live_tv/util/getapp/shantou.dart';

// 定义解析器函数类型，含URL和取消令牌参数
typedef ParserFunction = Future<String> Function(String url, {CancelToken? cancelToken});

// m3u8直播流地址解析器类
class GetM3u8Diy {
  // 解析器映射表，关键字关联对应解析函数
  static final Map<String, ParserFunction> _parsers = {
    'sousuo': SousuoParser.parse,
    'gansu': GansuParser.parse,
    'jinan': JinanParser.parse,
    'xizang': xizangParser.parse,
    'sichuan': SichuanParser.parse,
    'xishui': xishuiParser.parse,
    'yanan': yananParser.parse,
    'foshan': foshanParser.parse,
    'shantou': ShantouParser.parse,
  };

  // 根据URL获取直播流地址，支持取消请求
  static Future<String> getStreamUrl(String url, {CancelToken? cancelToken}) async {
    try {
      // 遍历解析器映射，匹配URL关键字
      for (final key in _parsers.keys) {
        if (url.contains(key)) {
          // 调用匹配的解析器，传递URL和取消令牌
          final result = await _parsers[key]!(url, cancelToken: cancelToken);
          // 记录解析成功的直播流地址
          LogUtil.i('解析结果: $result');
          return result;
        }
      }
      // 无匹配解析器，记录日志并返回错误
      LogUtil.i('未找到匹配的解析规则: $url');
      return 'ERROR';
    } catch (e) {
      // 捕获异常，记录解析失败信息
      LogUtil.i('解析直播流地址失败: $e');
      return 'ERROR';
    }
  }

  // 添加新解析器到映射表
  static void addParser(String keyword, ParserFunction parser) {
    _parsers[keyword] = parser;
  }
}
