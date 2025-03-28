import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/channel_drawer_page.dart';

/// 将颜色变暗的函数，amount 默认值为 0.3
Color darkenColor(Color color, [double amount = 0.3]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

/// TV 键盘导航组件，支持焦点管理和按键处理
class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 子组件
  final List<FocusNode> focusNodes; // 焦点节点列表
  final Map<int, Map<String, FocusNode>>? groupFocusCache; // 分组焦点缓存，可选
  final Function(int index)? onSelect; // 焦点选中时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键触发时的回调
  final bool isFrame; // 是否为框架模式，控制焦点切换
  final String? frameType; // 框架类型（parent 或 child）
  final int? initialIndex; // 初始焦点索引，默认自动聚焦
  final bool isHorizontalGroup; // 是否按横向分组
  final bool isVerticalGroup; // 是否按竖向分组
  final Function(TvKeyNavigationState state)? onStateCreated; // 状态创建时的回调
  final String? cacheName; // 自定义缓存名称

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.groupFocusCache,
    this.onSelect,
    this.onKeyPressed,
    this.isFrame = false,
    this.frameType,
    this.initialIndex,
    this.isHorizontalGroup = false,
    this.isVerticalGroup = false,
    this.onStateCreated,
    this.cacheName,
  }) : super(key: key);

  @override
  TvKeyNavigationState createState() => TvKeyNavigationState();
}

