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

// 修改部分：添加全局常量用于列表项高度
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

// 修改部分：添加全局变量 _lastFocusedIndex
int _lastFocusedIndex = -1; // 记录上一个焦点索引，初始值为 -1 表示未设置焦点

// 修改部分：使用 ScrollablePositionedList 后的焦点监听逻辑
void addFocusListeners(
  int startIndex,
  int length,
  State state, {
  ItemScrollController? scrollController, // 修改：改为 ItemScrollController
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
          final itemIndex = index - startIndex;
          bool isMovingDown = _lastFocusedIndex != -1 && index > _lastFocusedIndex;
          _lastFocusedIndex = index;

          final channelDrawerState = state is _ChannelDrawerPageState
              ? state
              : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
          if (channelDrawerState == null) return;

          final isFirstItem = index == channelDrawerState._groupListFirstIndex ||
              index == channelDrawerState._channelListFirstIndex;
          final isLastItem = itemIndex == length - 1;

          // 计算视窗内完整项数
          final viewportHeight = channelDrawerState._drawerHeight;
          final fullItemsInViewport = (viewportHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

          if (isFirstItem) {
            scrollController.scrollTo(
              index: 0,
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('焦点滚动到首项（顶部）: itemIndex=$itemIndex');
          } else if (isLastItem && isMovingDown) {
            scrollController.scrollTo(
              index: length - 1,
              alignment: 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('焦点滚动到末项（底部）: itemIndex=$itemIndex');
          } else if (isMovingDown && itemIndex >= fullItemsInViewport) {
            final targetIndex = itemIndex - fullItemsInViewport + 1;
            scrollController.scrollTo(
              index: targetIndex.clamp(0, length - fullItemsInViewport),
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('焦点向下移动（底部对齐）: itemIndex=$itemIndex, targetIndex=$targetIndex');
          } else if (!isMovingDown && itemIndex < length - fullItemsInViewport) {
            scrollController.scrollTo(
              index: itemIndex,
              alignment: 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            LogUtil.i('焦点向上移动（顶部对齐）: itemIndex=$itemIndex');
          }
        }
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
    LogUtil.i('FocusNodes 初始化: totalCount=$totalCount, _focusNodes.length=${_focusNodes.length}');
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

// 通用列表项构建函数（修改部分：移除 key 参数，恢复鼠标点击，固定高度并避免换行）
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
              softWrap: false,              // 修改：禁用换行
              maxLines: 1,                  // 修改：限制为单行
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

// 修改部分：CategoryList 使用 ScrollablePositionedList 包裹 Group
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
          mainAxisAlignment: MainAxisAlignment.start, // 强制顶部对齐
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded( // 使用 Expanded 填充可用空间
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
          ],
        ),
      ),
    );
  }
}

// 修改部分：GroupList 使用 ScrollablePositionedList 包裹 Group
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
    // 修改部分：在焦点监听中绑定滚动控制器
    addFocusListeners(widget.startIndex, widget.keys.length, this, scrollController: widget.scrollController);
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
          : Column(
              mainAxisAlignment: MainAxisAlignment.start, // 强制顶部对齐
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded( // 使用 Expanded 填充可用空间
                  child: ScrollablePositionedList.builder(
                    itemScrollController: widget.scrollController,
                    itemCount: widget.keys.length,
                    itemBuilder: (context, index) {
                      return Group(
                        groupIndex: 1,
                        child: buildListItem(
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
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// 修改部分：ChannelList 使用 ScrollablePositionedList 包裹 Group
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
    // 修改部分：在焦点监听中绑定滚动控制器
    addFocusListeners(widget.startIndex, widget.channels.length, this, scrollController: widget.scrollController);
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start, // 强制顶部对齐
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded( // 使用 Expanded 填充可用空间
            child: ScrollablePositionedList.builder(
              itemScrollController: widget.scrollController,
              itemCount: channelList.length,
              itemBuilder: (context, index) {
                final channelEntry = channelList[index];
                final channelName = channelEntry.key;
                final isSelect = widget.selectedChannelName == channelName;
                return Group(
                  groupIndex: 2,
                  child: buildListItem(
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
                  ),
                );
              },
            ),
          ),
        ],
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
  // 修改部分：将 ScrollController 改为 ItemScrollController
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

  late List<String> _keys;
  late List<Map<String, PlayModel>> _values;
  late int _groupIndex;
  late int _channelIndex;
  late List<String> _categories;
  late int _categoryIndex;
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  // 修改部分：添加视窗高度变量，参考代码方式
  double? _viewPortHeight;

  // 修改部分：添加抽屉高度成员变量
  double _drawerHeight = 0.0;

  // 修改部分：添加第一项索引变量
  int _groupListFirstIndex = -1; // GroupList 第一项索引，初始值为 -1 表示未设置
  int _channelListFirstIndex = -1; // ChannelList 第一项索引，初始值为 -1 表示未设置

  // 修改部分：移除 _setupScrollControllerListeners，改为直接在 initState 中计算
  void _calculateViewportHeight() {
    setState(() {
      _viewPortHeight = MediaQuery.of(context).size.height * 0.5; // 参考代码方式
    });
  }

  // 修改部分：计算抽屉高度的方法
  void _calculateDrawerHeight() {
    double screenHeight = MediaQuery.of(context).size.height;
    double appBarHeight = 48.0 + 1 + MediaQuery.of(context).padding.top;
    double playerHeight = MediaQuery.of(context).size.width / (16 / 9);
    double bottomPadding = MediaQuery.of(context).padding.bottom;
    double leftPadding = MediaQuery.of(context).padding.left;

    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      _drawerHeight = screenHeight - leftPadding;
    } else {
      _drawerHeight = screenHeight - appBarHeight - playerHeight - bottomPadding - leftPadding;
      _drawerHeight = _drawerHeight > 0 ? _drawerHeight : 0;
    }
    LogUtil.i('抽屉高度计算: _drawerHeight=$_drawerHeight');
  }

  // 修改部分：优化滚动方法，使用 ItemScrollController
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        _calculateViewportHeight(); // 原有视窗高度计算
        _calculateDrawerHeight();  // 初始化抽屉高度
      });
    });
    _initializeData(); // 统一的初始化方法

    // 修改部分：在 initState 中调用 _updateStartIndexes，确保索引初始化
    _updateStartIndexes(includeGroupsAndChannels: true);
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当刷新键变化时重新初始化
    if (widget.refreshKey != oldWidget.refreshKey) {
      _initializeData(); // 修复为_initializeData
      // 重置焦点管理
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        }
        // 重新初始化所有焦点监听器
        _reInitializeFocusListeners();
        // 修改部分：更新视窗高度
        _calculateViewportHeight();
        // 修改部分：在 didUpdateWidget 中更新索引
        _updateStartIndexes(includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty);
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
    // 修改部分：修复清理逻辑，使用 scrollTo 替代 jumpTo
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
    
    // 修改部分：屏幕尺寸变化时更新视窗高度和抽屉高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _calculateViewportHeight();
        _calculateDrawerHeight();  // 更新抽屉高度
        _adjustScrollPositions();
        _updateStartIndexes(includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty);
      });
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

    // 如果有位置信息，进行排序
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

  // 位置排序逻辑（与<DOCUMENT> 完全一致）
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

  // 通用地理前缀排序方法（从 <DOCUMENT> 引用）
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

  // 修改部分：切换分类时更新分组和频道，使用 ScrollablePositionedList
  void _onCategoryTap(int index) {
    if (_categoryIndex == index) return;
    setState(() {
      _categoryIndex = index; // 更新选中的分类索引
      // 重置所有焦点状态
      _focusStates.clear();
      // 检查选中的分类是否有分组
      final selectedCategory = _categories[_categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];
      if (categoryMap == null || categoryMap.isEmpty) {
        _resetChannelData();
        _isSystemAutoSelected = true; // 空分类时设置为系统自动选中
        _initializeFocusNodes(_categories.length);
      } else {
        // 分组不为空时，初始化频道数据
        _initializeChannelData();
        // 计算新分类下的总节点数，并初始化 FocusNode
        int totalFocusNodes = _categories.length;
        // 确保_keys 不为空且_values 有效时才添加其长度
        if (_keys.isNotEmpty) {
          totalFocusNodes += _keys.length;
          // 确保 _groupIndex 有效且_values[_groupIndex] 存在
          if (_groupIndex >= 0 && _groupIndex < _values.length && _values[_groupIndex].isNotEmpty) {
            totalFocusNodes += _values[_groupIndex].length;
          }
        }
        _initializeFocusNodes(totalFocusNodes);
      }
      // 修改部分：移除条件判断，直接调用 _updateStartIndexes
      _updateStartIndexes(includeGroupsAndChannels: true);

      // 在状态更新后检查并调整滚动位置
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final viewportHeight = _drawerHeight;
        final fullItemsInViewport = (viewportHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

        if (widget.playModel?.title != null && _values[_groupIndex].containsKey(widget.playModel?.title)) {
          // 是当前播放频道所在分类
          if (_groupIndex >= fullItemsInViewport || _groupIndex < 0) {
            scrollTo(targetList: 'group', index: _groupIndex, alignment: 0.3);
            LogUtil.i('分类切换 - 分组不可见，已滚动到中间: _groupIndex=$_groupIndex');
          }
          if (_channelIndex >= fullItemsInViewport || _channelIndex < 0) {
            scrollTo(targetList: 'channel', index: _channelIndex, alignment: 0.3);
            LogUtil.i('分类切换 - 频道不可见，已滚动到中间: _channelIndex=$_channelIndex');
          }
        } else {
          // 不是当前播放频道所在分类
          if (_groupIndex != 0) {
            scrollTo(targetList: 'group', index: 0, alignment: 0.0);
            LogUtil.i('分类切换 - 分组不在顶部，已滚动到顶部');
          }
          if (_channelIndex != 0) {
            scrollTo(targetList: 'channel', index: 0, alignment: 0.0);
            LogUtil.i('分类切换 - 频道不在顶部，已滚动到顶部');
          }
        }
      });
    });

    // 重新初始化焦点系统
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: index);
      }
      _reInitializeFocusListeners();
    });
  }

  // 修改部分：切换分组时更新频道，使用 ScrollablePositionedList
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false; // 用户点击，直接设置为 false

      // 重置所有焦点状态
      _focusStates.clear();
      // 重新计算所需节点数，并初始化 FocusNode
      int totalFocusNodes = _categories.length +
          (_keys.isNotEmpty ? _keys.length : 0) +
          (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
              ? _values[_groupIndex].length
              : 0);
      _initializeFocusNodes(totalFocusNodes);
      // 重新分配索引
      _updateStartIndexes(includeGroupsAndChannels: true);

      // 在状态更新后检查并调整滚动位置
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final viewportHeight = _drawerHeight;
        final fullItemsInViewport = (viewportHeight / ITEM_HEIGHT_WITH_DIVIDER).floor();

        if (widget.playModel?.group == _keys[index]) {
          // 是当前播放频道所在分组
          _channelIndex = _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
          if (_channelIndex == -1) {
            _channelIndex = 0;
          }
          if (_channelIndex >= fullItemsInViewport || _channelIndex < 0) {
            scrollTo(targetList: 'channel', index: _channelIndex, alignment: 0.3);
            LogUtil.i('分组切换 - 频道不可见，已滚动到中间: _channelIndex=$_channelIndex');
          }
        } else {
          // 不是当前播放频道所在分组
          _channelIndex = 0;
          _isChannelAutoSelected = true;
          if (_channelIndex != 0) {
            scrollTo(targetList: 'channel', index: 0, alignment: 0.0);
            LogUtil.i('分组切换 - 频道不在顶部，已滚动到顶部');
          }
        }
      });
    });

    // 状态更新后重新初始化焦点系统
    WidgetsBinding.instance.addPostFrameCallback((_) {
      int firstChannelFocusIndex = _categories.length + _keys.length + _channelIndex;
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      }
      // 重新初始化所有焦点监听器
      _reInitializeFocusListeners();
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

  // 更新分类、分组、频道的startIndex，并更新第一项索引变量
  void _updateStartIndexes({bool includeGroupsAndChannels = true}) {
    int categoryStartIndex = 0; // 分类的起始索引
    int groupStartIndex = categoryStartIndex + _categories.length; // 分组的起始索引
    int channelStartIndex = groupStartIndex + (_keys.isNotEmpty ? _keys.length : 0); // 频道的起始索引

    if (!includeGroupsAndChannels) {
      // 如果不包含分组和频道，则分组和频道的索引只到分类部分
      groupStartIndex = categoryStartIndex + _categories.length;
      channelStartIndex = groupStartIndex; // 频道部分不参与计算
    }

    // 更新构造组件时的起始索引
    _categoryStartIndex = categoryStartIndex;
    _groupStartIndex = groupStartIndex;
    _channelStartIndex = channelStartIndex;

    // 更新第一项索引变量
    _groupListFirstIndex = groupStartIndex; // GroupList 第一项
    _channelListFirstIndex = channelStartIndex; // ChannelList 第一项
  }

  // 修改部分：调整滚动位置
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

  // 检查焦点列表是否正确，如果不正确则重建
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
    // 获取 isTV 状态
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;

    // 索引管理
    int currentFocusIndex = 0; // 从0开始

    // 修改部分：更新 build 中的列表组件
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
