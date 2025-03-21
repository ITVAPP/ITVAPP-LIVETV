import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 是否在非TV 模式下启用 TV 模式的焦点逻辑（用于调试）
const bool enableFocusInNonTVMode = true; // 默认开启

// 分割线样式 -垂直分割线加粗且增加渐变效果
final verticalDivider = Container(
  width: 1.5, // 加粗
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withOpacity(0.05),
        Colors.white.withOpacity(0.25),
        Colors.white.withOpacity(0.05),
      ],
    ),
  ),
);

// 水平分割线样式
final horizontalDivider = Container(
  height: 1,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Colors.white.withOpacity(0.05),
        Colors.white.withOpacity(0.15),
        Colors.white.withOpacity(0.05),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
  ),
);

// 文字样式
const defaultTextStyle = TextStyle(
  fontSize: 16, // 调整字体大小
  height: 1.4, // 调整行高
  color: Colors.white, // 添加默认颜色
);

const selectedTextStyle = TextStyle(
  fontWeight: FontWeight.w600, // 加粗
  color: Colors.white,
  shadows: [
    Shadow(
      offset: Offset(0, 1), // 调整阴影偏移
      blurRadius: 4.0, // 增加模糊半径
      color: Colors.black45, // 调整阴影颜色
    ),
  ],
);

// 最小高度
const defaultMinHeight = 42.0;

// 添加全局常量用于列表项高度
const double ITEM_HEIGHT_WITH_DIVIDER = defaultMinHeight + 12.0 + 1.0; // 55.0（42.0 + 12.0 + 1.0）
const double ITEM_HEIGHT_WITHOUT_DIVIDER = defaultMinHeight + 12.0; // 54.0（最后一项无分割线）

