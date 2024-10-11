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
        _showDebugOverlayMessage('初始焦点设置失败: $e\n位置: $stackTrace');
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
      _showDebugOverlayMessage('资源释放失败: $e\n位置: $stackTrace');
    }
    super.dispose();
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
      _showDebugOverlayMessage('调试窗口显示失败: $e\n位置: $stackTrace');
    }
  }

  /// 移除调试窗口
  void _removeDebugOverlay() {
    try {
      _debugOverlayEntry?.remove();
      _debugOverlayEntry = null;
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('移除调试窗口失败: $e\n位置: $stackTrace');
    }
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    try {
      if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
        _showDebugOverlayMessage('请求焦点无效，索引超出范围: $index');
        return;
      }
      FocusNode focusNode = widget.focusNodes[index];
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        _currentFocus = focusNode;
        _currentIndex = index; // 更新 currentIndex
        _showDebugOverlayMessage('切换焦点到索引: $index');
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('切换焦点失败: $e\n位置: $stackTrace');
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
      _showDebugOverlayMessage('切换到前一个焦点失败: $e\n位置: $stackTrace');
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
      _showDebugOverlayMessage('切换到下一个焦点失败: $e\n位置: $stackTrace');
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
        _showDebugOverlayMessage('找不到当前焦点的索引。\n焦点节点总数: ${widget.focusNodes.length}');
        return KeyEventResult.ignored; // 找不到当前焦点时忽略
      }

      // 获取 groupIndex
      int groupIndex = _getGroupIndex(currentFocus); // 通过 focusNode 获取 groupIndex

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
      _showDebugOverlayMessage('焦点切换错误: $e\n位置: $stackTrace');
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

  /// 获取当前焦点所属的 groupIndex，删除缓存，避免使用_cachedGroup来记录Group
  int _getGroupIndex(FocusNode focusNode) {
    try {
      final state = focusNode.context?.findAncestorStateOfType<_FocusableItemState>();
      if (state != null) {
        return (state.widget as FocusableItem).groupIndex;
      }
      return -1;
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('获取分组索引失败: $e\n位置: $stackTrace');
      return -1;
    }
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (groupIndex == null || groupIndex == -1) return false;

    try {
      // 定义前进或后退分组的逻辑
      int nextGroupIndex;
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        // 后退：groupIndex - 1
        nextGroupIndex = groupIndex - 1;
        if (nextGroupIndex < 0) {
          _showDebugOverlayMessage('已经是第一个分组，无法再后退');
          return false;
        }
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
        // 前进：groupIndex + 1
        int totalGroups = _getTotalGroups();
        nextGroupIndex = groupIndex + 1;
        if (nextGroupIndex >= totalGroups) {
          _showDebugOverlayMessage('已经是最后一个分组，无法再前进');
          return false;
        }
      } else {
        return false;
      }

      // 切换焦点到下一个分组的第一个控件
      final nextGroup = _findGroupByIndex(nextGroupIndex);
      if (nextGroup != null) {
        final firstFocusNode = _findFirstFocusNodeInGroup(nextGroup);
        if (firstFocusNode != null) {
          firstFocusNode.requestFocus();
          _showDebugOverlayMessage('操作: ${key.debugName}键，切换到组 $nextGroupIndex 的第一个焦点');
          return true;
        }
      }
      _showDebugOverlayMessage('无法找到下一个组编号: $nextGroupIndex');
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('分组跳转失败: $e\n位置: $stackTrace');
    }

    return false;
  }

  /// 根据 groupIndex 查找对应的 Group
  Group? _findGroupByIndex(int groupIndex) {
    try {
      BuildContext? ancestorContext = _currentFocus?.context; // 使用当前焦点节点的上下文
      if (ancestorContext == null) return null;
      Group? ancestorGroup = ancestorContext.findAncestorWidgetOfExactType<Group>();
      // 确认找到的 Group 是否符合 groupIndex
      _showDebugOverlayMessage('找到的 Group: ${ancestorGroup?.groupIndex}');
      if (ancestorGroup != null && ancestorGroup.groupIndex == groupIndex) {
        return ancestorGroup;
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('查找分组失败: $e\n位置: $stackTrace');
    }
    return null; // 未找到匹配的 groupIndex
  }

  /// 查找 Group 下的第一个 FocusNode，移除对子结构的假设
  FocusNode? _findFirstFocusNodeInGroup(Group group) {
    try {
      for (Widget child in group.children) {
        if (child is FocusableItem) {
          return child.focusNode; // 返回第一个 FocusableItem 的 FocusNode
        }
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('查找焦点节点失败: $e\n位置: $stackTrace');
    }
    return null; // 没有找到 FocusNode
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return widget.focusNodes.length; 
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
      _showDebugOverlayMessage('键盘事件处理失败: $e\n位置: $stackTrace');
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
      _showDebugOverlayMessage('执行控件点击操作失败: $e\n位置: $stackTrace');
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
  final int groupIndex; // 分组索引

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
    required this.groupIndex, // 新增分组索引参数
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
