import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';  // 假设你已经在使用 Flutter

class LogUtil {
  static const String _defTag = 'common_utils';
  static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间

  // 通过 ThemeProvider 动态获取 debugMode
  static bool getDebugMode(BuildContext context) {
    return Provider.of<ThemeProvider>(context, listen: false).isLogOn;
  }

  // 封装的日志记录方法，增加参数检查并记录堆栈位置
  static void logError(BuildContext context, String message, dynamic error, [StackTrace? stackTrace]) {
    if (!getDebugMode(context)) return; // 通过 ThemeProvider 获取日志开关

    // 使用当前堆栈信息
    stackTrace ??= StackTrace.current; 

    // 参数检查
    if (message?.isNotEmpty != true || error == null) {
      LogUtil.e(context, '参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    // 记录错误信息
    final timestamp = DateTime.now().toIso8601String();
    LogUtil.e(context, '[$timestamp] 错误: $message');
    LogUtil.e(context, '错误详情: $error');
    LogUtil.e(context, '堆栈信息: $stackTrace');
  }

  // 安全执行方法，捕获并记录异常
  static void safeExecute(BuildContext context, void Function()? action, String errorMessage) {
    if (!getDebugMode(context)) return; // 通过 ThemeProvider 获取日志开关
    if (action == null) {
      logError(context, '$errorMessage - 函数调用时参数为空或不匹配', 'action is null', StackTrace.current);
      return;
    }

    try {
      action(); // 执行传入的函数
    } catch (error, stackTrace) {
      logError(context, errorMessage, error, stackTrace); // 捕获并记录异常
    }
  }

  // 记录不同类型的日志
  static void v(BuildContext context, Object? object, {String? tag}) {
    if (!getDebugMode(context)) return;
    _log(context, 'v', object, tag);
  }

  static void e(BuildContext context, Object? object, {String? tag}) {
    if (!getDebugMode(context)) return;
    _log(context, 'e', object, tag);
  }

  static void i(BuildContext context, Object? object, {String? tag}) {
    if (!getDebugMode(context)) return;
    _log(context, 'i', object, tag);
  }

  static void d(BuildContext context, Object? object, {String? tag}) {
    if (!getDebugMode(context)) return;
    _log(context, 'd', object, tag);
  }

  // 通用日志记录方法
  static void _log(BuildContext context, String level, Object? object, String? tag) {
    if (!getDebugMode(context)) return;
    if (object == null) return;
    String time = DateTime.now().toString();
    String logMessage = '${tag ?? _defTag} $level | ${object.toString()}';
    _logs.add({'time': time, 'level': level, 'message': logMessage});
    developer.log(logMessage);
  }

  // 获取所有日志
  static List<Map<String, String>> getLogs() {
    return _logs;
  }

  // 获取指定类型的日志
  static List<Map<String, String>> getLogsByLevel(String level) {
    return _logs.where((log) => log['level'] == level).toList();
  }

  // 清空日志
  static void clearLogs() {
    _logs.clear();
  }

  // 设置 debugMode 状态，仍然保留供外部调用
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
    if (!isEnabled) {
      clearLogs(); // 如果关闭日志记录，则清空已有日志
    }
  }
}
