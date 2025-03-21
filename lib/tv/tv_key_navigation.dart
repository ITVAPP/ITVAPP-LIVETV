import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/channel_drawer_page.dart';
import 'package:async/async.dart'; // 确保导入async包以使用Debouncer

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.3]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode>? focusNodes; // 修改处：focusNodes为可选参数
  final Map<int, Map<String, FocusNode>>? groupFocusCache; // 新增：可选的分组缓存参数
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
    this.focusNodes, // 修改处：移除required关键字
    this.groupFocusCache, // 新增参数
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

// 修改处：添加TvFocusTraversalPolicy并实现所有抽象方法
class TvFocusTraversalPolicy extends FocusTraversalPolicy {
  final List<FocusNode>? focusNodes; // 修改处：focusNodes改为可选
  final Map<int, Map<String, FocusNode>> groupFocusCache;

  TvFocusTraversalPolicy(this.focusNodes, this.groupFocusCache);

  @override
  FocusNode? findNextFocus(FocusNode currentNode, TraversalDirection direction) {
    if (focusNodes == null || focusNodes!.isEmpty) return null;
    int currentIndex = focusNodes!.indexOf(currentNode);
    int groupIndex = _getGroupIndex(currentNode);
    if (groupIndex == -1) return null;

    FocusNode first = groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode last = groupFocusCache[groupIndex]!['lastFocusNode']!;
    int firstIndex = focusNodes!.indexOf(first);
    int lastIndex = focusNodes!.indexOf(last);

    if (direction == TraversalDirection.down || direction == TraversalDirection.right) {
      return currentIndex == lastIndex ? first : focusNodes![currentIndex + 1];
    } else if (direction == TraversalDirection.up || direction == TraversalDirection.left) {
      return currentIndex == firstIndex ? last : focusNodes![currentIndex - 1];
    }
    return null;
  }

  @override
  FocusNode? findFirstFocusInDirection(FocusNode currentNode, TraversalDirection direction) {
    int groupIndex = _getGroupIndex(currentNode);
    if (groupIndex == -1) return null;
    return groupFocusCache[groupIndex]!['firstFocusNode'];
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    FocusNode? nextFocus = findNextFocus(currentNode, direction);
    if (nextFocus != null) {
      nextFocus.requestFocus();
      return true;
    }
    return false;
  }

  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) {
    if (focusNodes == null) return descendants;
    return descendants.toList()..sort((a, b) => focusNodes!.indexOf(a) - focusNodes!.indexOf(b));
  }

  int _getGroupIndex(FocusNode node) {
    if (focusNodes == null) return -1;
    for (var entry in groupFocusCache.entries) {
      if (focusNodes!.indexOf(node) >= focusNodes!.indexOf(entry.value['firstFocusNode']!) &&
          focusNodes!.indexOf(node) <= focusNodes!.indexOf(entry.value['lastFocusNode']!)) {
        return entry.key;
      }
    }
    return -1;
  }
}

