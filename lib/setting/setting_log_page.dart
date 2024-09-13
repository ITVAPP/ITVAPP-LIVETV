import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';

/// 日志查看页面
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState();
}

class _SettinglogPageState extends State<SettinglogPage> {
  String _selectedLevel = 'all';
  int _logLimit = 100; // 初始加载条数
  bool _hasMoreLogs = true; // 是否还有更多日志

  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30), // 统一圆角样式
  );
  final _selectedColor = const Color(0xFFEB144C); // 选中时颜色
  final _unselectedColor = Colors.grey[300]!; // 未选中时颜色，使用 ! 确保为非空

  // 异步获取有限的日志并按日期排序
  Future<List<Map<String, String>>> getLimitedLogsAsync() async {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? await LogUtil.getLogsAsync()
        : await LogUtil.getLogsByLevelAsync(_selectedLevel);

    // 按时间降序排序
    logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!)));

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
    var screenWidth = MediaQuery.of(context).size.width;
    bool isTV = context.watch<ThemeProvider>().isTV;
    bool isLogOn = context.watch<ThemeProvider>().isLogOn; // 获取日志开关状态
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), // 增加整体的内边距
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 内容左对齐
              children: [
                // 添加开关
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: SwitchListTile(
                    title: const Text('记录日志', style: TextStyle(fontWeight: FontWeight.bold)), // 选项标题
                    subtitle: const Text('如非调试应用，无需打开日志开关'), // 选项的说明文字
                    value: isLogOn,
                    onChanged: (value) {
                      context.read<ThemeProvider>().setLogOn(value); // 使用 ThemeProvider 更新日志状态
                    },
                    activeColor: Colors.white, // 滑块的颜色
                    activeTrackColor: const Color(0xFFEB144C), // 开启时轨道的背景颜色
                    inactiveThumbColor: Colors.white, // 关闭时滑块的颜色
                    inactiveTrackColor: Colors.grey, // 关闭时轨道的背景颜色
                  ),
                ),
                // 判断开关状态，如果关闭则不显示日志内容
                if (isLogOn)
                  Expanded(
                    child: FutureBuilder<List<Map<String, String>>>(
                      future: getLimitedLogsAsync(), // 异步获取日志数据
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator()); // 显示加载动画
                        } else if (snapshot.hasError) {
                          return Center(child: Text('加载日志时出错'));
                        } else {
                          List<Map<String, String>> logs = snapshot.data ?? [];

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10), // 控制按钮与表格的间距
                                child: Wrap( // 使用 Wrap 代替 Row，避免按钮超出边界
                                  spacing: 3, // 控制每个按钮之间的水平间距
                                  runSpacing: 3, // 控制每行之间的垂直间距
                                  alignment: WrapAlignment.center, // 按钮居中对齐
                                  children: [
                                    _buildFilterButton('all', '所有'),
                                    _buildFilterButton('v', '详细'),
                                    _buildFilterButton('e', '错误'),
                                    _buildFilterButton('i', '信息'),
                                    _buildFilterButton('d', '调试'),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: logs.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.info_outline, size: 60, color: Colors.grey),
                                            SizedBox(height: 10),
                                            Text('暂无日志', style: TextStyle(fontSize: 18, color: Colors.grey)),
                                          ],
                                        ),
                                      )
                                    : Scrollbar(
                                        thumbVisibility: true, // 替代 isAlwaysShown
                                        child: ListView.builder(
                                          itemCount: logs.length + (_hasMoreLogs ? 1 : 0),
                                          itemBuilder: (context, index) {
                                            if (index == logs.length) {
                                              return Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: ElevatedButton(
                                                  onPressed: _loadMoreLogs,
                                                  child: Text('加载更多'),
                                                  style: ElevatedButton.styleFrom(
                                                    shape: _buttonShape, // 统一圆角样式
                                                    backgroundColor: _selectedColor,
                                                  ),
                                                ),
                                              );
                                            }

                                            final log = logs[index];
                                            return ListTile(
                                              title: Text(formatDateTime(log['time']!)),
                                              subtitle: Text(log['message']!),
                                            );
                                          },
                                        ),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      LogUtil.clearLogs();
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
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建过滤按钮
  Widget _buildFilterButton(String level, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0), // 缩小每个按钮之间的间距
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _selectedLevel = level;
            _logLimit = 100; // 切换过滤条件时重置分页
          });
        },
        child: Text(
          label,
          style: TextStyle(fontSize: 12), // 缩小按钮文字的字体大小
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), // 减少按钮的内边距
          shape: _buttonShape, // 统一圆角样式
          side: BorderSide(color: _selectedLevel == level ? _selectedColor : _unselectedColor),
          backgroundColor: _selectedLevel == level ? _selectedColor.withOpacity(0.1) : Colors.transparent,
        ),
      ),
    );
  }
}
