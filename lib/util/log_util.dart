import 'dart:developer';

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool _debugMode = false; // 是否是调试模式，生产环境关闭日志
  static List<String> _errorLogs = []; // 存储错误日志

  // 初始化日志工具
  static void init({
    String tag = _defTag,
    bool isDebug = false,
  }) {
    _debugMode = isDebug;
  }

  // 记录错误日志
  static void e(Object? object, {String? tag}) {
    String error = '${tag ?? _defTag} e | ${object?.toString()}';
    _errorLogs.add(error);
    if (_debugMode) {
      log(error);
    }
  }

  // 获取所有错误日志
  static List<String> getErrorLogs() {
    return _errorLogs;
  }

  // 清空错误日志
  static void clearErrorLogs() {
    _errorLogs.clear();
  }
}
