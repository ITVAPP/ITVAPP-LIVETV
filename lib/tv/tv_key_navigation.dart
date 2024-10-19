import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final bool isFrame; // 是否启用框架模式，用于切换焦点
  final String? frameType; // 新增：用于识别父页面或子页面
  final int? initialIndex; // 初始焦点的索引，默认为空，如果为空则使用自动聚焦
  final bool isHorizontalGroup; // 是否启用横向分组
  final bool isVerticalGroup; // 是否启用竖向分组

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
  }) : super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus;
  List<OverlayEntry> _debugOverlays = []; // 调试信息窗口集合
  List<String> _debugMessages = []; // 用于存储调试消息
  Timer? _timer; // 定时器，用于控制消息超时
  final int _messageDisplayDuration = 5; // 超时时间，单位：秒

  // 调试模式开关
  final bool _showDebugOverlay = true;

  // 用于缓存每个Group的焦点信息（首尾节点）
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent, // 处理键盘事件
      child: widget.child, // 直接使用传入的子组件
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 缓存 Group 的焦点信息
        _cacheGroupFocusNodes();

        // 设置初始焦点，只要焦点节点不为空，或frameType不是 "child" 就执行
        if (widget.focusNodes.isNotEmpty) {
          _requestFocus(widget.initialIndex ?? 0);  // 设置初始焦点到第一个有效节点
          _manageDebugOverlay(message: '初始焦点设置完成');
        }
      } catch (e) {
        _manageDebugOverlay(message: '初始焦点设置失败: $e');
      }
    });

    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    _cancelTimer(); // 取消计时器
    _manageDebugOverlay(); // 移除调试窗口
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    super.dispose();
  }

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    _manageDebugOverlay(message: '$message: $error\n位置: $stackTrace');
  }

  /// 管理调试信息浮动窗口，并控制超时逻辑
