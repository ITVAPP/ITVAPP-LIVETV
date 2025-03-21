import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/channel_drawer_page.dart';
import 'package:async/async.dart'; // 修改处：引入Debouncer所需的包

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.3]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode>? focusNodes; // 修改处：改为可选参数
  final Map<int, Map<String, FocusNode>>? groupFocusCache; // 修改处：可选的分组缓存参数
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final bool isFrame; // 是否启用框架模式，用于切换焦点
  final String? frameType; // 用于识别父页面或子页面
  final int? initialIndex; // 初始焦点的索引，默认为空，如果为空则使用自动聚焦
  final bool isHorizontalGroup; // 是否启用横向分组
  final bool isVerticalGroup; // 是否启用竖向分组
  final Function(TvKeyNavigationState state)? onStateCreated;
  final String? cacheName; // 自定义缓存名称

  const TvKeyNavigation({
    Key? key,
    required this.child,
    this.focusNodes, // 修改处：改为可选
    this.groupFocusCache, // 修改处：保持可选
    this.onSelect,
    this.onKeyPressed,
    this.isFrame = false,
    this.frameType, // 父页面或子页面
    this.initialIndex,
    this.isHorizontalGroup = false, // 默认不按横向分组
    this.isVerticalGroup = false,   // 默认不按竖向分组
    this.onStateCreated,
    this.cacheName,
  }) : super(key: key);

  @override
  TvKeyNavigationState createState() => TvKeyNavigationState();
}

// 修改处：添加自定义FocusTraversalPolicy，用于优化组内导航
class TvFocusTraversalPolicy extends FocusTraversalPolicy {
  final List<FocusNode> focusNodes;
  final Map<int, Map<String, FocusNode>> groupFocusCache;

  TvFocusTraversalPolicy(this.focusNodes, this.groupFocusCache);

  @override
  FocusNode? findNextFocus(FocusNode currentNode, TraversalDirection direction) {
    int currentIndex = focusNodes.indexOf(currentNode);
    int groupIndex = _getGroupIndex(currentNode);
    if (groupIndex == -1) return null;

    FocusNode first = groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode last = groupFocusCache[groupIndex]!['lastFocusNode']!;
    int firstIndex = focusNodes.indexOf(first);
    int lastIndex = focusNodes.indexOf(last);

    if (direction == TraversalDirection.down || direction == TraversalDirection.right) {
      return currentIndex == lastIndex ? first : focusNodes[currentIndex + 1];
    } else if (direction == TraversalDirection.up || direction == TraversalDirection.left) {
      return currentIndex == firstIndex ? last : focusNodes[currentIndex - 1];
    }
    return null;
  }

  int _getGroupIndex(FocusNode node) {
    for (var entry in groupFocusCache.entries) {
      if (focusNodes.indexOf(node) >= focusNodes.indexOf(entry.value['firstFocusNode']!) &&
          focusNodes.indexOf(node) <= focusNodes.indexOf(entry.value['lastFocusNode']!)) {
        return entry.key;
      }
    }
    return -1;
  }
}

