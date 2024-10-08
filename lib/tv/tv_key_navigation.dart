import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final int? initialIndex; // 初始焦点的索引，默认为空，如果为空则使用自动聚焦

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.onSelect,
    this.onKeyPressed,
    this.initialIndex,
  }) : super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? get _currentFocus => FocusScope.of(context).focusedChild as FocusNode?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 如果 initialIndex 不为空且在范围内，则手动请求焦点
      if (widget.initialIndex != null &&
          widget.initialIndex! >= 0 &&
          widget.initialIndex! < widget.focusNodes.length) {
        _requestFocus(widget.initialIndex!);
      } else {
        _requestFocus(0); // 如果没有提供 initialIndex 或不在范围内，则默认聚焦第一个
      }
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    super.dispose();
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    if (widget.focusNodes.isNotEmpty && index >= 0 && index < widget.focusNodes.length) {
      widget.focusNodes[index].requestFocus();
    }
  }

  /// 使用 `FocusTraversalGroup` 和 `ReadingOrderTraversalPolicy` 实现基于方向键的焦点移动
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return KeyEventResult.ignored; // 没有焦点时忽略

    // 使用 ReadingOrderTraversalPolicy 进行方向键导航
    FocusTraversalPolicy? traversalPolicy = FocusTraversalGroup.maybeOf(context);
    if (traversalPolicy != null) {
      if (key == LogicalKeyboardKey.arrowUp) {
        traversalPolicy.inDirection(currentFocus!, TraversalDirection.up);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        traversalPolicy.inDirection(currentFocus!, TraversalDirection.down);
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        traversalPolicy.inDirection(currentFocus!, TraversalDirection.left);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        traversalPolicy.inDirection(currentFocus!, TraversalDirection.right);
      }
    }

    // 调用选择回调
    FocusNode? currentFocusNode = FocusScope.of(context).focusedChild as FocusNode?;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != widget.focusNodes.indexOf(currentFocus)) {
        widget.onSelect!(newIndex);  // 确保只有在新焦点与当前焦点不同的时候调用回调
      }
    }

    return KeyEventResult.handled;
  }

  /// 处理键盘事件，包括方向键和选择键。
  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      LogicalKeyboardKey key = event.logicalKey;

      // 如果按下方向键，则进行导航
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        return _handleNavigation(key);
      }

      // 处理选择键（如 Enter 键）
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        _triggerButtonAction(); // 直接调用方法触发按钮操作
        return KeyEventResult.handled; // 标记按键事件已处理
      }

      // 自定义的按键处理回调
      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
      }
    }
    return KeyEventResult.ignored; // 如果未处理，返回忽略
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
          return;
        }
      }

      // 检查是否存在具有 onTap 回调的 FocusableItem 并调用其回调
      final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();
      if (focusableItem != null && focusableItem.child is ListTile) {
        final listTile = focusableItem.child as ListTile;
        if (listTile.onTap != null) {
          listTile.onTap!(); // 调用 ListTile 的 onTap 回调
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(), // 使用 ReadingOrderTraversalPolicy 策略
      child: Focus(
        autofocus: true, // 自动聚焦
        onKey: _handleKeyEvent, // 处理键盘事件
        child: widget.child, // 直接使用传入的子组件，不改变原有布局
      ),
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
