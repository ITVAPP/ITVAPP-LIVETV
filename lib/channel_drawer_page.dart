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

// 是否启用非TV模式下的焦点逻辑
const bool kEnableFocusInNonTVMode = true; // 是否在非TV模式下启用焦点导航

// 尺寸常量
const double kVerticalDividerWidth = 1.5; // 垂直分割线宽度
const double kHorizontalDividerHeight = 1.0; // 水平分割线高度
const double kDefaultMinHeight = 42.0; // 默认最小高度
const double kItemPaddingVertical = 6.0; // 列表项垂直内边距
const double kItemPaddingHorizontal = 8.0; // 列表项水平内边距
const double kItemHeightExtraPadding = 12.0; // 列表项高度额外内边距
const double kItemHeightDivider = 1.0; // 列表项分隔线高度
const double kCategoryWidthPortrait = 110.0; // 竖屏模式下分类列表宽度
const double kCategoryWidthLandscape = 120.0; // 横屏模式下分类列表宽度
const double kGroupWidthPortrait = 120.0; // 竖屏模式下分组列表宽度
const double kGroupWidthLandscape = 130.0; // 横屏模式下分组列表宽度
const double kChannelWidthLandscape = 160.0; // 横屏模式下频道列表宽度
const double kBorderWidth = 1.5; // 边框宽度
const double kShadowBlurRadius = 10.0; // 阴影模糊半径
const double kShadowSpreadRadius = 2.0; // 阴影扩散半径
const double kFocusShadowBlurRadius = 8.0; // 焦点阴影模糊半径
const double kFocusShadowSpreadRadius = 1.0; // 焦点阴影扩散半径
const double kDefaultFontSize = 16.0; // 默认字体大小
const double kEpgTitleFontSize = 18.0; // EPG标题字体大小
const double kLineHeight = 1.4; // 行高
const double kShadowOffsetX = 0.0; // 阴影水平偏移
const double kShadowOffsetY = 1.0; // 阴影垂直偏移
const double kItemLeadingEdgeTolerance = 0.1; // 列表项顶部边缘容差

// 颜色常量（带中文注释）
const Color kBackgroundGradientStart = Color(0xFF1A1A1A); // 背景渐变起始颜色
const Color kBackgroundGradientEnd = Color(0xFF2C2C2C); // 背景渐变结束颜色
const Color kSelectedColor = Color(0xFFEB144C); // 选中时的颜色
const Color kFocusColor = Color(0xFFDFA02A); // 焦点颜色
const Color kWhite = Colors.white; // 白色
const Color kBlack = Colors.black; // 黑色
const double kDividerOpacityStart = 0.05; // 分割线透明度起始值
const double kDividerOpacityMid = 0.25; // 分割线透明度中间值
const double kDividerOpacityHorizontalMid = 0.15; // 水平分割线透明度中间值
const double kBorderOpacity = 0.3; // 边框和焦点透明度
const double kShadowOpacity = 0.2; // 阴影透明度
const double kEpgHeaderOpacityStart = 0.8; // EPG头部透明度起始值
const double kEpgHeaderOpacityEnd = 0.6; // EPG头部透明度结束值
const double kGradientOpacityHigh = 0.9; // 渐变透明度高值
const double kGradientOpacityLow = 0.7; // 渐变透明度低值
const double kShadowColorOpacity = 0.1; // 阴影颜色透明度
const double kTextShadowOpacity = 0.45; // 文字阴影透明度

// 样式常量（带中文注释）
const double kCornerRadius = 8.0; // 圆角半径
const double kTextShadowBlurRadius = 4.0; // 文字阴影模糊半径
const FontWeight kBoldFontWeight = FontWeight.bold; // 加粗字体粗细

// 字符串常量（带中文注释）
const String kCacheName = 'ChannelDrawerPage'; // 缓存名称
const String kTargetListCategory = 'category'; // 目标列表：分类
const String kTargetListGroup = 'group'; // 目标列表：分组
const String kTargetListChannel = 'channel'; // 目标列表：频道
const String kTargetListEpg = 'epg'; // 目标列表：EPG
const String kLocationKey = 'user_all_info'; // 位置信息键名

// 索引常量（带中文注释）
const int kInitialIndex = 0; // 初始索引
const int kGroupIndexCategory = 0; // 分组索引：分类
const int kGroupIndexGroup = 1; // 分组索引：分组
const int kGroupIndexChannel = 2; // 分组索引：频道

