import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 日志查看页面
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState(); // 创建页面状态
}

class _SettinglogPageState extends State<SettinglogPage> {
  // 提取常用样式为静态常量，减少对象创建
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // 标题样式
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16); // 日志时间样式
  static const _logMessageStyle = TextStyle(fontSize: 14); // 日志消息样式

  String _selectedLevel = 'all'; // 当前选中的日志级别，默认为全部
  static const int _logLimit = 88; // 限制显示最多88条日志
  final ScrollController _scrollController = ScrollController(); // 控制日志列表滚动
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)); // 按钮统一圆角样式
  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景颜色
  final List<FocusNode> _focusNodes = List.generate(7, (index) => FocusNode()); // 焦点节点列表，提升性能
  late final Map<String, ButtonStyle> _buttonStyles; // 缓存按钮样式，避免重复创建

  List<Map<String, String>>? _cachedLogs; // 日志缓存
  DateTime? _lastLogUpdate; // 上次日志更新时间
  String? _lastSelectedLevel; // 上次筛选的日志级别
  static const _logCacheTimeout = Duration(seconds: 1); // 日志缓存超时时间

  late MediaQueryData _mediaQuery; // 缓存媒体查询数据

  // 初始化按钮样式，仅执行一次
  _SettinglogPageState() {
    _buttonStyles = {
      'all': OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0), shape: _buttonShape, backgroundColor: _selectedLevel == 'all' ? selectedColor : unselectedColor, side: BorderSide.none), // 全部日志按钮样式
      'v': OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0), shape: _buttonShape, backgroundColor: _selectedLevel == 'v' ? selectedColor : unselectedColor, side: BorderSide.none), // 详细日志按钮样式
      'e': OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0), shape: _buttonShape, backgroundColor: _selectedLevel == 'e' ? selectedColor : unselectedColor, side: BorderSide.none), // 错误日志按钮样式
      'i': OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0), shape: _buttonShape, backgroundColor: _selectedLevel == 'i' ? selectedColor : unselectedColor, side: BorderSide.none), // 信息日志按钮样式
      'd': OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0), shape: _buttonShape, backgroundColor: _selectedLevel == 'd' ? selectedColor : unselectedColor, side: BorderSide.none), // 调试日志按钮样式
    };
  }

  @override
  void initState() {
    super.initState();
    _mediaQuery = MediaQuery.of(context); // 初始化媒体查询数据
    for (var i = 0; i < _focusNodes.length; i++) { // 为焦点节点添加监听
      _focusNodes[i].addListener(() {
        if (mounted && _focusNodes[i].hasFocus && (i == 0 || i == 6 || (i >= 1 && i <= 5))) { // 仅在焦点变化影响UI时重绘
          setState(() {});
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SettinglogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastSelectedLevel != _selectedLevel) { // 筛选条件变化时更新缓存
      clearLogCache();
      getLimitedLogs();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器
    _focusNodes.forEach((node) => node.dispose()); // 释放所有焦点节点
    super.dispose();
  }

  // 获取有限日志并按时间排序
  List<Map<String, String>> getLimitedLogs() {
    final now = DateTime.now();
    if (_cachedLogs == null || _lastLogUpdate == null || _lastSelectedLevel != _selectedLevel || now.difference(_lastLogUpdate!) > _logCacheTimeout) { // 检查是否需要更新缓存
      List<Map<String, String>> logs = _selectedLevel == 'all' ? LogUtil.getLogs() : LogUtil.getLogsByLevel(_selectedLevel); // 获取日志
      logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!))); // 按时间降序排序
      _cachedLogs = (logs.length > _logLimit ? logs.sublist(0, _logLimit) : logs).map((log) => { // 限制日志条数并格式化
        'time': log['time']!,
        'message': log['message']!,
        'fileInfo': log['fileInfo']!,
        'formattedTime': formatDateTime(log['time']!), // 缓存格式化时间
      }).toList();
      _lastLogUpdate = now;
      _lastSelectedLevel = _selectedLevel; // 更新筛选条件
    }
    return _cachedLogs!;
  }

  // 格式化时间为可读格式
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} ${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}"; // 返回格式化时间
  }

  // 清除日志缓存
  void clearLogCache() {
    _cachedLogs = null; // 清空日志缓存
    _lastLogUpdate = null; // 重置更新时间
    _lastSelectedLevel = null; // 重置筛选条件
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>(); // 使用 watch 监听变化
    final bool isTV = themeProvider.isTV; // 是否为TV模式
    final bool isLogOn = themeProvider.isLogOn; // 日志开关状态
    final screenWidth = _mediaQuery.size.width; // 屏幕宽度
    double maxContainerWidth = 580; // 最大容器宽度

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式背景色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式隐藏返回按钮
        title: Text(S.of(context).logtitle, style: _titleStyle), // 设置标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式AppBar背景色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 焦点节点列表
          isHorizontalGroup: true, // 启用横向分组
          initialIndex: 0, // 初始焦点索引
          isFrame: isTV ? true : false, // TV模式启用框架
          frameType: isTV ? "child" : null, // TV模式子页面类型
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
                              value: isLogOn, // 当前开关状态
                              onChanged: (value) {
                                LogUtil.safeExecute(() {
                                  themeProvider.setLogOn(value);
                                  if (!value) { // 关闭时清空日志
                                    LogUtil.clearLogs();
                                    clearLogCache();
                                    setState(() {}); // 强制刷新界面
                                  }
                                }, '设置日志开关状态时出错');
                              },
                              activeColor: Colors.white, // 滑块颜色
                              activeTrackColor: _focusNodes[0].hasFocus ? selectedColor.withOpacity(0.8) : unselectedColor, // 聚焦/启动时轨道颜色
                              inactiveThumbColor: Colors.white, // 关闭时滑块颜色
                              inactiveTrackColor: _focusNodes[0].hasFocus ? selectedColor.withOpacity(0.8) : Colors.grey[400], // 聚焦/关闭时轨道颜色
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isLogOn) // 日志开启时显示
                      Expanded(
                        child: Column(
                          children: [
                            Group(
                              groupIndex: 1, // 过滤按钮分组
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10), // 按钮与表格间距
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildFilterButton('all', S.of(context).filterAll, 1), // 全部过滤按钮
                                      _buildFilterButton('v', S.of(context).filterVerbose, 2), // 详细过滤按钮
                                      _buildFilterButton('e', S.of(context).filterError, 3), // 错误过滤按钮
                                      _buildFilterButton('i', S.of(context).filterInfo, 4), // 信息过滤按钮
                                      _buildFilterButton('d', S.of(context).filterDebug, 5), // 调试过滤按钮
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Flexible(
                              child: Builder(
                                builder: (context) {
                                  List<Map<String, String>> logs = getLimitedLogs(); // 获取日志列表
                                  return logs.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.info_outline, size: 50, color: Colors.grey), SizedBox(height: 10), Text(S.of(context).noLogs, style: TextStyle(fontSize: 18, color: Colors.grey))])) // 无日志时显示提示
                                      : Scrollbar(thumbVisibility: true, controller: _scrollController, child: SingleChildScrollView(controller: _scrollController, scrollDirection: Axis.vertical, child: Column(children: logs.map((log) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(log['formattedTime']!, style: _logTimeStyle), if (!isTV) IconButton(icon: Icon(Icons.copy, color: Colors.grey), onPressed: () { Clipboard.setData(ClipboardData(text: '${log['formattedTime']!}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}')); CustomSnackBar.showSnackBar(context, S.of(context).logCopied, duration: Duration(seconds: 4)); })]), SelectableText(LogUtil.parseLogMessage(log['message']!), style: _logMessageStyle), Text(log['fileInfo']!, style: TextStyle(fontSize: 12, color: Colors.grey)), const Divider()])).toList()))); // 显示日志列表
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
                                        if (mounted) { setState(() { _selectedLevel == 'all' ? LogUtil.clearLogs() : LogUtil.clearLogs(level: _selectedLevel); clearLogCache(); }); CustomSnackBar.showSnackBar(context, S.of(context).logCleared, duration: Duration(seconds: 4)); } // 清空日志并提示
                                      },
                                      child: Text(S.of(context).clearLogs, style: TextStyle(fontSize: 18, color: Colors.white), textAlign: TextAlign.center), // 按钮文本
                                      style: ElevatedButton.styleFrom(shape: _buttonShape, backgroundColor: _focusNodes[6].hasFocus ? darkenColor(unselectedColor) : unselectedColor, side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3)), // 按钮样式
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

  // 构建过滤按钮
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _mediaQuery.orientation == Orientation.landscape ? 5.0 : 2.0), // 根据屏幕方向调整间距
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex], // 按钮焦点节点
        child: OutlinedButton(
          onPressed: () { 
            if (mounted) { 
              setState(() { 
                _selectedLevel = level; 
                clearLogCache(); 
              }); 
            } 
          }, // 更新筛选级别并刷新
          child: Text(label, style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: (_selectedLevel == level) ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center), // 按钮文本
          style: _buttonStyles[level]!.copyWith(
            backgroundColor: MaterialStateProperty.resolveWith((states) {
              if (_focusNodes[focusIndex].hasFocus) {
                return darkenColor(_selectedLevel == level ? selectedColor : unselectedColor);
              }
              return _selectedLevel == level ? selectedColor : unselectedColor;
            }),
          ), // 动态背景色
        ),
      ),
    );
  }
}
