import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Function(int index)? onSelect; // 选择某个焦点时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键时的回调
  final bool loopFocus; // 是否在边界时循环焦点
  final bool isFrame; // 是否启用框架模式，用于切换焦点
  final int? initialIndex; // 初始焦点的索引，默认为空，如果为空则使用自动聚焦

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.onSelect,
    this.onKeyPressed,
    this.loopFocus = true,
    this.isFrame = false,
    this.initialIndex, // 添加了 initialIndex 参数
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
      FocusScope.of(context).requestFocus(widget.focusNodes[index]);
    }
  }

  /// 判断当前焦点是否在边界
  bool _isAtEdge(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return false; // 如果没有焦点，直接返回 false

    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) return false;

    if ((key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) && currentIndex == 0) {
      return true; // 左边界或上边界
    } else if ((key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) && currentIndex == widget.focusNodes.length - 1) {
      return true; // 右边界或下边界
    }
    return false;
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return KeyEventResult.ignored; // 没有焦点时忽略

    int currentIndex = widget.focusNodes.indexOf(currentFocus);

    if (widget.isFrame && _isAtEdge(key)) {
      // 框架模式下，当焦点在边界时切换到其他框架
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
        FocusScope.of(context).nextFocus();
      } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
        FocusScope.of(context).previousFocus();
      }
    } else {
      // 非框架模式下，处理循环焦点
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
        widget.onKeyPressed!(key);
      }

      // 处理选择键（如 Enter 键），使用官方推荐的 Actions 和 Shortcuts
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        Actions.invoke(context, const ActivateIntent()); // 使用 Actions 处理点击
        return KeyEventResult.handled; // 标记按键事件已处理
      }
    }
    return KeyEventResult.ignored; // 如果未处理，返回忽略
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(), // 使用默认的焦点遍历策略
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(), // 绑定 Enter 键
          LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(), // 绑定 Select 键
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (Intent intent) {
                // 在焦点控件上触发点击操作
                final context = _currentFocus?.context;
                if (context != null) {
                  final gestureDetector = context.findAncestorWidgetOfExactType<GestureDetector>();
                  if (gestureDetector != null && gestureDetector.onTap != null) {
                    gestureDetector.onTap!(); // 触发点击事件
                  }
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true, // 自动聚焦
            onKey: _handleKeyEvent, // 处理键盘事件
            child: widget.child, // 直接使用传入的子组件，不改变原有布局
          ),
        ),
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
        duration: const Duration(milliseconds: 200), // 焦点状态变化时的动画时长
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFFEB144C) : Colors.transparent, // 聚焦时背景色变化
          border: isFocused
              ? Border.all(color: const Color(0xFFB01235), width: 2.0) // 聚焦时显示边框
              : null,
          boxShadow: isFocused
              ? [const BoxShadow(color: Colors.black26, blurRadius: 10.0)] // 聚焦时添加阴影效果
              : [],
        ),
        child: child, // 包装的子组件
      ),
    );
  }
}
