import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool debugMode = true;
  static bool _isOperating = false;
  static const int _maxSingleLogLength = 888;
  static const int _maxFileSizeBytes = 5 * 1024 * 1024;

  static final List<String> _memoryLogs = [];
  static final List<String> _newLogsBuffer = [];
  static const int _writeThreshold = 5;
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt';
  static String? _logFilePath; // 修改：恢复为可空类型，增强容错性
  static File? _logFile; // 修改：恢复为可空类型，增强容错性
  static const int _maxMemoryLogSize = 1000;
  static Timer? _memoryCleanupTimer;

  static bool _showOverlay = false;
  static OverlayEntry? _overlayEntry;
  static final List<String> _debugMessages = [];
  static ValueNotifier<List<String>> _debugMessagesNotifier = ValueNotifier([]);
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;
  static OverlayState? _cachedOverlayState;

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

  static final Map<String, String> _replacements = {
    '\n': '\\n',
    '\r': '\\r',
    '|': '\\|',
    '[': '\\[',
    ']': '\\]'
  };

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear();
      _newLogsBuffer.clear();

      _logFilePath ??= await _getLogFilePath();
      _logFile ??= File(_logFilePath!);

      if (!await _logFile!.exists()) {
        await _logFile!.create();
        _logInternal('创建日志文件: $_logFilePath');
      } else {
        final int sizeInBytes = await _logFile!.length();
        if (sizeInBytes > _maxFileSizeBytes) {
          _logInternal('日志文件超过大小限制，执行清理');
          await clearLogs(isAuto: true);
        }
      }

      _memoryCleanupTimer?.cancel();
      _memoryCleanupTimer = Timer.periodic(Duration(seconds: 30), (_) {
        _cleanupMemoryLogs();
      });
    } catch (e) {
      _logInternal('日志初始化失败: $e');
      _logFilePath = null; // 重置为 null，确保下次重试
      _logFile = null;
      await clearLogs(isAuto: true);
    }
  }

  // 获取日志文件路径（异步逻辑+缓存）
  static Future<String> _getLogFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_logFileName';
  }

  // 修改：优化日志记录方法，添加缓冲区检查
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString();
      String fileInfo = _extractStackInfo();

      String objectStr = object.toString();
      if (objectStr.length > _maxSingleLogLength) {
        final chunks = _splitLogIntoChunks(objectStr, _maxSingleLogLength);
        for (var chunk in chunks.reversed) {
          String formattedChunk = _formatLogString(chunk);
          String logMessage =
              '[${time}] [${level}] [${tag ?? _defTag}] | ${formattedChunk} | ${fileInfo}';
          _addLogToBuffers(logMessage);
          _logInternal(logMessage);
          if (_showOverlay) {
            _showDebugMessage('[${level}] ${_unformatLogString(formattedChunk)}');
          }
        }
      } else {
        objectStr = _formatLogString(objectStr);
        String logMessage =
            '[${time}] [${level}] [${tag ?? _defTag}] | ${objectStr} | ${fileInfo}';
        _addLogToBuffers(logMessage);
        _logInternal(logMessage);
        if (_showOverlay) {
          String displayMessage = _unformatLogString(objectStr);
          _showDebugMessage('[${level}] $displayMessage');
        }
      }

      _logInternal('当前缓冲区大小: ${_newLogsBuffer.length}');
      if (_newLogsBuffer.length >= _writeThreshold && !_isOperating) {
        await _flushToLocal();
      }
    } catch (e) {
      _logInternal('日志记录失败: $e');
      // 新增：异常时仍尝试保存缓冲区数据
      if (_newLogsBuffer.isNotEmpty && !_isOperating) {
        await _flushToLocal();
      }
    }
  }

  // 未修改：保留原始 _flushToLocal 方法，但恢复防护逻辑
  static Future<void> _flushToLocal() async {
    if (_newLogsBuffer.isEmpty || _isOperating) return;
    _isOperating = true;
    List<String> logsToWrite = [];
    try {
      logsToWrite = List.from(_newLogsBuffer);
      _newLogsBuffer.clear();

      if (_logFile == null || !await _logFile!.exists()) {
        _logFilePath = await _getLogFilePath();
        _logFile = File(_logFilePath!);
        if (!await _logFile!.exists()) {
          await _logFile!.create();
          _logInternal('重新创建日志文件: $_logFilePath');
        }
      }
      await _logFile!.writeAsString(
        logsToWrite.join('\n') + '\n',
        mode: FileMode.append,
      );
      _logInternal('成功写入日志，条数: ${logsToWrite.length}');
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

  // 以下为无关代码，仅列出部分以示完整性，未修改
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
  }

  static void setShowOverlay(bool show) {
    _showOverlay = show;
    if (!show) {
      _hideOverlay();
    }
  }

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

  static String _replaceSpecialChars(String input, bool isFormat) {
    String result = input;
    _replacements.forEach((key, value) {
      result = isFormat
          ? result.replaceAll(key, value)
          : result.replaceAll(value, key);
    });
    return result;
  }

  static String _formatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, true);
  }

  static String _unformatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, false);
  }

  static List<String> _splitLogIntoChunks(String log, int maxLength) {
    List<String> chunks = [];
    for (int i = 0; i < log.length; i += maxLength) {
      int end = i + maxLength;
      if (end > log.length) end = log.length;
      chunks.add(log.substring(i, end) + (end < log.length ? ' ... (续)' : ''));
    }
    return chunks;
  }

  static void _addLogToBuffers(String logMessage) {
    _memoryLogs.add(logMessage);
    _newLogsBuffer.add(logMessage);
  }

  static void _cleanupMemoryLogs() {
    if (_memoryLogs.length > _maxMemoryLogSize) {
      int excess = _memoryLogs.length - _maxMemoryLogSize;
      _memoryLogs.removeRange(0, excess);
      _logInternal('定时清理内存日志，移除 $excess 条');
    }
  }

  static void _showDebugMessage(String message) {
    final parsedLog = _parseLogString('[未知时间] [未知级别] [$_defTag] | $message | 未知文件');
    String displayMessage = '${parsedLog['time']}\n${parsedLog['message']}\n${parsedLog['fileInfo']}';

    _debugMessages.insert(0, displayMessage);
    if (_debugMessages.length > 6) {
      _debugMessages.removeLast();
    }
    _debugMessagesNotifier.value = List.from(_debugMessages);

    _hideOverlay();
    _cachedOverlayState ??= _findOverlayState();
    if (_cachedOverlayState != null && _overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          bottom: 20.0,
          right: 20.0,
          child: Material(
            color: Colors.transparent,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: _debugMessagesNotifier,
              builder: (context, messages, child) => Container(
                constraints: const BoxConstraints(maxWidth: 300.0),
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: messages
                      .map((msg) => Text(
                            msg,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            softWrap: true,
                            maxLines: null,
                            overflow: TextOverflow.visible,
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      );
      _cachedOverlayState!.insert(_overlayEntry!);
      _startAutoHideTimer();
    }
  }

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
      _logInternal('获取 OverlayState 失败: $e');
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
      _debugMessagesNotifier.value = [];
      _hideOverlay();
      _timer = null;
    });
  }

  static void _logInternal(String message) {
    if (debugMode) {
      developer.log(message);
    }
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
      _logInternal('堆栈信息:\n$frameInfo');

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
      _logInternal('解析日志失败: $e');
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
      return _memoryLogs.reversed.map(_parseLogString).toList();
    } catch (e) {
      _logInternal('获取日志失败: $e');
      return [];
    }
  }

  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      final pattern = _levelPatterns[level] ?? RegExp(r'\[' + level + r'\]');
      return _memoryLogs.reversed
          .where((log) => pattern.hasMatch(log))
          .map(_parseLogString)
          .toList();
    } catch (e) {
      _logInternal('按级别获取日志失败: $e');
      return [];
    }
  }

  static Future<void> clearLogs({String? level, bool isAuto = false}) async {
    if (_isOperating) return;
    _isOperating = true;

    try {
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
        final pattern = _clearLevelPatterns[level] ?? RegExp(r'\[' + level + r'\]');
        _memoryLogs.removeWhere((log) => pattern.hasMatch(log));
        _newLogsBuffer.removeWhere((log) => pattern.hasMatch(log));

        if (await _logFile!.exists()) {
          await _logFile!.writeAsString(_memoryLogs.join('\n') + '\n');
        }
      }
    } catch (e) {
      _logInternal('${level == null ? (isAuto ? "自动" : "手动") : "按级别"}清理日志失败: $e');
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
      _logInternal('解析日志消息失败: $e');
    }
    return logLine;
  }

  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
    _timer?.cancel();
    _timer = null;
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = null;
    _hideOverlay();
    _memoryLogs.clear();
    _newLogsBuffer.clear();
    _debugMessages.clear();
    _debugMessagesNotifier.value = [];
    _cachedOverlayState = null;
    _isOperating = false;
  }
}
