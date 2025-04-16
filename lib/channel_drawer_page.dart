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

const bool enableFocusInNonTVMode = true; // 是否在非TV模式启用焦点逻辑（调试用）

// 根据类型和屏幕方向返回列表宽度
const _widthMap = {
  'category': {true: 110.0, false: 120.0},
  'group': {true: 120.0, false: 130.0},
  'channel': {true: 150.0, false: 160.0},
};
double getListWidth(String type, bool isPortrait) => _widthMap[type]?[isPortrait] ?? 0.0;

// 默认最小高度
const defaultMinHeight = 42.0;

// 计算项高度（普通项或EPG项）
double getItemHeight(bool isEpg) => isEpg ? defaultMinHeight * 1.3 + 1 : defaultMinHeight + 1;

// 公共渐变颜色
const _gradientColors = [
  Color.fromRGBO(255, 255, 255, 0.05),
  Color.fromRGBO(255, 255, 255, 0.10),
  Color.fromRGBO(255, 255, 255, 0.15),
];

// 生成分割线
Container buildDivider({required bool isVertical, double? customOpacity}) {
  final colors = _gradientColors.map((c) => c.withOpacity(customOpacity ?? c.opacity)).toList();
  return Container(
    width: isVertical ? 1.5 : null,
    height: isVertical ? null : 1,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      boxShadow: isVertical
          ? null
          : [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
    ),
  );
}

// 垂直分割线
final verticalDivider = buildDivider(isVertical: true);

// 水平分割线
final horizontalDivider = buildDivider(isVertical: false);

// 默认文本样式
const defaultTextStyle = TextStyle(
  fontSize: 16,
  height: 1.4,
  color: Colors.white,
);

// 选中状态文本样式
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

