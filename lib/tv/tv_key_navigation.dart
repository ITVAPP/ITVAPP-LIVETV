import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 工具类
class ColorUtils {
  static Color darkenColor(Color color, [double amount = 0.2]) {
    final hsl = HSLColor.fromColor(color);
    final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }
}

// 调试管理器
class DebugManager {
  final List<String> _messages = [];
  final int maxMessages;
  final bool enabled;
  final List<OverlayEntry> _overlays = [];
  Timer? _timer;
  final BuildContext context;

  DebugManager({
    this.maxMessages = 8,
    this.enabled = true,
    required this.context,
  });

  void log(String message) {
    if (!enabled) return;
    
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeAt(0);
    }
    
    _updateOverlay();
    _resetTimer();
  }

  void _updateOverlay() {
    _clearOverlays();
    if (_messages.isEmpty) return;

    final entry = OverlayEntry(
      builder: (context) => DebugOverlay(messages: _messages),
    );
    
    Overlay.of(context).insert(entry);
    _overlays.add(entry);
  }

  void _resetTimer() {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 5), (_) {
      if (_messages.isNotEmpty) {
        _messages.removeAt(0);
        _updateOverlay();
      }
    });
  }

  void _clearOverlays() {
    for (var entry in _overlays) {
      entry.remove();
    }
    _overlays.clear();
  }

  void dispose() {
    _timer?.cancel();
    _clearOverlays();
  }
}

class DebugOverlay extends StatelessWidget {
  final List<String> messages;

  const DebugOverlay({Key? key, required this.messages}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
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
            )).toList(),
          ),
        ),
      ),
    );
  }
}

// Widget操作策略
class WidgetActionStrategy {
  static final Map<Type, Function(Widget)> _actionHandlers = {
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
    final handler = _actionHandlers[widget.runtimeType];
    return handler?.call(widget) ?? false;
  }
}

// 导航状态管理
class NavigationState {
  FocusNode? _currentFocus;
  int? _currentGroupIndex;
  final Map<int, GroupInfo> _groupCache = {};
  
  FocusNode? get currentFocus => _currentFocus;
  int? get currentGroupIndex => _currentGroupIndex;
  Map<int, GroupInfo> get groupCache => _groupCache;

  void updateFocus(FocusNode? newFocus) {
    _currentFocus = newFocus;
  }
  
  void updateGroupIndex(int? newIndex) {
    _currentGroupIndex = newIndex;
  }

  void cacheGroup(int index, GroupInfo info) {
    _groupCache[index] = info;
  }
  
  void clearCache() {
    _groupCache.clear();
  }
}

class GroupInfo {
  final FocusNode firstNode;
  final FocusNode lastNode;
  final List<FocusNode> nodes;

  GroupInfo({
    required this.firstNode,
    required this.lastNode,
    required this.nodes,
  });
}

// 导航控制器
class NavigationController {
  final NavigationState _state;
  final List<FocusNode> _focusNodes;
  final DebugManager _debugManager;
  final bool _isFrame;
  final String? _frameType;
  final bool _isHorizontalGroup;
  final bool _isVerticalGroup;
  final Function(int)? _onSelect;

  NavigationController({
    required NavigationState state,
    required List<FocusNode> focusNodes,
    required DebugManager debugManager,
    required bool isFrame,
    required String? frameType,
    required bool isHorizontalGroup,
    required bool isVerticalGroup,
    required Function(int)? onSelect,
  }) : _state = state,
       _focusNodes = focusNodes,
       _debugManager = debugManager,
       _isFrame = isFrame,
       _frameType = frameType,
       _isHorizontalGroup = isHorizontalGroup,
       _isVerticalGroup = isVerticalGroup,
       _onSelect = onSelect;

  void requestFocus(int index) {
    if (!_isValidIndex(index)) {
      _debugManager.log('无效的焦点索引: $index');
      return;
    }

    final node = _focusNodes[index];
    if (!node.canRequestFocus) {
      _debugManager.log('焦点节点不可请求: $index');
      return;
    }

    node.requestFocus();
    _state.updateFocus(node);
    _state.updateGroupIndex(_getGroupIndex(node));
    _onSelect?.call(index);
    
    _debugManager.log('焦点已切换到: $index');
  }

  bool handleNavigation(LogicalKeyboardKey key) {
    final currentNode = _state.currentFocus;
    if (currentNode == null) {
      requestFocus(0);
      return true;
    }

    final currentIndex = _focusNodes.indexOf(currentNode);
    if (currentIndex == -1) return false;

    if (_isFrame) {
      return _handleFrameNavigation(key, currentIndex);
    }

    if (_isHorizontalGroup || _isVerticalGroup) {
      return _handleGroupNavigation(key, currentIndex);
    }

    return _handleDefaultNavigation(key, currentIndex);
  }

