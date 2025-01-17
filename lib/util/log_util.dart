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
  static final List<Map<String, String>> _memoryLogs = [];
  static final List<Map<String, String>> _newLogsBuffer = [];
  static const int _writeThreshold = 5;  // 累积5条日志才写入本地
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt';  // 日志文件名
  static String? _logFilePath;  // 缓存日志文件路径

  // 弹窗相关属性
  static bool _showOverlay = true; // 控制是否显示弹窗
  static OverlayEntry? _overlayEntry;  // 修改为单个 OverlayEntry
  static final List<String> _debugMessages = [];
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;

  // 新增：直接记录日志的方法，跳过递归检查
  static Future<void> _logDirect(String level, String message, String tag) async {
    if (!debugMode) return;
    
    try {
      String time = DateTime.now().toString();
      String fileInfo = _getFileAndLine();

      Map<String, String> logEntry = {
        'time': time,
        'level': level,
        'message': message,
        'tag': tag,
        'fileInfo': fileInfo
      };

      _memoryLogs.insert(0, logEntry);
      _newLogsBuffer.insert(0, logEntry);

      if (_newLogsBuffer.length >= _writeThreshold) {
        await _flushToLocal();
      }

      if (_showOverlay) {
        _showDebugMessage('[$level] $message');
      }
    } catch (e) {
      developer.log('LogUtil内部错误: $e');
    }
  }

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear();
      _newLogsBuffer.clear();

      final filePath = await _getLogFilePath();
      final file = File(filePath);

      if (!await file.exists()) {
        await file.create();
        await _logDirect('i', '创建日志文件: $filePath', 'LogUtil');
      } else {
        final int sizeInBytes = await file.length();
        if (sizeInBytes > _maxFileSizeBytes) {
          await _logDirect('i', '日志文件超过大小限制，执行清理', 'LogUtil');
          await _clearLogs();
        } else {
          await _loadLogsFromLocal();
        }
      }
    } catch (e) {
      await _logDirect('e', '日志初始化失败: $e', 'LogUtil');
      await _clearLogs();
    }
  }

  // 通用日志记录方法
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString();
      String fileInfo = _getFileAndLine();

      String objectStr = object.toString()
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('|', '\\|')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');

      if (objectStr.length > _maxSingleLogLength) {
        objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)';
      }

      Map<String, String> logEntry = {
        'time': time,
        'level': level,
        'message': objectStr,
        'tag': tag ?? _defTag,
        'fileInfo': fileInfo
      };

      _memoryLogs.insert(0, logEntry);
      _newLogsBuffer.insert(0, logEntry);

      if (_newLogsBuffer.length >= _writeThreshold) {
        await _flushToLocal();
      }

      if (_showOverlay) {
        String displayMessage = objectStr
          .replaceAll('\\n', '\n')
          .replaceAll('\\r', '\r')
          .replaceAll('\\|', '|')
          .replaceAll('\\[', '[')
          .replaceAll('\\]', ']');

        _showDebugMessage('[$level] $displayMessage');
      }
    } catch (e) {
      developer.log('日志记录失败: $e');
    }
  }
  
  // 从本地加载日志到内存
  static Future<void> _loadLogsFromLocal() async {
    try {
      await _logDirect('i', '开始从本地加载历史日志', 'LogUtil');
      final filePath = await _getLogFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        final String content = await file.readAsString();
        await _logDirect('i', '读取到历史日志文件，内容大小: ${content.length}', 'LogUtil');

        if (content.isNotEmpty) {
          final List<Map<String, String>> logs = [];
          int successCount = 0;
          int failCount = 0;

          final lines = content.split('\n').where((line) => line.isNotEmpty);
          for (final line in lines) {
            try {
              final parts = line.split('|').map((s) => s.trim()).toList();
              if (parts.length == 3) {
                final headers = parts[0].split(']')
                    .map((s) => s.trim().replaceAll('[', ''))
                    .where((s) => s.isNotEmpty)
                    .toList();

                if (headers.length == 3) {
                  String message = parts[1]
                    .replaceAll('\\n', '\n')
                    .replaceAll('\\r', '\r')
                    .replaceAll('\\|', '|')
                    .replaceAll('\\[', '[')
                    .replaceAll('\\]', ']');

                  logs.add({
                    'time': headers[0],
                    'level': headers[1],
                    'tag': headers[2],
                    'message': message,
                    'fileInfo': parts[2]
                  });
                  successCount++;
                } else {
                  failCount++;
                  await _logDirect('e', '解析日志行头部失败，headers长度错误: ${headers.length}, line: $line', 'LogUtil');
                }
              } else {
                failCount++;
                await _logDirect('e', '解析日志行失败，parts长度错误: ${parts.length}, line: $line', 'LogUtil');
              }
            } catch (error) {
              failCount++;
              await _logDirect('e', '解析日志行异常: $line, 错误: $error', 'LogUtil');
            }
          }

          await _logDirect('i', '历史日志解析完成 - 成功: $successCount, 失败: $failCount', 'LogUtil');
          
          _memoryLogs.clear();
          _memoryLogs.addAll(logs.reversed);
          await _logDirect('i', '历史日志加载到内存完成，共${_memoryLogs.length}条', 'LogUtil');
        } else {
          await _logDirect('i', '历史日志文件为空', 'LogUtil');
        }
      } else {
        await _logDirect('i', '历史日志文件不存在', 'LogUtil');
      }
    } catch (error) {
      await _logDirect('e', '从文件加载历史日志失败: $error', 'LogUtil');
    }
  }

  // 获取日志文件路径
  static Future<String> _getLogFilePath() async {
    if (_logFilePath != null) return _logFilePath!;

    final directory = await getApplicationDocumentsDirectory();
    _logFilePath = '${directory.path}/$_logFileName';
    return _logFilePath!;
  }

  // 将缓冲区的日志写入本地
  static Future<void> _flushToLocal() async {
    if (_newLogsBuffer.isEmpty || _isOperating) return;
    _isOperating = true;
    List<Map<String, String>> logsToWrite = [];
    try {
      logsToWrite = List.from(_newLogsBuffer);
      _newLogsBuffer.clear();

      final filePath = await _getLogFilePath();
      final file = File(filePath);

      String content = logsToWrite.map((log) =>
        '[${log["time"]}] [${log["level"]}] [${log["tag"]}] | ${log["message"]} | ${log["fileInfo"]}'
      ).join('\n');

      await file.writeAsString(
        content + '\n',
        mode: FileMode.append,
      );

    } catch (e) {
      await _logDirect('e', '写入日志文件失败: $e', 'LogUtil');
      _newLogsBuffer.insertAll(0, logsToWrite);
    } finally {
      _isOperating = false;
    }
  }

  // 检查并处理日志文件大小
  static Future<void> _checkAndHandleLogSize() async {
    try {
      final filePath = await _getLogFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        final int sizeInBytes = await file.length();
        if (sizeInBytes > _maxFileSizeBytes) {
          await _logDirect('i', '日志文件大小超过限制，执行清理', 'LogUtil');
          await _clearLogs();
        }
      }
    } catch (e) {
      await _logDirect('e', '检查日志大小失败: $e', 'LogUtil');
      await _clearLogs();
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

  // 设置 debugMode 状态，供外部调用
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

  // 通过 Provider 来获取 isLogOn 并设置 debugMode
  static void updateDebugModeFromProvider(BuildContext context) {
    try {
      var themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      bool isLogOn = themeProvider.isLogOn;
      setDebugMode(isLogOn);
    } catch (e) {
      setDebugMode(false);
      _logDirect('e', '未能读取到 ThemeProvider，默认关闭日志功能: $e', 'LogUtil');
    }
  }

  // 显示调试信息的弹窗
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
                  overflow: TextOverflow.visible,
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

  // 查找有效的 OverlayState
  static final navigatorObserver = NavigatorObserver();
  static OverlayState? _findOverlayState() {
    try {
      if (navigatorObserver.navigator?.overlay != null) {
        return navigatorObserver.navigator?.overlay;
      }

      // 备用方案：从根元素开始搜索
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
      _logDirect('e', '获取 OverlayState 失败: $e', 'LogUtil');
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

  // 封装的日志记录方法，增加参数检查并记录堆栈位置
  static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
    if (!debugMode) return;

    stackTrace ??= StackTrace.current;

    if (message.isEmpty || error == null) {
      await _logDirect('e', '参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace', 'LogUtil');
      return;
    }

    await _log('e', '错误: $message\n错误详情: $error\n堆栈信息: ${_processStackTrace(stackTrace)}', _defTag);
  }

  // 安全执行方法，捕获并记录异常
  static Future<void> safeExecute(void Function()? action, String errorMessage, [StackTrace? stackTrace]) async {
    if (action == null) {
      await _logDirect('e', '$errorMessage - 函数调用时参数为空或不匹配', 'LogUtil');
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
      String frameInfo = frames.join('\n'); 

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

  // 提取和处理堆栈信息，过滤掉无关帧
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

  // 获取所有日志（从内存获取）
  static List<Map<String, String>> getLogs() {
    try {
      return List.from(_memoryLogs);
    } catch (e) {
      _logDirect('e', '获取日志失败: $e', 'LogUtil');
      return [];
    }
  }

  // 按级别获取日志（从内存获取）
  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      return _memoryLogs.where((log) => log['level'] == level).toList();
    } catch (e) {
      _logDirect('e', '按级别获取日志失败: $e', 'LogUtil');
      return [];
    }
  }

  // 清空日志
  static Future<void> clearLogs([String? level]) async {
    if (_isOperating) return;

    _isOperating = true;
    try {
      if (level == null) {
        // 清空所有日志
        _memoryLogs.clear();
        _newLogsBuffer.clear();

        // 删除日志文件
        final filePath = await _getLogFilePath();
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
        await _logDirect('i', '清空所有日志完成', 'LogUtil');
      } else {
        // 清空特定级别的日志
        _memoryLogs.removeWhere((log) => log['level'] == level);
        _newLogsBuffer.removeWhere((log) => log['level'] == level);

        // 更新文件内容
        final filePath = await _getLogFilePath();
        final file = File(filePath);
        final String updatedLogs = _memoryLogs.map((log) =>
          '[${log["time"]}] [${log["level"]}] [${log["tag"]}] | ${log["message"]} | ${log["fileInfo"]}'
        ).join('\n');
        await file.writeAsString(updatedLogs);
        await _logDirect('i', '清空 $level 级别日志完成', 'LogUtil');
      }
    } catch (e) {
      await _logDirect('e', '清空日志失败: $e', 'LogUtil');
    } finally {
      _isOperating = false;
    }
  }

  // 内部清空日志方法
  static Future<void> _clearLogs() async {
    if (_isOperating) return;

    _isOperating = true;
    try {
      _memoryLogs.clear();
      _newLogsBuffer.clear();

      // 删除日志文件
      final filePath = await _getLogFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      await _logDirect('i', '内部清空日志完成', 'LogUtil');
    } catch (e) {
      await _logDirect('e', '内部清空日志失败: $e', 'LogUtil');
    } finally {
      _isOperating = false;
    }
  }

  // 解析日志消息，展示实际内容时只提取消息部分，保留文件和行号信息
  static String parseLogMessage(String message) {
    try {
      // 格式：[时间] [级别] [标签] | 消息内容 | 文件位置
      final RegExp regex = RegExp(r'\[.*?\] \[.*?\] \[.*?\] \| (.*?) \|');
      final match = regex.firstMatch(message);
      if (match != null) {
        return match.group(1)?.trim() ?? message;
      }
    } catch (e) {
      _logDirect('e', '解析日志消息失败: $e', 'LogUtil');
    }
    return message;
  }

  // 应用退出时调用
  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
  }
}
