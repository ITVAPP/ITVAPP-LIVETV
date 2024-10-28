import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.2]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

// 添加调试信息管理器
class DebugMessageManager {
  final List<String> messages = [];  
  final int maxMessages;
  final bool showDebugOverlay;
  List<OverlayEntry> debugOverlays = [];
  Timer? timer;
  final BuildContext context;
  
  DebugMessageManager({
    this.maxMessages = 8,
    this.showDebugOverlay = true,
    required this.context,
  });

  void addMessage(String message) {
    if (!showDebugOverlay) return;
    
    messages.add(message);
    if (messages.length > maxMessages) {
      messages.removeAt(0);
    }
    
    _clearAllOverlays();
    _createOverlay();
    _resetTimer();
  }

  void _createOverlay() {
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 20.0,
        right: 20.0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxWidth: 300.0),
            padding: EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: messages.map((msg) => Text(
                msg,
                style: TextStyle(color: Colors.white, fontSize: 14),
                softWrap: true,
                overflow: TextOverflow.visible,
              )).toList(),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
    debugOverlays.add(overlayEntry);
  }

  void _resetTimer() {
    if (!showDebugOverlay) return;
    if (timer?.isActive ?? false) return;
    
    timer?.cancel();
    timer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (messages.isNotEmpty) {
        messages.removeAt(0);
        if (messages.isEmpty) {
          _clearAllOverlays();
          timer.cancel();
        } else {
          _updateOverlay();
        }
      }
    });
  }

  void _updateOverlay() {
    if (debugOverlays.isNotEmpty) {
      debugOverlays.first.markNeedsBuild();
    }
  }

  void _clearAllOverlays() {
    for (var entry in debugOverlays) {
      entry.remove();
    }
    debugOverlays.clear();
  }

  void dispose() {
    timer?.cancel();
    _clearAllOverlays();
  }
}

// 添加控件操作策略
class WidgetActionStrategy {
  static final Map<Type, Function(Widget)> actionHandlers = {
    SwitchListTile: (widget) => widget.onChanged?.call(!widget.value),
    ElevatedButton: (widget) => widget.onPressed?.call(),
    TextButton: (widget) => widget.onPressed?.call(),
    OutlinedButton: (widget) => widget.onPressed?.call(),
    IconButton: (widget) => widget.onPressed?.call(),
    FloatingActionButton: (widget) => widget.onPressed?.call(),
    ListTile: (widget) => widget.onTap?.call(),
    GestureDetector: (widget) => widget.onTap?.call(),
    PopupMenuButton: (widget) => widget.onSelected?.call(null),
    ChoiceChip: (widget) => widget.onSelected?.call(true),
  };

  static bool triggerAction(Widget widget) {
    final handler = actionHandlers[widget.runtimeType];
    if (handler != null) {
      handler(widget);
      return true;
    }
    return false;
  }
}

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final bool isFrame; // 是否启用框架模式，用于切换焦点
  final String? frameType; // 用于识别父页面或子页面
  final int? initialIndex; // 初始焦点的索引，默认为空，如果为空则使用自动聚焦
  final bool isHorizontalGroup; // 是否启用横向分组
  final bool isVerticalGroup; // 是否启用竖向分组
  final Function(TvKeyNavigationState state)? onStateCreated;

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.onSelect,
    this.onKeyPressed,
    this.isFrame = false,
    this.frameType, // 父页面或子页面
    this.initialIndex,
    this.isHorizontalGroup = false, // 默认不按横向分组
    this.isVerticalGroup = false,   // 默认不按竖向分组
    this.onStateCreated,
  }) : super(key: key);

  @override
  TvKeyNavigationState createState() => TvKeyNavigationState();
}

class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  late final DebugMessageManager debugManager;
  FocusNode? _currentFocus;
  // 用于缓存每个Group的焦点信息（首尾节点）
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  @override
  void initState() {
    super.initState();
    debugManager = DebugMessageManager(context: context);
    widget.onStateCreated?.call(this);
    initializeFocusLogic();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    debugManager.dispose();
    releaseResources();
    super.dispose();
  }

