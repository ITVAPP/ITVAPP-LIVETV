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

  final _scrollController = ScrollController(); // 用于控制滚动事件，自动加载更多
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30), // 统一圆角样式
  );
  final _selectedColor = const Color(0xFFEB144C); // 选中时颜色
  final _unselectedColor = Colors.grey[300]!; // 未选中时颜色，使用 ! 确保为非空

  // 焦点节点列表，用于 TV 端焦点管理，确保用户使用方向键时可以正确切换焦点
  final List<FocusNode> _focusNodes = List.generate(5, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    // 监听滚动事件，滚动到底部时加载更多日志
    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent && _hasMoreLogs) {
        _loadMoreLogs(); // 自动加载更多日志
      }
    });

    // 页面加载时，将焦点默认设置到第一个过滤按钮
    _focusNodes[0].requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器
    // 释放所有焦点节点资源，防止内存泄漏
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // 获取有限的日志
  List<Map<String, String>> getLimitedLogs() {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? LogUtil.getLogs() // 获取所有日志
        : LogUtil.getLogsByLevel(_selectedLevel); // 根据选定的日志级别获取日志

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
    List<Map<String, String>> logs = getLimitedLogs(); // 获取当前条件下的日志
    var screenWidth = MediaQuery.of(context).size.width; // 获取屏幕宽度

    bool isTV = context.watch<ThemeProvider>().isTV; // 判断是否处于TV模式
    bool isLogOn = context.watch<ThemeProvider>().isLogOn; // 获取日志开关状态
    double maxContainerWidth = 580; // 设置最大容器宽度

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
            child: FocusTraversalGroup( // 使用焦点组管理方向键焦点切换
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // 内容左对齐
                children: [
                  // 添加日志开关
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
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10), // 控制按钮与日志表格的间距
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildFilterButton('all', '所有', 0),
                                _buildFilterButton('v', '详细', 1),
                                _buildFilterButton('e', '错误', 2),
                                _buildFilterButton('i', '信息', 3),
                                _buildFilterButton('d', '调试', 4),
                              ],
                            ),
                          ),
                          Flexible(
                            // 显示日志内容
                            child: logs.isEmpty
                                ? Center(
                                    // 当没有日志时显示提示信息
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
                                    thumbVisibility: true, // 仅针对垂直方向显示滚动条
                                    child: ListView.builder(
                                      controller: _scrollController, // 控制滚动事件，滚动到底部时加载更多
                                      itemCount: logs.length + 1, // 日志数量加1，用于显示加载更多指示器
                                      itemBuilder: (context, index) {
                                        if (index == logs.length) {
                                          // 显示加载更多指示器
                                          return _hasMoreLogs
                                              ? Padding(
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Center(
                                                    child: CircularProgressIndicator(), // 显示加载中
                                                  ),
                                                )
                                              : SizedBox.shrink(); // 没有更多日志时不显示内容
                                        }
                                        // 显示每条日志的时间和消息内容
                                        return ListTile(
                                          title: Text(formatDateTime(logs[index]['time']!)), // 显示日志时间
                                          subtitle: Text(logs[index]['message']!), // 显示日志内容
                                        );
                                      },
                                    ),
                                  ),
                          ),
                          // 清空日志按钮
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  LogUtil.clearLogs(); // 清空日志
                                });
                                // 提示用户日志已清空
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 构建过滤按钮，并加入 TV 端的焦点管理
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: OutlinedButton(
        focusNode: _focusNodes[focusIndex], // 将过滤按钮与焦点节点关联
        onPressed: () {
          setState(() {
            _selectedLevel = level;
            _logLimit = 100; // 切换过滤条件时重置分页
          });
        },
        child: Text(label),
        style: OutlinedButton.styleFrom(
          shape: _buttonShape, // 统一圆角样式
          side: BorderSide(color: _selectedLevel == level ? _selectedColor : _unselectedColor),
          backgroundColor: _selectedLevel == level ? _selectedColor.withOpacity(0.1) : Colors.transparent,
        ),
      ),
    );
  }
}