// 背景色
final defaultBackgroundColor = LinearGradient(
  colors: [
    Color(0xFF1A1A1A),
    Color(0xFF2C2C2C),
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// padding设置
const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0);

// 装饰设置
const Color selectedColor = Color(0xFFEB144C); // 选中颜色
const Color focusColor = Color(0xFFDFA02A); // 焦点颜色

LinearGradient? getGradientForDecoration({
  required bool isTV,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  if (isTV) {
    return hasFocus
        ? LinearGradient(
            colors: [
              focusColor.withOpacity(0.9),
              focusColor.withOpacity(0.7),
            ],
          )
        : (isSelected && !isSystemAutoSelected
            ? LinearGradient(
                colors: [
                  selectedColor.withOpacity(0.9),
                  selectedColor.withOpacity(0.7),
                ],
              )
            : null);
  } else {
    return isSelected && !isSystemAutoSelected
        ? LinearGradient(
            colors: [
              selectedColor.withOpacity(0.9),
              selectedColor.withOpacity(0.7),
            ],
          )
        : null;
  }
}

BoxDecoration buildItemDecoration({
  bool isSelected = false,
  bool hasFocus = false,
  bool isTV = false,
  bool isSystemAutoSelected = false,
}) {
  return BoxDecoration(
    gradient: getGradientForDecoration(
      isTV: isTV,
      hasFocus: hasFocus,
      isSelected: isSelected,
      isSystemAutoSelected: isSystemAutoSelected,
    ),
    border: Border.all(
      color: hasFocus || (isSelected && !isSystemAutoSelected)
          ? Colors.white.withOpacity(0.3)
          : Colors.transparent,
      width: 1.5, // 加粗边框
    ),
    borderRadius: BorderRadius.circular(8), // 添加圆角
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

// 用于管理所有 FocusNode 的列表和全局焦点状态
List<FocusNode> _focusNodes = [];
Map<int, bool> _focusStates = {};

// 添加全局变量 _lastFocusedIndex
int _lastFocusedIndex = -1; // 记录上一个焦点索引，初始值为 -1 表示未设置焦点

// 添加全局变量用于跟踪每个焦点的 groupIndex
Map<int, int> _focusGroupIndices = {}; // 记录每个焦点的 groupIndex

// 修改后的 addFocusListeners 方法，按完善逻辑调整
void addFocusListeners(
  int startIndex,
  int length,
  State state, {
  ItemScrollController? scrollController,
}) {
  if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
    LogUtil.e('焦点监听器索引越界: startIndex=$startIndex, length=$length, total=${_focusNodes.length}');
    return;
  }
  for (var i = 0; i < length; i++) {
    _focusStates[startIndex + i] = _focusNodes[startIndex + i].hasFocus;
  }
  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    _focusNodes[index].removeListener(() {});
    _focusNodes[index].addListener(() {
      final currentFocus = _focusNodes[index].hasFocus;
      if (_focusStates[index] != currentFocus) {
        _focusStates[index] = currentFocus;
        state.setState(() {});
        if (scrollController != null && currentFocus && scrollController.isAttached) {
          final itemIndex = index - startIndex; // 相对索引
          final currentGroup = _focusGroupIndices[index] ?? -1;
          final lastGroup = _lastFocusedIndex != -1 ? (_focusGroupIndices[_lastFocusedIndex] ?? -1) : -1;
          final isSameGroup = _lastFocusedIndex != -1 && currentGroup == lastGroup;
          final isMovingForward = isSameGroup && index > _lastFocusedIndex; // 向前移动（下移或反转上移）
          final isMovingBackward = isSameGroup && index < _lastFocusedIndex; // 向后移动（上移或反转下移）
          final isInitialFocus = _lastFocusedIndex == -1; // 首次聚焦
          _lastFocusedIndex = index;

          // 获取 ChannelDrawerPageState 以访问索引和抽屉高度
          final channelDrawerState = state is _ChannelDrawerPageState
              ? state
              : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
          if (channelDrawerState == null) return;

          // 判断是否为首项或末项
          final isFirstItem = index == channelDrawerState._categoryListFirstIndex ||
              index == channelDrawerState._groupListFirstIndex ||
              index == channelDrawerState._channelListFirstIndex;
          final isLastItem = index == channelDrawerState._categoryListLastIndex ||
              index == channelDrawerState._groupListLastIndex ||
              index == channelDrawerState._channelListLastIndex;

          // 计算视窗内完整项数
          final viewportHeight = channelDrawerState._drawerHeight;
          final fullItemsInViewport = (viewportHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

          // 当列表项数少于视窗容量时，直接滚动到顶部
          if (length <= fullItemsInViewport) {
            scrollController.scrollTo(
              index: 0,
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('列表项数少于视窗容量，滚动到顶部: length=$length, fullItemsInViewport=$fullItemsInViewport');
            return;
          }

          // 滚动逻辑
          if (isFirstItem) {
            // 首项：滚动到顶部
            scrollController.scrollTo(
              index: 0,
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('滚动到首项: index=$index, group=$currentGroup');
          } else if (isLastItem) {
            // 末项：滚动到底部
            scrollController.scrollTo(
              index: length - 1,
              alignment: 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('滚动到末项: index=$index, group=$currentGroup');
          } else if (isMovingForward && itemIndex >= fullItemsInViewport) {
            // 向前移动（正常下移或反转上移）：焦点项居底部
            final targetIndex = itemIndex - fullItemsInViewport + 1;
            scrollController.scrollTo(
              index: targetIndex.clamp(0, length - fullItemsInViewport),
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('向前滚动: index=$index, targetIndex=$targetIndex');
          } else if (isMovingBackward && itemIndex < fullItemsInViewport - 1) {
            // 向后移动（正常上移或反转下移）：焦点项居顶部
            scrollController.scrollTo(
              index: itemIndex,
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('向后滚动: index=$index, targetIndex=$itemIndex');
          } else if (!isSameGroup && !isInitialFocus) {
            // 组间移动：根据移动方向滚动到新组首项或末项
            final targetIndex = (currentGroup > lastGroup) ? 0 : (length - 1);
            scrollController.scrollTo(
              index: targetIndex,
              alignment: (currentGroup > lastGroup) ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('组间切换: index=$index, group=$currentGroup, targetIndex=$targetIndex');
          } else if (isInitialFocus) {
            // 首次聚焦：不滚动（保持默认位置）
            LogUtil.i('首次聚焦，不触发滚动: index=$index, group=$currentGroup');
          }
        }
      }
    });
  }
}

// 修改部分：移除焦点监听逻辑的通用函数，添加边界检查
void removeFocusListeners(int startIndex, int length) {
  if (startIndex < 0 || startIndex >= _focusNodes.length) {
    LogUtil.e('removeFocusListeners: startIndex 超出范围: $startIndex, _focusNodes.length=${_focusNodes.length}');
    return;
  }
  int safeLength = (startIndex + length > _focusNodes.length) ? (_focusNodes.length - startIndex) : length;
  for (var i = 0; i < safeLength; i++) {
    _focusNodes[startIndex + i].removeListener(() {});
    _focusStates.remove(startIndex + i);
  }
}

// 优化 _initializeFocusNodes，添加日志验证
void _initializeFocusNodes(int totalCount) {
  if (_focusNodes.length != totalCount) {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
    _focusNodes = List.generate(totalCount, (index) => FocusNode());
    LogUtil.i('FocusNodes 初始化: totalCount=$totalCount, _focusNodes.length=${_focusNodes.length}');
  } else {
    LogUtil.i('FocusNodes 无需更新: totalCount=$totalCount, _focusNodes.length=${_focusNodes.length}');
  }
}

// 判断是否超出可视区域函数
bool isOutOfView(BuildContext context) {
  RenderObject? renderObject = context.findRenderObject();
  if (renderObject is RenderBox) {
    final ScrollableState? scrollableState = Scrollable.of(context);
    if (scrollableState != null) {
      final ScrollPosition position = scrollableState.position; // 修复拼写错误
      final double offset = position.pixels;
      final double viewportHeight = position.viewportDimension;
      final Offset objectPosition = renderObject.localToGlobal(Offset.zero);
      return objectPosition.dy < offset || objectPosition.dy > offset + viewportHeight;
    }
  }
  return false;
}

// 通用列表项构建函数（移除 key 参数，恢复鼠标点击，固定高度并避免换行）
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
}) {
  FocusNode? focusNode = (index != null && index >= 0 && index < _focusNodes.length)
      ? _focusNodes[index]
      : null;

  final hasFocus = focusNode?.hasFocus ?? false;

  final textStyle = (isTV || enableFocusInNonTVMode)
      ? (hasFocus
          ? defaultTextStyle.merge(selectedTextStyle)
          : (isSelected && !isSystemAutoSelected
              ? defaultTextStyle.merge(selectedTextStyle)
              : defaultTextStyle))
      : (isSelected && !isSystemAutoSelected
          ? defaultTextStyle.merge(selectedTextStyle)
          : defaultTextStyle);

  Widget listItemContent = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MouseRegion(
        onEnter: (_) => !isTV ? (context as Element).markNeedsBuild() : null,
        onExit: (_) => !isTV ? (context as Element).markNeedsBuild() : null,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: defaultMinHeight, // 修改：固定高度为 42.0，替换 constraints
            padding: padding,
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            decoration: buildItemDecoration(
              isSelected: isSelected,
              hasFocus: hasFocus,
              isTV: isTV || enableFocusInNonTVMode,
              isSystemAutoSelected: isSystemAutoSelected,
            ),
            child: Text(
              title,
              style: textStyle,
              softWrap: false, // 修改：禁用换行
              maxLines: 1, // 修改：限制为单行
              overflow: TextOverflow.ellipsis, // 修改：超出宽度显示省略号
            ),
          ),
        ),
      ),
      if (!isLastItem) horizontalDivider, // 不是最后一项时添加分割线
    ],
  );

  return (isTV || enableFocusInNonTVMode) && useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

// CategoryList 使用 ScrollablePositionedList 包裹 Group
class CategoryList extends StatefulWidget {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;
  final bool isTV;
  final int startIndex;
  final ItemScrollController scrollController; // 修改：添加 ItemScrollController

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.onCategoryTap,
    required this.isTV,
    this.startIndex = 0,
    required this.scrollController,
  });

  @override
  _CategoryListState createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  Map<int, bool> _localFocusStates = {};

  @override
  void initState() {
    super.initState();
    // 初始化本地焦点状态
    for (var i = 0; i < widget.categories.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
    addFocusListeners(widget.startIndex, widget.categories.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
    // 修改部分：添加防护检查，避免索引越界
    if (_focusNodes.isNotEmpty && widget.startIndex >= 0 && widget.startIndex < _focusNodes.length) {
      removeFocusListeners(widget.startIndex, widget.categories.length);
    }
    _localFocusStates.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Group(
        groupIndex: 0,
        child: ScrollablePositionedList.builder(
          itemScrollController: widget.scrollController,
          itemCount: widget.categories.length,
          itemBuilder: (context, index) {
            final category = widget.categories[index];
            final displayTitle = category == Config.myFavoriteKey
                ? S.of(context).myfavorite
                : category == Config.allChannelsKey
                    ? S.of(context).allchannels
                    : category;

            return buildListItem(
              title: displayTitle,
              isSelected: widget.selectedCategoryIndex == index,
              onTap: () => widget.onCategoryTap(index),
              isCentered: true,
              isTV: widget.isTV,
              context: context,
              index: widget.startIndex + index,
              isLastItem: index == widget.categories.length - 1,
            );
          },
        ),
      ),
    );
  }
}

// GroupList 使用单一 Group 包裹整个列表，与 CategoryList 一致
class GroupList extends StatefulWidget {
  final List<String> keys;
  final ItemScrollController scrollController; // 修改：改为 ItemScrollController
  final int selectedGroupIndex;
  final Function(int index) onGroupTap;
  final bool isTV;
  final bool isFavoriteCategory;
  final int startIndex;
  final bool isSystemAutoSelected;

  const GroupList({
    super.key,
    required this.keys,
    required this.scrollController,
    required this.selectedGroupIndex,
    required this.onGroupTap,
    required this.isTV,
    this.startIndex = 0,
    this.isFavoriteCategory = false,
    required this.isSystemAutoSelected,
  });

  @override
  _GroupListState createState() => _GroupListState();
}

class _GroupListState extends State<GroupList> {
  Map<int, bool> _localFocusStates = {};

  @override
  void initState() {
    super.initState();
    // 初始化本地焦点状态
    for (var i = 0; i < widget.keys.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
    // 在焦点监听中绑定滚动控制器
    addFocusListeners(widget.startIndex, widget.keys.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
    // 修改部分：添加防护检查，避免索引越界
    if (_focusNodes.isNotEmpty && widget.startIndex >= 0 && widget.startIndex < _focusNodes.length) {
      removeFocusListeners(widget.startIndex, widget.keys.length);
    }
    _localFocusStates.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty && !widget.isFavoriteCategory) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: widget.keys.isEmpty && widget.isFavoriteCategory
          ? Column(
              mainAxisAlignment: MainAxisAlignment.start, // 整体顶部对齐
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: defaultMinHeight, // 使用与列表项一致的高度
                  alignment: Alignment.center, // 文字在项内垂直居中
                  padding: const EdgeInsets.all(8.0), // 保持内边距
                  child: Text(
                    S.of(context).nofavorite,
                    textAlign: TextAlign.center, // 水平居中
                    style: defaultTextStyle.merge(
                      const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )
          : Group(
              groupIndex: 1,
              child: ScrollablePositionedList.builder(
                itemScrollController: widget.scrollController,
                itemCount: widget.keys.length,
                itemBuilder: (context, index) {
                  return buildListItem(
                    title: widget.keys[index],
                    isSelected: widget.selectedGroupIndex == index,
                    onTap: () => widget.onGroupTap(index),
                    isCentered: false,
                    isTV: widget.isTV,
                    minHeight: defaultMinHeight,
                    context: context,
                    index: widget.startIndex + index,
                    isLastItem: index == widget.keys.length - 1,
                    isSystemAutoSelected: widget.isSystemAutoSelected,
                  );
                },
              ),
            ),
    );
  }
}

// ChannelList 使用单一 Group 包裹整个列表，与 CategoryList 一致
class ChannelList extends StatefulWidget {
  final Map<String, PlayModel> channels;
  final ItemScrollController scrollController; // 修改：改为 ItemScrollController
  final Function(PlayModel?) onChannelTap;
  final String? selectedChannelName;
  final bool isTV;
  final int startIndex;
  final bool isSystemAutoSelected;

  const ChannelList({
    super.key,
    required this.channels,
    required this.scrollController,
    required this.onChannelTap,
    this.selectedChannelName,
    required this.isTV,
    this.startIndex = 0,
    this.isSystemAutoSelected = false,
  });

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList> {
  Map<int, bool> _localFocusStates = {};

  @override
  void initState() {
    super.initState();
    // 初始化本地焦点状态
    for (var i = 0; i < widget.channels.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
    // 在焦点监听中绑定滚动控制器
    addFocusListeners(widget.startIndex, widget.channels.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
    // 修改部分：添加防护检查，避免索引越界
    if (_focusNodes.isNotEmpty && widget.startIndex >= 0 && widget.startIndex < _focusNodes.length) {
      removeFocusListeners(widget.startIndex, widget.channels.length);
    }
    _localFocusStates.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    if (channelList.isEmpty) {
      return const SizedBox.shrink();
    }

    // 获取 ChannelDrawerPageState 以访问 _groupIndex 和 playModel
    final channelDrawerState = context.findAncestorStateOfType<_ChannelDrawerPageState>();
    final currentGroupIndex = channelDrawerState?._groupIndex ?? -1;
    final currentPlayingGroup = channelDrawerState?.widget.playModel?.group;
    final currentGroupKeys = channelDrawerState?._keys ?? [];

    // 当前分组名称
    final currentGroupName = (currentGroupIndex >= 0 && currentGroupIndex < currentGroupKeys.length)
        ? currentGroupKeys[currentGroupIndex]
        : null;

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Group(
        groupIndex: 2,
        child: ScrollablePositionedList.builder(
          itemScrollController: widget.scrollController,
          itemCount: channelList.length,
          itemBuilder: (context, index) {
            final channelEntry = channelList[index];
            final channelName = channelEntry.key;
            // 判断是否是当前播放的分组，只有匹配时才应用选中状态
            final isCurrentPlayingGroup = currentGroupName == currentPlayingGroup;
            final isSelect = isCurrentPlayingGroup && widget.selectedChannelName == channelName;
            return buildListItem(
              title: channelName,
              isSelected: !widget.isSystemAutoSelected && isSelect,
              onTap: () => widget.onChannelTap(widget.channels[channelName]),
              isCentered: false,
              minHeight: defaultMinHeight,
              isTV: widget.isTV,
              context: context,
              index: widget.startIndex + index,
              isLastItem: index == channelList.length - 1,
              isSystemAutoSelected: widget.isSystemAutoSelected,
            );
          },
        ),
      ),
    );
  }
}

// EPG列表组件（未修改，已使用 ScrollablePositionedList）
class EPGList extends StatefulWidget {
  final List<EpgData>? epgData;
  final int selectedIndex;
  final bool isTV;
  final ItemScrollController epgScrollController;
  final VoidCallback onCloseDrawer;

  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.isTV,
    required this.epgScrollController,
    required this.onCloseDrawer,
  });

  @override
  State<EPGList> createState() => _EPGListState();
}

class _EPGListState extends State<EPGList> {
  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) {
      return const SizedBox.shrink();
    }

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
                const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              ),
            ),
          ),
          verticalDivider,
          Flexible(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: widget.selectedIndex,
              itemScrollController: widget.epgScrollController,
              itemCount: widget.epgData?.length ?? 0,
              itemBuilder: (BuildContext context, int index) {
                final data = widget.epgData?[index];
                if (data == null) return const SizedBox.shrink();
                final isSelect = index == widget.selectedIndex;
                return buildListItem(
                  title: '${data.start}-${data.end}\n${data.title}',
                  isSelected: isSelect,
                  onTap: () {
                    widget.onCloseDrawer();
                  },
                  isCentered: false,
                  isTV: widget.isTV,
                  context: context,
                  useFocusableItem: false,
                  isLastItem: index == (widget.epgData!.length - 1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

abstract class ChannelDrawerStateInterface extends State<StatefulWidget> {
  void initializeData();
  void updateFocusLogic(bool isInitial, {int? initialIndexOverride});
}

// 主组件ChannelDrawerPage
class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final bool isLandscape;
  final Function(PlayModel? newModel)? onTapChannel;
  final VoidCallback onCloseDrawer;
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated;
  final ValueKey<int>? refreshKey; // 刷新键

  const ChannelDrawerPage({
    super.key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
    required this.onCloseDrawer,
    this.onTvKeyNavigationStateCreated,
    this.refreshKey,
  });

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  final Map<String, Map<String, dynamic>> epgCache = {};
  final ItemScrollController _scrollController = ItemScrollController(); // 分组
  final ItemScrollController _scrollChannelController = ItemScrollController(); // 频道
  final ItemScrollController _categoryScrollController = ItemScrollController(); // 修改：新增分类控制器
  final ItemScrollController _epgItemScrollController = ItemScrollController();
  TvKeyNavigationState? _tvKeyNavigationState;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;
  bool isPortrait = true;
  bool _isSystemAutoSelected = false;
  bool _isChannelAutoSelected = false;

  final GlobalKey _viewPortKey = GlobalKey();
  List<String> _categories = [];                  // 默认空列表，与 _initializeCategoryData 的降级行为一致
  List<String> _keys = [];                        // 默认空列表，与 _resetChannelData 一致
  List<Map<String, PlayModel>> _values = [];      // 默认空列表，与 _resetChannelData 一致
  int _groupIndex = -1;                           // 默认 -1，与 _initializeCategoryData 的初始值一致
  int _channelIndex = -1;                         // 默认 -1，与 _initializeCategoryData 的初始值一致
  int _categoryIndex = -1;                        // 默认 -1，与 _initializeCategoryData 的初始值一致
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  // 添加抽屉高度成员变量
  double _drawerHeight = 0.0;

  // 第一项和最后一项索引（保持为实例变量）
  int _categoryListFirstIndex = 0;  // 分类列表第一项，始终为 0
  int _groupListFirstIndex = -1;    // 分组列表第一项
  int _channelListFirstIndex = -1;  // 频道列表第一项
  int _categoryListLastIndex = -1;  // 分类列表最后一项
  int _groupListLastIndex = -1;     // 分组列表最后一项
  int _channelListLastIndex = -1;   // 频道列表最后一项

  // 新增分组焦点缓存
  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  // 计算抽屉高度的方法
  void _calculateDrawerHeight() {
    double screenHeight = MediaQuery.of(context).size.height;
    double appBarHeight = 48.0 + 1 + MediaQuery.of(context).padding.top;
    double playerHeight = MediaQuery.of(context).size.width / (16 / 9);
    double bottomPadding = MediaQuery.of(context).padding.bottom;

    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      _drawerHeight = screenHeight; // 移除 leftPadding
    } else {
      _drawerHeight = screenHeight - appBarHeight - playerHeight - bottomPadding; // 移除 leftPadding
      _drawerHeight = _drawerHeight > 0 ? _drawerHeight : 0;
    }
    LogUtil.i('抽屉高度计算: _drawerHeight=$_drawerHeight');
  }

  // 优化滚动方法，使用 ItemScrollController
  void scrollTo({
    required String targetList,
    required int index,
    double alignment = 0.0, // 0.0 表示顶部，0.5 表示中间，1.0 表示底部
    Duration duration = const Duration(milliseconds: 200),
  }) {
    ItemScrollController? scrollController;
    int maxIndex = 0;
    switch (targetList) {
      case 'category':
        scrollController = _categoryScrollController;
        maxIndex = _categories.length - 1;
        break;
      case 'group':
        scrollController = _scrollController;
        maxIndex = _keys.length - 1;
        break;
      case 'channel':
        scrollController = _scrollChannelController;
        maxIndex = _values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
            ? _values[_groupIndex].length - 1
            : 0;
        break;
      case 'epg':
        if (_epgItemScrollController.isAttached) {
          _epgItemScrollController.scrollTo(
            index: index,
            alignment: alignment,
            duration: duration,
          );
        }
        return;
      default:
        LogUtil.i('无效的滚动目标: $targetList');
        return;
    }

    if (index < 0 || index > maxIndex || !scrollController.isAttached) {
      LogUtil.i('$targetList 滚动索引越界或未附着: index=$index, maxIndex=$maxIndex');
      return;
    }

    scrollController.scrollTo(
      index: index,
      alignment: alignment,
      duration: duration,
      curve: Curves.easeInOut,
    );
    LogUtil.i('scrollTo 调用: targetList=$targetList, index=$index, alignment=$alignment');
  }

  // 优化 initState，同步初始化数据，异步加载 EPG
  @override
  void initState() {
    super.initState();
    _calculateDrawerHeight();
    WidgetsBinding.instance.addObserver(this);

    // 同步初始化数据，确保 build 前所有变量已就绪
    initializeData();  // 修改：去掉 _ 前缀
    updateFocusLogic(true);  // 修改：去掉 _ 前缀，首次初始化

    // 异步加载 EPG 数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shouldLoadEpg()) {
        _loadEPGMsg(widget.playModel);
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoMap != oldWidget.videoMap || widget.playModel != oldWidget.playModel) {
      LogUtil.i('ChannelDrawerPage: videoMap 或 playModel 变化，重新初始化');
      initializeData();
      updateFocusLogic(false);
      setState(() {}); // 确保 UI 更新
    }
  }

  // 修改：暴露为公共方法，仅初始化数据并调用 updateFocusLogic
  void initializeData() {
    _initializeCategoryData();
    _initializeChannelData();
    updateFocusLogic(true); // 首次初始化时更新索引
  }

  // 计算总焦点节点数
  int _calculateTotalFocusNodes() {
    int totalFocusNodes = _categories.length;
    // 检查当前选中的分类是否有效
    if (_categoryIndex >= 0 && _categoryIndex < _categories.length) {
      // 检查分组列表是否不为空
      if (_keys.isNotEmpty) {
        totalFocusNodes += _keys.length;
        // 检查当前选中的分组是否有效且包含频道
        if (_values.isNotEmpty &&
            _groupIndex >= 0 &&
            _groupIndex < _values.length &&
            _values[_groupIndex].isNotEmpty) {
          totalFocusNodes += _values[_groupIndex].length;
        }
      }
    }
    return totalFocusNodes;
  }

  // 判断是否需要加载EPG
  bool _shouldLoadEpg() {
    return _keys.isNotEmpty &&
        _values.isNotEmpty &&
        _values[_groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 修复清理逻辑，使用 scrollTo 替代 jumpTo
    if (_scrollController.isAttached) {
      _scrollController.scrollTo(index: 0, duration: Duration.zero);
    }
    if (_scrollChannelController.isAttached) {
      _scrollChannelController.scrollTo(index: 0, duration: Duration.zero);
    }
    if (_categoryScrollController.isAttached) {
      _categoryScrollController.scrollTo(index: 0, duration: Duration.zero);
    }
    _focusNodes.forEach((node) => node.dispose());
    _focusNodes.clear();
    _focusStates.clear();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final newOrientation = MediaQuery.of(context).orientation == Orientation.portrait;
    if (newOrientation != isPortrait) {
      setState(() {
        isPortrait = newOrientation;
      });
    }

    // 仅更新高度和滚动位置，不更新焦点索引
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // 检查 State 是否仍挂载
      setState(() {
        _calculateDrawerHeight();
        _adjustScrollPositions();
      });
    });
  }

  // 简化_handleTvKeyNavigationStateCreated，不绑定 onFocusChanged
  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  // 初始化分类数据
  void _initializeCategoryData() {
    _categories = widget.videoMap?.playList?.keys.toList() ?? <String>[];
    _categoryIndex = -1;
    _groupIndex = -1;
    _channelIndex = -1;

    // 查找当前播放的频道所属的分组和分类
    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      final categoryMap = widget.videoMap?.playList[category];

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = 0; groupIndex < categoryMap.keys.length; groupIndex++) {
          final group = categoryMap.keys.toList()[groupIndex];
          final channelMap = categoryMap[group];

          if (channelMap != null && channelMap.containsKey(widget.playModel?.title)) {
            _categoryIndex = i; // 设置匹配的分类
            _groupIndex = groupIndex; // 设置匹配的分组
            _channelIndex = channelMap.keys.toList().indexOf(widget.playModel?.title ?? '');
            return;
          }
        }
      }
    }

    // 如果未找到当前播放频道的分类，寻找第一个非空分类
    if (_categoryIndex == -1) {
      for (int i = 0; i < _categories.length; i++) {
        final categoryMap = widget.videoMap?.playList[_categories[i]];
        if (categoryMap != null && categoryMap.isNotEmpty) {
          _categoryIndex = i;
          _groupIndex = 0;
          _channelIndex = 0;
          break;
        }
      }
    }
  }

  // 修改后的 _initializeChannelData 方法
  void _initializeChannelData() {
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    // 默认从顶部开始
    _groupIndex = 0;
    _channelIndex = 0;

    // 检查当前分类是否包含当前播放频道的分组
    if (widget.playModel?.group != null && categoryMap.containsKey(widget.playModel?.group)) {
      final groupIdx = _keys.indexOf(widget.playModel?.group ?? '');
      if (groupIdx != -1) {
        _groupIndex = groupIdx;
        final channelIdx = _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
        if (channelIdx != -1) {
          _channelIndex = channelIdx;
        }
      }
    }

    // 如果当前分类不包含当前播放频道的分组，则认为是系统自动选择
    _isSystemAutoSelected = widget.playModel?.group != null && !categoryMap.containsKey(widget.playModel?.group);
    _isChannelAutoSelected = _groupIndex == 0 && _channelIndex == 0;
  }

  // 重置频道数据
  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _selEPGIndex = 0;
  }

  // 重新初始化所有焦点监听器的方法
  void _reInitializeFocusListeners() {
    for (var node in _focusNodes) {
      node.removeListener(() {});
    }

    // 添加新的监听器并检查焦点变化
    addFocusListeners(0, _categories.length, this, scrollController: _categoryScrollController);

    // 如果有分组，初始化分组的监听器
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

  // 修改后的 updateFocusLogic，直接更新所有索引并供复用
  void updateFocusLogic(bool isInitial, {int? initialIndexOverride}) {
    _lastFocusedIndex = -1; // 重置 _lastFocusedIndex，确保首次聚焦正确触发

    // 计算总数
    int totalNodes = _categories.length +
        (_keys.isNotEmpty ? _keys.length : 0) +
        (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);

    for (final node in _focusNodes) node.dispose();
    _focusNodes.clear();
    _focusNodes = List.generate(totalNodes, (index) => FocusNode(debugLabel: 'Node_$index'));
    _focusGroupIndices.clear();

    // 分配 groupIndex
    for (int i = 0; i < _categories.length; i++) {
      _focusGroupIndices[i] = 0; // 分类列表 groupIndex: 0
    }
    for (int i = 0; i < _keys.length; i++) {
      _focusGroupIndices[_groupStartIndex + i] = 1; // 分组列表 groupIndex: 1
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      for (int i = 0; i < _values[_groupIndex].length; i++) {
        _focusGroupIndices[_channelStartIndex + i] = 2; // 频道列表 groupIndex: 2
      }
    }

    LogUtil.i('焦点节点更新: 总数=$totalNodes');

    // 更新起始索引
    _categoryStartIndex = 0;
    _groupStartIndex = _categories.length;
    _channelStartIndex = _categories.length + _keys.length;

    // 直接更新第一项和最后一项索引
    _categoryListFirstIndex = 0;  // 分类列表第一项始终为 0
    _groupListFirstIndex = _groupStartIndex;
    _channelListFirstIndex = _channelStartIndex;

    _categoryListLastIndex = _categories.isNotEmpty ? _categories.length - 1 : -1;
    _groupListLastIndex = _keys.isNotEmpty ? _groupStartIndex + _keys.length - 1 : -1;
    _channelListLastIndex = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length)
        ? _channelStartIndex + _values[_groupIndex].length - 1
        : -1;

    // 使用已更新的索引生成 _groupFocusCache
    _groupFocusCache.clear();
    if (_categories.isNotEmpty) {
      _groupFocusCache[0] = {
        'firstFocusNode': _focusNodes[_categoryListFirstIndex],
        'lastFocusNode': _focusNodes[_categoryListLastIndex]
      };
    }
    if (_keys.isNotEmpty) {
      _groupFocusCache[1] = {
        'firstFocusNode': _focusNodes[_groupListFirstIndex],
        'lastFocusNode': _focusNodes[_groupListLastIndex]
      };
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      _groupFocusCache[2] = {
        'firstFocusNode': _focusNodes[_channelListFirstIndex],
        'lastFocusNode': _focusNodes[_channelListLastIndex]
      };
    }

    // 日志输出
    final groupFocusCacheLog = _groupFocusCache.map((key, value) => MapEntry(
          key,
          '{first: ${_focusNodes.indexOf(value['firstFocusNode']!)}, last: ${_focusNodes.indexOf(value['lastFocusNode']!)}}',
        ));
    LogUtil.i('焦点逻辑更新: categoryStart=$_categoryStartIndex, groupStart=$_groupStartIndex, '
        'channelStart=$_channelStartIndex, '
        'first=[$_categoryListFirstIndex, $_groupListFirstIndex, $_channelListFirstIndex], '
        'last=[$_categoryListLastIndex, $_groupListLastIndex, $_channelListLastIndex], '
        'groupFocusCache=$groupFocusCacheLog');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.updateNamedCache(cache: _groupFocusCache);
      }
    });

    // 非初始化时更新导航状态
    if (!isInitial && _tvKeyNavigationState != null) {
      _tvKeyNavigationState!.releaseResources();
      int safeIndex = initialIndexOverride != null && initialIndexOverride < totalNodes ? initialIndexOverride : 0;
      _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: safeIndex);
      _reInitializeFocusListeners();
    }
  }

  // 修改后的 _onCategoryTap 方法，切换时更新索引
  void _onCategoryTap(int index) {
    if (_categoryIndex == index) return;
    setState(() {
      _categoryIndex = index;
      _focusStates.clear();
      final selectedCategory = _categories[_categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];
      if (categoryMap == null || categoryMap.isEmpty) {
        _resetChannelData();
        _isSystemAutoSelected = true;
      } else {
        _initializeChannelData();
      }
      updateFocusLogic(false, initialIndexOverride: index); // 更新焦点逻辑和索引
    });

    // 添加滚动调整逻辑，确保只有当前播放频道的分类才滚动到 0.23
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewportHeight = _drawerHeight;
      final fullItemsInViewport = (viewportHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

      final selectedCategory = _categories[_categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];
      final isCurrentCategory = widget.playModel?.group != null && categoryMap.containsKey(widget.playModel?.group);

      if (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _keys.length) {
        final isCurrentGroup = isCurrentCategory && _keys[_groupIndex] == widget.playModel?.group;
        if (!isCurrentGroup || _keys.length <= fullItemsInViewport) {
          scrollTo(targetList: 'group', index: 0, alignment: 0.0);
        } else {
          scrollTo(targetList: 'group', index: _groupIndex, alignment: 0.23);
        }
      }

      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final isCurrentGroup = isCurrentCategory && _keys[_groupIndex] == widget.playModel?.group;
        final isCurrentChannel = isCurrentGroup && _values[_groupIndex].containsKey(widget.playModel?.title);
        if (!isCurrentChannel || _values[_groupIndex].length <= fullItemsInViewport) {
          scrollTo(targetList: 'channel', index: 0, alignment: 0.0);
        } else {
          scrollTo(targetList: 'channel', index: _channelIndex, alignment: 0.23);
        }
      }
    });
  }

  // 修改后的 _onGroupTap 方法，切换时更新索引
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;
      _focusStates.clear();
      updateFocusLogic(false, initialIndexOverride: _categories.length + index); // 更新焦点逻辑和索引
    });

    // 添加滚动调整逻辑，确保只有当前播放频道所在分组才滚动到 0.23
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewportHeight = _drawerHeight;
      final fullItemsInViewport = (viewportHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final isCurrentGroup = _keys[_groupIndex] == widget.playModel?.group;
        final isCurrentChannel = isCurrentGroup && _values[_groupIndex].containsKey(widget.playModel?.title);
        if (!isCurrentChannel || _values[_groupIndex].length <= fullItemsInViewport) {
          scrollTo(targetList: 'channel', index: 0, alignment: 0.0);
        } else {
          scrollTo(targetList: 'channel', index: _channelIndex, alignment: 0.23);
        }
      }
    });
  }

  // 切换频道
  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return; // 防止重复点击已选频道

    _isSystemAutoSelected = false; // 用户点击，直接设置为 false
    _isChannelAutoSelected = false;

    // 向父组件发送选中的频道
    widget.onTapChannel?.call(newModel);

    setState(() {
      _channelIndex = _values[_groupIndex].keys.toList().indexOf(newModel?.title ?? '');
      _epgData = null; // 清空节目单数据
      _selEPGIndex = 0; // 重置节目单索引
      updateFocusLogic(false);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEPGMsg(newModel, channelKey: newModel?.title ?? '');
    });
  }

  // 滚动到顶部
  void _scrollToTop(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  // 调整滚动位置
  void _adjustScrollPositions() {
    scrollTo(targetList: 'group', index: _groupIndex);
    scrollTo(targetList: 'channel', index: _channelIndex);
  }

  // 加载EPG
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (isPortrait || playModel == null) return;
    try {
      final currentTime = DateTime.now();
      // 检查缓存是否存在且未过期
      if (channelKey != null &&
          epgCache.containsKey(channelKey) &&
          epgCache[channelKey]!['timestamp'].day == currentTime.day) {
        setState(() {
          _epgData = epgCache[channelKey]!['data'];
          _selEPGIndex = _getInitialSelectedIndex(_epgData);
        });
        // 在节目单数据更新后滚动到当前选中的节目项
        if (_epgData!.isNotEmpty) {
          scrollTo(targetList: 'epg', index: _selEPGIndex);
        }
        return;
      }
      // 缓存不存在或过期，重新获取数据
      final res = await EpgUtil.getEpg(playModel);
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      // 获取当前节目索引
      final selectedIndex = _getInitialSelectedIndex(res.epgData);

      setState(() {
        _epgData = res.epgData!; // 更新节目单数据
        _selEPGIndex = selectedIndex;
      });
      if (channelKey != null) {
        epgCache[channelKey] = {
          'data': res.epgData!,
          'timestamp': currentTime,
        };
      }
      // 在节目单数据更新后滚动到当前选中的节目项
      if (_epgData!.isNotEmpty) {
        scrollTo(targetList: 'epg', index: _selEPGIndex);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  // 查找当前正在播放的节目索引
  int _getInitialSelectedIndex(List<EpgData>? epgData) {
    if (epgData == null || epgData.isEmpty) return 0;

    final currentTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');

    // 从后往前查找最后一个在当前时间之前开始的节目
    for (int i = epgData.length - 1; i >= 0; i--) {
      if (epgData[i].start!.compareTo(currentTime) < 0) {
        return i;
      }
    }

    // 如果没找到,返回第一个节目的索引
    return 0;
  }

  // 修改后的 build 方法，按方案 1 移除防护检查，直接传递状态
  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;
    int currentFocusIndex = 0;

    // 直接传递 _categoryIndex，不加防护检查
    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex, // 修改：移除 >= 0 ? _categoryIndex : -1
      onCategoryTap: _onCategoryTap,
      isTV: useFocusNavigation,
      startIndex: currentFocusIndex,
      scrollController: _categoryScrollController,
    );
    currentFocusIndex += _categories.length;

    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    // 直接传递 _groupIndex，不加防护检查
    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex, // 修改：移除 >= 0 ? _groupIndex : -1
      onGroupTap: _onGroupTap,
      isTV: useFocusNavigation,
      scrollController: _scrollController,
      isFavoriteCategory: _categoryIndex >= 0 && _categories.isNotEmpty && _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,
      isSystemAutoSelected: _isSystemAutoSelected,
    );

    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length;
        // 直接根据 _channelIndex 获取频道名称，不加额外防护
        String? selectedChannelName = _channelIndex >= 0 && _values[_groupIndex].isNotEmpty
            ? _values[_groupIndex].keys.toList()[_channelIndex]
            : null;
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: selectedChannelName, // 修改：简化逻辑，直接传递
          onChannelTap: _onChannelTap,
          isTV: useFocusNavigation,
          scrollController: _scrollChannelController,
          startIndex: currentFocusIndex,
          isSystemAutoSelected: _isChannelAutoSelected,
        );

        epgListWidget = EPGList(
          epgData: _epgData,
          selectedIndex: _selEPGIndex,
          isTV: useFocusNavigation,
          epgScrollController: _epgItemScrollController,
          onCloseDrawer: widget.onCloseDrawer,
        );
      }
    }

    return TvKeyNavigation(
      focusNodes: _focusNodes,
      groupFocusCache: _groupFocusCache,
      cacheName: 'ChannelDrawerPage',
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),
    );
  }

  // 构建抽屉视图
  Widget _buildOpenDrawer(
      bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
    double categoryWidth = isPortrait ? 110 : 120; // 分类列表宽度
    double groupWidth = groupListWidget != null ? (isPortrait ? 120 : 130) : 0; // 设置分组列表宽度

    // 设置频道列表宽度
    double channelListWidth = (groupListWidget != null && channelListWidget != null)
        ? (isPortrait ? MediaQuery.of(context).size.width - categoryWidth - groupWidth : 160)
        : 0;

    // 设置 EPG 列表宽度
    double epgListWidth = (groupListWidget != null && channelListWidget != null && epgListWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth
        : 0;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape
          ? categoryWidth + groupWidth + channelListWidth + epgListWidth
          : MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
                height: constraints.maxHeight, // 自适应高度
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
              if (channelListWidget != null) ...[
                verticalDivider,
                SizedBox(
                  width: channelListWidth,
                  height: constraints.maxHeight,
                  child: channelListWidget,
                ),
              ],
              if (epgListWidget != null) ...[
                verticalDivider,
                Container(
                  width: epgListWidth,
                  child: epgListWidget,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
