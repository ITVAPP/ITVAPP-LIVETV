import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import '../provider/theme_provider.dart';

class LogUtil {
 static const String _defTag = 'common_utils';
 static bool debugMode = true; // 控制是否记录日志 true 或 false
 static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间
 static const int _maxLogs = 300; // 设置最大日志条目数
 static const int _maxSingleLogLength = 500; // 添加单条日志最大长度限制
 static const String _logsKey = 'ITVAPP_LIVETV_logs'; // 持久化存储的key

 // 弹窗相关属性
 static bool _showOverlay = true; // 控制是否显示弹窗
 static OverlayEntry? _overlayEntry;  // 修改为单个 OverlayEntry
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

 // 通用日志记录方法，日志记录受 debugMode 控制
 static Future<void> _log(String level, Object? object, String? tag) async {
   if (!debugMode || object == null) return;

   try {
     String time = DateTime.now().toString();
     String fileInfo = _getFileAndLine(); // 获取文件和行号信息
     
     // 安全处理 object，避免出现 null 值导致错误
     String objectStr = object?.toString() ?? 'null';
     if (objectStr.length > _maxSingleLogLength) {
       objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)';
     }
     String logMessage = '${tag ?? _defTag} $level | $objectStr\n$fileInfo';

     // 限制日志的数量，如果超过最大数量，则移除最旧的日志
     if (_logs.length >= _maxLogs) {
       _logs.removeAt(0); // 移除最旧的一条日志
     }

     _logs.add({'time': time, 'level': level, 'message': logMessage});
     await _saveLogsToStorage(); // 等待保存完成
     developer.log(logMessage);

     // 如果开启了弹窗显示，则显示弹窗
     if (_showOverlay) {
       _showDebugMessage('[$level] $objectStr');
     }
   } catch (e) {
     developer.log('日志记录时发生异常: $e'); // 捕获日志记录中的异常并记录
   }
 }

 // 显示调试信息的弹窗
 static void _showDebugMessage(String message) {
   _debugMessages.add(message);
   if (_debugMessages.length > 6) {
     _debugMessages.removeAt(0);
   }

   _hideOverlay();  // 先清理已有的弹窗

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
   _timer = Timer(Duration(seconds: _messageDisplayDuration), () {
     if (_debugMessages.isNotEmpty) {
       _debugMessages.removeAt(0);
       if (_debugMessages.isEmpty) {
         _hideOverlay();
       } else {
         _overlayEntry?.markNeedsBuild();
       }
     }
   });
 }

 // 封装的日志记录方法，增加参数检查并记录堆栈位置
 static Future<void> logError(String message, dynamic error, [StackTrace? stackTrace]) async {
   if (!debugMode) return; // 如果 debugMode 为 false，不记录日志

   stackTrace ??= StackTrace.current; // 使用当前堆栈信息

   if (message?.isNotEmpty != true || error == null) {
     await LogUtil.e('参数不匹配或为空: $message, $error, 堆栈信息: $stackTrace');
     return;
   }

   await _log('e', '错误: $message\n错误详情: $error\n堆栈信息: ${_processStackTrace(stackTrace)}', _defTag);
 }

 // 安全执行方法，捕获并记录异常
 static Future<void> safeExecute(void Function()? action, String errorMessage, [StackTrace? stackTrace]) async {
   if (action == null) {
     await logError('$errorMessage - 函数调用时参数为空或不匹配', 'action is null', stackTrace ?? StackTrace.current);
     return;
   }

   try {
     action(); // 执行传入的函数
   } catch (error, st) {
     await logError(errorMessage, error, st); // 捕获并记录异常
   }
 }

 // 获取文件名和行号，记录 frames
 static String _getFileAndLine() {
   try {
     final frames = StackTrace.current.toString().split('\n');

     // 记录 frames 到日志
     String frameInfo = frames.join('\n'); // 将 frames 转换为字符串
     developer.log('堆栈信息:\n$frameInfo'); // 记录到日志

     // 从第三帧开始遍历堆栈信息，尝试找到业务代码相关的文件名和行号
     for (int i = 2; i < frames.length; i++) {
       final frame = frames[i]; // 获取当前帧

       // 修改后的正则表达式，忽略列号，只捕获文件名和行号
       final match = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);

       // 过滤掉与 LogUtil 相关的堆栈帧
       if (match != null && !frame.contains('log_util.dart')) {
         // 返回捕获到的文件名和行号
         return '${match.group(1)}:${match.group(2)}';
       }
     }
   } catch (e) {
     return 'Unknown'; // 捕获任何异常，避免日志记录失败
   }
   return 'Unknown';
 }

 // 提取和处理堆栈信息，过滤掉无关帧
 static String _processStackTrace(StackTrace stackTrace) {
   try {
     final frames = stackTrace.toString().split('\n');
     for (int i = 2; i < frames.length; i++) {
       final frame = frames[i];

       // 忽略 log_util.dart 中的堆栈信息
       final match = RegExp(r'([^/\\]+\.dart):(\d+)').firstMatch(frame);
       if (match != null && !frame.contains('log_util.dart')) {
         return '${match.group(1)}:${match.group(2)}'; // 返回业务代码文件和行号
       }
     }
   } catch (e) {
     return 'Unknown'; // 捕获任何异常，避免日志记录失败
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

 // 清空日志，支持传入参数来清空特定类型的日志
 static Future<void> clearLogs([String? level]) async {
   if (level == null) {
     _logs.clear(); // 清空所有日志
   } else {
     _logs.removeWhere((log) => log['level'] == level); // 清空特定类型的日志
   }
   await _saveLogsToStorage(); // 同步清理持久化存储的日志
 }

 // 解析日志消息，展示实际内容时只提取消息部分，保留文件和行号信息
 static String parseLogMessage(String message) {
   // 按 '|' 分割，返回第二部分，即实际的日志内容和文件名行号
   List<String> parts = message.split('|');
   if (parts.length >= 2) {
     return parts[1].trim(); // 保留文件名和行号信息
   }
   return message; // 如果日志格式不符，返回原始信息
 }
}