// 其他常量（带中文注释）
const Duration kScrollDuration = Duration.zero; // 滚动动画持续时间

// 分割线样式
final kVerticalDivider = Container(
  width: kVerticalDividerWidth,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        kWhite.withOpacity(kDividerOpacityStart),
        kWhite.withOpacity(kDividerOpacityMid),
        kWhite.withOpacity(kDividerOpacityStart),
      ],
    ),
  ),
);

final kHorizontalDivider = Container(
  height: kHorizontalDividerHeight,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        kWhite.withOpacity(kDividerOpacityStart),
        kWhite.withOpacity(kDividerOpacityHorizontalMid),
        kWhite.withOpacity(kDividerOpacityStart),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: kBlack.withOpacity(kShadowColorOpacity),
        blurRadius: kShadowBlurRadius / 5, // 调整为较小值
        offset: Offset(kShadowOffsetX, kShadowOffsetY),
      ),
    ],
  ),
);

// 文字样式
const kDefaultTextStyle = TextStyle(
  fontSize: kDefaultFontSize,
  height: kLineHeight,
  color: kWhite,
);

const kSelectedTextStyle = TextStyle(
  fontWeight: kBoldFontWeight,
  color: kWhite,
  shadows: [
    Shadow(
      offset: Offset(kShadowOffsetX, kShadowOffsetY),
      blurRadius: kTextShadowBlurRadius,
      color: Colors.black45, // 保留为 Colors.black45，因为它是 Flutter 内置颜色
    ),
  ],
);

// 计算项高度
const double kItemHeight = kDefaultMinHeight + kItemHeightExtraPadding + kItemHeightDivider;

// 背景色
final kDefaultBackgroundColor = LinearGradient(
  colors: [
    kBackgroundGradientStart,
    kBackgroundGradientEnd,
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// padding 设置
const kDefaultPadding = EdgeInsets.symmetric(
  horizontal: kItemPaddingHorizontal,
  vertical: kItemPaddingVertical,
);

// 装饰逻辑
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
              kFocusColor.withOpacity(kGradientOpacityHigh),
              kFocusColor.withOpacity(kGradientOpacityLow),
            ],
          )
        : (isSelected && !isSystemAutoSelected
            ? LinearGradient(
                colors: [
                  kSelectedColor.withOpacity(kGradientOpacityHigh),
                  kSelectedColor.withOpacity(kGradientOpacityLow),
                ],
              )
            : null);
  } else {
    return isSelected && !isSystemAutoSelected
        ? LinearGradient(
            colors: [
              kSelectedColor.withOpacity(kGradientOpacityHigh),
              kSelectedColor.withOpacity(kGradientOpacityLow),
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
          ? kWhite.withOpacity(kBorderOpacity)
          : Colors.transparent,
      width: kBorderWidth,
    ),
    borderRadius: BorderRadius.circular(kCornerRadius),
    boxShadow: hasFocus
        ? [
            BoxShadow(
              color: kFocusColor.withOpacity(kBorderOpacity),
              blurRadius: kFocusShadowBlurRadius,
              spreadRadius: kFocusShadowSpreadRadius,
            ),
          ]
        : [],
  );
}

// 焦点管理
List<FocusNode> _focusNodes = [];
Map<int, bool> _focusStates = {};

