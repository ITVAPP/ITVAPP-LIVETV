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
 static const String _logsKey = 'ITVAPP_LIVETV_logs'; // 持久化存储的key
 static bool _isOperating = false; // 添加操作锁，防止并发问题
 static const int _maxSingleLogLength = 500; // 添加单条日志最大长度限制
 static const int _maxFileSizeBytes = 1 * 1024 * 1024; // 最大日志限制1MB
 
 // 新增：内存存储相关
 static final List<Map<String, String>> _memoryLogs = [];
 static final List<Map<String, String>> _newLogsBuffer = [];
 static const int _writeThreshold = 5;  // 累积5条日志才写入本地
 
 // 弹窗相关属性
 static bool _showOverlay = true; // 控制是否显示弹窗
 static OverlayEntry? _overlayEntry;  // 修改为单个 OverlayEntry
 static final List<String> _debugMessages = [];
 static Timer? _timer;
 static const int _messageDisplayDuration = 3;

 // 初始化方法，在应用启动时调用
static Future<void> init() async {
  try {
    await SpUtil.getInstance();
    _memoryLogs.clear();  // 初始化时先清空内存
    _newLogsBuffer.clear();  // 初始化时先清空缓冲区
    await _loadLogsFromLocal(); // 先从本地加载
    await _checkAndHandleLogSize(); // 再检查大小
  } catch (e) {
    developer.log('日志初始化失败: $e');
    await _clearLogs();
  }
}
 
 // 新增：从本地加载日志到内存
static Future<void> _loadLogsFromLocal() async {
  try {
    final String? logsStr = await SpUtil.getString(_logsKey);
    if (logsStr != null && logsStr.isNotEmpty) {
      final logs = logsStr
          .split('\n')
          .where((line) => line.isNotEmpty)
          .map((line) {
            try {
              // 尝试解析日志行
              final RegExp regex = RegExp(r'\[(.*?)\] \[(.*?)\] \[(.*?)\] \| (.*?) \| (.*)');
              final match = regex.firstMatch(line);
              if (match != null) {
                return {
                  'time': match.group(1) ?? '',
                  'level': match.group(2) ?? '',
                  'tag': match.group(3) ?? '',
                  'message': match.group(4) ?? '',
                  'fileInfo': match.group(5) ?? ''
                };
              }
              return null;
            } catch (e) {
              developer.log('解析日志行失败: $e');
              return null;
            }
          })
          .where((log) => log != null)
          .cast<Map<String, String>>()
          .toList();

      // 确保先清空现有内存日志
      _memoryLogs.clear();
      // 添加解析的日志到内存
      _memoryLogs.addAll(logs);
      developer.log('成功从本地加载 ${logs.length} 条日志');
    }
  } catch (e) {
    developer.log('从本地加载日志失败: $e');
  }
}

 // 检查并处理日志文件大小
 static Future<void> _checkAndHandleLogSize() async {
   try {
     final String? logsStr = await SpUtil.getString(_logsKey);
     if (logsStr != null) {
       int sizeInBytes = utf8.encode(logsStr).length;
       if (sizeInBytes > _maxFileSizeBytes) {
         developer.log('日志文件超过1MB，执行清理');
         await _clearLogs();
       }
     }
   } catch (e) {
     developer.log('检查日志大小失败: $e');
     await _clearLogs();
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
     String fileInfo = _getFileAndLine();
     
     String objectStr = object?.toString().replaceAll('\n', '\\n') ?? 'null';
     if (objectStr.length > _maxSingleLogLength) {
       objectStr = objectStr.substring(0, _maxSingleLogLength) + '... (日志已截断)';
     }
     
     // 创建日志条目
     Map<String, String> logEntry = {
       'time': time,
       'level': level,
       'message': objectStr,
       'tag': tag ?? _defTag,
       'fileInfo': fileInfo
     };

     // 添加到内存（新日志在前）
     _memoryLogs.insert(0, logEntry);
     // 添加到缓冲区（新日志在前）
     _newLogsBuffer.insert(0, logEntry);

     // 生成控制台日志消息
     String logMessage = '[${logEntry["time"]}] [${logEntry["level"]}] [${logEntry["tag"]}] | ${logEntry["message"]} | ${logEntry["fileInfo"]}';

     // 如果缓冲区达到阈值，写入本地
     if (_newLogsBuffer.length >= _writeThreshold) {
       await _flushToLocal();
     }

     developer.log(logMessage);

     if (_showOverlay) {
       _showDebugMessage('[${logEntry["level"]}] ${logEntry["message"]}');
     }
   } catch (e) {
     developer.log('日志记录失败: $e');
   }
}

 // 新增：将缓冲区的日志写入本地
