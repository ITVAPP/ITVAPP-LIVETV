import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/widget/common_widgets.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 管理焦点与选中状态：跟踪按钮焦点和日志级别
class SelectionState {
  final int focusedIndex; // 当前聚焦按钮索引
  final String selectedLevel; // 当前选中日志级别

  SelectionState(this.focusedIndex, this.selectedLevel);

  // 比较状态：避免无效更新
  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is SelectionState &&
    runtimeType == other.runtimeType &&
    focusedIndex == other.focusedIndex &&
    selectedLevel == other.selectedLevel;

  @override
  int get hashCode => focusedIndex.hashCode ^ selectedLevel.hashCode;
}

// 日志查看页面：管理日志开关、筛选和清理
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState();
}

// 日志查看状态：处理焦点、日志加载和UI渲染
class _SettinglogPageState extends State<SettinglogPage> {
  // 标题文本样式：22号粗体
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  // 日志时间样式：16号粗体
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
  // 日志消息样式：14号字体
  static const _logMessageStyle = TextStyle(fontSize: 14);

  // 日志显示限制：最多88条
  static const int _logLimit = 88;
  // 滚动控制器：控制日志列表滚动
  final ScrollController _scrollController = ScrollController();
  // 按钮圆角样式：16像素圆角
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  // 选中背景色：红色
  final Color selectedColor = const Color(0xFFEB144C);
  // 未选中背景色：黄色
  final Color unselectedColor = const Color(0xFFDFA02A);
  // 焦点节点列表：管理按钮焦点
  late List<FocusNode> _focusNodes;
  // 当前焦点和选中状态：跟踪日志级别选择
  late SelectionState _logState;
  // 分组焦点缓存：优化TV导航
  late Map<int, Map<String, FocusNode>> _groupFocusCache;
  
  // 追踪日志开关状态：避免资源重建
  bool _lastLogOnState = false;

  // 缓存日志数据：存储已加载日志
  List<Map<String, String>>? _cachedLogs;
  // 上次日志更新时间：用于缓存有效性检查
  DateTime? _lastLogUpdate;
  // 上次筛选日志级别：记录当前筛选
  String? _lastSelectedLevel;
  // 日志缓存超时：1秒
  static const _logCacheTimeout = Duration(seconds: 1);