void _manageDebugOverlay({String? message}) {
  if (!_showDebugOverlay) return;

  if (message != null) {
    // 插入新消息
    _debugMessages.add(message);

    // 限制最多显示消息，超出时立即移除最早的一条
    if (_debugMessages.length > 8) {
      _debugMessages.removeAt(0);
    }

    // 移除所有旧的 OverlayEntry
    _clearAllOverlays();

    // 创建新的 OverlayEntry，用于显示多条提示
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 20.0,
        right: 20.0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 300.0, // 设置最大宽度为300
            ),
            padding: EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _debugMessages
                  .map((msg) => Text(
                        msg,
                        style: TextStyle(color: Colors.white, fontSize: 14),
                        softWrap: true, // 自动换行
                        overflow: TextOverflow.visible, // 超出部分可见
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );

    // 插入新的提示 OverlayEntry
    Overlay.of(context).insert(overlayEntry);
    _debugOverlays.add(overlayEntry); // 将新的 OverlayEntry 添加到列表中

    // 每次有新消息时，重置计时器
    _resetTimer();
  } else {
    // 移除所有 OverlayEntry
    _clearAllOverlays();
    _cancelTimer(); // 清空后，取消计时器
  }
}

  /// 重置计时器，每次新消息加入时调用
  void _resetTimer() {
    if (_timer != null && _timer!.isActive) {
        // 如果已有活动定时器，不重新启动，避免多次重置
        return;
    }
    // 取消现有定时器
    _cancelTimer(); // 先取消已有的计时器
    _timer = Timer.periodic(Duration(seconds: _messageDisplayDuration), (timer) {
      if (_debugMessages.isNotEmpty) {
        _debugMessages.removeAt(0); // 删除最早的一条消息

        // 如果消息清空了，停止计时器并关闭弹窗
        if (_debugMessages.isEmpty) {
          _clearAllOverlays();
          _cancelTimer();
        } else {
          // 仅更新剩余消息的显示，而不清除整个 Overlay
          _updateOverlayMessages();
        }
      }
    });
  }

  /// 更新当前显示的 Overlay 信息，而不是删除和重建
  void _updateOverlayMessages() {
    if (_debugOverlays.isNotEmpty) {
      // 获取当前的 OverlayEntry
      OverlayEntry currentOverlay = _debugOverlays.first;

      // 通过 OverlayState 更新显示内容，而不清除整个 Overlay
      currentOverlay.markNeedsBuild();
    }
  }

  /// 取消定时器
  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 清除所有 OverlayEntry
  void _clearAllOverlays() {
    for (var entry in _debugOverlays) {
      entry.remove();
    }
    _debugOverlays.clear();
  }

  /// 请求将焦点切换到指定索引的控件上
  void _requestFocus(int index, {int? groupIndex}) {
    if (widget.focusNodes.isEmpty) {
      _manageDebugOverlay(message: '焦点节点列表为空，无法设置焦点');
      return;
    }

    try {
      // 检查 index 是否在合法范围内
      if (index < 0 || index >= widget.focusNodes.length) {
        _manageDebugOverlay(message: '索引 $index 超出范围，无法访问 focusNodes。总节点数: ${widget.focusNodes.length}');
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
        _manageDebugOverlay(message: '无效的 Group，设置到第一个可用焦点节点');
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
        _manageDebugOverlay(message: '焦点节点不可请求，索引: $index');
        return;
      }

      // 请求焦点
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();  // 设置焦点到指定的节点
        _currentFocus = focusNode;
        _manageDebugOverlay(message: '切换焦点到索引: $index, 当前Group: $groupIndex');
      }
    } catch (e, stackTrace) {
      // 捕获其他潜在的异常，显示错误提示
      _manageDebugOverlay(message: '设置焦点时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
  }

  /// 缓存 Group 的焦点信息
 void _cacheGroupFocusNodes() {
  _groupFocusCache.clear();  // 清空现有缓存
  _manageDebugOverlay(message: '开始缓存分组焦点信息');

  // 获取所有的 Group
  final groups = _getAllGroups();
  _manageDebugOverlay(message: '找到的总组数: ${groups.length}');

  if (groups.isEmpty || groups.length == 1) {
    // 如果没有显式的分组，或只有一个分组，直接缓存首尾焦点节点
    FocusNode? firstFocusNode = widget.focusNodes.firstWhere(
      (node) => node.canRequestFocus, 
      orElse: () => FocusNode() // 处理没有可请求焦点的情况
    );
    FocusNode? lastFocusNode = widget.focusNodes.lastWhere(
      (node) => node.canRequestFocus, 
      orElse: () => FocusNode() // 处理没有可请求焦点的情况
    );
    // 即使没有显式分组，也要缓存一个默认的分组
    _groupFocusCache[0] = {
      'firstFocusNode': firstFocusNode,
      'lastFocusNode': lastFocusNode,
    };
    _manageDebugOverlay(
      message: '缓存了没有分组或单一分组的焦点节点 - '
               '首个焦点节点: ${_formatFocusNodeDebugLabel(firstFocusNode)}, '
               '最后焦点节点: ${_formatFocusNodeDebugLabel(lastFocusNode)}'
    );
  } else {
    // 如果有多个分组，遍历每个分组并缓存其首尾焦点节点
    for (var group in groups) {
      final groupWidgets = _getWidgetsInGroup(group);  // 获取分组中的所有子组件
      final groupFocusNodes = _getFocusNodesInGroup(groupWidgets);  // 获取所有焦点节点
      
      _manageDebugOverlay(message: '分组 ${group.groupIndex} 的组件数: ${groupWidgets.length}, 焦点节点数: ${groupFocusNodes.length}');

      if (groupFocusNodes.isNotEmpty) {
        // 缓存当前分组的首尾焦点节点
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': groupFocusNodes.first,
          'lastFocusNode': groupFocusNodes.last,
        };
        _manageDebugOverlay(
          message: '分组 ${group.groupIndex}: '
                   '首个焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.first)}, '
                   '最后焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.last)}'
        );
      } else {
        _manageDebugOverlay(message: '警告：分组 ${group.groupIndex} 没有可聚焦的节点');
      }
    }
  }

  // 显示总共缓存的分组数量和详细信息
  _manageDebugOverlay(message: '缓存了 ${_groupFocusCache.length} 个分组的焦点节点');
}

  String _formatFocusNodeDebugLabel(FocusNode focusNode) {
    // 如果 FocusNode 设置了 debugLabel，就显示它，否则显示该节点在 focusNodes 中的索引
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
      // 遍历缓存的分组信息，查找该 focusNode 所属的分组
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
    return _groupFocusCache.length;  // 返回缓存中分组的数量
  }

  /// 获取所有的 Group
  List<Group> _getAllGroups() {
    List<Group> groups = [];

    // 递归查找所有 Group 的方法
    void searchGroups(Element element) {
      if (element.widget is Group) {
        groups.add(element.widget as Group);
      }

      // 递归访问子元素
      element.visitChildren((child) {
        searchGroups(child);
      });
    }

    // 查找 context 中的所有 Element
    if (context != null) {
      context.visitChildElements((element) {
        searchGroups(element);
      });
    }

    _manageDebugOverlay(message: '找到的总组数: ${groups.length}');
    return groups;
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    FocusNode? currentFocus = _currentFocus;

    // 如果当前没有焦点，则尝试将焦点设置为第一个 focusNode
    if (currentFocus == null) {
      _manageDebugOverlay(message: '当前无焦点，尝试设置初始焦点');
      _requestFocus(0); // 设置焦点为第一个控件
      return KeyEventResult.handled; // 返回已处理，避免进一步忽略
    }

    // 获取当前焦点的索引 (currentIndex)
    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      _manageDebugOverlay(message: '找不到当前焦点的索引，忽略按键: ${key.debugName}');
      return KeyEventResult.ignored; // 找不到当前焦点时忽略
    }

    // 获取当前焦点的 groupIndex，如果找不到，默认为 -1
    int groupIndex = _getGroupIndex(currentFocus);  // 通过 context 获取 groupIndex

    _manageDebugOverlay(message: '导航开始: 按键=${key.debugName}, 当前索引=$currentIndex, 当前Group=$groupIndex, 总节点数=${widget.focusNodes.length}');

    try {
      // 判断是否启用了框架模式 (isFrame)
      if (widget.isFrame) {  // 如果是框架模式
        if (widget.frameType == "parent") {   // 父页面
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {  // 左上键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            FocusManager.instance.primaryFocus?.unfocus();
            FocusScope.of(context).nextFocus(); // 前往子页面
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateFocus(key, currentIndex, forward: true, groupIndex: groupIndex);  // 前进或循环焦点
          }
        } else if (widget.frameType == "child") {  // 子页面
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateFocus(key, currentIndex, forward: false, groupIndex: groupIndex);  // 后退或循环焦点
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
      _manageDebugOverlay(message: '焦点切换错误: $e');
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

      // 判断是否为方向键
      if (_isDirectionKey(key)) {
        return _handleNavigation(key);
      }

      // 判断是否为选择键
      if (_isSelectKey(key)) {
        _triggerButtonAction(); // 直接调用方法触发按钮操作
        _manageDebugOverlay(message: '选择键操作: ${key.debugName}');
        return KeyEventResult.handled; // 标记按键事件已处理
      }

      // 自定义的按键处理回调
      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
        _manageDebugOverlay(message: '自定义按键回调: ${key.debugName}');
      }
    }
    return KeyEventResult.ignored; // 如果未处理，返回忽略
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

  /// 执行当前焦点控件的点击操作或切换开关状态
void _triggerButtonAction() {
  final focusNode = _currentFocus; // 获取当前焦点

  if (focusNode != null && focusNode.context != null) {
    final BuildContext? context = focusNode.context;

    if (context == null) {
      _manageDebugOverlay(message: '索引${_currentFocus.toString()} 焦点上下文为空，无法操作');
      return;
    }

    try {
      // 查找当前焦点下的交互组件
      Widget? interactiveWidget = _findInteractiveWidget(context);

      if (interactiveWidget != null) {
        _executeInteractiveWidgetAction(interactiveWidget); // 找到交互组件后执行其操作
      } else {
        _manageDebugOverlay(message: '索引${_currentFocus.toString()} 未找到可执行操作的控件');
      }
    } catch (e, stackTrace) {
      _manageDebugOverlay(message: '执行操作时发生错误: $e\n堆栈信息: $stackTrace');
    }
  } else {
    _manageDebugOverlay(message: '索引${_currentFocus.toString()} 无有效的焦点上下文');
  }
}

// 在子组件中递归查找交互组件
Widget? _findInteractiveChild(Widget child) {
  if (_isInteractiveWidget(child)) {
    return child; // 如果是交互组件，直接返回它
  }

  // 如果是 FocusableItem 或 Focus 包裹的组件，递归查找其子组件
  if (child is FocusableItem) {
    return _findInteractiveChild(child.child); // 查找 FocusableItem 的子组件
  } else if (child is Focus) {
    return _findInteractiveChild(child.child!); // 查找 Focus 的子组件
  }

  return null;
}

// 递归查找控件树中的交互组件
Widget? _findInteractiveWidget(BuildContext context) {
  Widget widget = context.widget;
  if (_isInteractiveWidget(widget)) {
    return widget; // 如果是交互组件，直接返回它
  }

  // 如果是 Focus 包裹的组件，继续递归查找其子节点
  if (widget is Focus) {
    Focus focusWidget = widget as Focus;
    if (focusWidget.child != null) {
      return _findInteractiveChild(focusWidget.child!);
    }
  }

  // 查找父上下文中的交互组件
  final parentContext = context.findAncestorStateOfType<State>()?.context;
  if (parentContext != null) {
    return _findInteractiveWidget(parentContext);
  }
  
  return null;
}

// 判断是否为交互组件
bool _isInteractiveWidget(Widget widget) {
  return widget is ElevatedButton ||
         widget is IconButton ||
         widget is TextButton ||
         widget is OutlinedButton ||
         widget is SwitchListTile ||
         widget is FloatingActionButton ||
         widget is PopupMenuButton ||
         widget is ListTile;
}

// 执行交互组件的操作
void _executeInteractiveWidgetAction(Widget interactiveWidget) {
  if (interactiveWidget is SwitchListTile && interactiveWidget.onChanged != null) {
    interactiveWidget.onChanged!(!interactiveWidget.value); // 切换 SwitchListTile 状态
  } else if (interactiveWidget is ElevatedButton && interactiveWidget.onPressed != null) {
    interactiveWidget.onPressed!(); // 执行 ElevatedButton 的 onPressed
  } else if (interactiveWidget is TextButton && interactiveWidget.onPressed != null) {
    interactiveWidget.onPressed!(); // 执行 TextButton 的 onPressed
  } else if (interactiveWidget is OutlinedButton && interactiveWidget.onPressed != null) {
    interactiveWidget.onPressed!(); // 执行 OutlinedButton 的 onPressed
  } else if (interactiveWidget is IconButton && interactiveWidget.onPressed != null) {
    interactiveWidget.onPressed!(); // 执行 IconButton 的 onPressed
  } else if (interactiveWidget is FloatingActionButton && interactiveWidget.onPressed != null) {
    interactiveWidget.onPressed!(); // 执行 FloatingActionButton 的 onPressed
  } else if (interactiveWidget is ListTile && interactiveWidget.onTap != null) {
    interactiveWidget.onTap!(); // 执行 ListTile 的 onTap
  } else if (interactiveWidget is PopupMenuButton && interactiveWidget.onSelected != null) {
    interactiveWidget.onSelected!(null); // 执行 PopupMenuButton 的 onSelected
  } else {
    _manageDebugOverlay(message: '索引${_currentFocus.toString()} 未找到可执行操作的控件');
  }

  _manageDebugOverlay(message: '执行按钮操作');
}
  
  /// 导航方法，通过 forward 参数决定是前进还是后退
void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward, required int groupIndex}) {
  String action;
  int nextIndex;

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
        FocusScope.of(context).requestFocus();
        return; // 提前退出函数，避免后续调用 _requestFocus
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
  _manageDebugOverlay(message: '操作: ${key.debugName}键，$action (组: $groupIndex)');
}

