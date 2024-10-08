import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<List<FocusableItem>> groups; // 每个组包含多个 FocusableItem
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
    required this.groups, // 使用每组 FocusableItem 列表代替focusNodes
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
      if (widget.initialIndex != null) {
        _requestFocusByIndex(widget.initialIndex!);
      } else {
        _requestFocus(0, 0); // 如果没有提供 initialIndex，则默认聚焦第一个组的第一个控件
      }
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期观察者
    super.dispose();
  }

  /// 请求将焦点切换到指定组和组内的索引控件上
  void _requestFocus(int groupIndex, int itemIndex) {
    if (widget.groups.isNotEmpty &&
        groupIndex >= 0 && groupIndex < widget.groups.length &&
        itemIndex >= 0 && itemIndex < widget.groups[groupIndex].length) {
      widget.groups[groupIndex][itemIndex].requestFocus();
    }
  }

  /// 没有分组时，根据线性索引请求焦点
  void _requestFocusByIndex(int linearIndex) {
    if (!widget.isHorizontalGroup && !widget.isVerticalGroup) {
      // 如果没有启用分组，直接视为线性列表
      int totalItems = widget.groups.expand((group) => group).length;
      if (linearIndex >= 0 && linearIndex < totalItems) {
        int currentIndex = 0;
        for (var group in widget.groups) {
          if (linearIndex < currentIndex + group.length) {
            _requestFocus(widget.groups.indexOf(group), linearIndex - currentIndex);
            return;
          }
          currentIndex += group.length;
        }
      }
    } else {
      // 分组处理
      int groupIndex = 0;
      int itemIndex = linearIndex;
      for (var group in widget.groups) {
        if (itemIndex < group.length) {
          _requestFocus(groupIndex, itemIndex);
          return;
        }
        itemIndex -= group.length;
        groupIndex++;
      }
    }
  }

  /// 获取当前焦点的线性索引
  int? _getCurrentFocusIndex() {
    final currentFocus = _currentFocus;
    if (currentFocus == null) return null;

    int linearIndex = 0;
    for (int groupIndex = 0; groupIndex < widget.groups.length; groupIndex++) {
      for (int itemIndex = 0; itemIndex < widget.groups[groupIndex].length; itemIndex++) {
        if (widget.groups[groupIndex][itemIndex].hasFocus()) {
          return linearIndex + itemIndex;
        }
      }
      linearIndex += widget.groups[groupIndex].length;
    }
    return null;
  }

  /// 判断当前焦点是否在边界
  bool _isAtEdge(LogicalKeyboardKey key, int currentIndex) {
    int totalItems = widget.groups.expand((group) => group).length;
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
        return currentIndex == 0; // 最左或最上
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        return currentIndex == totalItems - 1; // 最右或最下
      default:
        return false;
    }
  }

  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentFocusIndex = _getCurrentFocusIndex();
    if (currentFocusIndex == null) return KeyEventResult.ignored; // 没有焦点时忽略

    int totalItems = widget.groups.expand((group) => group).length;

    if (_isAtEdge(key, currentFocusIndex) && widget.loopFocus) {
      // 处理循环焦点逻辑
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
        _requestFocusByIndex(0); // 循环到第一个控件
      } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
        _requestFocusByIndex(totalItems - 1); // 循环到最后一个控件
      }
    } else if (widget.isFrame) {
      // 框架模式逻辑处理
      if (widget.frameType == "parent") {
        _handleParentFrameNavigation(key, currentFocusIndex);
      } else if (widget.frameType == "child") {
        _handleChildFrameNavigation(key, currentFocusIndex);
      }
    } else if (!widget.isHorizontalGroup && !widget.isVerticalGroup) {
      // 没有分组时，线性焦点前进后退
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        if (currentFocusIndex > 0) {
          _requestFocusByIndex(currentFocusIndex - 1); // 线性后退
        }
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
        if (currentFocusIndex < totalItems - 1) {
          _requestFocusByIndex(currentFocusIndex + 1); // 线性前进
        }
      }
    } else {
      // 有分组时，按分组逻辑处理
      return _handleGroupedNavigation(key, currentFocusIndex);
    }

    return KeyEventResult.handled;
  }

  /// 父框架导航逻辑
  void _handleParentFrameNavigation(LogicalKeyboardKey key, int currentFocusIndex) {
    if (widget.isHorizontalGroup) {
      // 横向分组下的父框架
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (currentFocusIndex == 0) {
          if (widget.loopFocus) {
            _requestFocusByIndex(widget.groups.expand((group) => group).length - 1); // 循环到最后
          }
        } else {
          _requestFocusByIndex(currentFocusIndex - 1); // 组内后退
        }
      } else if (key == LogicalKeyboardKey.arrowRight) {
        if (currentFocusIndex == widget.groups.expand((group) => group).length - 1) {
          FocusScope.of(context).nextFocus(); // 切换到下一个框架的焦点
        } else {
          _requestFocusByIndex(currentFocusIndex + 1); // 组内前进
        }
      }
    } else if (widget.isVerticalGroup) {
      // 竖向分组下的父框架
      if (key == LogicalKeyboardKey.arrowUp) {
        if (currentFocusIndex == 0) {
          if (widget.loopFocus) {
            _requestFocusByIndex(widget.groups.expand((group) => group).length - 1); // 循环到最后
          }
        } else {
          _requestFocusByIndex(currentFocusIndex - 1); // 组内后退
        }
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (currentFocusIndex == widget.groups.expand((group) => group).length - 1) {
          FocusScope.of(context).nextFocus(); // 切换到下一个框架的焦点
        } else {
          _requestFocusByIndex(currentFocusIndex + 1); // 组内前进
        }
      }
    }
  }

  /// 子框架导航逻辑
  void _handleChildFrameNavigation(LogicalKeyboardKey key, int currentFocusIndex) {
    if (widget.isHorizontalGroup) {
      // 横向分组下的子框架
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (currentFocusIndex == 0) {
          FocusScope.of(context).nextFocus(); // 切换到父框架的焦点
        } else {
          _requestFocusByIndex(currentFocusIndex - 1); // 组内后退
        }
      } else if (key == LogicalKeyboardKey.arrowRight) {
        if (currentFocusIndex == widget.groups.expand((group) => group).length - 1) {
          if (widget.loopFocus) {
            _requestFocusByIndex(0); // 循环到第一个
          }
        } else {
          _requestFocusByIndex(currentFocusIndex + 1); // 组内前进
        }
      }
    } else if (widget.isVerticalGroup) {
      // 竖向分组下的子框架
      if (key == LogicalKeyboardKey.arrowUp) {
        if (currentFocusIndex == 0) {
          FocusScope.of(context).nextFocus(); // 切换到父框架的焦点
        } else {
          _requestFocusByIndex(currentFocusIndex - 1); // 组内后退
        }
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (currentFocusIndex == widget.groups.expand((group) => group).length - 1) {
          if (widget.loopFocus) {
            _requestFocusByIndex(0); // 循环到第一个
          }
        } else {
          _requestFocusByIndex(currentFocusIndex + 1); // 组内前进
        }
      }
    }
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

class FocusableItem extends StatefulWidget {
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
  }) : super(key: key);

  /// 是否当前 FocusableItem 已经聚焦
  bool hasFocus() => focusNode.hasFocus;

  /// 请求聚焦此 FocusableItem
  void requestFocus() {
    focusNode.requestFocus();
  }

  @override
  _FocusableItemState createState() => _FocusableItemState();
}

class _FocusableItemState extends State<FocusableItem> {
  @override
  Widget build(BuildContext context) {
    return widget.child; // 直接返回子组件，不做样式修改
  }
}
