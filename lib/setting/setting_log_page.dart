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
  // 提取常用样式为静态常量，减少对象创建
  static const _titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static const _logTimeStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
  );

  static const _logMessageStyle = TextStyle(fontSize: 14);

  String _selectedLevel = 'all';
  static const int _logLimit = 88; // 固定最多显示88条日志
  final ScrollController _scrollController = ScrollController(); // 控制日志列表滚动

  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16), // 统一圆角样式
  );
  final Color selectedColor = const Color(0xFFEB144C); // 选中时背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时背景颜色

  // 将 _focusNodes 移至类变量初始化，避免重复创建，提升性能
  final List<FocusNode> _focusNodes = List.generate(7, (index) => FocusNode());
  // 将按钮样式缓存为类变量，使用 ButtonStyle 类型，避免类型未找到的问题
  late final Map<String, ButtonStyle> _buttonStyles;

  // 添加日志缓存相关变量
  List<Map<String, String>>? _cachedLogs;
  DateTime? _lastLogUpdate;
  String? _lastSelectedLevel; // 新增：记录上一次的筛选条件
  static const _logCacheTimeout = Duration(seconds: 1);

  // 提前缓存 ThemeProvider 和 MediaQuery 数据，避免重复调用
  late ThemeProvider _themeProvider;
  late MediaQueryData _mediaQuery;

  // 初始化按钮样式，减少运行时计算
  void _initButtonStyles() {
    _buttonStyles = {
      'all': OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
        shape: _buttonShape,
        backgroundColor: _selectedLevel == 'all' ? selectedColor : unselectedColor,
        side: BorderSide.none,
      ),
      'v': OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
        shape: _buttonShape,
        backgroundColor: _selectedLevel == 'v' ? selectedColor : unselectedColor,
        side: BorderSide.none,
      ),
      'e': OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
        shape: _buttonShape,
        backgroundColor: _selectedLevel == 'e' ? selectedColor : unselectedColor,
        side: BorderSide.none,
      ),
      'i': OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
        shape: _buttonShape,
        backgroundColor: _selectedLevel == 'i' ? selectedColor : unselectedColor,
        side: BorderSide.none,
      ),
      'd': OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
        shape: _buttonShape,
        backgroundColor: _selectedLevel == 'd' ? selectedColor : unselectedColor,
        side: BorderSide.none,
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    // 初始化缓存数据
    _themeProvider = context.read<ThemeProvider>();
    _mediaQuery = MediaQuery.of(context);
    _initButtonStyles(); // 初始化按钮样式
    // 优化 FocusNode 监听，仅在焦点变化影响 UI 时触发 setState
    for (var focusNode in _focusNodes) {
      focusNode.addListener(() {
        if (mounted && focusNode.hasFocus) { // 仅在焦点实际变化且影响 UI 时重绘
          setState(() {});
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SettinglogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检查 _selectedLevel 是否变化，仅在必要时更新缓存
    if (_lastSelectedLevel != _selectedLevel) {
      clearLogCache();
      getLimitedLogs(); // 提前更新缓存
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器
    _focusNodes.forEach((node) => node.dispose()); // 释放所有焦点节点
    super.dispose();
  }

  // 获取有限的日志并按日期排序（添加缓存机制）
  List<Map<String, String>> getLimitedLogs() {
    final now = DateTime.now();
    if (_cachedLogs == null ||
        _lastLogUpdate == null ||
        _lastSelectedLevel != _selectedLevel || // 检查筛选条件是否变化
        now.difference(_lastLogUpdate!) > _logCacheTimeout) {
      List<Map<String, String>> logs = _selectedLevel == 'all'
          ? LogUtil.getLogs()
          : LogUtil.getLogsByLevel(_selectedLevel);

      // 按时间降序排序
      logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!)));
      // 限制最多88条
      List<Map<String, String>> limitedLogs = logs.length > _logLimit ? logs.sublist(0, _logLimit) : logs;

      // 为每条日志添加格式化后的时间字段，避免重复计算
      _cachedLogs = limitedLogs.map((log) {
        return {
          'time': log['time']!,
          'message': log['message']!,
          'fileInfo': log['fileInfo']!,
          'formattedTime': formatDateTime(log['time']!), // 缓存格式化时间
        };
      }).toList();
      _lastLogUpdate = now;
      _lastSelectedLevel = _selectedLevel; // 更新上一次筛选条件
    }
    return _cachedLogs!;
  }

  // 格式化时间（提取为独立方法以便复用）
  String formatDateTime(String dateTime) {
    // 将时间格式化为 "年-月-日 时:分:秒" 的形式，便于阅读
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} "
        "${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  // 提取清除缓存的逻辑为独立方法，避免重复代码
  void clearLogCache() {
    _cachedLogs = null; // 清除日志缓存
    _lastLogUpdate = null; // 重置缓存时间
    _lastSelectedLevel = null; // 重置上一次筛选条件
  }

  @override
  Widget build(BuildContext context) {
    // 使用缓存的 ThemeProvider 和 MediaQuery 数据
    final bool isTV = _themeProvider.isTV;
    final bool isLogOn = _themeProvider.isLogOn;
    final screenWidth = _mediaQuery.size.width;

    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下不显示返回按钮
        title: Text(
          S.of(context).logtitle, // 页面标题
          style: _titleStyle,
        ),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下AppBar背景颜色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes,
          isHorizontalGroup: true, // 启用横向分组
          initialIndex: 0, // 设置初始焦点索引为 0
          isFrame: isTV ? true : false, // TV 模式下启用框架模式
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
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: FocusableItem(
                            focusNode: _focusNodes[0], // 为开关分配焦点节点
                            child: SwitchListTile(
                              title: Text(
                                S.of(context).switchTitle,
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
                                  ? selectedColor // 聚焦时颜色变暗
                                  : unselectedColor, // 启动时背景颜色
                              inactiveThumbColor: Colors.white, // 关闭时滑块的颜色
                              inactiveTrackColor: _focusNodes[0].hasFocus
                                  ? selectedColor // 聚焦时颜色变暗
                                  : Colors.grey, // 关闭时轨道的背景颜色
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
                                  padding: const EdgeInsets.only(top: 10), // 控制按钮与表格的间距
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
                            Flexible(
                              child: Builder(
                                builder: (context) {
                                  List<Map<String, String>> logs = getLimitedLogs();
                                  return logs.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.info_outline, size: 50, color: Colors.grey),
                                              SizedBox(height: 10),
                                              Text(S.of(context).noLogs,
                                                  style: TextStyle(fontSize: 18, color: Colors.grey)),
                                            ],
                                          ),
                                        )
                                      : Scrollbar(
                                          thumbVisibility: true,
                                          controller: _scrollController,
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            scrollDirection: Axis.vertical,
                                            child: Column(
                                              children: logs
                                                  .map((log) => Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment.spaceBetween,
                                                            children: [
                                                              Text(
                                                                log['formattedTime']!, // 使用缓存的格式化时间
                                                                style: _logTimeStyle, // 修正语法错误
                                                              ),
                                                              if (!isTV)
                                                                IconButton(
                                                                  icon: Icon(Icons.copy, color: Colors.grey),
                                                                  onPressed: () {
                                                                    String logContent =
                                                                        '${log['formattedTime']!}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}';
                                                                    Clipboard.setData(
                                                                        ClipboardData(text: logContent));
                                                                    CustomSnackBar.showSnackBar(
                                                                      context,
                                                                      S.of(context).logCopied,
                                                                      duration: Duration(seconds: 4),
                                                                    );
                                                                  },
                                                                ),
                                                            ],
                                                          ),
                                                          SelectableText(
                                                            LogUtil.parseLogMessage(log['message']!),
                                                            style: _logMessageStyle,
                                                          ),
                                                          Text(
                                                            log['fileInfo']!,
                                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                                          ),
                                                          const Divider(),
                                                        ],
                                                      ))
                                                  .toList(),
                                            ),
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
                                    focusNode: _focusNodes[6], // 为清空日志按钮添加焦点节点
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (mounted) { // 检查 mounted
                                          setState(() {
                                            if (_selectedLevel == 'all') {
                                              LogUtil.clearLogs();
                                              clearLogCache(); // 使用提取的方法清除缓存
                                            } else {
                                              LogUtil.clearLogs(level: _selectedLevel);
                                              clearLogCache(); // 使用提取的方法清除缓存
                                            }
                                          });
                                          CustomSnackBar.showSnackBar(
                                            context,
                                            S.of(context).logCleared,
                                            duration: Duration(seconds: 4),
                                          );
                                        }
                                      },
                                      child: Text(
                                        S.of(context).clearLogs,
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        shape: _buttonShape,
                                        backgroundColor: _focusNodes[6].hasFocus
                                            ? darkenColor(unselectedColor)
                                            : unselectedColor,
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

  // 构建过滤按钮，使用缓存的样式并简化参数
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _mediaQuery.orientation == Orientation.landscape ? 5.0 : 2.0,
      ),
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex],
        child: OutlinedButton(
          onPressed: () {
            if (mounted) {
              setState(() {
                _selectedLevel = level;
                clearLogCache(); // 清除缓存并触发更新
                _initButtonStyles(); // 更新按钮样式
              });
            }
          },
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: (_selectedLevel == level) ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
          style: _buttonStyles[level]!.copyWith(
            backgroundColor: MaterialStateProperty.resolveWith((states) {
              if (_focusNodes[focusIndex].hasFocus) {
                return darkenColor(_selectedLevel == level ? selectedColor : unselectedColor);
              }
              return _selectedLevel == level ? selectedColor : unselectedColor;
            }),
          ),
        ),
      ),
    );
  }
}

// 定义 darkenColor 函数
Color darkenColor(Color color, [double amount = 0.1]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}