static Future<void> _flushToLocal() async {
   if (_newLogsBuffer.isEmpty || _isOperating) return;
   
   _isOperating = true;
   List<Map<String, String>> logsToWrite = [];  // 移到这里声明
   try {
     logsToWrite = List.from(_newLogsBuffer);  // 赋值
     _newLogsBuffer.clear();
     
     // 1. 获取现有日志
     String? existingLogs = await SpUtil.getString(_logsKey) ?? '';
     
     // 2. 转换新日志为文本格式
     String newContent = logsToWrite.map((log) => 
       '[${log["time"]}] [${log["level"]}] [${log["tag"]}] | ${log["message"]} | ${log["fileInfo"]}'
     ).join('\n');
     
     // 3. 合并新旧日志，新日志在前
     String finalContent = newContent;
     if (existingLogs.isNotEmpty) {
       finalContent += '\n$existingLogs';
     }
     
     // 4. 写入合并后的日志
     await SpUtil.putString(_logsKey, finalContent);
   } catch (e) {
     developer.log('写入本地存储失败: $e');
     // 写入失败时，将日志放回缓冲区
     _newLogsBuffer.insertAll(0, logsToWrite);  // 现在可以访问 logsToWrite 了
   } finally {
     _isOperating = false;
   }
}

 // 显示调试信息的弹窗
static void _showDebugMessage(String message) {
  // 在开头插入新消息（最新的消息在最上面）
  _debugMessages.insert(0, message);
  if (_debugMessages.length > 6) {
    // 移除最后一条（最旧的）消息
    _debugMessages.removeLast();
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
  _timer = Timer.periodic(Duration(seconds: _messageDisplayDuration), (timer) {
    if (_debugMessages.isEmpty) {
      _hideOverlay();
      _timer?.cancel();
      _timer = null;
    } else {
      // 每次都移除最后一条（最旧的）消息
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

 // 获取所有日志（从内存获取）
 static List<Map<String, String>> getLogs() {
   try {
     return List.from(_memoryLogs);
   } catch (e) {
     developer.log('获取日志失败: $e');
     return [];
   }
 }
 
 // 按级别获取日志（从内存获取）
 static List<Map<String, String>> getLogsByLevel(String level) {
   try {
     return _memoryLogs.where((log) => log['level'] == level).toList();
   } catch (e) {
     developer.log('按级别获取日志失败: $e');
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
       await SpUtil.putString(_logsKey, '');
     } else {
       // 清空特定级别的日志
       _memoryLogs.removeWhere((log) => log['level'] == level);
       _newLogsBuffer.removeWhere((log) => log['level'] == level);
       final String updatedLogs = _memoryLogs.map((log) =>
         '[${log["time"]}] [${log["level"]}] [${log["tag"]}] | ${log["message"]} | ${log["fileInfo"]}'
       ).join('\n');
       await SpUtil.putString(_logsKey, updatedLogs);
     }
   } catch (e) {
     developer.log('清空日志失败: $e');
   } finally {
     _isOperating = false;
   }
 }

 // 内部清空日志方法
 static Future<void> _clearLogs() async {
   if (_isOperating) return;
   
   _isOperating = true;
   try {
     _memoryLogs.clear();  // 新增：清空内存日志
     _newLogsBuffer.clear();  // 新增：清空缓冲区
     await SpUtil.putString(_logsKey, '');
   } catch (e) {
     developer.log('清空日志失败: $e');
   } finally {
     _isOperating = false;
   }
 }

 // 解析日志消息，展示实际内容时只提取消息部分，保留文件和行号信息
static String parseLogMessage(String message) {
   try {
     // 新格式：[时间] [级别] [标签] | 消息内容 | 文件位置
     final RegExp regex = RegExp(r'\[.*?\] \[.*?\] \[.*?\] \| (.*?) \|');
     final match = regex.firstMatch(message);
     if (match != null) {
       return match.group(1)?.trim() ?? message;
     }
   } catch (e) {
     developer.log('解析日志消息失败: $e');
   }
   return message;
}
 
 // 应用退出时调用
 static Future<void> dispose() async {
   if (_newLogsBuffer.isNotEmpty) {
     await _flushToLocal();
   }
 }
}