class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus;
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};
  // 修改处：添加动态焦点节点存储
  List<FocusNode> _dynamicFocusNodes = [];
  // 按页面名称存储的缓存
  static Map<String, Map<int, Map<String, FocusNode>>> _namedCaches = {};
  bool _isFocusManagementActive = false;
  int? _lastParentFocusIndex;
  DateTime? _lastKeyProcessedTime; // 新增：记录上一次按键处理的时间
  static const Duration _throttleDuration = Duration(milliseconds: 200); // 按键节流间隔的毫秒数
  // 修改处：添加Debouncer用于节流
  final _debouncer = Debouncer(Duration(milliseconds: 200));
  
  // 判断是否为导航相关的按键（方向键、选择键和确认键）
  bool _isNavigationKey(LogicalKeyboardKey key) {
    return _isDirectionKey(key) || _isSelectKey(key);
  }
  
  @override
  Widget build(BuildContext context) {
    // 修改处：将Focus包裹在FocusScope中，增强分组管理
    return FocusScope(
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            // 如果是导航相关的按键，处理并阻止传递
            if (_isNavigationKey(event.logicalKey)) {
              final result = _handleKeyEvent(node, event);
              return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
            }
          }
          // 其他按键继续传递
          return KeyEventResult.ignored;
        },
        child: widget.child, // 直接使用传入的子组件
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);
    // 根据 frameType 初始化焦点管理状态
    _isFocusManagementActive = !widget.isFrame || widget.frameType == "parent";
    // 如果焦点管理未激活，则不处理按键事件
    if (_isFocusManagementActive) {
       initializeFocusLogic(); // 调用初始化焦点逻辑
    }
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  /// 激活焦点管理
  void activateFocusManagement({int? initialIndexOverride}) {
    setState(() {
      _isFocusManagementActive = true;
    });

    // 如果传入了 cacheName，直接使用缓存
    if (widget.cacheName != null) {
      String cacheName = 'groupCache-${widget.cacheName}';
      if (_namedCaches.containsKey(cacheName)) {
        _groupFocusCache = Map.from(_namedCaches[cacheName]!);
        LogUtil.i('Using cache for ${widget.cacheName}');
        
        // 恢复焦点位置
        _requestFocus(_lastParentFocusIndex ?? 0);
      } else {
        LogUtil.i('No cache found for ${widget.cacheName}');
      }
    }
    // 如果是子页面，直接初始化焦点逻辑
    else if (widget.frameType == "child") {
      initializeFocusLogic();
    }
    LogUtil.i('Focus management activated');
  }

  /// 停用焦点管理
  void deactivateFocusManagement() {
      setState(() {
        _isFocusManagementActive = false;
        if (widget.frameType == "parent" && _currentFocus != null) {
          _lastParentFocusIndex = (widget.focusNodes ?? _dynamicFocusNodes).indexOf(_currentFocus!);
          LogUtil.i('Saved parent focus position: $_lastParentFocusIndex');
        }
      });
      LogUtil.i('Focus management deactivated');
  }
  
  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }

  /// 释放组件使用的资源
  // 修改处：支持动态焦点节点
  void releaseResources() {
    if (_currentFocus != null && _currentFocus!.canRequestFocus) {
      if (widget.frameType == "parent") {
        _lastParentFocusIndex = (widget.focusNodes ?? _dynamicFocusNodes).indexOf(_currentFocus!);
      }
      if (_currentFocus!.hasFocus) {
        _currentFocus!.unfocus();
      }
      _currentFocus = null;
    }

    if (widget.frameType == "child" || !widget.isFrame) {
      _groupFocusCache.clear();
      // 修改处：释放动态焦点节点
      if (widget.focusNodes == null) {
        for (var node in _dynamicFocusNodes) {
          node.dispose();
        }
        _dynamicFocusNodes.clear();
      }
    }

    _isFocusManagementActive = !widget.isFrame;
    WidgetsBinding.instance.removeObserver(this);
  }

  void updateNamedCache({required Map<int, Map<String, FocusNode>> cache, bool syncGroupFocusCache = true}) {
    if (widget.cacheName == null) {
      LogUtil.i('cacheName not provided, cannot update _namedCaches');
      return;
    }
    if (cache.isEmpty) {
      LogUtil.i('Cache is empty, skipping update to _namedCaches');
      return;
    }
    final cacheName = 'groupCache-${widget.cacheName}';
    _namedCaches[cacheName] = Map.from(cache);
    if (syncGroupFocusCache) {
      _groupFocusCache = Map.from(cache);
    }
    LogUtil.i('Updated _namedCaches[$cacheName]: ${_namedCaches[cacheName]}');
  }
  
  /// 初始化焦点逻辑
  // 修改处：支持动态获取焦点节点
  void initializeFocusLogic({int? initialIndexOverride}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (widget.focusNodes != null) {
          // 使用传入的 focusNodes
          if (widget.focusNodes!.isEmpty) {
            LogUtil.i('focusNodes is empty, cannot set focus');
            return; 
          } else {
            LogUtil.i('Initializing focus logic with ${widget.focusNodes!.length} nodes');
          }
          
          // 检查是否传入了 groupFocusCache
          if (widget.groupFocusCache != null) {
            _groupFocusCache = Map.from(widget.groupFocusCache!);
            LogUtil.i('Using provided groupFocusCache: ${_groupFocusCache.map((key, value) => MapEntry(key, "{first: ${widget.focusNodes!.indexOf(value['firstFocusNode']!)}, last: ${widget.focusNodes!.indexOf(value['lastFocusNode']!)}}"))}');
            updateNamedCache(cache: _groupFocusCache); 
          } else {
            LogUtil.i('No groupFocusCache provided, performing group lookup');
            cacheGroupFocusNodes();
          }
        } else {
          // 动态获取焦点节点
          collectDynamicFocusNodes();
          if (_dynamicFocusNodes.isEmpty) {
            LogUtil.i('No focus nodes dynamically acquired, cannot set focus');
            return;
          }
          LogUtil.i('Dynamically initializing focus logic with ${_dynamicFocusNodes.length} nodes');
          cacheGroupFocusNodes();
        }

        // 使用 initialIndexOverride 参数，如果为空则使用 widget.initialIndex 或默认 0
        int initialIndex = initialIndexOverride ?? widget.initialIndex ?? 0;

        // initialIndex 为 -1，跳过设置初始焦点的逻辑
        if (initialIndex != -1 && (widget.focusNodes ?? _dynamicFocusNodes).isNotEmpty) {
          _requestFocus(initialIndex); // 设置初始焦点
        } 
      } catch (e) {
        LogUtil.i('Failed to initialize focus: $e');
      }
    });
  }

  /// 动态收集焦点节点
  // 修改处：重命名以避免重复声明
  void collectDynamicFocusNodes() {
    _dynamicFocusNodes.clear();
    _groupFocusCache.clear();
    void visitNode(Widget widget) {
      if (widget is FocusableItem) {
        _dynamicFocusNodes.add(widget.focusNode);
        final groupIndex = getGroupIndexFromContext(widget.focusNode.context);
        if (!_groupFocusCache.containsKey(groupIndex)) {
          _groupFocusCache[groupIndex] = {
            'firstFocusNode': widget.focusNode,
            'lastFocusNode': widget.focusNode,
          };
        } else {
          _groupFocusCache[groupIndex]!['lastFocusNode'] = widget.focusNode;
        }
      } else if (widget is MultiChildRenderObjectWidget) {
        for (var child in widget.children) {
          visitNode(child);
        }
      } else if (widget is SingleChildRenderObjectWidget) {
        if (widget.child != null) visitNode(widget.child!);
      }
    }
    visitNode(widget.child);
  }

  /// 从上下文获取 groupIndex
  // 修改处：重命名以避免重复声明
  int getGroupIndexFromContext(BuildContext? context) {
    while (context != null) {
      final group = context.findAncestorWidgetOfExactType<Group>();
      if (group != null) return group.groupIndex;
      context = context.findAncestorStateOfType<StatefulWidget>()?.context ??
          context.findAncestorStateOfType<StatelessWidget>()?.context;
    }
    return 0; // 默认组
  }

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    LogUtil.i('$message: $error\n位置: $stackTrace');
  }
  
  /// 查找子页面导航状态
  TvKeyNavigationState? _findChildNavigation() {
    TvKeyNavigationState? childNavigation;
    void visitChild(Element element) {
      if (element.widget is TvKeyNavigation) {
        final navigationWidget = element.widget as TvKeyNavigation;
        // 检查 frameType 是否为 "child"
        if (navigationWidget.frameType == "child") {
          // 找到目标子页面并进行初始化
          childNavigation = (element as StatefulElement).state as TvKeyNavigationState;
          LogUtil.i('Found available child navigation component');
          return; // 停止递归
        }
      }
      // 继续递归地访问子元素
      element.visitChildren(visitChild);
    }
    // 开始从当前 context 访问子元素
    context.visitChildElements(visitChild);
    if (childNavigation == null) {
      LogUtil.i('No available child navigation component found');
    }
    return childNavigation;
  }

  /// 查找父页面导航状态
  TvKeyNavigationState? _findParentNavigation() {
    TvKeyNavigationState? parentNavigation;

    // 在整个页面范围内查找 parent navigation
    void findInContext(BuildContext context) {
      context.visitChildElements((element) {
        // 检查是否是 TvKeyNavigation
        if (element.widget is TvKeyNavigation) {
          final navigationWidget = element.widget as TvKeyNavigation;
          // 确保只查找 frameType 为 "parent" 且可见的父页面
          if (navigationWidget.frameType == "parent") {
            parentNavigation = (element as StatefulElement).state as TvKeyNavigationState;
            LogUtil.i('Found available parent navigation component');
            return; // 找到后停止遍历
          }
        }
        // 继续递归查找
        findInContext(element);
      });
    }

    // 从根部开始查找
    final rootElement = context.findRootAncestorStateOfType<NavigatorState>()?.context;
    if (rootElement != null) {
      findInContext(rootElement);
    }

    // 如果找不到合适的父组件，添加调试信息
    if (parentNavigation == null) {
      LogUtil.i('No available parent navigation component found');
    }

    return parentNavigation;
  }
  
  /// 请求将焦点切换到指定索引的控件上
  // 修改处：支持动态焦点节点并修复非ASCII字符和index问题
  void _requestFocus(int index, {int? groupIndex}) {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    if (focusNodes.isEmpty) {
      LogUtil.i('Focus node list is empty, cannot set focus');
      return;
    }

    try {
      // 检查 index 是否在合法范围内
      if (index < 0 || index >= focusNodes.length) {
        return;
      }

      // 从缓存获取 groupIndex
      groupIndex ??= getGroupIndex(focusNodes[index]);
      if (groupIndex == -1 || !_groupFocusCache.containsKey(groupIndex)) {
        // 无效的 groupIndex，直接设置为第一个可请求焦点的节点
        FocusNode firstValidFocusNode = focusNodes.firstWhere(
          (node) => node.canRequestFocus, 
          orElse: () => focusNodes[0]
        );

        // 请求第一个有效焦点
        firstValidFocusNode.requestFocus();
        _currentFocus = firstValidFocusNode;
        if (FocusManager.instance.primaryFocus != _currentFocus) {
          FocusManager.instance.primaryFocus?.unfocus();
          firstValidFocusNode.requestFocus();
        }
        LogUtil.i('Invalid Group, setting to first available focus node');
        return;
      }

      // 获取当前组的焦点范围
      FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
      FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
      int firstFocusIndex = focusNodes.indexOf(firstFocusNode);
      int lastFocusIndex = focusNodes.indexOf(lastFocusNode);

      // 确保 index 在当前组的范围内
      int newIndex = index; // 使用局部变量而不是类成员
      if (newIndex < firstFocusIndex) {
        newIndex = lastFocusIndex; // 循环到最后一个焦点
      } else if (newIndex > lastFocusIndex) {
        newIndex = firstFocusIndex; // 循环到第一个焦点
      }

      FocusNode focusNode = focusNodes[newIndex];

      // 检查焦点是否可请求
      if (!focusNode.canRequestFocus) {
        LogUtil.i('Focus node cannot be requested, index: $newIndex');
        return;
      }

      // 请求焦点
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();  // 设置焦点到指定的节点
        _currentFocus = focusNode;
        if (FocusManager.instance.primaryFocus != _currentFocus) {
          LogUtil.i('Focus state inconsistent, syncing to FocusManager');
          FocusManager.instance.primaryFocus?.unfocus();
          focusNode.requestFocus();
        }
        LogUtil.i('Switched focus to index: $newIndex, current Group: $groupIndex');
      }
    } catch (e, stackTrace) {
      LogUtil.i('Unknown error occurred while setting focus: $e\nStack trace: $stackTrace');
    }
  }
  
  /// 缓存 Group 的焦点信息
  // 修改处：重命名以避免重复声明
  void cacheGroupFocusNodes() {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    if (widget.groupFocusCache != null && widget.focusNodes != null) {
      LogUtil.i('groupFocusCache provided, skipping cacheGroupFocusNodes');
      return;
    }
    _groupFocusCache.clear();  // 清空缓存
    final groups = getAllGroups();
    LogUtil.i('Caching groups: Total groups found: ${groups.length}');

    if (groups.isEmpty || groups.length == 1) {
      cacheDefaultGroup();
    } else {
      for (var group in groups) {
        final scopeNode = FocusScope.of(group.child?.context ?? context);
        final groupFocusNodes = getFocusNodesInScope(scopeNode).where((node) => focusNodes.contains(node)).toList();
        if (groupFocusNodes.isNotEmpty) {
          _groupFocusCache[group.groupIndex] = {
            'firstFocusNode': groupFocusNodes.first,
            'lastFocusNode': groupFocusNodes.last,
          };
          LogUtil.i('Group ${group.groupIndex}: '
                    'First focus node: ${formatFocusNodeDebugLabel(groupFocusNodes.first)}, '
                    'Last focus node: ${formatFocusNodeDebugLabel(groupFocusNodes.last)}');
        } else {
          LogUtil.i('Warning: Group ${group.groupIndex} has no focusable nodes');
        }
      }
    }
    
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}';
    _namedCaches[cacheName] = Map.from(_groupFocusCache);
    LogUtil.i('Saved cache for $cacheName');
  }
  
  // 缓存默认分组（无分组或单一分组）的焦点节点
  // 修改处：重命名以避免重复声明
  void cacheDefaultGroup() {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    final firstFocusNode = findFirstFocusableNode(focusNodes);
    final lastFocusNode = findLastFocusableNode(focusNodes);

    _groupFocusCache[0] = {
      'firstFocusNode': firstFocusNode,
      'lastFocusNode': lastFocusNode,
    };

    LogUtil.i('Cached default group focus nodes - '
               'First focus node: ${formatFocusNodeDebugLabel(firstFocusNode)}, '
               'Last focus node: ${formatFocusNodeDebugLabel(lastFocusNode)}'
    );
  }

  // 修改处：重命名以避免重复声明，并修复visitChildren问题
  List<FocusNode> getFocusNodesInScope(FocusScopeNode scope) {
    List<FocusNode> nodes = [];
    // FocusScopeNode没有visitChildren方法，改为遍历focusNodes
    for (var node in (widget.focusNodes ?? _dynamicFocusNodes)) {
      if (node.canRequestFocus && scope.descendants.contains(node)) {
        nodes.add(node);
      }
    }
    return nodes;
  }

  // 遍历分组缓存它们的焦点节点
  void cacheMultipleGroups(List<Group> groups) {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    for (var group in groups) {
      final groupWidgets = getWidgetsInGroup(group);
      final groupFocusNodes = getFocusNodesInGroup(groupWidgets).where((node) => focusNodes.contains(node)).toList();

      if (groupFocusNodes.isNotEmpty) {
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': groupFocusNodes.first,
          'lastFocusNode': groupFocusNodes.last,
        };

        LogUtil.i('Group ${group.groupIndex}: '
                   'First focus node: ${formatFocusNodeDebugLabel(groupFocusNodes.first)}, '
                   'Last focus node: ${formatFocusNodeDebugLabel(groupFocusNodes.last)}'
        );
      } else {
        LogUtil.i('Warning: Group ${group.groupIndex} has no focusable nodes');
      }
    }
  }
  
  // 查找第一个可聚焦的节点
  // 修改处：重命名以避免重复声明
  FocusNode findFirstFocusableNode(List<FocusNode> nodes) {
    return nodes.firstWhere(
      (node) => node.canRequestFocus,
      orElse: () => FocusNode(debugLabel: 'Empty focus node') // 添加 debugLabel，便于调试
    );
  }

  // 查找最后一个可聚焦的节点
  // 修改处：重命名以避免重复声明
  FocusNode findLastFocusableNode(List<FocusNode> nodes) {
    return nodes.lastWhere(
      (node) => node.canRequestFocus,
      orElse: () => FocusNode(debugLabel: 'Empty focus node')
    );
  }

  // 修改处：重命名以避免重复声明
  String formatFocusNodeDebugLabel(FocusNode focusNode) {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    return focusNode.debugLabel ?? 'Index: ${focusNodes.indexOf(focusNode)}';
  }

  // 修改处：重命名以避免重复声明
  List<Widget> getWidgetsInGroup(Group group) {
    return group.children ?? (group.child != null ? [group.child!] : []);
  }

  // 修改处：重命名以避免重复声明
  List<FocusNode> getFocusNodesInGroup(List<Widget> widgets) {
    List<FocusNode> focusNodes = [];
    for (var widget in widgets) {
      if (widget is FocusableItem) {
        focusNodes.add(widget.focusNode);
      } else if (widget is SingleChildRenderObjectWidget && widget.child != null) {
        focusNodes.addAll(getFocusNodesInGroup([widget.child!]));
      } else if (widget is MultiChildRenderObjectWidget) {
        focusNodes.addAll(getFocusNodesInGroup(widget.children));
      }
    }
    return focusNodes.where((node) => node.canRequestFocus).toList();
  }

  /// 获取当前焦点所属的 groupIndex
  // 修改处：支持动态焦点节点
  int getGroupIndex(FocusNode focusNode) {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    try {
      for (var entry in _groupFocusCache.entries) {
        FocusNode firstFocusNode = entry.value['firstFocusNode']!;
        FocusNode lastFocusNode = entry.value['lastFocusNode']!;

        if (focusNodes.indexOf(focusNode) >= focusNodes.indexOf(firstFocusNode) &&
            focusNodes.indexOf(focusNode) <= focusNodes.indexOf(lastFocusNode)) {
          return entry.key;  // 返回对应的 groupIndex
        }
      }
      return -1; // 如果没有找到匹配的分组，返回 -1
    } catch (e, stackTrace) {
      _handleError('Failed to get group index from cache', e, stackTrace);
      return -1;
    }
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return _groupFocusCache.length; 
  }

  /// 获取所有的 Group
  // 修改处：重命名以避免重复声明
  List<Group> getAllGroups() {
    List<Group> groups = [];
    void searchGroups(Element element) {
      if (element.widget is Group) {
        groups.add(element.widget as Group);
      }
      element.visitChildren((child) {
        searchGroups(child);
      });
    }
    if (context != null) {
      context.visitChildElements((element) {
        searchGroups(element);
      });
    }
    return groups;
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  // 修改处：支持动态焦点节点并重命名
  KeyEventResult handleNavigation(LogicalKeyboardKey key) {
    FocusNode? currentFocus = FocusManager.instance.primaryFocus ?? _currentFocus;
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;

    if (currentFocus == null) {
      LogUtil.i('No current focus, attempting to set initial focus');
      _requestFocus(0); // 设置焦点为第一个控件
      return KeyEventResult.handled;
    }

    int currentIndex = focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      LogUtil.i('Current focus index not found');
      return KeyEventResult.ignored; 
    }

    int groupIndex = getGroupIndex(currentFocus);
    
    try {
      if (widget.isFrame) {
        if (widget.frameType == "parent") {
          if (key == LogicalKeyboardKey.arrowRight) {
            final childNavigation = _findChildNavigation();
            if (childNavigation != null) {
              deactivateFocusManagement();
              childNavigation.activateFocusManagement();
              LogUtil.i('Switched to child page');
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);
          }
        } else if (widget.frameType == "child") {
          if (key == LogicalKeyboardKey.arrowLeft) {
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        }
      } else {
        if (widget.isHorizontalGroup) {
          if (key == LogicalKeyboardKey.arrowLeft) {
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else if (widget.isVerticalGroup) {
          if (key == LogicalKeyboardKey.arrowUp) {
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else {
          final policy = TvFocusTraversalPolicy(focusNodes, _groupFocusCache);
          FocusNode? nextFocus;
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
            nextFocus = policy.findNextFocus(currentFocus, TraversalDirection.up);
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
            nextFocus = policy.findNextFocus(currentFocus, TraversalDirection.down);
          }
          if (nextFocus != null) {
            nextFocus.requestFocus();
            _currentFocus = nextFocus;
          }
        }
      }
    } catch (e) {
      LogUtil.i('Focus switch error: $e');
    }

    FocusNode? currentFocusNode = _currentFocus;
    if (currentFocusNode != null) {
      int newIndex = focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex);
      }
    }

    return KeyEventResult.handled;
  }
  
  /// 处理键盘事件，包括方向键和选择键。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {    
    if (event is KeyEvent && event is! KeyUpEvent) {
      LogicalKeyboardKey key = event.logicalKey;
      
      if (!_isFocusManagementActive) {
        LogUtil.i('Focus management not active, ignoring key event');
        return KeyEventResult.ignored;
      }
      
      if (_isDirectionKey(key)) {
        _debouncer(() => handleNavigation(key));
        return KeyEventResult.handled;
      }

      if (_isSelectKey(key)) {
        try {
          _triggerButtonAction();
        } catch (e) {
          LogUtil.i('Error executing button action: $e');
        }
        return KeyEventResult.handled;
      }

      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
      }
    }
    return KeyEventResult.ignored; 
  }
  
  /// 判断是否为方向键
  bool _isDirectionKey(LogicalKeyboardKey key) {
    return {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    }.contains(key);
  }

  /// 判断是否为选择键
  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
  }
  
  /// 执行当前焦点控件的点击操作
  void _triggerButtonAction() { 
    final focusNode = _currentFocus;
    if (focusNode != null && focusNode.context != null) {
      final BuildContext? context = focusNode.context;

      if (context == null) {
        LogUtil.i('Focus context is null, cannot operate');
        return;
      }

      try {
        final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();

        if (focusableItem != null) {
          _triggerActionsInFocusableItem(context);
        } else {
          LogUtil.i('No FocusableItem wrapper found');
        }
      } catch (e, stackTrace) {
        LogUtil.i('Error during operation: $e, Stack trace: $stackTrace');
      }
    }
  }

  // 在 FocusableItem 节点下查找并触发第一个交互控件的操作
  void _triggerActionsInFocusableItem(BuildContext context) {
    _visitAllElements(context, (element) {
      final widget = element.widget;
      return _triggerWidgetAction(widget);
    });
  }

  // 遍历函数，遇到交互控件后终止遍历
  bool _visitAllElements(BuildContext context, bool Function(Element) visitor) {
    bool stop = false;
    context.visitChildElements((element) {
      if (stop) return;
      stop = visitor(element);
      if (!stop) {
        stop = _visitAllElements(element, visitor);
      }
    });
    return stop;
  }

  // 执行目标控件的操作函数，返回 true 表示已触发操作并停止查找
  bool _triggerWidgetAction(Widget widget) {
    final highPriorityWidgets = [
      ElevatedButton,
      TextButton,
      OutlinedButton,
      IconButton,
      FloatingActionButton,
      GestureDetector,
      ListTile,
    ];

    final lowPriorityWidgets = [
      Container,
      Padding,
      SizedBox,
      Align,
      Center,
    ];

    if (lowPriorityWidgets.contains(widget.runtimeType)) {
      return false;
    }

    for (var type in highPriorityWidgets) {
      if (widget.runtimeType == type) {
        return _triggerSpecificWidgetAction(widget);
      }
    }

    return _triggerSpecificWidgetAction(widget);
  }
  
  // 触发特定组件的操作
  bool _triggerSpecificWidgetAction(Widget widget) {
    if (widget is SwitchListTile && widget.onChanged != null) {
      Function.apply(widget.onChanged!, [!widget.value]);
      return true;
    } else if (widget is ElevatedButton && widget.onPressed != null) {	
      Function.apply(widget.onPressed!, []);
      return true;
    } else if (widget is TextButton && widget.onPressed != null) {
      Function.apply(widget.onPressed!, []);
      return true;
    } else if (widget is OutlinedButton && widget.onPressed != null) {
      Function.apply(widget.onPressed!, []);
      return true;
    } else if (widget is IconButton && widget.onPressed != null) {
      Function.apply(widget.onPressed!, []);
      return true;
    } else if (widget is FloatingActionButton && widget.onPressed != null) {
      Function.apply(widget.onPressed!, []);
      return true;
    } else if (widget is ListTile && widget.onTap != null) {
      Function.apply(widget.onTap!, []);
      return true;
    } else if (widget is GestureDetector && widget.onTap != null) {
      Function.apply(widget.onTap!, []);
      return true;
    } else if (widget is PopupMenuButton && widget.onSelected != null) {
      Function.apply(widget.onSelected!, [null]);
      return true;
    } else if (widget is ChoiceChip && widget.onSelected != null) {
      Function.apply(widget.onSelected!, [true]);
      return true;
    } else {
      LogUtil.i('Found widget but cannot trigger action');
      return false;
    }
  }
  
  /// 导航方法，通过 forward 参数决定是前进还是后退
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) {
    String action = '';
    int nextIndex = 0;
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
   
    int firstFocusIndex = focusNodes.indexOf(firstFocusNode);
    int lastFocusIndex = focusNodes.indexOf(lastFocusNode);
    if (forward) {
      if (currentIndex == lastFocusIndex) {
        nextIndex = firstFocusIndex;
        action = "Loop to first focus (index: $nextIndex)";
      } else {
        nextIndex = currentIndex + 1;
        action = "Switch to next focus (current index: $currentIndex -> new index: $nextIndex)";
      }
    } else {
      if (currentIndex == firstFocusIndex) {
        if (widget.frameType == "child") {
          final parentNavigation = _findParentNavigation();
          if (parentNavigation != null) {
            deactivateFocusManagement();
            parentNavigation.activateFocusManagement();
            LogUtil.i('Returned to parent page');
          } else {
            LogUtil.i('Failed to return to parent page');
          }
          return;
        } else {
          nextIndex = lastFocusIndex;
          action = "Loop to last focus (index: $nextIndex)";
        } 
      } else {
        nextIndex = currentIndex - 1;
        action = "Switch to previous focus (current index: $currentIndex -> new index: $nextIndex)";
      }
    }
    _requestFocus(nextIndex, groupIndex: groupIndex);
    LogUtil.i('Action: $action (Group: $groupIndex)');
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (_groupFocusCache.isEmpty) {
      LogUtil.i('No cached group info, cannot jump');
      return false;
    }

    try {
      List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
      int currentGroupIndex = groupIndex ?? groupIndices.first;
      
      if (!groupIndices.contains(currentGroupIndex)) {
        LogUtil.i('Current Group $currentGroupIndex not found');
        return false;
      }
      
      int totalGroups = groupIndices.length;
      int nextGroupIndex;

      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + totalGroups) % totalGroups];
      } else {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % totalGroups];
      }
      
      LogUtil.i('Jumping from Group $currentGroupIndex to Group $nextGroupIndex');

      final nextGroupFocus = _groupFocusCache[nextGroupIndex];

      if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) {
        FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode'];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nextFocusNode != null && nextFocusNode.context != null && nextFocusNode.canRequestFocus) {
            nextFocusNode.requestFocus();
            _currentFocus = nextFocusNode;
            LogUtil.i('Jumped to Group $nextGroupIndex focus node: ${nextFocusNode.debugLabel ?? 'unknown'}');
          } else {
            LogUtil.i('Target focus node not mounted or not requestable');
          }
        });
        return true;
      } else {
        LogUtil.i('No focus node info found for Group $nextGroupIndex');
      }
    } catch (e, stackTrace) {
      LogUtil.i('Unknown error during group jump: $e\nStack trace: $stackTrace');
    }
    
    return false;
  }
}

class Group extends StatelessWidget {
  final int groupIndex;
  final Widget? child;
  final List<Widget>? children;

  const Group({
    Key? key,
    required this.groupIndex,
    this.child,
    this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: FocusScopeNode(debugLabel: 'Group_$groupIndex'),
      child: child != null ? child! : (children != null ? Column(children: children!) : SizedBox.shrink()),
    );
  }
}

class FocusableItem extends StatefulWidget { 
  final FocusNode focusNode;
  final Widget child;

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
  }) : super(key: key);

  @override
  _FocusableItemState createState() => _FocusableItemState();
}

class _FocusableItemState extends State<FocusableItem> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      child: widget.child,
    );
  }
}