  bool _handleFrameNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (_frameType == "parent") {
      return _handleParentFrameNavigation(key, currentIndex);
    } else if (_frameType == "child") {
      return _handleChildFrameNavigation(key, currentIndex);
    }
    return false;
  }

  bool _handleParentFrameNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      return _moveFocus(currentIndex, forward: false);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      FocusManager.instance.primaryFocus?.unfocus();
      return true;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      return _moveFocus(currentIndex, forward: true);
    }
    return false;
  }

  bool _handleChildFrameNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      return _moveFocus(currentIndex, forward: false);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      return _moveFocus(currentIndex, forward: true);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      return _jumpBetweenGroups(key, currentIndex);
    }
    return false;
  }

  bool _handleGroupNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (_isHorizontalGroup) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        return _moveFocus(currentIndex, forward: false);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        return _moveFocus(currentIndex, forward: true);
      } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        return _jumpBetweenGroups(key, currentIndex);
      }
    } else if (_isVerticalGroup) {
      if (key == LogicalKeyboardKey.arrowUp) {
        return _moveFocus(currentIndex, forward: false);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        return _moveFocus(currentIndex, forward: true);
      } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
        return _jumpBetweenGroups(key, currentIndex);
      }
    }
    return false;
  }

  bool _handleDefaultNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
      return _moveFocus(currentIndex, forward: false);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
      return _moveFocus(currentIndex, forward: true);
    }
    return false;
  }

  bool _moveFocus(int currentIndex, {required bool forward}) {
    final groupInfo = _getCurrentGroupInfo();
    if (groupInfo == null) return false;

    int targetIndex;
    if (forward) {
      targetIndex = currentIndex == _focusNodes.indexOf(groupInfo.lastNode) 
          ? _focusNodes.indexOf(groupInfo.firstNode) 
          : currentIndex + 1;
    } else {
      targetIndex = currentIndex == _focusNodes.indexOf(groupInfo.firstNode)
          ? _focusNodes.indexOf(groupInfo.lastNode)
          : currentIndex - 1;
    }

    requestFocus(targetIndex);
    return true;
  }

  bool _jumpBetweenGroups(LogicalKeyboardKey key, int currentIndex) {
    final currentGroupIndex = _state.currentGroupIndex;
    if (currentGroupIndex == null) return false;

    final groups = _state.groupCache.keys.toList()..sort();
    final currentGroupPosition = groups.indexOf(currentGroupIndex);
    if (currentGroupPosition == -1) return false;

    final isMovingUp = key == LogicalKeyboardKey.arrowUp || 
                      key == LogicalKeyboardKey.arrowLeft;
    
    final targetGroupIndex = isMovingUp
        ? groups[(currentGroupPosition - 1 + groups.length) % groups.length]
        : groups[(currentGroupPosition + 1) % groups.length];

    final targetGroup = _state.groupCache[targetGroupIndex];
    if (targetGroup == null) return false;

    requestFocus(_focusNodes.indexOf(targetGroup.firstNode));
    return true;
  }

  GroupInfo? _getCurrentGroupInfo() {
    return _state.currentGroupIndex != null 
        ? _state.groupCache[_state.currentGroupIndex]
        : null;
  }

  int? _getGroupIndex(FocusNode node) {
    final nodeIndex = _focusNodes.indexOf(node);
    for (var entry in _state.groupCache.entries) {
      final groupNodes = entry.value.nodes;
      if (groupNodes.contains(node)) {
        return entry.key;
      }
    }
    return null;
  }

  bool _isValidIndex(int index) {
    return index >= 0 && index < _focusNodes.length;
  }
}

// 事件处理器
class EventHandler {
  static KeyEventResult handleKeyEvent({
    required KeyEvent event,
    required NavigationController controller,
    required Function(LogicalKeyboardKey)? onKeyPressed,
  }) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    
    final key = event.logicalKey;
    
    if (_isDirectionKey(key)) {
      final handled = controller.handleNavigation(key);
      return handled ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (_isSelectKey(key)) {
      // 处理选择事件
      return KeyEventResult.handled;
    }

    onKeyPressed?.call(key);
    return KeyEventResult.ignored;
  }

  static bool _isDirectionKey(LogicalKeyboardKey key) {
    return {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    }.contains(key);
  }

  static bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select || 
           key == LogicalKeyboardKey.enter;
  }
}

// Group管理器
class GroupManager {
  final NavigationState _state;
  final List<FocusNode> _focusNodes;
  final DebugManager _debugManager;

  GroupManager({
    required NavigationState state,
    required List<FocusNode> focusNodes,
    required DebugManager debugManager,
  }) : _state = state,
       _focusNodes = focusNodes,
       _debugManager = debugManager;

