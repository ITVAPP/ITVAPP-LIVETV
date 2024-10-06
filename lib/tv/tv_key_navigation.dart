import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 通用的 TV 焦点管理和按键处理组件
class TvKeyNavigation extends StatefulWidget {
  final List<Widget> focusableWidgets; // 可聚焦的控件
  final int initialIndex; // 初始焦点索引
  final Function(int index)? onSelect; // 选中回调
  final Function(LogicalKeyboardKey key, int currentIndex)? onKeyPressed; // 自定义按键处理
  final double spacing; // 控件间的间距
  final bool loopFocus; // 是否允许焦点循环切换

  const TvKeyNavigation({
    Key? key,
    required this.focusableWidgets,
    this.initialIndex = 0,
    this.onSelect,
    this.onKeyPressed,
    this.spacing = 8.0,
    this.loopFocus = true,
  })  : assert(focusableWidgets.length > 0, "必须提供至少一个可聚焦控件"),
        super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> {
  late List<FocusNode> _focusNodes; // 焦点节点列表
  late int _currentIndex; // 当前聚焦的控件索引
  late List<GlobalKey> _widgetKeys; // 每个控件对应的 GlobalKey，用于获取位置
  late List<Offset?> _cachedPositions; // 缓存的控件位置

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initializeFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheWidgetPositions(); // 首次加载后缓存控件位置
      _requestFocus(_currentIndex);
    });
  }

  /// 初始化 FocusNodes 和 GlobalKey
  void _initializeFocusNodes() {
    _focusNodes = List.generate(widget.focusableWidgets.length, (_) => FocusNode());
    _widgetKeys = List.generate(widget.focusableWidgets.length, (_) => GlobalKey());
    _cachedPositions = List.filled(widget.focusableWidgets.length, null);
  }

  /// 请求焦点
  void _requestFocus(int index) {
    if (_focusNodes.isNotEmpty && index >= 0 && index < _focusNodes.length) {
      FocusScope.of(context).requestFocus(_focusNodes[index]);
    }
  }

  /// 缓存所有控件的位置
  void _cacheWidgetPositions() {
    for (int i = 0; i < _widgetKeys.length; i++) {
      final context = _widgetKeys[i].currentContext;
      if (context != null) {
        final renderBox = context.findRenderObject() as RenderBox;
        _cachedPositions[i] = renderBox.localToGlobal(Offset.zero);
      }
    }
  }

  /// 捕获并处理上下左右键、选择键等按键事件
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

      // 如果用户提供了自定义按键处理，则调用
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
    }
    return KeyEventResult.ignored;
  }

  /// 焦点切换逻辑，基于控件的全局坐标位置处理
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentPosition = _cachedPositions[_currentIndex];

    if (currentPosition == null) {
      return KeyEventResult.ignored;
    }

    int? nextIndex;
    double closestDistance = double.infinity;

    for (int i = 0; i < _cachedPositions.length; i++) {
      if (i == _currentIndex) continue;

      final position = _cachedPositions[i];
      if (position == null) continue;

      double dx = position.dx - currentPosition.dx;
      double dy = position.dy - currentPosition.dy;

      // 判断按键方向并找到最近的控件
      if ((key == LogicalKeyboardKey.arrowUp && dy < 0) ||
          (key == LogicalKeyboardKey.arrowDown && dy > 0) ||
          (key == LogicalKeyboardKey.arrowLeft && dx < 0) ||
          (key == LogicalKeyboardKey.arrowRight && dx > 0)) {
        double distance = dx * dx + dy * dy;
        if (distance < closestDistance) {
          closestDistance = distance;
          nextIndex = i;
        }
      }
    }

    if (nextIndex != null && nextIndex != _currentIndex) {
      setState(() {
        _currentIndex = nextIndex!;
      });
      _requestFocus(nextIndex!);
      return KeyEventResult.handled;
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
        child: Column(
          children: List.generate(widget.focusableWidgets.length, (index) {
            return Padding(
              padding: EdgeInsets.all(widget.spacing),
              child: FocusableItem( // 使用自定义的 FocusableItem 处理焦点样式变化
                focusNode: _focusNodes[index],
                isFocused: _currentIndex == index, // 判断当前是否聚焦
                child: widget.focusableWidgets[index],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// 自定义组件，用于处理聚焦时的样式变化
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
      onFocusChange: (focused) {
        // 焦点变化时触发样式更新
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200), // 平滑过渡效果
        decoration: BoxDecoration(
          color: isFocused ? Color(0xFFEB144C) : Colors.transparent, // 聚焦时的背景颜色
          border: isFocused
              ? Border.all(color: Color(0xFFB01235), width: 3.0) // 聚焦时的边框颜色
              : null, // 聚焦时的边框
        ),
        child: child,
      ),
    );
  }
}
