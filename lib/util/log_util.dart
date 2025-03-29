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
  static const int _maxSingleLogLength = 588; // 添加单条日志最大长度限制
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 最大日志限制5MB

  // 内存存储相关
  static final List<String> _memoryLogs = [];
  static final List<String> _newLogsBuffer = [];
  static const int _writeThreshold = 5; // 累积5条日志才写入本地
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt'; // 日志文件名
  static String? _logFilePath; // 缓存日志文件路径

  // 弹窗相关属性
  static bool _showOverlay = false; // 控制是否显示弹窗
  static OverlayEntry? _overlayEntry; // 修改为单个 OverlayEntry
  static final List<String> _debugMessages = [];
  static Timer? _timer;
  static const int _messageDisplayDuration = 3;

  // 修改代码开始
  // 将 _cachedOverlayState 移到类级别，作为静态变量，用于缓存 OverlayState，避免语法错误
  static OverlayState? _cachedOverlayState;
  // 修改代码结束

  // 初始化方法，在应用启动时调用
  static Future<void> init() async {
    try {
      _memoryLogs.clear(); // 初始化时先清空内存
      _newLogsBuffer.clear(); // 初始化时先清空缓冲区

      // 修改代码开始
      // 预计算日志文件路径，避免重复调用 _getLogFilePath
      final directory = await getApplicationDocumentsDirectory();
      _logFilePath = '${directory.path}/$_logFileName';
      // 修改代码结束

      final file = File(_logFilePath!);

      if (!await file.exists()) {
        await file.create();
        developer.log('创建日志文件: $_logFilePath');
      } else {
        final int sizeInBytes = await file.length();
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

  // 获取日志文件路径
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

  // 记录日志的通用方法
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;
    try {
      String time = DateTime.now().toString();

      // 修改代码开始
      // 提取日志格式化逻辑，消除 _log 和 logError 中的重复代码
      String logMessage = _formatLogMessage(level, object, tag ?? _defTag, time);
      // 修改代码结束

      // 添加到内存和缓冲区（新日志在前）
      _memoryLogs.insert(0, logMessage);
      _newLogsBuffer.insert(0, logMessage);

      if (_newLogsBuffer.length >= _writeThreshold) {
        await _flushToLocal();
      }

      developer.log(logMessage);
      if (_showOverlay) {
        String displayMessage = object.toString()
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

  // 修改代码开始
  // 新增方法：格式化日志消息，消除重复逻辑
  static String _formatLogMessage(String level, Object? object, String tag, String time) {
    String objectStr = object.toString()
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('|', '\\|')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        ?? 'null';

    if (objectStr.length > _maxSingleLogLength) {
      objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)';
    }

    return '[${time}] [${level}] [${tag}] | ${objectStr}';
  }
  // 修改代码结束

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
      // 修改代码开始
      // 确保异常后操作锁被正确重置，避免并发问题
      _isOperating = false;
      // 修改代码结束
    }
  }

  // 显示调试消息
  static void _showDebugMessage(String message) {
    _debugMessages.insert(0, message);
    if (_debugMessages.length > 6) {
      _debugMessages.removeLast();
    }
    _hideOverlay();
    
    // 修改代码开始
    // 添加空检查，确保 overlayState 不为 null，提升健壮性
    final overlayState = _findOverlayState();
    if (overlayState == null) {
      developer.log('无法找到 OverlayState，弹窗显示失败');
      return;
    }
    // 修改代码结束

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

  // NavigatorObserver实例
  static final navigatorObserver = NavigatorObserver();

  // 查找OverlayState
  static OverlayState? _findOverlayState() {
    // 修改代码开始
    // 使用类级别的 _cachedOverlayState，避免重复计算，提升性能
    if (_cachedOverlayState != null) return _cachedOverlayState;
    // 修改代码结束

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
      return _cachedOverlayState;
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
    
    // 修改代码开始
    // 将 Timer.periodic 改为单次 Timer，提升效率
    _timer = Timer(Duration(seconds: _messageDisplayDuration), () {
      if (_debugMessages.isEmpty) {
        _hideOverlay();
        _timer = null;
      } else {
        _debugMessages.removeLast();
        if (_debugMessages.isEmpty) {
          _hideOverlay();
        } else {
          _overlayEntry?.markNeedsBuild();
        }
      }
    });
    // 修改代码结束
  }

  // 记录错误日志
  static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
    if (!debugMode) return;

    stackTrace ??= StackTrace.current;

    if (message?.isNotEmpty != true || error == null) {
      await LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
      return;
    }

    // 修改代码开始
    // 使用提取的 _formatLogMessage 方法，消除重复
    String time = DateTime.now().toString();
    String logMessage = _formatLogMessage('e', '错误: $message\n错误详情: $error\n堆栈信息: $stackTrace', _defTag, time);
    await _log('e', logMessage, _defTag);
    // 修改代码结束
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

  // 获取所有日志
  static List<Map<String, String>> getLogs() {
    try {
      // 修改代码开始
      // 增强字符串解析逻辑，提升健壮性
      return _memoryLogs.map((logStr) {
        final parts = logStr.split('|').map((s) => s.trim()).toList();
        if (parts.length < 2) return {'time': '', 'level': '', 'tag': '', 'message': logStr};

        final headers = parts[0].split(']')
            .map((s) => s.trim().replaceAll('[', ''))
            .where((s) => s.isNotEmpty)
            .toList();
        
        return {
          'time': headers.length > 0 ? headers[0] : '',
          'level': headers.length > 1 ? headers[1] : '',
          'tag': headers.length > 2 ? headers[2] : '',
          'message': parts[1],
        };
      }).toList();
      // 修改代码结束
    } catch (e) {
      developer.log('获取日志失败: $e');
      return [];
    }
  }

  // 按级别获取日志
  static List<Map<String, String>> getLogsByLevel(String level) {
    try {
      // 修改代码开始
      // 预编译正则表达式，提升性能
      final levelPattern = RegExp(r'\[' + RegExp.escape(level) + r'\]');
      return _memoryLogs
          .where((log) => levelPattern.hasMatch(log))
          .map((logStr) {
            final parts = logStr.split('|').map((s) => s.trim()).toList();
            if (parts.length < 2) return {'time': '', 'level': level, 'tag': '', 'message': logStr};

            final headers = parts[0].split(']')
                .map((s) => s.trim().replaceAll('[', ''))
                .where((s) => s.isNotEmpty)
                .toList();
            
            return {
              'time': headers.length > 0 ? headers[0] : '',
              'level': headers.length > 1 ? headers[1] : '',
              'tag': headers.length > 2 ? headers[2] : '',
              'message': parts[1],
            };
          }).toList();
      // 修改代码结束
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
        // 修改代码开始
        // 预编译正则表达式，提升性能
        final levelPattern = RegExp(r'\[' + RegExp.escape(level) + r'\]');
        _memoryLogs.removeWhere((log) => levelPattern.hasMatch(log));
        _newLogsBuffer.removeWhere((log) => levelPattern.hasMatch(log));
        // 修改代码结束
        
        if (await file.exists()) {
          await file.writeAsString(_memoryLogs.join('\n') + '\n');
        }
      }
    } catch (e) {
      developer.log('${level == null ? (isAuto ? "自动" : "手动") : "按级别"}清理日志失败: $e');
    } finally {
      // 修改代码开始
      // 确保异常后操作锁被正确重置，避免并发问题
      _isOperating = false;
      // 修改代码结束
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
    // 修改代码开始
    // 清理 _timer 和 _overlayEntry，避免资源泄漏
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
    _timer?.cancel();
    _timer = null;
    _hideOverlay();
    // 修改代码结束
  }
}
