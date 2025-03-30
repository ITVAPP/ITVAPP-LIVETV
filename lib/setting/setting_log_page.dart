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
  _SettinglogPageState createState() => _SettinglogPageState(); // 创建页面状态实例
}

class _SettinglogPageState extends State<SettinglogPage> {
  // 提取常用样式为静态常量，减少对象创建
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // 标题样式
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16); // 日志时间样式
  static const _logMessageStyle = TextStyle(fontSize: 14); // 日志消息样式

  String _selectedLevel = 'all'; // 当前选中的日志级别
  int _logLimit = 100; // 初始加载的日志条数
  bool _hasMoreLogs = true; // 标记是否还有更多日志可加载
  final ScrollController _scrollController = ScrollController(); // 控制日志列表滚动

  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)); // 按钮统一圆角样式
  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景颜色

  final List<FocusNode> _focusNodes = List.generate(7, (index) => FocusNode()); // 初始化7个焦点节点

  List<Map<String, String>>? _cachedLogs; // 缓存日志数据
  DateTime? _lastLogUpdate; // 记录最后一次日志更新时间
  static const _logCacheTimeout = Duration(seconds: 1); // 日志缓存有效期

  List<Map<String, String>> _logs = []; // 存储当前显示的日志数据
  final _dateTimeCache = <String, String>{}; // 缓存格式化后的时间字符串

  @override
  void initState() {
    super.initState();
    _updateLogs(); // 初始化时加载日志数据
    for (var focusNode in _focusNodes) { // 为每个焦点节点添加监听
      focusNode.addListener(() {
        if (mounted && focusNode.hasFocus != focusNode.hasPrimaryFocus) {
          setState(() {}); // 焦点状态变化时触发重绘
        }
      });
    }
    _scrollController.addListener(_checkScrollPosition); // 添加滚动监听以检测加载更多
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器资源
    _focusNodes.forEach((node) => node.dispose()); // 释放所有焦点节点资源
    LogUtil.safeExecute(() => LogUtil.log('资源释放完成', level: 'd'), '资源释放日志记录失败'); // 记录资源释放日志
    super.dispose();
  }

  void _checkScrollPosition() { // 检查滚动位置以提示加载更多
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50 && _hasMoreLogs) {
      CustomSnackBar.showSnackBar(context, '滑动到底部，可点击加载更多', duration: Duration(seconds: 2));
    }
  }

  void _updateLogs() { // 更新状态中的日志数据
    setState(() {
      _logs = getLimitedLogs(); // 获取并更新日志列表
    });
  }

  List<Map<String, String>> getLimitedLogs() { // 获取有限日志并排序，带缓存和异常处理
    final now = DateTime.now();
    final currentLogs = LogUtil.safeExecute(
          () => _selectedLevel == 'all' ? LogUtil.getLogs() : LogUtil.getLogsByLevel(_selectedLevel),
          '获取日志失败',
        ) ?? [];
    if (_cachedLogs != null && _lastLogUpdate != null && // 检查缓存是否有效
        now.difference(_lastLogUpdate!) <= _logCacheTimeout &&
        currentLogs.length == _cachedLogs!.length) {
      return _cachedLogs!;
    }
    currentLogs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!))); // 按时间降序排序
    _hasMoreLogs = currentLogs.length > _logLimit; // 判断是否还有更多日志
    _cachedLogs = _hasMoreLogs ? currentLogs.sublist(0, _logLimit) : currentLogs; // 限制日志数量
    _lastLogUpdate = now; // 更新缓存时间
    return _cachedLogs!;
  }

  void _loadMoreLogs() { // 加载更多日志
    setState(() {
      _logLimit += 100; // 每次增加100条日志
      _cachedLogs = null; // 清除缓存以重新加载
      _updateLogs(); // 更新日志数据
    });
  }

  String formatDateTime(String dateTime) { // 格式化时间字符串并缓存
    return _dateTimeCache.putIfAbsent(dateTime, () {
      DateTime parsedTime = DateTime.parse(dateTime);
      return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} "
          "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
    });
  }

  @override
  Widget build(BuildContext context) { // 构建日志页面UI
    var screenWidth = MediaQuery.of(context).size.width;
    bool isTV = context.watch<ThemeProvider>().isTV; // 判断是否为TV模式
    bool isLogOn = context.watch<ThemeProvider>().isLogOn; // 获取日志开关状态
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // 设置TV模式背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下隐藏返回按钮
        title: Text(S.of(context).logtitle, style: _titleStyle), // 设置页面标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // 设置TV模式AppBar背景颜色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 传递焦点节点列表
          isHorizontalGroup: true, // 启用横向焦点分组
          initialIndex: 0, // 设置初始焦点索引
          isFrame: isTV ? true : false, // TV模式下启用框架模式
          frameType: isTV ? "child" : null, // TV模式下设置为子页面
          child: Align(
            alignment: Alignment.center, // 内容居中对齐
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity), // 限制容器最大宽度
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 设置内容内边距
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 子组件左对齐
                  children: [
                    Group(
                      groupIndex: 0, // 日志开关分组
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: FocusableItem(
                            focusNode: _focusNodes[0], // 为开关分配焦点
                            child: SwitchListTile(
                              title: Text(S.of(context).switchTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              subtitle: Text(S.of(context).logSubtitle, style: TextStyle(fontSize: 16)),
                              value: isLogOn, // 日志开关状态
                              onChanged: (value) {
                                LogUtil.safeExecute(() => context.read<ThemeProvider>().setLogOn(value), '设置日志开关状态时出错');
                              },
                              activeColor: Colors.white, // 开关开启时的滑块颜色
                              activeTrackColor: _focusNodes[0].hasFocus ? selectedColor : unselectedColor, // 开关轨道颜色
                              inactiveThumbColor: Colors.white, // 开关关闭时的滑块颜色
                              inactiveTrackColor: _focusNodes[0].hasFocus ? selectedColor : Colors.grey, // 开关关闭时的轨道颜色
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
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ...[
                                        {'level': 'all', 'label': S.of(context).filterAll, 'index': 1},
                                        {'level': 'v', 'label': S.of(context).filterVerbose, 'index': 2},
                                        {'level': 'e', 'label': S.of(context).filterError, 'index': 3},
                                        {'level': 'i', 'label': S.of(context).filterInfo, 'index': 4},
                                        {'level': 'd', 'label': S.of(context).filterDebug, 'index': 5},
                                      ].map((option) => _buildFilterButton(option['level']!, option['label']!, option['index']!)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Flexible(
                              child: _logs.isEmpty // 判断日志是否为空
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.info_outline, size: 50, color: Colors.grey),
                                          SizedBox(height: 10),
                                          Text(S.of(context).noLogs, style: TextStyle(fontSize: 18, color: Colors.grey)),
                                        ],
                                      ),
                                    )
                                  : Scrollbar(
                                      thumbVisibility: true, // 显示滚动条
                                      controller: _scrollController,
                                      child: SingleChildScrollView(
                                        controller: _scrollController,
                                        scrollDirection: Axis.vertical,
                                        child: Column(
                                          children: _logs.map((log) => Column( // 渲染每条日志
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(formatDateTime(log['time']!), style: _logTimeStyle),
                                                        if (!isTV)
                                                          IconButton(
                                                            icon: Icon(Icons.copy, color: Colors.grey),
                                                            onPressed: () { // 复制日志内容到剪贴板
                                                              String logContent = '${formatDateTime(log['time']!)}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}';
                                                              Clipboard.setData(ClipboardData(text: logContent));
                                                              CustomSnackBar.showSnackBar(context, S.of(context).logCopied, duration: Duration(seconds: 4));
                                                            },
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  SelectableText(LogUtil.parseLogMessage(log['message']!), style: _logMessageStyle),
                                                  SelectableText(log['fileInfo']!, style: _logMessageStyle.copyWith(color: Colors.grey)),
                                                  const Divider(),
                                                ],
                                              ))
                                              .toList(),
                                        ),
                                      ),
                                    ),
                            ),
                            Group(
                              groupIndex: 2, // 清空和加载更多按钮分组
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: FocusableItem(
                                    focusNode: _focusNodes[6], // 清空日志按钮焦点
                                    child: ElevatedButton(
                                      onPressed: () {
                                        LogUtil.safeExecute(() { // 清空日志并更新
                                          setState(() {
                                            if (_selectedLevel == 'all') {
                                              LogUtil.clearLogs();
                                              _cachedLogs = null;
                                            } else {
                                              LogUtil.clearLogs(level: _selectedLevel);
                                              _cachedLogs = null;
                                            }
                                            _updateLogs();
                                          });
                                          CustomSnackBar.showSnackBar(context, S.of(context).logCleared, duration: Duration(seconds: 4));
                                        }, '清空日志时出错');
                                      },
                                      child: Text(S.of(context).clearLogs, style: TextStyle(fontSize: 18, color: Colors.white), textAlign: TextAlign.center),
                                      style: ElevatedButton.styleFrom(
                                        shape: _buttonShape,
                                        backgroundColor: _focusNodes[6].hasFocus ? darkenColor(unselectedColor) : unselectedColor,
                                        side: BorderSide.none,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: FocusableItem(
                                    focusNode: _focusNodes[5], // 加载更多按钮焦点
                                    child: ElevatedButton(
                                      onPressed: _hasMoreLogs // 根据是否有更多日志启用按钮
                                          ? () {
                                              _loadMoreLogs();
                                              CustomSnackBar.showSnackBar(context, '已加载更多日志', duration: Duration(seconds: 2));
                                            }
                                          : null,
                                      child: Text('加载更多', style: TextStyle(fontSize: 18, color: Colors.white), textAlign: TextAlign.center),
                                      style: ElevatedButton.styleFrom(
                                        shape: _buttonShape,
                                        backgroundColor: _focusNodes[5].hasFocus ? darkenColor(unselectedColor) : unselectedColor,
                                        side: BorderSide.none,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
      ),
    );
  }

  Widget _buildFilterButton(String level, String label, int focusIndex) { // 构建日志过滤按钮
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).orientation == Orientation.landscape ? 5.0 : 2.0),
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex], // 为按钮分配焦点
        child: OutlinedButton(
          onPressed: () {
            setState(() { // 更新选中级别并刷新日志
              _selectedLevel = level;
              _logLimit = 100;
              _cachedLogs = null;
              _updateLogs();
            });
          },
          child: Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: (_selectedLevel == level) ? FontWeight.bold : FontWeight.normal),
            textAlign: TextAlign.center,
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
            shape: _buttonShape,
            backgroundColor: _focusNodes[focusIndex].hasFocus
                ? darkenColor(_selectedLevel == level ? selectedColor : unselectedColor)
                : (_selectedLevel == level ? selectedColor : unselectedColor),
            side: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
