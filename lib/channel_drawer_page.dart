import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
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

// 修改部分：移除全局变量 _lastFocusedIndex
// int _lastFocusedIndex = -1; // 已移除

// 修改部分：修改焦点监听逻辑，仅更新焦点状态，不控制滚动
void addFocusListeners(
  int startIndex,
  int length,
  State state,
) {
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
      }
    });
  }
}

// 移除焦点监听逻辑的通用函数
void removeFocusListeners(int startIndex, int length) {
  for (var i = 0; i < length; i++) {
    _focusNodes[startIndex + i].removeListener(() {});
    _focusStates.remove(startIndex + i);
  }
}

// 初始化 FocusNode 列表
void _initializeFocusNodes(int totalCount) {
  if (_focusNodes.length != totalCount) {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
    _focusNodes = List.generate(totalCount, (index) => FocusNode());
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

// 通用列表项构建函数
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
            constraints: BoxConstraints(minHeight: minHeight),
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
              softWrap: true,
              maxLines: null,
              overflow: TextOverflow.visible,
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

// 分类列表组件
class CategoryList extends StatefulWidget {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;
  final bool isTV;
  final int startIndex;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.onCategoryTap,
    required this.isTV,
    this.startIndex = 0,
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
    addFocusListeners(widget.startIndex, widget.categories.length, this);
  }

  @override
  void dispose() {
    removeFocusListeners(widget.startIndex, widget.categories.length);
    _localFocusStates.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Group(
        groupIndex: 0,
        child: Column(
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

// 分组列表组件
class GroupList extends StatefulWidget {
  final List<String> keys;
  final ScrollController scrollController; // 修改为ScrollController
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
    // 修改部分：移除滚动控制器参数，仅更新焦点状态
    addFocusListeners(widget.startIndex, widget.keys.length, this);
  }

  @override
  void dispose() {
    removeFocusListeners(widget.startIndex, widget.keys.length);
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
          ? ListView(
              controller: widget.scrollController,
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
            )
          : ListView(
              controller: widget.scrollController,
              children: [
                Group(
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
              ],
            ),
    );
  }
}

// 频道列表组件
class ChannelList extends StatefulWidget {
  final Map<String, PlayModel> channels;
  final ScrollController scrollController; // 修改为 ScrollController
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
    // 修改部分：移除滚动控制器参数，仅更新焦点状态
    addFocusListeners(widget.startIndex, widget.channels.length, this);
  }

  @override
  void dispose() {
    removeFocusListeners(widget.startIndex, widget.channels.length);
    _localFocusStates.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    if (channelList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: ListView(
        controller: widget.scrollController,
        children: [
          RepaintBoundary(
            child: Group(
              groupIndex: 2,
              children: List.generate(channelList.length, (index) {
                final channelEntry = channelList[index];
                final channelName = channelEntry.key;
                final isSelect = widget.selectedChannelName == channelName;
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
        ],
      ),
    );
  }
}

// EPG列表组件
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
  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  final ItemScrollController _epgItemScrollController = ItemScrollController();
  TvKeyNavigationState? _tvKeyNavigationState;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;
  bool isPortrait = true;
  bool _isSystemAutoSelected = false;
  bool _isChannelAutoSelected = false;

  final GlobalKey _viewPortKey = GlobalKey();

  late List<String> _keys;
  late List<Map<String, PlayModel>> _values;
  late int _groupIndex;
  late int _channelIndex;
  late List<String> _categories;
  late int _categoryIndex;
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  // 修改部分：添加全局视窗高度变量
  double _viewPortHeight = 0.0;

  // 修改部分：移除 ScrollController 监听器
  // void _setupScrollControllerListeners() { ... } // 已移除

  // 修改部分：添加滚动到指定位置的方法
  void _scrollToPosition(ScrollController controller, int index) {
    if (!controller.hasClients) return;
    const itemHeight = defaultMinHeight;
    final viewPortHeight = _viewPortHeight;
    final targetOffset = index * itemHeight - viewPortHeight + itemHeight * 0.5;
    final clampedOffset = targetOffset.clamp(0.0, controller.position.maxScrollExtent);
    controller.jumpTo(clampedOffset);
  }

  // 修改部分：修改 scrollTo 方法，移除 alignment 和 duration 参数
  void scrollTo({
    required String targetList,
    required int index,
  }) {
    ScrollController? scrollController;
    int maxIndex = 0;
    switch (targetList) {
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
            duration: const Duration(milliseconds: 200),
            alignment: 0.5,
          );
        }
        return;
      default:
        LogUtil.i('无效的滚动目标: $targetList');
        return;
    }

    if (index < 0 || index > maxIndex) {
      LogUtil.i('$targetList 滚动索引越界: index=$index, maxIndex=$maxIndex');
      return;
    }

    if (scrollController != null && scrollController.hasClients) {
      _scrollToPosition(scrollController, index);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
      });
    });
    // 修改部分：添加视窗高度计算
    _calculateViewportHeight();
    _initializeData();
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当刷新键变化时重新初始化
    if (widget.refreshKey != oldWidget.refreshKey) {
      _initializeData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        }
        _reInitializeFocusListeners();
        // 修改部分：更新视窗高度
        _calculateViewportHeight();
      });
    }
  }

  // 统一的初始化方法
  void _initializeData() {
    // 1. 初始化基础数据
    _initializeCategoryData();
    _initializeChannelData();

    // 2. 计算并初始化焦点节点
    int totalFocusNodes = _calculateTotalFocusNodes();
    _initializeFocusNodes(totalFocusNodes);

    // 4. 加载EPG数据（如果需要）
    if (_shouldLoadEpg()) {
      _loadEPGMsg(widget.playModel);
    }
  }

  // 计算总焦点节点数
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

  // 判断是否需要加载EPG
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
    _focusNodes.forEach((node) => node.dispose());
    _focusNodes.clear();
    _focusStates.clear();
    // 修改部分：移除 _viewportHeightCache.clear()
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
      setState(() {
        // 修改部分：使用新的视窗高度计算方法
        _calculateViewportHeight();
        _adjustScrollPositions();
        _updateStartIndexes(includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty);
      });
    });
  }

  // 修改部分：添加视窗高度计算方法
  void _calculateViewportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_viewPortKey.currentContext != null) {
        final RenderBox renderBox = _viewPortKey.currentContext!.findRenderObject() as RenderBox;
        setState(() {
          _viewPortHeight = renderBox.size.height * 0.5;
        });
      }
    });
  }

  // 修改部分：简化_handleTvKeyNavigationStateCreated，不绑定 onFocusChanged
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

  // 初始化频道数据
  void _initializeChannelData() {
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    _sortByLocation();

    _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

    _isSystemAutoSelected = _groupIndex == -1 || _channelIndex == -1;
    _isChannelAutoSelected = _groupIndex == -1 || _channelIndex == -1;

    if (_groupIndex == -1) _groupIndex = 0;
    if (_channelIndex == -1) _channelIndex = 0;
  }

  void _sortByLocation() {
    const String locationKey = 'user_all_info';
    String? locationStr = SpUtil.getString(locationKey);
    LogUtil.i('开始频道排序逻辑, locationStr: $locationStr');
    if (locationStr == null || locationStr.isEmpty) {
      LogUtil.i('未找到地理信息，跳过排序');
      return;
    }

    String? regionPrefix;
    String? cityPrefix;
    try {
      Map<String, dynamic> cacheData = jsonDecode(locationStr);
      Map<String, dynamic>? locationData = cacheData['info']?['location'];
      String? region = locationData?['region'];
      String? city = locationData?['city'];
      if (region != null && region.isNotEmpty) {
        regionPrefix = region.length >= 2 ? region.substring(0, 2) : region;
      }
      if (city != null && city.isNotEmpty) {
        cityPrefix = city.length >= 2 ? city.substring(0, 2) : city;
      }
    } catch (e) {
      LogUtil.e('解析地理信息 JSON 失败: $e');
      return;
    }

    if ((regionPrefix == null || regionPrefix.isEmpty) && (cityPrefix == null || cityPrefix.isEmpty)) {
      LogUtil.i('地理信息中未找到地区或城市，跳过排序');
      return;
    }

    _keys = _sortByGeoPrefix<String>(
      items: _keys,
      prefix: regionPrefix,
      getName: (key) => key,
    );

    List<Map<String, PlayModel>> newValues = [];
    for (String key in _keys) {
      int oldIndex = widget.videoMap?.playList[_categories[_categoryIndex]]?.keys.toList().indexOf(key) ?? -1;
      if (oldIndex != -1) {
        Map<String, PlayModel> channelMap = _values[oldIndex];
        List<String> sortedChannelKeys = _sortByGeoPrefix<String>(
          items: channelMap.keys.toList(),
          prefix: cityPrefix,
          getName: (key) => key,
        );
        Map<String, PlayModel> sortedChannels = {
          for (String channelKey in sortedChannelKeys) channelKey: channelMap[channelKey]!
        };
        newValues.add(sortedChannels);
      } else {
        LogUtil.e('位置排序时未找到键: $key');
      }
    }
    _values = newValues;

    LogUtil.i('根据地区"$regionPrefix" 和城市 "$cityPrefix" 排序完成: $_keys');
  }

  List<T> _sortByGeoPrefix<T>({
    required List<T> items,
    required String? prefix,
    required String Function(T) getName,
  }) {
    if (prefix == null || prefix.isEmpty) return items;

    List<T> matches = [];
    List<T> others = [];

    for (T item in items) {
      String name = getName(item);
      if (name.startsWith(prefix)) {
        matches.add(item);
      } else {
        others.add(item);
      }
    }

    return [...matches, ...others];
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

    addFocusListeners(0, _categories.length, this);

    if (_keys.isNotEmpty) {
      addFocusListeners(_categories.length, _keys.length, this);
      if (_values.isNotEmpty && _groupIndex >= 0) {
        addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          this,
        );
      }
    }
  }

  // 修改部分：调整分类切换逻辑，添加滚动调整
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
        _initializeFocusNodes(_categories.length);
        _updateStartIndexes(includeGroupsAndChannels: false);
      } else {
        _initializeChannelData();
        int totalFocusNodes = _categories.length;
        if (_keys.isNotEmpty) {
          totalFocusNodes += _keys.length;
          if (_groupIndex >= 0 && _groupIndex < _values.length && _values[_groupIndex].isNotEmpty) {
            totalFocusNodes += _values[_groupIndex].length;
          }
        }
        _initializeFocusNodes(totalFocusNodes);
        _updateStartIndexes(includeGroupsAndChannels: true);
        if (widget.playModel?.title == null ||
            !_values[_groupIndex].containsKey(widget.playModel?.title)) {
          _isSystemAutoSelected = true;
          scrollTo(targetList: 'group', index: 0);
          scrollTo(targetList: 'channel', index: 0);
        } else {
          _isSystemAutoSelected = false;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: index);
      }
      _reInitializeFocusListeners();
      _adjustScrollPositions(); // 新增滚动调整
    });
  }

  // 修改部分：调整分组切换逻辑，添加滚动调整
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;
      _focusStates.clear();
      int totalFocusNodes = _categories.length +
          (_keys.isNotEmpty ? _keys.length : 0) +
          (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
              ? _values[_groupIndex].length
              : 0);
      _initializeFocusNodes(totalFocusNodes);
      _updateStartIndexes(includeGroupsAndChannels: true);
      if (widget.playModel?.group == _keys[index]) {
        _channelIndex = _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
        if (_channelIndex == -1) _channelIndex = 0;
      } else {
        _channelIndex = 0;
        _isChannelAutoSelected = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      int firstChannelFocusIndex = _categories.length + _keys.length + _channelIndex;
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      }
      _reInitializeFocusListeners();
      _adjustScrollPositions(); // 新增滚动调整
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

  void _updateStartIndexes({bool includeGroupsAndChannels = true}) {
    int categoryStartIndex = 0;
    int groupStartIndex = categoryStartIndex + _categories.length;
    int channelStartIndex = groupStartIndex + (_keys.isNotEmpty ? _keys.length : 0);

    if (!includeGroupsAndChannels) {
      groupStartIndex = categoryStartIndex + _categories.length;
      channelStartIndex = groupStartIndex;
    }

    _categoryStartIndex = categoryStartIndex;
    _groupStartIndex = groupStartIndex;
    _channelStartIndex = channelStartIndex;
  }

  // 修改部分：添加调整滚动位置方法
  void _adjustScrollPositions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollToPosition(_scrollController, _groupIndex);
      }
      if (_scrollChannelController.hasClients) {
        _scrollToPosition(_scrollChannelController, _channelIndex);
      }
    });
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
          scrollTo(targetList: 'epg', index: _selEPGIndex);
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
        scrollTo(targetList: 'epg', index: _selEPGIndex);
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

  List<FocusNode> _ensureCorrectFocusNodes() {
    int totalNodesExpected = _categories.length +
        (_keys.isNotEmpty ? _keys.length : 0) +
        (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);
    if (_focusNodes.length != totalNodesExpected) {
      _initializeFocusNodes(totalNodesExpected);
    }
    return _focusNodes;
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
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,
      isSystemAutoSelected: _isSystemAutoSelected,
    );

    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length;
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: _values[_groupIndex].keys.toList()[_channelIndex],
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
      focusNodes: _ensureCorrectFocusNodes(),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: categoryWidth,
            child: categoryListWidget,
          ),
          if (groupListWidget != null) ...[
            verticalDivider,
            Container(
              width: groupWidth,
              child: groupListWidget,
            ),
          ],
          if (channelListWidget != null) ...[
            verticalDivider,
            Container(
              width: channelListWidth,
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
      ),
    );
  }
}
