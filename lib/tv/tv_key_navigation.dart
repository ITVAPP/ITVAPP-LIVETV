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
  final currentPosition = positions[currentIndex];
  if (currentPosition == null) return currentIndex; // 如果找不到当前位置，不切换

  Offset? nextPosition;
  int? nextIndex;
  double closestDistance = double.infinity; // 记录距离当前焦点最近的控件距离

  // 遍历所有控件位置，找到符合方向的下一个焦点
  for (int i = 0; i < positions.length; i++) {
    if (i == currentIndex || positions[i] == null) continue; // 跳过当前焦点和无效位置

    final position = positions[i]!;
    final dx = position.dx - currentPosition.dx;
    final dy = position.dy - currentPosition.dy;

    // 判断目标控件是否在按键方向上
    bool isInDirection = false;
    if (key == LogicalKeyboardKey.arrowUp && dy < 0 && dx.abs() < dy.abs()) {
      isInDirection = true;
    } else if (key == LogicalKeyboardKey.arrowDown && dy > 0 && dx.abs() < dy.abs()) {
      isInDirection = true;
    } else if (key == LogicalKeyboardKey.arrowLeft && dx < 0 && dy.abs() < dx.abs()) {
      isInDirection = true;
    } else if (key == LogicalKeyboardKey.arrowRight && dx > 0 && dy.abs() < dx.abs()) {
      isInDirection = true;
    }

    // 更新最近的符合方向的控件
    if (isInDirection) {
      double distance = dx * dx + dy * dy; // 计算欧几里得距离
      if (distance < closestDistance) {
        closestDistance = distance;
        nextPosition = position;
        nextIndex = i;
      }
    }
  }

  // 返回找到的下一个焦点索引，如果没有则返回当前索引
  return nextIndex ?? currentIndex; 
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
  late List<Offset?> _cachedPositions; // 缓存每个焦点控件的屏幕位置

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.focusNodes.length - 1); // 设置初始焦点位置，确保索引有效
    _cachedPositions = List.filled(widget.focusNodes.length, null); // 初始化位置缓存
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheWidgetPositions(); // 在组件布局后缓存控件位置
      _requestFocus(_currentIndex); // 请求焦点
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _cacheWidgetPositions(); // 当窗口大小变化时，重新缓存控件位置
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    if (widget.focusNodes.isNotEmpty && index >= 0 && index < widget.focusNodes.length) {
      FocusScope.of(context).requestFocus(widget.focusNodes[index]);
    }
  }

  /// 缓存每个控件的位置，以便用于自定义导航策略。
  void _cacheWidgetPositions() {
    for (int i = 0; i < widget.focusNodes.length; i++) {
      final context = widget.focusNodes[i].context;
      if (context != null) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          _cachedPositions[i] = renderBox.localToGlobal(Offset.zero); // 获取控件的全局位置
        } else {
          _cachedPositions[i] = null; // 确保无效位置不会影响导航逻辑
        }
      } else {
        _cachedPositions[i] = null; // 确保无效位置不会影响导航逻辑
      }
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    int nextIndex = widget.navigationPolicy(_currentIndex, key, _cachedPositions);

    // 处理边界情况：循环焦点或切换到框架焦点
    if ((widget.loopFocus || widget.isFrame) && _isAtEdge(key)) {
      if (widget.isFrame) {
        FocusScope.of(context).nextFocus(); // 切换到下一个焦点
      } else if (widget.loopFocus) {
        // 在边界时循环回到起始或结束
        nextIndex = (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown)
            ? 0
            : widget.focusNodes.length - 1;
      }
    }

    // 确保索引在有效范围内
    nextIndex = nextIndex.clamp(0, widget.focusNodes.length - 1);

    // 更新焦点位置并请求焦点
    setState(() {
      _currentIndex = nextIndex;
    });
    _requestFocus(nextIndex);

    return KeyEventResult.handled; // 标记按键事件已处理
  }

  /// 判断当前焦点是否在边界位置。
  bool _isAtEdge(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      return _currentIndex == 0; // 左边界或上边界
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
      return _currentIndex == widget.focusNodes.length - 1; // 右边界或下边界
    }
    return false;
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
