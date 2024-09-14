import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart'; // 引入 ThemeProvider

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = false; // 控制是否记录日志 true 或 false
  static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间
  static const int _maxLogs = 500; // 设置最大日志条目数

  // 设置 debugMode 状态，供外部调用
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
    if (!isEnabled) {
      clearLogs(); // 如果关闭日志记录，则清空已有日志
    }
  }

  // 通过 Provider 来获取 isLogOn 并设置 debugMode
  static void updateDebugModeFromProvider(BuildContext context) {
    try {
      var themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      bool isLogOn = themeProvider.isLogOn; // 获取日志开关状态
      setDebugMode(isLogOn);
    } catch (e) {
      setDebugMode(false); // 如果 Provider 获取失败，默认关闭日志
      print('未能读取到 ThemeProvider，默认关闭日志功能: $e');
    }
  }

  // 封装的日志记录方法，增加参数检查并记录堆栈位置
  static void logError(String message, dynamic error, [StackTrace? stackTrace]) {
    if (!debugMode) return; // 如果 debugMode 为 false，不记录日志

    stackTrace ??= StackTrace.current; // 使用当前堆栈信息

    if (message?.isNotEmpty != true || error == null) {
      LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    LogUtil.e('[$timestamp] 错误: $message');
    LogUtil.e('错误详情: $error');
    LogUtil.e('堆栈信息: $stackTrace');
  }

  // 安全执行方法，捕获并记录异常
  static void safeExecute(void Function()? action, String errorMessage) {
    if (action == null) {
      logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null', StackTrace.current);
      return;
    }

    try {
      action(); // 执行传入的函数
    } catch (error, stackTrace) {
      logError(errorMessage, error, stackTrace); // 捕获并记录异常
    }
  }

  // 记录不同类型的日志
  static void v(Object? object, {String? tag}) {
    _log('v', object, tag);
  }

  static void e(Object? object, {String? tag}) {
    _log('e', object, tag);
  }

  static void i(Object? object, {String? tag}) {
    _log('i', object, tag);
  }

  static void d(Object? object, {String? tag}) {
    _log('d', object, tag);
  }

  // 通用日志记录方法，日志记录受 debugMode 控制
  static void _log(String level, Object? object, String? tag) {
    if (!debugMode || object == null) return;

    String time = DateTime.now().toString();
    String logMessage = '${tag ?? _defTag} $level | ${object.toString()}';

    // 限制日志的数量，如果超过最大数量，则移除最旧的日志
    if (_logs.length >= _maxLogs) {
      _logs.removeAt(0); // 移除最旧的一条日志
    }

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
}
