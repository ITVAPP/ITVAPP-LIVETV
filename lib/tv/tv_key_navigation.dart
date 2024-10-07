import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 定义 NavigationPolicy 类型，用于自定义导航策略。
typedef NavigationPolicy = int Function(
  int currentIndex,
  LogicalKeyboardKey key,
  List<Offset?> positions,
);

/// 自定义导航策略：根据上下左右是否有控件来决定焦点切换。
/// [currentIndex] 当前焦点位置的索引。
/// [key] 用户按下的方向键。
/// [positions] 所有焦点控件的位置列表，每个位置用 Offset 表示。
/// 返回下一个焦点控件的索引。
int directionBasedNavigationPolicy(int currentIndex, LogicalKeyboardKey key, List<Offset?> positions) {
  return currentIndex; // 使用系统默认的焦点切换机制，不再自定义
}

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final int initialIndex; // 初始焦点位置的索引
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key, int currentIndex)? onKeyPressed; // 按键时的回调
  final bool loopFocus; // 是否在边界时循环焦点
  final bool isFrame; // 是否启用框架模式，用于切换焦点
  final NavigationPolicy navigationPolicy; // 自定义导航策略

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes, 
    this.initialIndex = 0,
    this.onSelect,
    this.onKeyPressed,
    this.loopFocus = true,
    this.isFrame = false,
    this.navigationPolicy = directionBasedNavigationPolicy,
  }) : super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  late int _currentIndex; // 当前焦点位置的索引

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.focusNodes.length - 1); // 设置初始焦点位置，确保索引有效
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFocus(_currentIndex); // 请求焦点
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
      FocusScope.of(context).requestFocus(widget.focusNodes[index]);
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    // 使用系统的焦点切换机制，而不是自定义
    if (key == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).previousFocus(); // 上一个焦点
    } else if (key == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).nextFocus(); // 下一个焦点
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      FocusScope.of(context).previousFocus(); // 左侧焦点
    } else if (key == LogicalKeyboardKey.arrowRight) {
      FocusScope.of(context).nextFocus(); // 右侧焦点
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

      // 自定义的按键处理回调
      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key, _currentIndex);
      }

      // 处理选择键（如 Enter 键）
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        // 如果当前聚焦控件有点击操作，则自动触发点击
        final context = widget.focusNodes[_currentIndex].context;
        if (context != null) {
          final gestureDetector = context.findAncestorWidgetOfExactType<GestureDetector>();
          if (gestureDetector != null && gestureDetector.onTap != null) {
            gestureDetector.onTap!(); // 触发点击事件
          }
        }
        return KeyEventResult.handled; // 标记按键事件已处理
      }
    }
    return KeyEventResult.ignored; // 如果未处理，返回忽略
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(), // 使用默认的焦点遍历策略
      child: Focus(
        autofocus: true, // 自动聚焦
        onKey: _handleKeyEvent, // 处理键盘事件
        child: widget.child, // 直接使用传入的子组件，不改变原有布局
      ),
    );
  }
}

// FocusableItem 类，用于包装具有焦点的组件
class FocusableItem extends StatelessWidget {
  final FocusNode focusNode; // 焦点节点
  final bool isFocused; // 是否当前聚焦
  final Widget child; // 子组件

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.isFocused,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200), // 焦点状态变化时的动画时长
        decoration: BoxDecoration(
          color: isFocused ? Color(0xFFEB144C) : Colors.transparent, // 聚焦时背景色变化
          border: isFocused
              ? Border.all(color: Color(0xFFB01235), width: 2.0) // 聚焦时显示边框
              : null,
          boxShadow: isFocused
              ? [BoxShadow(color: Colors.black26, blurRadius: 10.0)] // 聚焦时添加阴影效果
              : [],
        ),
        child: child, // 包装的子组件
      ),
    );
  }
}
