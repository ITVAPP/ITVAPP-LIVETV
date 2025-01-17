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

 // 初始化方法，在应用启动时调用
 static Future<void> init() async {
   try {
     _memoryLogs.clear();  
     _newLogsBuffer.clear(); 

     final filePath = await _getLogFilePath();
     final file = File(filePath);

     if (!await file.exists()) {
       await file.create();
       await i('创建日志文件: $filePath');
     } else {
       final int sizeInBytes = await file.length();
       if (sizeInBytes > _maxFileSizeBytes) {
         await i('日志文件超过大小限制，执行清理');
         await _clearLogs();
       } else {
         await _loadLogsFromLocal();
       }
     }
   } catch (e) {
     await i('日志初始化失败: $e');
     await _clearLogs();
   }
 }

 static Future<String> _getLogFilePath() async {
   if (_logFilePath != null) return _logFilePath!;
   final directory = await getApplicationDocumentsDirectory();
   _logFilePath = '${directory.path}/$_logFileName';
   return _logFilePath!;
 }

 static Future<void> _loadLogsFromLocal() async {
   try {
     final filePath = await _getLogFilePath();
     final file = File(filePath);

     if (await file.exists()) {
       final String content = await file.readAsString();
       if (content.isNotEmpty) {
         final List<Map<String, String>> logs = [];
         int successCount = 0;
         int failCount = 0;

         content.split('\n').where((line) => line.isNotEmpty).forEach((line) {
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
               }
             } else {
               failCount++;
             }
           } catch (error) {
             failCount++;
           }
         });

         if(logs.isNotEmpty) {
           _memoryLogs.addAll(logs.reversed);
         }

         // 记录日志加载结果
         await i('历史日志加载完成 - 成功: $successCount, 失败: $failCount, 总数: ${_memoryLogs.length}');
       } else {
         await i('历史日志文件为空');
       }
     }
   } catch (error) {
     await e('从文件加载历史日志失败: $error');
   }
 }

 static Future<void> _checkAndHandleLogSize() async {
   try {
     final filePath = await _getLogFilePath();
     final file = File(filePath);
     if (await file.exists()) {
       final int sizeInBytes = await file.length();
       if (sizeInBytes > _maxFileSizeBytes) {
         await i('日志文件大小超过限制，执行清理');
         await _clearLogs();
       }
     }
   } catch (e) {
     await i('检查日志大小失败: $e');
     await _clearLogs();
   }
 }

 static void setDebugMode(bool isEnabled) {
   debugMode = isEnabled;
 }

 static void setShowOverlay(bool show) {
   _showOverlay = show;
   if (!show) {
     _hideOverlay();
   }
 }

 static Future<void> updateDebugModeFromProvider(BuildContext context) async {
   try {
     var themeProvider = Provider.of<ThemeProvider>(context, listen: false);
     bool isLogOn = themeProvider.isLogOn;
     setDebugMode(isLogOn);
   } catch (e) {
     setDebugMode(false);
     await e('未能读取到 ThemeProvider，默认关闭日志功能: $e');
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

     Map<String, String> logEntry = {
       'time': time,
       'level': level,
       'message': objectStr,
       'tag': tag ?? _defTag,
       'fileInfo': fileInfo
     };

     _memoryLogs.insert(0, logEntry);
     _newLogsBuffer.insert(0, logEntry);

     String logMessage = '[${logEntry["time"]}] [${logEntry["level"]}] [${logEntry["tag"]}] | ${logEntry["message"]} | ${logEntry["fileInfo"]}';

     if (_newLogsBuffer.length >= _writeThreshold) {
       await _flushToLocal();
     }

     if (_showOverlay) {
       String displayMessage = logEntry["message"] ?? '';
       displayMessage = displayMessage
         .replaceAll('\\n', '\n')
         .replaceAll('\\r', '\r')
         .replaceAll('\\|', '|')
         .replaceAll('\\[', '[')
         .replaceAll('\\]', ']');

       _showDebugMessage('[${logEntry["level"]}] $displayMessage');
     }
   } catch (e) {
     await i('日志记录失败: $e');
   }
 }

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
     await i('写入日志文件失败: $e');
     _newLogsBuffer.insertAll(0, logsToWrite);
   } finally {
     _isOperating = false;
   }
 }

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
     i('获取 OverlayState 失败: $e');
     return null;
   }
 }

 static void _hideOverlay() {
   _overlayEntry?.remove();
   _overlayEntry = null;
 }

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

 static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
   if (!debugMode) return;

   stackTrace ??= StackTrace.current;

   if (message?.isNotEmpty != true || error == null) {
     await e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
     return;
   }

   await _log('e', '错误: $message\n错误详情: $error\n堆栈信息: ${_processStackTrace(stackTrace)}', _defTag);
 }

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

 static Future<List<Map<String, String>>> getLogs() async {
   try {
     return List.from(_memoryLogs);
   } catch (e) {
     await e('获取日志失败: $e');
     return [];
   }
 }

static Future<List<Map<String, String>>> getLogsByLevel(String level) async {
    try {
      return _memoryLogs.where((log) => log['level'] == level).toList();
    } catch (e) {
      await e('按级别获取日志失败: $e');
      return [];
    }
  }

  static Future<void> clearLogs([String? level]) async {
    if (_isOperating) return;

    _isOperating = true;
    try {
      if (level == null) {
        _memoryLogs.clear();
        _newLogsBuffer.clear();

        final filePath = await _getLogFilePath();
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        _memoryLogs.removeWhere((log) => log['level'] == level);
        _newLogsBuffer.removeWhere((log) => log['level'] == level);

        final filePath = await _getLogFilePath();
        final file = File(filePath);
        final String updatedLogs = _memoryLogs.map((log) =>
          '[${log["time"]}] [${log["level"]}] [${log["tag"]}] | ${log["message"]} | ${log["fileInfo"]}'
        ).join('\n');
        await file.writeAsString(updatedLogs);
      }
    } catch (e) {
      await i('清空日志失败: $e');
    } finally {
      _isOperating = false;
    }
  }

  static Future<void> _clearLogs() async {
    if (_isOperating) return;

    _isOperating = true;
    try {
      _memoryLogs.clear();
      _newLogsBuffer.clear();

      final filePath = await _getLogFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      await i('清空日志失败: $e');
    } finally {
      _isOperating = false;
    }
  }

  static Future<String?> parseLogMessage(String message) async {
    try {
      final RegExp regex = RegExp(r'\[.*?\] \[.*?\] \[.*?\] \| (.*?) \|');
      final match = regex.firstMatch(message);
      if (match != null) {
        return match.group(1)?.trim() ?? message;
      }
    } catch (e) {
      await e('解析日志消息失败: $e');
    }
    return message;
  }

  static Future<void> dispose() async {
    if (!_isOperating && _newLogsBuffer.isNotEmpty) {
      await _flushToLocal();
    }
  }
}
