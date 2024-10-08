import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = false; // 控制是否记录日志 true 或 false
  static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间
  static const int _maxLogs = 800; // 设置最大日志条目数

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

    _log('e', '错误: $message\n错误详情: $error\n堆栈信息: ${_processStackTrace(stackTrace)}', _defTag);
  }

  // 安全执行方法，捕获并记录异常
  static void safeExecute(void Function()? action, String errorMessage, [StackTrace? stackTrace]) {
    if (action == null) {
      logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null', stackTrace ?? StackTrace.current);
      return;
    }

    try {
      action(); // 执行传入的函数
    } catch (error, st) {
      logError(errorMessage, error, st); // 捕获并记录异常
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

    try {
      String time = DateTime.now().toString();
      String fileInfo = _getFileAndLine(); // 获取文件和行号信息
      // 安全处理 object，避免出现 null 值导致错误
      String logMessage = '${tag ?? _defTag} $level | ${object?.toString() ?? 'null'}\n$fileInfo';

      // 限制日志的数量，如果超过最大数量，则移除最旧的日志
      if (_logs.length >= _maxLogs) {
        _logs.removeAt(0); // 移除最旧的一条日志
      }

      _logs.add({'time': time, 'level': level, 'message': logMessage});
      developer.log(logMessage);
    } catch (e) {
      developer.log('日志记录时发生异常: $e'); // 捕获日志记录中的异常并记录
    }
  }

  // 获取文件名和行号，记录 frames
  static String _getFileAndLine() {
    try {
      final frames = StackTrace.current.toString().split('\n');

      // 记录 frames 到日志
      String frameInfo = frames.join('\n'); // 将 frames 转换为字符串
      developer.log('堆栈信息:\n$frameInfo'); // 记录到日志

      // 从第三帧开始遍历堆栈信息，尝试找到业务代码相关的文件名和行号
      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i]; // 获取当前帧

        // 修改后的正则表达式，忽略列号，只捕获文件名和行号
        final match = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);

        // 过滤掉与 LogUtil 相关的堆栈帧
        if (match != null && !frame.contains('log_util.dart')) {
          // 返回捕获到的文件名和行号
          return '${match.group(1)}:${match.group(2)}';
        }
      }
    } catch (e) {
      return 'Unknown'; // 捕获任何异常，避免日志记录失败
    }
    return 'Unknown';
  }

  // 提取和处理堆栈信息，过滤掉无关帧
  static String _processStackTrace(StackTrace stackTrace) {
    try {
      final frames = stackTrace.toString().split('\n');
      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i];

        // 忽略 log_util.dart 中的堆栈信息
        final match = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);
        if (match != null && !frame.contains('log_util.dart')) {
          return '${match.group(1)}:${match.group(2)}'; // 返回业务代码文件和行号
        }
      }
    } catch (e) {
      return 'Unknown'; // 捕获任何异常，避免日志记录失败
    }

    return 'Unknown';
  }

  // 获取所有日志
  static List<Map<String, String>> getLogs() {
    return _logs;
  }

  // 获取指定类型的日志
  static List<Map<String, String>> getLogsByLevel(String level) {
    return _logs.where((log) => log['level'] == level).toList();
  }

  // 清空日志，支持传入参数来清空特定类型的日志
  static void clearLogs([String? level]) {
    if (level == null) {
      _logs.clear(); // 清空所有日志
    } else {
      _logs.removeWhere((log) => log['level'] == level); // 清空特定类型的日志
    }
  }

  // 解析日志消息，展示实际内容时只提取消息部分，保留文件和行号信息
  static String parseLogMessage(String message) {
    // 按 '|' 分割，返回第二部分，即实际的日志内容和文件名行号
    List<String> parts = message.split('|');
    if (parts.length >= 2) {
      return parts[1].trim(); // 保留文件名和行号信息
    }
    return message; // 如果日志格式不符，返回原始信息
  }
}