  void scanAndCacheGroups(BuildContext context) {
    _state.clearCache();
    final groups = _findAllGroups(context);
    
    if (groups.isEmpty) {
      _cacheDefaultGroup();
    } else {
      _cacheGroups(groups);
    }
  }

  List<Group> _findAllGroups(BuildContext context) {
    List<Group> groups = [];
    void visitor(Element element) {
      if (element.widget is Group) {
        groups.add(element.widget as Group);
      }
      element.visitChildren(visitor);
    }
    
    context.visitChildElements(visitor);
    return groups;
  }

  void _cacheDefaultGroup() {
    if (_focusNodes.isEmpty) return;

    _state.cacheGroup(0, GroupInfo(
      firstNode: _focusNodes.first,
      lastNode: _focusNodes.last,
      nodes: List.from(_focusNodes),
    ));
    
    _debugManager.log('已缓存默认分组');
  }

  void _cacheGroups(List<Group> groups) {
    for (var group in groups) {
      final nodes = _getGroupFocusNodes(group);
      if (nodes.isEmpty) continue;

      _state.cacheGroup(group.groupIndex, GroupInfo(
        firstNode: nodes.first,
        lastNode: nodes.last,
        nodes: nodes,
      ));
      
      _debugManager.log('已缓存分组 ${group.groupIndex}');
    }
  }

  List<FocusNode> _getGroupFocusNodes(Group group) {
    List<FocusNode> nodes = [];
    void visitor(Element element) {
      if (element.widget is FocusableItem) {
        final focusableItem = element.widget as FocusableItem;
        if (_focusNodes.contains(focusableItem.focusNode)) {
          nodes.add(focusableItem.focusNode);
        }
      }
      element.visitChildren(visitor);
    }

    if (group.child != null) {
      (group.child as Element).visitChildren(visitor);
    } else if (group.children != null) {
      for (var child in group.children!) {
        (child as Element).visitChildren(visitor);
      }
    }

    return nodes;
  }
}

// 主Widget
class TvKeyNavigation extends StatefulWidget {
  final Widget child;
  final List<FocusNode> focusNodes;
  final Function(int index)? onSelect;
  final Function(LogicalKeyboardKey key)? onKeyPressed;
  final bool isFrame;
  final String? frameType;
  final int? initialIndex;
  final bool isHorizontalGroup;
  final bool isVerticalGroup;
  final Function(TvKeyNavigationState state)? onStateCreated;

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.onSelect,
    this.onKeyPressed,
    this.isFrame = false,
    this.frameType,
    this.initialIndex,
    this.isHorizontalGroup = false,
    this.isVerticalGroup = false,
    this.onStateCreated,
  }) : super(key: key);

  @override
  TvKeyNavigationState createState() => TvKeyNavigationState();
}

class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  late final DebugManager _debugManager;
  late final NavigationState _navigationState;
  late final NavigationController _navigationController;
  late final GroupManager _groupManager;

  @override
  void initState() {
    super.initState();
    _initializeManagers();
    widget.onStateCreated?.call(this);
    _initializeFocus();
    WidgetsBinding.instance.addObserver(this);
  }

  void _initializeManagers() {
    _debugManager = DebugManager(context: context);
    _navigationState = NavigationState();
    _navigationController = NavigationController(
      state: _navigationState,
      focusNodes: widget.focusNodes,
      debugManager: _debugManager,
      isFrame: widget.isFrame,
      frameType: widget.frameType,
      isHorizontalGroup: widget.isHorizontalGroup,
      isVerticalGroup: widget.isVerticalGroup,
      onSelect: widget.onSelect,
    );
    _groupManager = GroupManager(
      state: _navigationState,
      focusNodes: widget.focusNodes,
      debugManager: _debugManager,
    );
  }

  void _initializeFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (widget.focusNodes.isEmpty) {
          _debugManager.log('焦点节点列表为空');
          return;
        }

        _groupManager.scanAndCacheGroups(context);
        
        final initialIndex = widget.initialIndex ?? 0;
        if (initialIndex >= 0) {
          _navigationController.requestFocus(initialIndex);
        }
      } catch (e, stackTrace) {
        _debugManager.log('初始化焦点失败: $e\n$stackTrace');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) => EventHandler.handleKeyEvent(
        event: event,
        controller: _navigationController,
        onKeyPressed: widget.onKeyPressed,
      ),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _debugManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// 辅助Widget
class Group extends StatelessWidget {
  final int groupIndex;
  final Widget? child;
  final List<Widget>? children;

  const Group({
    Key? key,
    required this.groupIndex,
    this.child,
    this.children,
  }) : assert(child != null || children != null),
       super(key: key);

  @override
  Widget build(BuildContext context) {
    if (child != null) return child!;
    return Column(
      children: children ?? [],
    );
  }
}

class FocusableItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: child,
    );
  }
}
