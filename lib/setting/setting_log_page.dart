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
  final int focusedIndex; // 当前聚焦的索引
  final String selectedLevel; // 当前选中的日志级别

  SelectionState(this.focusedIndex, this.selectedLevel);
}

/// 日志查看页面，展示和管理应用日志
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState(); // 创建页面状态实例
}

class _SettinglogPageState extends State<SettinglogPage> {
  // 定义静态常量样式
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // 标题样式
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16); // 日志时间样式
  static const _logMessageStyle = TextStyle(fontSize: 14); // 日志消息样式

  static const int _logLimit = 88; // 限制显示的日志条数为88条
  final ScrollController _scrollController = ScrollController(); // 控制日志列表的滚动
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)); // 按钮统一圆角样式
  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景颜色
  late List<FocusNode> _focusNodes; // 修改为 late，非 final，因为需要动态更新
  late SelectionState _logState; // 新增状态管理，移除 _selectedLevel
  late Map<String, ButtonStyle> _buttonStyles; // 缓存按钮样式，提升性能
  late Map<int, Map<String, FocusNode>> _groupFocusCache; // 新增分组焦点缓存

  List<Map<String, String>>? _cachedLogs; // 缓存日志数据
  DateTime? _lastLogUpdate; // 上次日志更新时间
  String? _lastSelectedLevel; // 上次筛选的日志级别
  static const _logCacheTimeout = Duration(seconds: 1); // 日志缓存超时时间为1秒

  // 按钮基础样式
  static final _baseButtonStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    side: BorderSide.none,
  );

  // 生成焦点节点
  List<FocusNode> _generateFocusNodes(int count) {
    return List.generate(count, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 统一监听
      return node;
    });
  }

  // 动态生成分组焦点缓存
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache(bool isLogOn) {
    final cache = <int, Map<String, FocusNode>>{};
    cache[0] = {
      'firstFocusNode': _focusNodes[0], // 开关的焦点节点
      'lastFocusNode': _focusNodes[0],  // 开关只有一个节点
    };
    if (isLogOn) {
      cache[1] = {
        'firstFocusNode': _focusNodes[1], // 过滤按钮第一个节点
        'lastFocusNode': _focusNodes[5],  // 过滤按钮最后一个节点
      };
      cache[2] = {
        'firstFocusNode': _focusNodes[6], // 清空按钮的焦点节点
        'lastFocusNode': _focusNodes[6],  // 清空按钮只有一个节点
      };
    }
    return cache;
  }

  @override
  void initState() {
    super.initState();
    _logState = SelectionState(-1, 'all'); // 初始化状态，默认选中 'all'
    _initButtonStyles(); // 初始化按钮样式
    // 初始化焦点节点（根据初始日志开关状态）
    _focusNodes = _generateFocusNodes(context.read<ThemeProvider>().isLogOn ? 7 : 1);
    _groupFocusCache = _generateGroupFocusCache(context.read<ThemeProvider>().isLogOn);
    // 异步加载初始日志数据
    _loadLogsAsync();
  }

  // 统一处理焦点变化
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      _logState = SelectionState(focusedIndex, _logState.selectedLevel); // 更新焦点状态
      if (mounted) setState(() {}); // 直接更新状态
    } else {
      // 若未找到焦点，延迟检查
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          setState(() {
            _logState = SelectionState(newFocusedIndex, _logState.selectedLevel);
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SettinglogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 日志级别变化时异步更新缓存和界面
    if (_lastSelectedLevel != _logState.selectedLevel) {
      clearLogCache();
      _loadLogsAsync();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 释放滚动控制器
    for (var node in _focusNodes) {
      node.removeListener(_handleFocusChange); // 统一移除监听器
      node.dispose(); // 释放焦点节点
    }
    _cachedLogs = null; // 释放日志缓存，避免内存占用
    super.dispose();
  }

  // 初始化按钮样式，仅在必要时更新
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

  // 异步获取有限日志，预计算格式化时间并缓存
  Future<List<Map<String, String>>> _getLimitedLogsAsync() async {
    final now = Date

Time.now();
    if (_cachedLogs == null || _lastLogUpdate == null || _lastSelectedLevel != _logState.selectedLevel ||
        now.difference(_lastLogUpdate!) > _logCacheTimeout) {
      try {
        List<Map<String, String>> logs = _logState.selectedLevel == 'all'
            ? LogUtil.getLogs()
            : LogUtil.getLogsByLevel(_logState.selectedLevel); // 根据级别获取日志

        // 仅在数据变化时排序，避免重复计算
        logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!))); // 按时间降序排序
        _cachedLogs = (logs.length > _logLimit ? logs.sublist(0, _logLimit) : logs).map((log) => {
              'time': log['time']!,
              'message': log['message']!,
              'fileInfo': log['fileInfo']!,
              'formattedTime': formatDateTime(log['time']!), // 预计算并缓存格式化时间
            }).toList();
        _lastLogUpdate = now;
        _lastSelectedLevel = _logState.selectedLevel;
      } catch (e) {
        LogUtil.e('获取日志失败: $e'); // 记录错误日志
        _cachedLogs = []; // 返回空列表以避免崩溃
      }
    }
    return _cachedLogs!;
  }

  // 异步加载日志并更新 UI
  void _loadLogsAsync() {
    _getLimitedLogsAsync().then((logs) {
      if (mounted) {
        setState(() {}); // 仅在数据准备好后刷新 UI
      }
    });
  }

  // 将时间格式化为可读字符串
  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} ${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  // 清除日志缓存数据
  void clearLogCache() {
    _cachedLogs = null;
    _lastLogUpdate = null;
    _lastSelectedLevel = null;
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context); // 获取屏幕信息
    final themeProvider = context.watch<ThemeProvider>(); // 监听主题状态
    final bool isTV = themeProvider.isTV; // 是否为TV模式
    final bool isLogOn = themeProvider.isLogOn; // 日志开关状态
    final screenWidth = mediaQuery.size.width; // 屏幕宽度
    double maxContainerWidth = 580; // 最大容器宽度

    // 动态调整焦点节点和分组焦点缓存
    final int requiredNodes = isLogOn ? 7 : 1;
    if (_focusNodes.length != requiredNodes) {
      // 释放旧的焦点节点
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange);
        node.dispose();
      }
      // 生成新的焦点节点
      _focusNodes = _generateFocusNodes(requiredNodes);
      _groupFocusCache = _generateGroupFocusCache(isLogOn);
    }

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下设置背景色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式隐藏返回按钮
        title: Text(S.of(context).logtitle, style: _titleStyle), // 显示“日志”标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下设置AppBar颜色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 动态传递焦点节点
          groupFocusCache: _groupFocusCache, // 动态传递分组焦点缓存
          isHorizontalGroup: true, // 启用横向焦点分组
          initialIndex: 0, // 初始焦点索引为0
          isFrame: isTV ? true : false, // TV模式启用框架导航
          frameType: isTV ? "child" : null, // TV模式下标记为子页面
          child: Align(
            alignment: Alignment.center, // 内容居中对齐
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity), // 限制容器宽度
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
                            focusNode: _focusNodes[0], // 开关的焦点节点
                            child: SwitchListTile(
                              title: Text(S.of(context).switchTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), // “日志开关”标题
                              subtitle: Text(S.of(context).logSubtitle, style: TextStyle(fontSize: 16)), // 开关描述
                              value: isLogOn, // 当前日志开关状态
                              onChanged: (value) {
                                LogUtil.safeExecute(() {
                                  themeProvider.setLogOn(value); // 设置日志开关状态
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
                    if (isLogOn) // 日志开启时显示以下内容
                      Expanded(
                        child: Column(
                          children: [
                            Group(
                              groupIndex: 1, // 过滤按钮分组
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10), // 按钮与上方间距
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildFilterButton('all', S.of(context).filterAll, 1), // “全部”过滤按钮
                                      _buildFilterButton('v', S.of(context).filterVerbose, 2), // “详细”过滤按钮
                                      _buildFilterButton('e', S.of(context).filterError, 3), // “错误”过滤按钮
                                      _buildFilterButton('i', S.of(context).filterInfo, 4), // “信息”过滤按钮
                                      _buildFilterButton('d', S.of(context).filterDebug, 5), // “调试”过滤按钮
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Flexible(
                              child: Builder(
                                builder: (context) {
                                  // 使用 FutureBuilder 异步加载日志，提升页面响应性
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
                                                          Text(log['formattedTime']!, style: _logTimeStyle), // 显示日志时间
                                                          if (!isTV)
                                                            IconButton(
                                                              icon: Icon(Icons.copy, color: Colors.grey),
                                                              onPressed: () {
                                                                try {
                                                                  Clipboard.setData(ClipboardData(
                                                                      text: '${log['formattedTime']!}\n${LogUtil.parseLogMessage(log['message']!)}\n${log['fileInfo']!}')); // 复制日志内容
                                                                  CustomSnackBar.showSnackBar(context, S.of(context).logCopied, duration: Duration(seconds: 4)); // 提示复制成功
                                                                } catch (e) {
                                                                  LogUtil.e('复制日志到剪贴板失败: $e');
                                                                  CustomSnackBar.showSnackBar(context, '复制失败', duration: Duration(seconds: 4)); // 提示复制失败
                                                                }
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                      SelectableText(LogUtil.parseLogMessage(log['message']!), style: _logMessageStyle), // 显示日志消息
                                                      Text(log['fileInfo']!, style: TextStyle(fontSize: 12, color: Colors.grey)), // 显示文件信息
                                                      const Divider(), // 分隔线
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
                                    focusNode: _focusNodes[6], // 清空按钮的焦点节点
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (mounted) {
                                          setState(() {
                                            _logState.selectedLevel == 'all' ? LogUtil.clearLogs() : LogUtil.clearLogs(level: _logState.selectedLevel); // 清空日志
                                            clearLogCache();
                                          });
                                          CustomSnackBar.showSnackBar(context, S.of(context).logCleared, duration: Duration(seconds: 4)); // 提示清空成功
                                        }
                                      },
                                      child: Text(S.of(context).clearLogs, style: TextStyle(fontSize: 18, color: Colors.white), textAlign: TextAlign.center), // “清空日志”文本
                                      style: ElevatedButton.styleFrom(
                                        shape: _buttonShape,
                                        backgroundColor: _focusNodes[6].hasFocus ? darkenColor(unselectedColor) : unselectedColor, // 动态背景色
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

  // 构建日志过滤按钮，动态更新样式和焦点状态
  Widget _buildFilterButton(String level, String label, int focusIndex) {
    if (_logState.selectedLevel == level) {
      _buttonStyles[level] = _baseButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(selectedColor));
    } else {
      _buttonStyles[level] = _baseButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(unselectedColor));
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).orientation == Orientation.landscape ? 5.0 : 2.0), // 适配屏幕方向的间距
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex], // 绑定焦点节点
        child: OutlinedButton(
          onPressed: () {
            if (mounted) {
              setState(() {
                _logState = SelectionState(focusIndex, level); // 更新状态并同步焦点
                clearLogCache();
                _focusNodes[focusIndex].requestFocus(); // 确保焦点切换
              });
            }
          },
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: (_logState.selectedLevel == level) ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ), // 按钮文本
          style: _buttonStyles[level]!.copyWith(
            backgroundColor: MaterialStateProperty.resolveWith((states) {
              return _focusNodes[focusIndex].hasFocus
                  ? darkenColor(_logState.selectedLevel == level ? selectedColor : unselectedColor)
                  : (_logState.selectedLevel == level ? selectedColor : unselectedColor); // 动态调整背景色
            }),
          ),
        ),
      ),
    );
  }
}
