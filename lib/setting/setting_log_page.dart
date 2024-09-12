import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; // 导入日志工具类

/// 日志查看页面
class LogViewerPage extends StatefulWidget {
  @override
  _LogViewerPageState createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  String _selectedLevel = 'all';

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
