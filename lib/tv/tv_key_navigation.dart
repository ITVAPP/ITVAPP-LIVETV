import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final bool loopFocus; // 是否在边界时循环焦点
  // 如果 frameIdentifier 为 'parent'，且焦点在最右侧，则按右键时会跨域到下一个框架。
  // 如果 frameIdentifier 为 'child'，且焦点在最左侧，则按左键时会跨域到上一个框架。
  final String? frameIdentifier; // 用于区分父框架和子框架的标识
  final int? initialIndex; // 初始焦点的索引，默认为空，如果为空则使用自动聚焦

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.onSelect,
    this.onKeyPressed,
    this.loopFocus = true,
    this.frameIdentifier,
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

  /// 获取控件位置
  Offset _getOffset(FocusNode focusNode) {
    final context = focusNode.context;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        return renderBox.localToGlobal(Offset.zero);
      }
    }
    return Offset.zero;
  }

  /// 找到最接近的上下方向的焦点索引
  int _findClosestVerticalIndex(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return -1;

    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) return -1;

    Offset currentOffset = _getOffset(currentFocus);
    double shortestDistance = double.infinity;
    int closestIndex = currentIndex;

    for (int i = 0; i < widget.focusNodes.length; i++) {
      if (i == currentIndex) continue;

      Offset targetOffset = _getOffset(widget.focusNodes[i]);
      double distance;

      if (key == LogicalKeyboardKey.arrowUp) {
        if (targetOffset.dy < currentOffset.dy) {
          distance = (currentOffset.dy - targetOffset.dy).abs() +
                     (currentOffset.dx - targetOffset.dx).abs();
          if (distance < shortestDistance) {
            shortestDistance = distance;
            closestIndex = i;
          }
        }
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (targetOffset.dy > currentOffset.dy) {
          distance = (targetOffset.dy - currentOffset.dy).abs() +
                     (currentOffset.dx - targetOffset.dx).abs();
          if (distance < shortestDistance) {
            shortestDistance = distance;
            closestIndex = i;
          }
        }
      }
    }

    return closestIndex;
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    int nextIndex = -1; // 初始化 nextIndex，确保有默认值

    // 处理上下方向键，基于控件位置选择最近的焦点
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      nextIndex = _findClosestVerticalIndex(key);

      // 如果找不到上下方向的焦点，则按左右的逻辑处理
      if (nextIndex == -1 || nextIndex == widget.focusNodes.indexOf(_currentFocus!)) {
        if (key == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(context).previousFocus();
        } else if (key == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(context).nextFocus();
        }
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      // 处理右键跨越框架逻辑
      if (widget.frameIdentifier == 'parent') {
        int currentIndex = widget.focusNodes.indexOf(_currentFocus!);
        if (currentIndex == widget.focusNodes.length - 1) {
          FocusScope.of(context).nextFocus(); // 如果在父框架并且是最右边，跨域到下一个框架
        } else {
          FocusScope.of(context).nextFocus(); // 否则继续在当前框架内移动
        }
      } else {
        FocusScope.of(context).nextFocus(); // 默认行为
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      // 处理左键跨越框架逻辑
      if (widget.frameIdentifier == 'child') {
        int currentIndex = widget.focusNodes.indexOf(_currentFocus!);
        if (currentIndex == 0) {
          FocusScope.of(context).previousFocus(); // 如果在子框架并且是最左边，跨域到上一个框架
        } else {
          FocusScope.of(context).previousFocus(); // 否则继续在当前框架内移动
        }
      } else {
        FocusScope.of(context).previousFocus(); // 默认行为
      }
    } else {
      // 如果按键不在上下左右范围内，返回忽略
      return KeyEventResult.ignored;
    }

    // 切换焦点到计算出的目标控件
    if (nextIndex != -1 && nextIndex != widget.focusNodes.indexOf(_currentFocus!)) {
      _requestFocus(nextIndex);
      if (widget.onSelect != null) {
        widget.onSelect!(nextIndex);
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
        _triggerButtonAction();
        return KeyEventResult.handled;
      }

      // 自定义的按键处理回调
      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key);
      }
    }
    return KeyEventResult.ignored;
  }

  /// 执行当前焦点控件的点击操作或切换开关状态。
  void _triggerButtonAction() {
    final context = _currentFocus?.context;
    if (context != null) {
      // 检查是否是 SwitchListTile 并切换其状态
      final switchTile = context.findAncestorWidgetOfExactType<SwitchListTile>();
      if (switchTile != null) {
        final value = !(switchTile.value ?? false);
        switchTile.onChanged?.call(value);
        return;
      }

      // 检查是否有带 onPressed 的按钮类型组件
      final button = context.findAncestorWidgetOfExactType<ElevatedButton>() ??
          context.findAncestorWidgetOfExactType<TextButton>() ??
          context.findAncestorWidgetOfExactType<OutlinedButton>();

      if (button != null) {
        final onPressed = button.onPressed;
        if (onPressed != null) {
          onPressed();
          return;
        }
      }

      // 检查是否是 ListTile 并调用其 onTap 回调
      final listTile = context.findAncestorWidgetOfExactType<ListTile>();
      if (listTile != null && listTile.onTap != null) {
        listTile.onTap!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKey: _handleKeyEvent,
      child: widget.child,
    );
  }
}
