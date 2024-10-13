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
  List<String> _debugMessages = []; // 用于存储最多6条的调试消息
  Timer? _timer; // 定时器，用于控制消息超时
  final int _messageDisplayDuration = 6; // 超时时间，单位：秒

  // 调试模式开关
  final bool _showDebugOverlay = true;

  // 用于缓存每个Group的焦点信息（首尾节点）
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKey: _handleKeyEvent, // 处理键盘事件
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

        // 设置初始焦点
        if (widget.focusNodes.isNotEmpty || (widget.frameType ?? "") != "child") {
          _requestFocus(widget.initialIndex ?? 0);  // 设置初始焦点到第一个有效节点
        }
        _manageDebugOverlay(message: '初始焦点设置完成');
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
      if (_debugMessages.length > 15) {
        _debugMessages.removeAt(0);
      }

      // 移除所有旧的 OverlayEntry
      _clearAllOverlays();

      // 创建新的 OverlayEntry，用于显示多条提示
      final overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: 20.0,
          right: 20.0,
          child: Material(
            color: Colors.transparent,
            child: Container(
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

  /// 请求将焦点切换到指定索引的控件上。
void _requestFocus(int index) {
  if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
    _manageDebugOverlay(message: '请求焦点无效，索引超出范围: $index');
    return;
  }

  try {
    FocusNode focusNode = widget.focusNodes[index];

    // 检查焦点节点是否可以请求焦点
    if (!focusNode.canRequestFocus) {
      _manageDebugOverlay(message: '焦点节点不可请求，索引: $index');
      return;
    }

    if (!focusNode.hasFocus) {
      // 尝试设置焦点
      focusNode.requestFocus();
      _currentFocus = focusNode;
      _manageDebugOverlay(message: '切换焦点到索引: $index, 总节点数: ${widget.focusNodes.length}, 当前Group: ${_getGroupIndex(focusNode)}');

      // 延迟检查焦点是否成功获得
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.hasFocus) {
          _manageDebugOverlay(message: '焦点成功设置: 索引 $index');
        } else {
          _manageDebugOverlay(message: '焦点设置失败，焦点未正确切换到索引: $index');
        }
      });
    } else {
      _manageDebugOverlay(message: '焦点已经在索引: $index');
    }
  } catch (e) {
    _manageDebugOverlay(message: '切换焦点失败: $e');
  }
}


  /// 缓存 Group 的焦点信息