void addFocusListeners(int startIndex, int length, State state) {
  if (startIndex < kInitialIndex || length <= kInitialIndex || startIndex + length > _focusNodes.length) {
    LogUtil.e('焦点监听器索引越界: startIndex=$startIndex, length=$length, total=${_focusNodes.length}');
    return;
  }
  for (var i = kInitialIndex; i < length; i++) {
    _focusStates[startIndex + i] = _focusNodes[startIndex + i].hasFocus;
  }
  for (var i = kInitialIndex; i < length; i++) {
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

void removeFocusListeners(int startIndex, int length) {
  for (var i = kInitialIndex; i < length; i++) {
    _focusNodes[startIndex + i].removeListener(() {});
    _focusStates.remove(startIndex + i);
  }
}

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

bool isOutOfView(BuildContext context) {
  RenderObject? renderObject = context.findRenderObject();
  if (renderObject is RenderBox) {
    final ScrollableState? scrollableState = Scrollable.of(context);
    if (scrollableState != null) {
      final ScrollPosition position = scrollableState.position;
      final double offset = position.pixels;
      final double viewportHeight = position.viewportDimension;
      final Offset objectPosition = renderObject.localToGlobal(Offset.zero);
      return objectPosition.dy < offset || objectPosition.dy > offset + viewportHeight;
    }
  }
  return false;
}

Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true,
  double minHeight = kDefaultMinHeight,
  EdgeInsets padding = kDefaultPadding,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
}) {
  FocusNode? focusNode =
      (index != null && index >= kInitialIndex && index < _focusNodes.length) ? _focusNodes[index] : null;

  final hasFocus = focusNode?.hasFocus ?? false;

  final textStyle = (isTV || kEnableFocusInNonTVMode)
      ? (hasFocus
          ? kDefaultTextStyle.merge(kSelectedTextStyle)
          : (isSelected && !isSystemAutoSelected
              ? kDefaultTextStyle.merge(kSelectedTextStyle)
              : kDefaultTextStyle))
      : (isSelected && !isSystemAutoSelected
          ? kDefaultTextStyle.merge(kSelectedTextStyle)
          : kDefaultTextStyle);

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
              isTV: isTV || kEnableFocusInNonTVMode,
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
      if (!isLastItem) kHorizontalDivider,
    ],
  );

  return (isTV || kEnableFocusInNonTVMode) && useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

