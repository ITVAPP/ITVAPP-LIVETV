import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../provider/theme_provider.dart';

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = true; // 控制是否记录日志 true 或 false
  static bool _isOperating = false; // 添加操作锁，防止并发问题
  static const int _maxSingleLogLength = 500; // 添加单条日志最大长度限制
  static const int _maxFileSizeBytes = 3 * 1024 * 1024; // 最大日志限制3MB

  // 内存存储相关
  static final List<String> _memoryLogs = [];
  static final List<String> _newLogsBuffer = [];
  static const int _writeThreshold = 5;  // 累积5条日志才写入本地
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt';  // 日志文件名
  static String? _logFilePath;  // 缓存日志文件路径

  // 弹窗相关属性
  static bool _showOverlay = true; // 控制是否显示弹窗
  static OverlayEntry? _overlayEntry;  // 修改为单个 OverlayEntry
  static final List<String> _debugMessages = [];
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear();  // 初始化时先清空内存
      _newLogsBuffer.clear();  // 初始化时先清空缓冲区

      final filePath = await _getLogFilePath();
      final file = File(filePath);

      if (!await file.exists()) {
        await file.create();
        developer.log('创建日志文件: $filePath');
      } else {
        final int sizeInBytes = await file.length();
        if (sizeInBytes > _maxFileSizeBytes) {
          developer.log('日志文件超过大小限制，执行清理');
          await clearLogs(isAuto: true);  // 修改为命名参数
        } else {
          await _loadLogsFromLocal();
        }
      }
    } catch (e) {
      developer.log('日志初始化失败: $e');
      await clearLogs(isAuto: true);  // 修改为命名参数
    }
  }

  // 获取日志文件路径
  static Future<String> _getLogFilePath() async {
    if (_logFilePath != null) return _logFilePath!;
    final directory = await getApplicationDocumentsDirectory();
    _logFilePath = '${directory.path}/$_logFileName';
    return _logFilePath!;
  }

  // 从本地文件加载日志
  static Future<void> _loadLogsFromLocal() async {
    if (_isOperating) return;
    _isOperating = true;

    try {
      final filePath = await _getLogFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        final String content = await file.readAsString();
        if (content.isNotEmpty) {
          _memoryLogs.clear();
          _memoryLogs.addAll(content.split('\n').where((line) => line.isNotEmpty));
        }
      }
    } catch (e) {
      developer.log('从文件加载日志失败: $e');
    } finally {
      _isOperating = false;
    }
  }

  // 设置调试模式
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
  }

  // 设置是否显示弹窗
  static void setShowOverlay(bool show) {
    _showOverlay = show;
    if (!show) {
      _hideOverlay();
    }
  }

  // 从Provider更新调试模式
  static void updateDebugModeFromProvider(BuildContext context) {
    try {
      var themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      bool isLogOn = themeProvider.isLogOn;
      setDebugMode(isLogOn);
    } catch (e) {
      setDebugMode(false);
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

  // 记录日志的通用方法
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString();
      String fileInfo = _getFileAndLine();

      String objectStr = object?.toString()
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('|', '\\|')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        ?? 'null';

      if (objectStr.length > _maxSingleLogLength) {
        objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)';
      }

      String logMessage = '[${time}] [${level}] [${tag ?? _defTag}] | ${objectStr} | ${fileInfo}';

      // 添加到内存和缓冲区（新日志在前）
      _memoryLogs.insert(0, logMessage);
      _newLogsBuffer.insert(0, logMessage);

      if (_newLogsBuffer.length >= _writeThreshold) {
        await _flushToLocal();
      }

      developer.log(logMessage);
      if (_showOverlay) {
        String displayMessage = objectStr
          .replaceAll('\\n', '\n')
          .replaceAll('\\r', '\r')
          .replaceAll('\\|', '|')
          .replaceAll('\\[', '[')
          .replaceAll('\\]', ']');

        _showDebugMessage('[${level}] $displayMessage');
      }
    } catch (e) {
      developer.log('日志记录失败: $e');
    }
  }

  // 将日志写入本地文件
  static Future<void> _flushToLocal() async {
    if (_newLogsBuffer.isEmpty || _isOperating) return;
    _isOperating = true;
    List<String> logsToWrite = [];
    try {
      logsToWrite = List.from(_newLogsBuffer);
      _newLogsBuffer.clear();

      final filePath = await _getLogFilePath();
      final file = File(filePath);

      await file.writeAsString(_memoryLogs.join('\n') + '\n');

    } catch (e) {
      developer.log('写入日志文件失败: $e');
      _newLogsBuffer.insertAll(0, logsToWrite);
    } finally {
      _isOperating = false;
    }
  }

  // 显示调试消息
  static void _showDebugMessage(String message) {
    _debugMessages.insert(0, message);
    if (_debugMessages.length > 6) {
      _debugMessages.removeLast();
    }

    _hideOverlay();

    final overlayState = _findOverlayState();
    if (overlayState != null) {
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
                  overflow: TextOverflow.visible,  // 修改这里从 TextOverlay 到 TextOverflow
                )).toList(),
              ),
            ),
          ),
        ),
      );

      overlayState.insert(_overlayEntry!);
      _startAutoHideTimer();
    }
  }

  // NavigatorObserver实例
  static final navigatorObserver = NavigatorObserver();

  // 查找OverlayState
  static OverlayState? _findOverlayState() {
    try {
      if (navigatorObserver.navigator?.overlay != null) {
        return navigatorObserver.navigator?.overlay;
      }

      Element? rootElement = WidgetsBinding.instance.renderViewElement;
      if (rootElement == null) return null;

      OverlayState? overlayState;
      void visitor(Element element) {
        if (overlayState != null) return;
        if (element is StatefulElement &&
            element.state is OverlayState) {
          overlayState = element.state as OverlayState;
          return;
        }
        element.visitChildren(visitor);
      }
      rootElement.visitChildren(visitor);

      return overlayState;
    } catch (e) {
      developer.log('获取 OverlayState 失败: $e');
      return null;
    }
  }
  
  // 隐藏弹窗
  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 启动自动隐藏计时器
  static void _startAutoHideTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _messageDisplayDuration), (timer) {
      if (_debugMessages.isEmpty) {
        _hideOverlay();
        _timer?.cancel();
        _timer = null;
      } else {
        _debugMessages.removeLast();
        if (_debugMessages.isEmpty) {
          _hideOverlay();
          _timer?.cancel();
          _timer = null;
        } else {
          _overlayEntry?.markNeedsBuild();
        }
      }
    });
  }

  // 记录错误日志
  static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
    if (!debugMode) return;

    stackTrace ??= StackTrace.current;

    if (message?.isNotEmpty != true || error == null) {
      await LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    await _log('e', '错误: $message\n错误详情: $error\n堆栈信息: ${_processStackTrace(stackTrace)}', _defTag);
  }

  // 安全执行函数
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

  // 处理堆栈信息
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
  static List<Map<String, String>> getLogs() {  // 修改返回类型
    try {
      return _memoryLogs.map((logStr) {
        final parts = logStr.split('|').map((s) => s.trim()).toList();
        final headers = parts[0].split(']')
            .map((s) => s.trim().replaceAll('[', ''))
            .where((s) => s.isNotEmpty)
            .toList();
        
        return {
          'time': headers[0],
          'level': headers[1],
          'tag': headers[2],
          'message': parts[1],
          'fileInfo': parts[2]
        };
      }).toList();
    } catch (e) {
      developer.log('获取日志失败: $e');
      return [];
    }
  }

  // 按级别获取日志
  static List<Map<String, String>> getLogsByLevel(String level) {  // 修改返回类型
    try {
      final levelPattern = RegExp(r'\[' + level + r'\]');
      return _memoryLogs
          .where((log) => levelPattern.hasMatch(log))
          .map((logStr) {
        final parts = logStr.split('|').map((s) => s.trim()).toList();
        final headers = parts[0].split(']')
            .map((s) => s.trim().replaceAll('[', ''))
            .where((s) => s.isNotEmpty)
            .toList();
        
        return {
          'time': headers[0],
          'level': headers[1],
          'tag': headers[2],
          'message': parts[1],
          'fileInfo': parts[2]
        };
      }).toList();
    } catch (e) {
      developer.log('按级别获取日志失败: $e');
      return [];
    }
  }

  // 清理日志
  static Future<void> clearLogs({String? level, bool isAuto = false}) async {
    if (_isOperating) return;
    _isOperating = true;
    
    try {
      final filePath = await _getLogFilePath();
      final file = File(filePath);
      
      if (level == null) {
        // 清理所有日志
        _memoryLogs.clear();
        _newLogsBuffer.clear();
        
        if (await file.exists()) {
          if (isAuto) {
            // 自动清理时保留前半部分
            final lines = await file.readAsLines();
            if (lines.isNotEmpty) {
              final endIndex = lines.length ~/ 2;
              final remainingLogs = lines.sublist(0, endIndex);
              await file.writeAsString(remainingLogs.join('\n') + '\n');
            }
          } else {
            // 手动清理时直接删除
            await file.delete();
          }
        }
      } else {
        // 清理指定级别的日志
        final levelPattern = RegExp(r'\[' + level + r'\]');
        _memoryLogs.removeWhere((log) => levelPattern.hasMatch(log));
        _newLogsBuffer.removeWhere((log) => levelPattern.hasMatch(log));
        
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

  // 解析日志消息
  static String parseLogMessage(String logLine) {
    try {
      final parts = logLine.split('|');
      if (parts.length >= 2) {
        return parts[1].trim();
      }
    } catch (e) {
      developer.log('解析日志消息失败: $e');
    }
    return logLine;
  }

  // 释放资源
  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
  }
}
