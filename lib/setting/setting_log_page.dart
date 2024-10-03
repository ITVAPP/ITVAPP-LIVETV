import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
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
  final FocusNode _logListFocusNode = FocusNode(); // 管理日志列表的焦点
  final FocusNode _clearLogsButtonFocusNode = FocusNode(); // 清空日志按钮焦点
  final FocusNode _copyButtonFocusNode = FocusNode(); // 复制按钮焦点

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
    _focusNodes[0].requestFocus(); // 页面加载时，将焦点默认设置到第一个过滤按钮
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    // 释放所有焦点节点和滚动控制器
    for (var node in _focusNodes) {
      node.dispose();
    }
    _logListFocusNode.dispose();
    _clearLogsButtonFocusNode.dispose();
    _copyButtonFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 处理滚动逻辑
  void _handleScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      // 滚动到底部，焦点移动到清空日志按钮
      _clearLogsButtonFocusNode.requestFocus();
    } else if (_scrollController.position.pixels == _scrollController.position.minScrollExtent) {
      // 滚动到顶部，焦点移动到分类按钮
      _focusNodes[0].requestFocus();
    }
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 增加整体的内边距
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 内容左对齐
              children: [
                // 添加开关
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: SwitchListTile(
                    title: Text(
                      S.of(context).SwitchTitle,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), // 修改后的字号为 18
                    ), 
                    subtitle: Text(
                      S.of(context).logSubtitle,
                      style: TextStyle(fontSize: 16), // 修改后的字号为 16
                    ),
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
                        FocusTraversalGroup( // 增加 FocusTraversalGroup 来管理焦点顺序
                          child: Padding(
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
                        ),
                        Flexible(
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
                                  child: Focus(
                                    focusNode: _logListFocusNode, // 管理日志列表的焦点
                                    onKey: (FocusNode node, RawKeyEvent event) {
                                      if (event is RawKeyDownEvent) {
                                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                          if (_scrollController.position.atEdge &&
                                              _scrollController.position.pixels ==
                                                  _scrollController.position.maxScrollExtent) {
                                            // 到达底部，焦点移到清空日志按钮
                                            _clearLogsButtonFocusNode.requestFocus();
                                            return KeyEventResult.handled;
                                          } else {
                                            _scrollController.jumpTo(
                                                _scrollController.offset + 50); // 下滚动
                                            return KeyEventResult.handled;
                                          }
                                        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                          if (_scrollController.position.atEdge &&
                                              _scrollController.position.pixels ==
                                                  _scrollController.position.minScrollExtent) {
                                            // 到达顶部，焦点移到第一个过滤按钮
                                            _focusNodes[0].requestFocus();
                                            return KeyEventResult.handled;
                                          } else {
                                            _scrollController.jumpTo(
                                                _scrollController.offset - 50); // 上滚动
                                            return KeyEventResult.handled;
                                          }
                                        }
                                      }
                                      return KeyEventResult.ignored;
                                    },
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
                                                          IconButton(
                                                            focusNode: _copyButtonFocusNode, // 为复制按钮添加焦点
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
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: ElevatedButton(
                            focusNode: _clearLogsButtonFocusNode, // 为清空日志按钮添加焦点
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
                                fontSize: 18, // 设置字体大小为 16
                                color: Colors.white, // 设置文字颜色为白色
                                fontWeight: _clearLogsButtonFocusNode.hasFocus
                                    ? FontWeight.bold // 选中或焦点时文字加粗
                                    : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center, // 文字居中对齐
                            ),
                            style: ElevatedButton.styleFrom(
                              shape: _buttonShape, // 统一圆角样式
                              backgroundColor: _clearLogsButtonFocusNode.hasFocus
                                  ? const Color(0xFFFE8401) // 焦点时背景颜色为 #FE8401
                                  : const Color(0xFFEB144C), // 未选中时背景颜色为 #EB144C
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // 设置按钮内边距
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16, // 设置字体大小
            color: Colors.white, // 设置文字颜色为白色
            fontWeight: (_selectedLevel == level || _focusNodes[focusIndex].hasFocus)
                ? FontWeight.bold // 选中或焦点时文字加粗
                : FontWeight.normal,
          ),
          textAlign: TextAlign.center, // 文字居中对齐
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2.0), // 调整按钮的左右内边距
          shape: _buttonShape, // 统一圆角样式
          backgroundColor: _selectedLevel == level || _focusNodes[focusIndex].hasFocus
              ? const Color(0xFFFE8401) // 选中或焦点时背景颜色为 #FE8401
              : const Color(0xFFEB144C), // 未选中时背景颜色为 #EB144C
          side: BorderSide.none, // 不需要边框
        ),
      ),
    );
  }
}
