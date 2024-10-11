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
  OverlayEntry? _debugOverlayEntry; // 调试信息窗口

  // 添加私有变量来跟踪当前索引
  int _currentIndex = 0; // 初始索引为0，或根据需要设置默认值

  // 添加 getter
  int get currentIndex => _currentIndex; // 获取当前索引

  // 调试模式开关
  final bool _showDebugOverlay = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 设置初始焦点
        if (widget.focusNodes.isNotEmpty) {
          _requestFocus(widget.initialIndex ?? 0);  // 设置初始焦点到第一个有效节点
        }
        _showDebugOverlayMessage('初始焦点设置完成');
      } catch (e, stackTrace) {
        _handleError('初始焦点设置失败', e, stackTrace);
      }
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    try {
      _removeDebugOverlay(); // 移除调试窗口
      WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    } catch (e, stackTrace) {
      _handleError('资源释放失败', e, stackTrace);
    }
    super.dispose();
  }

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    _showDebugOverlayMessage('$message: $error\n位置: $stackTrace');
  }

  /// 显示调试信息的浮动窗口
  void _showDebugOverlayMessage(String message) {
    if (!_showDebugOverlay) return;

    try {
      if (_debugOverlayEntry == null) {
        _debugOverlayEntry = OverlayEntry(
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
                child: Text(
                  message,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        );
        Overlay.of(context).insert(_debugOverlayEntry!);
      } else {
        _debugOverlayEntry!.markNeedsBuild(); // 更新已存在的 OverlayEntry
      }

      // 自动隐藏提示
      Future.delayed(Duration(seconds: 3), () {
        _removeDebugOverlay();
      });
    } catch (e, stackTrace) {
      _handleError('调试窗口显示失败', e, stackTrace);
    }
  }

  /// 移除调试窗口
  void _removeDebugOverlay() {
    try {
      _debugOverlayEntry?.remove();
      _debugOverlayEntry = null;
    } catch (e, stackTrace) {
      _handleError('移除调试窗口失败', e, stackTrace);
    }
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    try {
      if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
        _showDebugOverlayMessage('请求焦点无效，索引超出范围: $index, 总节点数: ${widget.focusNodes.length}');
        return;
      }
      FocusNode focusNode = widget.focusNodes[index];
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        _currentFocus = focusNode;
        _currentIndex = index; // 更新 currentIndex
        _showDebugOverlayMessage('切换焦点到索引: $index, 总节点数: ${widget.focusNodes.length}, 当前Group: ${_getGroupIndex(focusNode)}');
      }
    } catch (e, stackTrace) {
      _handleError('切换焦点失败', e, stackTrace);
    }
  }

  // 后退或循环焦点
  void _navigateToPreviousFocus(LogicalKeyboardKey key, int currentIndex) {
    try {
      String action;
      // 如果当前焦点是第一个
      if (currentIndex == 0) {
        _requestFocus(widget.focusNodes.length - 1);
        action = "循环到最后一个焦点";
      } else {
        _requestFocus(currentIndex - 1);
        action = "切换到前一个焦点";
      }
      _showDebugOverlayMessage('操作: ${key.debugName}键，$action');
    } catch (e, stackTrace) {
      _handleError('切换到前一个焦点失败', e, stackTrace);
    }
  }

  // 前进或循环焦点
  void _navigateToNextFocus(LogicalKeyboardKey key, int currentIndex) {
    try {
      String action;
      // 如果当前焦点是最后一个
      if (currentIndex == widget.focusNodes.length - 1) {
        _requestFocus(0);
        action = "循环到第一个焦点";
      } else {
        _requestFocus(currentIndex + 1);
        action = "切换到下一个焦点";
      }
      _showDebugOverlayMessage('操作: ${key.debugName}键，$action');
    } catch (e, stackTrace) {
      _handleError('切换到下一个焦点失败', e, stackTrace);
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    try {
      FocusNode? currentFocus = _currentFocus;

      // 如果当前没有焦点，则尝试将焦点设置为第一个 focusNode
      if (currentFocus == null) {
        _showDebugOverlayMessage('当前无焦点，尝试设置初始焦点。\n焦点节点总数: ${widget.focusNodes.length}');
        _requestFocus(0); // 设置焦点为第一个控件
        return KeyEventResult.handled; // 返回已处理，避免进一步忽略
      }

      // 获取当前焦点的索引 (currentIndex)
      int currentIndex = widget.focusNodes.indexOf(currentFocus);
      if (currentIndex == -1) {
        _showDebugOverlayMessage('找不到当前焦点的索引。\n焦点节点总数: ${widget.focusNodes.length}, 当前焦点: ${currentFocus.toString()}');
        return KeyEventResult.ignored; // 找不到当前焦点时忽略
      }

      // 获取 groupIndex
      int groupIndex = _getGroupIndex(currentFocus); // 通过 focusNode 获取 groupIndex

      _showDebugOverlayMessage('导航开始: 按键=${key.debugName}, 当前索引=$currentIndex, 当前Group=$groupIndex, 总节点数=${widget.focusNodes.length}');

      // 判断是否启用了框架模式 (isFrame)
      if (widget.isFrame) {  // 如果是框架模式
        if (widget.frameType == "parent") {   // 父页面
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {    // 左上键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {   // 右键
            FocusScope.of(context).nextFocus(); // 前往子页面
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          }
        } else if (widget.frameType == "child") {  // 子页面
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            FocusScope.of(context).previousFocus(); // 返回主页面
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        }
      } else {  // 如果不是框架模式
        if (widget.isHorizontalGroup) {   // 横向分组逻辑
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else if (widget.isVerticalGroup) {   // 竖向分组逻辑
          if (key == LogicalKeyboardKey.arrowUp) {  // 上键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {  // 左右键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else {  // 没有启用分组的默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {  // 左上键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {  // 右下键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          }
        }
      }
    } catch (e, stackTrace) {
      _handleError('焦点切换错误', e, stackTrace);
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

  /// 获取当前焦点所属的 groupIndex
  int _getGroupIndex(FocusNode focusNode) {
    try {
      BuildContext? context = focusNode.context;
      while (context != null) {
        final widget = context.widget;
        if (widget is FocusableItem && widget.groupIndex != null) {
          return widget.groupIndex!;
        }
        context = context.findAncestorStateOfType<StatefulElement>()?.widget.key == context.widget.key
            ? null
            : context.findAncestorStateOfType<StatefulElement>()?.context;
      }
      return -1;
    } catch (e, stackTrace) {
      _handleError('获取分组索引失败', e, stackTrace);
      return -1;
    }
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (groupIndex == null || groupIndex == -1) {
      _showDebugOverlayMessage('无法跳转：当前组索引无效, groupIndex=$groupIndex');
      return false;
    }

    try {
      List<Group> allGroups = _getAllGroups();
      if (allGroups.isEmpty) {
        _showDebugOverlayMessage('无法跳转：未找到任何组');
        return false;
      }

int currentGroupIndex = allGroups.indexWhere((group) => group.groupIndex == groupIndex);
      if (currentGroupIndex == -1) {
        _showDebugOverlayMessage('无法跳转：找不到当前组, groupIndex=$groupIndex');
        return false;
      }

      int nextGroupIndex;
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        nextGroupIndex = (currentGroupIndex - 1 + allGroups.length) % allGroups.length;
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
        nextGroupIndex = (currentGroupIndex + 1) % allGroups.length;
      } else {
        _showDebugOverlayMessage('无法跳转：无效的按键, key=${key.debugName}');
        return false;
      }

      Group nextGroup = allGroups[nextGroupIndex];
      final firstFocusNode = _findFirstFocusNodeInGroup(nextGroup);
      if (firstFocusNode != null) {
        firstFocusNode.requestFocus();
        _showDebugOverlayMessage('组间跳转: 按键=${key.debugName}, 从组$groupIndex跳转到组${nextGroup.groupIndex}, 总组数=${allGroups.length}');
        return true;
      }
      _showDebugOverlayMessage('无法跳转：在目标组中找不到焦点节点, 目标组索引=${nextGroup.groupIndex}');
    } catch (e, stackTrace) {
      _handleError('分组跳转失败', e, stackTrace);
    }

    return false;
  }

  /// 根据 groupIndex 查找对应的 Group
  Group? _findGroupByIndex(int groupIndex) {
    try {
      Group? foundGroup;
      void searchGroup(Widget widget) {
        if (widget is Group && widget.groupIndex == groupIndex) {
          foundGroup = widget;
          return;
        }
        if (widget is SingleChildRenderObjectWidget) {
          searchGroup(widget.child!);
        } else if (widget is MultiChildRenderObjectWidget) {
          widget.children.forEach(searchGroup);
        }
      }
      searchGroup(widget.child);
      return foundGroup;
    } catch (e, stackTrace) {
      _handleError('查找分组失败', e, stackTrace);
      return null;
    }
  }

  /// 查找 Group 下的第一个 FocusNode
  FocusNode? _findFirstFocusNodeInGroup(Group group) {
    try {
      FocusNode? firstFocusNode;
      void searchFocusNode(List<Widget> children) {
        for (var child in children) {
          if (child is FocusableItem) {
            firstFocusNode = child.focusNode;
            return;
          } else if (child is SingleChildRenderObjectWidget) {
            searchFocusNode([child.child!]);
          } else if (child is MultiChildRenderObjectWidget) {
            searchFocusNode(child.children);
          }
          if (firstFocusNode != null) break;
        }
      }
      searchFocusNode(group.children);
      return firstFocusNode;
    } catch (e, stackTrace) {
      _handleError('查找焦点节点失败', e, stackTrace);
      return null;
    }
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return _getAllGroups().length;
  }

  /// 获取所有的 Group
  List<Group> _getAllGroups() {
    List<Group> groups = [];
    void searchGroups(Widget widget) {
      if (widget is Group) {
        groups.add(widget);
      }
      if (widget is SingleChildRenderObjectWidget) {
        searchGroups(widget.child!);
      } else if (widget is MultiChildRenderObjectWidget) {
        widget.children.forEach(searchGroups);
      }
    }
    searchGroups(widget.child);
    return groups;
  }

  /// 处理键盘事件，包括方向键和选择键。
  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    try {
      if (event is RawKeyDownEvent) {
        LogicalKeyboardKey key = event.logicalKey;

        // 判断是否为方向键
        if (_isDirectionKey(key)) {
          return _handleNavigation(key);
        }

        // 判断是否为选择键
        if (_isSelectKey(key)) {
          _triggerButtonAction(); // 直接调用方法触发按钮操作
          _showDebugOverlayMessage('选择键操作: ${key.debugName}');
          return KeyEventResult.handled; // 标记按键事件已处理
        }

        // 自定义的按键处理回调
        if (widget.onKeyPressed != null) {
          widget.onKeyPressed!(key);
          _showDebugOverlayMessage('自定义按键回调: ${key.debugName}');
        }
      }
    } catch (e, stackTrace) {
      _handleError('键盘事件处理失败', e, stackTrace);
    }
    return KeyEventResult.ignored; // 如果未处理，返回忽略
  }

  /// 判断是否为方向键
  bool _isDirectionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
           key == LogicalKeyboardKey.arrowDown ||
           key == LogicalKeyboardKey.arrowLeft ||
           key == LogicalKeyboardKey.arrowRight;
  }

  /// 判断是否为选择键
  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
  }

  /// 执行当前焦点控件的点击操作或切换开关状态。
  void _triggerButtonAction() {
    try {
      final context = _currentFocus?.context;
      if (context != null) {
        // 检查是否是 SwitchListTile 并切换其状态
        final switchTile = context.findAncestorWidgetOfExactType<SwitchListTile>();
        if (switchTile != null) {
          final value = !(switchTile.value ?? false); // 切换状态
          switchTile.onChanged?.call(value); // 调用 onChanged 回调切换开关状态
          _showDebugOverlayMessage('切换开关状态: $value');
          return;
        }

        // 检查是否有带 onPressed 的按钮类型组件
        final button = context.findAncestorWidgetOfExactType<ElevatedButton>() ??
            context.findAncestorWidgetOfExactType<TextButton>() ??
            context.findAncestorWidgetOfExactType<OutlinedButton>();

        if (button != null) {
          final onPressed = button.onPressed;
          if (onPressed != null) {
            onPressed(); // 调用按钮的 onPressed 回调
            _showDebugOverlayMessage('执行按钮操作');
            return;
          }
        }

        // 检查是否存在具有 onTap 回调的 FocusableItem 并调用其回调
        final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();
        if (focusableItem != null && focusableItem.child is ListTile) {
          final listTile = focusableItem.child as ListTile;
          if (listTile.onTap != null) {
            listTile.onTap!(); 
            _showDebugOverlayMessage('执行 ListTile 的 onTap 操作');
            return;
          }
        }
      }
    } catch (e, stackTrace) {
      _handleError('执行控件点击操作失败', e, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKey: _handleKeyEvent, // 处理键盘事件
      child: widget.child, // 直接使用传入的子组件
    );
  }
}

class Group extends StatelessWidget {
  final int groupIndex; // 分组编号
  final List<Widget> children;

  const Group({
    Key? key,
    required this.groupIndex,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.map((child) {
        if (child is FocusableItem) {
          return FocusableItem(
            focusNode: child.focusNode,
            child: child.child,
            groupIndex: groupIndex, // 将 groupIndex 传递给 FocusableItem
          );
        }
        return child;
      }).toList(),
    );
  }
}

// 用于包装具有焦点的组件
class FocusableItem extends StatefulWidget {
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件
  final int? groupIndex; // 分组索引，可选参数

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
    this.groupIndex, // groupIndex 是可选的
  }) : super(key: key);

  @override
  _FocusableItemState createState() => _FocusableItemState();
}

class _FocusableItemState extends State<FocusableItem> {
  @override
  Widget build(BuildContext context) {
    // 在需要使用 groupIndex 的地方做 null 检查
    int groupIndex = widget.groupIndex ?? -1; // 默认值为 -1 或根据需求设置
    
    return Focus(
      focusNode: widget.focusNode,
      child: widget.child,
    );
  }
}
