import 'dart:async';
import 'dart:math';
import 'dart:convert';
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

void addFocusListeners(
  int startIndex,
  int length,
  State state, {
  ScrollController? scrollController,
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
        if (scrollController != null && currentFocus && scrollController.hasClients) {
          final itemIndex = index - startIndex;
          final currentGroup = _focusGroupIndices[index] ?? -1;
          final lastGroup = _lastFocusedIndex != -1 ? (_focusGroupIndices[_lastFocusedIndex] ?? -1) : -1;
          final isSameGroup = _lastFocusedIndex != -1 && currentGroup == lastGroup;
          final isMovingForward = isSameGroup && index > _lastFocusedIndex;
          final isMovingBackward = isSameGroup && index < _lastFocusedIndex;
          final isInitialFocus = _lastFocusedIndex == -1;
          _lastFocusedIndex = index;

          final channelDrawerState = state is _ChannelDrawerPageState
              ? state
              : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
          if (channelDrawerState == null) return;

          final isFirstItem = index == channelDrawerState._categoryListFirstIndex ||
              index == channelDrawerState._groupListFirstIndex ||
              index == channelDrawerState._channelListFirstIndex;
          final isLastItem = index == channelDrawerState._categoryListLastIndex ||
              index == channelDrawerState._groupListLastIndex ||
              index == channelDrawerState._channelListLastIndex;

          final fullItemsInViewport = (channelDrawerState._drawerHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

          if (length <= fullItemsInViewport) {
            channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: 0, alignment: 0.0);
            LogUtil.i('列表项数少于视窗容量，滚动到顶部');
            return;
          }

          if (isFirstItem) {
            channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: itemIndex, alignment: 0.0);
          } else if (isLastItem) {
            channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: itemIndex, alignment: 1.0);
          } else if (isMovingForward && itemIndex >= fullItemsInViewport) {
            channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: itemIndex, alignment: 1.0);
          } else if (isMovingBackward && itemIndex < fullItemsInViewport - 1) {
            channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: itemIndex, alignment: 0.0);
          } else if (!isSameGroup && !isInitialFocus) {
            channelDrawerState.scrollTo(
              targetList: _getTargetList(currentGroup),
              index: itemIndex,
              alignment: (currentGroup > lastGroup) ? 0.0 : 1.0,
            );
          } else if (isInitialFocus) {
            return;
          }
        }
      }
    });
  }
}

// 辅助方法：根据 groupIndex 获取 targetList
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

// 修改部分：CategoryList 使用 ListView 加载全部项，从顶部排列
class CategoryList extends StatefulWidget {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;
  final bool isTV;
  final int startIndex;
  final ScrollController scrollController;

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
    for (var i = 0; i < widget.categories.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
    addFocusListeners(widget.startIndex, widget.categories.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
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
        child: ListView(
          controller: widget.scrollController,
                child: Group(
        groupIndex: 0,
          children: List.generate(widget.categories.length, (index) {
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
          }),
        ),
      ),
    );
  }
}

// 修改部分：GroupList 使用 ListView 加载全部项，从顶部排列
class GroupList extends StatefulWidget {
  final List<String> keys;
  final ScrollController scrollController;
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
    for (var i = 0; i < widget.keys.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
    addFocusListeners(widget.startIndex, widget.keys.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
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
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: defaultMinHeight,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    S.of(context).nofavorite,
                    textAlign: TextAlign.center,
                    style: defaultTextStyle.merge(
                      const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )
          : ListView(
              controller: widget.scrollController,
              child: Group(
              groupIndex: 1,
                children: List.generate(widget.keys.length, (index) {
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
                }),
              ),
            ),
    );
  }
}

// 修改部分：ChannelList 使用 ListView 加载全部项，从顶部排列
class ChannelList extends StatefulWidget {
  final Map<String, PlayModel> channels;
  final ScrollController scrollController;
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
    for (var i = 0; i < widget.channels.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
    addFocusListeners(widget.startIndex, widget.channels.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
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

    final channelDrawerState = context.findAncestorStateOfType<_ChannelDrawerPageState>();
    final currentGroupIndex = channelDrawerState?._groupIndex ?? -1;
    final currentPlayingGroup = channelDrawerState?.widget.playModel?.group;
    final currentGroupKeys = channelDrawerState?._keys ?? [];

    final currentGroupName = (currentGroupIndex >= 0 && currentGroupIndex < currentGroupKeys.length)
        ? currentGroupKeys[currentGroupIndex]
        : null;

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
        child: ListView(
          controller: widget.scrollController,
          child: Group(
          groupIndex: 2,
          children: List.generate(channelList.length, (index) {
            final channelEntry = channelList[index];
            final channelName = channelEntry.key;
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
          }),
        ),
      ),
    );
  }
}

