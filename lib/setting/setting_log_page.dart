import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; // 导入日志工具类

/// 日志查看页面
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState();
}

class _SettinglogPageState extends State<SettinglogPage> {
  String _selectedLevel = 'all';
  int _logLimit = 100; // 初始加载条数
  bool _hasMoreLogs = true; // 是否还有更多日志

  // 获取有限的日志
  List<Map<String, String>> getLimitedLogs() {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? LogUtil.getLogs()
        : LogUtil.getLogsByLevel(_selectedLevel);

    if (logs.length > _logLimit) {
      _hasMoreLogs = true;
      return logs.sublist(0, _logLimit); // 返回限制条数的日志
    } else {
      _hasMoreLogs = false;
      return logs; // 没有更多日志时，返回所有日志
    }
  }

  // 加载更多日志
  void _loadMoreLogs() {
    setState(() {
      _logLimit += 100; // 每次增加100条
    });
  }

  // 格式化时间
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} "
           "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, String>> logs = getLimitedLogs();

    return Scaffold(
      appBar: AppBar(
        title: Text('日志查看器'),
      ),
      body: Column(
        children: [
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
                : Scrollbar(
                    isAlwaysShown: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        children: [
                          DataTable(
                            columns: [
                              DataColumn(label: Text('时间')),
                              DataColumn(label: Text('类型')),
                              DataColumn(label: Text('日志信息')),
                            ],
                            rows: logs
                                .map((log) => DataRow(cells: [
                                      DataCell(Text(formatDateTime(log['time']!))),
                                      DataCell(Text(log['level']!)),
                                      DataCell(Text(log['message']!)),
                                    ]))
                                .toList(),
                          ),
                          if (_hasMoreLogs) // 仅当有更多日志时显示加载更多按钮
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: ElevatedButton(
                                onPressed: _loadMoreLogs,
                                child: Text('加载更多'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  LogUtil.clearLogs();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('日志已清空'),
                    action: SnackBarAction(
                      label: '撤销',
                      onPressed: () {
                        setState(() {
                          LogUtil.restorePreviousLogs(); // 恢复之前的日志
                        });
                      },
                    ),
                  ),
                );
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
            _logLimit = 100; // 切换过滤条件时重置分页
          });
        },
        child: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _selectedLevel == level
              ? Theme.of(context).colorScheme.secondary
              : Colors.grey,
        ),
      ),
    );
  }
}
