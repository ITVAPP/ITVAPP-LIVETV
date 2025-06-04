import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';

class LogUtil {
  static String setLogFileKeywords = ''; // 调试时可以设置只记录某些文件的日志，多个文件用 @@ 分隔文件名关键字
  static const String _defTag = 'common_utils'; // 默认日志标签
  static bool debugMode = true; // 调试模式开关
  static const int _maxSingleLogLength = 888; // 单条日志最大长度
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 日志文件最大大小（5MB）
  static final List<String> _memoryLogs = []; // 内存中的日志缓存
  static final List<String> _activeBuffer = []; // 活动缓冲区
  static final List<String> _pendingBuffer = []; // 待写入缓冲区
  static const int _writeThreshold = 5; // 缓冲区达到此阈值时触发写入
  static const String _logFileName = 'ITVAPP_LIVETV_logs.txt'; // 日志文件名
  static String? _logFilePath; // 日志文件路径，可为空以增强容错性
  static File? _logFile; // 日志文件对象，可为空以增强容错性
  static const int _maxMemoryLogSize = 100; // 内存日志最大条数
  static Timer? _memoryCleanupTimer; // 定时清理内存日志的定时器
  static bool _showOverlay = false; // 是否显示浮层调试信息
  static OverlayEntry? _overlayEntry; // 浮层入口对象
  static final List<String> _debugMessages = []; // 调试消息列表
  static ValueNotifier<List<String>> _debugMessagesNotifier = ValueNotifier([]); // 调试消息通知器
  static Timer? _timer; // 浮层自动隐藏定时器
  static const int _messageDisplayDuration = 5; // 单条消息显示时长（秒）
  static OverlayState? _cachedOverlayState; // 缓存的浮层状态
  static const int _maxStackFramesToShow = 1; // 最大显示调用帧数量，可根据需求调整
  static final RegExp _stackFramePattern = RegExp(r'([^/\\]+\.dart):(\d+)'); // 堆栈帧解析正则
  
  // 合并重复的正则表达式映射
  static final Map<String, RegExp> _levelPatterns = { // 日志级别正则表达式映射
    'v': RegExp(r'\[v\]'),
    'e': RegExp(r'\[e\]'),
    'i': RegExp(r'\[i\]'),
    'd': RegExp(r'\[d\]'),
  };
  
  static final Map<String, String> _replacements = { // 特殊字符替换规则
    '\n': '\\n',
    '\r': '\\r',
    '|': '\\|',
    '[': '\\[',
    ']': '\\]'
  };
  
  // 写入队列，确保写入操作按顺序执行
  static Future<void>? _writeQueue;
  static RandomAccessFile? _randomAccessFile; // 使用 RandomAccessFile 提高性能
  
  // 新增：文件状态标志位，减少文件存在性检查
  static bool _fileValid = false;
  static int _currentFileSize = 0; // 跟踪当前文件大小

  // 初始化方法，在应用启动时调用以设置日志系统
  static Future<void> init() async {
    try {
      _memoryLogs.clear();
      _activeBuffer.clear();
      _pendingBuffer.clear();

      _logFilePath ??= await _getLogFilePath(); // 初始化日志文件路径
      _logFile ??= File(_logFilePath!); // 初始化日志文件对象

      if (!await _logFile!.exists()) { // 如果日志文件不存在则创建
        await _logFile!.create();
        _fileValid = true;
        _currentFileSize = 0;
        _logInternal('创建日志文件: $_logFilePath');
      } else { // 检查文件大小，超限则清理
        final int sizeInBytes = await _logFile!.length();
        _currentFileSize = sizeInBytes;
        _fileValid = true;
        if (sizeInBytes > _maxFileSizeBytes) {
          _logInternal('日志文件超过大小限制，执行清理');
          await clearLogs(isAuto: true);
        }
      }
      
      // 打开随机访问文件以提高写入性能
      try {
        _randomAccessFile = await _logFile!.open(mode: FileMode.append);
      } catch (e) {
        _logInternal('打开随机访问文件失败，使用普通文件写入: $e');
      }

      _memoryCleanupTimer?.cancel(); // 重置内存清理定时器
      _memoryCleanupTimer = Timer.periodic(Duration(seconds: 30), (_) {
        _cleanupMemoryLogs();
      });
    } catch (e) {
      _logInternal('日志初始化失败: $e');
      _logFilePath = null; // 重置路径以便重试
      _logFile = null;
      _fileValid = false;
      await clearLogs(isAuto: true);
    }
  }