// 修改部分：EPGList 使用 ListView 加载全部项，从顶部排列
class EPGList extends StatefulWidget {
  final List<EpgData>? epgData;
  final int selectedIndex;
  final bool isTV;
  final ScrollController epgScrollController;
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.epgData != null && widget.epgData!.isNotEmpty) {
        final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
        state?.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: 0.23);
      }
    });
  }

  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.epgData != null && widget.epgData!.isNotEmpty) {
          final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
          state?.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: 0.23);
        }
      });
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

// 主组件 ChannelDrawerPage（未修改，仅保留原样）
class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final bool isLandscape;
  final Function(PlayModel? newModel)? onTapChannel;
  final VoidCallback onCloseDrawer;
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated;
  final ValueKey<int>? refreshKey;

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
  }) : super(key: key ?? _stateKey);

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();

  static Future<void> initializeData() async {
    final state = _stateKey.currentState;
    if (state != null) {
      await state.initializeData();
    }
  }

  static Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    final state = _stateKey.currentState;
    if (state != null) {
      await state.updateFocusLogic(isInitial, initialIndexOverride: initialIndexOverride);
    }
  }

  static Future<void> scroll({
    required String targetList,
    required bool toTop,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final state = _stateKey.currentState;
    if (state == null) return;

    int index;
    double alignment;

    switch (targetList) {
      case 'category':
        if (state._categories.isEmpty) return;
        index = toTop ? 0 : state._categories.length - 1;
        alignment = toTop ? 0.0 : 1.0;
        break;
      case 'group':
        if (state._keys.isEmpty) return;
        index = toTop ? 0 : state._keys.length - 1;
        alignment = toTop ? 0.0 : 1.0;
        break;
      case 'channel':
        if (state._values.isEmpty || state._groupIndex < 0) return;
        index = toTop ? 0 : state._values[state._groupIndex].length - 1;
        alignment = toTop ? 0.0 : 1.0;
        break;
      default:
        return;
    }

    await state.scrollTo(
      targetList: targetList,
      index: index,
      alignment: alignment,
      duration: duration,
    );
  }
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  final Map<String, Map<String, dynamic>> epgCache = {};
  final ScrollController _scrollController = ScrollController(); // 分组
  final ScrollController _scrollChannelController = ScrollController(); // 频道
  final ScrollController _categoryScrollController = ScrollController(); // 分类
  final ScrollController _epgItemScrollController = ScrollController(); // EPG
  TvKeyNavigationState? _tvKeyNavigationState;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;
  bool isPortrait = true;
  bool _isSystemAutoSelected = false;
  bool _isChannelAutoSelected = false;

  final GlobalKey _viewPortKey = GlobalKey();
  List<String> _categories = [];
  List<String> _keys = [];
  List<Map<String, PlayModel>> _values = [];
  int _groupIndex = -1;
  int _channelIndex = -1;
  int _categoryIndex = -1;
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  double _drawerHeight = 0.0;

  int _categoryListFirstIndex = 0;
  int _groupListFirstIndex = -1;
  int _channelListFirstIndex = -1;
  int _categoryListLastIndex = -1;
  int _groupListLastIndex = -1;
  int _channelListLastIndex = -1;

  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  void _calculateDrawerHeight() {
    double screenHeight = MediaQuery.of(context).size.height;
    double appBarHeight = 48.0 + 1 + MediaQuery.of(context).padding.top;
    double playerHeight = MediaQuery.of(context).size.width / (16 / 9);
    double bottomPadding = MediaQuery.of(context).padding.bottom;

    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      _drawerHeight = screenHeight;
    } else {
      _drawerHeight = screenHeight - appBarHeight - playerHeight - bottomPadding;
      _drawerHeight = _drawerHeight > 0 ? _drawerHeight : 0;
    }
    LogUtil.i('抽屉高度计算: _drawerHeight=$_drawerHeight');
  }

  Future<void> scrollTo({
    required String targetList,
    required int index,
    double alignment = 0.0, // 0.0 表示顶部，0.5 表示中间，1.0 表示底部
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    ScrollController? scrollController;
    int itemCount = 0;
    double itemHeight = ITEM_HEIGHT_WITH_DIVIDER;

    switch (targetList) {
      case 'category':
        scrollController = _categoryScrollController;
        itemCount = _categories.length;
        break;
      case 'group':
        scrollController = _scrollController;
        itemCount = _keys.length;
        break;
      case 'channel':
        scrollController = _scrollChannelController;
        itemCount = _values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
            ? _values[_groupIndex].length
            : 0;
        break;
      case 'epg':
        scrollController = _epgItemScrollController;
        itemCount = _epgData?.length ?? 0;
        break;
      default:
        LogUtil.i('无效的滚动目标: $targetList');
        return;
    }

    if (index < 0 || index >= itemCount || !scrollController.hasClients) {
      LogUtil.i('$targetList 滚动索引越界或未附着: index=$index, itemCount=$itemCount');
      return;
    }

    double targetOffset = index * itemHeight;
    double maxScrollExtent = scrollController.position.maxScrollExtent;

    if (alignment > 0.0 && alignment <= 1.0) {
      targetOffset -= _drawerHeight * alignment;
    }

    targetOffset = targetOffset.clamp(0.0, maxScrollExtent);
    await scrollController.animateTo(
      targetOffset,
      duration: duration,
      curve: Curves.easeInOut,
    );
    LogUtil.i('scrollTo 调用: targetList=$targetList, index=$index, alignment=$alignment, offset=$targetOffset');
  }

  @override
  void initState() {
    super.initState();
    _calculateDrawerHeight();
    WidgetsBinding.instance.addObserver(this);

    initializeData();
    updateFocusLogic(true);

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
      setState(() {});
    }
  }

  Future<void> initializeData() async {
    _initializeCategoryData();
    _initializeChannelData();
    await updateFocusLogic(true);
  }

  int _calculateTotalFocusNodes() {
    int totalFocusNodes = _categories.length;
    if (_categoryIndex >= 0 && _categoryIndex < _categories.length) {
      if (_keys.isNotEmpty) {
        totalFocusNodes += _keys.length;
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

  bool _shouldLoadEpg() {
    return _keys.isNotEmpty &&
        _values.isNotEmpty &&
        _values[_groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _scrollChannelController.dispose();
    _categoryScrollController.dispose();
    _epgItemScrollController.dispose();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _calculateDrawerHeight();
        _adjustScrollPositions();
      });
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
    _channelIndex = -1;

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
            _channelIndex = channelMap.keys.toList().indexOf(widget.playModel?.title ?? '');
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
          _channelIndex = 0;
          break;
        }
      }
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

    _groupIndex = 0;
    _channelIndex = 0;

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

    _isSystemAutoSelected = widget.playModel?.group != null && !categoryMap.containsKey(widget.playModel?.group);
    _isChannelAutoSelected = _groupIndex == 0 && _channelIndex == 0;
  }

  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _selEPGIndex = 0;
  }

  void _reInitializeFocusListeners() {
    for (var node in _focusNodes) {
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
    _lastFocusedIndex = -1;

    int totalNodes = _categories.length +
        (_keys.isNotEmpty ? _keys.length : 0) +
        (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);

    for (final node in _focusNodes) node.dispose();
    _focusNodes.clear();
    _focusNodes = List.generate(totalNodes, (index) => FocusNode(debugLabel: 'Node_$index'));
    _focusGroupIndices.clear();

    for (int i = 0; i < _categories.length; i++) {
      _focusGroupIndices[i] = 0;
    }
    for (int i = 0; i < _keys.length; i++) {
      _focusGroupIndices[_groupStartIndex + i] = 1;
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      for (int i = 0; i < _values[_groupIndex].length; i++) {
        _focusGroupIndices[_channelStartIndex + i] = 2;
      }
    }

    LogUtil.i('焦点节点更新: 总数=$totalNodes');

    _categoryStartIndex = 0;
    _groupStartIndex = _categories.length;
    _channelStartIndex = _categories.length + _keys.length;

    _categoryListFirstIndex = 0;
    _groupListFirstIndex = _groupStartIndex;
    _channelListFirstIndex = _channelStartIndex;

    _categoryListLastIndex = _categories.isNotEmpty ? _categories.length - 1 : -1;
    _groupListLastIndex = _keys.isNotEmpty ? _groupStartIndex + _keys.length - 1 : -1;
    _channelListLastIndex = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length)
        ? _channelStartIndex + _values[_groupIndex].length - 1
        : -1;

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

    final groupFocusCacheLog = _groupFocusCache.map((key, value) => MapEntry(
          key,
          '{first: ${_focusNodes.indexOf(value['firstFocusNode']!)}, last: ${_focusNodes.indexOf(value['lastFocusNode']!)}}',
        ));
    LogUtil.i('焦点逻辑更新: categoryStart=$_categoryStartIndex, groupStart=$_groupStartIndex, '
        'channelStart=$_channelStartIndex, '
        'first=[$_categoryListFirstIndex, $_groupListFirstIndex, $_channelListFirstIndex], '
        'last=[$_categoryListLastIndex, $_groupListLastIndex, $_channelListLastIndex], '
        'groupFocusCache=$groupFocusCacheLog');

    await WidgetsBinding.instance.endOfFrame;

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.updateNamedCache(cache: _groupFocusCache);
      if (!isInitial) {
        _tvKeyNavigationState!.releaseResources();
        int safeIndex = initialIndexOverride != null && initialIndexOverride < totalNodes ? initialIndexOverride : 0;
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: safeIndex);
        _reInitializeFocusListeners();
      }
    }
  }

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
      updateFocusLogic(false, initialIndexOverride: index);
    });

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

  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;
      _focusStates.clear();
      updateFocusLogic(false, initialIndexOverride: _categories.length + index);
    });

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

  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;

    _isSystemAutoSelected = false;
    _isChannelAutoSelected = false;

    widget.onTapChannel?.call(newModel);

    setState(() {
      _channelIndex = _values[_groupIndex].keys.toList().indexOf(newModel?.title ?? '');
      _epgData = null;
      _selEPGIndex = 0;
      updateFocusLogic(false);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEPGMsg(newModel, channelKey: newModel?.title ?? '');
    });
  }

  void _scrollToTop(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  void _adjustScrollPositions() {
    scrollTo(targetList: 'group', index: _groupIndex, alignment: 0.23);
    scrollTo(targetList: 'channel', index: _channelIndex, alignment: 0.23);
  }

  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (isPortrait || playModel == null) return;
    try {
      final currentTime = DateTime.now();
      if (channelKey != null &&
          epgCache.containsKey(channelKey) &&
          epgCache[channelKey]!['timestamp'].day == currentTime.day) {
        setState(() {
          _epgData = epgCache[channelKey]!['data'];
          _selEPGIndex = _getInitialSelectedIndex(_epgData);
        });
        if (_epgData!.isNotEmpty) {
          scrollTo(targetList: 'epg', index: _selEPGIndex, alignment: 0.23);
        }
        return;
      }
      final res = await EpgUtil.getEpg(playModel);
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      final selectedIndex = _getInitialSelectedIndex(res.epgData);

      setState(() {
        _epgData = res.epgData!;
        _selEPGIndex = selectedIndex;
      });
      if (channelKey != null) {
        epgCache[channelKey] = {
          'data': res.epgData!,
          'timestamp': currentTime,
        };
      }
      if (_epgData!.isNotEmpty) {
        scrollTo(targetList: 'epg', index: _selEPGIndex, alignment: 0.23);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  int _getInitialSelectedIndex(List<EpgData>? epgData) {
    if (epgData == null || epgData.isEmpty) return 0;

    final currentTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');

    for (int i = epgData.length - 1; i >= 0; i--) {
      if (epgData[i].start!.compareTo(currentTime) < 0) {
        return i;
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;
    int currentFocusIndex = 0;

    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: useFocusNavigation,
      startIndex: currentFocusIndex,
      scrollController: _categoryScrollController,
    );
    currentFocusIndex += _categories.length;

    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
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
        String? selectedChannelName = _channelIndex >= 0 && _values[_groupIndex].isNotEmpty
            ? _values[_groupIndex].keys.toList()[_channelIndex]
            : null;
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: selectedChannelName,
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

  Widget _buildOpenDrawer(
      bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
    double categoryWidth = isPortrait ? 110 : 120;
    double groupWidth = groupListWidget != null ? (isPortrait ? 120 : 130) : 0;
    double channelListWidth = (groupListWidget != null && channelListWidget != null)
        ? (isPortrait ? MediaQuery.of(context).size.width - categoryWidth - groupWidth : 160)
        : 0;
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