/// 处理在组之间的跳转逻辑
bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
  _manageDebugOverlay(message: '尝试跳转到其他组，当前索引：$currentIndex，当前组：$groupIndex');
  
  if (_groupFocusCache.isEmpty) {
    _manageDebugOverlay(message: '没有缓存的分组信息，无法跳转');
    return false;
  }

  try {
    // 获取所有组索引并排序
    List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
    int currentGroupIndex = groupIndex ?? groupIndices.first;
    
    if (!groupIndices.contains(currentGroupIndex)) {
      _manageDebugOverlay(message: '当前 Group $currentGroupIndex 无法找到');
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
    
    _manageDebugOverlay(message: '从 Group $currentGroupIndex 跳转到 Group $nextGroupIndex');

    // 获取下一个组的焦点信息
    final nextGroupFocus = _groupFocusCache[nextGroupIndex];

    if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) {
      FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode'];

      // 检查焦点节点挂载并在下一个渲染帧请求焦点
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (nextFocusNode != null && nextFocusNode.context != null && nextFocusNode.canRequestFocus) {
          nextFocusNode.requestFocus();
          _currentFocus = nextFocusNode;
          _manageDebugOverlay(message: '跳转到 Group $nextGroupIndex 的焦点节点: ${nextFocusNode.debugLabel ?? '未知'}');
        } else {
          _manageDebugOverlay(message: '目标焦点节点未挂载或不可请求');
        }
      });
      return true;
    } else {
      _manageDebugOverlay(message: '未找到 Group $nextGroupIndex 的焦点节点信息');
    }
  } catch (RangeError) {
    _manageDebugOverlay(message: '焦点跳转时发生范围错误，当前 Group 无法跳转');
  } catch (e, stackTrace) {
    // 捕获其他潜在的异常，显示错误提示
    _manageDebugOverlay(message: '跳转组时发生未知错误: $e\n堆栈信息: $stackTrace');
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
    // 不改变布局，仅仅透传 child 或 children
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
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // 如果需要对键盘事件进行处理，可以在这里处理
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
