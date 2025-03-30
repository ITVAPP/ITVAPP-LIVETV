import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../provider/theme_provider.dart';

class LogUtil {
  static const String _defTag = 'common_utils'; // 默认日志标签
  static bool debugMode = true; // 控制是否记录日志，true为开启
  static bool _isOperating = false; // 操作锁，防止并发写文件
  static const int _maxSingleLogLength = 588; // 单条日志最大长度限制
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 日志文件最大5MB

  // 内存存储相关
  static final List<String> _memoryLogs = []; // 内存中的日志列表
  static const int _writeThreshold = 5; // 累积5条日志后写入本地
  static late final String _logFilePath; // 日志文件路径，静态常量缓存
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt'; // 日志文件名

  // 弹窗相关属性
  static bool _showOverlay = false; // 控制弹窗是否显示
  static OverlayEntry? _overlayEntry; // 弹窗的OverlayEntry实例
  static final List<String> _debugMessages = []; // 调试消息列表
  static Timer? _timer; // 弹窗自动隐藏定时器
  static const int _messageDisplayDuration = 3; // 弹窗显示时长（秒）

  static OverlayState? _cachedOverlayState; // 缓存的OverlayState实例

  // 初始化日志工具，应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear(); // 清空内存日志
      final directory = await getApplicationDocumentsDirectory();
      _logFilePath = '${directory.path}/$_logFileName'; // 缓存日志文件路径
      final file = File(_logFilePath);
      if (!await file.exists()) {
        await file.create(); // 创建日志文件
        developer.log('创建日志文件: $_logFilePath');
      } else {
        final int sizeInBytes = await file.length();
        if (sizeInBytes > _maxFileSizeBytes) {
          developer.log('日志文件超过大小限制，执行清理');
          await clearLogs(isAuto: true); // 文件超限时自动清理
        }
      }
    } catch (e) {
      developer.log('日志初始化失败: $e');
      await clearLogs(isAuto: true); // 初始化失败时清理
    }
  }

  // 设置调试模式开关
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
  }

  // 设置是否显示调试弹窗
  static void setShowOverlay(bool show) {
    _showOverlay = show;
    if (!show) _hideOverlay(); // 关闭时隐藏弹窗
  }

  // 从Provider更新调试模式状态
  static void updateDebugModeFromProvider(BuildContext context) {
    try {
      var themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      bool isLogOn = themeProvider.isLogOn;
      setDebugMode(isLogOn); // 根据Provider设置调试模式
    } catch (e) {
      setDebugMode(false); // 读取失败时默认关闭
      print('未能读取到 ThemeProvider，默认关闭日志功能: $e');
    }
  }

  // 记录verbose级别日志
  static Future<void> v(Object? object, {String? tag}) async {
    await _log('v', object, tag);
  }

  // 记录error级别日志
  static Future<void> e(Object? object, {String? tag}) async {
    await _log('e', object, tag);
  }

  // 记录info级别日志
  static Future<void> i(Object? object, {String? tag}) async {
    await _log('i', object, tag);
  }

  // 记录debug级别日志
  static Future<void> d(Object? object, {String? tag}) async {
    await _log('d', object, tag);
  }

  // 处理特殊字符，区分显示和存储格式
  static String _replaceSpecialChars(String input, {bool isDisplay = false}) {
    if (isDisplay) {
      return input // 弹窗显示时还原特殊字符
          .replaceAll('\\n', '\n')
          .replaceAll('\\r', '\r')
          .replaceAll('\\|', '|')
          .replaceAll('\\[', '[')
          .replaceAll('\\]', ']');
    } else {
      return input // 存储时转义特殊字符
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '\\r')
          .replaceAll('|', '\\|')
          .replaceAll('[', '\\[')
          .replaceAll(']', '\\]');
    }
  }

  // 通用的日志记录方法
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString(); // 当前时间戳
      String fileInfo = _getFileAndLine(); // 获取调用位置
      String logMessage = _formatLogMessage(level, object, tag ?? _defTag, time, fileInfo);
      _memoryLogs.add(logMessage); // 添加到内存日志
      if (_memoryLogs.length >= _writeThreshold) {
        Future.microtask(() => _flushToLocal()); // 达到阈值时异步写入
      }
      developer.log(logMessage); // 输出到开发者日志
      if (_showOverlay) {
        String displayMessage = _replaceSpecialChars(object.toString(), isDisplay: true);
        _showDebugMessage('[${level}] $displayMessage | $fileInfo'); // 显示弹窗
      }
    } catch (e) {
      developer.log('日志记录失败: $e');
    }
  }

  // 格式化日志消息
  static String _formatLogMessage(String level, Object? object, String tag, String time, String fileInfo) {
    String objectStr = _replaceSpecialChars(object.toString()) ?? 'null';
    if (objectStr.length > _maxSingleLogLength) {
      objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)'; // 截断超长日志
    }
    return '[${time}] [${level}] [${tag}] | ${objectStr} | ${fileInfo}';
  }

  // 将内存日志写入本地文件
  static Future<void> _flushToLocal() async {
    if (_memoryLogs.isEmpty || _isOperating) return;
    try {
      final file = File(_logFilePath);
      final newLogs = _memoryLogs.toList(); // 复制日志列表
      _isOperating = true; // 加锁保护文件操作
      await file.writeAsString(newLogs.join('\n') + '\n', mode: FileMode.append);
      _memoryLogs.clear(); // 清空内存日志
    } catch (e) {
      developer.log('写入日志文件失败: $e');
    } finally {
      _isOperating = false; // 释放锁
    }
  }

  // 显示调试弹窗消息
  static void _showDebugMessage(String message) {
    String displayMessage = message;
    if (message.contains('|')) {
      final parts = message.split('|').map((s) => s.trim()).toList();
      final headers = parts[0].split(']')
          .map((s) => s.trim().replaceAll('[', ''))
          .where((s) => s.isNotEmpty)
          .toList();
      String timeAndLevel = '${headers[0]}\n';
      String content = parts[1];
      String fileInfo = parts[2];
      displayMessage = '$timeAndLevel$content\n$fileInfo'; // 格式化弹窗内容
    }
    _debugMessages.insert(0, displayMessage); // 插入最新消息
    if (_debugMessages.length > 6) _debugMessages.removeLast(); // 限制消息数量
    final overlayState = _cachedOverlayState ?? _findOverlayState();
    if (overlayState == null) {
      developer.log('无法找到 OverlayState，弹窗显示失败');
      return;
    }
    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          bottom: 20.0,
          right: 20.0,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300.0),
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _debugMessages.map((msg) => Text(
                  msg,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  softWrap: true,
                  maxLines: null,
                  overflow: TextOverflow.visible,
                )).toList(),
              ),
            ),
          ),
        ),
      );
      overlayState.insert(_overlayEntry!); // 创建并插入弹窗
    } else {
      _overlayEntry!.markNeedsBuild(); // 更新现有弹窗
    }
    _startAutoHideTimer(); // 启动自动隐藏
  }

  static final navigatorObserver = NavigatorObserver(); // 导航观察者

  // 查找OverlayState实例
  static OverlayState? _findOverlayState() {
    if (_cachedOverlayState != null && _cachedOverlayState!.mounted) return _cachedOverlayState;
    try {
      if (navigatorObserver.navigator?.overlay != null) {
        _cachedOverlayState = navigatorObserver.navigator?.overlay;
        return _cachedOverlayState;
      }
      Element? rootElement = WidgetsBinding.instance.renderViewElement;
      if (rootElement == null) return null;
      OverlayState? overlayState;
      void visitor(Element element) {
        if (overlayState != null) return;
        if (element is StatefulElement && element.state is OverlayState) {
          overlayState = element.state as OverlayState;
          return;
        }
        element.visitChildren(visitor);
      }
      rootElement.visitChildren(visitor);
      _cachedOverlayState = overlayState;
      return _cachedOverlayState; // 返回找到的OverlayState
    } catch (e) {
      developer.log('获取 OverlayState 失败: $e');
      return null;
    }
  }

  // 隐藏调试弹窗
  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 启动弹窗自动隐藏定时器
  static void _startAutoHideTimer() {
    if (_timer != null && _timer!.isActive) _timer!.cancel(); // 取消现有定时器
    _timer = Timer.periodic(Duration(seconds: _messageDisplayDuration), (timer) {
      if (_debugMessages.isEmpty) {
        _hideOverlay();
        timer.cancel();
        _timer = null;
      } else {
        _debugMessages.removeLast(); // 移除最早的消息
        if (_debugMessages.isEmpty) {
          _hideOverlay();
          timer.cancel();
          _timer = null;
        } else {
          _overlayEntry?.markNeedsBuild(); // 更新弹窗内容
        }
      }
    });
  }

  // 记录错误日志，包含堆栈信息
  static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
    if (!debugMode) return;
    stackTrace ??= StackTrace.current;
    if (message?.isNotEmpty !=  != true || error == null) {
      await LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }
    String fileInfo = _getFileAndLine();
    String time = DateTime.now().toString();
    String logMessage = _formatLogMessage('e', '错误: $message\n错误详情: $error\n堆栈信息: $stackTrace', _defTag, time, fileInfo);
    await _log('e', logMessage, _defTag);
  }

  // 安全执行函数并捕获异常
  static Future<void> safeExecute(void Function()? action, String errorMessage, [StackTrace? stackTrace]) async {
    if (action == null) {
      await logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null', stackTrace ?? StackTrace.current);
      return;
    }
    try {
      action();
    } catch (error, st) {
      await logError(errorMessage, error, st); // 记录执行中的错误
    }
  }

  // 获取调用者的文件和行号信息
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

  // 解析单条日志为键值对
  static Map<String, String> _parseLogEntry(String logStr, [String? level]) {
    final parts = logStr.split('|').map((s) => s.trim()).toList();
    if (parts.length < 3) return {'time': '', 'level': level ?? '', 'tag': '', 'message': parts.length > 1 ? parts[1] : logStr, 'fileInfo': ''};
    final headers = parts[0].split(']')
        .map((s) => s.trim().replaceAll('[', ''))
        .where((s) => s.isNotEmpty)
        .toList();
    return {
      'time': headers.length > 0 ? headers[0] : '',
      'level': headers.length > 1 ? headers[1] : '',
      'tag': headers.length > 2 ? headers[2] : '',
      'message': parts[1],
      'fileInfo': parts[2],
    };
  }

  // 获取所有内存中的日志
  static List<Map<String, String>> getLogs() {
    try {
      return _memoryLogs.map((logStr) => _parseLogEntry(logStr)).toList();
    } catch (e) {
      developer.log('获取日志失败: $e');
      return [];
    }
  }

  // 按级别获取内存中的日志
  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      final levelPattern = RegExp(r'\[' + RegExp.escape(level) + r'\]');
      return _memoryLogs
          .where((log) => levelPattern.hasMatch(log))
          .map((logStr) => _parseLogEntry(logStr, level))
          .toList();
    } catch (e) {
      developer.log('按级别获取日志失败: $e');
      return [];
    }
  }

  // 清理日志，可按级别或全部清理
  static Future<void> clearLogs({String? level, bool isAuto = false}) async {
    if (_isOperating) return;
    _isOperating = true;
    try {
      final file = File(_logFilePath);
      if (level == null) {
        _memoryLogs.clear(); // 清空内存日志
        if (await file.exists()) {
          if (isAuto) {
            final lines = await file.readAsLines();
            if (lines.isNotEmpty) {
              final endIndex = lines.length ~/ 2;
              final remainingLogs = lines.sublist(0, endIndex);
              await file.writeAsString(remainingLogs.join('\n') + '\n'); // 保留一半日志
            }
          } else {
            await file.delete(); // 手动清理时删除文件
          }
        }
      } else {
        final levelPattern = RegExp(r'\[' + RegExp.escape(level) + r'\]');
        _memoryLogs.removeWhere((log) => levelPattern.hasMatch(log)); // 移除指定级别日志
        if (await file.exists()) {
          await file.writeAsString(_memoryLogs.join('\n') + '\n');
        }
      }
    } catch (e) {
      developer.log('${level == null ? (isAuto ? "自动" : "手动") : "按级别"}清理日志失败: $e');
    } finally {
      _isOperating = false;
    }
  }

  // 解析日志消息内容
  static String parseLogMessage(String logLine) {
    try {
      final parts = logLine.split('|');
      if (parts.length >= 2) return parts[1].trim();
    } catch (e) {
      developer.log('解析日志消息失败: $e');
    }
    return logLine;
  }

  // 释放资源，清理未写入的日志
  static Future<void> dispose() async {
    if (!_isOperating && _memoryLogs.isNotEmpty) {
      await _flushToLocal(); // 写入剩余日志
    }
    _timer?.cancel();
    _timer = null;
    _hideOverlay(); // 隐藏弹窗
  }
}
