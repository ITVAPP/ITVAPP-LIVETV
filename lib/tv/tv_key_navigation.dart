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
  FocusNode? get _currentFocus => FocusScope.of(context).focusedChild as FocusNode?;
  OverlayEntry? _debugOverlayEntry; // 调试信息窗口
  Group? _cachedGroup; // 缓存 Group 实例

  // 硬编码调试模式开关
  final bool _showDebugOverlay = true;

  @override
  void initState() {
    super.initState();
    _cachedGroup = null; // 清除缓存
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 设置初始焦点
        _requestFocus((widget.initialIndex != null && widget.initialIndex! >= 0 && widget.initialIndex! < widget.focusNodes.length)
            ? widget.initialIndex!
            : 0);
        _showDebugOverlayMessage('初始焦点设置完成');
      } catch (e) {
        _showDebugOverlayMessage('初始焦点设置失败: $e');
      }
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    _cachedGroup = null; // 清除缓存
    _removeDebugOverlay(); // 移除调试窗口
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    super.dispose();
  }

  /// 显示调试信息的浮动窗口
  void _showDebugOverlayMessage(String message) {
    if (!_showDebugOverlay) return;

    _removeDebugOverlay(); // 先移除旧的，确保只有一个显示

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

    // 自动隐藏提示
    Future.delayed(Duration(seconds: 3), () {
      _removeDebugOverlay();
    });
  }

  /// 移除调试窗口
  void _removeDebugOverlay() {
    _debugOverlayEntry?.remove();
    _debugOverlayEntry = null;
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    try {
      // 增加 focusNodes 是否为空的检查
      if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
        _showDebugOverlayMessage('请求焦点无效，索引超出范围: $index');
        return; // 增加检查，防止空引用错误
      }
      widget.focusNodes[index].requestFocus();
      _showDebugOverlayMessage('切换焦点到索引: $index');
    } catch (e) {
      _showDebugOverlayMessage('切换焦点失败: $e');
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;

    // 1. 检查当前是否有焦点 (currentFocus)
    if (currentFocus == null) {
      _showDebugOverlayMessage('当前无焦点，忽略按键: ${key.debugName}');
      return KeyEventResult.ignored; // 没有焦点时忽略
    }

    // 2. 获取当前焦点的索引 (currentIndex)
    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      _showDebugOverlayMessage('找不到当前焦点的索引，忽略按键: ${key.debugName}');
      return KeyEventResult.ignored; // 找不到当前焦点时忽略
    }

    // 获取 groupIndex
    int groupIndex = _getGroupIndex(currentFocus.context!); // 通过 context 获取 groupIndex

    // 3. 判断是否启用了框架模式 (isFrame)
    try {
      if (widget.isFrame) {
        // 如果 frameType 是 "parent"
        if (widget.frameType == "parent") {
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
            // 左键和上键：后退或循环焦点
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
              _showDebugOverlayMessage('父页面: ${key == LogicalKeyboardKey.arrowLeft ? '左' : '上'}键，循环到最后一个焦点');
            } else {
              _requestFocus(currentIndex - 1);
              _showDebugOverlayMessage('父页面: ${key == LogicalKeyboardKey.arrowLeft ? '左' : '上'}键，切换到前一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowRight) {
            // 右键：切换到子页面
            _jumpToOtherGroup(key, currentIndex, 0);
            _showDebugOverlayMessage('父页面: 右键，切换到子页面');
          } else if (key == LogicalKeyboardKey.arrowDown) {
            // 下键：前进或循环焦点
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0);
              _showDebugOverlayMessage('父页面: 下键，循环到第一个焦点');
            } else {
              _requestFocus(currentIndex + 1);
              _showDebugOverlayMessage('父页面: 下键，切换到下一个焦点');
            }
          }
        } else if (widget.frameType == "child") {
          // 如果 frameType 是 "child"
          if (key == LogicalKeyboardKey.arrowLeft) {
            // 左键：切换到父页面
            _jumpToOtherGroup(key, currentIndex, 1);
            _showDebugOverlayMessage('子页面: 左键，切换到父页面');
          } else if (key == LogicalKeyboardKey.arrowRight) {
            // 右键：前进（如果到达边界则循环焦点）
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
              _showDebugOverlayMessage('子页面: 右键，循环到第一个焦点');
            } else {
              _requestFocus(currentIndex + 1);
              _showDebugOverlayMessage('子页面: 右键，切换到下一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
            // 上键或下键：切换分组
            _jumpToOtherGroup(key, currentIndex, groupIndex);
            _showDebugOverlayMessage('子页面: ${key == LogicalKeyboardKey.arrowUp ? '上' : '下'}键，切换分组');
          }
        }
      } else {  // 如果没有启用框架模式
        if (widget.isHorizontalGroup) {
          // 横向分组逻辑
          if (key == LogicalKeyboardKey.arrowLeft) {
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
              _showDebugOverlayMessage('横向组: 左键，循环到最后一个焦点');
            } else {
              _requestFocus(currentIndex - 1);
              _showDebugOverlayMessage('横向组: 左键，切换到前一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowRight) {
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
              _showDebugOverlayMessage('横向组: 右键，循环到第一个焦点');
            } else {
              _requestFocus(currentIndex + 1);
              _showDebugOverlayMessage('横向组: 右键，切换到下一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
            // 上键或下键：切换分组
            _jumpToOtherGroup(key, currentIndex, groupIndex);
            _showDebugOverlayMessage('横向组: ${key == LogicalKeyboardKey.arrowUp ? '上' : '下'}键，切换分组');
          }
        } else if (widget.isVerticalGroup) {
          // 竖向分组逻辑
          if (key == LogicalKeyboardKey.arrowUp) {
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
              _showDebugOverlayMessage('竖向组: 上键，循环到最后一个焦点');
            } else {
              _requestFocus(currentIndex - 1);
              _showDebugOverlayMessage('竖向组: 上键，切换到前一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowDown) {
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
              _showDebugOverlayMessage('竖向组: 下键，循环到第一个焦点');
            } else {
              _requestFocus(currentIndex + 1);
              _showDebugOverlayMessage('竖向组: 下键，切换到下一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
            // 左键或右键：切换分组
            _jumpToOtherGroup(key, currentIndex, groupIndex);
            _showDebugOverlayMessage('竖向组: ${key == LogicalKeyboardKey.arrowLeft ? '左' : '右'}键，切换分组');
          }
        } else {
          // 没有启用分组的默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
              _showDebugOverlayMessage('默认导航: ${key == LogicalKeyboardKey.arrowUp ? '上' : '左'}键，循环到最后一个焦点');
            } else {
              _requestFocus(currentIndex - 1);
              _showDebugOverlayMessage('默认导航: ${key == LogicalKeyboardKey.arrowUp ? '上' : '左'}键，切换到前一个焦点');
            }
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
              _showDebugOverlayMessage('默认导航: ${key == LogicalKeyboardKey.arrowDown ? '下' : '右'}键，循环到第一个焦点');
            } else {
              _requestFocus(currentIndex + 1);
              _showDebugOverlayMessage('默认导航: ${key == LogicalKeyboardKey.arrowDown ? '下' : '右'}键，切换到下一个焦点');
            }
          }
        }
      }
    } catch (e) {
      _showDebugOverlayMessage('焦点切换错误: $e');
    }

    // 调用选择回调
    FocusNode? currentFocusNode = FocusScope.of(context).focusedChild as FocusNode?;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex); // 只有在新焦点与当前焦点不同的时候调用回调
      }
    }

    return KeyEventResult.handled;
  }

  /// 获取当前焦点所属的 groupIndex
  int _getGroupIndex(BuildContext context) {
    // 优化：使用缓存的 Group 实例
    if (_cachedGroup == null) {
      _cachedGroup = context.findAncestorWidgetOfExactType<Group>();
    }
    return _cachedGroup?.groupIndex ?? -1; // 未找到 Group 时返回 -1
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (groupIndex == null || groupIndex == -1) return false;

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
        _showDebugOverlayMessage('切换到组 $nextGroupIndex 的第一个焦点');
        return true;
      }
    }

    _showDebugOverlayMessage('无法找到下一个组或其焦点');
    return false;
  }

  /// 根据 groupIndex 查找对应的 Group
  Group? _findGroupByIndex(int groupIndex) {
    RenderObject? ancestor = context.findRenderObject();
    Group? targetGroup;
    if (ancestor != null) {
      ancestor.visitChildren((child) {
        final group = context.findAncestorWidgetOfExactType<Group>();
        if (group != null && group.groupIndex == groupIndex) {
          targetGroup = group;
        }
      });
    }
    return targetGroup;
  }

  /// 查找 Group 下的第一个 FocusNode
  FocusNode? _findFirstFocusNodeInGroup(Group group) {
    for (Widget child in group.children) {
      if (child is FocusableItem) {
        return child.focusNode; // 返回第一个 FocusableItem 的 FocusNode
      }
    }
    return null; // 没有找到 FocusNode
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return widget.focusNodes.length;
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
        _showDebugOverlayMessage('选择键操作: ${key.debugName}');
        return KeyEventResult.handled; // 标记按键事件已处理
      }

      // 自定义的按键处理回调
      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
        _showDebugOverlayMessage('自定义按键回调: ${key.debugName}');
      }
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
          listTile.onTap!(); // 调用 ListTile 的 onTap 回调
          _showDebugOverlayMessage('执行 ListTile 的 onTap 操作');
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true, // 自动聚焦
      onKey: _handleKeyEvent, // 处理键盘事件
      child: widget.child, // 直接使用传入的子组件，不改变原有布局
    );
  }
}

class Group extends StatelessWidget {
  final int groupIndex; // 分组编号
  final List<Widget> children;

  // Group 组件用于将一组 FocusableItem 组件分组，如果开启 isHorizontalGroup 或 isVerticalGroup 参数，
  // 使得焦点可以在分组内切换，限制焦点在不同的分组之间移动。
  // groupIndex（开启分组的话必填）：分组编号，用于标识当前分组，焦点切换时可以根据这个编号来识别分组。
  // children（开启分组的话必填）：需要被分组的子组件列表，通常这些组件会是 FocusableItem。

  const Group({
    Key? key,
    required this.groupIndex,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children,
    );
  }
}

// 用于包装具有焦点的组件
class FocusableItem extends StatefulWidget {
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件

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
    return widget.child; // 直接返回子组件，不做样式修改
  }
}
