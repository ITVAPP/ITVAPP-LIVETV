// 修改代码开始
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
  static bool debugMode = true; // 控制是否记录日志 true 或 false
  static bool _isOperating = false; // 恢复原始标志位，避免引入新依赖
  static const int _maxSingleLogLength = 888; // 添加单条日志最大长度限制
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 最大日志限制5MB

  // 内存存储相关
  static final List<String> _memoryLogs = [];
  static final List<String> _newLogsBuffer = [];
  static const int _writeThreshold = 5; // 累积5条日志才写入本地
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt'; // 日志文件名
  static String? _logFilePath; // 可空类型，确保路径缓存
  static File? _logFile; // 缓存 File 对象，避免重复构造
  static const int _maxMemoryLogSize = 1000; // 限制 _memoryLogs 最大容量为 1000 条

  // 弹窗相关属性
  static bool _showOverlay = false; // 控制是否显示弹窗
  static OverlayEntry? _overlayEntry; // 修改为单个 OverlayEntry
  static final List<String> _debugMessages = [];
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear(); // 初始化时先清空内存
      _newLogsBuffer.clear(); // 初始化时先清空缓冲区

      _logFilePath ??= await _getLogFilePath(); // 确保路径在 init 时初始化
      _logFile ??= File(_logFilePath!); // 缓存 File 对象

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
    if (_logFilePath != null) return _logFilePath!;
    final directory = await getApplicationDocumentsDirectory();
    _logFilePath = '${directory.path}/$_logFileName';
    return _logFilePath!;
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

  // 修改：提取公共的字符串替换逻辑，消除重复代码
  static String _replaceSpecialChars(String input, bool isFormat) {
    final replacements = {
      '\n': '\\n',
      '\r': '\\r',
      '|': '\\|',
      '[': '\\[',
      ']': '\\]'
    };
    String result = input;
    replacements.forEach((key, value) {
      result = isFormat
          ? result.replaceAll(key, value)
          : result.replaceAll(value, key);
    });
    return result;
  }

  // 修改：使用提取的公共方法重构格式化逻辑
  static String _formatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, true);
  }

  // 修改：使用提取的公共方法重构反格式化逻辑
  static String _unformatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, false);
  }

  // 修改：优化日志记录方法，提升性能
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      // 恢复原始并发检查逻辑，避免新依赖
      if (_isOperating) {
        await Future.delayed(Duration(milliseconds: 50)); // 短暂等待后重试
        if (_isOperating) return; // 若仍被占用则跳过，避免死锁
      }
      _isOperating = true;

      try {
        String time = DateTime.now().toString();
        String fileInfo = _extractStackInfo(); // 使用优化后的堆栈信息提取

        String objectStr = object.toString();
        // 修改：优化长日志截断，支持分段记录
        if (objectStr.length > _maxSingleLogLength) {
          final chunks = _splitLogIntoChunks(objectStr, _maxSingleLogLength);
          for (var chunk in chunks.reversed) { // 从后向前记录，确保顺序
            String formattedChunk = _formatLogString(chunk);
            String logMessage =
                '[${time}] [${level}] [${tag ?? _defTag}] | ${formattedChunk} | ${fileInfo}';
            _addLogToBuffers(logMessage); // 添加到内存和缓冲区
            developer.log(logMessage);
            if (_showOverlay) {
              _showDebugMessage('[${level}] ${_unformatLogString(formattedChunk)}');
            }
          }
          if (_newLogsBuffer.length >= _writeThreshold) {
            await _flushToLocal();
          }
          return; // 分段记录后直接返回
        }

        // 正常日志处理
        objectStr = _formatLogString(objectStr);
        String logMessage =
            '[${time}] [${level}] [${tag ?? _defTag}] | ${objectStr} | ${fileInfo}';
        _addLogToBuffers(logMessage); // 添加到内存和缓冲区

        if (_newLogsBuffer.length >= _writeThreshold) {
          await _flushToLocal();
        }

        developer.log(logMessage);
        if (_showOverlay) {
          String displayMessage = _unformatLogString(objectStr);
          _showDebugMessage('[${level}] $displayMessage');
        }
      } finally {
        _isOperating = false; // 确保释放锁
      }
    } catch (e) {
      developer.log('日志记录失败: $e');
      _isOperating = false; // 异常时也释放锁
    }
  }

  // 新增：辅助方法，将长日志分段
  static List<String> _splitLogIntoChunks(String log, int maxLength) {
    List<String> chunks = [];
    for (int i = 0; i < log.length; i += maxLength) {
      int end = i + maxLength;
      if (end > log.length) end = log.length;
      chunks.add(log.substring(i, end) + (end < log.length ? ' ... (续)' : ''));
    }
    return chunks;
  }

  // 新增：提取公共逻辑，将日志添加到内存和缓冲区并优化性能
  static void _addLogToBuffers(String logMessage) {
    // 修改：改为 add 替代 insert(0)，提升插入性能
    _memoryLogs.add(logMessage);
    _newLogsBuffer.add(logMessage);
    // 修改：批量移除超限日志，提升性能
    if (_memoryLogs.length > _maxMemoryLogSize) {
      int excess = _memoryLogs.length - _maxMemoryLogSize;
      _memoryLogs.removeRange(0, excess);
    }
  }

  // 未修改：保留原始 _flushToLocal 方法
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

  // 查找OverlayState（恢复原始递归遍历逻辑）
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

  // 隐藏弹窗
  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 启动自动隐藏计时器（优化为单次触发）
  static void _startAutoHideTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _messageDisplayDuration * _debugMessages.length), () {
      _debugMessages.clear();
      _hideOverlay();
      _timer = null;
    });
  }

  // 记录错误日志
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

  // 安全执行函数
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

  // 修改：优化堆栈信息提取，缓存正则表达式并提升性能
  static final RegExp _stackFramePattern = RegExp(r'([^/\\]+\.dart):(\d+)');
  static String _extractStackInfo({StackTrace? stackTrace}) {
    try {
      final frames = (stackTrace ?? StackTrace.current).toString().split('\n');
      String frameInfo = frames.join('\n'); // 将堆栈帧拼接为字符串
      developer.log('堆栈信息:\n$frameInfo'); // 每次调用时记录完整堆栈

      // 从第 3 帧开始遍历，跳过当前方法和直接调用者
      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i];
        final match = _stackFramePattern.firstMatch(frame);
        if (match != null && !frame.contains('log_util.dart')) {
          return '${match.group(1)}:${match.group(2)}';
        }
      }
    } catch (e) {
      return 'Unknown'; // 捕获异常时返回 Unknown
    }
    return 'Unknown'; // 未找到有效帧时返回 Unknown
  }

  // 解析日志字符串（提取公共逻辑）
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

  // 获取所有日志（复用解析逻辑）
  static List<Map<String, String>> getLogs() {
    try {
      // 修改：反转读取顺序以匹配 add 的插入方式
      return _memoryLogs.reversed.map(_parseLogString).toList();
    } catch (e) {
      developer.log('获取日志失败: $e');
      return [];
    }
  }

  // 按级别获取日志（复用解析逻辑并缓存正则表达式）
  static final Map<String, RegExp> _levelPatterns = {};

  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      _levelPatterns[level] ??= RegExp(r'\[' + level + r'\]');
      // 修改：反转读取顺序以匹配 add 的插入方式
      return _memoryLogs.reversed
          .where((log) => _levelPatterns[level]!.hasMatch(log))
          .map(_parseLogString)
          .toList();
    } catch (e) {
      developer.log('按级别获取日志失败: $e');
      return [];
    }
  }

  // 清理日志（添加正则缓存）
  static final Map<String, RegExp> _clearLevelPatterns = {};
  static Future<void> clearLogs({String? level, bool isAuto = false}) async {
    if (_isOperating) return;
    _isOperating = true;

    try {
      if (_logFile == null) {
        _logFile = File(await _getLogFilePath());
      }

      if (level == null) {
        // 清理所有日志
        _memoryLogs.clear();
        _newLogsBuffer.clear();

        if (await _logFile!.exists()) {
          if (isAuto) {
            // 自动清理时保留前半部分
            final lines = await _logFile!.readAsLines();
            if (lines.isNotEmpty) {
              final endIndex = lines.length ~/ 2;
              final remainingLogs = lines.sublist(0, endIndex);
              await _logFile!.writeAsString(remainingLogs.join('\n') + '\n');
            }
          } else {
            // 手动清理时直接删除
            await _logFile!.delete();
          }
        }
      } else {
        // 清理指定级别的日志
        _clearLevelPatterns[level] ??= RegExp(r'\[' + level + r'\]');
        _memoryLogs.removeWhere((log) => _clearLevelPatterns[level]!.hasMatch(log));
        _newLogsBuffer.removeWhere((log) => _clearLevelPatterns[level]!.hasMatch(log));

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

  // 修改：完善资源释放
  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
    _timer?.cancel();
    _timer = null;
    _hideOverlay(); // 清理 OverlayEntry
    _memoryLogs.clear(); // 清理内存日志
    _newLogsBuffer.clear(); // 清理缓冲区
    _debugMessages.clear(); // 清理调试消息
    _isOperating = false; // 确保状态重置
  }
}
// 修改代码结束
