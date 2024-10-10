import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
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
  final ScrollController _scrollController = ScrollController(); // 控制日志列表滚动

  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16), // 统一圆角样式
  );
  final Color selectedColor = const Color(0xFFEB144C); // 选中时背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时背景颜色

  // 设置焦点节点
  final List<FocusNode> _focusNodes = List.generate(7, (index) => FocusNode());

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器
    _focusNodes.forEach((node) => node.dispose()); // 释放所有焦点节点
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
        title: Text(
          S.of(context).logtitle,  // 页面标题
          style: const TextStyle(
            fontSize: 22, // 设置字号
            fontWeight: FontWeight.bold, // 设置加粗
          ),
        ),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下AppBar背景颜色
      ),
      body: TvKeyNavigation(
        focusNodes: _focusNodes,
        isHorizontalGroup: true, // 启用横向分组
        initialIndex: 0, // 设置初始焦点索引为 0
        isFrame: isTV ? true  : false , // TV 模式下启用框架模式
        frameType: isTV ? "child" : null, // TV 模式下设置为子页面
        child: Align(
          alignment: Alignment.center, // 内容居中显示
          child: Container(
            constraints: BoxConstraints(
              maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 增加整体的内边距
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // 内容左对齐
                children: [
                  Group(
                    groupIndex: 0, // 日志开关分组
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: FocusableItem(
                          focusNode: _focusNodes[0], // 为开关分配焦点节点
                          child: SwitchListTile(
                            title: Text(
                              S.of(context).SwitchTitle,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            subtitle: Text(
                              S.of(context).logSubtitle,
                              style: TextStyle(fontSize: 16),
                            ),
                            value: isLogOn,
                            onChanged: (value) {
                              LogUtil.safeExecute(() {
                                context.read<ThemeProvider>().setLogOn(value); // 使用 ThemeProvider 更新日志状态
                              }, '设置日志开关状态时出错');
                            },
                            activeColor: Colors.white, // 滑块的颜色
                            activeTrackColor: _focusNodes[0].hasFocus
                                ? selectedColor.withOpacity(0.1) // 焦点时透明版本颜色
                                : selectedColor, // 启动时背景颜色
                            inactiveThumbColor: Colors.white, // 关闭时滑块的颜色
                            inactiveTrackColor: Colors.grey, // 关闭时轨道的背景颜色
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isLogOn)
                    Expanded(
                      child: Column(
                        children: [
                          Group(
                            groupIndex: 1, // 过滤按钮分组
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10), // 控制按钮与表格的间距
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildFilterButton('all', S.of(context).filterAll, 1),
                                    _buildFilterButton('v', S.of(context).filterVerbose, 2),
                                    _buildFilterButton('e', S.of(context).filterError, 3),
                                    _buildFilterButton('i', S.of(context).filterInfo, 4),
                                    _buildFilterButton('d', S.of(context).filterDebug, 5),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Group(
                            groupIndex: 2, // 日志内容分组
                            children: [
                              FocusableItem(
                                focusNode: _focusNodes[6], // 为日志区域分配焦点
                                child: Flexible(
                                  child: logs.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.info_outline, size: 50, color: Colors.grey),
                                              SizedBox(height: 10),
                                              Text(S.of(context).noLogs, style: TextStyle(fontSize: 18, color: Colors.grey)),    //暂无日志
                                            ],
                                          ),
                                        )
                                      : Scrollbar(
                                          thumbVisibility: true,
                                          controller: _scrollController, // 使用滚动控制器
                                          child: SingleChildScrollView(
                                            controller: _scrollController, // 日志列表使用同一滚动控制器
                                            scrollDirection: Axis.vertical, // 仅垂直滚动
                                            child: Column(
                                              children: logs
                                                  .map((log) => Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Padding(
                                                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                                                            child: Row(
                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                              children: [
                                                                Text(
                                                                  formatDateTime(log['time']!), // 第一行时间
                                                                  style: const TextStyle(
                                                                      fontWeight: FontWeight.bold, fontSize: 16),
                                                                ),
                                                                // 仅在非TV模式下显示复制按钮
                                                                if (!isTV)
                                                                  IconButton(
                                                                    icon: Icon(Icons.copy, color: Colors.grey), // 复制按钮
                                                                    onPressed: () {
                                                                      // 将该条日志的内容复制到剪贴板
                                                                      String logContent = '${formatDateTime(log['time']!)}\n${LogUtil.parseLogMessage(log['message']!)}';
                                                                      Clipboard.setData(ClipboardData(text: logContent));
                                                                      // 显示复制成功的提示
                                                                      CustomSnackBar.showSnackBar(
                                                                        context,
                                                                        S.of(context).logCopied,  // 日志已复制
                                                                        duration: Duration(seconds: 4),
                                                                      );
                                                                    },
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          SelectableText(
                                                            LogUtil.parseLogMessage(log['message']!), // 可选择并复制日志信息
                                                            style: const TextStyle(fontSize: 14),
                                                          ),
                                                          const Divider(), // 分隔符
                                                        ],
                                                      ))
                                                  .toList(),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          Group(
                            groupIndex: 3, // 清空日志按钮分组
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: FocusableItem(
                                  focusNode: _focusNodes[7], // 为清空日志按钮添加焦点节点
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        if (_selectedLevel == 'all') {
                                          LogUtil.clearLogs(); // 清空所有日志
                                        } else {
                                          LogUtil.clearLogs(_selectedLevel); // 清空特定类型的日志
                                        }
                                      });
                                      CustomSnackBar.showSnackBar(
                                        context,
                                        S.of(context).logCleared,  //日志已清空
                                        duration: Duration(seconds: 4), 
                                      );
                                    },
                                    child: Text(
                                      S.of(context).clearLogs,  //清空日志
                                      style: TextStyle(
                                        fontSize: 18, // 设置字体大小
                                        color: Colors.white, // 设置文字颜色为白色
                                      ),
                                      textAlign: TextAlign.center, // 文字居中对齐
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      shape: _buttonShape, // 统一圆角样式
                                        backgroundColor: _focusNodes[7].hasFocus
                                            ? selectedColor.withOpacity(0.3) // 焦点时使用选中颜色的透明版本
                                            : (_selectedLevel == level
                                                ? selectedColor // 选中时使用完全不透明的颜色
                                                : unselectedColor), // 未选中时颜色
                                        side: BorderSide.none, // 不需要边框
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), // 设置按钮内边距
                                    ),
                                  ),
                                ),
                              ),
                            ],
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

  // 构建过滤按钮，增加焦点节点参数
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).orientation == Orientation.landscape ? 5.0 : 2.0,
      ),
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex], // 为每个过滤按钮添加焦点节点
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _selectedLevel = level;
              _logLimit = 100; // 切换过滤条件时重置分页
            });
          },
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16, // 设置字体大小
              color: Colors.white, // 设置文字颜色为白色
              fontWeight: (_selectedLevel == level)
                  ? FontWeight.bold // 选中时文字加粗
                  : FontWeight.normal,
            ),
            textAlign: TextAlign.center, // 文字居中对齐
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
            shape: _buttonShape, // 统一圆角样式
            backgroundColor: _focusNodes[focusIndex].hasFocus
                ? selectedColor.withOpacity(0.3) // 焦点时使用选中颜色的透明版本
                : (_selectedLevel == level
                    ? selectedColor // 选中时使用完全不透明的颜色
                    : unselectedColor), // 未选中时颜色
            side: BorderSide.none, // 不需要边框
          ),
        ),
      ),
    );
  }
}
