import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.3]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

// 添加调试信息管理的 mixin
mixin DebugOverlayManager {
  final List<OverlayEntry> _debugOverlays = [];
  final List<String> _debugMessages = [];
  Timer? _timer;
  final int _messageDisplayDuration = 3;
  final bool _showDebugOverlay = true;

  void manageDebugOverlay(BuildContext context, {String? message}) {
    if (!_showDebugOverlay) return;

    if (message != null) {
      _debugMessages.add(message);
      if (_debugMessages.length > 6) {
        _debugMessages.removeAt(0);
      }
      _clearAllOverlays();
      
      final overlayEntry = _createDebugOverlay(context);
      Overlay.of(context).insert(overlayEntry);
      _debugOverlays.add(overlayEntry);
      _resetTimer();
    } else {
      _clearAllOverlays();
      _cancelTimer();
    }
  }

  OverlayEntry _createDebugOverlay(BuildContext context) {
    return OverlayEntry(
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
              children: _debugMessages.map((msg) => Text(
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
  }

  void _resetTimer() {
    if (!_showDebugOverlay || (_timer?.isActive ?? false)) return;
    
    _cancelTimer();
    _timer = Timer.periodic(Duration(seconds: _messageDisplayDuration), (timer) {
      if (_debugMessages.isNotEmpty) {
        _debugMessages.removeAt(0);
        if (_debugMessages.isEmpty) {
          _clearAllOverlays();
          _cancelTimer();
        } else {
          _updateOverlayMessages();
        }
      }
    });
  }

  void _updateOverlayMessages() {
    if (_debugOverlays.isNotEmpty) {
      _debugOverlays.first.markNeedsBuild();
    }
  }

  void _clearAllOverlays() {
    for (var entry in _debugOverlays) {
      entry.remove();
    }
    _debugOverlays.clear();
  }

  void _cancelTimer() {
    if (_timer?.isActive ?? false) {
      _timer?.cancel();
    }
    _timer = null;
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
  final String? cacheName; // 新增参数: 用于自定义缓存名称

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
    this.cacheName, // 新增参数
  }) : super(key: key);

  @override
  TvKeyNavigationState createState() => TvKeyNavigationState();
}

class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver, DebugOverlayManager {
  FocusNode? _currentFocus;
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};
  // 按页面名称存储的缓存
  static Map<String, Map<int, Map<String, FocusNode>>> _namedCaches = {};
  bool _isFocusManagementActive = false;
  int? _lastParentFocusIndex;
  
  // 判断是否为导航相关的按键（方向键、选择键和确认键）
  bool _isNavigationKey(LogicalKeyboardKey key) {
    return _isDirectionKey(key) || _isSelectKey(key);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
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

    // 如果传入了 cacheName,直接使用缓存
    if (widget.cacheName != null) {
      String cacheName = 'groupCache-${widget.cacheName}';
      if (_namedCaches.containsKey(cacheName)) {
        _groupFocusCache = Map.from(_namedCaches[cacheName]!);
        manageDebugOverlay(context, message: '使用 ${widget.cacheName} 的缓存');
        
        // 恢复焦点位置
        _requestFocus(_lastParentFocusIndex ?? 0);
      } else {
        manageDebugOverlay(context, message: '未找到 ${widget.cacheName} 的缓存');
      }
    }
    // 如果是子页面,直接初始化焦点逻辑
    else if (widget.frameType == "child") {
      initializeFocusLogic();
    }
    manageDebugOverlay(context, message: '激活页面的焦点管理');
  }

  /// 停用焦点管理
  void deactivateFocusManagement() {
      setState(() {
        _isFocusManagementActive = false;
        if (widget.frameType == "parent" && _currentFocus != null) {
          _lastParentFocusIndex = widget.focusNodes.indexOf(_currentFocus!);
          manageDebugOverlay(context, message: '保存父页面焦点位置: $_lastParentFocusIndex');
        }
      });
      manageDebugOverlay(context, message: '停用页面的焦点管理');
  }
  
@override
  void dispose() {
    releaseResources();
    super.dispose();
  }

  /// 初始化焦点逻辑
  void initializeFocusLogic({int? initialIndexOverride}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 判断 focusNodes 是否有效
        if (widget.focusNodes.isEmpty) {
          manageDebugOverlay(context, message: 'focusNodes 为空，无法设置焦点');
          return; 
        } else {
          manageDebugOverlay(context, message: '正在初始化焦点逻辑，共 ${widget.focusNodes.length} 个节点');
        }
      
        _cacheGroupFocusNodes(); // 缓存 Group 的焦点信息

        // 使用 initialIndexOverride 参数，如果为空则使用 widget.initialIndex 或默认 0
        int initialIndex = initialIndexOverride ?? widget.initialIndex ?? 0;

        // initialIndex 为 -1，跳过设置初始焦点的逻辑
        if (initialIndex != -1 && widget.focusNodes.isNotEmpty) {
          _requestFocus(initialIndex); // 设置初始焦点
        } 
      } catch (e) {
        manageDebugOverlay(context, message: '初始焦点设置失败: $e');
      }
    });
  }

