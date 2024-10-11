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
  final String? custom; // 自定义方向键，比如 "Up", "Down", "Left", "Right"
  final int? customGroupIndex; // 自定义分组索引
  final int? customFocusIndex; // 自定义焦点索引

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
    this.custom,
    this.customGroupIndex,
    this.customFocusIndex,
  }) : super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus;
  OverlayEntry? _debugOverlayEntry; // 调试信息窗口

  // 添加私有变量来跟踪当前索引
  int _currentIndex = 0; // 初始索引为0，或根据需要设置默认值

  // 添加 getter
  int get currentIndex => _currentIndex; // 获取当前索引

  // 调试模式开关
  final bool _showDebugOverlay = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 设置初始焦点
        if (widget.focusNodes.isNotEmpty) {
          _requestFocus(widget.initialIndex ?? 0);  // 设置初始焦点到第一个有效节点
        } else {
          // 如果没有提供初始索引，自动寻找焦点
          _autoFocusFirstAvailable();
        }
        _showDebugOverlayMessage('初始焦点设置完成');
      } catch (e, stackTrace) {
        _showDebugOverlayMessage('初始焦点设置失败: $e\n位置: $stackTrace');
      }
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    try {
      _removeDebugOverlay(); // 移除调试窗口
      WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('资源释放失败: $e\n位置: $stackTrace');
    }
    super.dispose();
  }

  /// 自动寻找第一个可用的焦点节点
  void _autoFocusFirstAvailable() {
    try {
      // 手动查找第一个可以获取焦点的节点
      if (widget.focusNodes.isNotEmpty) {
        widget.focusNodes.first.requestFocus();
        _showDebugOverlayMessage('自动找到第一个焦点并请求焦点');
      } else {
        _showDebugOverlayMessage('没有找到可用的焦点节点');
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('自动寻找焦点失败: $e\n位置: $stackTrace');
    }
  }

  /// 显示调试信息的浮动窗口
  void _showDebugOverlayMessage(String message) {
    if (!_showDebugOverlay) return;

    try {
      if (_debugOverlayEntry == null) {
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
      } else {
        _debugOverlayEntry!.markNeedsBuild(); // 更新已存在的 OverlayEntry
      }

      // 自动隐藏提示
      Future.delayed(Duration(seconds: 3), () {
        _removeDebugOverlay();
      });
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('调试窗口显示失败: $e\n位置: $stackTrace');
    }
  }

  /// 移除调试窗口
  void _removeDebugOverlay() {
    try {
      _debugOverlayEntry?.remove();
      _debugOverlayEntry = null;
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('移除调试窗口失败: $e\n位置: $stackTrace');
    }
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    try {
      if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
        _showDebugOverlayMessage('请求焦点无效，索引超出范围: $index');
        return;
      }
      FocusNode focusNode = widget.focusNodes[index];
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        _currentFocus = focusNode;
        _currentIndex = index; // 更新 currentIndex
        _showDebugOverlayMessage('切换焦点到索引: $index');
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('切换焦点失败: $e\n位置: $stackTrace');
    }
  }

  // 后退或循环焦点，使用 FocusScope 进行管理
  void _navigateToPreviousFocus(LogicalKeyboardKey key) {
    try {
      // 调用 FocusScope 实现焦点切换
      FocusScope.of(context).previousFocus();
      _showDebugOverlayMessage('操作: ${key.debugName}键，切换到前一个焦点');
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('切换到前一个焦点失败: $e\n位置: $stackTrace');
    }
  }

  // 前进或循环焦点，使用 FocusScope 进行管理
  void _navigateToNextFocus(LogicalKeyboardKey key) {
    try {
      // 调用 FocusScope 实现焦点切换
      FocusScope.of(context).nextFocus();
      _showDebugOverlayMessage('操作: ${key.debugName}键，切换到下一个焦点');
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('切换到下一个焦点失败: $e\n位置: $stackTrace');
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    try {
      FocusNode? currentFocus = _currentFocus;

      // 如果当前没有焦点，则尝试将焦点设置为第一个 focusNode
      if (currentFocus == null) {
        _showDebugOverlayMessage('当前无焦点，尝试设置初始焦点。\n焦点节点总数: ${widget.focusNodes.length}');
        _requestFocus(0); // 设置焦点为第一个控件
        return KeyEventResult.handled; // 返回已处理，避免进一步忽略
      }

      // 获取当前焦点的索引 (currentIndex)
      int currentIndex = widget.focusNodes.indexOf(currentFocus);
      if (currentIndex == -1) {
        _showDebugOverlayMessage('找不到当前焦点的索引。\n焦点节点总数: ${widget.focusNodes.length}');
        return KeyEventResult.ignored; // 找不到当前焦点时忽略
      }

      // 判断是否启用了框架模式 (isFrame)
      if (widget.isFrame) {  // 如果是框架模式
        if (widget.frameType == "parent") {   // 父页面
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {    // 左上键
            _navigateToPreviousFocus(key);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {   // 右键
            FocusScope.of(context).nextFocus(); // 前往子页面
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateToNextFocus(key);  // 前进或循环焦点
          }
        } else if (widget.frameType == "child") {  // 子页面
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            FocusScope.of(context).previousFocus(); // 返回主页面
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateToNextFocus(key);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key);
          }
        }
      } else {  // 如果不是框架模式
        if (widget.isHorizontalGroup) {   // 横向分组逻辑
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateToPreviousFocus(key);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateToNextFocus(key);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key);
          }
        } else if (widget.isVerticalGroup) {   // 竖向分组逻辑
          if (key == LogicalKeyboardKey.arrowUp) {  // 上键
            _navigateToPreviousFocus(key);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateToNextFocus(key);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {  // 左右键
            _jumpToOtherGroup(key);
          }
        } else {  // 没有启用分组的默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {  // 左上键
            _navigateToPreviousFocus(key);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {  // 右下键
            _navigateToNextFocus(key);  // 前进或循环焦点
          }
        }
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('焦点切换错误: $e\n位置: $stackTrace');
    }

    // 调用选择回调
    FocusNode? currentFocusNode = _currentFocus;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex); // 只有在新焦点与当前焦点不同的时候调用回调
      }
    }

    return KeyEventResult.handled;
  }

  /// 处理在组之间的跳转逻辑，使用 FocusScope 实现跨组焦点跳转
  bool _jumpToOtherGroup(LogicalKeyboardKey key) {
    try {
      // 判断是否启用了自定义跳转
      if (widget.custom != null &&
          widget.customGroupIndex != null &&
          widget.customFocusIndex != null) {
        if (_isCustomDirectionKey(key)) {
          _showDebugOverlayMessage(
              '自定义跳转: 分组${widget.customGroupIndex}, 焦点${widget.customFocusIndex}');
          _navigateToCustomGroup(widget.customGroupIndex!, widget.customFocusIndex!);
          return true;
        }
      }

      // 默认的焦点跳转逻辑
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        return FocusScope.of(context).previousFocus(); // 切换到前一个组的焦点
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
        return FocusScope.of(context).nextFocus(); // 切换到下一个组的焦点
      }
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('跳转分组错误: $e\n位置: $stackTrace');
    }
    return false;
  }

  /// 判断是否为自定义方向键
  bool _isCustomDirectionKey(LogicalKeyboardKey key) {
    switch (widget.custom?.toLowerCase()) {
      case 'up':
        return key == LogicalKeyboardKey.arrowUp;
      case 'down':
        return key == LogicalKeyboardKey.arrowDown;
      case 'left':
        return key == LogicalKeyboardKey.arrowLeft;
      case 'right':
        return key == LogicalKeyboardKey.arrowRight;
      default:
        return false;
    }
  }

  /// 自定义跳转逻辑
  void _navigateToCustomGroup(int groupIndex, int focusIndex) {
    try {
      // 自定义跳转逻辑的实现，假设自定义组和焦点索引可用
      // 此处需要根据具体的业务需求实现
      _showDebugOverlayMessage('跳转到分组 $groupIndex 的焦点 $focusIndex');
      // 例如：找到目标组并设置焦点
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('跳转到自定义分组失败: $e\n位置: $stackTrace');
    }
  }

  /// 处理键盘事件，包括方向键和选择键。
  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    try {
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
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('键盘事件处理失败: $e\n位置: $stackTrace');
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
    try {
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
            listTile.onTap!(); 
            _showDebugOverlayMessage('执行 ListTile 的 onTap 操作');
            return;
          }
        }
      }
      // 如果没有可操作的控件
      _showDebugOverlayMessage('当前焦点控件不可操作');
    } catch (e, stackTrace) {
      _showDebugOverlayMessage('执行控件点击操作失败: $e\n位置: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKey: _handleKeyEvent, // 处理键盘事件
      child: widget.child, // 直接使用传入的子组件
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
    return Focus(
      focusNode: widget.focusNode,
      child: widget.child,
    );
  }
}
