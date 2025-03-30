import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

/// 日志查看页面 - 显示和管理应用程序日志
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState(); // 创建状态对象
}

class _SettinglogPageState extends State<SettinglogPage> {
  // 定义静态常量样式 - 标题样式，字体大小22，加粗
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);

  // 定义静态常量样式 - 日志时间样式，字体大小16，加粗
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);

  // 定义静态常量样式 - 日志消息样式，字体大小14
  static const _logMessageStyle = TextStyle(fontSize: 14);

  String _selectedLevel = 'all'; // 当前选中的日志级别，默认显示全部
  static const int _logLimit = 88; // 限制日志显示数量为88条
  final ScrollController _scrollController = ScrollController(); // 日志列表滚动控制器

  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)); // 按钮统一圆角样式
  final Color selectedColor = const Color(0xFFEB144C); // 选中状态背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中状态背景颜色

  // 初始化焦点节点列表 - 为7个可聚焦元素分配焦点
  final List<FocusNode> _focusNodes = List.generate(7, (index) => FocusNode());

  List<Map<String, String>>? _cachedLogs; // 日志缓存，避免重复计算
  DateTime? _lastLogUpdate; // 上次日志更新时间，用于缓存管理
  static const _logCacheTimeout = Duration(seconds: 1); // 日志缓存超时时间，1秒

  @override
  void initState() {
    super.initState();
    // 初始化方法 - 为每个焦点节点添加监听，仅在焦点变化时重绘
    for (var focusNode in _focusNodes) {
      focusNode.addListener(() {
        if (mounted && focusNode.hasFocus != focusNode.oldFocus) {
          setState(() {}); // 焦点状态变化时触发重绘
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器资源
    _focusNodes.forEach((node) => node.dispose()); // 释放所有焦点节点资源
    super.dispose();
  }

  // 静态方法 - 对日志按时间降序排序并限制数量
  static List<Map<String, String>> _sortAndLimitLogs(List<Map<String, String>> logs, int limit) {
    logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!))); // 按时间降序排序
    return logs.length > limit ? logs.sublist(0, limit) : logs; // 限制日志数量
  }

  // 异步获取日志 - 使用缓存和异步线程优化性能
  Future<List<Map<String, String>>> getLimitedLogs() async {
    final now = DateTime.now();
    if (_cachedLogs == null || _lastLogUpdate == null || now.difference(_lastLogUpdate!) > _logCacheTimeout) {
      List<Map<String, String>> logs = _selectedLevel == 'all' ? LogUtil.getLogs() : LogUtil.getLogsByLevel(_selectedLevel); // 获取日志
      if (_cachedLogs == null || logs.length != _cachedLogs!.length || _cachedLogs!.isEmpty || _cachedLogs!.first['time'] != logs.first['time']) {
        List<Map<String, String>> limitedLogs = await compute(_sortAndLimitLogs, logs, _logLimit); // 异步排序和截取
        _cachedLogs = limitedLogs.map((log) => { // 缓存日志并添加格式化时间
          'time': log['time']!,
          'message': log['message']!,
          'fileInfo': log['fileInfo']!,
          'formattedTime': formatDateTime(log['time']!),
        }).toList();
      }
      _lastLogUpdate = now; // 更新缓存时间
    }
    return _cachedLogs!; // 返回缓存的日志
  }

  // 格式化时间 - 将时间字符串转换为"年-月-日 时:分:秒"格式
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} "
        "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  // 清除日志缓存 - 重置缓存数据和时间
  void clearLogCache() {
    _cachedLogs = null;
    _lastLogUpdate = null;
  }

  // 构建日志项 - 返回单个日志的可视化组件
  Widget _buildLogItem(Map<String, String> log, bool isTV) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSpacing: 4.0, // 控制子项之间的垂直间距为4dp
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(log['formattedTime']!, style: _logTimeStyle), // 显示格式化后的时间
            if (!isTV)
              IconButton(
                icon: Icon(Icons.copy, color: Colors.grey),
                onPressed: () {
                  String logContent = '${log['formattedTime']!}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}'; // 组合日志内容
                  Clipboard.setData(ClipboardData(text: logContent)); // 复制到剪贴板
                  CustomSnackBar.showSnackBar(context, S.of(context).logCopied, duration: Duration(seconds: 4)); // 显示复制成功提示
                },
              ),
          ],
        ),
        SelectableText(LogUtil.parseLogMessage(log['message']!), style: _logMessageStyle), // 显示可选择的日志消息
        Text(log['fileInfo']!, style: TextStyle(fontSize: 12, color: Colors.grey)), // 显示文件信息
        const Divider(height: 8.0, thickness: 1.0), // 分隔线高度为8dp，厚度为1dp
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>(); // 获取主题提供者
    final bool isTV = themeProvider.isTV; // 判断是否为TV模式
    final bool isLogOn = themeProvider.isLogOn; // 日志开关状态
    final mediaQuery = MediaQuery.of(context); // 获取屏幕信息
    final screenWidth = mediaQuery.size.width; // 屏幕宽度
    final orientation = mediaQuery.orientation; // 屏幕方向

    double maxContainerWidth = 580; // 内容最大宽度

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下设置背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式隐藏返回按钮
        title: Text(S.of(context).logtitle, style: _titleStyle), // 设置页面标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下设置AppBar背景颜色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes,
          isHorizontalGroup: true, // 启用横向焦点分组
          initialIndex: 0, // 初始焦点索引
          isFrame: isTV ? true : false, // TV模式启用框架
          frameType: isTV ? "child" : null, // TV模式设置为子页面
          child: Align(
            alignment: Alignment.center, // 内容居中
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity), // 限制最大宽度
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 设置内边距
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 内容左对齐
                  children: [
                    Group(
                      groupIndex: 0, // 日志开关分组
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: FocusableItem(
                            focusNode: _focusNodes[0], // 开关焦点节点
                            child: SwitchListTile(
                              title: Text(S.of(context).switchTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), // 开关标题
                              subtitle: Text(S.of(context).logSubtitle, style: TextStyle(fontSize: 16)), // 开关副标题
                              value: isLogOn,
                              onChanged: (value) {
                                LogUtil.safeExecute(() => context.read<ThemeProvider>().setLogOn(value), '设置日志开关状态时出错'); // 更新日志状态
                              },
                              activeColor: Colors.white, // 滑块激活颜色
                              activeTrackColor: _focusNodes[0].hasFocus ? selectedColor : unselectedColor, // 轨道激活颜色
                              inactiveThumbColor: Colors.white, // 滑块关闭颜色
                              inactiveTrackColor: _focusNodes[0].hasFocus ? selectedColor : Colors.grey, // 轨道关闭颜色
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
                                      _buildFilterButton('all', S.of(context).filterAll, 1, orientation), // 全部日志按钮
                                      _buildFilterButton('v', S.of(context).filterVerbose, 2, orientation), // 详细日志按钮
                                      _buildFilterButton('e', S.of(context).filterError, 3, orientation), // 错误日志按钮
                                      _buildFilterButton('i', S.of(context).filterInfo, 4, orientation), // 信息日志按钮
                                      _buildFilterButton('d', S.of(context).filterDebug, 5, orientation), // 调试日志按钮
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Flexible(
                              child: FutureBuilder<List<Map<String, String>>>(
                                future: getLimitedLogs(), // 异步获取日志数据
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return Center(child: CircularProgressIndicator()); // 显示加载指示器
                                  }
                                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Icon(Icons.info_outline, size: 50, color: Colors.grey),
                                      SizedBox(height: 10),
                                      Text(S.of(context).noLogs, style: TextStyle(fontSize: 18, color: Colors.grey)),
                                    ])); // 显示无日志提示
                                  }
                                  final logs = snapshot.data!;
                                  return Scrollbar(
                                    thumbVisibility: true,
                                    controller: _scrollController,
                                    child: lectureSingleChildScrollView(
                                      controller: _scrollController,
                                      scrollDirection: Axis.vertical,
                                      child: Column(children: logs.map((log) => _buildLogItem(log, isTV)).toList()), // 显示日志列表
                                    ),
                                  );
                                },
                              ),
                            ),
                            Group(
                              groupIndex: 2, // 清空日志按钮分组
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: FocusableItem(
                                    focusNode: _focusNodes[6], // 清空按钮焦点节点
                                    child: ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          if (_selectedLevel == 'all') {
                                            LogUtil.clearLogs(); // 清空所有日志
                                            clearLogCache();
                                          } else {
                                            LogUtil.clearLogs(level: _selectedLevel); // 清空指定级别日志
                                            clearLogCache();
                                          }
                                        });
                                        CustomSnackBar.showSnackBar(context, S.of(context).logCleared, duration: Duration(seconds: 4)); // 显示清空提示
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

  // 构建过滤按钮 - 返回带焦点管理的日志级别筛选按钮
  Widget _buildFilterButton(String level, String label, int focusIndex, Orientation orientation) {
    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
      shape: _buttonShape,
      backgroundColor: _focusNodes[focusIndex].hasFocus
          ? darkenColor(_selectedLevel == level ? selectedColor : unselectedColor)
          : (_selectedLevel == level ? selectedColor : unselectedColor),
      side: BorderSide.none,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: orientation == Orientation.landscape ? 5.0 : 2.0),
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex],
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _selectedLevel = level; // 更新选中级别
              clearLogCache(); // 清除缓存以刷新数据
            });
          },
          child: Text(label, style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: (_selectedLevel == level) ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
          style: buttonStyle,
        ),
      ),
    );
  }
}
