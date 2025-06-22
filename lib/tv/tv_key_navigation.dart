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
  // 优化：使用LRU缓存替代无限增长的Map，最多保存20个缓存项
  static final Map<String, Map<int, Map<String, FocusNode>>> _namedCaches = {};
  static final List<String> _cacheKeys = []; // 用于LRU
  static const int _maxCacheSize = 20;
  
  bool _isFocusManagementActive = false; // 焦点管理是否激活
  int? _lastParentFocusIndex; // 父页面最后焦点索引
  DateTime? _lastKeyProcessedTime; // 上次按键处理时间
  static const Duration _throttleDuration = Duration(milliseconds: 200); // 按键节流间隔
  
  // 性能优化：焦点索引缓存
  Map<FocusNode, int>? _focusNodeIndexCache;
  Map<int, List<int>>? _groupIndexRanges;
  List<int>? _sortedGroupIndices;
  
  // 优化：预先创建的方向键操作映射，避免每次创建
  late final Map<LogicalKeyboardKey, VoidCallback> _parentFrameActions;
  late final Map<LogicalKeyboardKey, VoidCallback> _childFrameActions;
  late final Map<LogicalKeyboardKey, VoidCallback> _horizontalGroupActions;
  late final Map<LogicalKeyboardKey, VoidCallback> _verticalGroupActions;
  late final Map<LogicalKeyboardKey, VoidCallback> _defaultActions;
  
  // 新增：焦点动作缓存，使用弱引用避免内存泄漏
  final Map<FocusNode, _CachedAction> _focusActionCache = {};
  
  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        // 修复：对所有按键事件进行处理，包括 KeyDownEvent 和 KeyRepeatEvent
        if ((event is KeyDownEvent || event is KeyRepeatEvent) && 
            (_isDirectionKey(event.logicalKey) || _isSelectKey(event.logicalKey))) {
          
          // 特殊处理：有 scrollController 且是上下键的 KeyRepeatEvent
          if (widget.scrollController != null && 
              event is KeyRepeatEvent && 
              (event.logicalKey == LogicalKeyboardKey.arrowUp || 
               event.logicalKey == LogicalKeyboardKey.arrowDown)) {
            // 滚动操作支持长按，不需要防抖
            final result = _handleKeyEvent(node, event);
            return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
          }
          
          // 其他情况都需要防抖
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
    LogUtil.i('initState - '
        'frameType: ${widget.frameType}, '
        'cacheName: ${widget.cacheName}, '
        'isFrame: ${widget.isFrame}');
    
    // 优化：初始化操作映射
    _initializeActionMaps();
    
    widget.onStateCreated?.call(this);
    _isFocusManagementActive = !widget.isFrame || widget.frameType == "parent"; // 初始化焦点管理状态
    if (_isFocusManagementActive) initializeFocusLogic(); // 激活时初始化焦点逻辑
    WidgetsBinding.instance.addObserver(this); // 注册生命周期观察者
  }
  
  // 优化：预先初始化操作映射
  void _initializeActionMaps() {
    _parentFrameActions = {
      LogicalKeyboardKey.arrowRight: () => _switchToChild(),
      LogicalKeyboardKey.arrowLeft: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowLeft, forward: false),
      LogicalKeyboardKey.arrowUp: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowUp, forward: false),
      LogicalKeyboardKey.arrowDown: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowDown, forward: true),
    };
    
    _childFrameActions = {
      LogicalKeyboardKey.arrowLeft: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowLeft, forward: false),
      LogicalKeyboardKey.arrowRight: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowRight, forward: true),
      LogicalKeyboardKey.arrowUp: () => _jumpToOtherGroupWrapper(LogicalKeyboardKey.arrowUp),
      LogicalKeyboardKey.arrowDown: () => _jumpToOtherGroupWrapper(LogicalKeyboardKey.arrowDown),
    };
    
    _horizontalGroupActions = {
      LogicalKeyboardKey.arrowLeft: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowLeft, forward: false),
      LogicalKeyboardKey.arrowRight: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowRight, forward: true),
      LogicalKeyboardKey.arrowUp: () => _jumpToOtherGroupWrapper(LogicalKeyboardKey.arrowUp),
      LogicalKeyboardKey.arrowDown: () => _jumpToOtherGroupWrapper(LogicalKeyboardKey.arrowDown),
    };
    
    _verticalGroupActions = {
      LogicalKeyboardKey.arrowUp: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowUp, forward: false),
      LogicalKeyboardKey.arrowDown: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowDown, forward: true),
      LogicalKeyboardKey.arrowLeft: () => _jumpToOtherGroupWrapper(LogicalKeyboardKey.arrowLeft),
      LogicalKeyboardKey.arrowRight: () => _jumpToOtherGroupWrapper(LogicalKeyboardKey.arrowRight),
    };
    
    _defaultActions = {
      LogicalKeyboardKey.arrowUp: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowUp, forward: false),
      LogicalKeyboardKey.arrowLeft: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowLeft, forward: false),
      LogicalKeyboardKey.arrowDown: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowDown, forward: true),
      LogicalKeyboardKey.arrowRight: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowRight, forward: true),
    };
  }
  
  // 优化：包装方法，避免在_handleNavigation中重复获取当前状态
  void _navigateFocusWrapper(LogicalKeyboardKey key, {required bool forward}) {
    if (_currentFocus == null) return;
    int currentIndex = _getFocusNodeIndex(_currentFocus!);
    int groupIndex = _getGroupIndex(_currentFocus!);
    _navigateFocus(key, currentIndex, forward: forward, groupIndex: groupIndex);
  }
  
  void _jumpToOtherGroupWrapper(LogicalKeyboardKey key) {
    if (_currentFocus == null) return;
    int currentIndex = _getFocusNodeIndex(_currentFocus!);
    int groupIndex = _getGroupIndex(_currentFocus!);
    _jumpToOtherGroup(key, currentIndex, groupIndex);
  }

  /// 激活焦点管理，支持指定初始焦点
  void activateFocusManagement({int? initialIndexOverride}) {
    setState(() => _isFocusManagementActive = true);
    if (widget.cacheName != null) {
      String cacheName = 'groupCache-${widget.cacheName}';
      if (_namedCaches.containsKey(cacheName)) {
        _groupFocusCache = Map.from(_namedCaches[cacheName]!);
        _updateCaches(); // 更新所有缓存
        LogUtil.i('使用 $cacheName 的缓存');
        _requestFocus(initialIndexOverride ?? _lastParentFocusIndex ?? 0);
      } else {
        LogUtil.i('未找到 $cacheName 的缓存');
      }
    } else if (widget.frameType == "child") {
      initializeFocusLogic(initialIndexOverride: initialIndexOverride);
    }
  }

  /// 停用焦点管理，保存父页面焦点位置
  void deactivateFocusManagement() {
    setState(() {
      _isFocusManagementActive = false;
      if (widget.frameType == "parent" && _currentFocus != null) {
        _lastParentFocusIndex = _getFocusNodeIndex(_currentFocus!);
      }
    });
  }

  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }

  /// 释放资源，清理焦点和观察者
  void releaseResources({bool preserveFocus = false}) {
    if (!mounted) return;
    
    // 1. 先停止焦点管理
    _isFocusManagementActive = false;
    
    // 2. 保存必要的状态
    if (_currentFocus != null && widget.frameType == "parent") {
      _lastParentFocusIndex = _getFocusNodeIndex(_currentFocus!);
    }
    
    // 3. 清理焦点（按依赖顺序）
    if (_currentFocus != null && !preserveFocus) {
      // 简化：移除try-catch，直接处理
      if (_currentFocus!.hasFocus && _currentFocus!.canRequestFocus) {
        _currentFocus!.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      }
      _currentFocus = null;
    }
    
    // 4. 清理缓存
    _clearAllCaches();
    
    // 5. 清理分组缓存
    if (widget.frameType == "child" || !widget.isFrame) {
      _groupFocusCache.clear();
    }
    
    // 6. 移除观察者
    WidgetsBinding.instance.removeObserver(this);
  }

  /// 清理所有缓存
  void _clearAllCaches() {
    _focusNodeIndexCache?.clear();
    _focusNodeIndexCache = null;
    _groupIndexRanges?.clear();
    _groupIndexRanges = null;
    _sortedGroupIndices?.clear();
    _sortedGroupIndices = null;
    _focusActionCache.clear(); // 清理动作缓存
  }

  /// 更新所有缓存
  void _updateCaches() {
    _updateFocusNodeIndexCache();
    _updateGroupIndexRanges();
  }

  /// 更新命名缓存，支持同步到分组缓存（优化：LRU缓存）
  void updateNamedCache({required Map<int, Map<String, FocusNode>> cache, bool syncGroupFocusCache = true}) {
    if (widget.cacheName == null || cache.isEmpty) {
      return;
    }
    final cacheName = 'groupCache-${widget.cacheName}';
    
    // LRU缓存管理
    if (_namedCaches.containsKey(cacheName)) {
      _cacheKeys.remove(cacheName);
    }
    _cacheKeys.add(cacheName);
    
    // 如果超过最大缓存数，移除最旧的
    if (_cacheKeys.length > _maxCacheSize) {
      final oldestKey = _cacheKeys.removeAt(0);
      _namedCaches.remove(oldestKey);
    }
    
    _namedCaches[cacheName] = Map.from(cache);
    if (syncGroupFocusCache) {
      _groupFocusCache = Map.from(cache);
      _updateCaches(); // 更新所有缓存
    }
    LogUtil.i('更新缓存 $cacheName: ${_namedCaches[cacheName]}');
  }

  /// 初始化焦点逻辑，支持指定初始焦点
  void initializeFocusLogic({int? initialIndexOverride}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.focusNodes.isEmpty) {
        LogUtil.i('focusNodes 为空或组件已卸载，无法初始化');
        return;
      }
      
      LogUtil.i('初始化焦点，节点数: ${widget.focusNodes.length}');
      // 更新所有缓存
      _updateCaches();
      
      // 在设置新焦点前移除旧焦点（如果有）
      if (_currentFocus != null && _currentFocus!.hasFocus) {
        _currentFocus!.unfocus();
        _currentFocus = null;
      }
      
      if (widget.groupFocusCache != null) {
        _groupFocusCache = Map.from(widget.groupFocusCache!);
        _updateCaches(); // 更新所有缓存
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
    });
  }

  /// 更新焦点节点索引缓存
  void _updateFocusNodeIndexCache() {
    _focusNodeIndexCache = {};
    for (int i = 0; i < widget.focusNodes.length; i++) {
      _focusNodeIndexCache![widget.focusNodes[i]] = i;
    }
  }

  /// 更新组索引范围缓存
  void _updateGroupIndexRanges() {
    _groupIndexRanges = {};
    _sortedGroupIndices = _groupFocusCache.keys.toList()..sort();
    
    for (var entry in _groupFocusCache.entries) {
      int firstIndex = _getFocusNodeIndex(entry.value['firstFocusNode']!);
      int lastIndex = _getFocusNodeIndex(entry.value['lastFocusNode']!);
      if (firstIndex != -1 && lastIndex != -1) {
        _groupIndexRanges![entry.key] = [firstIndex, lastIndex];
      }
    }
  }

  /// 获取焦点节点索引（优化版）
  int _getFocusNodeIndex(FocusNode node) {
    return _focusNodeIndexCache?[node] ?? widget.focusNodes.indexOf(node);
  }

  /// 查找子页面导航状态（优化：使用迭代替代递归）
  TvKeyNavigationState? _findChildNavigation() {
    // 使用队列进行广度优先搜索，避免深度递归
    final queue = <Element>[];
    final visited = <Element>{};
    
    context.visitChildElements((element) {
      queue.add(element);
    });
    
    while (queue.isNotEmpty) {
      final element = queue.removeAt(0);
      if (visited.contains(element)) continue;
      visited.add(element);
      
      if (element.widget is TvKeyNavigation) {
        final tvNav = element.widget as TvKeyNavigation;
        if (tvNav.frameType == "child") {
          final state = (element as StatefulElement).state;
          if (state is TvKeyNavigationState && state.mounted) {
            LogUtil.i('[_findChildNavigation] 找到子页面: ${tvNav.cacheName}');
            return state;
          }
        }
      }
      
      element.visitChildElements((child) {
        if (!visited.contains(child)) {
          queue.add(child);
        }
      });
    }
    
    LogUtil.i('[_findChildNavigation] 未找到子页面');
    return null;
  }

  /// 查找父页面导航状态（保持原有实现，因为向上查找效率已经很高）
  TvKeyNavigationState? _findParentNavigation() {
    // 子框架向上查找父框架
    TvKeyNavigationState? parentState;
    context.visitAncestorElements((element) {
      if (element.widget is TvKeyNavigation) {
        final tvNav = element.widget as TvKeyNavigation;
        if (tvNav.frameType == "parent") {
          final state = (element as StatefulElement).state;
          if (state is TvKeyNavigationState && state.mounted) {
            parentState = state;
            LogUtil.i('[_findParentNavigation] 找到父页面: ${tvNav.cacheName}');
            return false; // 停止遍历
          }
        }
      }
      return true; // 继续遍历
    });
    
    if (parentState == null) {
      LogUtil.i('[_findParentNavigation] 未找到父页面');
    }
    
    return parentState;
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
    _requestFocusSafely(focusNode, _getFocusNodeIndex(focusNode), groupIndex, skipIfHasFocus: true);
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

  /// 安全请求焦点（优化版）
  void _requestFocusSafely(FocusNode focusNode, int index, int groupIndex, {bool skipIfHasFocus = false}) {
    // 提前返回，避免不必要的操作
    if (skipIfHasFocus && focusNode.hasFocus && _currentFocus == focusNode) {
      return;
    }
    
    // 切换焦点时清理旧缓存
    if (_currentFocus != null && _currentFocus != focusNode) {
      _focusActionCache.remove(_currentFocus);
    }
    
    if (!focusNode.canRequestFocus || focusNode.context == null) {
      LogUtil.i('焦点节点不可用，索引: $index');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focusNode.canRequestFocus && focusNode.context != null) {
          focusNode.requestFocus();
          _currentFocus = focusNode;
          LogUtil.i('延迟重试成功，焦点索引: $index, Group: $groupIndex');
          _ensureFocusVisible(focusNode);
        }
      });
      return;
    }
    
    focusNode.requestFocus();
    _currentFocus = focusNode;
    _ensureFocusVisible(focusNode);
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
    _updateCaches(); // 更新所有缓存
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}';
    updateNamedCache(cache: _groupFocusCache);
    LogUtil.i('保存缓存 $cacheName');
  }

  /// 缓存默认分组的焦点节点
  void _cacheDefaultGroup() {
    final firstFocusNode = _findFocusableNode(widget.focusNodes, findFirst: true);
    final lastFocusNode = _findFocusableNode(widget.focusNodes, findFirst: false);
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

  /// 查找可聚焦节点（合并的通用方法）
  FocusNode _findFocusableNode(List<FocusNode> nodes, {bool findFirst = true}) {
    final finder = findFirst ? nodes.firstWhere : nodes.lastWhere;
    return finder((node) => node.canRequestFocus, 
      orElse: () => FocusNode(debugLabel: '空焦点节点'));
  }

  /// 获取分组内的控件
  List<Widget> _getWidgetsInGroup(Group group) {
    return group.children ?? (group.child != null ? [group.child!] : []);
  }

  /// 获取分组内的焦点节点（优化：使用迭代替代递归）
  List<FocusNode> _getFocusNodesInGroup(List<Widget> widgets) {
    List<FocusNode> focusNodes = [];
    Set<FocusNode> seenNodes = {}; // 避免重复
    
    // 使用栈进行深度优先搜索，避免递归
    final stack = <(Widget, int)>[]; // (widget, depth)
    const int maxDepth = 10;
    
    // 初始化栈
    for (var widget in widgets) {
      stack.add((widget, 0));
    }
    
    while (stack.isNotEmpty) {
      final (widget, depth) = stack.removeLast();
      
      if (depth > maxDepth) continue;
      
      // 直接处理FocusableItem
      if (widget is FocusableItem) {
        if (widget.focusNode.canRequestFocus && 
            !seenNodes.contains(widget.focusNode)) {
          focusNodes.add(widget.focusNode);
          seenNodes.add(widget.focusNode);
        }
        continue; // FocusableItem下不需要继续遍历
      }
      
      // 处理单子组件
      if (widget is SingleChildRenderObjectWidget && widget.child != null) {
        stack.add((widget.child!, depth + 1));
      } 
      // 处理多子组件
      else if (widget is MultiChildRenderObjectWidget) {
        // 反向添加，保持遍历顺序
        for (int i = widget.children.length - 1; i >= 0; i--) {
          stack.add((widget.children[i], depth + 1));
        }
      }
    }
    
    return focusNodes;
  }

  /// 获取焦点所属分组索引（优化版）
  int _getGroupIndex(FocusNode focusNode) {
    try {
      if (_groupIndexRanges == null || _groupIndexRanges!.isEmpty) {
        // 回退到原始方法
        for (var entry in _groupFocusCache.entries) {
          FocusNode firstFocusNode = entry.value['firstFocusNode']!;
          FocusNode lastFocusNode = entry.value['lastFocusNode']!;
          int focusIndex = _getFocusNodeIndex(focusNode);
          if (focusIndex >= _getFocusNodeIndex(firstFocusNode) && 
              focusIndex <= _getFocusNodeIndex(lastFocusNode)) {
            return entry.key;
          }
        }
        return -1;
      }
      
      int nodeIndex = _getFocusNodeIndex(focusNode);
      if (nodeIndex == -1) return -1;
      
      for (var entry in _groupIndexRanges!.entries) {
        if (nodeIndex >= entry.value[0] && nodeIndex <= entry.value[1]) {
          return entry.key;
        }
      }
      return -1;
    } catch (e, stackTrace) {
      LogUtil.i('获取分组索引失败: $e\n位置: $stackTrace');
      return -1;
    }
  }

  /// 获取所有分组（优化：使用迭代替代递归）
  List<Group> _getAllGroups() {
    // 如果已经有groupFocusCache，说明分组已知，避免重复遍历
    if (_groupFocusCache.isNotEmpty) {
      LogUtil.i('使用已有的分组信息');
      return [];
    }
    
    List<Group> groups = [];
    Set<int> seenGroupIndices = {}; // 避免重复的groupIndex
    
    // 使用队列进行广度优先搜索
    final queue = <Element>[];
    final visited = <Element>{};
    const maxElements = 1000; // 限制最大遍历元素数，避免无限循环
    int elementCount = 0;
    
    context.visitChildElements((element) {
      queue.add(element);
    });
    
    while (queue.isNotEmpty && elementCount < maxElements) {
      final element = queue.removeAt(0);
      if (visited.contains(element)) continue;
      visited.add(element);
      elementCount++;
      
      if (element.widget is Group) {
        final group = element.widget as Group;
        // 避免重复的groupIndex
        if (!seenGroupIndices.contains(group.groupIndex)) {
          groups.add(group);
          seenGroupIndices.add(group.groupIndex);
        }
      }
      
      element.visitChildElements((child) {
        if (!visited.contains(child)) {
          queue.add(child);
        }
      });
    }
    
    // 按groupIndex排序，确保顺序一致
    groups.sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
    
    return groups;
  }

/// 处理导航逻辑，根据按键移动焦点（优化：使用预创建的映射）
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    LogUtil.i('处理导航键: $key, frameType: ${widget.frameType}, cacheName: ${widget.cacheName}');
    
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
    
    // 优化：直接使用预创建的操作映射
    Map<LogicalKeyboardKey, VoidCallback>? navigationActions;
    
    // 特殊处理：子框架的垂直分组
    if (widget.isVerticalGroup && widget.frameType == "child") {
      // 子页面垂直分组：上下键导航，右键等同下键，左键返回父页面
      navigationActions = {
        LogicalKeyboardKey.arrowUp: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowUp, forward: false),
        LogicalKeyboardKey.arrowDown: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowDown, forward: true),
        LogicalKeyboardKey.arrowRight: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowDown, forward: true),
        LogicalKeyboardKey.arrowLeft: () => _navigateFocusWrapper(LogicalKeyboardKey.arrowLeft, forward: false),
      };
    } else if (widget.isFrame && widget.frameType == "parent") {
      navigationActions = _parentFrameActions;
    } else if (widget.isFrame && widget.frameType == "child") {
      navigationActions = _childFrameActions;
    } else if (widget.isHorizontalGroup) {
      navigationActions = _horizontalGroupActions;
    } else if (widget.isVerticalGroup) {
      navigationActions = _verticalGroupActions;
    } else {
      navigationActions = _defaultActions;
    }
    
    navigationActions[key]?.call();
    return KeyEventResult.handled;
  }

  /// 切换到子页面导航（简化版本）
  void _switchToChild() {
    var childNavigation = _findChildNavigation();
    
    if (childNavigation != null) {
      deactivateFocusManagement();
      childNavigation.activateFocusManagement();
      LogUtil.i('切换到子页面完成');
    } else {
      LogUtil.i('未找到子页面');
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

  /// 触发当前焦点控件的点击操作（优化版本）
  void _triggerButtonAction() {
    final focusNode = _currentFocus;
    if (focusNode == null || focusNode.context == null) {
      LogUtil.i('无有效焦点节点');
      return;
    }
    
    // 优化1：先检查焦点是否真的需要重新请求
    final bool needsRefocus = !focusNode.hasFocus;
    
    // 检查缓存
    final cachedAction = _focusActionCache[focusNode];
    if (cachedAction != null && cachedAction.isValid()) {
      LogUtil.i('使用缓存的动作，控件类型: ${cachedAction.widgetType}');
      cachedAction.action();
      
      // 优化2：只在需要时重新聚焦
      if (needsRefocus) {
        int newIndex = _getFocusNodeIndex(focusNode);
        if (newIndex != -1) {
          _requestFocusSafely(focusNode, newIndex, _getGroupIndex(focusNode), skipIfHasFocus: true);
        }
      }
      return;
    }
    
    // 清理失效缓存
    if (cachedAction != null) {
      _focusActionCache.remove(focusNode);
    }
    
    // 查找并缓存新动作
    final context = focusNode.context!;
    final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();
    if (focusableItem != null) {
      _findAndCacheAction(context, focusNode);
      
      // 优化3：只在需要时重新聚焦
      if (needsRefocus) {
        int newIndex = _getFocusNodeIndex(focusNode);
        if (newIndex != -1) {
          _requestFocusSafely(focusNode, newIndex, _getGroupIndex(focusNode), skipIfHasFocus: true);
        }
      }
    } else {
      LogUtil.i('未找到 FocusableItem');
    }
  }

  /// 查找并缓存动作（优化版本）
  void _findAndCacheAction(BuildContext context, FocusNode focusNode) {
    // 优化1：限制搜索深度
    const int maxDepth = 5;
    VoidCallback? action;
    Type? actionWidgetType;
    Element? actionElement;
    
    // 优化2：使用访问者模式向上查找，通常动作在较近的祖先中
    context.visitAncestorElements((element) {
      final widget = element.widget;
      
      // 优化3：使用早期返回避免不必要的类型检查
      if (widget is Container || widget is Padding || widget is SizedBox || 
          widget is Align || widget is Center) {
        return true; // 跳过布局类控件，继续向上
      }
      
      // 优化4：按使用频率排序类型检查
      if (widget is ElevatedButton && widget.onPressed != null) {
        action = widget.onPressed;
        actionWidgetType = ElevatedButton;
        actionElement = element;
      } else if (widget is ListTile && widget.onTap != null) {
        action = widget.onTap;
        actionWidgetType = ListTile;
        actionElement = element;
      } else if (widget is IconButton && widget.onPressed != null) {
        action = widget.onPressed;
        actionWidgetType = IconButton;
        actionElement = element;
      } else if (widget is TextButton && widget.onPressed != null) {
        action = widget.onPressed;
        actionWidgetType = TextButton;
        actionElement = element;
      } else if (widget is OutlinedButton && widget.onPressed != null) {
        action = widget.onPressed;
        actionWidgetType = OutlinedButton;
        actionElement = element;
      } else if (widget is FloatingActionButton && widget.onPressed != null) {
        action = widget.onPressed;
        actionWidgetType = FloatingActionButton;
        actionElement = element;
      } else if (widget is GestureDetector && widget.onTap != null) {
        action = widget.onTap;
        actionWidgetType = GestureDetector;
        actionElement = element;
      } else if (widget is SwitchListTile && widget.onChanged != null) {
        final w = widget;
        action = () => w.onChanged!(!w.value);
        actionWidgetType = SwitchListTile;
        actionElement = element;
      } else if (widget is PopupMenuButton) {
        final w = widget;
        if (w.onSelected != null) {
          action = () => w.onSelected!(null);
          actionWidgetType = PopupMenuButton;
          actionElement = element;
        }
      } else if (widget is ChoiceChip) {
        final w = widget;
        if (w.onSelected != null) {
          action = () => w.onSelected!(true);
          actionWidgetType = ChoiceChip;
          actionElement = element;
        }
      }
      
      return action == null; // 找到动作后停止
    });
    
    // 如果向上查找没有结果，再向下查找（保持原有逻辑但限制深度）
    if (action == null) {
      // 使用栈进行迭代遍历，限制深度
      final stack = <(Element, int)>[];
      context.visitChildElements((element) => stack.add((element, 1)));
      
      while (stack.isNotEmpty && action == null) {
        final (element, depth) = stack.removeLast();
        
        if (depth > maxDepth) continue;
        
        final widget = element.widget;
        
        // 跳过布局类控件
        if (!(widget is Container || widget is Padding || widget is SizedBox || 
              widget is Align || widget is Center)) {
          // 尝试提取动作
          if (widget is ElevatedButton && widget.onPressed != null) {
            action = widget.onPressed;
            actionWidgetType = ElevatedButton;
            actionElement = element;
          } else if (widget is ListTile && widget.onTap != null) {
            action = widget.onTap;
            actionWidgetType = ListTile;
            actionElement = element;
          } else if (widget is IconButton && widget.onPressed != null) {
            action = widget.onPressed;
            actionWidgetType = IconButton;
            actionElement = element;
          } else if (widget is TextButton && widget.onPressed != null) {
            action = widget.onPressed;
            actionWidgetType = TextButton;
            actionElement = element;
          } else if (widget is OutlinedButton && widget.onPressed != null) {
            action = widget.onPressed;
            actionWidgetType = OutlinedButton;
            actionElement = element;
          } else if (widget is FloatingActionButton && widget.onPressed != null) {
            action = widget.onPressed;
            actionWidgetType = FloatingActionButton;
            actionElement = element;
          } else if (widget is GestureDetector && widget.onTap != null) {
            action = widget.onTap;
            actionWidgetType = GestureDetector;
            actionElement = element;
          } else if (widget is SwitchListTile && widget.onChanged != null) {
            final w = widget;
            action = () => w.onChanged!(!w.value);
            actionWidgetType = SwitchListTile;
            actionElement = element;
          } else if (widget is PopupMenuButton) {
            final w = widget;
            if (w.onSelected != null) {
              action = () => w.onSelected!(null);
              actionWidgetType = PopupMenuButton;
              actionElement = element;
            }
          } else if (widget is ChoiceChip) {
            final w = widget;
            if (w.onSelected != null) {
              action = () => w.onSelected!(true);
              actionWidgetType = ChoiceChip;
              actionElement = element;
            }
          }
        }
        
        // 继续遍历子元素（如果还没找到动作）
        if (action == null) {
          element.visitChildElements((child) => stack.add((child, depth + 1)));
        }
      }
    }
    
    if (action != null && actionWidgetType != null && actionElement != null) {
      // 缓存动作
      _focusActionCache[focusNode] = _CachedAction(
        action: action!,
        widgetType: actionWidgetType!,
        element: actionElement!,
      );
      action!(); // 执行动作
      
      // 定期清理缓存（每10次操作清理一次）
      if (_focusActionCache.length % 10 == 0) {
        _cleanupActionCache();
      }
    }
  }
  
  /// 清理动作缓存
  void _cleanupActionCache() {
    // 移除失效的缓存项
    _focusActionCache.removeWhere((node, action) => !action.isValid());
    
    // 限制缓存大小
    const maxCacheSize = 50;
    if (_focusActionCache.length > maxCacheSize) {
      // 简单的LRU实现：移除最早的缓存项
      final keysToRemove = _focusActionCache.keys
          .take(_focusActionCache.length - maxCacheSize)
          .toList();
      for (final key in keysToRemove) {
        _focusActionCache.remove(key);
      }
    }
  }

  /// 计算下一个焦点索引
  int _calculateNextIndex(int currentIndex, bool forward, int firstFocusIndex, int lastFocusIndex, {bool isChildFrame = false}) {
    int nextIndex;
    if (forward) {
      nextIndex = currentIndex == lastFocusIndex ? firstFocusIndex : currentIndex + 1;
    } else {
      if (currentIndex == firstFocusIndex) {
        if (isChildFrame) return -1;
        nextIndex = lastFocusIndex;
      } else {
        nextIndex = currentIndex - 1;
      }
    }
    return nextIndex;
  }

  /// 导航焦点（优化版）
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) async {
    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
    // 使用缓存的索引
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

  /// 处理组间跳转（优化版）
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (_groupFocusCache.isEmpty) {
      LogUtil.i('无分组信息，无法跳转');
      return false;
    }
    try {
      // 使用缓存的排序索引
      List<int> groupIndices = _sortedGroupIndices ?? _groupFocusCache.keys.toList()..sort();
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

/// 缓存的动作信息
class _CachedAction {
  final VoidCallback action;
  final Type widgetType;
  final Element element;
  
  _CachedAction({
    required this.action,
    required this.widgetType,
    required this.element,
  });
  
  /// 检查缓存是否仍然有效
  bool isValid() {
    // 检查Element是否仍然在树中
    return element.mounted && element.widget.runtimeType == widgetType;
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
