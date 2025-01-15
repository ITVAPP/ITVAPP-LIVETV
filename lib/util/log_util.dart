import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import '../provider/theme_provider.dart';

class _DebugOverlayWidget extends StatefulWidget {
  final String message;
  final VoidCallback? onDismiss;

  const _DebugOverlayWidget({
    Key? key,
    required this.message,
    this.onDismiss,
  }) : super(key: key);

  @override
  _DebugOverlayWidgetState createState() => _DebugOverlayWidgetState();
}

class _DebugOverlayWidgetState extends State<_DebugOverlayWidget> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        alignment: Alignment.bottomRight,
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = true; // 控制是否记录日志 true 或 false
  static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间
  static const int _maxLogs = 300; // 设置最大日志条目数
  static const int _maxSingleLogLength = 500; // 添加单条日志最大长度限制
  static const String _logsKey = 'ITVAPP_LIVETV_logs'; // 持久化存储的key

  // 弹窗相关属性
  static bool _showOverlay = true; // 控制是否显示弹窗
  static OverlayEntry? _overlayEntry;
  static final List<String> _debugMessages = [];
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    await SpUtil.getInstance();
    await _loadLogsFromStorage(); // 等待日志加载完成
  }

  // 从持久化存储加载日志
  static Future<void> _loadLogsFromStorage() async {
    try {
      final String? logsStr = SpUtil.getString(_logsKey);  
      if (logsStr != null && logsStr.isNotEmpty) {
        final List<dynamic> logsList = json.decode(logsStr);
        _logs = logsList.map((log) => Map<String, String>.from(log)).toList();
      }
    } catch (e) {
      developer.log('加载持久化日志失败: $e');
      // 加载失败时不清空内存中的日志
      if (_logs.isEmpty) {
        _logs = [];  // 只有在内存也为空时才初始化
      }
    }
  }

  // 保存日志到持久化存储
  static Future<void> _saveLogsToStorage() async {
    try {
      final String logsStr = json.encode(_logs);
      await SpUtil.putString(_logsKey, logsStr);  // putString 会自动保存
    } catch (e) {
      developer.log('保存日志到持久化存储失败: $e');
    }
  }

  // 设置 debugMode 状态，供外部调用
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
    if (!isEnabled) {
      //  clearLogs(); // 如果关闭日志记录，则清空已有日志
    }
  }

  // 设置是否显示弹窗
  static void setShowOverlay(bool show) {
    _showOverlay = show;
    if (!show) {
      _hideOverlay();
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

  // 记录不同类型的日志
  static Future<void> v(Object? object, {String? tag}) async {
    await _log('v', object, tag);
  }

  static Future<void> e(Object? object, {String? tag}) async {
    await _log('e', object, tag);
  }

  static Future<void> i(Object? object, {String? tag}) async {
    await _log('i', object, tag);
  }

  static Future<void> d(Object? object, {String? tag}) async {
    await _log('d', object, tag);
  }

  // 通用日志记录方法
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;

    try {
      String time = DateTime.now().toString();
      String fileInfo = _getFileAndLine();
      
      String objectStr = object?.toString() ?? 'null';
      if (objectStr.length > _maxSingleLogLength) {
        objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)';
      }
      String logMessage = '${tag ?? _defTag} $level | $objectStr\n$fileInfo';

      if (_logs.length >= _maxLogs) {
        _logs.removeAt(0);
      }

      _logs.add({'time': time, 'level': level, 'message': logMessage});
      await _saveLogsToStorage();
      developer.log(logMessage);

      if (_showOverlay) {
        _showDebugMessage('[$level] $objectStr');
      }
    } catch (e) {
      developer.log('日志记录时发生异常: $e');
    }
  }

  // 显示调试信息
  static void _showDebugMessage(String message) {
    _debugMessages.add(message);
    if (_debugMessages.length > 6) {
      _debugMessages.removeAt(0);
    }

    _hideOverlay();

    final overlayState = _findOverlayState();
    if (overlayState != null) {
      _overlayEntry = OverlayEntry(
        builder: (context) => _DebugOverlayWidget(
          message: _debugMessages.join('\n'),
          onDismiss: () => _hideOverlay(),
        ),
      );
      overlayState.insert(_overlayEntry!);

      _startAutoHideTimer();
    }
  }

  // 查找有效的 OverlayState
  static OverlayState? _findOverlayState() {
    final navigator = Navigator.maybeOf(WidgetsBinding.instance.rootElement as BuildContext);
    return navigator?.overlay;
  }

  // 隐藏调试弹窗
  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 启动自动隐藏计时器
  static void _startAutoHideTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _messageDisplayDuration), () {
      if (_debugMessages.isNotEmpty) {
        _debugMessages.removeAt(0);
        if (_debugMessages.isEmpty) {
          _hideOverlay();
        } else {
          _overlayEntry?.markNeedsBuild();
        }
      }
      _timer = null;
    });
  }

  // 获取文件名和行号
  static String _getFileAndLine() {
    try {
      final frames = StackTrace.current.toString().split('\n');
      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i];
        final match = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);
        if (match != null && !frame.contains('log_util.dart')) {
          return '${match.group(1)}:${match.group(2)}';
        }
      }
    } catch (e) {
      return 'Unknown';
    }
    return 'Unknown';
  }

  // 提取和处理堆栈信息
  static String _processStackTrace(StackTrace stackTrace) {
    try {
      final frames = stackTrace.toString().split('\n');
      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i];
        final match = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);
        if (match != null && !frame.contains('log_util.dart')) {
          return '${match.group(1)}:${match.group(2)}';
        }
      }
    } catch (e) {
      return 'Unknown';
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

  // 清空日志
  static Future<void> clearLogs([String? level]) async {
    if (level == null) {
      _logs.clear();
    } else {
      _logs.removeWhere((log) => log['level'] == level);
    }
    await _saveLogsToStorage();
  }

  // 解析日志消息
  static String parseLogMessage(String message) {
    List<String> parts = message.split('|');
    if (parts.length >= 2) {
      return parts[1].trim();
    }
    return message;
  }

  // 封装的日志记录方法
  static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
    if (!debugMode) return;

    stackTrace ??= StackTrace.current;

    if (message?.isNotEmpty != true || error == null) {
      await LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    await _log('e', '错误: $message\n错误详情: $error\n堆栈信息: ${_processStackTrace(stackTrace)}', _defTag);
  }

  // 安全执行方法
  static Future<void> safeExecute(void Function()? action, String errorMessage, [StackTrace? stackTrace]) async {
    if (action == null) {
      await logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null', stackTrace ?? StackTrace.current);
      return;
    }

    try {
      action();
    } catch (error, st) {
      await logError(errorMessage, error, st);
    }
  }
}
