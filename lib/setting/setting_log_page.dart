import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 日志查看页面，展示和管理应用日志
class SettinglogPage extends StatefulWidget {
  @override
  _SettinglogPageState createState() => _SettinglogPageState();
}

class _SettinglogPageState extends State<SettinglogPage> {
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  static const _logTimeStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
  static const _logMessageStyle = TextStyle(fontSize: 14);

  String _selectedLevel = 'all';
  static const int _logLimit = 88;
  final ScrollController _scrollController = ScrollController();
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final Color selectedColor = const Color(0xFFEB144C);
  final Color unselectedColor = const Color(0xFFDFA02A);
  late List<FocusNode> _focusNodes; // 修改为 late，动态调整
  late Map<String, ButtonStyle> _buttonStyles;
  bool _isFocusUpdating = false;

  List<Map<String, String>>? _cachedLogs;
  DateTime? _lastLogUpdate;
  String? _lastSelectedLevel;
  static const _logCacheTimeout = Duration(seconds: 1);

  static final _baseButtonStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    side: BorderSide.none,
  );

  void _initButtonStyles() {
    _buttonStyles = {
      'all': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_selectedLevel == 'all' ? selectedColor : unselectedColor)),
      'v': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_selectedLevel == 'v' ? selectedColor : unselectedColor)),
      'e': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_selectedLevel == 'e' ? selectedColor : unselectedColor)),
      'i': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_selectedLevel == 'i' ? selectedColor : unselectedColor)),
      'd': _baseButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(_selectedLevel == 'd' ? selectedColor : unselectedColor)),
    };
  }

  // 初始化或更新焦点节点
  void _updateFocusNodes(bool isLogOn) {
    // 先清理旧的焦点节点
    if (_focusNodes != null) {
      _focusNodes.forEach((node) => node.dispose());
    }
    // 根据开关状态调整焦点节点数量
    _focusNodes = List.generate(isLogOn ? 7 : 1, (index) => FocusNode());
    for (var i = 0; i < _focusNodes.length; i++) {
      _focusNodes[i].addListener(() {
        if (mounted && _focusNodes[i].hasFocus && !_isFocusUpdating && (i == 0 || i == 6 || (i >= 1 && i <= 5))) {
          _isFocusUpdating = true;
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isFocusUpdating = false;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initButtonStyles();
    _updateFocusNodes(true); // 初始时假设日志开启
    _loadLogsAsync();
  }

  @override
  void didUpdateWidget(covariant SettinglogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastSelectedLevel != _selectedLevel) {
      clearLogCache();
      _loadLogsAsync();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNodes.forEach((node) => node.dispose());
    _cachedLogs = null;
    super.dispose();
  }

  Future<List<Map<String, String>>> _getLimitedLogsAsync() async {
    final now = DateTime.now();
    if (_cachedLogs == null || _lastLogUpdate == null || _lastSelectedLevel != _selectedLevel ||
        now.difference(_lastLogUpdate!) > _logCacheTimeout) {
      try {
        List<Map<String, String>> logs = _selectedLevel == 'all'
            ? LogUtil.getLogs()
            : LogUtil.getLogsByLevel(_selectedLevel);

        logs.sort((a, b) => DateTime.parse(b['time']!).compareTo(DateTime.parse(a['time']!)));
        _cachedLogs = (logs.length > _logLimit ? logs.sublist(0, _logLimit) : logs).map((log) => {
              'time': log['time']!,
              'message': log['message']!,
              'fileInfo': log['fileInfo']!,
              'formattedTime': formatDateTime(log['time']!),
            }).toList();
        _lastLogUpdate = now;
        _lastSelectedLevel = _selectedLevel;
      } catch (e) {
        LogUtil.e('获取日志失败: $e');
        _cachedLogs = [];
      }
    }
    return _cachedLogs!;
  }

  void _loadLogsAsync() {
    _getLimitedLogsAsync().then((logs) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String formatDateTime(String dateTime) {
    DateTime parsedTime = DateTime.parse(dateTime);
    return "${parsedTime.year}-${parsedTime.month.toString().padLeft(2, '0')}-${parsedTime.day.toString().padLeft(2, '0')} ${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}:${parsedTime.second.toString().padLeft(2, '0')}";
  }

  void clearLogCache() {
    _cachedLogs = null;
    _lastLogUpdate = null;
    _lastSelectedLevel = null;
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final bool isTV = themeProvider.isTV;
    final bool isLogOn = themeProvider.isLogOn;
    final screenWidth = mediaQuery.size.width;
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null,
        title: Text(S.of(context).logtitle, style: _titleStyle),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes,
          isHorizontalGroup: true,
          initialIndex: 0,
          isFrame: isTV ? true : false,
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
                                  themeProvider.setLogOn(value);
                                  if (!value) {
                                    LogUtil.clearLogs();
                                    clearLogCache();
                                    _updateFocusNodes(false); // 开关关闭时更新焦点节点
                                    setState(() {});
                                  } else {
                                    _updateFocusNodes(true); // 开关开启时恢复焦点节点
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
                                            _selectedLevel == 'all' ? LogUtil.clearLogs() : LogUtil.clearLogs(level: _selectedLevel);
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

  Widget _buildFilterButton(String level, String label, int focusIndex) {
    if (_selectedLevel == level) {
      _buttonStyles[level] = _baseButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(selectedColor));
    } else {
      _buttonStyles[level] = _baseButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(unselectedColor));
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).orientation == Orientation.landscape ? 5.0 : 2.0),
      child: FocusableItem(
        focusNode: _focusNodes[focusIndex],
        child: OutlinedButton(
          onPressed: () {
            if (mounted) {
              setState(() {
                _selectedLevel = level;
                clearLogCache();
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
              return _focusNodes[focusIndex].hasFocus
                  ? darkenColor(_selectedLevel == level ? selectedColor : unselectedColor)
                  : (_selectedLevel == level ? selectedColor : unselectedColor);
            }),
          ),
        ),
      ),
    );
  }
}
