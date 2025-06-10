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
  
  // 性能优化：焦点索引缓存
  Map<FocusNode, int>? _focusNodeIndexCache;
  Map<int, List<int>>? _groupIndexRanges;
  List<int>? _sortedGroupIndices;
  
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
  LogUtil.i('[TvKeyNavigation] initState - '
      'frameType: ${widget.frameType}, '
      'cacheName: ${widget.cacheName}, '
      'isFrame: ${widget.isFrame}');
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
        _updateCaches(); // 更新所有缓存
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
    if (!mounted) return;
    
    // 1. 先停止焦点管理
    _isFocusManagementActive = false;
    
    // 2. 保存必要的状态
    if (_currentFocus != null && widget.frameType == "parent") {
      _lastParentFocusIndex = _getFocusNodeIndex(_currentFocus!);
    }
    
    // 3. 清理焦点（按依赖顺序）
    if (_currentFocus != null) {
      try {
        if (!preserveFocus && _currentFocus!.hasFocus && _currentFocus!.canRequestFocus) {
          _currentFocus!.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
        }
      } catch (e) {
        LogUtil.i('焦点清理失败: $e');
      }
      _currentFocus = null;
    }
    
    // 4. 清理缓存（按依赖顺序）
    _clearAllCaches();
    
    // 5. 清理分组缓存
    if (widget.frameType == "child" || !widget.isFrame) {
      _groupFocusCache.clear();
    }
    
    // 6. 清理导航缓存中的引用
    _clearNavigationCache();
    
    // 7. 最后移除观察者
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      LogUtil.i('移除观察者失败: $e');
    }
  }

  /// 清理所有缓存
  void _clearAllCaches() {
    _focusNodeIndexCache?.clear();
    _focusNodeIndexCache = null;
    _groupIndexRanges?.clear();
    _groupIndexRanges = null;
    _sortedGroupIndices?.clear();
    _sortedGroupIndices = null;
  }

  /// 更新所有缓存
  void _updateCaches() {
    _updateFocusNodeIndexCache();
    _updateGroupIndexRanges();
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
      _updateCaches(); // 更新所有缓存
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
        // 更新所有缓存
        _updateCaches();
        // 在设置新焦点前移除旧焦点（如果有）
        if (_currentFocus != null && _currentFocus!.hasFocus) {
          LogUtil.i('移除旧焦点: ${_getFocusNodeIndex(_currentFocus!)}');
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
      } catch (e) {
        LogUtil.i('焦点初始化失败: $e');
      }
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

  static final Map<String, TvKeyNavigationState> _navigationCache = {}; // 导航状态缓存

  /// 清理导航缓存中的当前组件引用
  void _clearNavigationCache() {
    // 使用迭代器避免并发修改
    final keysToRemove = <String>[];
    _navigationCache.forEach((key, value) {
      if (value == this) {
        keysToRemove.add(key);
      }
    });
    
    // 批量移除
    for (final key in keysToRemove) {
      _navigationCache.remove(key);
    }
  }

  /// 验证缓存的组件是否仍然有效（修复：不检查子页面的焦点管理状态）
  bool _isNavigationStateValid(TvKeyNavigationState? state) {
    return state != null && state.mounted;
  }

  /// 查找子页面导航状态，使用缓存优化
  TvKeyNavigationState? _findChildNavigation() {
    LogUtil.i('[_findChildNavigation] 开始查找 - 当前cacheName: ${widget.cacheName}')	
    final cacheKey = 'child-${widget.cacheName}';
    final cached = _navigationCache[cacheKey];
    
    // 验证缓存是否有效
    if (_isNavigationStateValid(cached)) {
      LogUtil.i('[查找子页面] 缓存命中: $cacheKey');
      return cached;
    }
    
    // 缓存无效，重新查找
    if (cached != null) {
      LogUtil.i('[查找子页面] 缓存已失效，重新查找: $cacheKey');
      _navigationCache.remove(cacheKey);
    } else {
      LogUtil.i('[查找子页面] 缓存未命中，开始查找: $cacheKey');
    }
    
    TvKeyNavigationState? childNavigation;
    int depth = 0;
    const maxDepth = 15; // 增加最大深度限制
    int visitedCount = 0; // 统计访问的元素数量
    
    void findInContext(BuildContext searchContext) {
      if (childNavigation != null || depth > maxDepth) {
        if (depth > maxDepth) {
          LogUtil.i('[查找子页面] 警告：达到最大深度限制 $maxDepth');
        }
        return;
      }
      depth++;
      visitedCount++;
      
      searchContext.visitChildElements((element) {
      if (depth <= 3) { // 只记录前3层，避免日志过多
        LogUtil.v('[_findChildNavigation] 深度$depth: ${element.widget.runtimeType}');
      }
        if (element.widget is TvKeyNavigation) {
          final tvNav = element.widget as TvKeyNavigation;
        LogUtil.i('[_findChildNavigation] 发现第$tvNavCount个TvKeyNavigation - '
            'frameType: ${tvNav.frameType}, '
            'cacheName: ${tvNav.cacheName}, '
            'isFrame: ${tvNav.isFrame}, '
            'depth: $depth');
          
          if (tvNav.frameType == "child") {
            final state = (element as StatefulElement).state;
            if (state is TvKeyNavigationState && state.mounted) {
              childNavigation = state;
              _navigationCache[cacheKey] = childNavigation!;
              LogUtil.i('[查找子页面] 找到子页面导航并缓存 - cacheName: ${tvNav.cacheName}');
              return;
            } else {
              LogUtil.i('[查找子页面] 子页面状态无效或未挂载');
            }
          }
        }
              // 特别记录关键页面组件
      if (element.widget is AboutPage || element.widget is SettingFontPage || element.widget is AgreementPage) {
        LogUtil.i('[_findChildNavigation] 发现页面组件: ${element.widget.runtimeType} at depth=$depth');
      }
        findInContext(element);
      });
      depth--;
    }
    
    // 使用与 _findParentNavigation 相同的搜索策略
    final rootElement = context.findRootAncestorStateOfType<NavigatorState>()?.context;
    if (rootElement != null) {
      LogUtil.i('[查找子页面] 从 NavigatorState 根节点开始查找');
      findInContext(rootElement);
    } else {
      // 如果找不到 NavigatorState，尝试从当前 context 开始
      LogUtil.i('[查找子页面] 未找到 NavigatorState，从当前 context 开始查找');
      findInContext(context);
    }
    
      LogUtil.i('[_findChildNavigation] 查找结束 - '
      '访问元素: $visitedCount, '
      '发现TvKeyNavigation: $tvNavCount, '
      '找到子页面: ${childNavigation != null}');
    return childNavigation;
  }

  /// 查找父页面导航状态，使用缓存优化
  TvKeyNavigationState? _findParentNavigation() {
    final cacheKey = 'parent-${widget.cacheName}';
    final cached = _navigationCache[cacheKey];
    
    // 验证缓存是否有效
    if (_isNavigationStateValid(cached)) {
      LogUtil.i('[查找父页面] 缓存命中: $cacheKey');
      return cached;
    }
    
    // 缓存无效，重新查找
    if (cached != null) {
      LogUtil.i('[查找父页面] 缓存已失效，重新查找: $cacheKey');
      _navigationCache.remove(cacheKey);
    } else {
      LogUtil.i('[查找父页面] 缓存未命中，开始查找: $cacheKey');
    }
    
    TvKeyNavigationState? parentNavigation;
    int depth = 0;
    const maxDepth = 10; // 限制遍历深度
    int visitedCount = 0; // 统计访问的元素数量
    
    void findInContext(BuildContext context) {
      if (parentNavigation != null || depth > maxDepth) {
        if (depth > maxDepth) {
          LogUtil.i('[查找父页面] 警告：达到最大深度限制 $maxDepth');
        }
        return;
      }
      depth++;
      visitedCount++;
      
      context.visitChildElements((element) {
        if (element.widget is TvKeyNavigation) {
          final tvNav = element.widget as TvKeyNavigation;
          LogUtil.i('[查找父页面] 发现 TvKeyNavigation - frameType: ${tvNav.frameType}, cacheName: ${tvNav.cacheName}, depth: $depth');
          
          if (tvNav.frameType == "parent") {
            final state = (element as StatefulElement).state;
            if (state is TvKeyNavigationState && state.mounted) {
              parentNavigation = state;
              _navigationCache[cacheKey] = parentNavigation!;
              LogUtil.i('[查找父页面] 找到父页面导航并缓存 - cacheName: ${tvNav.cacheName}');
              return;
            } else {
              LogUtil.i('[查找父页面] 父页面状态无效或未挂载');
            }
          }
        }
        findInContext(element);
      });
      depth--;
    }
    
    final rootElement = context.findRootAncestorStateOfType<NavigatorState>()?.context;
    if (rootElement != null) {
      LogUtil.i('[查找父页面] 从 NavigatorState 根节点开始查找');
      findInContext(rootElement);
    } else {
      LogUtil.i('[查找父页面] 未找到 NavigatorState，从当前 context 开始查找');
      findInContext(context);
    }
    
    if (parentNavigation == null) {
      LogUtil.i('[查找父页面] 未找到父页面导航，已访问 $visitedCount 个元素');
    } else {
      LogUtil.i('[查找父页面] 成功找到父页面导航，已访问 $visitedCount 个元素');
    }
    
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
    _namedCaches[cacheName] = Map.from(_groupFocusCache);
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

  /// 获取分组内的焦点节点（优化版）
  List<FocusNode> _getFocusNodesInGroup(List<Widget> widgets) {
    List<FocusNode> focusNodes = [];
    Set<FocusNode> seenNodes = {}; // 避免重复
    const int maxDepth = 10; // 添加深度限制
    
    void collectFocusNodes(Widget widget, int depth) {
      if (depth > maxDepth) return;
      
      // 直接处理FocusableItem
      if (widget is FocusableItem) {
        if (widget.focusNode.canRequestFocus && 
            !seenNodes.contains(widget.focusNode)) {
          focusNodes.add(widget.focusNode);
          seenNodes.add(widget.focusNode);
        }
        return; // FocusableItem下不需要继续遍历
      }
      
      // 处理单子组件
      if (widget is SingleChildRenderObjectWidget && widget.child != null) {
        collectFocusNodes(widget.child!, depth + 1);
      } 
      // 处理多子组件
      else if (widget is MultiChildRenderObjectWidget) {
        for (var child in widget.children) {
          collectFocusNodes(child, depth + 1);
        }
      }
    }
    
    // 开始收集
    for (var widget in widgets) {
      collectFocusNodes(widget, 0);
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

  /// 获取所有分组（优化版）
  List<Group> _getAllGroups() {
    // 如果已经有groupFocusCache，说明分组已知，避免重复遍历
    if (_groupFocusCache.isNotEmpty) {
      LogUtil.i('使用已有的分组信息');
      return [];
    }
    
    List<Group> groups = [];
    Set<int> seenGroupIndices = {}; // 避免重复的groupIndex
    int depth = 0;
    const maxDepth = 10; // 限制最大遍历深度
    
    void searchGroups(Element element) {
      if (depth > maxDepth) return;
      depth++;
      
      if (element.widget is Group) {
        final group = element.widget as Group;
        // 避免重复的groupIndex
        if (!seenGroupIndices.contains(group.groupIndex)) {
          groups.add(group);
          seenGroupIndices.add(group.groupIndex);
        }
      }
      element.visitChildren(searchGroups);
      
      depth--;
    }
    
    if (context != null) context.visitChildElements(searchGroups);
    
    // 按groupIndex排序，确保顺序一致
    groups.sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
    
    return groups;
  }

  /// 处理导航逻辑，根据按键移动焦点
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
  	LogUtil.i('[TvKeyNavigation] 处理导航键: $key, frameType: ${widget.frameType}, cacheName: ${widget.cacheName}');
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
    LogUtil.i('[TvKeyNavigation] 当前焦点: index=$currentIndex, group=$groupIndex');
  if (widget.isFrame && widget.frameType == "parent" && key == LogicalKeyboardKey.arrowRight) {
    LogUtil.i('[TvKeyNavigation] 父框架收到右键，准备切换到子页面');
  }
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
    LogUtil.i('[TvKeyNavigation] _switchToChild 开始执行 - cacheName: ${widget.cacheName}');	
  	
    // 立即尝试查找
    var childNavigation = _findChildNavigation();
    
    if (childNavigation != null) {
    	LogUtil.i('[TvKeyNavigation] 找到子页面，准备切换');
      // 找到子页面，执行切换
      deactivateFocusManagement();
      childNavigation!.activateFocusManagement();
      LogUtil.i('[TvKeyNavigation] 切换到子页面完成');
    } else {
      // 未找到子页面，可能还在构建中，延迟重试
      LogUtil.i('[TvKeyNavigation] 子页面未找到，延迟重试');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          LogUtil.i('[TvKeyNavigation] 延迟重试时组件已卸载');
          return;
        }
        LogUtil.i('[TvKeyNavigation] 开始延迟重试查找');
        // 再次尝试查找
        childNavigation = _findChildNavigation();
        if (childNavigation != null) {
          deactivateFocusManagement();
          childNavigation!.activateFocusManagement();
          LogUtil.i('延迟切换到子页面成功');
        } else {
          LogUtil.i('子页面仍未找到');
        }
      });
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

  /// 在 FocusableItem 中触发交互控件操作（合并后的方法）
  void _triggerActionsInFocusableItem(BuildContext context) {
    bool stop = false;
    
    void visitElement(Element element) {
      if (stop) return;
      
      final widget = element.widget;
      final lowPriorityWidgets = [Container, Padding, SizedBox, Align, Center];
      
      // 跳过低优先级控件
      if (!lowPriorityWidgets.contains(widget.runtimeType)) {
        // 尝试触发特定控件操作
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
          stop = true;
          return;
        } else if ([ElevatedButton, TextButton, OutlinedButton, IconButton, 
                    FloatingActionButton, GestureDetector, ListTile].contains(widget.runtimeType)) {
          LogUtil.i('找到控件但无法触发');
        }
      }
      
      // 继续遍历子元素
      element.visitChildren(visitElement);
    }
    
    context.visitChildElements(visitElement);
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
        parentNavigation!.activateFocusManagement();
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
