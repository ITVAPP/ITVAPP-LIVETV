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
  String _selectedLevel = 'all';  // 日志过滤的初始级别，默认显示所有日志
  int _logLimit = 100; // 每次加载的日志条数，初始为100
  bool _hasMoreLogs = true; // 是否还有更多日志可加载，初始为true

  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30), // 定义过滤按钮的圆角样式
  );
  final _selectedColor = const Color(0xFFEB144C); // 过滤按钮选中的颜色
  final _unselectedColor = Colors.grey[300]!; // 过滤按钮未选中的颜色，使用 ! 确保为非空

  final ScrollController _scrollController = ScrollController(); // 控制日志列表的滚动，用于自动加载更多日志

  // 焦点节点列表，用于 TV 端焦点管理，确保用户使用方向键时可以正确切换焦点
  final List<FocusNode> _focusNodes = List.generate(5, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    // 监听滚动事件，当滚动到底部时加载更多日志
    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent && _hasMoreLogs) {
        _loadMoreLogs(); // 如果滚动到底部且有更多日志时，加载更多
      }
    });
    // 页面加载时，将焦点默认设置到第一个过滤按钮
    _focusNodes[0].requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器资源
    // 释放所有焦点节点资源，防止内存泄漏
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // 获取有限的日志，并按时间降序排列
  List<Map<String, String>> getLimitedLogs() {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? LogUtil.getLogs()  // 如果选中了“所有”，则获取所有日志
        : LogUtil.getLogsByLevel(_selectedLevel);  // 否则按日志级别过滤日志

    // 按时间降序排列日志，确保最新的日志在最上面
    logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!))); 

    if (logs.length > _logLimit) {
      _hasMoreLogs = true;  // 如果日志条数超过限制，表示还有更多日志
      return logs.sublist(0, _logLimit);  // 返回限制条数的日志
    } else {
      _hasMoreLogs = false;  // 没有更多日志时，将_hasMoreLogs设置为false
      return logs;  // 返回所有可用日志
    }
  }

  // 加载更多日志，将当前限制条数增加100
  void _loadMoreLogs() {
    setState(() {
      _logLimit += 100;  // 每次增加100条日志
    });
  }

  // 格式化时间字符串，使其变为更易读的格式
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime); // 将字符串解析为 DateTime 对象
    // 返回格式化后的时间字符串：年-月-日 时:分:秒
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} "
        "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, String>> logs = getLimitedLogs();  // 获取当前过滤条件下的有限日志
    var screenWidth = MediaQuery.of(context).size.width;  // 获取屏幕宽度

    bool isTV = context.watch<ThemeProvider>().isTV;  // 检查是否处于 TV 模式
    bool isLogOn = context.watch<ThemeProvider>().isLogOn;  // 获取日志开关的当前状态
    double maxContainerWidth = 580;  // 设置内容最大宽度

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // 如果是 TV 模式，设置特定的背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // 如果是 TV 模式，不显示返回按钮
        title: const Text('日志查看器'), // 设置页面标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // 如果是 TV 模式，设置 AppBar 背景颜色
      ),
      body: Align(
        alignment: Alignment.center,  // 内容居中显示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity,  // 如果屏幕宽度大于580，设置最大宽度为580，否则填满屏幕宽度
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), // 设置容器的内边距
            child: FocusTraversalGroup( // 在 TV 模式下，使用焦点组管理方向键焦点切换
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // 内容左对齐
                children: [
                  // 添加开关，用于控制是否开启日志记录
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: SwitchListTile(
                      title: const Text('记录日志', style: TextStyle(fontWeight: FontWeight.bold)), // 开关的标题
                      subtitle: const Text('如非调试应用，无需打开日志开关'), // 开关的说明文字
                      value: isLogOn,  // 当前开关状态
                      onChanged: (value) {
                        context.read<ThemeProvider>().setLogOn(value); // 当开关状态变化时，更新日志状态
                      },
                      activeColor: Colors.white, // 开启时滑块的颜色
                      activeTrackColor: const Color(0xFFEB144C), // 开启时轨道的背景颜色
                      inactiveThumbColor: Colors.white, // 关闭时滑块的颜色
                      inactiveTrackColor: Colors.grey, // 关闭时轨道的背景颜色
                    ),
                  ),
                  // 如果日志开关打开，显示日志内容；否则不显示
                  if (isLogOn)
                    Expanded(
                      child: Column(
                        children: [
                          // 日志过滤按钮组，用于选择不同的日志级别
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10), // 控制按钮与日志表格的间距
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center, // 过滤按钮居中显示
                              children: [
                                _buildFilterButton('all', '所有', 0), // "所有" 日志按钮
                                _buildFilterButton('v', '详细', 1), // "详细" 日志按钮
                                _buildFilterButton('e', '错误', 2), // "错误" 日志按钮
                                _buildFilterButton('i', '信息', 3), // "信息" 日志按钮
                                _buildFilterButton('d', '调试', 4), // "调试" 日志按钮
                              ],
                            ),
                          ),
                          // 显示日志内容
                          Flexible(
                            child: logs.isEmpty
                                ? Center(
                                    // 如果没有日志，显示提示信息
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.info_outline, size: 60, color: Colors.grey), // 提示图标
                                        SizedBox(height: 10),
                                        Text('暂无日志', style: TextStyle(fontSize: 18, color: Colors.grey)), // 提示文字
                                      ],
                                    ),
                                  )
                                : Scrollbar(
                                    thumbVisibility: true, // 显示滚动条
                                    child: ListView.builder(
                                      controller: _scrollController, // 使用滚动控制器实现滚动到底部时加载更多日志
                                      itemCount: logs.length + 1, // 日志条目数加1，用于显示“加载更多”按钮
                                      itemBuilder: (context, index) {
                                        if (index == logs.length) {
                                          return _hasMoreLogs
                                              ? Padding(
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Center(
                                                    child: CircularProgressIndicator(), // 如果有更多日志，显示加载指示器
                                                  ),
                                                )
                                              : SizedBox.shrink(); // 没有更多日志时不显示内容
                                        }
                                        // 每个日志条目
                                        return ListTile(
                                          title: Text(formatDateTime(logs[index]['time']!)), // 显示日志时间
                                          subtitle: Text(logs[index]['message']!), // 显示日志信息
                                        );
                                      },
                                    ),
                                  ),
                          ),
                          // 清空日志按钮，点击后清空所有日志
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  LogUtil.clearLogs(); // 清空日志数据
                                });
                                // 显示提示消息，日志已清空
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('日志已清空'),
                                  ),
                                );
                              },
                              child: Text('清空日志'), // 按钮文本
                              style: ElevatedButton.styleFrom(
                                shape: _buttonShape, // 设置按钮圆角
                                backgroundColor: _selectedColor, // 按钮背景颜色
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
            _selectedLevel = level;  // 根据点击的按钮更新过滤条件
            _logLimit = 100;  // 切换过滤条件时，重置日志加载条数为100
          });
        },
        child: Text(label), // 按钮文本
        style: OutlinedButton.styleFrom(
          shape: _buttonShape, // 设置按钮的圆角样式
          side: BorderSide(color: _selectedLevel == level ? _selectedColor : _unselectedColor), // 按钮边框颜色根据是否选中决定
          backgroundColor: _selectedLevel == level ? _selectedColor.withOpacity(0.1) : Colors.transparent, // 选中时按钮背景颜色
        ),
      ),
    );
  }
}