/// 释放组件使用的资源
void releaseResources() {
  try {
    // 1. 首先检查 context 是否有效
    if (!mounted) {
      return;
    }

    // 2. 清理定时器资源（优先级最高，避免后续可能的回调）
    _cancelTimer();

    // 3. 清理焦点相关资源（在清理UI之前处理状态）
    if (_currentFocus != null && _currentFocus!.canRequestFocus) {
      if (widget.frameType == "parent") {
        // 保存父页面最后的焦点位置
        _lastParentFocusIndex = widget.focusNodes.indexOf(_currentFocus!);
      }
      // 安全地取消焦点
      if (_currentFocus!.hasFocus) {
        _currentFocus!.unfocus();
      }
      _currentFocus = null;
    }

    // 4. 清理调试相关资源（从内到外清理UI）
    _debugMessages.clear();
    // 安全地移除所有调试覆盖层
    if (_debugOverlays.isNotEmpty) {
      for (var entry in List<OverlayEntry>.from(_debugOverlays)) {
        if (entry.mounted) {
          entry.remove();
        }
      }
      _debugOverlays.clear();
    }
    
    // 最后清除调试覆盖层状态
    if (mounted) {
      manageDebugOverlay(context);
    }

    // 5. 清理缓存资源
    if (widget.frameType == "child" || !widget.isFrame) {
      // 清理分组焦点缓存
      _groupFocusCache.clear();
    }

    // 6. 重置组件状态（在最后阶段重置状态变量）
    _isFocusManagementActive = !widget.isFrame;

    // 7. 移除生命周期观察者（最后执行，因为可能还需要生命周期回调）
    WidgetsBinding.instance.removeObserver(this);

  } catch (e, _) {
    // 确保关键资源释放
    _ensureCriticalResourceRelease();
  }
}

/// 确保关键资源释放的辅助方法
void _ensureCriticalResourceRelease() {
  try {
    // 1. 确保定时器被取消
    _cancelTimer();
    
    // 2. 确保移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    
    // 3. 确保清理所有覆盖层
    if (_debugOverlays.isNotEmpty) {
      for (var entry in List<OverlayEntry>.from(_debugOverlays)) {
        if (entry.mounted) {
          entry.remove();
        }
      }
      _debugOverlays.clear();
    }
  } catch (_) {
    // 忽略最终清理时的错误
  }
}

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    manageDebugOverlay(context, message: '$message: $error\n位置: $stackTrace');
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
          manageDebugOverlay(context, message: '找到可用的子页面导航组件');
          return; // 停止递归
        }
      }
      // 继续递归地访问子元素
      element.visitChildren(visitChild);
    }
    // 开始从当前 context 访问子元素
    context.visitChildElements(visitChild);
    if (childNavigation == null) {
      manageDebugOverlay(context, message: '未找到可用的子页面导航组件');
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
            manageDebugOverlay(context, message: '找到可用的父页面导航组件');
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
      manageDebugOverlay(context, message: '未找到可用的父页面导航组件');
    }

    return parentNavigation;
  }
  
