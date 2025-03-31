import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:collection/collection.dart' show Queue;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = true; // 控制是否记录日志 true 或 false
  static bool _isOperating = false; // 恢复原始标志位
  static const int _maxSingleLogLength = 888; // 添加单条日志最大长度限制
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 最大日志限制5MB

  // 内存存储相关
  // 修改：使用 Queue 替代 List 以优化移除操作
  static final Queue<String> _memoryLogs = Queue<String>();
  static final List<String> _newLogsBuffer = [];
  static const int _writeThreshold = 5; // 累积5条日志才写入本地
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt'; // 日志文件名
  // 修改：在类级别静态初始化日志文件路径，避免重复构造
  static late String _logFilePath; // 使用 late 确保初始化时赋值
  static File? _logFile; // 缓存 File 对象，避免重复构造
  static const int _maxMemoryLogSize = 1000; // 限制 _memoryLogs 最大容量为 1000 条

  // 弹窗相关属性
  static bool _showOverlay = false; // 控制是否显示弹窗
  static OverlayEntry? _overlayEntry; // 修改为单个 OverlayEntry
  static final List<String> _debugMessages = [];
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;

  // 修改：预生成所有级别的正则表达式，避免运行时重复创建
  static final Map<String, RegExp> _levelPatterns = {
    'v': RegExp(r'\[v\]'),
    'e': RegExp(r'\[e\]'),
    'i': RegExp(r'\[i\]'),
    'd': RegExp(r'\[d\]'),
  };
  static final Map<String, RegExp> _clearLevelPatterns = {
    'v': RegExp(r'\[v\]'),
    'e': RegExp(r'\[e\]'),
    'i': RegExp(r'\[i\]'),
    'd': RegExp(r'\[d\]'),
  };

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear(); // 初始化时先清空内存
      _newLogsBuffer.clear(); // 初始化时先清空缓冲区

      // 修改：静态初始化 _logFilePath，避免重复调用 _getLogFilePath
      final directory = await getApplicationDocumentsDirectory();
      _logFilePath = '${directory.path}/$_logFileName';
      _logFile ??= File(_logFilePath); // 缓存 File 对象

      if (!await _logFile!.exists()) {
        await _logFile!.create();
        developer.log('创建日志文件: $_logFilePath');
      } else {
        final int sizeInBytes = await _logFile!.length();
        if (sizeInBytes > _maxFileSizeBytes) {
          developer.log('日志文件超过大小限制，执行清理');
          await clearLogs(isAuto: true); // 修改为命名参数
        }
      }
    } catch (e) {
      developer.log('日志初始化失败: $e');
      await clearLogs(isAuto: true); // 修改为命名参数
    }
  }

  // 获取日志文件路径（异步逻辑+缓存）
  static Future<String> _getLogFilePath() async {
    // 修改：直接返回静态缓存的 _logFilePath，无需重复构造
    return _logFilePath;
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

  // 修改：使用正则表达式优化特殊字符替换，减少多次遍历
  static String _replaceSpecialChars(String input, bool isFormat) {
    final pattern = RegExp(r'[\n\r\|\[\]]');
    final replacements = {
      '\n': '\\n',
      '\r': '\\r',
      '|': '\\|',
      '[': '\\[',
      ']': '\\]',
    };
    return input.replaceAllMapped(pattern, (match) {
      final char = match.group(0)!;
      return isFormat ? replacements[char]! : char.replaceAll('\\', '');
    });
  }

  static String _formatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, true);
  }

  static String _unformatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, false);
  }

  // 修改：优化日志记录方法，提取公共逻辑并异步写入
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString();
      String fileInfo = _extractStackInfo();

      String objectStr = object.toString();
      // 处理长日志分段
      if (objectStr.length > _maxSingleLogLength) {
        final chunks = _splitLogIntoChunks(objectStr, _maxSingleLogLength);
        for (var chunk in chunks.reversed) {
          await _processLogChunk(level, time, tag, chunk, fileInfo);
        }
      } else {
        // 正常日志处理
        await _processLogChunk(level, time, tag, objectStr, fileInfo);
      }

      // 检查并触发写入
      developer.log('当前缓冲区大小: ${_newLogsBuffer.length}');
      if (_newLogsBuffer.length >= _writeThreshold && !_isOperating) {
        // 修改：将 _flushToLocal 放入 compute 异步执行，避免阻塞 UI
        await compute(_flushToLocalCompute, null);
      }
    } catch (e) {
      developer.log('日志记录失败: $e');
    }
  }

  // 新增：提取公共日志处理逻辑
  static Future<void> _processLogChunk(String level, String time, String? tag, String chunk, String fileInfo) async {
    String formattedChunk = _formatLogString(chunk);
    String logMessage = '[${time}] [${level}] [${tag ?? _defTag}] | ${formattedChunk} | ${fileInfo}';
    _addLogToBuffers(logMessage);
    developer.log(logMessage);
    if (_showOverlay) {
      _showDebugMessage('[${level}] ${_unformatLogString(formattedChunk)}');
    }
  }

  // 修改：使用 StringBuffer 优化长日志分段
  static List<String> _splitLogIntoChunks(String log, int maxLength) {
    List<String> chunks = [];
    StringBuffer buffer = StringBuffer();
    int start = 0;

    while (start < log.length) {
      int end = start + maxLength;
      if (end > log.length) end = log.length;
      buffer.write(log.substring(start, end));
      if (end < log.length) {
        buffer.write(' ... (续)');
      }
      chunks.add(buffer.toString());
      buffer.clear();
      start = end;
    }
    return chunks;
  }

  // 修改：优化缓冲区添加逻辑，使用 Queue
  static void _addLogToBuffers(String logMessage) {
    _memoryLogs.addLast(logMessage);
    _newLogsBuffer.add(logMessage);
    if (_memoryLogs.length > _maxMemoryLogSize) {
      _memoryLogs.removeFirst(); // Queue 的移除操作复杂度为 O(1)
    }
  }

  // 未修改：保留原始 _flushToLocal 方法，但新增 compute 包装函数
  static Future<void> _flushToLocal() async {
    if (_newLogsBuffer.isEmpty || _isOperating) return;
    _isOperating = true;
    List<String> logsToWrite = [];
    try {
      logsToWrite = List.from(_newLogsBuffer);
      _newLogsBuffer.clear();

      if (_logFile == null) {
        _logFile = File(await _getLogFilePath());
      }
      await _logFile!.writeAsString(
        logsToWrite.join('\n') + '\n',
        mode: FileMode.append, // 使用追加模式而不是覆盖
      );
    } catch (e) {
      developer.log('写入日志文件失败: $e');
      _newLogsBuffer.insertAll(0, logsToWrite);
      if (e is IOException) {
        developer.log('IO异常，可能是权限或空间不足: $e');
      }
    } finally {
      _isOperating = false;
    }
  }

  // 新增：compute 包装函数，用于异步执行 _flushToLocal
  static Future<void> _flushToLocalCompute(dynamic _) async {
    await _flushToLocal();
  }

  // 显示调试消息
  static void _showDebugMessage(String message) {
    final parsedLog = _parseLogString('[未知时间] [未知级别] [$_defTag] | $message | 未知文件');
    String displayMessage = '${parsedLog['time']}\n${parsedLog['message']}\n${parsedLog['fileInfo']}';

    _debugMessages.insert(0, displayMessage);
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
                children: _debugMessages
                    .map((msg) => Text(
                          msg,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          softWrap: true,
                          maxLines: null,
                          overflow: TextOverflow.visible,
                        ))
                    .toList(),
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
        if (element is StatefulElement && element.state is OverlayState) {
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

  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  static void _startAutoHideTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _messageDisplayDuration * _debugMessages.length), () {
      _debugMessages.clear();
      _hideOverlay();
      _timer = null;
    });
  }

  static Future<void> logError(String message, dynamic error,
      [StackTrace? stackTrace]) async {
    if (!debugMode) return;

    stackTrace ??= StackTrace.current;

    if (message?.isNotEmpty != true || error == null) {
      await LogUtil.e(
          '参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    await _log('e',
        '错误: $message\n错误详情: $error\n堆栈信息: ${_extractStackInfo(stackTrace: stackTrace)}',
        _defTag);
  }

  static Future<void> safeExecute(void Function()? action, String errorMessage,
      [StackTrace? stackTrace]) async {
    if (action == null) {
      await logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null',
          stackTrace ?? StackTrace.current);
      return;
    }

    try {
      action();
    } catch (error, st) {
      await logError(errorMessage, error, st);
    }
  }

  static final RegExp _stackFramePattern = RegExp(r'([^/\\]+\.dart):(\d+)');
  static String _extractStackInfo({StackTrace? stackTrace}) {
    try {
      final frames = (stackTrace ?? StackTrace.current).toString().split('\n');
      String frameInfo = frames.join('\n');
      developer.log('堆栈信息:\n$frameInfo');

      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i];
        final match = _stackFramePattern.firstMatch(frame);
        if (match != null && !frame.contains('log_util.dart')) {
          return '${match.group(1)}:${match.group(2)}';
        }
      }
    } catch (e) {
      return 'Unknown';
    }
    return 'Unknown';
  }

  static Map<String, String> _parseLogString(String logStr) {
    try {
      final parts = logStr.split('|').map((s) => s.trim()).toList();
      final headers = parts[0]
          .split(']')
          .map((s) => s.trim().replaceAll('[', ''))
          .where((s) => s.isNotEmpty)
          .toList();

      return {
        'time': headers[0],
        'level': headers[1],
        'tag': headers[2],
        'message': parts[1],
        'fileInfo': parts[2],
      };
    } catch (e) {
      developer.log('解析日志失败: $e');
      return {
        'time': '未知时间',
        'level': '未知级别',
        'tag': _defTag,
        'message': logStr,
        'fileInfo': '未知文件',
      };
    }
  }

  static List<Map<String, String>> getLogs() {
    try {
      return _memoryLogs.toList().reversed.map(_parseLogString).toList();
    } catch (e) {
      developer.log('获取日志失败: $e');
      return [];
    }
  }

  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      // 修改：使用预生成的正则表达式
      final pattern = _levelPatterns[level];
      if (pattern == null) return [];
      return _memoryLogs
          .where((log) => pattern.hasMatch(log))
          .map(_parseLogString)
          .toList();
    } catch (e) {
      developer.log('按级别获取日志失败: $e');
      return [];
    }
  }

  static Future<void> clearLogs({String? level, bool isAuto = false}) async {
    if (_isOperating) return;
    _isOperating = true;

    try {
      if (_logFile == null) {
        _logFile = File(await _getLogFilePath());
      }

      if (level == null) {
        _memoryLogs.clear();
        _newLogsBuffer.clear();

        if (await _logFile!.exists()) {
          if (isAuto) {
            final lines = await _logFile!.readAsLines();
            if (lines.isNotEmpty) {
              final endIndex = lines.length ~/ 2;
              final remainingLogs = lines.sublist(0, endIndex);
              await _logFile!.writeAsString(remainingLogs.join('\n') + '\n');
            }
          } else {
            await _logFile!.delete();
          }
        }
      } else {
        // 修改：使用预生成的正则表达式
        final pattern = _clearLevelPatterns[level];
        if (pattern != null) {
          _memoryLogs.removeWhere((log) => pattern.hasMatch(log));
          _newLogsBuffer.removeWhere((log) => pattern.hasMatch(log));
        }

        if (await _logFile!.exists()) {
          await _logFile!.writeAsString(_memoryLogs.join('\n') + '\n');
        }
      }
    } catch (e) {
      developer.log(
          '${level == null ? (isAuto ? "自动" : "手动") : "按级别"}清理日志失败: $e');
    } finally {
      _isOperating = false;
    }
  }

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

  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
    _timer?.cancel();
    _timer = null;
    _hideOverlay();
    _memoryLogs.clear();
    _newLogsBuffer.clear();
    _debugMessages.clear();
    _isOperating = false;
  }
}