// 修改后的 CategoryList
class CategoryList extends StatefulWidget {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;
  final bool isTV;
  final int startIndex;
  final ItemScrollController scrollController;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.onCategoryTap,
    required this.isTV,
    this.startIndex = kInitialIndex,
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
    for (var i = kInitialIndex; i < widget.categories.length; i++) {
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
      decoration: BoxDecoration(gradient: kDefaultBackgroundColor),
      child: ScrollablePositionedList.builder(
        itemScrollController: widget.scrollController,
        itemCount: 1, // 外层只包含一个静态组
        itemBuilder: (context, _) => Group(
          groupIndex: kGroupIndexCategory,
          child: Column(
            children: List.generate(widget.categories.length, (index) {
              return buildListItem(
                title: widget.categories[index] == Config.myFavoriteKey
                    ? S.of(context).myfavorite
                    : widget.categories[index] == Config.allChannelsKey
                        ? S.of(context).allchannels
                        : widget.categories[index],
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
      ),
    );
  }
}

// 修改后的 GroupList
class GroupList extends StatefulWidget {
  final List<String> keys;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
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
    required this.positionsListener,
    required this.selectedGroupIndex,
    required this.onGroupTap,
    required this.isTV,
    this.startIndex = kInitialIndex,
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
    for (var i = kInitialIndex; i < widget.keys.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
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
      decoration: BoxDecoration(gradient: kDefaultBackgroundColor),
      child: ScrollablePositionedList.builder(
        itemScrollController: widget.scrollController,
        itemPositionsListener: widget.positionsListener,
        itemCount: 1, // 外层只包含一个静态项
        itemBuilder: (context, _) {
          if (widget.keys.isEmpty && widget.isFavoriteCategory) {
            return Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: kDefaultMinHeight),
              child: Center(
                child: Text(
                  S.of(context).nofavorite,
                  textAlign: TextAlign.center,
                  style: kDefaultTextStyle.merge(
                    const TextStyle(fontWeight: kBoldFontWeight),
                  ),
                ),
              ),
            );
          }
          return Group(
            groupIndex: kGroupIndexGroup,
            child: Column(
              children: List.generate(widget.keys.length, (index) {
                // 修改部分：添加 RepaintBoundary，与 ChannelList 保持一致
                return RepaintBoundary(
                  child: buildListItem(
                    title: widget.keys[index],
                    isSelected: widget.selectedGroupIndex == index,
                    onTap: () => widget.onGroupTap(index),
                    isCentered: false,
                    isTV: widget.isTV,
                    minHeight: kDefaultMinHeight,
                    context: context,
                    index: widget.startIndex + index,
                    isLastItem: index == widget.keys.length - 1,
                    isSystemAutoSelected: widget.isSystemAutoSelected,
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}

// 修改后的 ChannelList
class ChannelList extends StatefulWidget {
  final Map<String, PlayModel> channels;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final Function(PlayModel?) onChannelTap;
  final String? selectedChannelName;
  final bool isTV;
  final int startIndex;
  final bool isSystemAutoSelected;

  const ChannelList({
    super.key,
    required this.channels,
    required this.scrollController,
    required this.positionsListener,
    required this.onChannelTap,
    this.selectedChannelName,
    required this.isTV,
    this.startIndex = kInitialIndex,
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
    for (var i = kInitialIndex; i < widget.channels.length; i++) {
      _localFocusStates[widget.startIndex + i] = false;
    }
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
      decoration: BoxDecoration(gradient: kDefaultBackgroundColor),
      child: ScrollablePositionedList.builder(
        itemScrollController: widget.scrollController,
        itemPositionsListener: widget.positionsListener,
        itemCount: 1, // 外层只包含一个静态组
        itemBuilder: (context, _) => Group(
          groupIndex: kGroupIndexChannel,
          child: Column(
            children: List.generate(channelList.length, (index) {
              return RepaintBoundary(
                child: buildListItem(
                  title: channelList[index].key,
                  isSelected: !widget.isSystemAutoSelected && widget.selectedChannelName == channelList[index].key,
                  onTap: () => widget.onChannelTap(widget.channels[channelList[index].key]),
                  isCentered: false,
                  minHeight: kDefaultMinHeight,
                  isTV: widget.isTV,
                  context: context,
                  index: widget.startIndex + index,
                  isLastItem: index == channelList.length - 1,
                  isSystemAutoSelected: widget.isSystemAutoSelected,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

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
      decoration: BoxDecoration(gradient: kDefaultBackgroundColor),
      child: Column(
        children: [
          Container(
            height: kDefaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: kItemPaddingHorizontal),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kBlack.withOpacity(kEpgHeaderOpacityStart),
                  kBlack.withOpacity(kEpgHeaderOpacityEnd),
                ],
              ),
              borderRadius: BorderRadius.circular(kCornerRadius),
            ),
            child: Text(
              S.of(context).programListTitle,
              style: kDefaultTextStyle.merge(
                const TextStyle(
                  fontSize: kEpgTitleFontSize,
                  fontWeight: kBoldFontWeight,
                ),
              ),
            ),
          ),
          kVerticalDivider,
          Flexible(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: widget.selectedIndex,
              itemScrollController: widget.epgScrollController,
              itemCount: widget.epgData?.length ?? kInitialIndex,
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

class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final bool isLandscape;
  final Function(PlayModel? newModel)? onTapChannel;
  final VoidCallback onCloseDrawer;
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated;
  final ValueKey<int>? refreshKey;

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
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemScrollController _scrollChannelController = ItemScrollController();
  final ItemScrollController _epgItemScrollController = ItemScrollController();
  final ItemScrollController _categoryScrollController = ItemScrollController();
  final ItemPositionsListener _groupPositionsListener = ItemPositionsListener.create();
  final ItemPositionsListener _channelPositionsListener = ItemPositionsListener.create();

  TvKeyNavigationState? _tvKeyNavigationState;
  List<EpgData>? _epgData;
  int _selEPGIndex = kInitialIndex;
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
  int _categoryStartIndex = kInitialIndex;
  int _groupStartIndex = kInitialIndex;
  int _channelStartIndex = kInitialIndex;

  // 新增：视窗检查方法
  bool _isIndexInViewport(ItemPositionsListener positionsListener, int targetIndex, double viewportHeight) {
    final positions = positionsListener.itemPositions.value;
    if (positions.isEmpty) return false;

    final firstVisible = positions.firstWhere(
      (pos) => pos.itemLeadingEdge >= 0,
      orElse: () => positions.first,
    );
    final lastVisible = positions.lastWhere(
      (pos) => pos.itemTrailingEdge <= 1,
      orElse: () => positions.last,
    );

    return targetIndex >= firstVisible.index && targetIndex <= lastVisible.index;
  }

  // 修改后的 scrollTo 方法
  void scrollTo({
    required String targetList,
    required int index,
    required bool isMovingUp,
    required double viewportHeight,
    double? forceAlignment, // 新增参数：强制对齐
  }) {
    ItemScrollController? scrollController;
    ItemPositionsListener? positionsListener;
    int maxIndex = kInitialIndex;
    int itemCount = 0;

    switch (targetList) {
      case kTargetListCategory:
        scrollController = _categoryScrollController;
        positionsListener = null;
        maxIndex = _categories.length - 1;
        itemCount = _categories.length;
        break;
      case kTargetListGroup:
        scrollController = _scrollController;
        positionsListener = _groupPositionsListener;
        maxIndex = _keys.length - 1;
        itemCount = _keys.length;
        break;
      case kTargetListChannel:
        scrollController = _scrollChannelController;
        positionsListener = _channelPositionsListener;
        maxIndex = _values.isNotEmpty && _groupIndex >= kInitialIndex && _groupIndex < _values.length
            ? _values[_groupIndex].length - 1
            : kInitialIndex;
        itemCount = _values.isNotEmpty && _groupIndex >= kInitialIndex && _groupIndex < _values.length
            ? _values[_groupIndex].length
            : 0;
        break;
      case kTargetListEpg:
        scrollController = _epgItemScrollController;
        positionsListener = null;
        maxIndex = _epgData?.length ?? kInitialIndex - 1;
        itemCount = _epgData?.length ?? 0;
        break;
      default:
        LogUtil.i('Invalid scroll target: $targetList');
        return;
    }

    if (index < kInitialIndex || index > maxIndex || scrollController == null || !scrollController.isAttached) {
      LogUtil.i('$targetList scroll index out of bounds or controller not attached: index=$index, maxIndex=$maxIndex');
      return;
    }

    double alignment;
    if (forceAlignment != null) {
      // 使用强制对齐
      alignment = forceAlignment.clamp(0.0, 1.0);
    } else {
      // 现有动态对齐逻辑
      final positions = positionsListener?.itemPositions.value ?? [];
      if (positions.isEmpty && positionsListener != null) {
        alignment = isMovingUp ? 0.0 : 1.0;
      } else if (positionsListener == null) {
        alignment = isMovingUp ? 0.0 : 1.0;
      } else {
        final firstVisible = positions.firstWhere((pos) => pos.itemLeadingEdge >= 0, orElse: () => positions.first);
        final lastVisible = positions.lastWhere((pos) => pos.itemTrailingEdge <= 1, orElse: () => positions.last);
        final visibleItemCount = (viewportHeight / kItemHeight).floor();

        if (isMovingUp) {
          if (index <= firstVisible.index) {
            alignment = 0.0;
          } else if (index >= lastVisible.index - visibleItemCount + 1) {
            alignment = (index - firstVisible.index) / visibleItemCount;
          } else {
            return; // 项已在视窗内
          }
        } else {
          if (index >= lastVisible.index) {
            alignment = 1.0;
          } else if (index <= firstVisible.index + visibleItemCount - 1) {
            alignment = (index - firstVisible.index) / visibleItemCount;
          } else {
            return; // 项已在视窗内
          }
        }
      }
    }

    scrollController.scrollTo(
      index: index,
      alignment: alignment,
      duration: kScrollDuration,
    );
  }

  bool _isItemAtTop(ItemPositionsListener listener) {
    final positions = listener.itemPositions.value;
    if (positions.isEmpty) return true;
    final firstVisible = positions.first;
    return firstVisible.index == kInitialIndex &&
        (firstVisible.itemLeadingEdge >= kInitialIndex && firstVisible.itemLeadingEdge < kItemLeadingEdgeTolerance);
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
    _initializeData();
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.refreshKey != oldWidget.refreshKey) {
      _initializeData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        }
        _reInitializeFocusListeners();
      });
    }
  }

  void _initializeData() {
    _initializeCategoryData();
    _initializeChannelData();

    int totalFocusNodes = _calculateTotalFocusNodes();
    _initializeFocusNodes(totalFocusNodes);

    if (_shouldLoadEpg()) {
      _loadEPGMsg(widget.playModel);
    }
  }

  int _calculateTotalFocusNodes() {
    int totalFocusNodes = _categories.length;
    if (_categoryIndex >= kInitialIndex && _categoryIndex < _categories.length) {
      if (_keys.isNotEmpty) {
        totalFocusNodes += _keys.length;
        if (_values.isNotEmpty &&
            _groupIndex >= kInitialIndex &&
            _groupIndex < _values.length &&
            _values[_groupIndex].isNotEmpty) {
          totalFocusNodes += _values[_groupIndex].length;
        }
      }
    }
    return totalFocusNodes;
  }

  bool _shouldLoadEpg() {
    return _keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      setState(() {
        _adjustScrollPositions();
        _updateStartIndexes(includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty);
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

    for (int i = kInitialIndex; i < _categories.length; i++) {
      final category = _categories[i];
      final categoryMap = widget.videoMap?.playList[category];

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = kInitialIndex; groupIndex < categoryMap.keys.length; groupIndex++) {
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
      for (int i = kInitialIndex; i < _categories.length; i++) {
        final categoryMap = widget.videoMap?.playList[_categories[i]];
        if (categoryMap != null && categoryMap.isNotEmpty) {
          _categoryIndex = i;
          _groupIndex = kInitialIndex;
          _channelIndex = kInitialIndex;
          break;
        }
      }
    }
  }

  void _initializeChannelData() {
    if (_categoryIndex < kInitialIndex || _categoryIndex >= _categories.length) {
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
        : kInitialIndex;

    _isSystemAutoSelected = _groupIndex == -1 || _channelIndex == -1;
    _isChannelAutoSelected = _groupIndex == -1 || _channelIndex == -1;

    if (_groupIndex == -1) _groupIndex = kInitialIndex;
    if (_channelIndex == -1) _channelIndex = kInitialIndex;
  }

  void _sortByLocation() {
    String? locationStr = SpUtil.getString(kLocationKey);
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
        regionPrefix = region.length >= 2 ? region.substring(kInitialIndex, 2) : region;
      }
      if (city != null && city.isNotEmpty) {
        cityPrefix = city.length >= 2 ? city.substring(kInitialIndex, 2) : city;
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
      int oldIndex =
          widget.videoMap?.playList[_categories[_categoryIndex]]?.keys.toList().indexOf(key) ?? -1;
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
    _selEPGIndex = kInitialIndex;
  }

  void _reInitializeFocusListeners() {
    for (var node in _focusNodes) {
      node.removeListener(() {});
    }

    addFocusListeners(kInitialIndex, _categories.length, this);

    if (_keys.isNotEmpty) {
      addFocusListeners(_categories.length, _keys.length, this);
      if (_values.isNotEmpty && _groupIndex >= kInitialIndex) {
        addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          this,
        );
      }
    }
  }

  // 修改后的 _onCategoryTap 方法
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
        int totalFocusNodes = _categories.length +
            (_keys.isNotEmpty ? _keys.length : kInitialIndex) +
            (_groupIndex >= kInitialIndex && _groupIndex < _values.length ? _values[_groupIndex].length : kInitialIndex);
        _initializeFocusNodes(totalFocusNodes);
        _updateStartIndexes(includeGroupsAndChannels: true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: index);
      }
      _reInitializeFocusListeners();
      if (_keys.isNotEmpty) {
        int targetGroupIndex = (_groupIndex != -1 && widget.playModel?.group == _keys[_groupIndex])
            ? _groupIndex
            : kInitialIndex;
        final viewportHeight = _viewPortKey.currentContext?.findRenderObject()?.size.height ??
            MediaQuery.of(context).size.height;

        // 检查是否包含当前频道
        bool containsCurrentChannel = widget.playModel?.group != null && _keys.contains(widget.playModel?.group);
        bool groupInViewport = _isIndexInViewport(_groupPositionsListener, targetGroupIndex, viewportHeight);
        bool channelInViewport = _isIndexInViewport(_channelPositionsListener, _channelIndex, viewportHeight);

        if (containsCurrentChannel && !groupInViewport) {
          scrollTo(
            targetList: kTargetListGroup,
            index: targetGroupIndex,
            isMovingUp: false,
            viewportHeight: viewportHeight,
            forceAlignment: 0.5, // 居中对齐
          );
        }
        if (containsCurrentChannel && !channelInViewport) {
          scrollTo(
            targetList: kTargetListChannel,
            index: _channelIndex,
            isMovingUp: false,
            viewportHeight: viewportHeight,
            forceAlignment: 0.5, // 居中对齐
          );
        } else {
          scrollTo(
            targetList: kTargetListChannel,
            index: _channelIndex,
            isMovingUp: false,
            viewportHeight: viewportHeight,
          );
        }
        if (targetGroupIndex == kInitialIndex && !_isItemAtTop(_groupPositionsListener)) {
          scrollTo(
            targetList: kTargetListGroup,
            index: kInitialIndex,
            isMovingUp: true,
            viewportHeight: viewportHeight,
          );
        }
      }
    });
  }

  // 修改后的 _onGroupTap 方法
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;
      if (widget.playModel?.group == _keys[index]) {
        _channelIndex = _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
        if (_channelIndex == -1) _channelIndex = kInitialIndex;
      } else {
        _channelIndex = kInitialIndex;
        _isChannelAutoSelected = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      int firstChannelFocusIndex = _channelStartIndex + _channelIndex;
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!._requestFocus(firstChannelFocusIndex);
      }
      final viewportHeight = _viewPortKey.currentContext?.findRenderObject()?.size.height ??
          MediaQuery.of(context).size.height;

      // 检查是否包含当前频道
      bool containsCurrentChannel = widget.playModel?.title != null &&
          _values[_groupIndex].containsKey(widget.playModel?.title);
      bool channelInViewport = _isIndexInViewport(_channelPositionsListener, _channelIndex, viewportHeight);

      if (containsCurrentChannel && !channelInViewport) {
        scrollTo(
          targetList: kTargetListChannel,
          index: _channelIndex,
          isMovingUp: false,
          viewportHeight: viewportHeight,
          forceAlignment: 0.5, // 居中对齐
        );
      } else {
        scrollTo(
          targetList: kTargetListChannel,
          index: _channelIndex,
          isMovingUp: false,
          viewportHeight: viewportHeight,
        );
      }
      int targetCategoryIndex = (_categoryIndex != -1 &&
              widget.playModel?.title != null &&
              _values[_groupIndex].containsKey(widget.playModel?.title))
          ? _categoryIndex
          : kInitialIndex;
      scrollTo(
        targetList: kTargetListCategory,
        index: targetCategoryIndex,
        isMovingUp: false,
        viewportHeight: viewportHeight,
      );
      if (_channelIndex == kInitialIndex && !_isItemAtTop(_channelPositionsListener)) {
        scrollTo(
          targetList: kTargetListChannel,
          index: kInitialIndex,
          isMovingUp: true,
          viewportHeight: viewportHeight,
        );
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
      if (_channelIndex == -1) _channelIndex = kInitialIndex;
      _epgData = null;
      _selEPGIndex = kInitialIndex;
      _focusStates.clear();
      int totalFocusNodes = _categories.length +
          (_keys.isNotEmpty ? _keys.length : kInitialIndex) +
          (_groupIndex >= kInitialIndex && _groupIndex < _values.length ? _values[_groupIndex].length : kInitialIndex);
      _initializeFocusNodes(totalFocusNodes);
      _updateStartIndexes(includeGroupsAndChannels: true);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reInitializeFocusListeners();
      if (_tvKeyNavigationState != null) {
        int newFocusIndex = _channelStartIndex + _channelIndex;
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: newFocusIndex);
      }
      scrollTo(
        targetList: kTargetListChannel,
        index: _channelIndex,
        isMovingUp: false,
        viewportHeight: MediaQuery.of(context).size.height,
      );
      _loadEPGMsg(newModel, channelKey: newModel?.title ?? '');
    });
  }

  void _scrollToTop(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(kInitialIndex.toDouble());
    }
  }

  void _updateStartIndexes({bool includeGroupsAndChannels = true}) {
    int categoryStartIndex = kInitialIndex;
    int groupStartIndex = categoryStartIndex + _categories.length;
    int channelStartIndex = groupStartIndex + (_keys.isNotEmpty ? _keys.length : kInitialIndex);

    if (!includeGroupsAndChannels) {
      groupStartIndex = categoryStartIndex + _categories.length;
      channelStartIndex = groupStartIndex;
    }

    _categoryStartIndex = categoryStartIndex;
    _groupStartIndex = groupStartIndex;
    _channelStartIndex = channelStartIndex;
  }

  void _adjustScrollPositions() {
    scrollTo(
      targetList: kTargetListGroup,
      index: _groupIndex,
      isMovingUp: false,
      viewportHeight: MediaQuery.of(context).size.height,
    );
    scrollTo(
      targetList: kTargetListChannel,
      index: _channelIndex,
      isMovingUp: false,
      viewportHeight: MediaQuery.of(context).size.height,
    );
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
          scrollTo(
            targetList: kTargetListEpg,
            index: _selEPGIndex,
            isMovingUp: false,
            viewportHeight: MediaQuery.of(context).size.height,
          );
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
        scrollTo(
          targetList: kTargetListEpg,
          index: _selEPGIndex,
          isMovingUp: false,
          viewportHeight: MediaQuery.of(context).size.height,
        );
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  int _getInitialSelectedIndex(List<EpgData>? epgData) {
    if (epgData == null || epgData.isEmpty) return kInitialIndex;

    final currentTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');

    for (int i = epgData.length - 1; i >= kInitialIndex; i--) {
      if (epgData[i].start!.compareTo(currentTime) < kInitialIndex) {
        return i;
      }
    }

    return kInitialIndex;
  }

  List<FocusNode> _ensureCorrectFocusNodes() {
    int totalNodesExpected = _categories.length +
        (_keys.isNotEmpty ? _keys.length : kInitialIndex) +
        (_values.isNotEmpty && _groupIndex >= kInitialIndex && _groupIndex < _values.length
            ? _values[_groupIndex].length
            : kInitialIndex);
    if (_focusNodes.length != totalNodesExpected) {
      _initializeFocusNodes(totalNodesExpected);
    }
    return _focusNodes;
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || kEnableFocusInNonTVMode;

    int currentFocusIndex = kInitialIndex;

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
      positionsListener: _groupPositionsListener,
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,
      isSystemAutoSelected: _isSystemAutoSelected,
    );

    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= kInitialIndex && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length;
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: _values[_groupIndex].keys.toList()[_channelIndex],
          onChannelTap: _onChannelTap,
          isTV: useFocusNavigation,
          scrollController: _scrollChannelController,
          positionsListener: _channelPositionsListener,
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
      cacheName: kCacheName,
      isVerticalGroup: true,
      initialIndex: kInitialIndex,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      onFocusChanged: (int newIndex, int oldIndex) {
        if (newIndex == oldIndex) return;

        int groupStart = _categoryStartIndex + _categories.length;
        int channelStart = _groupStartIndex + _keys.length;

        final RenderBox? renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
        final viewportHeight = renderBox?.size.height ?? MediaQuery.of(context).size.height;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (newIndex >= _categoryStartIndex && newIndex < groupStart) {
            int categoryIndex = newIndex - _categoryStartIndex;
            setState(() {
              _categoryIndex = categoryIndex;
            });
            scrollTo(
              targetList: kTargetListCategory,
              index: categoryIndex,
              isMovingUp: newIndex < oldIndex,
              viewportHeight: viewportHeight,
            );
          } else if (newIndex >= groupStart && newIndex < channelStart) {
            int groupIndex = newIndex - groupStart;
            setState(() {
              _groupIndex = groupIndex;
            });
            scrollTo(
              targetList: kTargetListGroup,
              index: groupIndex,
              isMovingUp: newIndex < oldIndex,
              viewportHeight: viewportHeight,
            );
          } else if (newIndex >= channelStart && newIndex < _focusNodes.length) {
            int channelIndex = newIndex - channelStart;
            setState(() {
              _channelIndex = channelIndex;
            });
            scrollTo(
              targetList: kTargetListChannel,
              index: channelIndex,
              isMovingUp: newIndex < oldIndex,
              viewportHeight: viewportHeight,
            );
          } else {
            LogUtil.i('焦点索引超出范围: newIndex=$newIndex, totalFocusNodes=${_focusNodes.length}');
          }
        });
      },
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),
    );
  }

  Widget _buildOpenDrawer(
      bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
    double categoryWidth = isPortrait ? kCategoryWidthPortrait : kCategoryWidthLandscape;
    double groupWidth = groupListWidget != null ? (isPortrait ? kGroupWidthPortrait : kGroupWidthLandscape) : kInitialIndex.toDouble();

    double channelListWidth = (groupListWidget != null && channelListWidget != null)
        ? (isPortrait
            ? MediaQuery.of(context).size.width - categoryWidth - groupWidth
            : kChannelWidthLandscape)
        : kInitialIndex.toDouble();

    double epgListWidth = (groupListWidget != null && channelListWidget != null && epgListWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth
        : kInitialIndex.toDouble();

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape
          ? categoryWidth + groupWidth + channelListWidth + epgListWidth
          : MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kBackgroundGradientStart, kBackgroundGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kCornerRadius),
        boxShadow: [
          BoxShadow(
            color: kBlack.withOpacity(kShadowOpacity),
            blurRadius: kShadowBlurRadius,
            spreadRadius: kShadowSpreadRadius,
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
            kVerticalDivider,
            Container(
              width: groupWidth,
              child: groupListWidget,
            ),
          ],
          if (channelListWidget != null) ...[
            kVerticalDivider,
            Container(
              width: channelListWidth,
              child: channelListWidget,
            ),
          ],
          if (epgListWidget != null) ...[
            kVerticalDivider,
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