/// 初始化焦点逻辑
  void initializeFocusLogic({int? initialIndexOverride}) { 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 判断 focusNodes 是否有效
        if (widget.focusNodes.isEmpty) {
          debugManager.addMessage('focusNodes 为空，无法设置焦点');
          return;
        } else {
          debugManager.addMessage('正在初始化焦点逻辑，共 ${widget.focusNodes.length} 个节点');
        }
      
        _cacheGroupFocusNodes();

        int initialIndex = initialIndexOverride ?? widget.initialIndex ?? 0;

        if (initialIndex != -1 && widget.focusNodes.isNotEmpty) {
          _requestFocus(initialIndex);
          debugManager.addMessage('初始焦点设置完成');
        } else {
          debugManager.addMessage('跳过初始焦点设置');
        }
      } catch (e) {
        debugManager.addMessage('初始焦点设置失败: $e');
      }
    });
  }

  /// 释放资源
  void releaseResources() {
    debugManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    debugManager.addMessage('$message: $error\n位置: $stackTrace');
  }

  /// 请求将焦点切换到指定索引的控件上
  void _requestFocus(int index, {int? groupIndex}) {
    if (widget.focusNodes.isEmpty) {
      debugManager.addMessage('焦点节点列表为空，无法设置焦点');
      return;
    }

    try {
      if (index < 0 || index >= widget.focusNodes.length) {
        debugManager.addMessage('索引 $index 超出范围，无法访问 focusNodes。总节点数: ${widget.focusNodes.length}');
        return;
      }

      groupIndex ??= _getGroupIndex(widget.focusNodes[index]);
      if (groupIndex == -1 || !_groupFocusCache.containsKey(groupIndex)) {
        FocusNode firstValidFocusNode = widget.focusNodes.firstWhere(
          (node) => node.canRequestFocus, 
          orElse: () => widget.focusNodes[0]
        );

        firstValidFocusNode.requestFocus();
        _currentFocus = firstValidFocusNode;
        debugManager.addMessage('无效的 Group，设置到第一个可用焦点节点');
        return;
      }

      FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
      FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;

      int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode);
      int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode);

      if (index < firstFocusIndex) {
        index = lastFocusIndex;
      } else if (index > lastFocusIndex) {
        index = firstFocusIndex;
      }

      FocusNode focusNode = widget.focusNodes[index];

      if (!focusNode.canRequestFocus) {
        debugManager.addMessage('焦点节点不可请求，索引: $index');
        return;
      }

      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        _currentFocus = focusNode;
        debugManager.addMessage('切换焦点到索引: $index, 当前Group: $groupIndex');
      }
    } catch (e, stackTrace) {
      debugManager.addMessage('设置焦点时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
  }
  
  /// 缓存 Group 的焦点信息
  void _cacheGroupFocusNodes() {
    _groupFocusCache.clear();
    debugManager.addMessage('开始缓存分组焦点信息');

    final groups = _getAllGroups();
    debugManager.addMessage('找到的总组数: ${groups.length}');

    if (groups.isEmpty || groups.length == 1) {
      _cacheDefaultGroup();
    } else {
      _cacheMultipleGroups(groups);
    }

    debugManager.addMessage('缓存完成，共缓存了 ${_groupFocusCache.length} 个分组的焦点节点');
  }

  void _cacheDefaultGroup() {
    final firstFocusNode = _findFirstFocusableNode(widget.focusNodes);
    final lastFocusNode = _findLastFocusableNode(widget.focusNodes);

    _groupFocusCache[0] = {
      'firstFocusNode': firstFocusNode,
      'lastFocusNode': lastFocusNode,
    };

    debugManager.addMessage(
      '缓存了默认分组的焦点节点 - '
      '首个焦点节点: ${_formatFocusNodeDebugLabel(firstFocusNode)}, '
      '最后焦点节点: ${_formatFocusNodeDebugLabel(lastFocusNode)}'
    );
  }

  void _cacheMultipleGroups(List<Group> groups) {
    for (var group in groups) {
      final groupWidgets = _getWidgetsInGroup(group);
      final groupFocusNodes = _getFocusNodesInGroup(groupWidgets);

      debugManager.addMessage(
        '分组 ${group.groupIndex} 的组件数: ${groupWidgets.length}, '
        '焦点节点数: ${groupFocusNodes.length}'
      );

      if (groupFocusNodes.isNotEmpty) {
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': groupFocusNodes.first,
          'lastFocusNode': groupFocusNodes.last,
        };

        debugManager.addMessage(
          '分组 ${group.groupIndex}: '
          '首个焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.first)}, '
          '最后焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.last)}'
        );
      } else {
        debugManager.addMessage('警告：分组 ${group.groupIndex} 没有可聚焦的节点');
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
    return focusNode.debugLabel ?? '索引: ${widget.focusNodes.indexOf(focusNode)}';
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
      for (var entry in _groupFocusCache.entries) {
        FocusNode firstFocusNode = entry.value['firstFocusNode']!;
        FocusNode lastFocusNode = entry.value['lastFocusNode']!;

        if (widget.focusNodes.indexOf(focusNode) >= widget.focusNodes.indexOf(firstFocusNode) &&
            widget.focusNodes.indexOf(focusNode) <= widget.focusNodes.indexOf(lastFocusNode)) {
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

    debugManager.addMessage('找到的总组数: ${groups.length}');
    return groups;
  }

  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {    
    FocusNode? currentFocus = _currentFocus;

    if (currentFocus == null) {
      debugManager.addMessage('当前无焦点，尝试设置初始焦点');
      _requestFocus(0);
      return KeyEventResult.handled;
    }

    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      debugManager.addMessage('找不到当前焦点的索引');
      return KeyEventResult.ignored; 
    }

    int groupIndex = _getGroupIndex(currentFocus);

    debugManager.addMessage('当前索引=$currentIndex, 当前Group=$groupIndex, 总节点数=${widget.focusNodes.length}');

    try {
      if (widget.isFrame) {
        if (widget.frameType == "parent") {
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            FocusManager.instance.primaryFocus?.unfocus();
            FocusScope.of(context).nextFocus();
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
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);
          }
        }
      }
    } catch (e) {
      debugManager.addMessage('焦点切换错误: $e');
    }

    FocusNode? currentFocusNode = _currentFocus;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex);
      }
    }

    return KeyEventResult.handled;
  }

KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {    
    if (event is KeyEvent && event is! KeyUpEvent) {
      LogicalKeyboardKey key = event.logicalKey;

      if (_isDirectionKey(key)) {
        return _handleNavigation(key);
      }

      if (_isSelectKey(key)) {
        _triggerButtonAction();
        debugManager.addMessage('选择键操作: ${key.debugName}');
        return KeyEventResult.handled;
      }

      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
        debugManager.addMessage('自定义按键回调: ${key.debugName}');
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
        debugManager.addMessage('焦点上下文为空，无法操作');
        return;
      }

      try {
        final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();

        if (focusableItem != null) {
          _triggerActionsInFocusableItem(context);
        } else {
          debugManager.addMessage('未找到 FocusableItem 包裹的控件');
        }
      } catch (e, stackTrace) {
        debugManager.addMessage('执行操作时发生错误: $e, 堆栈信息: $stackTrace');
      }
    } else {
      debugManager.addMessage('当前无有效的焦点上下文');
    }
  }

  void _triggerActionsInFocusableItem(BuildContext context) {
    _visitAllElements(context, (element) {
      final widget = element.widget;
      return WidgetActionStrategy.triggerAction(widget);
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
  
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) {
    String action;
    int nextIndex;

    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
    
    int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode);
    int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode);

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
          FocusScope.of(context).requestFocus();
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

    _requestFocus(nextIndex, groupIndex: groupIndex);
    debugManager.addMessage('操作: $action (组: $groupIndex)');
  }

  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    debugManager.addMessage('跳转到其他组，当前索引：$currentIndex，当前组：$groupIndex');
    
    if (_groupFocusCache.isEmpty) {
      debugManager.addMessage('没有缓存的分组信息，无法跳转');
      return false;
    }

    try {
      List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
      int currentGroupIndex = groupIndex ?? groupIndices.first;
      
      if (!groupIndices.contains(currentGroupIndex)) {
        debugManager.addMessage('当前 Group $currentGroupIndex 无法找到');
        return false;
      }
      
      int totalGroups = groupIndices.length;
      int nextGroupIndex;

      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + totalGroups) % totalGroups];
      } else {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % totalGroups];
      }
      
      debugManager.addMessage('从 Group $currentGroupIndex 跳转到 Group $nextGroupIndex');

      final nextGroupFocus = _groupFocusCache[nextGroupIndex];

      if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) {
        FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode'];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nextFocusNode != null && nextFocusNode.context != null && nextFocusNode.canRequestFocus) {
            nextFocusNode.requestFocus();
            _currentFocus = nextFocusNode;
            debugManager.addMessage('跳转到 Group $nextGroupIndex 的焦点节点: ${nextFocusNode.debugLabel ?? '未知'}');
          } else {
            debugManager.addMessage('目标焦点节点未挂载或不可请求');
          }
        });
        return true;
      } else {
        debugManager.addMessage('未找到 Group $nextGroupIndex 的焦点节点信息');
      }
    } catch (RangeError) {
      debugManager.addMessage('焦点跳转时发生范围错误');
    } catch (e, stackTrace) {
      debugManager.addMessage('跳转组时发生未知错误: $e\n堆栈信息: $stackTrace');
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
  final int? groupIndex;

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
    this.groupIndex,
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
