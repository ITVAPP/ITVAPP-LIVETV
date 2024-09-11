import 'dart:developer' as developer;
import 'package:flutter/material.dart';

class LogUtil {
  static const String _defTag = 'common_utils';
  static bool _debugMode = true; // 直接在这里设置是否记录日志，true 表示记录日志，false 表示不记录
  static List<Map<String, String>> _logs = []; // 存储所有类型的日志，包含级别和时间

  // 封装的日志记录方法
  static void logError(String message, dynamic error, StackTrace stackTrace) {
    LogUtil.e('$message: $error');
    LogUtil.e('堆栈信息: $stackTrace');
  }

  // 封装的安全执行方法，捕获并记录异常
  static void safeExecute(void Function() action, String errorMessage) {
    try {
      action();
    } catch (error, stackTrace) {
      logError(errorMessage, error, stackTrace);
    }
  }

  // 记录 verbose 日志
  static void v(Object? object, {String? tag}) {
    _log('v', object, tag);
  }

  // 记录错误日志
  static void e(Object? object, {String? tag}) {
    _log('e', object, tag);
  }

  // 记录信息日志
  static void i(Object? object, {String? tag}) {
    _log('i', object, tag);
  }

  // 记录调试日志
  static void d(Object? object, {String? tag}) {
    _log('d', object, tag);
  }

  // 通用日志记录方法
  static void _log(String level, Object? object, String? tag) {
    if (!_debugMode) return;  // 如果 _debugMode 为 false，不记录日志
    if (object == null) return; // 跳过 null 日志
    String time = DateTime.now().toString();
    String logMessage = '${tag ?? _defTag} $level | ${object.toString()}';
    _logs.add({'time': time, 'level': level, 'message': logMessage});
    developer.log(logMessage); // 使用 developer.log 记录日志
  }

  // 获取所有日志
  static List<Map<String, String>> getLogs() {
    return _logs;
  }

  // 获取指定类型的日志
  static List<Map<String, String>> getLogsByLevel(String level) {
    return _logs.where((log) => log['level'] == level).toList();
  }

  // 清空日志
  static void clearLogs() {
    _logs.clear();
  }
}

/// 日志查看页面
class LogViewerPage extends StatefulWidget {
  @override
  _LogViewerPageState createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  String _selectedLevel = 'all'; // 当前选中的日志级别

  @override
  Widget build(BuildContext context) {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? LogUtil.getLogs()
        : LogUtil.getLogsByLevel(_selectedLevel);

    return Scaffold(
      appBar: AppBar(
        title: Text('日志查看器'),
      ),
      body: Column(
        children: [
          // 日志类型切换按钮
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFilterButton('all', '所有日志'),
                _buildFilterButton('v', 'Verbose'),
                _buildFilterButton('e', 'Error'),
                _buildFilterButton('i', 'Info'),
                _buildFilterButton('d', 'Debug'),
              ],
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? Center(child: Text('暂无日志'))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text('时间')),
                        DataColumn(label: Text('类型')),
                        DataColumn(label: Text('日志信息')),
                      ],
                      rows: logs
                          .map((log) => DataRow(cells: [
                                DataCell(Text(log['time']!)),
                                DataCell(Text(log['level']!)),
                                DataCell(Text(log['message']!)),
                              ]))
                          .toList(),
                    ),
                  ),
          ),
          // 清空日志按钮
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  LogUtil.clearLogs();
                });
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('日志已清空')));
              },
              child: Text('清空日志'),
            ),
          ),
        ],
      ),
    );
  }

  // 构建过滤按钮
  Widget _buildFilterButton(String level, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _selectedLevel = level;
          });
        },
        child: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _selectedLevel == level
              ? Theme.of(context).primaryColor
              : Colors.grey,
        ),
      ),
    );
  }
}
