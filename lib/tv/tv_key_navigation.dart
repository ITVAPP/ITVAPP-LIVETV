import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 自定义导航策略，用于在复杂布局中处理上下左右键切换
typedef NavigationPolicy = int Function(int currentIndex, LogicalKeyboardKey key, List<Offset?> positions);

/// 默认导航策略：基于最短距离的上下左右键切换
int defaultNavigationPolicy(int currentIndex, LogicalKeyboardKey key, List<Offset?> positions) {
  final currentPosition = positions[currentIndex];
  if (currentPosition == null) return currentIndex; // 如果找不到位置，不切换

  int? nextIndex;
  double closestDistance = double.infinity;

  for (int i = 0; i < positions.length; i++) {
    if (i == currentIndex || positions[i] == null) continue;
    final position = positions[i]!;
    double dx = position.dx - currentPosition.dx;
    double dy = position.dy - currentPosition.dy;

    // 判断按键方向并找到最接近的控件
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

  return nextIndex ?? currentIndex;
}

class TvKeyNavigation extends StatefulWidget {
  final List<Widget> focusableWidgets; // 可聚焦的控件
  final int initialIndex; // 初始焦点索引
  final Function(int index)? onSelect; // 选中回调
  final Function(LogicalKeyboardKey key, int currentIndex)? onKeyPressed; // 自定义按键处理
  final double spacing; // 控件间的间距
  final bool loopFocus; // 是否允许焦点循环切换，默认为 true
  final bool isFrame; // 是否是框架模式
  final NavigationPolicy navigationPolicy; // 导航策略，用于控制焦点切换逻辑

  const TvKeyNavigation({
    Key? key,
    required this.focusableWidgets,
    this.initialIndex = 0,
    this.onSelect,
    this.onKeyPressed,
    this.spacing = 8.0,
    this.loopFocus = true, // 默认值为 true，允许焦点循环
    this.isFrame = false, // 默认不是框架模式
    this.navigationPolicy = defaultNavigationPolicy, // 默认导航策略
  })  : assert(focusableWidgets.length > 0, "必须提供至少一个可聚焦控件"),
        super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  late List<FocusNode> _focusNodes;
  late int _currentIndex;
  late List<GlobalKey> _widgetKeys;
  late List<Offset?> _cachedPositions;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initializeFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheWidgetPositions(); // 缓存控件的位置
      _requestFocus(_currentIndex);
    });

    // 添加监听窗口变化的 observer
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose(); // 销毁滚动控制器
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _cacheWidgetPositions(); // 当窗口大小发生变化时，重新缓存控件位置
  }

  /// 初始化 FocusNodes 和 GlobalKey
  void _initializeFocusNodes() {
    _focusNodes = List.generate(widget.focusableWidgets.length, (_) => FocusNode());
    _widgetKeys = List.generate(widget.focusableWidgets.length, (_) => GlobalKey());
    _cachedPositions = List.filled(widget.focusableWidgets.length, null);
  }

  /// 请求焦点并滚动视图以使其可见
  void _requestFocus(int index) {
    if (_focusNodes.isNotEmpty && index >= 0 && index < _focusNodes.length) {
      FocusScope.of(context).requestFocus(_focusNodes[index]);

      // 滚动到指定控件位置
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMakeVisible(index);
      });
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

  /// 判断是否在页面边缘，用于处理跨框架切换
  bool _isAtEdge(LogicalKeyboardKey key) {
    return (key == LogicalKeyboardKey.arrowUp && _currentIndex == 0) ||
           (key == LogicalKeyboardKey.arrowDown && _currentIndex == _focusNodes.length - 1) ||
           (key == LogicalKeyboardKey.arrowLeft && _currentIndex == 0) ||
           (key == LogicalKeyboardKey.arrowRight && _currentIndex == _focusNodes.length - 1);
  }

  /// 滚动视图，确保当前聚焦的控件可见
  void _scrollToMakeVisible(int index) {
    final context = _widgetKeys[index].currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox;
      final position = renderBox.localToGlobal(Offset.zero);

      final scrollableArea = context.findAncestorRenderObjectOfType<RenderBox>();
      if (scrollableArea != null) {
        final viewportHeight = scrollableArea.size.height;
        final widgetHeight = renderBox.size.height;
        final widgetTop = position.dy;
        final widgetBottom = widgetTop + widgetHeight;

        if (widgetTop < 0) {
          // 如果控件超出顶部，向上滚动
          _scrollController.animateTo(
            _scrollController.offset + widgetTop - widgetHeight,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else if (widgetBottom > viewportHeight) {
          // 如果控件超出底部，向下滚动
          _scrollController.animateTo(
            _scrollController.offset + (widgetBottom - viewportHeight),
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  /// 焦点切换逻辑，基于自定义的导航策略
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    int nextIndex = widget.navigationPolicy(_currentIndex, key, _cachedPositions);

    if (widget.loopFocus || widget.isFrame) {
      if (_isAtEdge(key)) {
        if (widget.isFrame) {
          FocusScope.of(context).nextFocus(); // 跨框架焦点切换
        } else if (widget.loopFocus) {
          nextIndex = (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown)
              ? 0
              : _focusNodes.length - 1;
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
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // 在这里我们不再改变控件的排列，只管理焦点
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: FocusScope(
        autofocus: true,
        onKey: _handleKeyEvent,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column( // 不影响控件原有布局
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.focusableWidgets.length, (index) {
              return Padding(
                padding: EdgeInsets.all(widget.spacing),
                child: FocusableItem(
                  focusNode: _focusNodes[index],
                  isFocused: _currentIndex == index,
                  child: widget.focusableWidgets[index],
                  key: _widgetKeys[index], // 用于缓存位置
                ),
              );
            }),
          ),
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