/// 请求将焦点切换到指定索引的控件上
  void _requestFocus(int index, {int? groupIndex}) {
    if (widget.focusNodes.isEmpty) {
      manageDebugOverlay(context, message: '焦点节点列表为空，无法设置焦点');
      return;
    }

    try {
      // 检查 index 是否在合法范围内
      if (index < 0 || index >= widget.focusNodes.length) {
        return;
      }

      // 从缓存获取 groupIndex
      groupIndex ??= _getGroupIndex(widget.focusNodes[index]);
      if (groupIndex == -1 || !_groupFocusCache.containsKey(groupIndex)) {
        // 无效的 groupIndex，直接设置为第一个可请求焦点的节点
        FocusNode firstValidFocusNode = widget.focusNodes.firstWhere(
          (node) => node.canRequestFocus, 
          orElse: () => widget.focusNodes[0]
        );

        // 请求第一个有效焦点
        firstValidFocusNode.requestFocus();
        _currentFocus = firstValidFocusNode;
        manageDebugOverlay(context, message: '无效的 Group，设置到第一个可用焦点节点');
        return;
      }

      // 获取当前组的焦点范围
      FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
      FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;

      int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode);
      int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode);

      // 确保 index 在当前组的范围内
      if (index < firstFocusIndex) {
        index = lastFocusIndex; // 循环到最后一个焦点
      } else if (index > lastFocusIndex) {
        index = firstFocusIndex; // 循环到第一个焦点
      }

      FocusNode focusNode = widget.focusNodes[index];

      // 检查焦点是否可请求
      if (!focusNode.canRequestFocus) {
        manageDebugOverlay(context, message: '焦点节点不可请求，索引: $index');
        return;
      }

      // 请求焦点
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();  // 设置焦点到指定的节点
        _currentFocus = focusNode;
        manageDebugOverlay(context, message: '切换焦点到索引: $index, 当前Group: $groupIndex');
      }
    } catch (e, stackTrace) {
      manageDebugOverlay(context, message: '设置焦点时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
  }
  
  /// 缓存 Group 的焦点信息
  void _cacheGroupFocusNodes() {
    _groupFocusCache.clear();  // 清空缓存
    // 获取所有的分组
    final groups = _getAllGroups();
    manageDebugOverlay(context, message: '缓存分组：找到的总组数: ${groups.length}');

    // 如果没有分组或只有一个分组，处理为默认分组逻辑
    if (groups.isEmpty || groups.length == 1) {
      _cacheDefaultGroup();
    } else {
      _cacheMultipleGroups(groups);
    }
    
    // 修改使用 widget.cacheName
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}';
    _namedCaches[cacheName] = Map.from(_groupFocusCache);
    manageDebugOverlay(context, message: '保存 $cacheName 的缓存');
  }
  
  // 缓存默认分组（无分组或单一分组）的焦点节点
  void _cacheDefaultGroup() {
    final firstFocusNode = _findFirstFocusableNode(widget.focusNodes);
    final lastFocusNode = _findLastFocusableNode(widget.focusNodes);

    _groupFocusCache[0] = {
      'firstFocusNode': firstFocusNode,
      'lastFocusNode': lastFocusNode,
    };

    manageDebugOverlay(
      context,
      message: '缓存了默认分组的焦点节点 - '
               '首个焦点节点: ${_formatFocusNodeDebugLabel(firstFocusNode)}, '
               '最后焦点节点: ${_formatFocusNodeDebugLabel(lastFocusNode)}'
    );
  }

  // 遍历分组缓存它们的焦点节点
  void _cacheMultipleGroups(List<Group> groups) {
    for (var group in groups) {
      final groupWidgets = _getWidgetsInGroup(group);
      final groupFocusNodes = _getFocusNodesInGroup(groupWidgets);

      if (groupFocusNodes.isNotEmpty) {
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': groupFocusNodes.first,
          'lastFocusNode': groupFocusNodes.last,
        };

        manageDebugOverlay(
          context,
          message: '分组 ${group.groupIndex}: '
                   '首个焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.first)}, '
                   '最后焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.last)}'
        );
      } else {
        manageDebugOverlay(
          context,
          message: '警告：分组 ${group.groupIndex} 没有可聚焦的节点'
        );
      }
    }
  }
  
