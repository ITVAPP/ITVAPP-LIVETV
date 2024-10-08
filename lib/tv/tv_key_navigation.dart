import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final bool loopFocus; // 是否在边界时循环焦点
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
    this.loopFocus = true,
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

  /// 判断当前焦点是否在边界
  bool _isAtEdge(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return false; // 如果没有焦点，直接返回 false

    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) return false;

    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
        return currentIndex == 0; // 左边界或上边界
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        return currentIndex == widget.focusNodes.length - 1; // 右边界或下边界
      default:
        return false;
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return KeyEventResult.ignored; // 没有焦点时忽略

    int currentIndex = widget.focusNodes.indexOf(currentFocus);

    if (widget.isFrame && _isAtEdge(key)) {
      // 新增：根据 frameType 判断是父页面还是子页面
      if (widget.frameType == "parent" && key == LogicalKeyboardKey.arrowRight) {
        // 父页面：在右边界时跨越到另一个框架的第一个焦点
        FocusScope.of(context).nextFocus();
        return KeyEventResult.handled;
      } else if (widget.frameType == "child" && key == LogicalKeyboardKey.arrowLeft) {
        // 子页面：在左边界时跨越到另一个框架的第一个焦点
        FocusScope.of(context).nextFocus();
        return KeyEventResult.handled;
      } else {
        // 如果 frameType 无效，则回退到默认的框架处理逻辑
        if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(context).nextFocus();
        } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(context).previousFocus();
        }
      }
    } else {
      // 根据分组信息处理焦点切换逻辑
      if (widget.isHorizontalGroup) {
        _handleHorizontalGroupNavigation(key, currentIndex);
      } else if (widget.isVerticalGroup) {
        _handleVerticalGroupNavigation(key, currentIndex);
      } else {
        // 非分组模式下的默认导航逻辑
        if (_isAtEdge(key) && widget.loopFocus) {
          if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
            _requestFocus(0); // 循环到第一个控件
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
            _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个控件
          }
        } else {
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
            FocusScope.of(context).previousFocus(); // 上一个或左侧焦点
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
            FocusScope.of(context).nextFocus(); // 下一个或右侧焦点
          }
        }
      }
    }

    // 调用选择回调
    FocusNode? currentFocusNode = FocusScope.of(context).focusedChild as FocusNode?;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex);  // 确保只有在新焦点与当前焦点不同的时候调用回调
      }
    }

    return KeyEventResult.handled;
  }

  /// 横向分组切换逻辑
  void _handleHorizontalGroupNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      FocusScope.of(context).nextFocus(); // 在横向分组内切换
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      // 切换到其他横向分组的第一个控件（自定义逻辑可扩展）
      _jumpToOtherGroup(key, currentIndex);
    }
  }

  /// 竖向分组切换逻辑
  void _handleVerticalGroupNavigation(LogicalKeyboardKey key, int currentIndex) {
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).nextFocus(); // 在竖向分组内切换
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      // 切换到其他竖向分组的第一个控件（自定义逻辑可扩展）
      _jumpToOtherGroup(key, currentIndex);
    }
  }

  /// 处理在组之间的跳转逻辑
  void _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex) {
    // 自定义逻辑：根据分组信息跳到下一个分组的第一个控件
    // 例如：_requestFocus(根据分组信息计算出的下一个分组的第一个控件的索引);
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
    return Focus(
      autofocus: true, // 自动聚焦
      onKey: _handleKeyEvent, // 处理键盘事件
      child: widget.child, // 直接使用传入的子组件，不改变原有布局
    );
  }
}

// 用于包装具有焦点的组件
class FocusableItem extends StatefulWidget {
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件

  // 新增：分组信息（行号或列号）
  final int? groupIndex; // 当前控件所属的分组编号（可为空）

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
    this.groupIndex, // 分组信息可选
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
