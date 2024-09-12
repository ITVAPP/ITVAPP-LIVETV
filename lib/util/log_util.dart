import 'dart:developer' as developer;

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = true; // 控制是否记录日志
  static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间

  // 封装的日志记录方法，增加参数检查并记录堆栈位置
  static void logError(String message, dynamic error, [StackTrace? stackTrace]) {
    if (!debugMode) return; // 如果 debugMode 为 false，不记录日志
    stackTrace ??= StackTrace.current; // 如果堆栈信息为空，使用当前堆栈信息

    // 检查参数是否为空
    if (message == null || error == null) {
      LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    // 记录错误信息和堆栈信息
    final timestamp = DateTime.now().toIso8601String();
    LogUtil.e('[$timestamp] 错误: $message');
    LogUtil.e('错误详情: $error');
    LogUtil.e('堆栈信息: $stackTrace');
  }

  // 安全执行方法，捕获并记录异常
  static void safeExecute(void Function()? action, String errorMessage) {
    if (!debugMode) return; // 如果 debugMode 为 false，不记录日志
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
    if (!debugMode) return;
    _log('v', object, tag);
  }

  static void e(Object? object, {String? tag}) {
    if (!debugMode) return;
    _log('e', object, tag);
  }

  static void i(Object? object, {String? tag}) {
    if (!debugMode) return;
    _log('i', object, tag);
  }

  static void d(Object? object, {String? tag}) {
    if (!debugMode) return;
    _log('d', object, tag);
  }

  // 通用日志记录方法
  static void _log(String level, Object? object, String? tag) {
    if (!debugMode) return;
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
}
