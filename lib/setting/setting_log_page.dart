import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; // 导入日志工具类
import 'package:itvapp_live_tv/provider/theme_provider.dart'; // 导入主题提供者

/// 日志查看页面
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState();
}

class _SettinglogPageState extends State<SettinglogPage> {
  String _selectedLevel = 'all';
  int _logLimit = 100; // 初始加载条数
  bool _hasMoreLogs = true; // 是否还有更多日志
  List<Map<String, String>> _logs = []; // 缓存的日志

  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30), // 统一圆角样式
  );
  final _selectedColor = const Color(0xFFEB144C); // 选中时颜色
  final _unselectedColor = Colors.grey[300]; // 未选中时颜色

  // 获取有限的日志并缓存
  void _fetchLogs() {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? LogUtil.getLogs()
        : LogUtil.getLogsByLevel(_selectedLevel);

    setState(() {
      _logs = logs.length > _logLimit ? logs.sublist(0, _logLimit) : logs;
      _hasMoreLogs = logs.length > _logLimit;
    });
  }

  // 加载更多日志
  void _loadMoreLogs() {
    setState(() {
      _logLimit += 100;
      _fetchLogs(); // 重新获取日志
    });
  }

  // 格式化时间
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} "
           "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    _fetchLogs(); // 初始化时获取日志
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;
    bool debugMode = context.watch<ThemeProvider>().debugMode; // 获取当前debugMode状态
    var screenWidth = MediaQuery.of(context).size.width;
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下不显示返回按钮
        title: const Text('日志查看器'), // 页面标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下AppBar背景颜色
      ),
      body: Align(
        alignment: Alignment.center, // 内容居中显示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
          ),
          child: Column(
            children: [
              // 调试模式开关
              SwitchListTile(
                title: Text('调试模式'),
                value: debugMode,
                onChanged: (bool value) {
                  context.read<ThemeProvider>().setDebugMode(value); // 更新调试模式状态
                  if (value) {
                    _fetchLogs(); // 调试模式打开时获取日志
                  }
                },
              ),
              
              // 日志过滤按钮
              Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterButton('all', '所有日志'),
                    _buildFilterButton('v', '详细'),
                    _buildFilterButton('e', '错误'),
                    _buildFilterButton('i', '信息'),
                    _buildFilterButton('d', '调试'),
                  ],
                ),
              ),

              // 仅在调试模式下显示日志表格
              if (debugMode)
                Expanded(
                  child: _logs.isEmpty
                      ? Center(child: Text('暂无日志'))
                      : Scrollbar(
                          thumbVisibility: true, // 替代 isAlwaysShown
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
                                  rows: _logs
                                      .map((log) => DataRow(cells: [
                                            DataCell(Text(formatDateTime(log['time']!))),
                                            DataCell(Text(log['level']!)),
                                            DataCell(Text(log['message']!)),
                                          ]))
                                      .toList(),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _hasMoreLogs
                                      ? ElevatedButton(
                                          onPressed: _loadMoreLogs,
                                          child: Text('加载更多'),
                                          style: ElevatedButton.styleFrom(
                                            shape: _buttonShape, // 统一圆角样式
                                            backgroundColor: _selectedColor,
                                          ),
                                        )
                                      : Text('无更多日志'),
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
                      _logs.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('日志已清空'),
                      ),
                    );
                  },
                  child: Text('清空日志'),
                  style: ElevatedButton.styleFrom(
                    shape: _buttonShape, // 统一圆角样式
                    backgroundColor: _selectedColor,
                  ),
                ),
              ),
            ],
          ),
        ),
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
            _fetchLogs(); // 根据过滤条件获取日志
          });
        },
        child: Text(label),
        style: ElevatedButton.styleFrom(
          shape: _buttonShape, // 统一圆角样式
          backgroundColor: _selectedLevel == level
              ? _selectedColor
              : _unselectedColor,
        ),
      ),
    );
  }
}
