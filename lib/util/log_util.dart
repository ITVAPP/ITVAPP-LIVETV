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
  static bool debugMode = true; // 是否开启日志记录
  static bool _isOperating = false; // 操作锁，避免并发问题
  static const int _maxSingleLogLength = 588; // 单条日志最大长度
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 日志文件最大限制5MB

  // 内存存储相关
  static final List<String> _memoryLogs = []; // 内存中的日志列表
  static final List<String> _newLogsBuffer = []; // 新日志缓冲区
  static const int _writeThreshold = 5; // 累积5条日志后写入本地
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt'; // 日志文件名
  static late String _logFilePath; // 日志文件路径，延迟初始化
  static const int _maxMemoryLogSize = 1000; // 内存日志最大容量

  // 弹窗相关属性
  static bool _showOverlay = false; // 是否显示调试弹窗
  static OverlayEntry? _overlayEntry; // 调试弹窗的OverlayEntry实例
  static final List<String> _debugMessages = []; // 调试消息列表
  static Timer? _timer; // 弹窗自动隐藏定时器
  static const int _messageDisplayDuration = 3; // 弹窗显示时长（秒）

  static OverlayState? _cachedOverlayState; // 缓存OverlayState，提升性能
  static String? _lastFileAndLine; // 缓存最近使用的文件和行号

  // 正则表达式缓存，提升字符串处理性能
  static final Map<String, RegExp> _regexCache = {
    'encode': RegExp(r'[\n\r\|\[\]]'), // 编码特殊字符
    'decode': RegExp(r'\\([n|r|\[|\]])'), // 解码特殊字符
    'fileLine': RegExp(r'([^/\\]+\.dart):(\d+)'), // 提取文件名和行号
    'trimNewlines': RegExp(r'^\n+|\n+$'), // 去除首尾换行符
  };

  // 初始化日志工具，应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear(); // 清空内存日志
      _newLogsBuffer.clear(); // 清空缓冲区
      _logFilePath = await _initLogFilePath(); // 初始化日志文件路径
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
      await clearLogs(isAuto: true); // 初始化失败时自动清理
    }
  }

  // 初始化日志文件路径
  static Future<String> _initLogFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_logFileName'; // 返回完整路径
  }

  // 获取日志文件路径
  static String getLogFilePath() => _logFilePath;

  // 设置调试模式开关
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
  }

  // 设置是否显示调试弹窗
  static void setShowOverlay(bool show) {
    _showOverlay = show;
    if (!show) _hideOverlay(); // 关闭时隐藏弹窗
  }

  // 从Provider更新调试模式
  static void updateDebugModeFromProvider(BuildContext context) {
    try {
      var themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      bool isLogOn = themeProvider.isLogOn;
      setDebugMode(isLogOn); // 根据Provider状态设置调试模式
    } catch (e) {
      setDebugMode(false); // 异常时默认关闭日志
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

  // 格式化日志消息
  static String _formatLogMessage(Object? object, {bool encode = true}) {
    String objectStr = object.toString() ?? 'null';
    if (encode) {
      objectStr = objectStr.replaceAllMapped(_regexCache['encode']!, (m) => '\\${m[0]}'); // 编码特殊字符
    } else {
      objectStr = objectStr.replaceAllMapped(_regexCache['decode']!, (m) => m[1]!); // 解码特殊字符
    }
    if (objectStr.length > _maxSingleLogLength) {
      objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)'; // 截断超长日志
    }
    return objectStr;
  }

  // 核心日志记录方法
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString(); // 获取当前时间
      String fileInfo = _getFileAndLine(); // 获取调用位置
      String objectStr = _formatLogMessage(object); // 格式化日志内容
      String logMessage = '[${time}] [${level}] [${tag ?? _defTag}] | ${objectStr} | ${fileInfo}';

      _newLogsBuffer.add(logMessage); // 添加到缓冲区
      if (_memoryLogs.length < _maxMemoryLogSize) {
        _memoryLogs.add(logMessage); // 未满时直接添加
      } else {
        _memoryLogs.removeAt(0); // 超出时移除最早日志
        _memoryLogs.add(logMessage);
      }

      if (_newLogsBuffer.length >= _writeThreshold) {
        await _flushToLocal(); // 达到阈值时写入本地
      }

      developer.log(logMessage); // 输出到开发者日志
      if (_showOverlay) {
        String displayMessage = _formatLogMessage(object, encode: false);
        _showDebugMessage('[${level}] $displayMessage'); // 显示调试弹窗
      }
    } catch (e) {
      developer.log('日志记录失败: $e');
    }
  }

  // 将缓冲区日志写入本地文件
  static Future<void> _flushToLocal() async {
    if (_newLogsBuffer.isEmpty || _isOperating) return;
    _isOperating = true;
    List<String> logsToWrite = [];
    try {
      logsToWrite = List.from(_newLogsBuffer); // 复制缓冲区日志
      _newLogsBuffer.clear(); // 清空缓冲区
      final file = File(_logFilePath);
      await file.writeAsString(_memoryLogs.join('\n') + '\n'); // 写入文件
    } catch (e) {
      developer.log('写入日志文件失败: $e');
      _newLogsBuffer.insertAll(0, logsToWrite); // 失败时回滚
    } finally {
      _isOperating = false; // 释放操作锁
    }
  }

  // 显示调试消息弹窗
  static void _showDebugMessage(String message) {
    _debugMessages.insert(0, message); // 添加新消息
    if (_debugMessages.length > 6) _debugMessages.removeLast(); // 限制消息数量

    _cachedOverlayState ??= _findOverlayState(); // 缓存OverlayState
    if (_cachedOverlayState == null) return;

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild(); // 更新现有弹窗
    } else {
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
      _cachedOverlayState!.insert(_overlayEntry!); // 插入新弹窗
    }
    _startAutoHideTimer(); // 启动自动隐藏
  }

  // 启动弹窗自动隐藏定时器
  static void _startAutoHideTimer() {
    _timer?.cancel(); // 取消现有定时器
    _timer = Timer(Duration(seconds: _messageDisplayDuration), () {
      if (_debugMessages.isNotEmpty) {
        _debugMessages.removeLast(); // 移除最后一条消息
        if (_debugMessages.isEmpty) {
          _hideOverlay(); // 无消息时隐藏弹窗
        } else {
          _overlayEntry?.markNeedsBuild(); // 更新弹窗内容
        }
      }
    });
  }

  static final navigatorObserver = NavigatorObserver(); // Navigator观察者实例

  // 查找OverlayState，仅在未缓存时调用
  static OverlayState? _findOverlayState() {
    try {
      if (navigatorObserver.navigator?.overlay != null) {
        return navigatorObserver.navigator?.overlay; // 从Navigator获取
      }

      Element? rootElement = WidgetsBinding.instance.renderViewElement;
      if (rootElement == null) return null;

      OverlayState? overlayState;
      void visitor(Element element) {
        if (overlayState != null) return;
        if (element is StatefulElement && element.state is OverlayState) {
          overlayState = element.state as OverlayState; // 找到OverlayState
          return;
        }
        element.visitChildren(visitor); // 递归查找
      }
      rootElement.visitChildren(visitor);

      return overlayState;
    } catch (e) {
      developer.log('获取 OverlayState 失败: $e');
      return null;
    }
  }

  // 隐藏调试弹窗
  static void _hideOverlay() {
    _overlayEntry?.remove(); // 移除弹窗
    _overlayEntry = null; // 清空引用
  }

  // 记录错误日志
  static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
    if (!debugMode) return;
    stackTrace ??= StackTrace.current; // 默认获取当前堆栈

    if (message?.isNotEmpty != true || error == null) {
      await LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }
    await _log('e', '错误: $message\n错误详情: $error\n堆栈信息: $stackTrace', _defTag); // 记录错误日志
  }

  // 安全执行函数并捕获异常
  static Future<void> safeExecute(void Function()? action, String errorMessage, [StackTrace? stackTrace]) async {
    if (action == null) {
      await logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null', stackTrace ?? StackTrace.current);
      return;
    }
    try {
      action(); // 执行目标函数
    } catch (error, st) {
      await logError(errorMessage, error, st); // 捕获并记录异常
    }
  }

  // 获取调用者的文件和行号
  static String _getFileAndLine() {
    if (_lastFileAndLine != null) return _lastFileAndLine!; // 使用缓存
    try {
      final frames = StackTrace.current.toString().split('\n');
      for (int i = 2; i < frames.length; i++) {
        final frame = frames[i];
        final match = _regexCache['fileLine']!.firstMatch(frame);
        if (match != null && !frame.contains('log_util.dart')) {
          _lastFileAndLine = '${match.group(1)}:${match.group(2)}'; // 缓存结果
          return _lastFileAndLine!;
        }
      }
      _lastFileAndLine = frames.length > 2 ? 'UnknownFile:${frames[2]}' : 'Unknown';
      return _lastFileAndLine!;
    } catch (e) {
      return 'Unknown (ParseError: $e)'; // 解析失败时返回错误信息
    }
  }

  // 解析单条日志内容
  static Map<String, String> _parseLogEntry(String logStr) {
    final parts = logStr.split('|').map((s) => s.trim()).toList();
    final headers = parts[0].split(']')
        .map((s) => s.trim().replaceAll('[', ''))
        .where((s) => s.isNotEmpty)
        .toList();

    return {
      'time': headers[0], // 时间
      'level': headers[1], // 日志级别
      'tag': headers[2], // 标签
      'message': parts[1], // 消息内容
      'fileInfo': parts[2], // 文件和行号
    };
  }

  // 获取所有日志
  static List<Map<String, String>> getLogs() {
    try {
      return _memoryLogs.map((logStr) => _parseLogEntry(logStr)).toList(); // 解析并返回日志列表
    } catch (e) {
      developer.log('获取日志失败: $e');
      return [];
    }
  }

  // 按级别获取日志
  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      final levelPattern = RegExp(r'\[' + level + r'\]');
      return _memoryLogs
          .where((log) => levelPattern.hasMatch(log))
          .map((logStr) => _parseLogEntry(logStr))
          .toList(); // 筛选并解析指定级别日志
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
      final file = File(_logFilePath);
      if (level == null) {
        _memoryLogs.clear(); // 清空内存日志
        _newLogsBuffer.clear(); // 清空缓冲区
        if (await file.exists()) {
          if (isAuto) {
            final lines = await file.readAsLines();
            if (lines.isNotEmpty) {
              final endIndex = lines.length ~/ 2;
              final remainingLogs = lines.sublist(0, endIndex);
              await file.writeAsString(remainingLogs.join('\n') + '\n'); // 自动清理保留前半部分
            }
          } else {
            await file.delete(); // 手动清理删除文件
          }
        }
      } else {
        final levelPattern = RegExp(r'\[' + level + r'\]');
        _memoryLogs.removeWhere((log) => levelPattern.hasMatch(log)); // 移除指定级别日志
        _newLogsBuffer.removeWhere((log) => levelPattern.hasMatch(log));
        if (await file.exists()) {
          await file.writeAsString(_memoryLogs.join('\n') + '\n'); // 更新文件内容
        }
      }
    } catch (e) {
      developer.log('${level == null ? (isAuto ? "自动" : "手动") : "按级别"}清理日志失败: $e');
    } finally {
      _isOperating = false; // 释放操作锁
    }
  }

  // 解析日志消息内容
  static String parseLogMessage(String logLine) {
    try {
      final parts = logLine.split('|');
      if (parts.length >= 2) {
        return parts[1].trim().replaceAll(_regexCache['trimNewlines']!, ''); // 提取并清理消息
      }
    } catch (e) {
      developer.log('解析日志消息失败: $e');
    }
    return logLine;
  }

  // 释放资源并确保日志写入
  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal(); // 写入剩余日志
    }
  }
}