  // 获取日志文件路径，使用应用文档目录
  static Future<String> _getLogFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_logFileName';
  }

  // 记录日志，包含级别、内容和标签，支持缓冲区检查
  static Future<void> _log(String level, Object? object, String? tag) async {
    if (!debugMode || object == null) return;

    // 检查当前位置的文件名是否匹配关键字（大小写不敏感）
    if (setLogFileKeywords.isNotEmpty) {
      String stackInfo = _extractStackInfo(); // 获取调用栈信息
      // 从调用栈信息中提取当前位置的文件名（最后一个调用帧）
      String currentFile = stackInfo.split(' -> ').last.split(':').first;
      String currentFileLower = currentFile.toLowerCase(); // 转换为小写
      List<String> keywords = setLogFileKeywords
          .split('@@')
          .map((k) => k.trim().toLowerCase())
          .toList(); // 解析关键字并转换为小写
      bool matches = keywords.any((keyword) => currentFileLower.contains(keyword));
      if (!matches) {
        return; // 如果当前位置的文件名不包含任一关键字，直接返回，不记录日志
      }
    }

    try {
      String time = DateTime.now().toString(); // 获取当前时间戳
      String fileInfo = _extractStackInfo(); // 提取调用栈信息
      String objectStr = object.toString();
      String logContent;
      if (objectStr.length > _maxSingleLogLength) { // 超长日志截断处理
        logContent = objectStr.substring(0, _maxSingleLogLength) + ' (截断) ...';
      } else { // 未超长直接使用
        logContent = objectStr;
      }

      // 格式化日志内容
      logContent = _formatLogString(logContent);
      
      // 使用 StringBuffer 优化字符串拼接
      final logMessage = StringBuffer()
        ..write('[')
        ..write(time)
        ..write('] [')
        ..write(level)
        ..write('] [')
        ..write(tag ?? _defTag)
        ..write('] | ')
        ..write(logContent)
        ..write(' | ')
        ..write(fileInfo);
      
      String logMessageStr = logMessage.toString();
      _addLogToBuffers(logMessageStr);
      _logInternal(logMessageStr);
      if (_showOverlay) {
        String displayMessage = _unformatLogString(logContent);
        _showDebugMessage('[${level}] $displayMessage');
      }

      _logInternal('当前缓冲区大小: ${_activeBuffer.length}');
      if (_activeBuffer.length >= _writeThreshold) { // 缓冲区满时触发写入
        await _triggerFlush();
      }
    } catch (e) {
      _logInternal('日志记录失败: $e');
      if (_activeBuffer.isNotEmpty) { // 异常时尝试保存缓冲区
        await _triggerFlush();
      }
    }
  }

  // 触发缓冲区刷新，使用队列保证顺序执行
  static Future<void> _triggerFlush() async {
    // 交换缓冲区，确保新日志可以继续写入活动缓冲区
    _pendingBuffer.addAll(_activeBuffer);
    _activeBuffer.clear();
    
    // 将写入操作加入队列
    _writeQueue = _writeQueue?.then((_) => _flushToLocal()) ?? _flushToLocal();
    await _writeQueue;
  }

  // 将待写入缓冲区的日志写入本地文件
  static Future<void> _flushToLocal() async {
    if (_pendingBuffer.isEmpty) return;
    
    List<String> logsToWrite = List.from(_pendingBuffer);
    _pendingBuffer.clear();
    
    try {
      // 优化：只在文件标志无效时检查文件存在性
      if (!_fileValid || _logFile == null) {
        _logFilePath = await _getLogFilePath();
        _logFile = File(_logFilePath!);
        if (!await _logFile!.exists()) {
          await _logFile!.create();
          _currentFileSize = 0;
          _logInternal('重新创建日志文件: $_logFilePath');
        }
        _fileValid = true;
        // 重新打开随机访问文件
        try {
          await _randomAccessFile?.close();
          _randomAccessFile = await _logFile!.open(mode: FileMode.append);
        } catch (e) {
          _logInternal('重新打开随机访问文件失败: $e');
        }
      }
      
      // 准备写入内容
      String contentToWrite = logsToWrite.join('\n') + '\n';
      int contentSize = utf8.encode(contentToWrite).length;
      
      // 检查是否会超过文件大小限制
      if (_currentFileSize + contentSize > _maxFileSizeBytes) {
        _logInternal('写入将导致文件超限，先执行自动清理');
        await clearLogs(isAuto: true);
      }
      
      // 使用 RandomAccessFile 写入（如果可用）
      if (_randomAccessFile != null) {
        await _randomAccessFile!.writeString(contentToWrite);
        await _randomAccessFile!.flush();
      } else {
        await _logFile!.writeAsString(
          contentToWrite,
          mode: FileMode.append,
        );
      }
      
      _currentFileSize += contentSize;
      _logInternal('成功写入日志，条数: ${logsToWrite.length}');
    } catch (e) {
      developer.log('写入日志文件失败: $e');
      _pendingBuffer.insertAll(0, logsToWrite); // 失败时回滚缓冲区
      _fileValid = false; // 标记文件状态无效
      if (e is IOException) {
        developer.log('IO异常，可能是权限或空间不足: $e');
      }
    }
  }

  // 设置调试模式开关
  static void setDebugMode(bool isEnabled) {
    debugMode = isEnabled;
  }

  // 设置是否显示浮层调试信息
  static void setShowOverlay(bool show) {
    _showOverlay = show;
    if (!show) {
      _hideOverlay();
    }
  }

  // 从 Provider 更新调试模式状态
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

  // Verbose 级别日志记录
  static Future<void> v(Object? object, {String? tag}) async {
    await _log('v', object, tag);
  }

  // Error 级别日志记录
  static Future<void> e(Object? object, {String? tag}) async {
    await _log('e', object, tag);
  }

  // Info 级别日志记录
  static Future<void> i(Object? object, {String? tag}) async {
    await _log('i', object, tag);
  }

  // Debug 级别日志记录
  static Future<void> d(Object? object, {String? tag}) async {
    await _log('d', object, tag);
  }

  // Warning 级别日志记录（与 Info 级别相同处理）
  static Future<void> w(Object? object, {String? tag}) async {
    await _log('i', object, tag);
  }

  // 优化：单次遍历完成所有字符替换
  static String _replaceSpecialChars(String input, bool isFormat) {
    if (input.isEmpty) return input;
    
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if (isFormat) {
        // 格式化：特殊字符转义
        switch (char) {
          case '\n':
            buffer.write('\\n');
            break;
          case '\r':
            buffer.write('\\r');
            break;
          case '|':
            buffer.write('\\|');
            break;
          case '[':
            buffer.write('\\[');
            break;
          case ']':
            buffer.write('\\]');
            break;
          default:
            buffer.write(char);
        }
      } else {
        // 反格式化：转义字符还原
        if (i < input.length - 1 && char == '\\') {
          final nextChar = input[i + 1];
          switch (nextChar) {
            case 'n':
              buffer.write('\n');
              i++; // 跳过下一个字符
              break;
            case 'r':
              buffer.write('\r');
              i++;
              break;
            case '|':
              buffer.write('|');
              i++;
              break;
            case '[':
              buffer.write('[');
              i++;
              break;
            case ']':
              buffer.write(']');
              i++;
              break;
            default:
              buffer.write(char);
          }
        } else {
          buffer.write(char);
        }
      }
    }
    return buffer.toString();
  }

  // 格式化日志字符串，替换特殊字符
  static String _formatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, true);
  }

  // 反格式化日志字符串，恢复特殊字符
  static String _unformatLogString(String logMessage) {
    return _replaceSpecialChars(logMessage, false);
  }

  // 优化：添加日志时立即检查内存限制
  static void _addLogToBuffers(String logMessage) {
    _memoryLogs.add(logMessage);
    // 立即检查并清理超限的内存日志
    if (_memoryLogs.length > _maxMemoryLogSize) {
      int excess = _memoryLogs.length - _maxMemoryLogSize;
      _memoryLogs.removeRange(0, excess);
    }
    _activeBuffer.add(logMessage);
  }

  // 清理超限的内存日志
  static void _cleanupMemoryLogs() {
    if (_memoryLogs.length > _maxMemoryLogSize) {
      int excess = _memoryLogs.length - _maxMemoryLogSize;
      _memoryLogs.removeRange(0, excess);
      _logInternal('定时清理内存日志，移除 $excess 条');
    }
  }

  // 显示调试消息浮层
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

  static final navigatorObserver = NavigatorObserver(); // 导航观察者实例

  // 查找当前的 OverlayState
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

  // 隐藏调试浮层
  static void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 启动浮层自动隐藏定时器
  static void _startAutoHideTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _messageDisplayDuration * _debugMessages.length), () {
      _debugMessages.clear();
      _debugMessagesNotifier.value = [];
      _hideOverlay();
      _timer = null;
    });
  }

  // 内部日志记录，仅在调试模式下生效
  static void _logInternal(String message) {
    if (debugMode) {
      developer.log(message);
    }
  }

  // 记录错误日志，包含消息、错误详情和堆栈信息
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

  // 安全执行方法，捕获并记录异常
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

  // 改进的调用栈提取方法 - 支持多层调用链显示
  static String _extractStackInfo({StackTrace? stackTrace}) {
    try {
      final frames = (stackTrace ?? StackTrace.current).toString().split('\n');
      String frameInfo = frames.join('\n');
      _logInternal('堆栈信息:\n$frameInfo');

      List<String> validFrames = []; // 存储有效的调用帧信息
      
      // 从第3帧开始扫描，跳过_extractStackInfo和_log方法本身
      for (int i = 2; i < frames.length && validFrames.length < _maxStackFramesToShow; i++) {
        final frame = frames[i];
        final match = _stackFramePattern.firstMatch(frame);
        
        if (match != null) {
          String fileName = match.group(1)!;
          String lineNumber = match.group(2)!;
          
          // 排除日志工具类本身的调用帧
          if (!frame.contains('log_util.dart')) {
            validFrames.add('$fileName:$lineNumber');
          }
        }
      }
      
      if (validFrames.isEmpty) {
        return 'Unknown';
      }
      
      // 将调用帧按调用时间顺序连接（最先发起的调用在前）
      return validFrames.reversed.join(' -> ');
      
    } catch (e) {
      _logInternal('提取调用栈信息失败: $e');
      return 'Unknown';
    }
  }

  // 解析日志字符串为键值对
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

  // 获取所有内存日志，按时间倒序返回
  static List<Map<String, String>> getLogs() {
    try {
      return _memoryLogs.reversed.map(_parseLogString).toList();
    } catch (e) {
      _logInternal('获取日志失败: $e');
      return [];
    }
  }

  // 按级别获取内存日志
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

  // 清理日志，可按级别或全部清理
  static Future<void> clearLogs({String? level, bool isAuto = false}) async {
    // 等待所有写入操作完成
    await _writeQueue;
    
    try {
      if (level == null) { // 清理所有日志
        _memoryLogs.clear();
        _activeBuffer.clear();
        _pendingBuffer.clear();

        if (_logFile != null && await _logFile!.exists()) {
          if (isAuto) { // 自动清理时保留一半日志
            final lines = await _logFile!.readAsLines();
            if (lines.isNotEmpty) {
              final endIndex = lines.length ~/ 2;
              final remainingLogs = lines.sublist(0, endIndex);
              // 关闭并重新打开文件
              await _randomAccessFile?.close();
              await _logFile!.writeAsString(remainingLogs.join('\n') + '\n');
              _randomAccessFile = await _logFile!.open(mode: FileMode.append);
              // 更新文件大小
              _currentFileSize = utf8.encode(remainingLogs.join('\n') + '\n').length;
            }
          } else { // 手动清理时删除文件
            await _randomAccessFile?.close();
            _randomAccessFile = null;
            await _logFile!.delete();
            _fileValid = false;
            _currentFileSize = 0;
          }
        }
      } else { // 按级别清理
        final pattern = _levelPatterns[level] ?? RegExp(r'\[' + level + r'\]');
        _memoryLogs.removeWhere((log) => pattern.hasMatch(log));
        _activeBuffer.removeWhere((log) => pattern.hasMatch(log));
        _pendingBuffer.removeWhere((log) => pattern.hasMatch(log));
        if (_logFile != null && await _logFile!.exists()) {
          await _randomAccessFile?.close();
          String content = _memoryLogs.join('\n') + '\n';
          await _logFile!.writeAsString(content);
          _randomAccessFile = await _logFile!.open(mode: FileMode.append);
          _currentFileSize = utf8.encode(content).length;
        }
      }
    } catch (e) {
      _logInternal('${level == null ? (isAuto ? "自动" : "手动") : "按级别"}清理日志失败: $e');
      _fileValid = false; // 标记文件状态无效
    }
  }

  // 从日志行中解析消息内容
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

  // 释放资源，清理所有状态
  static Future<void> dispose() async {
    // 等待所有写入操作完成
    await _writeQueue;
    
    // 将剩余缓冲区内容写入文件
    if (_activeBuffer.isNotEmpty || _pendingBuffer.isNotEmpty) {
      _pendingBuffer.addAll(_activeBuffer);
      _activeBuffer.clear();
      await _flushToLocal();
    }
    
    // 关闭文件句柄
    await _randomAccessFile?.close();
    _randomAccessFile = null;
    
    // 取消定时器
    _timer?.cancel();
    _timer = null;
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = null;
    
    // 清理浮层
    _hideOverlay();
    _cachedOverlayState = null;
    
    // 清理缓冲区和内存
    _memoryLogs.clear();
    _activeBuffer.clear();
    _pendingBuffer.clear();
    _debugMessages.clear();
    
    // dispose ValueNotifier
    _debugMessagesNotifier.dispose();
    _debugMessagesNotifier = ValueNotifier([]);
    
    // 重置写入队列
    _writeQueue = null;
    
    // 重置文件状态
    _fileValid = false;
    _currentFileSize = 0;
  }
}
