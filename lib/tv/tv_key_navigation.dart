import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 通用的 TV 焦点管理和按键处理组件
class TvKeyNavigation extends StatefulWidget {
  final List<Widget> focusableWidgets; // 可聚焦的控件
  final int initialIndex; // 初始焦点索引
  final Function(int index)? onSelect; // 选中回调
  final Function(LogicalKeyboardKey key, int currentIndex)? onKeyPressed; // 自定义按键处理
  final double spacing; // 控件间的间距
  final bool loopFocus; // 是否允许焦点循环切换，默认为 true
  final bool isFrame; // 是否是框架模式

  const TvKeyNavigation({
    Key? key,
    required this.focusableWidgets,
    this.initialIndex = 0,
    this.onSelect,
    this.onKeyPressed,
    this.spacing = 8.0,
    this.loopFocus = true, // 设置默认值为 true
    this.isFrame = false, // 默认不是框架模式
  })  : assert(focusableWidgets.length > 0, "必须提供至少一个可聚焦控件"),
        super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  late List<FocusNode> _focusNodes; // 焦点节点列表
  late int _currentIndex; // 当前聚焦的控件索引

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initializeFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFocus(_currentIndex);
    });

    // 添加监听窗口变化的 observer
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 移除监听窗口变化的 observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 初始化 FocusNodes
  void _initializeFocusNodes() {
    _focusNodes = List.generate(widget.focusableWidgets.length, (_) => FocusNode());
  }

  /// 请求焦点
  void _requestFocus(int index) {
    if (_focusNodes.isNotEmpty && index >= 0 && index < _focusNodes.length) {
      FocusScope.of(context).requestFocus(_focusNodes[index]);
    }
  }

  /// 判断是否在页面边缘，用于处理跨框架切换
  bool _isAtEdge(LogicalKeyboardKey key) {
    return (key == LogicalKeyboardKey.arrowUp && _currentIndex == 0) ||
           (key == LogicalKeyboardKey.arrowDown && _currentIndex == _focusNodes.length - 1) ||
           (key == LogicalKeyboardKey.arrowLeft && _currentIndex == 0) ||
           (key == LogicalKeyboardKey.arrowRight && _currentIndex == _focusNodes.length - 1);
  }

  /// 焦点切换逻辑，基于控件的顺序实现循环切换和跨框架切换
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    int nextIndex = _currentIndex;

    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
      nextIndex = (_currentIndex + 1) % _focusNodes.length; // 向右或向下循环
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      nextIndex = (_currentIndex - 1 + _focusNodes.length) % _focusNodes.length; // 向左或向上循环
    }

    if (widget.loopFocus || widget.isFrame) {
      // 处理循环切换
      if (_isAtEdge(key)) {
        if (widget.isFrame) {
          // 跨框架焦点切换
          FocusScope.of(context).nextFocus();
        } else if (widget.loopFocus) {
          // 焦点循环切换
          nextIndex = (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown)
              ? 0 // 从第一个开始
              : _focusNodes.length - 1; // 从最后一个开始
        }
      }
    }

    setState(() {
      _currentIndex = nextIndex;
    });
    _requestFocus(nextIndex);
    return KeyEventResult.handled;
  }

  /// 捕获并处理上下左右键、选择键、菜单键等按键事件
  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      LogicalKeyboardKey key = event.logicalKey;

      // 如果是导航键，进行处理
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        return _handleNavigation(key); // 处理焦点切换
      }

      // 如果提供了自定义按键处理，则调用
      if (widget.onKeyPressed != null) {
        widget.onKeyPressed!(key, _currentIndex);
      }

      // 处理选中操作
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        if (widget.onSelect != null) {
          widget.onSelect!(_currentIndex); // 调用选中回调
        }
        return KeyEventResult.handled;
      }

      // 阻止菜单键的冒泡
      if (key == LogicalKeyboardKey.contextMenu) {
        return KeyEventResult.handled; // 阻止菜单键冒泡
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(), // 控制焦点顺序
      child: FocusScope(
        autofocus: true, // 自动聚焦第一个控件
        onKey: _handleKeyEvent, // 处理按键事件
        child: Wrap( // 支持复杂布局
          spacing: widget.spacing, // 控件之间的间距
          runSpacing: widget.spacing,
          children: List.generate(widget.focusableWidgets.length, (index) {
            return FocusableItem(
              focusNode: _focusNodes[index],
              isFocused: _currentIndex == index, // 判断当前是否聚焦
              child: widget.focusableWidgets[index],
            );
          }),
        ),
      ),
    );
  }
}

/// 处理聚焦时的样式变化
class FocusableItem extends StatelessWidget {
  final FocusNode focusNode;
  final bool isFocused;
  final Widget child;

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
        duration: Duration(milliseconds: 200), // 平滑过渡效果
        decoration: BoxDecoration(
          color: isFocused ? Color(0xFFEB144C) : Colors.transparent, // 聚焦时背景颜色
          border: isFocused
              ? Border.all(color: Color(0xFFB01235), width: 3.0) // 聚焦时边框
              : null,
          boxShadow: isFocused
              ? [BoxShadow(color: Colors.black26, blurRadius: 10.0)] // 聚焦时阴影效果
              : [],
        ),
        child: child,
      ),
    );
  }
}