class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus;
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};
  // 按页面名称存储的缓存
  static Map<String, Map<int, Map<String, FocusNode>>> _namedCaches = {};
  bool _isFocusManagementActive = false;
  int? _lastParentFocusIndex;
  DateTime? _lastKeyProcessedTime; // 新增：记录上一次按键处理的时间
  static const Duration _throttleDuration = Duration(milliseconds: 200); // 按键节流间隔的毫秒数
  final _debouncer = Debouncer(milliseconds: 200); // 使用Debouncer
  List<FocusNode>? _dynamicFocusNodes; // 修改处：存储动态获取的FocusNode

  // 判断是否为导航相关的按键（方向键、选择键和确认键）
  bool _isNavigationKey(LogicalKeyboardKey key) {
    return _isDirectionKey(key) || _isSelectKey(key);
  }

  // 修改处：动态收集FocusNode的方法
  List<FocusNode> _collectFocusNodesFromChild(Widget child) {
    List<FocusNode> focusNodes = [];
    void visitChild(Element element) {
      if (element.widget is FocusableItem) {
        final focusableItem = element.widget as FocusableItem;
        focusNodes.add(focusableItem.focusNode);
      }
      element.visitChildren(visitChild);
    }
    context.visitChildElements(visitChild);
    return focusNodes.where((node) => node.canRequestFocus).toList();
  }
  
  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (_isNavigationKey(event.logicalKey)) {
              final result = _handleKeyEvent(node, event);
              return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
            }
          }
          return KeyEventResult.ignored;
        },
        child: widget.child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);
    _isFocusManagementActive = !widget.isFrame || widget.frameType == "parent";
    if (_isFocusManagementActive) {
      initializeFocusLogic();
    }
    WidgetsBinding.instance.addObserver(this);
  }

  /// 激活焦点管理
  void activateFocusManagement({int? initialIndexOverride}) {
    setState(() {
      _isFocusManagementActive = true;
    });

    if (widget.cacheName != null) {
      String cacheName = 'groupCache-${widget.cacheName}';
      if (_namedCaches.containsKey(cacheName)) {
        _groupFocusCache = Map.from(_namedCaches[cacheName]!);
        LogUtil.i('使用 ${widget.cacheName} 的缓存');
        _requestFocus(_lastParentFocusIndex ?? 0);
      } else {
        LogUtil.i('未找到 ${widget.cacheName} 的缓存');
      }
    } else if (widget.frameType == "child") {
      initializeFocusLogic();
    }
    LogUtil.i('激活页面的焦点管理');
  }

  /// 停用焦点管理
  void deactivateFocusManagement() {
    setState(() {
      _isFocusManagementActive = false;
      if (widget.frameType == "parent" && _currentFocus != null) {
        _lastParentFocusIndex = (widget.focusNodes ?? _dynamicFocusNodes)?.indexOf(_currentFocus!) ?? -1;
        LogUtil.i('保存父页面焦点位置: $_lastParentFocusIndex');
      }
    });
    LogUtil.i('停用页面的焦点管理');
  }
  
  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }

  /// 释放组件使用的资源
  void releaseResources() {
    try {
      if (!mounted) return;

      if (_currentFocus != null && _currentFocus!.canRequestFocus) {
        if (widget.frameType == "parent") {
          _lastParentFocusIndex = (widget.focusNodes ?? _dynamicFocusNodes)?.indexOf(_currentFocus!) ?? -1;
        }
        if (_currentFocus!.hasFocus) {
          _currentFocus!.unfocus();
        }
        _currentFocus = null;
      }

      if (widget.frameType == "child" || !widget.isFrame) {
        _groupFocusCache.clear();
      }

      _isFocusManagementActive = !widget.isFrame;
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      _ensureCriticalResourceRelease();
    }
  }

  void _ensureCriticalResourceRelease() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  void updateNamedCache({required Map<int, Map<String, FocusNode>> cache, bool syncGroupFocusCache = true}) {
    if (widget.cacheName == null) {
      LogUtil.i('cacheName 未提供，无法更新 _namedCaches');
      return;
    }
    if (cache.isEmpty) {
      LogUtil.i('传入的缓存为空，跳过更新 _namedCaches');
      return;
    }
    final cacheName = 'groupCache-${widget.cacheName}';
    _namedCaches[cacheName] = Map.from(cache);
    if (syncGroupFocusCache) {
      _groupFocusCache = Map.from(cache);
    }
    LogUtil.i('更新 _namedCaches[$cacheName]: ${_namedCaches[cacheName]}');
  }
  
  /// 初始化焦点逻辑
  void initializeFocusLogic({int? initialIndexOverride}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 如果未传入focusNodes，动态收集
        if (widget.focusNodes == null) {
          _dynamicFocusNodes = _collectFocusNodesFromChild(widget.child);
          if (_dynamicFocusNodes!.isEmpty) {
            LogUtil.i('未传入focusNodes，且从child中未收集到有效焦点节点');
            return;
          }
          LogUtil.i('动态收集到 ${_dynamicFocusNodes!.length} 个焦点节点');
        } else if (widget.focusNodes!.isEmpty) {
          LogUtil.i('传入的focusNodes为空，无法设置焦点');
          return;
        } else {
          LogUtil.i('使用传入的focusNodes，共 ${widget.focusNodes!.length} 个节点');
        }

        // 检查是否传入了groupFocusCache
        if (widget.focusNodes != null && widget.groupFocusCache != null) {
          _groupFocusCache = Map.from(widget.groupFocusCache!);
          LogUtil.i('使用传入的groupFocusCache: ${_groupFocusCache.map((key, value) => MapEntry(key, "{first: ${widget.focusNodes!.indexOf(value['firstFocusNode']!)}, last: ${widget.focusNodes!.indexOf(value['lastFocusNode']!)}}"))}');
          updateNamedCache(cache: _groupFocusCache);
        } else if (widget.focusNodes != null) {
          if (widget.cacheName == "ChannelDrawerPage") {
            final channelDrawerState = context.findAncestorStateOfType<ChannelDrawerStateInterface>();
            if (channelDrawerState != null) {
              channelDrawerState.initializeData();
              channelDrawerState.updateFocusLogic(true);
              LogUtil.i('cacheName为ChannelDrawerPage，调用initializeData和updateFocusLogic');
            } else {
              LogUtil.i('未找到ChannelDrawerPage的状态，无法调用initializeData和updateFocusLogic');
            }
          } else {
            LogUtil.i('未传入groupFocusCache，执行分组查找逻辑');
            _cacheGroupFocusNodes();
          }
        }

        int initialIndex = initialIndexOverride ?? widget.initialIndex ?? 0;
        if (initialIndex != -1 && (widget.focusNodes?.isNotEmpty ?? _dynamicFocusNodes!.isNotEmpty)) {
          _requestFocus(initialIndex);
        }
      } catch (e) {
        LogUtil.i('初始焦点设置失败: $e');
      }
    });
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
        if (navigationWidget.frameType == "child") {
          childNavigation = (element as StatefulElement).state as TvKeyNavigationState;
          LogUtil.i('找到可用的子页面导航组件');
          return;
        }
      }
      element.visitChildren(visitChild);
    }
    context.visitChildElements(visitChild);
    if (childNavigation == null) {
      LogUtil.i('未找到可用的子页面导航组件');
    }
    return childNavigation;
  }

  /// 查找父页面导航状态
  TvKeyNavigationState? _findParentNavigation() {
    TvKeyNavigationState? parentNavigation;
    void findInContext(BuildContext context) {
      context.visitChildElements((element) {
        if (element.widget is TvKeyNavigation) {
          final navigationWidget = element.widget as TvKeyNavigation;
          if (navigationWidget.frameType == "parent") {
            parentNavigation = (element as StatefulElement).state as TvKeyNavigationState;
            LogUtil.i('找到可用的父页面导航组件');
            return;
          }
        }
        findInContext(element);
      });
    }
    final rootElement = context.findRootAncestorStateOfType<NavigatorState>()?.context;
    if (rootElement != null) {
      findInContext(rootElement);
    }
    if (parentNavigation == null) {
      LogUtil.i('未找到可用的父页面导航组件');
    }
    return parentNavigation;
  }
  
  /// 请求将焦点切换到指定索引的控件上
  void _requestFocus(int index, {int? groupIndex}) {
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
    if (focusNodes == null || focusNodes.isEmpty) {
      LogUtil.i('焦点节点列表为空或未提供，无法设置焦点');
      return;
    }

    try {
      if (index < 0 || index >= focusNodes.length) {
        return;
      }

      // 如果未传入focusNodes，则不使用groupFocusCache
      if (widget.focusNodes != null) {
        groupIndex ??= _getGroupIndex(focusNodes[index]);
        if (groupIndex == -1 || !_groupFocusCache.containsKey(groupIndex)) {
          FocusNode firstValidFocusNode = focusNodes.firstWhere(
            (node) => node.canRequestFocus,
            orElse: () => focusNodes[0]
          );
          firstValidFocusNode.requestFocus();
          _currentFocus = firstValidFocusNode;
          if (FocusManager.instance.primaryFocus != _currentFocus) {
            FocusManager.instance.primaryFocus?.unfocus();
            firstValidFocusNode.requestFocus();
          }
          LogUtil.i('无效的Group，设置到第一个可用焦点节点');
          return;
        }

        FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
        FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
        int firstFocusIndex = focusNodes.indexOf(firstFocusNode);
        int lastFocusIndex = focusNodes.indexOf(lastFocusNode);

        int newIndex = index;
        if (newIndex < firstFocusIndex) {
          newIndex = lastFocusIndex;
        } else if (newIndex > lastFocusIndex) {
          newIndex = firstFocusIndex;
        }
        FocusNode focusNode = focusNodes[newIndex];
        if (!focusNode.canRequestFocus) {
          LogUtil.i('焦点节点不可请求，索引: $newIndex');
          return;
        }
        if (!focusNode.hasFocus) {
          focusNode.requestFocus();
          _currentFocus = focusNode;
          if (FocusManager.instance.primaryFocus != _currentFocus) {
            LogUtil.i('焦点状态不一致，同步到FocusManager');
            FocusManager.instance.primaryFocus?.unfocus();
            focusNode.requestFocus();
          }
          LogUtil.i('切换焦点到索引: $newIndex, 当前Group: $groupIndex');
        }
      } else {
        // 未传入focusNodes，直接使用动态节点，不考虑groupIndex
        FocusNode focusNode = focusNodes[index];
        if (!focusNode.canRequestFocus) {
          LogUtil.i('动态焦点节点不可请求，索引: $index');
          return;
        }
        if (!focusNode.hasFocus) {
          focusNode.requestFocus();
          _currentFocus = focusNode;
          if (FocusManager.instance.primaryFocus != _currentFocus) {
            LogUtil.i('焦点状态不一致，同步到FocusManager');
            FocusManager.instance.primaryFocus?.unfocus();
            focusNode.requestFocus();
          }
          LogUtil.i('切换焦点到动态节点索引: $index');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.i('设置焦点时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
  }
  
  /// 缓存 Group 的焦点信息
  void _cacheGroupFocusNodes() {
    if (widget.groupFocusCache != null) {
      LogUtil.i('groupFocusCache已传入，不执行_cacheGroupFocusNodes');
      return;
    }
    if (widget.focusNodes == null || widget.focusNodes!.isEmpty) {
      LogUtil.i('focusNodes为空或未提供，无法缓存分组焦点信息');
      return;
    }
    _groupFocusCache.clear();
    final groups = _getAllGroups();
    LogUtil.i('缓存分组：找到的总组数: ${groups.length}');

    if (groups.isEmpty || groups.length == 1) {
      _cacheDefaultGroup();
    } else {
      _cacheMultipleGroups(groups);
    }
    
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}';
    _namedCaches[cacheName] = Map.from(_groupFocusCache);
    LogUtil.i('保存 $cacheName 的缓存');
  }
  
  void _cacheDefaultGroup() {
    final firstFocusNode = _findFirstFocusableNode(widget.focusNodes!);
    final lastFocusNode = _findLastFocusableNode(widget.focusNodes!);

    _groupFocusCache[0] = {
      'firstFocusNode': firstFocusNode,
      'lastFocusNode': lastFocusNode,
    };

    LogUtil.i('缓存了默认分组的焦点节点 - '
              '首个焦点节点: ${_formatFocusNodeDebugLabel(firstFocusNode)}, '
              '最后焦点节点: ${_formatFocusNodeDebugLabel(lastFocusNode)}');
  }

  void _cacheMultipleGroups(List<Group> groups) {
    for (var group in groups) {
      final groupWidgets = _getWidgetsInGroup(group);
      final groupFocusNodes = _getFocusNodesInGroup(groupWidgets);

      if (groupFocusNodes.isNotEmpty) {
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': groupFocusNodes.first,
          'lastFocusNode': groupFocusNodes.last,
        };

        LogUtil.i('分组 ${group.groupIndex}: '
                  '首个焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.first)}, '
                  '最后焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.last)}');
      } else {
        LogUtil.i('警告：分组 ${group.groupIndex} 没有可聚焦的节点');
      }
    }
  }
  
  FocusNode _findFirstFocusableNode(List<FocusNode> nodes) {
    return nodes.firstWhere(
      (node) => node.canRequestFocus,
      orElse: () => FocusNode(debugLabel: '空焦点节点')
    );
  }

  FocusNode _findLastFocusableNode(List<FocusNode> nodes) {
    return nodes.lastWhere(
      (node) => node.canRequestFocus,
      orElse: () => FocusNode(debugLabel: '空焦点节点')
    );
  }

  String _formatFocusNodeDebugLabel(FocusNode focusNode) {
    return focusNode.debugLabel ?? '索引: ${(widget.focusNodes ?? _dynamicFocusNodes)?.indexOf(focusNode) ?? -1}';
  }

  List<Widget> _getWidgetsInGroup(Group group) {
    return group.children ?? (group.child != null ? [group.child!] : []);
  }

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

  int _getGroupIndex(FocusNode focusNode) {
    try {
      final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;
      if (focusNodes == null || widget.focusNodes == null) return -1; // 未传入focusNodes时不使用分组
      for (var entry in _groupFocusCache.entries) {
        FocusNode firstFocusNode = entry.value['firstFocusNode']!;
        FocusNode lastFocusNode = entry.value['lastFocusNode']!;
        if (focusNodes.indexOf(focusNode) >= focusNodes.indexOf(firstFocusNode) &&
            focusNodes.indexOf(focusNode) <= focusNodes.indexOf(lastFocusNode)) {
          return entry.key;
        }
      }
      return -1;
    } catch (e, stackTrace) {
      _handleError('从缓存中获取分组索引失败', e, stackTrace);
      return -1;
    }
  }

  int _getTotalGroups() {
    return _groupFocusCache.length;
  }

  List<Group> _getAllGroups() {
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

  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    FocusNode? currentFocus = FocusManager.instance.primaryFocus ?? _currentFocus;
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;

    if (currentFocus == null) {
      LogUtil.i('当前无焦点，尝试设置初始焦点');
      _requestFocus(0);
      return KeyEventResult.handled;
    }

    int currentIndex = focusNodes?.indexOf(currentFocus) ?? -1;
    if (currentIndex == -1) {
      LogUtil.i('找不到当前焦点的索引');
      return KeyEventResult.ignored;
    }

    int groupIndex = _getGroupIndex(currentFocus);

    try {
      if (widget.isFrame) {
        if (widget.frameType == "parent") {
          if (key == LogicalKeyboardKey.arrowRight) {
            final childNavigation = _findChildNavigation();
            if (childNavigation != null) {
              deactivateFocusManagement();
              childNavigation.activateFocusManagement();
              LogUtil.i('切换到子页面');
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
      LogUtil.i('焦点切换错误: $e');
    }

    FocusNode? currentFocusNode = _currentFocus;
    if (currentFocusNode != null) {
      int newIndex = focusNodes?.indexOf(currentFocusNode) ?? -1;
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex);
      }
    }

    return KeyEventResult.handled;
  }
  
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {    
    if (event is KeyEvent && event is! KeyUpEvent) {
      LogicalKeyboardKey key = event.logicalKey;
      
      if (!_isFocusManagementActive) {
        LogUtil.i('焦点管理未激活，不处理按键事件');
        return KeyEventResult.ignored;
      }
      
      if (_isDirectionKey(key)) {
        _debouncer.debounce(() => _handleNavigation(key));
        return KeyEventResult.handled;
      }

      if (_isSelectKey(key)) {
        try {
          _triggerButtonAction();
        } catch (e) {
          LogUtil.i('执行按钮操作时发生错误: $e');
        }
        return KeyEventResult.handled;
      }

      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
      }
    }
    return KeyEventResult.ignored;
  }
  
  bool _isDirectionKey(LogicalKeyboardKey key) {
    return {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    }.contains(key);
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
  }
  
  void _triggerButtonAction() { 
    final focusNode = _currentFocus;
    if (focusNode != null && focusNode.context != null) {
      final BuildContext? context = focusNode.context;
      if (context == null) {
        LogUtil.i('焦点上下文为空，无法操作');
        return;
      }
      try {
        final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();
        if (focusableItem != null) {
          _triggerActionsInFocusableItem(context);
        } else {
          LogUtil.i('未找到FocusableItem包裹的控件');
        }
      } catch (e, stackTrace) {
        LogUtil.i('执行操作时发生错误: $e, 堆栈信息: $stackTrace');
      }
    }
  }

  void _triggerActionsInFocusableItem(BuildContext context) {
    _visitAllElements(context, (element) {
      final widget = element.widget;
      return _triggerWidgetAction(widget);
    });
  }

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
      LogUtil.i('找到控件，但无法触发操作');
      return false;
    }
  }
  
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) {
    String action = '';
    int nextIndex = 0;
    final focusNodes = widget.focusNodes ?? _dynamicFocusNodes;

    if (widget.focusNodes != null && groupIndex != -1) {
      FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
      FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
      int firstFocusIndex = focusNodes!.indexOf(firstFocusNode);
      int lastFocusIndex = focusNodes.indexOf(lastFocusNode);

      if (forward) {
        if (currentIndex == lastFocusIndex) {
          nextIndex = firstFocusIndex;
          action = "循环到第一个焦点 (索引: $nextIndex)";
        } else {
          nextIndex = currentIndex + 1;
          action = "切换到下一个焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
        }
      } else {
        if (currentIndex == firstFocusIndex) {
          if (widget.frameType == "child") {
            final parentNavigation = _findParentNavigation();
            if (parentNavigation != null) {
              deactivateFocusManagement();
              parentNavigation.activateFocusManagement();
              LogUtil.i('返回父页面');
            } else {
              LogUtil.i('尝试返回父页面但失败');
            }
            return;
          } else {
            nextIndex = lastFocusIndex;
            action = "循环到最后一个焦点 (索引: $nextIndex)";
          }
        } else {
          nextIndex = currentIndex - 1;
          action = "切换到前一个焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
        }
      }
    } else {
      // 未传入focusNodes，使用动态节点，不考虑分组
      if (forward) {
        if (currentIndex == focusNodes!.length - 1) {
          nextIndex = 0;
          action = "循环到第一个动态焦点 (索引: $nextIndex)";
        } else {
          nextIndex = currentIndex + 1;
          action = "切换到下一个动态焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
        }
      } else {
        if (currentIndex == 0) {
          if (widget.frameType == "child") {
            final parentNavigation = _findParentNavigation();
            if (parentNavigation != null) {
              deactivateFocusManagement();
              parentNavigation.activateFocusManagement();
              LogUtil.i('返回父页面');
            } else {
              LogUtil.i('尝试返回父页面但失败');
            }
            return;
          } else {
            nextIndex = focusNodes.length - 1;
            action = "循环到最后一个动态焦点 (索引: $nextIndex)";
          }
        } else {
          nextIndex = currentIndex - 1;
          action = "切换到前一个动态焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
        }
      }
    }
    _requestFocus(nextIndex, groupIndex: groupIndex);
    LogUtil.i('操作: $action (组: $groupIndex)');
  }

  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (widget.focusNodes == null || _groupFocusCache.isEmpty) {
      LogUtil.i('未传入focusNodes或没有缓存的分组信息，无法跳转');
      return false;
    }

    try {
      List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
      int currentGroupIndex = groupIndex ?? groupIndices.first;
      
      if (!groupIndices.contains(currentGroupIndex)) {
        LogUtil.i('当前Group $currentGroupIndex 无法找到');
        return false;
      }
      
      int totalGroups = groupIndices.length;
      int nextGroupIndex;
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + totalGroups) % totalGroups];
      } else {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % totalGroups];
      }
      
      LogUtil.i('从Group $currentGroupIndex 跳转到Group $nextGroupIndex');
      final nextGroupFocus = _groupFocusCache[nextGroupIndex];
      if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) {
        FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode'];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nextFocusNode != null && nextFocusNode.context != null && nextFocusNode.canRequestFocus) {
            nextFocusNode.requestFocus();
            _currentFocus = nextFocusNode;
            LogUtil.i('跳转到Group $nextGroupIndex 的焦点节点: ${nextFocusNode.debugLabel ?? '未知'}');
          } else {
            LogUtil.i('目标焦点节点未挂载或不可请求');
          }
        });
        return true;
      } else {
        LogUtil.i('未找到Group $nextGroupIndex 的焦点节点信息');
      }
    } catch (e, stackTrace) {
      LogUtil.i('跳转组时发生未知错误: $e\n堆栈信息: $stackTrace');
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
    return child != null ? child! : (children != null ? Column(children: children!) : SizedBox.shrink());
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
