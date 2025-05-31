import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// SelectionState 类用于管理焦点和选中状态
class SelectionState {
  final int focusedIndex; // 当前聚焦的按钮索引
  final String selectedLevel; // 当前选中的日志级别

  SelectionState(this.focusedIndex, this.selectedLevel);

  // 优化：添加相等性比较，避免无效状态更新
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

/// 日志查看页面，用于展示和管理应用的日志数据
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState(); // 创建页面状态实例
}

class _SettinglogPageState extends State<SettinglogPage> {
  // 定义静态常量样式，提升复用性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // 标题文本样式
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16); // 日志时间样式
  static const _logMessageStyle = TextStyle(fontSize: 14); // 日志消息样式

  static const int _logLimit = 88; // 限制显示的日志条数为88
  final ScrollController _scrollController = ScrollController(); // 控制日志列表滚动
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)); // 按钮统一圆角样式
  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景色（红色）
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景色（黄色）
  late List<FocusNode> _focusNodes; // 焦点节点列表，动态初始化
  late SelectionState _logState; // 当前焦点和选中状态
  late Map<String, ButtonStyle> _buttonStyles; // 缓存按钮样式以优化性能
  late Map<int, Map<String, FocusNode>> _groupFocusCache; // 分组焦点缓存
  
  // 优化：添加状态追踪，避免不必要的资源重建
  bool _lastLogOnState = false; // 上次的日志开关状态

  List<Map<String, String>>? _cachedLogs; // 缓存的日志数据
  DateTime? _lastLogUpdate; // 上次日志更新时间
  String? _lastSelectedLevel; // 上次筛选的日志级别
  static const _logCacheTimeout = Duration(seconds: 1); // 日志缓存超时时间为1秒

  // 定义按钮基础样式，统一外观
  static final _baseButtonStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    side: BorderSide.none,
  );

  // 生成指定数量的焦点节点并绑定监听器
  List<FocusNode> _generateFocusNodes(int count) {
    return List.generate(count, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 添加焦点变化监听
      return node;
    });
  }

  // 生成分组焦点缓存，优化导航逻辑
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache(bool isLogOn) {
    final cache = <int, Map<String, FocusNode>>{};
    cache[0] = {
      'firstFocusNode': _focusNodes[0], // 日志开关焦点节点
      'lastFocusNode': _focusNodes[0],  // 开关单节点
    };
    if (isLogOn) {
      cache[1] = {
        'firstFocusNode': _focusNodes[1], // 过滤按钮组首个节点
        'lastFocusNode': _focusNodes[5],  // 过滤按钮组末尾节点
      };
      cache[2] = {
        'firstFocusNode': _focusNodes[6], // 清空按钮焦点节点
        'lastFocusNode': _focusNodes[6],  // 清空按钮单节点
      };
    }
    return cache;
  }

  @override
  void initState() {
    super.initState();
    _logState = SelectionState(-1, 'all'); // 初始化焦点和日志级别为"全部"
    _initButtonStyles(); // 初始化按钮样式
    
    // 优化：获取初始日志开关状态
    final themeProvider = context.read<ThemeProvider>();
    _lastLogOnState = themeProvider.isLogOn;
    
    _focusNodes = _generateFocusNodes(_lastLogOnState ? 7 : 1); // 根据日志开关状态初始化焦点节点
    _groupFocusCache = _generateGroupFocusCache(_lastLogOnState); // 初始化分组焦点缓存
    _loadLogsAsync(); // 异步加载初始日志
  }

  // 优化：处理焦点变化，添加状态比较减少无效更新
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      final newLogState = SelectionState(focusedIndex, _logState.selectedLevel);
      // 优化：只有状态实际发生变化时才执行setState
      if (newLogState != _logState) {
        _logState = newLogState; // 更新焦点状态
        if (mounted) setState(() {}); // 刷新UI
      }
    } else {
      // 未找到焦点时延迟检查，确保状态同步
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          final newLogState = SelectionState(newFocusedIndex, _logState.selectedLevel);
          // 优化：延迟回调中也添加状态比较
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
    
    // 优化：移动焦点节点管理到didUpdateWidget，避免在build中进行资源管理
    final themeProvider = context.read<ThemeProvider>();
    final currentLogOnState = themeProvider.isLogOn;
    
    // 只有当日志开关状态真正发生变化时才重建焦点节点
    if (_lastLogOnState != currentLogOnState) {
      // 清理旧的焦点节点
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange);
        node.dispose();
      }
      
      // 创建新的焦点节点
      final requiredNodes = currentLogOnState ? 7 : 1;
      _focusNodes = _generateFocusNodes(requiredNodes);
      _groupFocusCache = _generateGroupFocusCache(currentLogOnState);
      _lastLogOnState = currentLogOnState;
    }
    
    // 日志级别变化时刷新缓存和UI
    if (_lastSelectedLevel != _logState.selectedLevel) {
      clearLogCache();
      _loadLogsAsync();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器
    for (var node in _focusNodes) {
      node.removeListener(_handleFocusChange); // 移除焦点监听
      node.dispose(); // 释放焦点节点
    }
    _cachedLogs = null; // 清空日志缓存
    super.dispose();
  }

  // 初始化按钮样式，动态设置选中状态颜色
  void _initButtonStyles() {
    _buttonStyles = {
      'all': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_logState.selectedLevel == 'all' ? selectedColor : unselectedColor)),
      'v': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_logState.selectedLevel == 'v' ? selectedColor : unselectedColor)),
      'e': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_logState.selectedLevel == 'e' ? selectedColor : unselectedColor)),
      'i': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_logState.selectedLevel == 'i' ? selectedColor : unselectedColor)),
      'd': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_logState.selectedLevel == 'd' ? selectedColor : unselectedColor)),
    };
  }

  // 异步获取有限日志并缓存，优化性能
  Future<List<Map<String, String>>> _getLimitedLogsAsync() async {
    final now = DateTime.now();
    if (_cachedLogs == null || _lastLogUpdate == null || _lastSelectedLevel != _logState.selectedLevel ||
        now.difference(_lastLogUpdate!) > _logCacheTimeout) {
      try {
        List<Map<String, String>> logs = _logState.selectedLevel == 'all'
            ? LogUtil.getLogs()
            : LogUtil.getLogsByLevel(_logState.selectedLevel); // 根据级别筛选日志

        logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!))); // 按时间降序排序
        _cachedLogs = (logs.length > _logLimit ? logs.sublist(0, _logLimit) : logs).map((log) => {
              'time': log['time']!,
              'message': log['message']!,
              'fileInfo': log['fileInfo']!,
              'formattedTime': formatDateTime(log['time']!), // 预计算格式化时间
            }).toList();
        _lastLogUpdate = now;
        _lastSelectedLevel = _logState.selectedLevel;
      } catch (e) {
        LogUtil.e('获取日志失败: $e'); // 记录日志获取错误
        _cachedLogs = []; // 返回空列表避免崩溃
      }
    }
    return _cachedLogs!;
  }

  // 异步加载日志并更新界面
  void _loadLogsAsync() {
    _getLimitedLogsAsync().then((logs) {
      if (mounted) setState(() {}); // 数据准备好后刷新UI
    });
  }

  // 格式化时间为可读字符串
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} ${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  // 清空日志缓存数据
  void clearLogCache() {
    _cachedLogs = null;
    _lastLogUpdate = null;
    _lastSelectedLevel = null;
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context); // 获取屏幕信息
    final screenWidth = mediaQuery.size.width; // 屏幕宽度
    double maxContainerWidth = 580; // 最大容器宽度

    final themeProvider = context.watch<ThemeProvider>(); // 获取主题提供者
    final isTV = themeProvider.isTV; // 判断是否为TV模式
    final isLogOn = themeProvider.isLogOn; // 判断日志开关状态

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式设置背景色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式隐藏返回按钮
        title: Text(S.of(context).logtitle, style: _titleStyle), // 显示"日志"标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式设置标题栏颜色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 绑定焦点节点
          groupFocusCache: _groupFocusCache, // 绑定分组焦点缓存
          isHorizontalGroup: true, // 启用横向分组导航
          initialIndex: 0, // 初始焦点索引
          isFrame: isTV ? true : false, // TV模式启用框架导航
          frameType: isTV ? "child" : null, // TV模式标记为子页面
          child: Align(
            alignment: Alignment.center, // 内容居中
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity), // 限制最大宽度
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 设置内边距
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 子组件左对齐
                  children: [
                    Group(
                      groupIndex: 0, // 日志开关分组
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: FocusableItem(
                            focusNode: _focusNodes[0], // 日志开关焦点节点
                            child: SwitchListTile(
                              title: Text(S.of(context).switchTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), // "日志开关"标题
                              subtitle: Text(S.of(context).logSubtitle, style: TextStyle(fontSize: 16)), // 开关描述文本
                              value: isLogOn, // 当前开关状态
                              onChanged: (value) {
                                LogUtil.safeExecute(() {
                                  context.read<ThemeProvider>().setLogOn(value); // 更新日志开关状态
                                  if (!value) {
                                    LogUtil.clearLogs(); // 关闭时清空日志
                                    clearLogCache();
                                    setState(() {}); // 刷新界面
                                  }
                                }, '设置日志开关状态时出错');
                              },
                              activeColor: Colors.white, // 激活时滑块颜色
                              activeTrackColor: _focusNodes[0].hasFocus ? selectedColor : unselectedColor, // 激活时轨道颜色
                              inactiveThumbColor: Colors.white, // 未激活时滑块颜色
                              inactiveTrackColor: _focusNodes[0].hasFocus ? selectedColor : Colors.grey, // 未激活时轨道颜色
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isLogOn) // 日志开启时显示过滤和日志内容
                      Expanded(
                        child: Column(
                          children: [
                            Group(
                              groupIndex: 1, // 过滤按钮分组
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10), // 按钮上边距
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildFilterButton('all', S.of(context).filterAll, 1), // "全部"过滤按钮
                                      _buildFilterButton('v', S.of(context).filterVerbose, 2), // "详细"过滤按钮
                                      _buildFilterButton('e', S.of(context).filterError, 3), // "错误"过滤按钮
                                      _buildFilterButton('i', S.of(context).filterInfo, 4), // "信息"过滤按钮
                                      _buildFilterButton('d', S.of(context).filterDebug, 5), // "调试"过滤按钮
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Flexible(
                              child: Builder(
                                builder: (context) {
                                  // 使用FutureBuilder异步加载日志数据
                                  return FutureBuilder<List<Map<String, String>>>(
                                    future: _getLimitedLogsAsync(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return Center(child: CircularProgressIndicator()); // 显示加载指示器
                                      }
                                      if (snapshot.hasError) {
                                        return Center(child: Text('加载日志失败', style: TextStyle(color: Colors.red))); // 显示错误提示
                                      }
                                      List<Map<String, String>> logs = snapshot.data ?? [];
                                      return logs.isEmpty
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.info_outline, size: 50, color: Colors.grey),
                                                  SizedBox(height: 10),
                                                  Text(S.of(context).noLogs, style: TextStyle(fontSize: 18, color: Colors.grey)), // 无日志提示
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
                                                          Text(log['formattedTime']!, style: _logTimeStyle), // 显示格式化时间
                                                          if (!isTV)
                                                            IconButton(
                                                              icon: Icon(Icons.copy, color: Colors.grey),
                                                              onPressed: () {
                                                                try {
                                                                  Clipboard.setData(ClipboardData(
                                                                      text: '${log['formattedTime']!}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}')); // 复制日志到剪贴板
                                                                  CustomSnackBar.showSnackBar(context, S.of(context).logCopied, duration: Duration(seconds: 4)); // 提示复制成功
                                                                } catch (e) {
                                                                  LogUtil.e('复制日志到剪贴板失败: $e');
                                                                  CustomSnackBar.showSnackBar(context, '复制失败', duration: Duration(seconds: 4)); // 提示复制失败
                                                                }
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                      SelectableText(LogUtil.parseLogMessage(log['message']!), style: _logMessageStyle), // 显示日志内容
                                                      Text(log['fileInfo']!, style: TextStyle(fontSize: 12, color: Colors.grey)), // 显示文件信息
                                                      const Divider(), // 日志项分隔线
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
                              groupIndex: 2, // 清空日志按钮分组
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: FocusableItem(
                                    focusNode: _focusNodes[6], // 清空按钮焦点节点
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (mounted) {
                                          setState(() {
                                            _logState.selectedLevel == 'all' ? LogUtil.clearLogs() : LogUtil.clearLogs(level: _logState.selectedLevel); // 清空指定级别日志
                                            clearLogCache();
                                          });
                                          CustomSnackBar.showSnackBar(context, S.of(context).logCleared, duration: Duration(seconds: 4)); // 提示清空成功
                                        }
                                      },
                                      child: Text(S.of(context).clearLogs, style: TextStyle(fontSize: 18, color: Colors.white), textAlign: TextAlign.center), // "清空日志"按钮文本
                                      style: ElevatedButton.styleFrom(
                                        shape: _buttonShape,
                                        backgroundColor: _focusNodes[6].hasFocus ? darkenColor(unselectedColor) : unselectedColor, // 动态调整背景色
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

  // 优化：构建日志过滤按钮，减少重复样式计算
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    final isSelected = _logState.selectedLevel == level;
    final isFocused = _focusNodes[focusIndex].hasFocus;
    
    // 优化：预计算背景色，避免重复的MaterialStateProperty创建
    final backgroundColor = isFocused
        ? darkenColor(isSelected ? selectedColor : unselectedColor)
        : (isSelected ? selectedColor : unselectedColor);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).orientation == Orientation.landscape ? 5.0 : 2.0), // 根据屏幕方向调整间距
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex], // 绑定对应焦点节点
        child: OutlinedButton(
          onPressed: () {
            if (mounted) {
              final newLogState = SelectionState(focusIndex, level);
              // 优化：只有状态实际发生变化时才执行setState
              if (newLogState != _logState) {
                setState(() {
                  _logState = newLogState; // 更新焦点和选中级别
                  clearLogCache(); // 清空缓存以重新加载
                });
              }
            }
          },
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 选中时加粗
            ),
            textAlign: TextAlign.center,
          ), // 按钮显示文本
          style: _baseButtonStyle.copyWith(
            backgroundColor: MaterialStateProperty.all(backgroundColor),
          ),
        ),
      ),
    );
  }
}
