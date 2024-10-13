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
  }) : super(key: key);

  @override
  _TvKeyNavigationState createState() => _TvKeyNavigationState();
}

class _TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus;
  OverlayEntry? _debugOverlayEntry; // 调试信息窗口

  // 调试模式开关
  final bool _showDebugOverlay = true;

  // 用于缓存每个Group的焦点信息（首尾节点）
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKey: _handleKeyEvent, // 处理键盘事件
      child: widget.child, // 直接使用传入的子组件
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // 缓存 Group 的焦点信息
        _cacheGroupFocusNodes();

        // 设置初始焦点
        if (widget.focusNodes.isNotEmpty || (widget.frameType ?? "") != "child") {
          _requestFocus(widget.initialIndex ?? 0);  // 设置初始焦点到第一个有效节点
        }
        _showDebugOverlayMessage('初始焦点设置完成');
      } catch (e) {
        _showDebugOverlayMessage('初始焦点设置失败: $e');
      }
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    _removeDebugOverlay(); // 移除调试窗口
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    super.dispose();
  }

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    _showDebugOverlayMessage('$message: $error\n位置: $stackTrace');
  }

  /// 显示调试信息的浮动窗口
  void _showDebugOverlayMessage(String message) {
    if (!_showDebugOverlay) return;

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
  }

  /// 移除调试窗口
  void _removeDebugOverlay() {
    _debugOverlayEntry?.remove();
    _debugOverlayEntry = null;
  }

  /// 请求将焦点切换到指定索引的控件上。
  void _requestFocus(int index) {
    if (widget.focusNodes.isEmpty || index < 0 || index >= widget.focusNodes.length) {
      _showDebugOverlayMessage('请求焦点无效，索引超出范围: $index');
      return;
    }
    try {
      FocusNode focusNode = widget.focusNodes[index];
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        _currentFocus = focusNode;
        _showDebugOverlayMessage('切换焦点到索引: $index, 总节点数: ${widget.focusNodes.length}, 当前Group: ${_getGroupIndex(focusNode)}');
      }
    } catch (e) {
      _showDebugOverlayMessage('切换焦点失败: $e');
    }
  }

  /// 缓存 Group 的焦点信息
  void _cacheGroupFocusNodes() {
    _groupFocusCache.clear();  // 清空缓存

    final groups = _getAllGroups();  // 获取所有的 Group
    for (var group in groups) {
      final firstFocusNode = _findFirstFocusNodeInGroup(group);
      final lastFocusNode = _findLastFocusNodeInGroup(group);

      if (firstFocusNode != null && lastFocusNode != null) {
        _groupFocusCache[group.groupIndex] = {
          'firstFocusNode': firstFocusNode,
          'lastFocusNode': lastFocusNode
        };
      }
    }

    _showDebugOverlayMessage('已缓存 Group 的焦点信息: ${_groupFocusCache.length} 个 Group');
  }

  /// 查找 Group 下的最后一个 FocusNode
  FocusNode? _findLastFocusNodeInGroup(Group group) {
    try {
      FocusNode? lastFocusNode;
      
      // 修复：改为接收单个 Widget 而不是 List<Widget>
      void searchFocusNode(Widget child) {
        if (child is FocusableItem) {
          lastFocusNode = child.focusNode;
        } else if (child is SingleChildRenderObjectWidget && child.child != null) {
          searchFocusNode(child.child!);
        } else if (child is MultiChildRenderObjectWidget) {
          for (var widget in child.children) {
            searchFocusNode(widget);
            if (lastFocusNode != null) break;
          }
        }
      }

      group.children?.reversed.forEach(searchFocusNode);  // 倒序遍历子节点进行递归查找
      return lastFocusNode;
    } catch (e, stackTrace) {
      _handleError('查找最后焦点节点失败', e, stackTrace);
      return null;
    }
  }

  /// 后退或循环焦点
  void _navigateToPreviousFocus(LogicalKeyboardKey key, int currentIndex) {
    String action;
    // 如果当前焦点是第一个菜单项，切换到返回按钮（索引 0）
    if (currentIndex == 1) {
      _requestFocus(0); // 切换到返回按钮
      action = "切换到返回按钮";
    } else if (currentIndex == 0) {
      _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个焦点
      action = "循环到最后一个焦点";
    } else {
      _requestFocus(currentIndex - 1);
      action = "切换到前一个焦点";
    }
    _showDebugOverlayMessage('操作: ${key.debugName}键，$action');
  }

  /// 前进或循环焦点
  void _navigateToNextFocus(LogicalKeyboardKey key, int currentIndex) {
    String action;
    // 如果当前焦点是最后一个菜单项，循环回到返回按钮（索引 0）
    if (currentIndex == widget.focusNodes.length - 1) {
      _requestFocus(0); // 切换到返回按钮
      action = "循环到返回按钮";
    } else {
      _requestFocus(currentIndex + 1);
      action = "切换到下一个焦点";
    }
    _showDebugOverlayMessage('操作: ${key.debugName}键，$action');
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (groupIndex == null || groupIndex == -1) {
      _showDebugOverlayMessage('没有 Group 或无效的 groupIndex');
      return false;
    }

    // 定义前进或后退分组的逻辑
    int nextGroupIndex;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
      // 后退：groupIndex - 1
      nextGroupIndex = groupIndex - 1;
      if (nextGroupIndex < 0) {
        // 如果已经是第一个Group，则循环到最后一个Group
        nextGroupIndex = _getTotalGroups() - 1;
        _showDebugOverlayMessage('循环到最后一个分组');
      }
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
      // 前进：groupIndex + 1
      nextGroupIndex = groupIndex + 1;
      int totalGroups = _getTotalGroups();
      if (nextGroupIndex >= totalGroups) {
        // 如果已经是最后一个Group，则循环到第一个Group
        nextGroupIndex = 0;
        _showDebugOverlayMessage('循环到第一个分组');
      }
    } else {
      return false;
    }

    // 从缓存中直接获取下一个 Group 的焦点信息
    final nextGroupFocus = _groupFocusCache[nextGroupIndex];
    if (nextGroupFocus != null) {
      final firstFocusNode = nextGroupFocus['firstFocusNode'];
      if (firstFocusNode != null) {
        firstFocusNode.requestFocus();
        _showDebugOverlayMessage('操作: ${key.debugName}键，切换到组 $nextGroupIndex 的第一个焦点');
        return true;
      }
    }

    _showDebugOverlayMessage('无法找到下一个组编号: $nextGroupIndex');
    return false;
  }

  /// 获取当前焦点所属的 groupIndex
  int _getGroupIndex(FocusNode focusNode) {
    try {
      BuildContext? context = focusNode.context;
      if (context == null) {
        return -1;  // 如果 context 为空，直接返回 -1
      }
      GroupIndexProvider? provider = GroupIndexProvider.of(context);
      if (provider != null) {
        return provider.groupIndex;  // 返回找到的 groupIndex
      }
      return -1; // 如果没有找到 GroupIndexProvider，返回 -1
    } catch (e, stackTrace) {
      _handleError('获取分组索引失败', e, stackTrace);
      return -1;
    }
  }

  /// 获取总的组数
  int _getTotalGroups() {
    return _getAllGroups().length;
  }

  /// 获取所有的 Group
  List<Group> _getAllGroups() {
    List<Group> groups = [];

    // 递归查找所有 Group 的方法
    void searchGroups(Element element) {
      if (element.widget is Group) {
        groups.add(element.widget as Group);
      }
      
      // 递归访问子元素
      element.visitChildren((child) {
        searchGroups(child);
      });
    }

    // 查找 context 中的所有 Element
    if (context != null) {
      context.visitChildElements((element) {
        searchGroups(element);
      });
    }

    _showDebugOverlayMessage('找到的总组数: ${groups.length}');
    return groups;
  }

  /// 查找 Group 下的第一个 FocusNode
  FocusNode? _findFirstFocusNodeInGroup(Group group) {
    try {
      FocusNode? firstFocusNode;
      
      // 修复：改为接收单个 Widget 而不是 List<Widget>
      void searchFocusNode(Widget widget) {
        if (widget is FocusableItem) {
          firstFocusNode = widget.focusNode;
        }
        if (widget is SingleChildRenderObjectWidget && widget.child != null) {
          searchFocusNode(widget.child!);
        } else if (widget is MultiChildRenderObjectWidget) {
          widget.children.forEach(searchFocusNode);
        }
      }

      group.children?.forEach(searchFocusNode);  // 遍历子节点进行递归查找
      return firstFocusNode;
    } catch (e, stackTrace) {
      _handleError('查找焦点节点失败', e, stackTrace);
      return null;
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    FocusNode? currentFocus = _currentFocus;

    // 如果当前没有焦点，则尝试将焦点设置为第一个 focusNode
    if (currentFocus == null) {
      _showDebugOverlayMessage('当前无焦点，尝试设置初始焦点');
      _requestFocus(0); // 设置焦点为第一个控件
      return KeyEventResult.handled; // 返回已处理，避免进一步忽略
    }

    // 获取当前焦点的索引 (currentIndex)
    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      _showDebugOverlayMessage('找不到当前焦点的索引，忽略按键: ${key.debugName}');
      return KeyEventResult.ignored; // 找不到当前焦点时忽略
    }

    // 获取 groupIndex
    int groupIndex = _getGroupIndex(currentFocus);  // 通过 context 获取 groupIndex

    _showDebugOverlayMessage('导航开始: 按键=${key.debugName}, 当前索引=$currentIndex, 当前Group=$groupIndex, 总节点数=${widget.focusNodes.length}');

    // 判断是否启用了框架模式 (isFrame)
    try {
      if (widget.isFrame) {  // 如果是框架模式
        if (widget.frameType == "parent") {   // 父页面
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {    // 左上键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {   // 右键
            FocusScope.of(context).nextFocus(); // 前往子页面
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          }
        } else if (widget.frameType == "child") {  // 子页面
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            FocusScope.of(context).previousFocus(); // 返回主页面
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        }
      } else {  // 如果不是框架模式
        if (widget.isHorizontalGroup) {   // 横向分组逻辑
          if (key == LogicalKeyboardKey.arrowLeft) {  // 左键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowRight) {  // 右键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {  // 上下键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else if (widget.isVerticalGroup) {   // 竖向分组逻辑
          if (key == LogicalKeyboardKey.arrowUp) {  // 上键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown) {  // 下键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {  // 左右键
            _jumpToOtherGroup(key, currentIndex, groupIndex);
          }
        } else {  // 没有启用分组的默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {  // 左上键
            _navigateToPreviousFocus(key, currentIndex);  // 后退或循环焦点
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {  // 右下键
            _navigateToNextFocus(key, currentIndex);  // 前进或循环焦点
          }
        }
      }
    } catch (e) {
      _showDebugOverlayMessage('焦点切换错误: $e');
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

  /// 处理键盘事件，包括方向键和选择键。
  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
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
  final context = _currentFocus?.context;
  if (context != null) {
    try {
      // 1. 检查是否是 SwitchListTile 并切换其状态
      final switchTile = context.findAncestorWidgetOfExactType<SwitchListTile>();
      if (switchTile != null) {
        final value = !(switchTile.value ?? false); // 切换开关状态
        switchTile.onChanged?.call(value); // 调用 SwitchListTile 的 onChanged 回调
        _showDebugOverlayMessage('切换 SwitchListTile 开关状态: $value');
        return; // 操作完成后直接返回
      }

      // 2. 检查是否有带 onPressed 的按钮类型组件（包括 IconButton）
      final button = context.findAncestorWidgetOfExactType<ElevatedButton>() ??
                     context.findAncestorWidgetOfExactType<TextButton>() ??
                     context.findAncestorWidgetOfExactType<OutlinedButton>() ??
                     context.findAncestorWidgetOfExactType<IconButton>();  // 添加 IconButton 的查找

      if (button != null) {
        // 安全地检查按钮类型是否具有 onPressed 属性
        if (button is ElevatedButton && button.onPressed != null) {
          button.onPressed!(); // 调用 ElevatedButton 的 onPressed
        } else if (button is TextButton && button.onPressed != null) {
          button.onPressed!(); // 调用 TextButton 的 onPressed
        } else if (button is OutlinedButton && button.onPressed != null) {
          button.onPressed!(); // 调用 OutlinedButton 的 onPressed
        } else if (button is IconButton && button.onPressed != null) {
          button.onPressed!(); // 调用 IconButton 的 onPressed
        }
        _showDebugOverlayMessage('执行按钮的 onPressed 操作');
        return; // 操作完成后直接返回
      }

      // 3. 检查是否存在具有 onTap 回调的 ListTile 并调用其回调
      final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>();
      if (focusableItem != null && focusableItem.child is ListTile) {
        final listTile = focusableItem.child as ListTile;
        if (listTile.onTap != null) {
          listTile.onTap!(); // 调用 ListTile 的 onTap
          _showDebugOverlayMessage('执行 ListTile 的 onTap 操作');
          return; // 操作完成后直接返回
        }
      }

      // 如果没有找到可执行的组件
      _showDebugOverlayMessage('未找到可以执行操作的控件');
    } catch (e, stackTrace) {
      // 捕获并报告执行操作时的错误
      _showDebugOverlayMessage('执行操作时发生错误: $e, 堆栈信息: $stackTrace');
    }
  } else {
    _showDebugOverlayMessage('当前无有效的焦点上下文');
  }
}

}

class GroupIndexProvider extends InheritedWidget {
  final int groupIndex;

  const GroupIndexProvider({
    Key? key,
    required this.groupIndex,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  bool updateShouldNotify(GroupIndexProvider oldWidget) {
    return groupIndex != oldWidget.groupIndex;
  }

  static GroupIndexProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GroupIndexProvider>();
  }
}

class Group extends StatelessWidget {
  final int groupIndex;
  final Widget? child; // 支持单个 child
  final List<Widget>? children; // 支持多个 children

  const Group({
    Key? key,
    required this.groupIndex,
    this.child,
    this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GroupIndexProvider(
      groupIndex: groupIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: child != null
            ? [child!] // 如果传入了单个 child，则使用它
            : children ?? [], // 如果传入了 children，则使用它们
      ),
    );
  }
}

// 用于包装具有焦点的组件
class FocusableItem extends StatefulWidget {
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件
  final int? groupIndex;

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
    this.groupIndex,
  }) : super(key: key);

  @override
  _FocusableItemState createState() => _FocusableItemState();
}

class _FocusableItemState extends State<FocusableItem> {
  @override
  Widget build(BuildContext context) {
    final int effectiveGroupIndex = widget.groupIndex ??
        GroupIndexProvider.of(context)?.groupIndex ??
        -1;
    return Focus(
      focusNode: widget.focusNode,
      child: widget.child,
    );
  }
}