// 默认背景渐变
final defaultBackgroundColor = LinearGradient(
  colors: [
    Color(0xFF1A1A1A),
    Color(0xFF2C2C2C),
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// 默认内边距
const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0);

// 选中和高亮颜色
const Color selectedColor = Color(0xFFEB144C);
const Color focusColor = Color(0xFFDFA02A);

// 构建装饰样式
BoxDecoration buildItemDecoration({
  required bool isTV,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  final shouldHighlight = (useFocus && hasFocus) || (isSelected && !isSystemAutoSelected);
  final baseColor = useFocus && hasFocus ? focusColor : selectedColor;

  return BoxDecoration(
    gradient: shouldHighlight
        ? LinearGradient(
            colors: [
              baseColor.withOpacity(0.9),
              baseColor.withOpacity(0.7),
            ],
          )
        : null,
    border: Border.all(
        color: shouldHighlight ? Colors.white.withOpacity(0.3) : Colors.transparent,
        width: 1.5),
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

// 获取文本样式
TextStyle getItemTextStyle({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  return useFocus
      ? (hasFocus
          ? defaultTextStyle.merge(selectedTextStyle)
          : (isSelected && !isSystemAutoSelected
              ? defaultTextStyle.merge(selectedTextStyle)
              : defaultTextStyle))
      : (isSelected && !isSystemAutoSelected
          ? defaultTextStyle.merge(selectedTextStyle)
          : defaultTextStyle);
}

// 焦点状态管理类，单例模式
class FocusStateManager {
  static final FocusStateManager _instance = FocusStateManager._internal();
  factory FocusStateManager() => _instance;
  FocusStateManager._internal();

  List<FocusNode> focusNodes = [];
  Map<int, bool> focusStates = {};
  int lastFocusedIndex = -1;
  List<FocusNode> categoryFocusNodes = [];
  bool _isUpdating = false;

  // 验证索引范围
  bool _restrictIndexRange(int startIndex, int length, {bool logError = false}) {
    if (startIndex < 0 || length <= 0 || startIndex + length > focusNodes.length) {
      if (logError) {
        LogUtil.e('索引越界: startIndex=$startIndex, length=$length, total=${focusNodes.length}');
      }
      return false;
    }
    return true;
  }

  // 清理焦点节点
  void _clearNodes(List<FocusNode> nodes) {
    for (var node in nodes) {
      node.removeListener(() {});
      node.dispose();
    }
    nodes.clear();
  }

  // 统一管理焦点节点
  void manageFocusNodes({
    required int categoryCount,
    int groupCount = 0,
    int channelCount = 0,
    bool resetAll = false,
  }) {
    if (_isUpdating || (categoryCount <= 0 && !resetAll)) return;
    _isUpdating = true;

    if (resetAll || categoryFocusNodes.length != categoryCount) {
      _clearNodes(categoryFocusNodes);
      _clearNodes(focusNodes);
      categoryFocusNodes = List.generate(
        categoryCount,
        (index) => FocusNode(debugLabel: 'CategoryNode$index'),
      );
      focusNodes.addAll(categoryFocusNodes);
      focusStates.clear();
      lastFocusedIndex = -1;
    } else if (!resetAll && focusNodes.length > categoryFocusNodes.length) {
      for (int i = categoryFocusNodes.length; i < focusNodes.length; i++) {
        focusNodes[i].dispose();
      }
      focusNodes.length = categoryFocusNodes.length;
    }

    final totalDynamicNodes = groupCount + channelCount;
    if (totalDynamicNodes > 0) {
      final dynamicNodes = List.generate(
        totalDynamicNodes,
        (index) => FocusNode(debugLabel: 'DynamicNode$index'),
      );
      focusNodes.addAll(dynamicNodes);
    }

    _isUpdating = false;
  }

  bool get isUpdating => _isUpdating;

  // 清理所有焦点节点
  void dispose() {
    if (_isUpdating) return;
    _isUpdating = true;
    _clearNodes(focusNodes);
    _clearNodes(categoryFocusNodes);
    focusStates.clear();
    lastFocusedIndex = -1;
    _isUpdating = false;
  }
}

// 全局焦点管理实例
final focusManager = FocusStateManager();

// 为焦点节点添加监听器
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
  if (!focusManager._restrictIndexRange(startIndex, length, logError: true)) return;

  final nodes = focusManager.focusNodes;

  for (var i = 0; i < length; i++) {
    final index = startIndex + i;

    if (focusManager.focusStates.containsKey(index)) continue;

    final listener = () {
      final currentFocus = nodes[index].hasFocus;
      if (focusManager.focusStates[index] != currentFocus) {
        focusManager.focusStates[index] = currentFocus;

        if (state.mounted) {
          state.setState(() {});
        }

        if (scrollController != null && currentFocus && scrollController.hasClients) {
          _handleScroll(index, startIndex, state, scrollController, length);
        }
      }
    };

    nodes[index].addListener(listener);
    focusManager.focusStates[index] = nodes[index].hasFocus;
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
    currentGroup = 0;
  } else if (index >= channelDrawerState._groupStartIndex && index < channelDrawerState._channelStartIndex) {
    currentGroup = 1;
  } else if (index >= channelDrawerState._channelStartIndex) {
    currentGroup = 2;
  } else {
    currentGroup = -1;
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

  if (currentGroup == 0) return;

  final viewportHeight = channelDrawerState._drawerHeight;
  final fullItemsInViewport = (viewportHeight / getItemHeight(false)).floor();

  if (length <= fullItemsInViewport) {
    channelDrawerState.scrollTo(targetList: getTargetList(currentGroup), index: 0);
    return;
  }

  final currentOffset = scrollController.offset;
  final itemTop = itemIndex * getItemHeight(false);
  final itemBottom = itemTop + getItemHeight(false);

  double? alignment;
  if (itemIndex == 0) {
    alignment = 0.0;
  } else if (itemIndex == length - 1) {
    alignment = 1.0;
  } else if (isMovingDown && itemBottom > currentOffset + viewportHeight) {
    alignment = 2.0;
    channelDrawerState.scrollTo(targetList: getTargetList(currentGroup), index: itemIndex, alignment: alignment);
    return;
  } else if (!isMovingDown && itemTop < currentOffset) {
    alignment = 0.0;
    channelDrawerState.scrollTo(targetList: getTargetList(currentGroup), index: itemIndex, alignment: alignment);
    return;
  } else {
    return;
  }

  channelDrawerState.scrollTo(targetList: getTargetList(currentGroup), index: itemIndex, alignment: alignment);
}

// 获取目标列表名称
const _targetLists = ['category', 'group', 'channel'];
String getTargetList(int groupIndex) => _targetLists.elementAtOrNull(groupIndex) ?? 'category';

// 移除焦点监听器
void removeFocusListeners(int startIndex, int length) {
  if (!focusManager._restrictIndexRange(startIndex, length)) {
    LogUtil.e('removeFocusListeners: startIndex 超出范围: $startIndex');
    return;
  }
  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    focusManager.focusStates.remove(index);
  }
}

// 构建通用列表项
Widget buildGenericItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true,
  bool isEpg = false,
  List<Widget>? epgChildren,
  double minHeight = defaultMinHeight,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
  Key? key,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  final focusNode =
      (index != null && index >= 0 && index < focusManager.focusNodes.length)
          ? focusManager.focusNodes[index]
          : null;
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
            height: isEpg ? getItemHeight(true) : minHeight,
            padding: defaultPadding,
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            decoration: buildItemDecoration(
              isTV: isTV,
              hasFocus: hasFocus,
              isSelected: isSelected,
              isSystemAutoSelected: isSystemAutoSelected,
            ),
            child: isEpg && epgChildren != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: epgChildren,
                  )
                : Text(
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

// 抽象列表组件基类
abstract class BaseListWidget<T> extends StatefulWidget {
  final ScrollController scrollController;
  final bool isTV;
  final int startIndex;

  const BaseListWidget({
    super.key,
    required this.scrollController,
    required this.isTV,
    this.startIndex = 0,
  });

  int getItemCount();
  Widget buildContent(BuildContext context);

  @override
  BaseListState<T> createState();
}

// 抽象列表状态基类
abstract class BaseListState<T> extends State<BaseListWidget<T>> {
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.getItemCount(), this,
        scrollController: widget.scrollController);
  }

  @override
  void dispose() {
    if (focusManager.focusNodes.isNotEmpty &&
        widget.startIndex >= 0 &&
        widget.startIndex < focusManager.focusNodes.length) {
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

// 分类列表组件
class CategoryList extends BaseListWidget<String> {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;
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
      shrinkWrap: true,
      children: [
        RepaintBoundary(
          child: Group(
            groupIndex: 0,
            children: List.generate(categories.length, (index) {
              final category = categories[index];
              final displayTitle = category == Config.myFavoriteKey
                  ? S.of(context).myfavorite
                  : category == Config.allChannelsKey
                      ? S.of(context).allchannels
                      : category;

              return buildGenericItem(
                title: displayTitle,
                isSelected: selectedCategoryIndex == index,
                onTap: () => onCategoryTap(index),
                isCentered: true,
                isTV: isTV,
                context: context,
                index: startIndex + index,
                isLastItem: index == categories.length - 1,
                key: index == 0 ? GlobalKey() : null,
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  _CategoryListState createState() => _CategoryListState();
}

class _CategoryListState extends BaseListState<String> {}

// 分组列表组件
class GroupList extends BaseListWidget<String> {
  final List<String> keys;
  final int selectedGroupIndex;
  final Function(int index) onGroupTap;
  final bool isFavoriteCategory;
  final bool isSystemAutoSelected;

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
                style:
                    defaultTextStyle.merge(const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      controller: scrollController,
      children: [
        RepaintBoundary(
          child: Group(
            groupIndex: 1,
            children: List.generate(keys.length, (index) {
              return buildGenericItem(
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
        ),
      ],
    );
  }

  @override
  _GroupListState createState() => _GroupListState();
}

class _GroupListState extends BaseListState<String> {}

// 频道列表组件
class ChannelList extends BaseListWidget<Map<String, PlayModel>> {
  final Map<String, PlayModel> channels;
  final Function(PlayModel?) onChannelTap;
  final String? selectedChannelName;
  final bool isSystemAutoSelected;

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

    final channelDrawerState =
        context.findAncestorStateOfType<_ChannelDrawerPageState>();
    final currentGroupIndex = channelDrawerState?._groupIndex ?? -1;
    final currentPlayingGroup = channelDrawerState?.widget.playModel?.group;
    final currentGroupKeys = channelDrawerState?._keys ?? [];

    final currentGroupName = (currentGroupIndex >= 0 &&
            currentGroupIndex < currentGroupKeys.length)
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
              return buildGenericItem(
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

// EPG列表组件
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
  State<EPGList> createState() => EPGListState();
}

class EPGListState extends State<EPGList> {
  bool _shouldScroll = true;
  DateTime? _lastScrollTime;
  Timer? _scrollDebounceTimer;

  static int currentEpgDataLength = 0;

  @override
  void initState() {
    super.initState();
    EPGListState.currentEpgDataLength = widget.epgData?.length ?? 0;
    _scheduleScrollWithDebounce();
  }

  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData) {
      EPGListState.currentEpgDataLength = widget.epgData?.length ?? 0;
    }
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      _shouldScroll = true;
      _scheduleScrollWithDebounce();
    }
  }

  void _scheduleScrollWithDebounce() {
    if (!_shouldScroll || !mounted) return;

    _scrollDebounceTimer?.cancel();

    _scrollDebounceTimer = Timer(Duration(milliseconds: 150), () {
      if (mounted && widget.epgData != null && widget.epgData!.isNotEmpty) {
        final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
        if (state != null && state._epgItemScrollController.hasClients) {
          state.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: null);
          _shouldScroll = false;
          _lastScrollTime = DateTime.now();
          LogUtil.i('EPG 滚动完成: index=${widget.selectedIndex}');
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    super.dispose();
  }

  static final _appBarDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        spreadRadius: 2,
        offset: Offset(0, 2),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) return const SizedBox.shrink();
    final useFocus = widget.isTV || enableFocusInNonTVMode;
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Column(
        children: [
          Container(
            height: defaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            decoration: _appBarDecoration,
            child: Text(
              S.of(context).programListTitle,
              style: defaultTextStyle.merge(const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          verticalDivider,
          Flexible(
            child: ListView.builder(
              controller: widget.epgScrollController,
              itemCount: widget.epgData!.length,
              itemBuilder: (context, index) {
                final data = widget.epgData![index];
                final isSelect = index == widget.selectedIndex;
                final focusNode = useFocus ? FocusNode(debugLabel: 'EpgNode$index') : null;
                final hasFocus = focusNode?.hasFocus ?? false;
                final textStyle = getItemTextStyle(
                  useFocus: useFocus,
                  hasFocus: hasFocus,
                  isSelected: isSelect,
                  isSystemAutoSelected: false,
                );

                return buildGenericItem(
                  title: data.title ?? '无标题',
                  isSelected: isSelect,
                  onTap: widget.onCloseDrawer,
                  context: context,
                  isEpg: true,
                  isTV: widget.isTV,
                  isLastItem: index == widget.epgData!.length - 1,
                  isCentered: false,
                  epgChildren: [
                    Text(
                      '${data.start}-${data.end}',
                      style: textStyle.merge(const TextStyle(fontSize: 14)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      data.title ?? '无标题',
                      style: textStyle.merge(const TextStyle(fontSize: 16)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 频道抽屉页面主组件
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
    if (state != null)
      await state.updateFocusLogic(isInitial, initialIndexOverride: initialIndexOverride);
  }
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
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
  int _channelIndex = -1;
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
    'epg': {
      'controllerKey': '_epgItemScrollController',
      'countKey': null,
      'customHeight': defaultMinHeight * 1.3 + 1,
    },
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
    final config = _scrollConfig[targetList];
    if (config == null || !mounted) {
      LogUtil.i('滚动目标无效或组件已销毁: $targetList');
      return;
    }

    final scrollController = this.getField(config['controllerKey']) as ScrollController;
    if (!scrollController.hasClients) {
      LogUtil.i('$targetList 控制器未附着');
      return;
    }

    int itemCount;
    if (targetList == 'epg') {
      itemCount = EPGListState.currentEpgDataLength;
    } else if (targetList == 'channel') {
      itemCount = _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0;
    } else {
      itemCount = (this.getField(config['countKey']) as List?)?.length ?? 0;
    }

    if (itemCount == 0) {
      LogUtil.i('$targetList 数据为空');
      return;
    }

    if (index < 0 || index >= itemCount) {
      LogUtil.i('$targetList 索引超出范围: index=$index, itemCount=$itemCount');
      return;
    }

    final double localItemHeight = config['customHeight'] ?? getItemHeight(false);

    double targetOffset;
    if (alignment == 0.0) {
      targetOffset = index * localItemHeight;
    } else if (alignment == 1.0) {
      targetOffset = scrollController.position.maxScrollExtent;
    } else if (alignment == 2.0) {
      targetOffset = index * localItemHeight - (_drawerHeight - localItemHeight);
      targetOffset = targetOffset < 0 ? 0 : targetOffset;
    } else {
      final offsetAdjustment =
          (targetList == 'group' || targetList == 'channel') ? _categoryIndex.clamp(0, 6) : 2;
      targetOffset = (index - offsetAdjustment) * localItemHeight;
      if (targetList == 'epg') {
          targetOffset += (localItemHeight - defaultMinHeight); // 添加额外偏移
      }
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
    initializeData();
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey) {
      LogUtil.i(
          'didUpdateWidget 开始: refreshKey=${widget.refreshKey?.value}, oldRefreshKey=${oldWidget.refreshKey?.value}');
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
      LogUtil.i('分类列表为空');
      return;
    }
    focusManager.manageFocusNodes(categoryCount: _categories.length, resetAll: true);
    _initGroupFocusCacheForCategories();
    await updateFocusLogic(true);
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

  bool shouldLoadEpg(List<String> keys, List<Map<String, PlayModel>> values, int groupIndex) {
    return keys.isNotEmpty &&
        values.isNotEmpty &&
        groupIndex >= 0 &&
        groupIndex < values.length &&
        values[groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _scrollController.dispose();
    _scrollChannelController.dispose();
    _categoryScrollController.dispose();
    _epgItemScrollController.dispose();

    _tvKeyNavigationState?.releaseResources(preserveFocus: false);
    _tvKeyNavigationState = null;

    _groupFocusCache.clear();

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

  void _updateIndicesFromPlayModel(
      PlayModel? playModel, Map<String, Map<String, PlayModel>> categoryMap) {
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

    _isSystemAutoSelected =
        widget.playModel?.group != null && !categoryMap.containsKey(widget.playModel?.group);
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
      addFocusListeners(_categories.length, _keys.length, this,
          scrollController: _scrollController);
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
    final channelCount = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length)
        ? _values[_groupIndex].length
        : 0;
    focusManager.focusStates.clear();
    focusManager.manageFocusNodes(
        categoryCount: _categories.length, groupCount: groupCount, channelCount: channelCount);

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
        'lastFocusNode':
            focusManager.focusNodes[_channelStartIndex + _values[_groupIndex].length - 1]
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

  Future<void> updateSelection(String listType, int index) async {
    if (listType == 'category' && _categoryIndex == index || listType == 'group' && _groupIndex == index) return;
    final newIndex = listType == 'category' ? index : _groupStartIndex + index;
    _tvKeyNavigationState?.deactivateFocusManagement();
    setState(() {
      if (listType == 'category') {
        _categoryIndex = index;
        _initializeChannelData();
      } else {
        _groupIndex = index;
        final currentPlayModel = widget.playModel;
        final currentGroup = _keys[index];
        if (currentPlayModel != null && currentPlayModel.group == currentGroup) {
          _channelIndex = _values[_groupIndex].keys.toList().indexOf(currentPlayModel.title ?? '');
          if (_channelIndex == -1) _channelIndex = 0;
        } else {
          _channelIndex = 0;
        }
        _isSystemAutoSelected = false;
      }
    });
    await updateFocusLogic(false, initialIndexOverride: newIndex);
    _tvKeyNavigationState?.activateFocusManagement(initialIndexOverride: newIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToList(listType, index));
  }

  void _scrollToList(String listType, int index) {
    if (listType == 'category') {
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
    } else {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final currentPlayModel = widget.playModel;
        final currentGroup = _keys[index];
        final isChannelInGroup = currentPlayModel != null && currentPlayModel.group == currentGroup;
        scrollTo(
          targetList: 'channel',
          index: isChannelInGroup ? _channelIndex : 0,
          alignment: isChannelInGroup ? null : 0.0,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;

    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: (index) => updateSelection('category', index),
      isTV: useFocusNavigation,
      startIndex: 0,
      scrollController: _categoryScrollController,
    );

    Widget? groupListWidget;
    Widget? channelContentWidget;

    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
      onGroupTap: (index) => updateSelection('group', index),
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
    final double categoryWidth = getListWidth('category', isPortrait);
    final double groupWidth = groupListWidget != null ? getListWidth('group', isPortrait) : 0.0;

    final double channelContentWidth = (groupListWidget != null && channelContentWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - 2 * 1.5
        : 0.0;

    final totalWidth = widget.isLandscape
        ? categoryWidth + groupWidth + channelContentWidth + 2 * 1.5
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

// 频道内容组件
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
  String? _lastChannelKey;
  DateTime? _lastRequestTime;

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

    if (oldWidget.playModel?.title != widget.playModel?.title &&
        widget.playModel?.title != _lastChannelKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEPGMsgWithDebounce(widget.playModel, channelKey: widget.playModel?.title ?? '');
      });
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

    if (playModel == null || channelKey == null || channelKey.isEmpty) return;

    if (channelKey == _lastChannelKey && _epgData != null) {
      LogUtil.i('忽略重复EPG加载: channelKey=$channelKey');
      return;
    }

    final now = DateTime.now();
    final bool isRecentRequest = _lastRequestTime != null && 
                               _lastChannelKey != channelKey && 
                               now.difference(_lastRequestTime!).inMilliseconds < 500;
    
    if (isRecentRequest) {
      LogUtil.i('跳过频繁EPG请求: channelKey=$channelKey, 间隔=${now.difference(_lastRequestTime!).inMilliseconds}ms');
      return;
    }

    _lastChannelKey = channelKey;

    _epgDebounceTimer = Timer(Duration(milliseconds: 300), () {
      _lastRequestTime = DateTime.now();
      _loadEPGMsg(playModel, channelKey: channelKey);
    });
  }

  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (playModel == null || !mounted) return;
    final res = await EpgUtil.getEpg(playModel);
    LogUtil.i('EpgUtil.getEpg 返回结果: ${res != null ? "成功" : "为null"}, 播放模型: ${playModel.title}');
    if (res == null || res.epgData == null || res.epgData!.isEmpty) return;

    if (mounted) {
      setState(() {
        _epgData = res.epgData!;
        _selEPGIndex = _getInitialSelectedIndex(_epgData);
      });
    }
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

    final double channelWidth = getListWidth('channel', !widget.isTV);
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
          Expanded(
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
