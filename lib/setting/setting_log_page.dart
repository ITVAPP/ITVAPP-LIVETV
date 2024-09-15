import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:flutter/services.dart';  // 添加 Clipboard 的包
import '../generated/l10n.dart';

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

  // 为 TV 焦点管理增加焦点节点
  final List<FocusNode> _focusNodes = List.generate(5, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    // 页面加载时，将焦点默认设置到第一个过滤按钮
    _focusNodes[0].requestFocus();
  }

  @override
  void dispose() {
    // 释放所有焦点节点，防止内存泄漏
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // 获取有限的日志并按日期排序
  List<Map<String, String>> getLimitedLogs() {
    List<Map<String, String>> logs = _selectedLevel == 'all'
        ? LogUtil.getLogs()
        : LogUtil.getLogsByLevel(_selectedLevel);

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
    List<Map<String, String>> logs = getLimitedLogs();
    var screenWidth = MediaQuery.of(context).size.width;

    bool isTV = context.watch<ThemeProvider>().isTV;
    bool isLogOn = context.watch<ThemeProvider>().isLogOn; // 获取日志开关状态
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下不显示返回按钮
        title: Text(S.of(context).logtitle),  // 页面标题
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
                    title: Text(S.of(context).SwitchTitle, style: TextStyle(fontWeight: FontWeight.bold)), // 选项标题
                    subtitle: Text(S.of(context).logSubtitle), // 选项的说明文字
                    value: isLogOn,
                    onChanged: (value) {
                      LogUtil.safeExecute(() {
                        context.read<ThemeProvider>().setLogOn(value); // 使用 ThemeProvider 更新日志状态
                      }, '设置日志开关状态时出错');
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
                          padding: const EdgeInsets.only(bottom: 10), // 控制按钮与表格的间距
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildFilterButton('all', S.of(context).filterAll, 0),
                              _buildFilterButton('v', S.of(context).filterVerbose, 1),
                              _buildFilterButton('e', S.of(context).filterError, 2),
                              _buildFilterButton('i', S.of(context).filterInfo, 3),
                              _buildFilterButton('d', S.of(context).filterDebug, 4),
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
                                      Text(S.of(context).noLogs, style: TextStyle(fontSize: 18, color: Colors.grey)),    //暂无日志
                                    ],
                                  ),
                                )
                              : Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical, // 去掉水平滚动，仅保留垂直滚动
                                    child: Column(
                                      children: logs
                                          .asMap()
                                          .map((index, log) => MapEntry(
                                                index,
                                                Focus(
                                                  focusNode: _focusNodes[index], // 使用焦点节点管理焦点
                                                  onKey: (FocusNode node, RawKeyEvent event) {
                                                    if (event is RawKeyDownEvent &&
                                                        (event.logicalKey == LogicalKeyboardKey.select ||
                                                            event.logicalKey == LogicalKeyboardKey.enter)) {
                                                      // 当按下 TV 端遥控器的确认键或回车键时复制日志内容到剪贴板
                                                      Clipboard.setData(ClipboardData(text: log['message']!));
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(S.of(context).logCopied), // 日志已复制
                                                        ),
                                                      );
                                                      return KeyEventResult.handled; // 事件已处理
                                                    }
                                                    return KeyEventResult.ignored; // 未处理的事件
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          formatDateTime(log['time']!), // 第一行时间
                                                          style: const TextStyle(
                                                              fontWeight: FontWeight.bold, fontSize: 16),
                                                        ),
                                                        Text(LogUtil.parseLogMessage(log['message']!)), // 第二行日志信息
                                                        const Divider(), // 分隔符
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ))
                                          .values
                                          .toList(),
                                    ),
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
                                  content: Text(S.of(context).logCleared),  //日志已清空
                                ),
                              );
                            },
                            child: Text(S.of(context).clearLogs),   //清空日志
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
    );
  }

  // 构建过滤按钮，并将焦点节点添加进去
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: OutlinedButton(
        focusNode: _focusNodes[focusIndex], // 使用焦点节点管理焦点
        onPressed: () {
          setState(() {
            _selectedLevel = level;
            _logLimit = 100; // 切换过滤条件时重置分页
          });
        },
        child: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2.0), // 调整按钮的左右内边距	
          shape: _buttonShape, // 统一圆角样式
          side: BorderSide(color: _selectedLevel == level ? _selectedColor : _unselectedColor),
          backgroundColor: _selectedLevel == level ? _selectedColor.withOpacity(0.1) : Colors.transparent,
        ),
      ),
    );
  }
}