void _cacheGroupFocusNodes() {
  _groupFocusCache.clear();  // 清除现有缓存

  // 处理没有分组的情况
  if (_getAllGroups().isEmpty) {
    // 为所有可聚焦项创建一个“虚拟”分组
    _groupFocusCache[0] = {
      'firstFocusNode': widget.focusNodes.firstWhere((node) => node.canRequestFocus, orElse: () => FocusNode()),
      'lastFocusNode': widget.focusNodes.lastWhere((node) => node.canRequestFocus, orElse: () => FocusNode()),
    };

    _manageDebugOverlay(message: '缓存了没有分组页面的焦点节点');
    
    // 显示详细的缓存信息
    _manageDebugOverlay(
      message: '首个焦点节点: ${_groupFocusCache[0]?['firstFocusNode']}, 最后焦点节点: ${_groupFocusCache[0]?['lastFocusNode']}');
    
    return;
  }

  // 处理有分组的情况
  final groups = _getAllGroups();
  for (var group in groups) {
    final groupWidgets = _getWidgetsInGroup(group);
    final groupFocusNodes = _getFocusNodesInGroup(groupWidgets);

    if (groupFocusNodes.isNotEmpty) {
      _groupFocusCache[group.groupIndex] = {
        'firstFocusNode': groupFocusNodes.first,
        'lastFocusNode': groupFocusNodes.last,
      };

      // 显示每个分组的缓存信息
      _manageDebugOverlay(
        message: '分组 ${group.groupIndex}: 首个焦点节点: ${groupFocusNodes.first}, 最后焦点节点: ${groupFocusNodes.last}');
    }
  }

  // 显示总的缓存分组数量
  _manageDebugOverlay(message: '缓存了 ${_groupFocusCache.length} 个分组的焦点节点');
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

  /// 通用的查找 Group 中的焦点节点函数
  FocusNode? _findFocusNodeInGroup(Group group, {required bool first}) {
    try {
      FocusNode? focusNode;

      void searchFocusNode(Widget widget) {
        if (widget is FocusableItem) {
          focusNode = widget.focusNode;
        }
        if (widget is SingleChildRenderObjectWidget && widget.child != null) {
          searchFocusNode(widget.child!);
        } else if (widget is MultiChildRenderObjectWidget) {
          for (var child in first ? widget.children : widget.children.reversed) {
            searchFocusNode(child);
            if (focusNode != null) break;
          }
        }
      }

      group.children?.forEach((widget) {
        searchFocusNode(widget);
      });

      return focusNode;
    } catch (e, stackTrace) {
      _handleError(first ? '查找第一个焦点节点失败' : '查找最后一个焦点节点失败', e, stackTrace);
      return null;
    }
  }

  /// 合并后的导航方法，通过 forward 参数决定是前进还是后退
  void _navigateFocus(LogicalKeyboardKey key, int currentIndex, {required bool forward}) {
    String action;
    int nextIndex;

    if (forward) {
      // 前进逻辑
      if (currentIndex == widget.focusNodes.length - 1) {
        nextIndex = 0; // 循环到第一个焦点
        action = "循环到返回按钮";
      } else {
        nextIndex = currentIndex + 1;
        action = "切换到下一个焦点";
      }
    } else {
      // 后退逻辑
      if (currentIndex == 1) {
        nextIndex = 0; // 切换到返回按钮
        action = "切换到返回按钮";
      } else if (currentIndex == 0) {
        nextIndex = widget.focusNodes.length - 1; // 循环到最后一个焦点
        action = "循环到最后一个焦点";
      } else {
        nextIndex = currentIndex - 1;
        action = "切换到前一个焦点";
      }
    }

    _requestFocus(nextIndex);
    _manageDebugOverlay(message: '操作: ${key.debugName}键，$action');
  }

  /// 处理在组之间的跳转逻辑
bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
  if (_groupFocusCache.isEmpty) {
    _manageDebugOverlay(message: '没有缓存的分组信息，无法跳转');
    return false;
  }

  List<int> groupIndices = _groupFocusCache.keys.toList()..sort();
  int currentGroupIndex = groupIndex ?? groupIndices.first;
  int totalGroups = groupIndices.length;

  int nextGroupIndex;
  if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
    nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + totalGroups) % totalGroups];
  } else {
    nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % totalGroups];
  }

  _manageDebugOverlay(message: '跳跃分组操作，从 Group $currentGroupIndex 跳转到 Group $nextGroupIndex');

  final nextGroupFocus = _groupFocusCache[nextGroupIndex];
  if (nextGroupFocus != null && nextGroupFocus['firstFocusNode'] != null) {
    FocusNode nextFocusNode = nextGroupFocus['firstFocusNode']!;
    
    // 检查焦点节点是否可以请求焦点
    if (nextFocusNode.canRequestFocus) {
      nextFocusNode.requestFocus();

      // 获取焦点节点的 debugLabel 并显示详细信息
      String focusNodeLabel = nextFocusNode.debugLabel ?? '未知焦点节点';
      _manageDebugOverlay(message: '成功跳转到 Group $nextGroupIndex 的第一个焦点: $focusNodeLabel');
      
      return true;
    } else {
      _manageDebugOverlay(message: 'Group $nextGroupIndex 的第一个焦点无法请求焦点');
    }
  } else {
    _manageDebugOverlay(message: '未找到 Group $nextGroupIndex 的缓存信息');
  }

  return false;
}

  /// 获取当前焦点所属的 groupIndex
  int _getGroupIndex(FocusNode focusNode) {
    try {
      BuildContext? context = focusNode.context;
      if (context == null) {
        return -1;  // 如果 context 为空，直接返回 -1
      }
      GroupIndexProvider? provider = GroupIndexProvider.of(context);
      if (provider != null) {
        return provider.groupIndex;  // 返回找到的 groupIndex
      }
      return -1; // 如果没有找到 GroupIndexProvider，返回 -1
    } catch (e, stackTrace) {
      _handleError('获取分组索引失败', e, stackTrace);
      return -1;
    }
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return _getAllGroups().length;
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

    // 获取 groupIndex
    int groupIndex = _getGroupIndex(currentFocus);  // 通过 context 获取 groupIndex

    _manageDebugOverlay(message: '导航开始: 按键=${key.debugName}, 当前索引=$currentIndex, 当前Group=$groupIndex, 总节点数=${widget.focusNodes.length}');

    // 判断是否启用了框架模式 (isFrame)
    try {
      if (widget.isFrame) {  // 如果是框架模式
        if (widget.frameType == "parent") {   // 父页面
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {    // 左上键
            _navigateFocus(key, currentIndex, forward: false);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {   // 右键
            FocusScope.of(context).nextFocus(); // 前往子页面
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateFocus(key, currentIndex, forward: true);  // 前进或循环焦点
          }
        } else if (widget.frameType == "child") {  // 子页面
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            FocusScope.of(context).previousFocus(); // 返回主页面
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateFocus(key, currentIndex, forward: true);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        }
      } else {  // 如果不是框架模式
        if (widget.isHorizontalGroup) {   // 横向分组逻辑
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateFocus(key, currentIndex, forward: false);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateFocus(key, currentIndex, forward: true);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else if (widget.isVerticalGroup) {   // 竖向分组逻辑
          if (key == LogicalKeyboardKey.arrowUp) {  // 上键
            _navigateFocus(key, currentIndex, forward: false);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateFocus(key, currentIndex, forward: true);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {  // 左右键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else {  // 没有启用分组的默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {  // 左上键
            _navigateFocus(key, currentIndex, forward: false);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {  // 右下键
            _navigateFocus(key, currentIndex, forward: true);  // 前进或循环焦点
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
  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
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

  /// 执行当前焦点控件的点击操作或切换开关状态。
void _triggerButtonAction() {
    final focusNode = _currentFocus;  // 获取当前焦点
    if (focusNode != null && focusNode.context != null) {
        final context = focusNode.context!;
        final widget = context.widget;  // 获取当前焦点对应的 widget

        try {
            // 检查是否是 SwitchListTile 并切换其状态
            if (widget is SwitchListTile) {
                final value = !(widget.value ?? false); // 切换开关状态
                widget.onChanged?.call(value); // 调用 SwitchListTile 的 onChanged 回调
                _manageDebugOverlay(message: '切换 SwitchListTile 开关状态: $value');
                return; // 操作完成后直接返回
            }

            // 检查是否是带 onPressed 的按钮类型组件
            if (widget is ElevatedButton && widget.onPressed != null) {
                widget.onPressed!(); // 调用 ElevatedButton 的 onPressed
                _manageDebugOverlay(message: '执行 ElevatedButton 的 onPressed 操作');
                return; // 操作完成后直接返回
            } else if (widget is TextButton && widget.onPressed != null) {
                widget.onPressed!(); // 调用 TextButton 的 onPressed
                _manageDebugOverlay(message: '执行 TextButton 的 onPressed 操作');
                return; // 操作完成后直接返回
            } else if (widget is OutlinedButton && widget.onPressed != null) {
                widget.onPressed!(); // 调用 OutlinedButton 的 onPressed
                _manageDebugOverlay(message: '执行 OutlinedButton 的 onPressed 操作');
                return; // 操作完成后直接返回
            } else if (widget is IconButton && widget.onPressed != null) {
                widget.onPressed!(); // 调用 IconButton 的 onPressed
                _manageDebugOverlay(message: '执行 IconButton 的 onPressed 操作');
                return; // 操作完成后直接返回
            } else if (widget is FloatingActionButton && widget.onPressed != null) {
                widget.onPressed!(); // 调用 FloatingActionButton 的 onPressed
                _manageDebugOverlay(message: '执行 FloatingActionButton 的 onPressed 操作');
                return; // 操作完成后直接返回
            }

            // 检查是否存在具有 onTap 回调的 ListTile 并调用其回调
            if (widget is ListTile && widget.onTap != null) {
                widget.onTap!(); // 调用 ListTile 的 onTap
                _manageDebugOverlay(message: '执行 ListTile 的 onTap 操作');
                return; // 操作完成后直接返回
            }

            // 检查是否存在 PopupMenuButton 并调用其 onSelected 回调
            if (widget is PopupMenuButton) {
                widget.onSelected?.call(null); // 处理 PopupMenuButton 的选中事件
                _manageDebugOverlay(message: '执行 PopupMenuButton 的 onSelected 操作');
                return; // 操作完成后直接返回
            }

            // 如果没有找到可执行的组件
            _manageDebugOverlay(message: '未找到可以执行操作的控件');
        } catch (e, stackTrace) {
            // 捕获并报告执行操作时的错误
            _manageDebugOverlay(message: '执行操作时发生错误: $e, 堆栈信息: $stackTrace');
        }
    } else {
        _manageDebugOverlay(message: '当前无有效的焦点上下文');
    }
}

}

class GroupIndexProvider extends InheritedWidget {
  final int groupIndex;

  const GroupIndexProvider({
    Key? key,
    required this.groupIndex,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  bool updateShouldNotify(GroupIndexProvider oldWidget) {
    return groupIndex != oldWidget.groupIndex;
  }

  static GroupIndexProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GroupIndexProvider>();
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
    return GroupIndexProvider(
      groupIndex: groupIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: child != null
            ? [child!] // 如果传入了单个 child，则使用它
            : children ?? [], // 如果传入了 children，则使用它们
      ),
    );
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
    final int? effectiveGroupIndex = GroupIndexProvider.of(context)?.groupIndex ?? widget.groupIndex;
    return GroupIndexProvider( // 确保 GroupIndexProvider 传递正确的 groupIndex
      groupIndex: effectiveGroupIndex ?? -1,  // 确保有一个有效的 groupIndex
      child: Focus(
        focusNode: widget.focusNode,
        child: widget.child,
      ),
    );
  }
}
