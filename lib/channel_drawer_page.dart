import 'dart:async';
import 'dart:convert';
import 'dart:ui' as appui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 是否在非TV模式下启用TV焦点逻辑（调试用）
const bool enableFocusInNonTVMode = true;

// 定义宽度常量
const double defaultCategoryWidthPortrait = 110.0; // 竖屏分类宽度
const double defaultCategoryWidthLandscape = 120.0; // 横屏分类宽度
const double defaultGroupWidthPortrait = 120.0; // 竖屏分组宽度
const double defaultGroupWidthLandscape = 130.0; // 横屏分组宽度
const double defaultChannelWidthTV = 160.0; // TV模式频道宽度
const double defaultChannelWidthNonTV = 150.0; // 非TV模式频道宽度
const double defaultEpgWidth = 200.0; // EPG宽度

// 创建垂直分割线渐变样式
LinearGradient createDividerGradient({required double opacityStart, required double opacityEnd}) {
  return LinearGradient(
    colors: [
      Colors.white.withOpacity(opacityStart),
      Colors.white.withOpacity((opacityStart + opacityEnd) / 2),
      Colors.white.withOpacity(opacityEnd),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// 定义垂直分割线组件
final verticalDivider = Container(
  width: 1.5,
  decoration: BoxDecoration(gradient: createDividerGradient(opacityStart: 0.05, opacityEnd: 0.25)),
);

// 定义水平分割线组件，带阴影效果
final horizontalDivider = Container(
  height: 1,
  decoration: BoxDecoration(
    gradient: createDividerGradient(opacityStart: 0.05, opacityEnd: 0.15),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
  ),
);

// 定义默认文字样式
const defaultTextStyle = TextStyle(
  fontSize: 16,
  height: 1.4,
  color: Colors.white,
);

// 定义选中状态的文字样式，带阴影
const selectedTextStyle = TextStyle(
  fontWeight: FontWeight.w600,
  color: Colors.white,
  shadows: [
    Shadow(
      offset: Offset(0, 1),
      blurRadius: 4.0,
      color: Colors.black45,
    ),
  ],
);

// 定义列表项最小高度
const defaultMinHeight = 42.0;

// 定义带分割线和不带分割线的列表项高度
const double ITEM_HEIGHT_WITH_DIVIDER = defaultMinHeight + 1.0;
const double ITEM_HEIGHT_WITHOUT_DIVIDER = defaultMinHeight;

// 定义默认背景渐变色
final defaultBackgroundColor = LinearGradient(
  colors: [
    Color(0xFF1A1A1A),
    Color(0xFF2C2C2C),
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// 定义默认水平内边距
const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0);

// 定义选中和焦点颜色常量
const Color selectedColor = Color(0xFFEB144C);
const Color focusColor = Color(0xFFDFA02A);

// 判断是否需要高亮显示的辅助函数，消除重复逻辑
bool _shouldHighlight({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  return (useFocus && hasFocus) || (isSelected && !isSystemAutoSelected);
}

// 根据焦点和选中状态获取渐变色，优化重复逻辑
LinearGradient? _getGradientColor({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final shouldHighlight = _shouldHighlight(
    useFocus: useFocus,
    hasFocus: hasFocus,
    isSelected: isSelected,
    isSystemAutoSelected: isSystemAutoSelected,
  );
  if (shouldHighlight) {
    final baseColor = useFocus && hasFocus ? focusColor : selectedColor;
    return LinearGradient(
      colors: [
        baseColor.withOpacity(0.9),
        baseColor.withOpacity(0.7),
      ],
    );
  }
  return null;
}

// 构建列表项装饰样式，焦点和选中效果，优化重复计算
BoxDecoration buildItemDecoration({
  required bool isTV,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  final gradient = _getGradientColor(
    useFocus: useFocus,
    hasFocus: hasFocus,
    isSelected: isSelected,
    isSystemAutoSelected: isSystemAutoSelected,
  );
  final shouldHighlight = gradient != null;

  return BoxDecoration(
    gradient: gradient,
    border: Border.all(
      color: shouldHighlight ? Colors.white.withOpacity(0.3) : Colors.transparent,
      width: 1.5,
    ),
    borderRadius: BorderRadius.circular(8),
    boxShadow: hasFocus
        ? [
            BoxShadow(
              color: focusColor.withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ]
        : [],
  );
}

// 焦点状态管理类，单例模式管理全局焦点节点，增强并发控制
class FocusStateManager {
  static final FocusStateManager _instance = FocusStateManager._internal();
  factory FocusStateManager() => _instance;
  FocusStateManager._internal();

  List<FocusNode> focusNodes = [];
  Map<int, bool> focusStates = {};
  int lastFocusedIndex = -1;
  List<FocusNode> categoryFocusNodes = [];
  bool _isUpdating = false;

  void initialize(int categoryCount) {
    if (_isUpdating || categoryCount <= 0) return;
    _isUpdating = true;
    if (categoryFocusNodes.isEmpty) {
      categoryFocusNodes = List.generate(categoryCount, (index) => FocusNode(debugLabel: 'CategoryNode$index'));
    }
    focusNodes
      ..clear()
      ..addAll(categoryFocusNodes);
    focusStates.clear();
    lastFocusedIndex = -1;
    _isUpdating = false;
  }

  void updateDynamicNodes(int groupCount, int channelCount) {
    if (_isUpdating) return;
    _isUpdating = true;
    focusNodes
      ..clear()
      ..addAll(categoryFocusNodes);
    final totalDynamicNodes = groupCount + channelCount;
    final dynamicNodes = List.generate(totalDynamicNodes, (index) => FocusNode(debugLabel: 'DynamicNode$index'));
    focusNodes.addAll(dynamicNodes);
    _isUpdating = false;
  }

  bool get isUpdating => _isUpdating;

  void dispose() {
    if (_isUpdating) return;
    _isUpdating = true;
    for (var node in focusNodes) {
      node.removeListener(() {});
      node.dispose();
    }
    for (var node in categoryFocusNodes) {
      node.removeListener(() {});
      node.dispose();
    }
    focusNodes.clear();
    categoryFocusNodes.clear();
    focusStates.clear();
    lastFocusedIndex = -1;
    _isUpdating = false;
  }
}

// 全局焦点管理器实例
final focusManager = FocusStateManager();

// 定义全局键和变量，用于动态获取列表项高度
final GlobalKey _itemKey = GlobalKey();
double? _dynamicItemHeight;

// 获取列表项动态高度，添加缓存机制避免重复计算
void getItemHeight(BuildContext context) {
  if (_dynamicItemHeight != null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final RenderBox? renderBox = _itemKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      LogUtil.i('RenderBox 为 null，可能 CategoryList 未渲染');
      _dynamicItemHeight = ITEM_HEIGHT_WITH_DIVIDER;
    } else {
      _dynamicItemHeight = renderBox.size.height;
      if (_dynamicItemHeight == ITEM_HEIGHT_WITH_DIVIDER) {
        LogUtil.i('动态获取分类列表项高度失败，使用默认值: $_dynamicItemHeight');
      } else {
        LogUtil.i('成功获取动态高度: $_dynamicItemHeight');
      }
    }
  });
}

// 为指定范围的焦点节点添加监听器，避免重复绑定
void addFocusListeners(
  int startIndex,
  int length,
  State state, {
  ScrollController? scrollController,
}) {
  if (focusManager.focusNodes.isEmpty) {
    LogUtil.e('焦点节点未初始化，无法添加监听器');
    return;
  }
  if (startIndex < 0 || length <= 0 || startIndex + length > focusManager.focusNodes.length) {
    LogUtil.e('焦点监听器索引越界: startIndex=$startIndex, length=$length, total=${focusManager.focusNodes.length}');
    return;
  }

  final nodes = focusManager.focusNodes; // 缓存引用
  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    if (!focusManager.focusStates.containsKey(index)) {
      nodes[index].addListener(() {
        final currentFocus = nodes[index].hasFocus;
        if (focusManager.focusStates[index] != currentFocus) {
          focusManager.focusStates[index] = currentFocus;
          state.setState(() {});
          if (scrollController != null && currentFocus && scrollController.hasClients) {
            _handleScroll(index, startIndex, state, scrollController, length);
          }
        }
      });
      focusManager.focusStates[index] = nodes[index].hasFocus;
    }
  }
}

// 处理焦点切换时的滚动逻辑
void _handleScroll(int index, int startIndex, State state, ScrollController scrollController, int length) {
  final itemIndex = index - startIndex;
  final channelDrawerState = state is _ChannelDrawerPageState
      ? state
      : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
  if (channelDrawerState == null) return;

  int currentGroup;
  if (index >= channelDrawerState._categoryStartIndex && index < channelDrawerState._groupStartIndex) {
    currentGroup = 0; // Category
  } else if (index >= channelDrawerState._groupStartIndex && index < channelDrawerState._channelStartIndex) {
    currentGroup = 1; // Group
  } else if (index >= channelDrawerState._channelStartIndex) {
    currentGroup = 2; // Channel
  } else {
    currentGroup = -1; // 无效分组
  }

  int lastGroup = -1;
  if (focusManager.lastFocusedIndex != -1) {
    if (focusManager.lastFocusedIndex >= channelDrawerState._categoryStartIndex &&
        focusManager.lastFocusedIndex < channelDrawerState._groupStartIndex) {
      lastGroup = 0;
    } else if (focusManager.lastFocusedIndex >= channelDrawerState._groupStartIndex &&
        focusManager.lastFocusedIndex < channelDrawerState._channelStartIndex) {
      lastGroup = 1;
    } else if (focusManager.lastFocusedIndex >= channelDrawerState._channelStartIndex) {
      lastGroup = 2;
    }
  }

  final isInitialFocus = focusManager.lastFocusedIndex == -1;
  final isMovingDown = !isInitialFocus && index > focusManager.lastFocusedIndex;
  focusManager.lastFocusedIndex = index;

  if (currentGroup == 0) return; // Category 不需要滚动

  final viewportHeight = channelDrawerState._drawerHeight;
  final itemHeight = _dynamicItemHeight ?? ITEM_HEIGHT_WITH_DIVIDER;
  final fullItemsInViewport = (viewportHeight / itemHeight).floor();

  if (length <= fullItemsInViewport) {
    channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: 0);
    return;
  }

  final currentOffset = scrollController.offset;
  final itemTop = itemIndex * itemHeight;
  final itemBottom = itemTop + itemHeight;

  double? alignment;
  if (itemIndex == 0) {
    alignment = 0.0;
  } else if (itemIndex == length - 1) {
    alignment = 1.0;
  } else if (isMovingDown && itemBottom > currentOffset + viewportHeight) {
    alignment = 2.0;
    channelDrawerState.scrollTo(
      targetList: _getTargetList(currentGroup),
      index: itemIndex,
      alignment: alignment,
    );
    return;
  } else if (!isMovingDown && itemTop < currentOffset) {
    alignment = 0.0;
    channelDrawerState.scrollTo(
      targetList: _getTargetList(currentGroup),
      index: itemIndex,
      alignment: alignment,
    );
    return;
  } else {
    return;
  }

  channelDrawerState.scrollTo(
    targetList: _getTargetList(currentGroup),
    index: itemIndex,
    alignment: alignment,
  );
}

// 根据组索引返回目标列表名称
String _getTargetList(int groupIndex) {
  switch (groupIndex) {
    case 0:
      return 'category';
    case 1:
      return 'group';
    case 2:
      return 'channel';
    default:
      return 'category';
  }
}

// 移除指定范围的焦点监听器
void removeFocusListeners(int startIndex, int length) {
  if (startIndex < 0 || startIndex >= focusManager.focusNodes.length) {
    LogUtil.e('removeFocusListeners: startIndex 超出范围: $startIndex');
    return;
  }
  int safeLength = (startIndex + length > focusManager.focusNodes.length) ? (focusManager.focusNodes.length - startIndex) : length;
  for (var i = 0; i < safeLength; i++) {
    focusManager.focusNodes[startIndex + i].removeListener(() {});
    focusManager.focusStates.remove(startIndex + i);
  }
}

// 获取列表项文字样式，基于焦点和选中状态
TextStyle getItemTextStyle({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  return useFocus
      ? (hasFocus
          ? defaultTextStyle.merge(selectedTextStyle)
          : (isSelected && !isSystemAutoSelected ? defaultTextStyle.merge(selectedTextStyle) : defaultTextStyle))
      : (isSelected && !isSystemAutoSelected ? defaultTextStyle.merge(selectedTextStyle) : defaultTextStyle);
}

// 构建通用列表项，支持焦点和选中样式
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true,
  double minHeight = defaultMinHeight,
  EdgeInsets padding = defaultPadding,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
  Key? key,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  final focusNode = (index != null && index >= 0 && index < focusManager.focusNodes.length) ? focusManager.focusNodes[index] : null;
  final hasFocus = focusNode?.hasFocus ?? false;

  final textStyle = getItemTextStyle(
    useFocus: useFocus,
    hasFocus: hasFocus,
    isSelected: isSelected,
    isSystemAutoSelected: isSystemAutoSelected,
  );

  Widget content = Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    children: [
      MouseRegion(
        onEnter: (_) => !isTV ? (context as Element).markNeedsBuild() : null,
        onExit: (_) => !isTV ? (context as Element).markNeedsBuild() : null,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: minHeight,
            padding: padding,
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            decoration: buildItemDecoration(
              isTV: isTV,
              hasFocus: hasFocus,
              isSelected: isSelected,
              isSystemAutoSelected: isSystemAutoSelected,
            ),
            child: Text(
              title,
              style: textStyle,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      if (!isLastItem) horizontalDivider,
    ],
  );

  return useFocus && useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: content)
      : content;
}

// 抽象列表组件基类，定义通用属性和方法
abstract class BaseListWidget<T> extends StatefulWidget {
  final ScrollController scrollController; // 滚动控制器
  final bool isTV; // 是否为TV模式
  final int startIndex; // 起始焦点索引

  const BaseListWidget({
    super.key,
    required this.scrollController,
    required this.isTV,
    this.startIndex = 0,
  });

  int getItemCount(); // 获取列表项数量
  Widget buildContent(BuildContext context); // 构建列表内容

  @override
  BaseListState<T> createState();
}

// 抽象列表状态基类，管理焦点和生命周期
abstract class BaseListState<T> extends State<BaseListWidget<T>> {
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.getItemCount(), this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
    if (focusManager.focusNodes.isNotEmpty && widget.startIndex >= 0 && widget.startIndex < focusManager.focusNodes.length) {
      removeFocusListeners(widget.startIndex, widget.getItemCount());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: widget.buildContent(context),
    );
  }
}

// 分类列表组件，展示分类并处理选择
class CategoryList extends BaseListWidget<String> {
  final List<String> categories; // 分类列表
  final int selectedCategoryIndex; // 当前选中分类索引
  final Function(int index) onCategoryTap; // 分类点击回调

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.onCategoryTap,
    required super.isTV,
    super.startIndex = 0,
    required super.scrollController,
  });

  @override
  int getItemCount() => categories.length;

  @override
  Widget buildContent(BuildContext context) {
    return ListView(
      controller: scrollController,
      shrinkWrap: true, // 添加 shrinkWrap 以确保有限约束
      children: [
        Group(
          groupIndex: 0,
          children: List.generate(categories.length, (index) {
            final category = categories[index];
            final displayTitle = category == Config.myFavoriteKey
                ? S.of(context).myfavorite
                : category == Config.allChannelsKey
                    ? S.of(context).allchannels
                    : category;

            return buildListItem(
              title: displayTitle,
              isSelected: selectedCategoryIndex == index,
              onTap: () => onCategoryTap(index),
              isCentered: true,
              isTV: isTV,
              context: context,
              index: startIndex + index,
              isLastItem: index == categories.length - 1,
              key: index == 0 ? _itemKey : null,
            );
          }),
        ),
      ],
    );
  }

  @override
  _CategoryListState createState() => _CategoryListState();
}

class _CategoryListState extends BaseListState<String> {}

// 分组列表组件，展示分组并处理选择
class GroupList extends BaseListWidget<String> {
  final List<String> keys; // 分组键列表
  final int selectedGroupIndex; // 当前选中分组索引
  final Function(int index) onGroupTap; // 分组点击回调
  final bool isFavoriteCategory; // 是否为收藏分类
  final bool isSystemAutoSelected; // 是否系统自动选中

  const GroupList({
    super.key,
    required this.keys,
    required this.selectedGroupIndex,
    required this.onGroupTap,
    required super.isTV,
    super.startIndex = 0,
    required super.scrollController,
    this.isFavoriteCategory = false,
    required this.isSystemAutoSelected,
  });

  @override
  int getItemCount() => keys.length;

  @override
  Widget buildContent(BuildContext context) {
    if (keys.isEmpty && isFavoriteCategory) {
      return ListView(
        controller: scrollController,
        children: [
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: defaultMinHeight),
            child: Center(
              child: Text(
                S.of(context).nofavorite,
                textAlign: TextAlign.center,
                style: defaultTextStyle.merge(
                  const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      controller: scrollController,
      children: [
        Group(
          groupIndex: 1,
          children: List.generate(keys.length, (index) {
            return buildListItem(
              title: keys[index],
              isSelected: selectedGroupIndex == index,
              onTap: () => onGroupTap(index),
              isCentered: false,
              isTV: isTV,
              minHeight: defaultMinHeight,
              context: context,
              index: startIndex + index,
              isLastItem: index == keys.length - 1,
              isSystemAutoSelected: isSystemAutoSelected,
            );
          }),
        ),
      ],
    );
  }

  @override
  _GroupListState createState() => _GroupListState();
}

class _GroupListState extends BaseListState<String> {}

// 频道列表组件，展示频道并处理选择
class ChannelList extends BaseListWidget<Map<String, PlayModel>> {
  final Map<String, PlayModel> channels; // 频道数据
  final Function(PlayModel?) onChannelTap; // 频道点击回调
  final String? selectedChannelName; // 当前选中频道名称
  final bool isSystemAutoSelected; // 是否系统自动选中

  const ChannelList({
    super.key,
    required this.channels,
    required this.onChannelTap,
    this.selectedChannelName,
    required super.isTV,
    super.startIndex = 0,
    required super.scrollController,
    this.isSystemAutoSelected = false,
  });

  @override
  int getItemCount() => channels.length;

  @override
  Widget buildContent(BuildContext context) {
    final channelList = channels.entries.toList();
    if (channelList.isEmpty) return const SizedBox.shrink();

    final channelDrawerState = context.findAncestorStateOfType<_ChannelDrawerPageState>();
    final currentGroupIndex = channelDrawerState?._groupIndex ?? -1;
    final currentPlayingGroup = channelDrawerState?.widget.playModel?.group;
    final currentGroupKeys = channelDrawerState?._keys ?? [];

    final currentGroupName = (currentGroupIndex >= 0 && currentGroupIndex < currentGroupKeys.length)
        ? currentGroupKeys[currentGroupIndex]
        : null;

    return ListView(
      controller: scrollController,
      children: [
        RepaintBoundary(
          child: Group(
            groupIndex: 2,
            children: List.generate(channelList.length, (index) {
              final channelEntry = channelList[index];
              final channelName = channelEntry.key;
              final isCurrentPlayingGroup = currentGroupName == currentPlayingGroup;
              final isSelect = isCurrentPlayingGroup && selectedChannelName == channelName;
              return buildListItem(
                title: channelName,
                isSelected: !isSystemAutoSelected && isSelect,
                onTap: () => onChannelTap(channels[channelName]),
                isCentered: false,
                minHeight: defaultMinHeight,
                isTV: isTV,
                context: context,
                index: startIndex + index,
                isLastItem: index == channelList.length - 1,
                isSystemAutoSelected: isSystemAutoSelected,
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  _ChannelListState createState() => _ChannelListState();
}

class _ChannelListState extends BaseListState<Map<String, PlayModel>> {}

// EPG列表组件，展示节目单并支持滚动，优化滚动逻辑避免重复执行
class EPGList extends StatefulWidget {
  final List<EpgData>? epgData; // EPG数据
  final int selectedIndex; // 当前选中索引
  final bool isTV; // 是否为TV模式
  final ScrollController epgScrollController; // EPG滚动控制器
  final VoidCallback onCloseDrawer; // 关闭抽屉回调

  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.isTV,
    required this.epgScrollController,
    required this.onCloseDrawer,
  });

  @override
  State<EPGList> createState() => EPGListState();
}

class EPGListState extends State<EPGList> {
  bool _shouldScroll = true; // 是否需要滚动

  @override
  void initState() {
    super.initState();
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      _shouldScroll = true;
      setState(() {});
    }
  }

  // 调度滚动到选中项，添加检查避免重复滚动
  void _scheduleScroll() {
    if (!_shouldScroll || !mounted) return; // 检查避免重复执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.epgData != null && widget.epgData!.isNotEmpty) {
        final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
        if (state != null && state._epgItemScrollController.hasClients) {
          state.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: null);
          _shouldScroll = false;
          LogUtil.i('EPG 滚动完成: index=${widget.selectedIndex}');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) return const SizedBox.shrink();

    _scheduleScroll();
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Column(
        children: [
          Container(
            height: defaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              S.of(context).programListTitle,
              style: defaultTextStyle.merge(
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          verticalDivider,
          Flexible(
            child: ListView(
              controller: widget.epgScrollController,
              children: List.generate(widget.epgData!.length, (index) {
                final data = widget.epgData![index];
                final isSelect = index == widget.selectedIndex;
                return buildListItem(
                  title: '${data.start}-${data.end}\n${data.title}',
                  isSelected: isSelect,
                  onTap: widget.onCloseDrawer,
                  isCentered: false,
                  isTV: widget.isTV,
                  context: context,
                  useFocusableItem: false,
                  isLastItem: index == (widget.epgData!.length - 1),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// 主组件 - 频道抽屉页面，管理分类、分组、频道和EPG
class ChannelDrawerPage extends StatefulWidget {
  static final GlobalKey<_ChannelDrawerPageState> _stateKey = GlobalKey<_ChannelDrawerPageState>();

  ChannelDrawerPage({
    Key? key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
    required this.onCloseDrawer,
    this.onTvKeyNavigationStateCreated,
    this.refreshKey,
  }) : super(key: _stateKey);

  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final Function(PlayModel? newModel)? onTapChannel;
  final bool isLandscape;
  final VoidCallback onCloseDrawer;
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated;
  final ValueKey<int>? refreshKey;

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();

  static Future<void> initializeData() async {
    final state = _stateKey.currentState;
    if (state != null) await state.initializeData();
  }

  static Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    final state = _stateKey.currentState;
    if (state != null) await state.updateFocusLogic(isInitial, initialIndexOverride: initialIndexOverride);
  }
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  final Map<String, Map<String, dynamic>> epgCache = {};
  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _epgItemScrollController = ScrollController();
  TvKeyNavigationState? _tvKeyNavigationState;
  bool isPortrait = true;
  bool _isSystemAutoSelected = false;

  final GlobalKey _viewPortKey = GlobalKey();
  List<String> _categories = [];
  List<String> _keys = [];
  List<Map<String, PlayModel>> _values = [];
  int _groupIndex = -1;
  int _channelIndex = -1; // 仅用于初始化
  int _categoryIndex = -1;
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  double _drawerHeight = 0.0;

  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  static final Map<String, Map<String, dynamic>> _scrollConfig = {
    'category': {'controllerKey': '_categoryScrollController', 'countKey': '_categories'},
    'group': {'controllerKey': '_scrollController', 'countKey': '_keys'},
    'channel': {'controllerKey': '_scrollChannelController', 'countKey': '_values'},
    'epg': {'controllerKey': '_epgItemScrollController', 'countKey': null},
  };

  double getStatusBarHeight() {
    final height = appui.window.viewPadding.top / appui.window.devicePixelRatio;
    return height;
  }

  void _calculateDrawerHeight() {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = getStatusBarHeight();
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    const double appBarHeight = 48.0 + 1;
    final double playerHeight = MediaQuery.of(context).size.width / (16 / 9);

    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      _drawerHeight = screenHeight;
    } else {
      _drawerHeight = screenHeight - statusBarHeight - appBarHeight - playerHeight - bottomPadding;
      _drawerHeight = _drawerHeight > 0 ? _drawerHeight : 0;
    }
  }

  Future<void> scrollTo({
    required String targetList,
    required int index,
    double? alignment,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final double itemHeight = _dynamicItemHeight ?? ITEM_HEIGHT_WITH_DIVIDER;
    final config = _scrollConfig[targetList];
    if (config == null || !mounted) {
      LogUtil.i('滚动目标无效或组件已销毁: $targetList');
      return;
    }

    final scrollController = this.getField(config['controllerKey']) as ScrollController;
    final itemCount = targetList == 'channel'
        ? (_groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0)
        : (this.getField(config['countKey']) as List?)?.length ?? 0;

    if (itemCount == 0 || !scrollController.hasClients) {
      LogUtil.i('$targetList 数据未准备好或控制器未附着');
      return;
    }

    if (index < 0 || index >= itemCount) {
      LogUtil.i('$targetList 索引超出范围: index=$index, itemCount=$itemCount');
      return;
    }

    double targetOffset;
    if (alignment == 0.0) {
      targetOffset = index == 0 ? scrollController.position.minScrollExtent : index * itemHeight;
    } else if (alignment == 1.0) {
      targetOffset = scrollController.position.maxScrollExtent;
    } else if (alignment == 2.0) {
      double itemBottomPosition = (index == itemCount - 1) ? (itemCount - 1) * itemHeight + defaultMinHeight : (index + 1) * itemHeight;
      targetOffset = itemBottomPosition - _drawerHeight;
      if (targetOffset < 0) targetOffset = 0;
    } else {
      int offsetAdjustment = (targetList == 'group' || targetList == 'channel') ? _categoryIndex.clamp(0, 6) : 3;
      targetOffset = (index - offsetAdjustment) * itemHeight;
      if (targetOffset < 0) targetOffset = 0;
    }

    targetOffset = targetOffset.clamp(0.0, scrollController.position.maxScrollExtent);
    await scrollController.animateTo(
      targetOffset,
      duration: duration,
      curve: Curves.easeInOut,
    );
  }

  dynamic getField(String fieldName) {
    switch (fieldName) {
      case '_categoryScrollController':
        return _categoryScrollController;
      case '_scrollController':
        return _scrollController;
      case '_scrollChannelController':
        return _scrollChannelController;
      case '_epgItemScrollController':
        return _epgItemScrollController;
      case '_categories':
        return _categories;
      case '_keys':
        return _keys;
      case '_values':
        return _values;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _calculateDrawerHeight();
    WidgetsBinding.instance.addObserver(this);
    initializeData(); // 修改：移除 then 中的 getItemHeight 调用
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey) {
      LogUtil.i('didUpdateWidget 开始: refreshKey=${widget.refreshKey?.value}, oldRefreshKey=${oldWidget.refreshKey?.value}');
      initializeData().then((_) {
        int initialFocusIndex = _categoryIndex >= 0 ? _categoryStartIndex + _categoryIndex : 0;
        Future<void> updateFocus() async {
          try {
            _tvKeyNavigationState?.deactivateFocusManagement();
            await updateFocusLogic(false, initialIndexOverride: initialFocusIndex);
            if (mounted && _tvKeyNavigationState != null) {
              _tvKeyNavigationState!.activateFocusManagement(initialIndexOverride: initialFocusIndex);
              setState(() {});
            }
          } catch (e) {
            LogUtil.e('updateFocus 失败: $e, stackTrace=${StackTrace.current}');
          }
        }
        updateFocus();
      }).catchError((e) {
        LogUtil.e('initializeData 失败: $e, stackTrace=${StackTrace.current}');
      });
    }
  }

  Future<void> initializeData() async {
    _initializeCategoryData();
    _initializeChannelData();
    if (_categories.isEmpty) {
      LogUtil.i('分类列表为空，无法绑定 _itemKey');
      _dynamicItemHeight = ITEM_HEIGHT_WITH_DIVIDER;
      return;
    }
    focusManager.initialize(_categories.length);
    _initGroupFocusCacheForCategories();
    await updateFocusLogic(true);

    // 新增：确保分类列表渲染后获取高度，只触发一次
    if (_dynamicItemHeight == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          getItemHeight(context);
        }
      });
    }
  }

  void _initGroupFocusCacheForCategories() {
    if (_categories.isNotEmpty) {
      _groupFocusCache[0] = {
        'firstFocusNode': focusManager.focusNodes[0],
        'lastFocusNode': focusManager.focusNodes[_categories.length - 1]
      };
    }
  }

  int _calculateTotalFocusNodes() {
    int totalFocusNodes = _categories.length;
    if (_categoryIndex >= 0 && _categoryIndex < _categories.length) {
      if (_keys.isNotEmpty) {
        totalFocusNodes += _keys.length;
        if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length && _values[_groupIndex].isNotEmpty) {
          totalFocusNodes += _values[_groupIndex].length;
        }
      }
    }
    return totalFocusNodes;
  }

  bool shouldLoadEpg(List<String> keys, List<Map<String, PlayModel>> values, int groupIndex) {
    return keys.isNotEmpty && values.isNotEmpty && groupIndex >= 0 && groupIndex < values.length && values[groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _scrollChannelController.dispose();
    _categoryScrollController.dispose();
    _epgItemScrollController.dispose();
    focusManager.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final newOrientation = MediaQuery.of(context).orientation == Orientation.portrait;
      final oldHeight = _drawerHeight;
      _calculateDrawerHeight();
      if (newOrientation != isPortrait || oldHeight != _drawerHeight) {
        setState(() {
          isPortrait = newOrientation;
          // 修改：移除 _dynamicItemHeight = null 和 getItemHeight 调用
        });
      }
    });
  }

  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  void _initializeCategoryData() {
    _categories = widget.videoMap?.playList?.keys.toList() ?? <String>[];
    _categoryIndex = -1;
    _groupIndex = -1;

    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      final categoryMap = widget.videoMap?.playList[category];

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = 0; groupIndex < categoryMap.keys.length; groupIndex++) {
          final group = categoryMap.keys.toList()[groupIndex];
          final channelMap = categoryMap[group];

          if (channelMap != null && channelMap.containsKey(widget.playModel?.title)) {
            _categoryIndex = i;
            _groupIndex = groupIndex;
            return;
          }
        }
      }
    }

    if (_categoryIndex == -1) {
      for (int i = 0; i < _categories.length; i++) {
        final categoryMap = widget.videoMap?.playList[_categories[i]];
        if (categoryMap != null && categoryMap.isNotEmpty) {
          _categoryIndex = i;
          _groupIndex = 0;
          break;
        }
      }
    }
  }

  void _updateIndicesFromPlayModel(PlayModel? playModel, Map<String, Map<String, PlayModel>> categoryMap) {
    if (playModel?.group != null && categoryMap.containsKey(playModel?.group)) {
      _groupIndex = _keys.indexOf(playModel!.group!);
      if (_groupIndex != -1) {
        _channelIndex = _values[_groupIndex].keys.toList().indexOf(playModel.title ?? '');
        if (_channelIndex == -1) _channelIndex = 0;
      } else {
        _groupIndex = 0;
        _channelIndex = 0;
      }
    } else {
      _groupIndex = 0;
      _channelIndex = 0;
    }
  }

  void _initializeChannelData() {
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    _updateIndicesFromPlayModel(widget.playModel, categoryMap);

    _isSystemAutoSelected = widget.playModel?.group != null && !categoryMap.containsKey(widget.playModel?.group);
  }

  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
  }

  void _reInitializeFocusListeners() {
    for (var node in focusManager.focusNodes) {
      node.removeListener(() {});
    }

    addFocusListeners(0, _categories.length, this, scrollController: _categoryScrollController);

    if (_keys.isNotEmpty) {
      addFocusListeners(_categories.length, _keys.length, this, scrollController: _scrollController);
      if (_values.isNotEmpty && _groupIndex >= 0) {
        addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          this,
          scrollController: _scrollChannelController,
        );
      }
    }
  }

  Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    if (isInitial) {
      focusManager.lastFocusedIndex = -1;
    }

    final groupCount = _keys.length;
    final channelCount = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) ? _values[_groupIndex].length : 0;
    focusManager.focusStates.clear();
    focusManager.updateDynamicNodes(groupCount, channelCount);

    _categoryStartIndex = 0;
    _groupStartIndex = _categories.length;
    _channelStartIndex = _categories.length + _keys.length;

    _groupFocusCache.remove(1);
    _groupFocusCache.remove(2);
    if (_keys.isNotEmpty) {
      _groupFocusCache[1] = {
        'firstFocusNode': focusManager.focusNodes[_groupStartIndex],
        'lastFocusNode': focusManager.focusNodes[_groupStartIndex + _keys.length - 1]
      };
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      _groupFocusCache[2] = {
        'firstFocusNode': focusManager.focusNodes[_channelStartIndex],
        'lastFocusNode': focusManager.focusNodes[_channelStartIndex + _values[_groupIndex].length - 1]
      };
    }

    LogUtil.i('焦点逻辑更新: categoryStart=$_categoryStartIndex, groupStart=$_groupStartIndex, '
        'channelStart=$_channelStartIndex');

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.updateNamedCache(cache: _groupFocusCache);
      if (!isInitial) {
        _tvKeyNavigationState!.releaseResources(preserveFocus: true);
        int safeIndex = initialIndexOverride ?? 0;
        if (safeIndex < 0 || safeIndex >= focusManager.focusNodes.length) {
          safeIndex = 0;
        }
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: safeIndex);
        _reInitializeFocusListeners();
      }
    }
  }

  void _onCategoryTap(int index) async {
    if (_categoryIndex == index) return;

    _categoryIndex = index;
    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];
    if (categoryMap == null || categoryMap.isEmpty) {
      _resetChannelData();
      _isSystemAutoSelected = true;
    } else {
      _keys = categoryMap.keys.toList();
      _values = categoryMap.values.toList();
      final currentPlayModel = widget.playModel;
      _updateIndicesFromPlayModel(currentPlayModel, categoryMap);
    }

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.deactivateFocusManagement();
    }

    await updateFocusLogic(false, initialIndexOverride: index);

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.activateFocusManagement(initialIndexOverride: index);
    }

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_keys.isNotEmpty) {
        final currentPlayModel = widget.playModel;
        final categoryMap = widget.videoMap?.playList[_categories[_categoryIndex]];
        final isChannelInCategory = currentPlayModel != null && categoryMap != null && categoryMap.containsKey(currentPlayModel.group);

        scrollTo(
          targetList: 'group',
          index: isChannelInCategory ? _groupIndex : 0,
          alignment: isChannelInCategory ? null : 0.0,
        );

        if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
          scrollTo(
            targetList: 'channel',
            index: isChannelInCategory ? _channelIndex : 0,
            alignment: isChannelInCategory ? null : 0.0,
          );
        }
      }
    });
  }

  void _onGroupTap(int index) async {
    _groupIndex = index;
    _isSystemAutoSelected = false;

    final currentPlayModel = widget.playModel;
    final currentGroup = _keys[index];
    if (currentPlayModel != null && currentPlayModel.group == currentGroup) {
      _channelIndex = _values[_groupIndex].keys.toList().indexOf(currentPlayModel.title ?? '');
      if (_channelIndex == -1) _channelIndex = 0;
    } else {
      _channelIndex = 0;
    }

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.deactivateFocusManagement();
    }

    await updateFocusLogic(false, initialIndexOverride: _groupStartIndex + index);

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.activateFocusManagement(initialIndexOverride: _groupStartIndex + index);
    }

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final isChannelInGroup = currentPlayModel != null && currentPlayModel.group == currentGroup;
        scrollTo(
          targetList: 'channel',
          index: isChannelInGroup ? _channelIndex : 0,
          alignment: isChannelInGroup ? null : 0.0,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;

    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: useFocusNavigation,
      startIndex: 0,
      scrollController: _categoryScrollController,
    );

    Widget? groupListWidget;
    Widget? channelContentWidget;

    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
      onGroupTap: _onGroupTap,
      isTV: useFocusNavigation,
      scrollController: _scrollController,
      isFavoriteCategory: _categoryIndex >= 0 && _categories.isNotEmpty && _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: _categories.length,
      isSystemAutoSelected: _isSystemAutoSelected,
    );

    if (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      channelContentWidget = ChannelContent(
        keys: _keys,
        values: _values,
        groupIndex: _groupIndex,
        playModel: widget.playModel,
        onTapChannel: widget.onTapChannel ?? (_) {},
        isTV: useFocusNavigation,
        channelScrollController: _scrollChannelController,
        epgScrollController: _epgItemScrollController,
        onCloseDrawer: widget.onCloseDrawer,
        channelStartIndex: _channelStartIndex,
        epgCache: epgCache,
      );
    }

    return TvKeyNavigation(
      focusNodes: focusManager.focusNodes,
      groupFocusCache: _groupFocusCache,
      cacheName: 'ChannelDrawerPage',
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelContentWidget),
    );
  }

  Widget _buildOpenDrawer(
    bool isTV,
    Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelContentWidget,
  ) {
    final double categoryWidth = isPortrait ? defaultCategoryWidthPortrait : defaultCategoryWidthLandscape;
    final double groupWidth = groupListWidget != null ? (isPortrait ? defaultGroupWidthPortrait : defaultGroupWidthLandscape) : 0.0;
    final double channelContentWidth = (groupListWidget != null && channelContentWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth
        : 0.0;

    final totalWidth = widget.isLandscape
        ? categoryWidth + groupWidth + channelContentWidth
        : MediaQuery.of(context).size.width;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: totalWidth,
      decoration: BoxDecoration(
        gradient: defaultBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: categoryWidth,
                height: constraints.maxHeight,
                child: categoryListWidget,
              ),
              if (groupListWidget != null) ...[
                verticalDivider,
                SizedBox(
                  width: groupWidth,
                  height: constraints.maxHeight,
                  child: groupListWidget,
                ),
              ],
              if (channelContentWidget != null) ...[
                verticalDivider,
                SizedBox(
                  width: channelContentWidth,
                  height: constraints.maxHeight,
                  child: channelContentWidget,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// 频道内容组件，隔离频道和EPG的状态管理
class ChannelContent extends StatefulWidget {
  final List<String> keys;
  final List<Map<String, PlayModel>> values;
  final int groupIndex;
  final PlayModel? playModel;
  final Function(PlayModel?) onTapChannel;
  final bool isTV;
  final ScrollController channelScrollController;
  final ScrollController epgScrollController;
  final VoidCallback onCloseDrawer;
  final int channelStartIndex;
  final Map<String, Map<String, dynamic>> epgCache;

  const ChannelContent({
    Key? key,
    required this.keys,
    required this.values,
    required this.groupIndex,
    required this.playModel,
    required this.onTapChannel,
    required this.isTV,
    required this.channelScrollController,
    required this.epgScrollController,
    required this.onCloseDrawer,
    required this.channelStartIndex,
    required this.epgCache,
  }) : super(key: key);

  @override
  _ChannelContentState createState() => _ChannelContentState();
}

class _ChannelContentState extends State<ChannelContent> {
  int _channelIndex = 0;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;
  bool _isSystemAutoSelected = false;
  bool _isChannelAutoSelected = false;
  Timer? _epgDebounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeChannelIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.playModel != null) {
        _loadEPGMsgWithDebounce(widget.playModel, channelKey: widget.playModel?.title ?? '');
      }
    });
  }

  @override
  void didUpdateWidget(ChannelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupIndex != widget.groupIndex) {
      _initializeChannelIndex();
    }
  }

  void _initializeChannelIndex() {
    if (widget.groupIndex >= 0 && widget.groupIndex < widget.values.length) {
      _channelIndex = widget.values[widget.groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
      if (_channelIndex == -1) _channelIndex = 0;
      _isSystemAutoSelected = widget.playModel?.group != null && !widget.keys.contains(widget.playModel?.group);
      _isChannelAutoSelected = _channelIndex == 0;
      setState(() {});
    }
  }

  bool shouldLoadEpg(List<String> keys, List<Map<String, PlayModel>> values, int groupIndex) {
    return keys.isNotEmpty && values.isNotEmpty && groupIndex >= 0 && groupIndex < values.length && values[groupIndex].isNotEmpty;
  }

  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;

    _isSystemAutoSelected = false;
    _isChannelAutoSelected = false;

    widget.onTapChannel(newModel);

    setState(() {
      _channelIndex = widget.values[widget.groupIndex].keys.toList().indexOf(newModel?.title ?? '');
      _epgData = null;
      _selEPGIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEPGMsgWithDebounce(newModel, channelKey: newModel?.title ?? '');
    });
  }

  void _loadEPGMsgWithDebounce(PlayModel? playModel, {String? channelKey}) {
    _epgDebounceTimer?.cancel();
    _epgDebounceTimer = Timer(Duration(milliseconds: 300), () {
      _loadEPGMsg(playModel, channelKey: channelKey);
    });
  }

  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (playModel == null || !mounted) return;

    final currentTime = DateTime.now();
    if (channelKey != null &&
        widget.epgCache.containsKey(channelKey) &&
        widget.epgCache[channelKey]!['timestamp'] != null &&
        currentTime.difference(widget.epgCache[channelKey]!['timestamp']).inHours < 24) {
      setState(() {
        _epgData = widget.epgCache[channelKey]!['data'];
        _selEPGIndex = _getInitialSelectedIndex(_epgData);
      });
      LogUtil.i('使用缓存的 EPG 数据: $channelKey');
      return;
    }

    final res = await EpgUtil.getEpg(playModel);
    if (res == null || res.epgData == null || res.epgData!.isEmpty) return;

    setState(() {
      _epgData = res.epgData!;
      _selEPGIndex = _getInitialSelectedIndex(_epgData);
      if (channelKey != null) {
        widget.epgCache[channelKey] = {
          'data': res.epgData!,
          'timestamp': currentTime,
        };
      }
    });
    LogUtil.i('加载并缓存新的 EPG 数据: $channelKey');
  }

  int _getInitialSelectedIndex(List<EpgData>? epgData) {
    if (epgData == null || epgData.isEmpty) return 0;
    final currentTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');
    for (int i = epgData.length - 1; i >= 0; i--) {
      if (epgData[i].start!.compareTo(currentTime) < 0) return i;
    }
    return 0;
  }

  @override
  void dispose() {
    _epgDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groupIndex < 0 || widget.groupIndex >= widget.values.length) {
      return const SizedBox.shrink();
    }

    String? selectedChannelName;
    if (_channelIndex >= 0 && _channelIndex < widget.values[widget.groupIndex].keys.length) {
      selectedChannelName = widget.values[widget.groupIndex].keys.toList()[_channelIndex];
    }

    final double channelWidth = widget.isTV ? defaultChannelWidthTV : defaultChannelWidthNonTV;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: channelWidth,
          child: ChannelList(
            channels: widget.values[widget.groupIndex],
            selectedChannelName: selectedChannelName,
            onChannelTap: _onChannelTap,
            isTV: widget.isTV,
            scrollController: widget.channelScrollController,
            startIndex: widget.channelStartIndex,
            isSystemAutoSelected: _isSystemAutoSelected,
          ),
        ),
        if (_epgData != null) ...[
          verticalDivider,
          SizedBox(
            width: defaultEpgWidth,
            child: EPGList(
              epgData: _epgData,
              selectedIndex: _selEPGIndex,
              isTV: widget.isTV,
              epgScrollController: widget.epgScrollController,
              onCloseDrawer: widget.onCloseDrawer,
            ),
          ),
        ],
      ],
    );
  }
}
