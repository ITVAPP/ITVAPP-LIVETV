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
    // 先检查取消状态
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，跳过解析: $url');
      return 'ERROR';
    }
    
    // 对URL进行基本检查
    if (url.isEmpty) {
      LogUtil.i('URL为空，返回ERROR');
      return 'ERROR';
    }
    
    // 查找匹配的解析器
    for (final key in _parsers.keys) {
      if (url.contains(key)) {
        try {
          // 再次检查取消状态
          if (cancelToken?.isCancelled ?? false) {
            LogUtil.i('任务已取消，跳过解析器: $key');
            return 'ERROR';
          }
          
          LogUtil.i('选择解析器: $key, URL: $url');
          
          // 传递 cancelToken 给解析器
          final result = await _parsers[key]!(url, cancelToken: cancelToken);
          
          // 解析完成后再次检查取消状态
          if (cancelToken?.isCancelled ?? false) {
            LogUtil.i('解析完成但任务已取消: $url');
            return 'ERROR';
          }
          
          return result;
        } catch (e) {
          // 检查是否因取消而抛出异常
          if (cancelToken?.isCancelled ?? false) {
            LogUtil.i('解析器执行被取消: $key');
            return 'ERROR';
          }
          
          LogUtil.e('解析器 $key 执行失败: $e');
          // 重新抛出以便外层捕获
          throw e;
        }
      }
    }
    
    // 如果不符合任何解析规则，记录日志并返回错误信息
    LogUtil.i('未找到匹配的解析规则: $url');
    return 'ERROR';
  } catch (e) {
    // 捕获解析异常并记录日志
    if (!(cancelToken?.isCancelled ?? false)) {
      LogUtil.i('解析直播流地址失败: $e');
    }
    return 'ERROR';
  }
}
  
  /// 添加新的解析器，更新函数签名
  static void addParser(String keyword, ParserFunction parser) {
    _parsers[keyword] = parser;
  }
}
