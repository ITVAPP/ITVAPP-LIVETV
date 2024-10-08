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

  /// 提取处理跳转逻辑的公共方法，减少重复代码。
  bool _handleGroupNavigation(LogicalKeyboardKey key, int currentIndex, int groupIndex) {
    bool handled = _jumpToOtherGroup(key, currentIndex, groupIndex);
    if (!handled) {
      FocusScope.of(context).nextFocus(); // 默认切换到下一个框架
    }
    return handled;
  }
  
  /// 处理导航逻辑，根据按下的键决定下一个焦点的位置。
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final currentFocus = _currentFocus;

    // 1. 检查当前是否有焦点 (currentFocus)
    if (currentFocus == null) {
      return KeyEventResult.ignored; // 没有焦点时忽略
    }

    // 2. 获取当前焦点的索引 (currentIndex)
    int currentIndex = widget.focusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      return KeyEventResult.ignored; // 找不到当前焦点时忽略
    }

    // 获取 groupIndex
    int groupIndex = _getGroupIndex(currentFocus.context!); // 通过 context 获取 groupIndex

    // 3. 判断是否启用了框架模式 (isFrame)
    if (widget.isFrame) {
      if (widget.frameType == "parent") {
        // 如果 frameType 是 "parent"
        if (widget.isHorizontalGroup) {
          // 处理横向分组
          if (key == LogicalKeyboardKey.arrowLeft) {
            // 左键：后退
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
            } else {
              FocusScope.of(context).previousFocus(); // 上一个焦点
            }
          } else if (key == LogicalKeyboardKey.arrowRight) {
            // 右键：前进
            FocusScope.of(context).nextFocus(); // 切换到下一个框架
          } else if (key == LogicalKeyboardKey.arrowUp) {
            // 上键：后退一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            // 下键：前进一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          }
        } else if (widget.isVerticalGroup) {
          // 处理竖向分组
          if (key == LogicalKeyboardKey.arrowLeft) {
            // 左键：后退一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            // 右键：前进一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            // 上键：后退
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
            } else {
              FocusScope.of(context).previousFocus();
            }
          } else if (key == LogicalKeyboardKey.arrowDown) {
            // 下键：前进
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
            } else {
              FocusScope.of(context).nextFocus();
            }
          }
        }
      } else if (widget.frameType == "child") {
        // 如果 frameType 是 "child"
        if (widget.isHorizontalGroup) {
          // 处理横向分组
          if (key == LogicalKeyboardKey.arrowLeft) {
            // 左键：后退（如果到达边界则切换到下一个框架的焦点）
            if (currentIndex == 0) {
              FocusScope.of(context).nextFocus(); // 切换到下一个框架
            } else {
              FocusScope.of(context).previousFocus(); // 上一个焦点
            }
          } else if (key == LogicalKeyboardKey.arrowRight) {
            // 右键：前进（如果到达边界则循环焦点）
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
            } else {
              FocusScope.of(context).nextFocus(); // 下一个焦点
            }
          } else if (key == LogicalKeyboardKey.arrowUp) {
            // 上键：后退一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            // 下键：前进一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          }
        } else if (widget.isVerticalGroup) {
          // 处理竖向分组
          if (key == LogicalKeyboardKey.arrowLeft) {
            // 左键：后退一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            // 右键：前进一个分组
            _handleGroupNavigation(key, currentIndex, groupIndex);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            // 上键：后退
            if (currentIndex == 0) {
              _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
            } else {
              FocusScope.of(context).previousFocus();
            }
          } else if (key == LogicalKeyboardKey.arrowDown) {
            // 下键：前进
            if (currentIndex == widget.focusNodes.length - 1) {
              _requestFocus(0); // 循环到第一个
            } else {
              FocusScope.of(context).nextFocus();
            }
          }
        }
      }
      return KeyEventResult.handled;
    }

    // 如果没有启用框架模式
    if (widget.isHorizontalGroup) {
      // 横向分组逻辑
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (currentIndex == 0) {
          _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
        } else {
          _requestFocus(currentIndex - 1);
        }
      } else if (key == LogicalKeyboardKey.arrowRight) {
        if (currentIndex == widget.focusNodes.length - 1) {
          _requestFocus(0); // 循环到第一个
        } else {
          _requestFocus(currentIndex + 1);
        }
      }
    } else if (widget.isVerticalGroup) {
      // 竖向分组逻辑
      if (key == LogicalKeyboardKey.arrowUp) {
        if (currentIndex == 0) {
          _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
        } else {
          _requestFocus(currentIndex - 1);
        }
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (currentIndex == widget.focusNodes.length - 1) {
          _requestFocus(0); // 循环到第一个
        } else {
          _requestFocus(currentIndex + 1);
        }
      }
    } else {
      // 没有启用分组的默认导航逻辑
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
        if (currentIndex == 0) {
          _requestFocus(widget.focusNodes.length - 1); // 循环到最后一个
        } else {
          _requestFocus(currentIndex - 1);
        }
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
        if (currentIndex == widget.focusNodes.length - 1) {
          _requestFocus(0); // 循环到第一个
        } else {
          _requestFocus(currentIndex + 1);
        }
      }
    }

    // 调用选择回调
    FocusNode? currentFocusNode = FocusScope.of(context).focusedChild as FocusNode?;
    if (currentFocusNode != null) {
      int newIndex = widget.focusNodes.indexOf(currentFocusNode);
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) {
        widget.onSelect!(newIndex); // 只有在新焦点与当前焦点不同的时候调用回调
      }
    }

    return KeyEventResult.handled;
  }

  /// 获取当前焦点所属的 groupIndex
  int _getGroupIndex(BuildContext context) {
    final group = context.findAncestorWidgetOfExactType<Group>();
    if (group != null) {
      return group.groupIndex;
    }
    return -1; // 未找到 Group 时返回 -1
  }

  /// 处理在组之间的跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (groupIndex == null || groupIndex == -1) return false;

    // 定义前进或后退分组的逻辑
    int nextGroupIndex;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
      // 后退：groupIndex - 1
      nextGroupIndex = groupIndex - 1;
      if (nextGroupIndex < 0) {
        return false; // 已经是第一个分组，无法再后退
      }
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
      // 前进：groupIndex + 1
      nextGroupIndex = groupIndex + 1;
      // 此处判断总的组数，避免越界错误，或者根据实际情况需要调整 totalGroups 逻辑
      int totalGroups = _getTotalGroups(); 
      if (nextGroupIndex >= totalGroups) {
        return false; // 已经是最后一个分组，无法再前进
      }
    } else {
      return false;
    }

    // 切换焦点到下一个分组的第一个控件
    final nextGroup = _findGroupByIndex(nextGroupIndex);
    if (nextGroup != null) {
      final firstFocusNode = _findFirstFocusNodeInGroup(nextGroup);
      if (firstFocusNode != null) {
        firstFocusNode.requestFocus();
        return true;
      }
    }

    return false; // 如果找不到合适的焦点，返回 false
  }

  /// 根据 groupIndex 查找对应的 Group
  Group? _findGroupByIndex(int groupIndex) {
    RenderObject? ancestor = context.findRenderObject();
    Group? targetGroup;
    if (ancestor != null) {
      ancestor.visitChildren((child) {
        final group = context.findAncestorWidgetOfExactType<Group>();
        if (group != null && group.groupIndex == groupIndex) {
          targetGroup = group;
        }
      });
    }
    return targetGroup;
  }

  /// 查找 Group 下的第一个 FocusNode
  FocusNode? _findFirstFocusNodeInGroup(Group group) {
    for (Widget child in group.children) {
      if (child is FocusableItem) {
        return child.focusNode; // 返回第一个 FocusableItem 的 FocusNode
      }
    }
    return null; // 没有找到 FocusNode
  }

  /// 获取总的组数
  int _getTotalGroups() {
    // 此处可以根据 focusNodes 或 Group 总数返回正确的总组数逻辑
    return widget.focusNodes.length; 
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

/// 用于包装多个 FocusableItem 的分组组件
class Group extends StatelessWidget {
  final int groupIndex; // 分组编号
  final List<Widget> children;

  const Group({
    Key? key,
    required this.groupIndex,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children,
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
    return widget.child; // 直接返回子组件，不做样式修改
  }
}