  // 按钮基础样式：统一圆角和边距
  static final _baseButtonStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    side: BorderSide.none,
  );

  // 生成焦点节点：为按钮分配焦点并绑定监听
  List<FocusNode> _generateFocusNodes(int count) {
    return List.generate(count, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange);
      return node;
    });
  }

  // 生成分组焦点缓存：为开关和筛选按钮配置焦点
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache(bool isLogOn) {
    final cache = <int, Map<String, FocusNode>>{};
    cache[0] = {
      'firstFocusNode': _focusNodes[0],
      'lastFocusNode': _focusNodes[0],
    };
    if (isLogOn) {
      cache[1] = {
        'firstFocusNode': _focusNodes[1],
        'lastFocusNode': _focusNodes[5],
      };
      cache[2] = {
        'firstFocusNode': _focusNodes[6],
        'lastFocusNode': _focusNodes[6],
      };
    }
    return cache;
  }

  @override
  void initState() {
    super.initState();
    // 初始化状态：默认选择全部日志
    _logState = SelectionState(-1, 'all');
    
    // 获取日志开关状态
    final themeProvider = context.read<ThemeProvider>();
    _lastLogOnState = themeProvider.isLogOn;
    
    // 初始化焦点节点：根据开关状态分配
    _focusNodes = _generateFocusNodes(_lastLogOnState ? 7 : 1);
    // 初始化焦点缓存：优化TV导航
    _groupFocusCache = _generateGroupFocusCache(_lastLogOnState);
    // 异步加载日志：初始化日志数据
    _loadLogsAsync();
  }

  // 处理焦点变化：异步更新状态并减少无效渲染
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      final newLogState = SelectionState(focusedIndex, _logState.selectedLevel);
      if (newLogState != _logState) {
        _logState = newLogState;
        if (mounted) setState(() {});
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          final newLogState = SelectionState(newFocusedIndex, _logState.selectedLevel);
          if (newLogState != _logState) {
            setState(() {
              _logState = newLogState;
            });
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SettinglogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final themeProvider = context.read<ThemeProvider>();
    final currentLogOnState = themeProvider.isLogOn;
    
    // 日志开关状态变化：重建焦点节点和缓存
    if (_lastLogOnState != currentLogOnState) {
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange);
        node.dispose();
      }
      
      final requiredNodes = currentLogOnState ? 7 : 1;
      _focusNodes = _generateFocusNodes(requiredNodes);
      _groupFocusCache = _generateGroupFocusCache(currentLogOnState);
      _lastLogOnState = currentLogOnState;
    }
    
    // 日志级别变化：清空缓存并重新加载
    if (_lastSelectedLevel != _logState.selectedLevel) {
      clearLogCache();
      _loadLogsAsync();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var node in _focusNodes) {
      node.removeListener(_handleFocusChange);
      node.dispose();
    }
    _cachedLogs = null;
    super.dispose();
  }

  // 获取日志：异步加载并限制数量
  Future<List<Map<String, String>>> _getLimitedLogsAsync() async {
    final now = DateTime.now();
    // 检查缓存有效性：避免重复加载
    if (_cachedLogs != null && 
        _lastLogUpdate != null && 
        _lastSelectedLevel == _logState.selectedLevel &&
        now.difference(_lastLogUpdate!) <= _logCacheTimeout) {
      return _cachedLogs!;
    }

    try {
      // 获取日志：按级别筛选
      List<Map<String, String>> logs = _logState.selectedLevel == 'all'
          ? LogUtil.getLogs()
          : LogUtil.getLogsByLevel(_logState.selectedLevel);

      // 排序并限制日志数量
      if (logs.isNotEmpty) {
        if (logs.length > _logLimit) {
          logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!)));
          logs = logs.sublist(0, _logLimit);
        } else {
          logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!)));
        }
        
        // 格式化日志时间
        _cachedLogs = logs.map((log) => {
          'time': log['time']!,
          'message': log['message']!,
          'fileInfo': log['fileInfo']!,
          'formattedTime': formatDateTime(log['time']!),
        }).toList();
      } else {
        _cachedLogs = [];
      }
      
      _lastLogUpdate = now;
      _lastSelectedLevel = _logState.selectedLevel;
    } catch (e) {
      LogUtil.e('获取日志失败: $e');
      _cachedLogs = [];
    }
    
    return _cachedLogs!;
  }

  // 异步加载日志：从缓存或LogUtil获取并更新UI
  void _loadLogsAsync() {
    _getLimitedLogsAsync().then((logs) {
      if (mounted) setState(() {});
    });
  }

  // 格式化时间字符串：转换为标准日期时间格式
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} ${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  // 清空日志缓存：重置缓存数据
  void clearLogCache() {
    _cachedLogs = null;
    _lastLogUpdate = null;
    _lastSelectedLevel = null;
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    double maxContainerWidth = 580;
    final themeProvider = context.watch<ThemeProvider>();
    final isLogOn = themeProvider.isLogOn;
    final isTV = context.read<ThemeProvider>().isTV;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: CommonSettingAppBar(
        title: S.of(context).logtitle,
        isTV: isTV,
        titleStyle: _titleStyle,
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes,
          groupFocusCache: _groupFocusCache,
          isHorizontalGroup: true,
          initialIndex: 0,
          isFrame: isTV, // 直接使用布尔值，不需要三元表达式
          frameType: isTV ? "child" : null,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Group(
                      groupIndex: 0,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: FocusableItem(
                            focusNode: _focusNodes[0],
                            child: SwitchListTile(
                              title: Text(S.of(context).switchTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              subtitle: Text(S.of(context).logSubtitle, style: TextStyle(fontSize: 16)),
                              value: isLogOn,
                              onChanged: (value) {
                                LogUtil.safeExecute(() {
                                  context.read<ThemeProvider>().setLogOn(value);
                                  if (!value) {
                                    LogUtil.clearLogs();
                                    clearLogCache();
                                    setState(() {});
                                  }
                                }, '设置日志开关状态时出错');
                              },
                              activeColor: Colors.white,
                              activeTrackColor: _focusNodes[0].hasFocus ? selectedColor : unselectedColor,
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: _focusNodes[0].hasFocus ? selectedColor : Colors.grey,
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
                              groupIndex: 1,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
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
                                  return FutureBuilder<List<Map<String, String>>>(
                                    future: _getLimitedLogsAsync(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return Center(child: CircularProgressIndicator());
                                      }
                                      if (snapshot.hasError) {
                                        return Center(child: Text('加载日志失败', style: TextStyle(color: Colors.red)));
                                      }
                                      List<Map<String, String>> logs = snapshot.data ?? [];
                                      return logs.isEmpty
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
                                              thumbVisibility: true,
                                              controller: _scrollController,
                                              child: SingleChildScrollView(
                                                controller: _scrollController,
                                                scrollDirection: Axis.vertical,
                                                child: Column(
                                                  children: logs.map((log) => Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text(log['formattedTime']!, style: _logTimeStyle),
                                                          if (!isTV)
                                                            IconButton(
                                                              icon: Icon(Icons.copy, color: Colors.grey),
                                                              onPressed: () {
                                                                try {
                                                                  Clipboard.setData(ClipboardData(
                                                                      text: '${log['formattedTime']!}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}'));
                                                                  CustomSnackBar.showSnackBar(context, S.of(context).logCopied, duration: Duration(seconds: 4));
                                                                } catch (e) {
                                                                  LogUtil.e('复制日志到剪贴板失败: $e');
                                                                  CustomSnackBar.showSnackBar(context, '复制失败', duration: Duration(seconds: 4));
                                                                }
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                      SelectableText(LogUtil.parseLogMessage(log['message']!), style: _logMessageStyle),
                                                      Text(log['fileInfo']!, style: TextStyle(fontSize: 12, color: Colors.grey)),
                                                      const Divider(),
                                                    ],
                                                  )).toList(),
                                                ),
                                              ),
                                            );
                                    },
                                  );
                                },
                              ),
                            ),
                            Group(
                              groupIndex: 2,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: FocusableItem(
                                    focusNode: _focusNodes[6],
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (mounted) {
                                          setState(() {
                                            _logState.selectedLevel == 'all' ? LogUtil.clearLogs() : LogUtil.clearLogs(level: _logState.selectedLevel);
                                            clearLogCache();
                                          });
                                          CustomSnackBar.showSnackBar(context, S.of(context).logCleared, duration: Duration(seconds: 4));
                                        }
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

  // 构建日志过滤按钮：动态设置样式和交互
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    final isSelected = _logState.selectedLevel == level;
    final isFocused = _focusNodes[focusIndex].hasFocus;
    
    // 计算背景色：根据焦点和选中状态调整
    final backgroundColor = isFocused
        ? darkenColor(isSelected ? selectedColor : unselectedColor)
        : (isSelected ? selectedColor : unselectedColor);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).orientation == Orientation.landscape ? 5.0 : 2.0),
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex],
        child: OutlinedButton(
          onPressed: () {
            if (mounted) {
              final newLogState = SelectionState(focusIndex, level);
              if (newLogState != _logState) {
                setState(() {
                  _logState = newLogState;
                  clearLogCache();
                });
              }
            }
          },
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
          style: _baseButtonStyle.copyWith(
            backgroundColor: MaterialStateProperty.all(backgroundColor),
          ),
        ),
      ),
    );
  }
}
