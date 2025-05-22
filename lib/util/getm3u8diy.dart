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

/// 定义解析器函数类型，添加 cancelToken 参数
typedef ParserFunction = Future<String> Function(String url, {CancelToken? cancelToken});

/// m3u8地址解析器
class GetM3u8Diy {
  /// 解析器映射表
  static final Map<String, ParserFunction> _parsers = {
    'sousuo': SousuoParser.parse,
    'gansu': GansuParser.parse,
    'jinan': JinanParser.parse,
    'xizang': xizangParser.parse,
    'sichuan': SichuanParser.parse,
    'xishui': xishuiParser.parse,
    'yanan': yananParser.parse,
    'foshan': foshanParser.parse,
  };

  /// 根据 URL 获取直播流地址，添加 cancelToken 参数
  static Future<String> getStreamUrl(String url, {CancelToken? cancelToken}) async {
    try {
      // 在开始解析前检查取消状态
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('GetM3u8Diy: 任务已取消，停止解析');
        return 'ERROR';
      }

      // 查找匹配的解析器
      for (final key in _parsers.keys) {
        if (url.contains(key)) {
          // 在调用解析器前再次检查取消状态
          if (cancelToken?.isCancelled ?? false) {
            LogUtil.i('GetM3u8Diy: 解析器调用前任务已取消');
            return 'ERROR';
          }

          LogUtil.i('GetM3u8Diy: 使用解析器 $key 解析 URL');
          
          // 传递 cancelToken 给解析器
          final result = await _parsers[key]!(url, cancelToken: cancelToken);
          
          // 解析完成后检查取消状态
          if (cancelToken?.isCancelled ?? false) {
            LogUtil.i('GetM3u8Diy: 解析完成后发现任务已取消');
            return 'ERROR';
          }
          
          // 记录解析结果
          LogUtil.i('GetM3u8Diy: 解析结果: $result');
          return result;
        }
      }
      
      // 如果不符合任何解析规则，记录日志并返回错误信息
      LogUtil.i('GetM3u8Diy: 未找到匹配的解析规则: $url');
      return 'ERROR';
    } catch (e) {
      // 区分取消异常和其他异常
      if (e is DioException && e.type == DioExceptionType.cancel) {
        LogUtil.i('GetM3u8Diy: 解析任务被取消');
        return 'ERROR';
      }
      
      // 捕获解析异常并记录日志
      LogUtil.e('GetM3u8Diy: 解析直播流地址失败: $e');
      return 'ERROR';
    }
  }
  
  /// 添加新的解析器，更新函数签名
  static void addParser(String keyword, ParserFunction parser) {
    _parsers[keyword] = parser;
  }

  /// 获取所有支持的解析器关键字
  static List<String> getSupportedKeywords() {
    return _parsers.keys.toList();
  }

  /// 检查URL是否支持解析
  static bool canParse(String url) {
    return _parsers.keys.any((key) => url.contains(key));
  }
}
