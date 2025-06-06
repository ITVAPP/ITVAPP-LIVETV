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
  final ScrollController? scrollController; // 滚动控制器，用于自动滚动到焦点位置

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
    this.scrollController,
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
  
  // 性能优化：添加焦点节点索引映射，避免频繁的indexOf调用
  Map<FocusNode, int> _focusNodeIndexMap = {};
  // 性能优化：缓存分组索引映射
  Map<FocusNode, int> _focusNodeGroupMap = {};
  
  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        // 只有在有 scrollController 时才处理 KeyRepeatEvent
        if (event is KeyDownEvent && (_isDirectionKey(event.logicalKey) || _isSelectKey(event.logicalKey))) {
          final result = _handleKeyEvent(node, event);
          return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
        } else if (widget.scrollController != null && 
                   event is KeyRepeatEvent && 
                   (event.logicalKey == LogicalKeyboardKey.arrowUp || 
                    event.logicalKey == LogicalKeyboardKey.arrowDown)) {
          // 仅对滚动操作支持长按
          final result = _handleKeyEvent(node, event);
          return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }

  @override
  void initState() {
    super.initState();
    _buildFocusNodeIndexMap(); // 构建索引映射
    widget.onStateCreated?.call(this);
    _isFocusManagementActive = !widget.isFrame || widget.frameType == "parent"; // 初始化焦点管理状态
    if (_isFocusManagementActive) initializeFocusLogic(); // 激活时初始化焦点逻辑
    WidgetsBinding.instance.addObserver(this); // 注册生命周期观察者
  }
  
  /// 构建焦点节点索引映射，提升查找性能
  void _buildFocusNodeIndexMap() {
    _focusNodeIndexMap.clear();
    for (int i = 0; i < widget.focusNodes.length; i++) {
      _focusNodeIndexMap[widget.focusNodes[i]] = i;
    }
  }
  
  /// 获取焦点节点的索引，O(1)时间复杂度
  int _getFocusNodeIndex(FocusNode node) {
    return _focusNodeIndexMap[node] ?? -1;
  }

  /// 激活焦点管理，支持指定初始焦点
  void activateFocusManagement({int? initialIndexOverride}) {
    setState(() => _isFocusManagementActive = true);
    if (widget.cacheName != null) {
      String cacheName = 'groupCache-${widget.cacheName}';
      if (_namedCaches.containsKey(cacheName)) {
        _groupFocusCache = Map.from(_namedCaches[cacheName]!);
        LogUtil.i('使用 $cacheName 的缓存');
        _requestFocus(initialIndexOverride ?? _lastParentFocusIndex ?? 0);
      } else {
        LogUtil.i('未找到 $cacheName 的缓存');
      }
    } else if (widget.frameType == "child") {
      initializeFocusLogic(initialIndexOverride: initialIndexOverride);
    }
    LogUtil.i('激活焦点管理');
  }

  /// 停用焦点管理，保存父页面焦点位置
  void deactivateFocusManagement() {
    setState(() {
      _isFocusManagementActive = false;
      if (widget.frameType == "parent" && _currentFocus != null) {
        _lastParentFocusIndex = _getFocusNodeIndex(_currentFocus!);
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
        if (widget.frameType == "parent") _lastParentFocusIndex = _getFocusNodeIndex(_currentFocus!);
        if (!preserveFocus && _currentFocus!.hasFocus) {
          _currentFocus!.unfocus(); // 仅当 preserveFocus 为 false 时移除焦点
        }
        _currentFocus = null;
      }
      if (widget.frameType == "child" || !widget.isFrame) _groupFocusCache.clear();
      _isFocusManagementActive = !widget.isFrame;
      WidgetsBinding.instance.removeObserver(this);
      _focusNodeIndexMap.clear(); // 清理索引映射
      _focusNodeGroupMap.clear(); // 清理分组映射
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
    if (syncGroupFocusCache) {
      _groupFocusCache = Map.from(cache);
      _updateFocusNodeGroupMap(); // 更新分组映射
    }
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
          LogUtil.i('移除旧焦点: ${_getFocusNodeIndex(_currentFocus!)}');
          _currentFocus!.unfocus();
          _currentFocus = null;
        }
        if (widget.groupFocusCache != null) {
          _groupFocusCache = Map.from(widget.groupFocusCache!);
          _updateFocusNodeGroupMap(); // 更新分组映射
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
    int firstFocusIndex = _getFocusNodeIndex(firstFocusNode);
    int lastFocusIndex = _getFocusNodeIndex(lastFocusNode);
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
          _ensureFocusVisible(focusNode);
        }
      });
      return;
    }
    if (!skipIfHasFocus || !focusNode.hasFocus) {
      focusNode.requestFocus();
      _currentFocus = focusNode;
      // 焦点切换后确保可见
      _ensureFocusVisible(focusNode);
    }
  }

  /// 确保焦点元素在滚动视图中可见
  void _ensureFocusVisible(FocusNode focusNode) {
    if (widget.scrollController == null || focusNode.context == null) return;
    
    // 使用 addPostFrameCallback 确保布局完成后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || focusNode.context == null) return;
      
      try {
        // 使用 Scrollable.ensureVisible 自动滚动到焦点位置
        Scrollable.ensureVisible(
          focusNode.context!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5, // 尽量将焦点元素滚动到视图中央
        );
      } catch (e) {
        LogUtil.i('滚动到焦点失败: $e');
      }
    });
  }
  
  /// 更新焦点节点到分组的映射
  void _updateFocusNodeGroupMap() {
    _focusNodeGroupMap.clear();
    for (var entry in _groupFocusCache.entries) {
      final groupIndex = entry.key;
      final firstFocusNode = entry.value['firstFocusNode']!;
      final lastFocusNode = entry.value['lastFocusNode']!;
      final firstIndex = _getFocusNodeIndex(firstFocusNode);
      final lastIndex = _getFocusNodeIndex(lastFocusNode);
      
      if (firstIndex != -1 && lastIndex != -1) {
        for (int i = firstIndex; i <= lastIndex; i++) {
          _focusNodeGroupMap[widget.focusNodes[i]] = groupIndex;
        }
      }
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
    _updateFocusNodeGroupMap(); // 更新分组映射
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}';
    _namedCaches[cacheName] = Map.from(_groupFocusCache);
    LogUtil.i('保存缓存 $cacheName');
  }

  /// 缓存默认分组的焦点节点
  void _cacheDefaultGroup() {
    final firstFocusNode = widget.focusNodes.firstWhere(
      (node) => node.canRequestFocus, 
      orElse: () => FocusNode(debugLabel: '空焦点节点')
    );
    final lastFocusNode = widget.focusNodes.lastWhere(
      (node) => node.canRequestFocus, 
      orElse: () => FocusNode(debugLabel: '空焦点节点')
    );
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
      // 优先使用缓存的映射
      if (_focusNodeGroupMap.containsKey(focusNode)) {
        return _focusNodeGroupMap[focusNode]!;
      }
      
      // 降级到原始逻辑
      for (var entry in _groupFocusCache.entries) {
        FocusNode firstFocusNode = entry.value['firstFocusNode']!;
        FocusNode lastFocusNode = entry.value['lastFocusNode']!;
        int focusIndex = _getFocusNodeIndex(focusNode);
        if (focusIndex >= _getFocusNodeIndex(firstFocusNode) && focusIndex <= _getFocusNodeIndex(lastFocusNode)) {
          _focusNodeGroupMap[focusNode] = entry.key; // 缓存结果
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
    // 仅当有 scrollController 且是上下键时，不应用节流（支持长按）
    final isScrollAction = widget.scrollController != null && 
        (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown);
  
    if (!isScrollAction) {
      // 其他所有操作保持原有节流
      final now = DateTime.now();
      if (_lastKeyProcessedTime != null && now.difference(_lastKeyProcessedTime!) < _throttleDuration) {
        return KeyEventResult.handled;
      }
      _lastKeyProcessedTime = now;
    }
  
    // 优先处理滚动控制
    if (widget.scrollController != null && widget.scrollController!.hasClients &&
        (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      // 通过检查当前事件类型来判断是否是长按
      final currentEvent = HardwareKeyboard.instance.physicalKeysPressed;
      final isLongPress = currentEvent.isNotEmpty; // 这是一个简化判断
      
      // 计算滚动偏移量
      // 单击：100像素，200ms
      // 长按：250像素，100ms
      final scrollOffset = (key == LogicalKeyboardKey.arrowUp ? -1 : 1) * 
                          (isLongPress ? 250.0 : 100.0);
      final scrollDuration = isLongPress 
          ? const Duration(milliseconds: 100)
          : const Duration(milliseconds: 200);
    
      final currentOffset = widget.scrollController!.offset;
      final targetOffset = (currentOffset + scrollOffset).clamp(
        widget.scrollController!.position.minScrollExtent,
        widget.scrollController!.position.maxScrollExtent,
      );

      // 执行滚动动画
      widget.scrollController!.animateTo(
        targetOffset,
        duration: scrollDuration,
        curve: Curves.easeInOut,
      );
    
      LogUtil.i('键盘滚动: ${key == LogicalKeyboardKey.arrowUp ? "向上" : "向下"}, 偏移量: $scrollOffset');
      return KeyEventResult.handled;
    }
  
    if (_currentFocus == null) {
      LogUtil.i('无焦点，设置初始焦点');
      _requestFocus(0);
      return KeyEventResult.handled;
    }
    int currentIndex = _getFocusNodeIndex(_currentFocus!);
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
        int newIndex = _getFocusNodeIndex(focusNode);
        if (newIndex != -1) {
          _requestFocusSafely(focusNode, newIndex, _getGroupIndex(focusNode));
        }
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

  /// 触发特定控件操作 - 优化性能，使用switch-case替代Map
  bool _triggerSpecificWidgetAction(Widget widget) {
    switch (widget.runtimeType) {
      case SwitchListTile:
        (widget as SwitchListTile).onChanged?.call(!widget.value);
        return true;
      case ElevatedButton:
        (widget as ElevatedButton).onPressed?.call();
        return true;
      case TextButton:
        (widget as TextButton).onPressed?.call();
        return true;
      case OutlinedButton:
        (widget as OutlinedButton).onPressed?.call();
        return true;
      case IconButton:
        (widget as IconButton).onPressed?.call();
        return true;
      case FloatingActionButton:
        (widget as FloatingActionButton).onPressed?.call();
        return true;
      case ListTile:
        (widget as ListTile).onTap?.call();
        return true;
      case GestureDetector:
        (widget as GestureDetector).onTap?.call();
        return true;
      case PopupMenuButton:
        (widget as PopupMenuButton).onSelected?.call(null);
        return true;
      case ChoiceChip:
        (widget as ChoiceChip).onSelected?.call(true);
        return true;
      default:
        LogUtil.i('找到控件但无法触发');
        return false;
    }
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
    int firstFocusIndex = _getFocusNodeIndex(firstFocusNode);
    int lastFocusIndex = _getFocusNodeIndex(lastFocusNode);
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
      _requestFocusSafely(widget.focusNodes[nextIndex], nextIndex, groupIndex);
      await WidgetsBinding.instance.endOfFrame;
      if (_currentFocus != widget.focusNodes[nextIndex]) {
        LogUtil.i('焦点切换失败，强制重试: $nextIndex');
        _requestFocusSafely(widget.focusNodes[nextIndex], nextIndex, groupIndex);
      }
    } else {
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
        FocusNode nextFocusNode = nextGroupFocus['firstFocusNode']!;
        int nextIndex = _getFocusNodeIndex(nextFocusNode);
        if (nextIndex == -1) {
          LogUtil.i('焦点节点不在列表中，Group: $nextGroupIndex');
          return false;
        }
        // 确保焦点切换
        if (nextFocusNode.canRequestFocus && nextFocusNode.context != null) {
          nextFocusNode.requestFocus();
          _currentFocus = nextFocusNode;
          LogUtil.i('跳转到 Group $nextGroupIndex, 索引: $nextIndex');
          _ensureFocusVisible(nextFocusNode);
        } else {
          LogUtil.i('焦点节点不可用，尝试延迟切换，Group: $nextGroupIndex');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (nextFocusNode.canRequestFocus && nextFocusNode.context != null) {
              nextFocusNode.requestFocus();
              _currentFocus = nextFocusNode;
              LogUtil.i('延迟切换成功，Group: $nextGroupIndex, 索引: $nextIndex');
              _ensureFocusVisible(nextFocusNode);
            }
          });
        }
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