/// TV 键盘导航的状态管理类
class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus; // 当前焦点节点
  Map<int, Map<String, FocusNode>> _groupFocusCache = {}; // 分组焦点缓存
  static Map<String, Map<int, Map<String, FocusNode>>> _namedCaches = {}; // 按名称存储的缓存
  bool _isFocusManagementActive = false; // 焦点管理是否激活
  int? _lastParentFocusIndex; // 父页面最后焦点索引
  DateTime? _lastKeyProcessedTime; // 上次按键处理时间
  static const Duration _throttleDuration = Duration(milliseconds: 200); // 按键节流间隔

  /// 判断是否为导航相关按键（方向键或选择键）
  bool _isNavigationKey(LogicalKeyboardKey key) {
    return _isDirectionKey(key) || _isSelectKey(key);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _isNavigationKey(event.logicalKey)) {
          final result = _handleKeyEvent(node, event);
          return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
        }
        return KeyEventResult.ignored; // 非导航按键透传
      },
      child: widget.child,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);
    _isFocusManagementActive = !widget.isFrame || widget.frameType == "parent"; // 初始化焦点管理状态
    if (_isFocusManagementActive) initializeFocusLogic(); // 激活时初始化焦点逻辑
    WidgetsBinding.instance.addObserver(this); // 注册生命周期观察者
  }

  /// 激活焦点管理，支持指定初始焦点
  void activateFocusManagement({int? initialIndexOverride}) {
    setState(() => _isFocusManagementActive = true);
    if (widget.cacheName != null) {
      String cacheName = 'groupCache-${widget.cacheName}';
      if (_namedCaches.containsKey(cacheName)) {
        _groupFocusCache = Map.from(_namedCaches[cacheName]!);
        LogUtil.i('使用 $cacheName 的缓存');
        _requestFocus(_lastParentFocusIndex ?? 0);
      } else {
        LogUtil.i('未找到 $cacheName 的缓存');
      }
    } else if (widget.frameType == "child") {
      initializeFocusLogic();
    }
    LogUtil.i('激活焦点管理');
  }

  /// 停用焦点管理，保存父页面焦点位置
  void deactivateFocusManagement() {
    setState(() {
      _isFocusManagementActive = false;
      if (widget.frameType == "parent" && _currentFocus != null) {
        _lastParentFocusIndex = widget.focusNodes.indexOf(_currentFocus!);
        LogUtil.i('保存父焦点位置: $_lastParentFocusIndex');
      }
    });
    LogUtil.i('停用焦点管理');
  }

  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }

  /// 释放资源，清理焦点和观察者
  void releaseResources({bool preserveFocus = false}) {
    try {
      if (!mounted) return;
      if (_currentFocus != null && _currentFocus!.canRequestFocus) {
        if (widget.frameType == "parent") _lastParentFocusIndex = widget.focusNodes.indexOf(_currentFocus!);
        if (!preserveFocus && _currentFocus!.hasFocus) {
          _currentFocus!.unfocus(); // 仅当 preserveFocus 为 false 时移除焦点
        }
        _currentFocus = null;
      }
      if (widget.frameType == "child" || !widget.isFrame) _groupFocusCache.clear();
      _isFocusManagementActive = !widget.isFrame;
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      _ensureCriticalResourceRelease();
    }
  }

  /// 确保关键资源释放
  void _ensureCriticalResourceRelease() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  /// 更新命名缓存，支持同步到分组缓存
  void updateNamedCache({required Map<int, Map<String, FocusNode>> cache, bool syncGroupFocusCache = true}) {
    if (widget.cacheName == null || cache.isEmpty) {
      LogUtil.i(widget.cacheName == null ? 'cacheName 未提供' : '缓存为空，跳过更新');
      return;
    }
    final cacheName = 'groupCache-${widget.cacheName}';
    _namedCaches[cacheName] = Map.from(cache);
    if (syncGroupFocusCache) _groupFocusCache = Map.from(cache);
    LogUtil.i('更新缓存 $cacheName: ${_namedCaches[cacheName]}');
  }

  /// 初始化焦点逻辑，支持指定初始焦点
  void initializeFocusLogic({int? initialIndexOverride}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (widget.focusNodes.isEmpty) {
          LogUtil.i('focusNodes 为空，无法初始化');
          return;
        }
        LogUtil.i('初始化焦点，节点数: ${widget.focusNodes.length}');
        // 在设置新焦点前移除旧焦点（如果有）
        if (_currentFocus != null && _currentFocus!.hasFocus) {
          LogUtil.i('移除旧焦点: ${widget.focusNodes.indexOf(_currentFocus!)}');
          _currentFocus!.unfocus();
          _currentFocus = null;
        }
        if (widget.groupFocusCache != null) {
          _groupFocusCache = Map.from(widget.groupFocusCache!);
          LogUtil.i('使用传入的 groupFocusCache');
          updateNamedCache(cache: _groupFocusCache);
        } else if (widget.cacheName == "ChannelDrawerPage") {
          ChannelDrawerPage.initializeData();
          ChannelDrawerPage.updateFocusLogic(true);
          LogUtil.i('处理 ChannelDrawerPage 初始化');
        } else {
          LogUtil.i('执行分组查找逻辑');
          _cacheGroupFocusNodes();
        }
        int initialIndex = initialIndexOverride ?? widget.initialIndex ?? 0;
        if (initialIndex < 0 || initialIndex >= widget.focusNodes.length) {
          LogUtil.i('初始索引无效 ($initialIndex)，回退到 0');
          initialIndex = 0; // 回退到 0
        }
        _requestFocusSafely(
          widget.focusNodes[initialIndex],
          initialIndex,
          _getGroupIndex(widget.focusNodes[initialIndex]),
        );
        LogUtil.i('焦点初始化到索引: $initialIndex');
      } catch (e) {
        LogUtil.i('焦点初始化失败: $e');
      }
    });
  }

  /// 处理错误并记录日志
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    LogUtil.i('$message: $error\n位置: $stackTrace');
  }

  static final Map<String, TvKeyNavigationState> _navigationCache = {}; // 导航状态缓存

  /// 查找子页面导航状态，使用缓存优化
  TvKeyNavigationState? _findChildNavigation() {
    if (_navigationCache.containsKey('child-${widget.cacheName}')) return _navigationCache['child-${widget.cacheName}'];
    TvKeyNavigationState? childNavigation;
    void visitChild(Element element) {
      if (element.widget is TvKeyNavigation && (element.widget as TvKeyNavigation).frameType == "child") {
        childNavigation = (element as StatefulElement).state as TvKeyNavigationState;
        _navigationCache['child-${widget.cacheName}'] = childNavigation!;
        LogUtil.i('找到子页面导航并缓存');
        return;
      }
      element.visitChildren(visitChild);
    }
    context.visitChildElements(visitChild);
    if (childNavigation == null) LogUtil.i('未找到子页面导航');
    return childNavigation;
  }

  /// 查找父页面导航状态，使用缓存优化
  TvKeyNavigationState? _findParentNavigation() {
    if (_navigationCache.containsKey('parent-${widget.cacheName}')) return _navigationCache['parent-${widget.cacheName}'];
    TvKeyNavigationState? parentNavigation;
    void findInContext(BuildContext context) {
      context.visitChildElements((element) {
        if (element.widget is TvKeyNavigation && (element.widget as TvKeyNavigation).frameType == "parent") {
          parentNavigation = (element as StatefulElement).state as TvKeyNavigationState;
          _navigationCache['parent-${widget.cacheName}'] = parentNavigation!;
          LogUtil.i('找到父页面导航并缓存');
          return;
        }
        findInContext(element);
      });
    }
    final rootElement = context.findRootAncestorStateOfType<NavigatorState>()?.context;
    if (rootElement != null) findInContext(rootElement);
    if (parentNavigation == null) LogUtil.i('未找到父页面导航');
    return parentNavigation;
  }

  /// 请求切换焦点到指定索引
  void _requestFocus(int index, {int? groupIndex}) {
    if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
      LogUtil.i('焦点列表为空或索引无效');
      return;
    }
    if (!widget.focusNodes.contains(widget.focusNodes[index])) {
      LogUtil.i('焦点节点已移除，切换到首个节点');
      index = 0;
    }
    groupIndex ??= _getGroupIndex(widget.focusNodes[index]);
    FocusNode focusNode = _adjustIndexInGroup(index, groupIndex);
    // 修改处：调用新的 _requestFocusSafely，替换原来的 _tryRequestFocus
    _requestFocusSafely(focusNode, index, groupIndex, skipIfHasFocus: true);
  }

  /// 调整索引到组内范围
  FocusNode _adjustIndexInGroup(int index, int groupIndex) {
    if (groupIndex == -1 || !_groupFocusCache.containsKey(groupIndex)) {
      FocusNode firstValidFocusNode = widget.focusNodes.firstWhere((node) => node.canRequestFocus, orElse: () => widget.focusNodes[0]);
      LogUtil.i('无效分组，调整到首个可用焦点');
      return firstValidFocusNode;
    }
    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
    int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode);
    int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode);
    if (index < firstFocusIndex) return lastFocusNode;
    if (index > lastFocusIndex) return firstFocusNode;
    return widget.focusNodes[index];
  }

  /// 新的合并方法：安全请求焦点
  void _requestFocusSafely(FocusNode focusNode, int index, int groupIndex, {bool skipIfHasFocus = false}) {
    if (!focusNode.canRequestFocus || focusNode.context == null) {
      LogUtil.i('焦点节点不可用，索引: $index');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.canRequestFocus && focusNode.context != null) {
          focusNode.requestFocus();
          _currentFocus = focusNode;
          LogUtil.i('延迟重试成功，焦点索引: $index, Group: $groupIndex');
        }
      });
      return;
    }
    if (!skipIfHasFocus || !focusNode.hasFocus) {
      focusNode.requestFocus();
      _currentFocus = focusNode;
    }
  }

  /// 缓存分组焦点信息
  void _cacheGroupFocusNodes() {
    if (widget.groupFocusCache != null) {
      LogUtil.i('已传入 groupFocusCache，跳过缓存');
      return;
    }
    _groupFocusCache.clear();
    final groups = _getAllGroups();
    LogUtil.i('找到分组数: ${groups.length}');
    if (groups.isEmpty || groups.length == 1) {
      _cacheDefaultGroup();
    } else {
      _cacheMultipleGroups(groups);
    }
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}';
    _namedCaches[cacheName] = Map.from(_groupFocusCache);
    LogUtil.i('保存缓存 $cacheName');
  }

  /// 缓存默认分组的焦点节点
  void _cacheDefaultGroup() {
    final firstFocusNode = _findFirstFocusableNode(widget.focusNodes);
    final lastFocusNode = _findLastFocusableNode(widget.focusNodes);
    _groupFocusCache[0] = {'firstFocusNode': firstFocusNode, 'lastFocusNode': lastFocusNode};
  }

  /// 缓存多分组的焦点节点
  void _cacheMultipleGroups(List<Group> groups) {
    for (var group in groups) {
      final groupWidgets = _getWidgetsInGroup(group);
      final groupFocusNodes = _getFocusNodesInGroup(groupWidgets);
      if (groupFocusNodes.isNotEmpty) {
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': groupFocusNodes.first,
          'lastFocusNode': groupFocusNodes.last,
        };
      } else {
        LogUtil.i('警告：分组 ${group.groupIndex} 无可聚焦节点');
      }
    }
  }

  /// 查找首个可聚焦节点
  FocusNode _findFirstFocusableNode(List<FocusNode> nodes) {
    return nodes.firstWhere((node) => node.canRequestFocus, orElse: () => FocusNode(debugLabel: '空焦点节点'));
  }

  /// 查找末尾可聚焦节点
  FocusNode _findLastFocusableNode(List<FocusNode> nodes) {
    return nodes.lastWhere((node) => node.canRequestFocus, orElse: () => FocusNode(debugLabel: '空焦点节点'));
  }

  /// 获取分组内的控件
  List<Widget> _getWidgetsInGroup(Group group) {
    return group.children ?? (group.child != null ? [group.child!] : []);
  }

  /// 获取分组内的焦点节点
  List<FocusNode> _getFocusNodesInGroup(List<Widget> widgets) {
    List<FocusNode> focusNodes = [];
    for (var widget in widgets) {
      if (widget is FocusableItem) {
        focusNodes.add(widget.focusNode);
      } else if (widget is SingleChildRenderObjectWidget && widget.child != null) {
        focusNodes.addAll(_getFocusNodesInGroup([widget.child!]));
      } else if (widget is MultiChildRenderObjectWidget) {
        focusNodes.addAll(_getFocusNodesInGroup(widget.children));
      }
    }
    return focusNodes.where((node) => node.canRequestFocus).toList();
  }

  /// 获取焦点所属分组索引
  int _getGroupIndex(FocusNode focusNode) {
    try {
      for (var entry in _groupFocusCache.entries) {
        FocusNode firstFocusNode = entry.value['firstFocusNode']!;
        FocusNode lastFocusNode = entry.value['lastFocusNode']!;
        int focusIndex = widget.focusNodes.indexOf(focusNode);
        if (focusIndex >= widget.focusNodes.indexOf(firstFocusNode) && focusIndex <= widget.focusNodes.indexOf(lastFocusNode)) {
          return entry.key;
        }
      }
      return -1;
    } catch (e, stackTrace) {
      _handleError('获取分组索引失败', e, stackTrace);
      return -1;
    }
  }

  /// 获取所有分组
  List<Group> _getAllGroups() {
    List<Group> groups = [];
    void searchGroups(Element element) {
      if (element.widget is Group) groups.add(element.widget as Group);
      element.visitChildren(searchGroups);
    }
    if (context != null) context.visitChildElements(searchGroups);
    return groups;
  }

  /// 处理导航逻辑，根据按键移动焦点
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final now = DateTime.now();
    if (_lastKeyProcessedTime != null && now.difference(_lastKeyProcessedTime!) < _throttleDuration) {
      return KeyEventResult.handled;
    }
    _lastKeyProcessedTime = now;
    if (_currentFocus == null) {
      LogUtil.i('无焦点，设置初始焦点');
      _requestFocus(0);
      return KeyEventResult.handled;
    }
    int currentIndex = widget.focusNodes.indexOf(_currentFocus!);
    if (currentIndex == -1) {
      LogUtil.i('找不到当前焦点索引');
      return KeyEventResult.ignored;
    }
    int groupIndex = _getGroupIndex(_currentFocus!);
    final navigationActions = {
      if (widget.isFrame && widget.frameType == "parent") ...{
        LogicalKeyboardKey.arrowRight: () => _switchToChild(),
        LogicalKeyboardKey.arrowLeft: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowUp: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowDown: () => _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex),
      } else if (widget.isFrame && widget.frameType == "child") ...{
        LogicalKeyboardKey.arrowLeft: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowRight: () => _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowUp: () => _jumpToOtherGroup(key, currentIndex, groupIndex),
        LogicalKeyboardKey.arrowDown: () => _jumpToOtherGroup(key, currentIndex, groupIndex),
      } else if (widget.isHorizontalGroup) ...{
        LogicalKeyboardKey.arrowLeft: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowRight: () => _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowUp: () => _jumpToOtherGroup(key, currentIndex, groupIndex),
        LogicalKeyboardKey.arrowDown: () => _jumpToOtherGroup(key, currentIndex, groupIndex),
      } else if (widget.isVerticalGroup) ...{
        LogicalKeyboardKey.arrowUp: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowDown: () => _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowLeft: () => _jumpToOtherGroup(key, currentIndex, groupIndex),
        LogicalKeyboardKey.arrowRight: () => _jumpToOtherGroup(key, currentIndex, groupIndex),
      } else ...{
        LogicalKeyboardKey.arrowUp: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowLeft: () => _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowDown: () => _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex),
        LogicalKeyboardKey.arrowRight: () => _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex),
      }
    };
    navigationActions[key]?.call();
    _triggerOnSelect(currentIndex);
    return KeyEventResult.handled;
  }

  /// 切换到子页面导航
  void _switchToChild() {
    final childNavigation = _findChildNavigation();
    if (childNavigation != null) {
      deactivateFocusManagement();
      childNavigation.activateFocusManagement();
      LogUtil.i('切换到子页面');
    }
  }

  /// 触发选择回调
  void _triggerOnSelect(int currentIndex) {
    if (_currentFocus != null && widget.onSelect != null) {
      int newIndex = widget.focusNodes.indexOf(_currentFocus!);
      if (newIndex != -1 && newIndex != currentIndex) widget.onSelect!(newIndex);
    }
  }

  /// 处理键盘事件
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyUpEvent) {
      LogicalKeyboardKey key = event.logicalKey;
      if (!_isFocusManagementActive) {
        LogUtil.i('焦点管理未激活，忽略按键');
        return KeyEventResult.ignored;
      }
      if (_isDirectionKey(key)) return _handleNavigation(key);
      if (_isSelectKey(key)) {
        try {
          _triggerButtonAction();
        } catch (e) {
          LogUtil.i('按钮操作失败: $e');
        }
        return KeyEventResult.handled;
      }
      widget.onKeyPressed?.call(key);
    }
    return KeyEventResult.ignored;
  }

  /// 判断是否为方向键
  bool _isDirectionKey(LogicalKeyboardKey key) {
    return {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight}.contains(key);
  }

  /// 判断是否为选择键
  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
  }

  /// 触发当前焦点控件的点击操作
  void _triggerButtonAction() {
    final focusNode = _currentFocus;
    if (focusNode != null && focusNode.context != null) {
      final context = focusNode.context!;
      final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();
      if (focusableItem != null) {
        _triggerActionsInFocusableItem(context);
      } else {
        LogUtil.i('未找到 FocusableItem');
      }
    }
  }

  /// 在 FocusableItem 中触发交互控件操作
  void _triggerActionsInFocusableItem(BuildContext context) {
    _visitAllElements(context, (element) => _triggerWidgetAction(element.widget));
  }

  /// 遍历元素并触发操作
  bool _visitAllElements(BuildContext context, bool Function(Element) visitor) {
    bool stop = false;
    context.visitChildElements((element) {
      if (stop) return;
      stop = visitor(element);
      if (!stop) stop = _visitAllElements(element, visitor);
    });
    return stop;
  }

  /// 触发控件操作
  bool _triggerWidgetAction(Widget widget) {
    final highPriorityWidgets = [ElevatedButton, TextButton, OutlinedButton, IconButton, FloatingActionButton, GestureDetector, ListTile];
    final lowPriorityWidgets = [Container, Padding, SizedBox, Align, Center];
    if (lowPriorityWidgets.contains(widget.runtimeType)) return false;
    if (highPriorityWidgets.contains(widget.runtimeType)) return _triggerSpecificWidgetAction(widget);
    return _triggerSpecificWidgetAction(widget);
  }

  /// 触发特定控件操作
  bool _triggerSpecificWidgetAction(Widget widget) {
    final actions = {
      SwitchListTile: (w) => (w as SwitchListTile).onChanged?.call(!w.value),
      ElevatedButton: (w) => (w as ElevatedButton).onPressed?.call(),
      TextButton: (w) => (w as TextButton).onPressed?.call(),
      OutlinedButton: (w) => (w as OutlinedButton).onPressed?.call(),
      IconButton: (w) => (w as IconButton).onPressed?.call(),
      FloatingActionButton: (w) => (w as FloatingActionButton).onPressed?.call(),
      ListTile: (w) => (w as ListTile).onTap?.call(),
      GestureDetector: (w) => (w as GestureDetector).onTap?.call(),
      PopupMenuButton: (w) => (w as PopupMenuButton).onSelected?.call(null),
      ChoiceChip: (w) => (w as ChoiceChip).onSelected?.call(true),
    };
    final action = actions[widget.runtimeType];
    if (action != null) {
      action(widget);
      return true;
    }
    LogUtil.i('找到控件但无法触发');
    return false;
  }

  /// 计算下一个焦点索引
  int _calculateNextIndex(int currentIndex, bool forward, int firstFocusIndex, int lastFocusIndex, {bool isChildFrame = false}) {
    int nextIndex;
    String action;
    if (forward) {
      nextIndex = currentIndex == lastFocusIndex ? firstFocusIndex : currentIndex + 1;
      action = currentIndex == lastFocusIndex ? '循环到首个焦点' : '切换到下一焦点';
    } else {
      if (currentIndex == firstFocusIndex) {
        if (isChildFrame) return -1;
        nextIndex = lastFocusIndex;
        action = '循环到末尾焦点';
      } else {
        nextIndex = currentIndex - 1;
        action = '切换到前一焦点';
      }
    }
    return nextIndex;
  }

  /// 导航焦点
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) async {
    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
    int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode);
    int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode);
    int nextIndex = _calculateNextIndex(currentIndex, forward, firstFocusIndex, lastFocusIndex, isChildFrame: widget.frameType == "child");
    if (nextIndex == -1) {
      final parentNavigation = _findParentNavigation();
      if (parentNavigation != null) {
        deactivateFocusManagement();
        parentNavigation.activateFocusManagement();
        LogUtil.i('返回父页面');
      }
      return;
    }
    if (widget.cacheName == "ChannelDrawerPage") {
      String targetList = groupIndex == 0 ? 'category' : groupIndex == 1 ? 'group' : 'channel';
      // 修改处：调用新的 _requestFocusSafely，替换原来的 _safeRequestFocus
      _requestFocusSafely(widget.focusNodes[nextIndex], nextIndex, groupIndex);
      await WidgetsBinding.instance.endOfFrame; 
      if (_currentFocus != widget.focusNodes[nextIndex]) {
        LogUtil.i('焦点切换失败，强制重试: $nextIndex');
        // 修改处：再次调用新的 _requestFocusSafely
        _requestFocusSafely(widget.focusNodes[nextIndex], nextIndex, groupIndex);
      }
    } else {
      // 修改处：调用新的 _requestFocusSafely，替换原来的 _safeRequestFocus
      _requestFocusSafely(widget.focusNodes[nextIndex], nextIndex, groupIndex);
    }
  }

  /// 处理组间跳转
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (_groupFocusCache.isEmpty) {
      LogUtil.i('无分组信息，无法跳转');
      return false;
    }
    try {
      List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
      int currentGroupIndex = groupIndex ?? groupIndices.first;
      if (!groupIndices.contains(currentGroupIndex)) {
        LogUtil.i('当前 Group $currentGroupIndex 未找到');
        return false;
      }
      int nextGroupIndex = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft
          ? groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + groupIndices.length) % groupIndices.length]
          : groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % groupIndices.length];
      final nextGroupFocus = _groupFocusCache[nextGroupIndex];
      if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) {
        FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode'];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nextFocusNode != null && nextFocusNode.canRequestFocus && nextFocusNode.context != null) {
            // 修改处：调用新的 _requestFocusSafely，替换原来的 _safeRequestFocus
            _requestFocusSafely(nextFocusNode, widget.focusNodes.indexOf(nextFocusNode), nextGroupIndex);
            LogUtil.i('跳转到 Group $nextGroupIndex');
          }
        });
        return true;
      }
    } catch (e, stackTrace) {
      LogUtil.i('组跳转错误: $e\n$stackTrace');
    }
    return false;
  }
}

/// 分组控件，支持单个或多个子节点
class Group extends StatelessWidget {
  final int groupIndex; // 分组索引
  final Widget? child; // 单个子节点
  final List<Widget>? children; // 多个子节点

  const Group({Key? key, required this.groupIndex, this.child, this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return child != null ? child! : (children != null ? Column(children: children!) : SizedBox.shrink());
  }
}

/// 可聚焦控件包装器
class FocusableItem extends StatefulWidget {
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子控件

  const FocusableItem({Key? key, required this.focusNode, required this.child}) : super(key: key);

  @override
  _FocusableItemState createState() => _FocusableItemState();
}

/// 可聚焦控件状态
class _FocusableItemState extends State<FocusableItem> {
  @override
  Widget build(BuildContext context) {
    return Focus(focusNode: widget.focusNode, child: widget.child);
  }
}