// 查找第一个可聚焦的节点
  FocusNode _findFirstFocusableNode(List<FocusNode> nodes) {
    return nodes.firstWhere(
      (node) => node.canRequestFocus,
      orElse: () => FocusNode(debugLabel: '空焦点节点') // 添加 debugLabel，便于调试
    );
  }

  // 查找最后一个可聚焦的节点
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

  /// 获取当前焦点所属的 groupIndex
  int _getGroupIndex(FocusNode focusNode) {
    try {
      for (var entry in _groupFocusCache.entries) {
        FocusNode firstFocusNode = entry.value['firstFocusNode']!;
        FocusNode lastFocusNode = entry.value['lastFocusNode']!;

        // 如果焦点节点在当前分组的范围内（首尾节点之间）
        if (widget.focusNodes.indexOf(focusNode) >= widget.focusNodes.indexOf(firstFocusNode) &&
            widget.focusNodes.indexOf(focusNode) <= widget.focusNodes.indexOf(lastFocusNode)) {
          return entry.key;  // 返回对应的 groupIndex
        }
      }
      return -1; // 如果没有找到匹配的分组，返回 -1
    } catch (e, stackTrace) {
      _handleError('从缓存中获取分组索引失败', e, stackTrace);
      return -1;
    }
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return _groupFocusCache.length; 
  }

  /// 获取所有的 Group
  List<Group> _getAllGroups() {
    List<Group> groups = [];
    // 递归查找所有 Group 的方法
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
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    FocusNode? currentFocus = _currentFocus;

    if (currentFocus == null) {
      manageDebugOverlay(context, message: '当前无焦点，尝试设置初始焦点');
      _requestFocus(0); // 设置焦点为第一个控件
      return KeyEventResult.handled;
    }

    // 获取当前焦点的索引 (currentIndex)
    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      manageDebugOverlay(context, message: '找不到当前焦点的索引');
      return KeyEventResult.ignored; 
    }

    // 获取当前焦点的 groupIndex，如果找不到，默认为 -1
    int groupIndex = _getGroupIndex(currentFocus);  // 通过 context 获取 groupIndex
    
    try {
      // 判断是否启用了框架模式 (isFrame)
      if (widget.isFrame) {  // 如果是框架模式
        if (widget.frameType == "parent") {
          // 父页面导航逻辑
          if (key == LogicalKeyboardKey.arrowRight) {
            // 按下右键时，尝试切换到子页面
            final childNavigation = _findChildNavigation();
            if (childNavigation != null) {
              deactivateFocusManagement(); // 停用父页面焦点
              childNavigation.activateFocusManagement(); // 激活子页面焦点
              manageDebugOverlay(context, message: '切换到子页面');
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {   // 左上键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);
          } else if (key == LogicalKeyboardKey.arrowDown) {    // 下键
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);
          }
        } else if (widget.frameType == "child") {  // 子页面
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);  // 后退或回父页面
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);  // 跳转到其它 Group
          }
        }
      } else {  // 如果不是框架模式
        // 判断是否启用了横向分组
        if (widget.isHorizontalGroup) {
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);  // 跳转到其它 Group
          }
        } else if (widget.isVerticalGroup) {   // 判断是否启用了竖向分组
          if (key == LogicalKeyboardKey.arrowUp) {  // 上键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {  // 左右键
            _jumpToOtherGroup(key, currentIndex, groupIndex);  // 跳转到其它 Group
          }
        } else {  // 没有启用分组的默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {  // 左上键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {  // 右下键
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);  // 前进或循环焦点
          }
        }
      }
    } catch (e) {
      manageDebugOverlay(context, message: '焦点切换错误: $e');
    }

    // 调用选择回调
    FocusNode? currentFocusNode = _currentFocus;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex); // 只有在新焦点与当前焦点不同的时候调用回调
      }
    }

    return KeyEventResult.handled;
  }
  
  /// 处理键盘事件，包括方向键和选择键。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {    
    if (event is KeyEvent && event is! KeyUpEvent) {
      LogicalKeyboardKey key = event.logicalKey;
      
      // 如果焦点管理未激活，则不处理按键事件
      if (!_isFocusManagementActive) {
        manageDebugOverlay(context, message: '焦点管理未激活，不处理按键事件');
        return KeyEventResult.ignored;
      }
      
      // 判断是否为方向键
      if (_isDirectionKey(key)) {
        return _handleNavigation(key);
      }

      // 判断是否为选择键
      if (_isSelectKey(key)) {
        try {
          _triggerButtonAction(); // 调用按钮操作
        } catch (e) {
          manageDebugOverlay(context, message: '执行按钮操作时发生错误: $e');
        }
        return KeyEventResult.handled;
      }

      // 自定义的按键处理回调
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
    final focusNode = _currentFocus;  // 获取当前焦点
    if (focusNode != null && focusNode.context != null) {
      final BuildContext? context = focusNode.context;

      // 如果上下文不可用，显示调试消息并返回
      if (context == null) {
        manageDebugOverlay(this.context, message: '焦点上下文为空，无法操作');
        return;
      }

      try {
        // 查找最近的 FocusableItem 节点
        final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();

        if (focusableItem != null) {
          // 使用当前的 context 而不是 focusableItem.context
          _triggerActionsInFocusableItem(context); // 将 context 传递下去
        } else {
          manageDebugOverlay(this.context, message: '未找到 FocusableItem 包裹的控件');
        }
      } catch (e, stackTrace) {
        manageDebugOverlay(this.context, message: '执行操作时发生错误: $e, 堆栈信息: $stackTrace');
      }
    }
  }

  // 在 FocusableItem 节点下查找并触发第一个交互控件的操作
  void _triggerActionsInFocusableItem(BuildContext context) {
    _visitAllElements(context, (element) {
      final widget = element.widget;

      // 识别并触发交互控件的操作，找到并触发后停止递归
      return _triggerWidgetAction(widget);  // 如果成功触发操作，返回 true，停止遍历
    });
  }

  // 遍历函数，遇到交互控件后终止遍历
  bool _visitAllElements(BuildContext context, bool Function(Element) visitor) {
    bool stop = false;  // 用于控制是否继续递归
    context.visitChildElements((element) {
      if (stop) return; // 如果已经找到并触发了操作，停止递归
      stop = visitor(element);  // 如果触发了操作，stop 会变为 true
      if (!stop) {
        stop = _visitAllElements(element, visitor);  // 递归遍历子元素
      }
    });
    return stop;  // 返回是否已停止查找
  }

  // 执行目标控件的操作函数，返回 true 表示已触发操作并停止查找
  bool _triggerWidgetAction(Widget widget) {
    // 定义高优先级组件列表
    final highPriorityWidgets = [
      ElevatedButton,
      TextButton,
      OutlinedButton,
      IconButton,
      FloatingActionButton,
      GestureDetector,
      ListTile,
    ];

    // 定义低优先级（可能不包含交互逻辑）的组件列表
    final lowPriorityWidgets = [
      Container,
      Padding,
      SizedBox,
      Align,
      Center,
    ];

    // 检查是否为低优先级组件，如果是则跳过
    if (lowPriorityWidgets.contains(widget.runtimeType)) {
      return false;
    }

    // 优先检查高优先级组件
    for (var type in highPriorityWidgets) {
      if (widget.runtimeType == type) {
        return _triggerSpecificWidgetAction(widget);
      }
    }

    // 如果不是高优先级组件，则按原来的顺序检查
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
      manageDebugOverlay(context, message: '找到控件，但无法触发操作');
      return false;
    }
  }
  
  /// 导航方法，通过 forward 参数决定是前进还是后退
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) {
    String action = '';
    int nextIndex = 0;
    // 获取当前组的首尾节点
    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!;
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!;
   
    // 获取焦点范围
    int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode);
    int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode);
    if (forward) {
      // 前进逻辑
      if (currentIndex == lastFocusIndex) {
        nextIndex = firstFocusIndex; // 循环到第一个焦点
        action = "循环到第一个焦点 (索引: $nextIndex)";
      } else {
        nextIndex = currentIndex + 1;
        action = "切换到下一个焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
      }
    } else {
      // 后退逻辑
      if (currentIndex == firstFocusIndex) {
        if (widget.frameType == "child") {
          // 在子页面的第一个焦点按左键时，一定要返回父页面
          final parentNavigation = _findParentNavigation();
          if (parentNavigation != null) {
            deactivateFocusManagement(); // 停用子页面焦点
            parentNavigation.activateFocusManagement(); // 激活父页面焦点
            manageDebugOverlay(context, message: '返回父页面');
          } else {
            manageDebugOverlay(context, message: '尝试返回父页面但失败');
          }
          return; // 无论成功失败都返回，不要循环到最后
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
    manageDebugOverlay(context, message: '操作: $action (组: $groupIndex)');
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (_groupFocusCache.isEmpty) {
      manageDebugOverlay(context, message: '没有缓存的分组信息，无法跳转');
      return false;
    }

    try {
      List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
      int currentGroupIndex = groupIndex ?? groupIndices.first;
      
      if (!groupIndices.contains(currentGroupIndex)) {
        manageDebugOverlay(context, message: '当前 Group $currentGroupIndex 无法找到');
        return false;
      }
      
      int totalGroups = groupIndices.length;
      int nextGroupIndex;

      // 判断跳转方向
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + totalGroups) % totalGroups];
      } else {
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % totalGroups];
      }
      
      manageDebugOverlay(context, message: '从 Group $currentGroupIndex 跳转到 Group $nextGroupIndex');

      // 获取下一个组的焦点信息
      final nextGroupFocus = _groupFocusCache[nextGroupIndex];

      if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) {
        FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode'];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nextFocusNode != null && nextFocusNode.context != null && nextFocusNode.canRequestFocus) {
            nextFocusNode.requestFocus();
            _currentFocus = nextFocusNode;
            manageDebugOverlay(context, message: '跳转到 Group $nextGroupIndex 的焦点节点: ${nextFocusNode.debugLabel ?? '未知'}');
          } else {
            manageDebugOverlay(context, message: '目标焦点节点未挂载或不可请求');
          }
        });
        return true;
      } else {
        manageDebugOverlay(context, message: '未找到 Group $nextGroupIndex 的焦点节点信息');
      }
    } catch (e, stackTrace) {
      manageDebugOverlay(context, message: '跳转组时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
    
    return false;
  }
}

class Group extends StatelessWidget {
  final int groupIndex;
  final Widget? child; // 支持单个 child
  final List<Widget>? children; // 支持多个 children

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

// 用于包装具有焦点的组件
class FocusableItem extends StatefulWidget { 
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件
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
