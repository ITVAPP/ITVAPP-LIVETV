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

// 是否在非TV模式下启用TV模式的焦点逻辑（用于调试）
const bool enableFocusInNonTVMode = true; // 默认开启

// 垂直分割线样式 - 加粗并添加渐变效果
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

// 水平分割线样式 - 带渐变和阴影
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

// 默认文字样式 - 设置字体大小、行高和颜色
const defaultTextStyle = TextStyle(
  fontSize: 16,
  height: 1.4,
  color: Colors.white,
);

// 选中文字样式 - 加粗并添加阴影
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

// 列表项最小高度
const defaultMinHeight = 42.0;

// 列表项高度常量 - 包含和不包含分割线的情况
const double ITEM_HEIGHT_WITH_DIVIDER = defaultMinHeight + 1.0; // 43.0
const double ITEM_HEIGHT_WITHOUT_DIVIDER = defaultMinHeight; // 42.0

// 默认背景渐变色 - 从深灰到中灰
final defaultBackgroundColor = LinearGradient(
  colors: [
    Color(0xFF1A1A1A),
    Color(0xFF2C2C2C),
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// 默认内边距 - 水平8，垂直6
const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0);

// 选中和焦点颜色常量
const Color selectedColor = Color(0xFFEB144C); // 选中颜色
const Color focusColor = Color(0xFFDFA02A); // 焦点颜色

// 构建列表项装饰 - 根据状态设置渐变、边框和阴影
BoxDecoration buildItemDecoration({
  required bool isTV,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  LinearGradient? gradient;
  if (useFocus && hasFocus) {
    gradient = LinearGradient(
      colors: [focusColor.withOpacity(0.9), focusColor.withOpacity(0.7)],
    );
  } else if (isSelected && !isSystemAutoSelected) {
    gradient = LinearGradient(
      colors: [selectedColor.withOpacity(0.9), selectedColor.withOpacity(0.7)],
    );
  }

  return BoxDecoration(
    gradient: gradient,
    border: Border.all(
      color: hasFocus || (isSelected && !isSystemAutoSelected)
          ? Colors.white.withOpacity(0.3)
          : Colors.transparent,
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

// 焦点状态管理类 - 单例模式管理焦点节点和状态
class FocusStateManager {
  static final FocusStateManager _instance = FocusStateManager._internal();
  factory FocusStateManager() => _instance;
  FocusStateManager._internal();

  List<FocusNode> focusNodes = []; // 焦点节点列表
  Map<int, bool> focusStates = {}; // 焦点状态映射
  int lastFocusedIndex = -1; // 上次聚焦的索引
  Map<int, int> focusGroupIndices = {}; // 焦点组索引映射

  // 初始化焦点节点 - 根据总数生成新节点
  void initialize(int totalCount) {
    focusNodes = List.generate(totalCount, (index) => FocusNode());
    focusStates.clear();
    lastFocusedIndex = -1;
    focusGroupIndices.clear();
  }

  // 释放焦点节点资源
  void dispose() {
    for (var node in focusNodes) {
      node.dispose();
    }
    focusNodes.clear();
    focusStates.clear();
  }
}

final focusManager = FocusStateManager(); // 全局焦点管理实例

// 用于动态获取列表项高度的全局键和变量
final GlobalKey _itemKey = GlobalKey(); // 获取分类列表项高度的键
double? _dynamicItemHeight; // 动态存储列表项高度

// 获取动态列表项高度 - 从渲染对象获取或使用默认值
void getItemHeight(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final RenderBox? renderBox = _itemKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      _dynamicItemHeight = renderBox.size.height;
    } else {
      _dynamicItemHeight = ITEM_HEIGHT_WITH_DIVIDER;
      LogUtil.i('动态获取分类列表项高度失败，使用默认值: $_dynamicItemHeight');
    }
  });
}

// 添加焦点监听器 - 为指定范围的焦点节点添加状态监听
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

  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    focusManager.focusStates[index] ??= focusManager.focusNodes[index].hasFocus;
  }

  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    focusManager.focusNodes[index].addListener(() {
      final currentFocus = focusManager.focusNodes[index].hasFocus;
      if (focusManager.focusStates[index] != currentFocus) {
        focusManager.focusStates[index] = currentFocus;
        state.setState(() {});
        if (scrollController != null && currentFocus && scrollController.hasClients) {
          _handleScroll(index, startIndex, state, scrollController);
        }
      }
    });
  }
}

// 处理焦点切换时的滚动逻辑
void _handleScroll(int index, int startIndex, State state, ScrollController scrollController) {
  final itemIndex = index - startIndex;
  final currentGroup = focusManager.focusGroupIndices[index] ?? -1;
  final lastGroup = focusManager.lastFocusedIndex != -1 ? (focusManager.focusGroupIndices[focusManager.lastFocusedIndex] ?? -1) : -1;
  final isInitialFocus = focusManager.lastFocusedIndex == -1;
  final isMovingDown = !isInitialFocus && index > focusManager.lastFocusedIndex;
  focusManager.lastFocusedIndex = index;

  final channelDrawerState = state is _ChannelDrawerPageState
      ? state
      : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
  if (channelDrawerState == null) return;

  if (currentGroup == 0) return; // 分类组不滚动

  final viewportHeight = channelDrawerState._drawerHeight;
  final itemHeight = _dynamicItemHeight ?? ITEM_HEIGHT_WITH_DIVIDER;
  final fullItemsInViewport = (viewportHeight / itemHeight).floor();

  if (channelDrawerState._keys.length <= fullItemsInViewport) {
    channelDrawerState.scrollTo(targetList: _getTargetList(currentGroup), index: 0);
    return;
  }

  final currentOffset = scrollController.offset;
  final itemTop = itemIndex * itemHeight;
  final itemBottom = itemTop + itemHeight;

  double? alignment;
  if (itemIndex == 0) {
    alignment = 0.0; // 第一个项顶部对齐
  } else if (itemIndex == channelDrawerState._keys.length - 1) {
    alignment = 1.0; // 最后一个项底部对齐
  } else if (isMovingDown && itemBottom > currentOffset + viewportHeight) {
    alignment = 2.0; // 下移超出视窗，底部对齐
    channelDrawerState.scrollTo(
      targetList: _getTargetList(currentGroup),
      index: itemIndex,
      alignment: alignment,
    );
    return;
  } else if (!isMovingDown && itemTop < currentOffset) {
    alignment = 0.0; // 上移超出顶部，顶部对齐
    channelDrawerState.scrollTo(
      targetList: _getTargetList(currentGroup),
      index: itemIndex,
      alignment: alignment,
    );
    return;
  } else {
    return; // 项目在视窗内，无需滚动
  }

  channelDrawerState.scrollTo(
    targetList: _getTargetList(currentGroup),
    index: itemIndex,
    alignment: alignment,
  );
}

// 根据组索引获取目标列表名称
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

// 移除焦点监听器 - 清理指定范围的监听和状态
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

// 初始化焦点节点 - 根据总数重新生成并记录日志
void _initializeFocusNodes(int totalCount) {
  if (focusManager.focusNodes.length != totalCount) {
    for (final node in focusManager.focusNodes) {
      node.dispose();
    }
    focusManager.focusNodes.clear();
    focusManager.focusStates.clear();
    focusManager.focusNodes = List.generate(totalCount, (index) => FocusNode());
  }
}

// 构建列表项 - 支持焦点、选中样式和点击事件
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

  final textStyle = useFocus
      ? (hasFocus
          ? defaultTextStyle.merge(selectedTextStyle)
          : (isSelected && !isSystemAutoSelected ? defaultTextStyle.merge(selectedTextStyle) : defaultTextStyle))
      : (isSelected && !isSystemAutoSelected ? defaultTextStyle.merge(selectedTextStyle) : defaultTextStyle);

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

// 修改部分：抽象列表组件基类 - 定义通用属性和抽象方法
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

  // 抽象方法：获取列表项总数
  int getItemCount();

  // 抽象方法：构建列表内容
  Widget buildContent(BuildContext context);

  @override
  BaseListState<T> createState();
}

// 修改部分：抽象列表状态基类 - 管理焦点监听和构建内容
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

// 修改部分：分类列表组件 - 显示分类并支持选中和点击
class CategoryList extends BaseListWidget {
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

class _CategoryListState extends BaseListState<CategoryList> {}

// 修改部分：分组列表组件 - 显示分组并支持选中和点击
class GroupList extends BaseListWidget {
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

class _GroupListState extends BaseListState<GroupList> {}

// 修改部分：频道列表组件 - 显示频道并支持选中和点击
class ChannelList extends BaseListWidget {
  final Map<String, PlayModel> channels; // 频道数据映射
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
        Group(
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
      ],
    );
  }

  @override
  _ChannelListState createState() => _ChannelListState();
}

class _ChannelListState extends BaseListState<ChannelList> {}

// EPG列表组件 - 显示节目单并支持滚动到选中项
class EPGList extends StatefulWidget {
  final List<EpgData>? epgData; // EPG数据列表
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
  bool _shouldScroll = true; // 标记是否需要滚动

  @override
  void initState() {
    super.initState();
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      _shouldScroll = true; // 数据或选中项变化时标记需要滚动
      setState(() {});
    }
  }

  // 调度滚动，确保在布局完成后执行
  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shouldScroll && widget.epgData != null && widget.epgData!.isNotEmpty) {
        final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
        if (state != null && state._epgItemScrollController.hasClients) {
          state.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: null);
          _shouldScroll = false; // 滚动成功后重置
          LogUtil.i('EPG 滚动完成: index=${widget.selectedIndex}');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) return const SizedBox.shrink();

    _scheduleScroll(); // 确保每次构建时检查滚动需求
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

// 主组件 - 频道抽屉页面，管理分类、分组、频道和EPG显示
class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap; // 播放列表数据
  final PlayModel? playModel; // 当前播放模型
  final bool isLandscape; // 是否为横屏
  final Function(PlayModel? newModel)? onTapChannel; // 频道点击回调
  final VoidCallback onCloseDrawer; // 关闭抽屉回调
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated; // TV导航状态创建回调
  final ValueKey<int>? refreshKey; // 刷新键

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

  // 静态方法 - 初始化数据
  static Future<void> initializeData() async {
    final state = _stateKey.currentState;
    if (state != null) await state.initializeData();
  }

  // 静态方法 - 更新焦点逻辑
  static Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    final state = _stateKey.currentState;
    if (state != null) await state.updateFocusLogic(isInitial, initialIndexOverride: initialIndexOverride);
  }

  // 静态方法 - 滚动到指定列表位置
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
  final Map<String, Map<String, dynamic>> epgCache = {}; // EPG缓存
  final ScrollController _scrollController = ScrollController(); // 分组滚动控制器
  final ScrollController _scrollChannelController = ScrollController(); // 频道滚动控制器
  final ScrollController _categoryScrollController = ScrollController(); // 分类滚动控制器
  final ScrollController _epgItemScrollController = ScrollController(); // EPG滚动控制器
  TvKeyNavigationState? _tvKeyNavigationState; // TV导航状态
  List<EpgData>? _epgData; // 当前EPG数据
  int _selEPGIndex = 0; // 选中EPG索引
  bool isPortrait = true; // 是否为竖屏
  bool _isSystemAutoSelected = false; // 是否系统自动选中分组
  bool _isChannelAutoSelected = false; // 是否系统自动选中频道

  final GlobalKey _viewPortKey = GlobalKey(); // 视口键
  List<String> _categories = []; // 分类列表
  List<String> _keys = []; // 分组键列表
  List<Map<String, PlayModel>> _values = []; // 频道值列表
  int _groupIndex = -1; // 当前分组索引
  int _channelIndex = -1; // 当前频道索引
  int _categoryIndex = -1; // 当前分类索引
  int _categoryStartIndex = 0; // 分类焦点起始索引
  int _groupStartIndex = 0; // 分组焦点起始索引
  int _channelStartIndex =  0; // 频道焦点起始索引

  double _drawerHeight = 0.0; // 抽屉高度

  int _categoryListFirstIndex = 0; // 分类列表首个焦点索引
  int _groupListFirstIndex = -1; // 分组列表首个焦点索引
  int _channelListLastIndex = -1; // 频道列表最后一个焦点索引
  int _categoryListLastIndex = -1; // 分类列表最后一个焦点索引
  int _groupListLastIndex = -1; // 分组列表最后一个焦点索引
  int _channelListFirstIndex = -1; // 频道列表首个焦点索引

  Map<int, Map<String, FocusNode>> _groupFocusCache = {}; // 分组焦点缓存

  // 获取状态栏高度 - 根据设备像素比计算
  double getStatusBarHeight() {
    final height = appui.window.viewPadding.top / appui.window.devicePixelRatio;
    return height;
  }

  // 计算抽屉高度 - 根据屏幕方向调整
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

  // 滚动到指定列表位置 - 支持动画和对齐方式
  Future<void> scrollTo({
    required String targetList,
    required int index,
    double? alignment,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final scrollConfig = {
      'category': {'controller': _categoryScrollController, 'count': _categories.length},
      'group': {'controller': _scrollController, 'count': _keys.length},
      'channel': {
        'controller': _scrollChannelController,
        'count': _values.isNotEmpty && _groupIndex >= 0 ? _values[_groupIndex].length : 0
      },
      'epg': {'controller': _epgItemScrollController, 'count': _epgData?.length ?? 0},
    };

    final config = scrollConfig[targetList];
    if (config == null) {
      LogUtil.e('无效的滚动目标: $targetList');
      return;
    }

    final scrollController = config['controller'] as ScrollController;
    final itemCount = config['count'] as int;
    final double itemHeight = _dynamicItemHeight ?? ITEM_HEIGHT_WITH_DIVIDER;

    if (index < 0 || index >= itemCount || !scrollController.hasClients) {
      LogUtil.e('$targetList 滚动索引越界或未附着: index=$index');
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

  @override
  void initState() {
    super.initState();
    _calculateDrawerHeight();
    WidgetsBinding.instance.addObserver(this);

    initializeData();
    updateFocusLogic(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shouldLoadEpg()) _loadEPGMsg(widget.playModel);
      getItemHeight(context);
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoMap != oldWidget.videoMap || widget.playModel != oldWidget.playModel) {
      initializeData();
      updateFocusLogic(false);
      setState(() {});
    }
  }

  // 初始化所有数据 - 包括分类和频道
  Future<void> initializeData() async {
    _initializeCategoryData();
    _initializeChannelData();
    await updateFocusLogic(true);
  }

  // 计算焦点节点总数 - 包括分类、分组和频道
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

  // 判断是否需要加载EPG数据
  bool _shouldLoadEpg() {
    return _keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty;
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
      if (newOrientation != isPortrait) {
        setState(() {
          isPortrait = newOrientation;
        });
      }
      setState(() {
        _calculateDrawerHeight();
        getItemHeight(context);
        _adjustScrollPositions();
      });
    });
  }

  // 处理TV导航状态创建 - 更新状态并调用回调
  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  // 初始化分类数据 - 设置当前分类、分组和频道索引
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

  // 初始化频道数据 - 根据选中分类设置分组和频道
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

  // 重置频道数据 - 清空分组和频道信息
  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _selEPGIndex = 0;
  }

  // 重新初始化焦点监听器 - 为所有节点添加监听
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

  // 更新焦点逻辑 - 初始化焦点节点并设置分组缓存
  Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    focusManager.lastFocusedIndex = -1;

    int totalNodes = _categories.length +
        (_keys.isNotEmpty ? _keys.length : 0) +
        (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);

    for (final node in focusManager.focusNodes) node.dispose();
    focusManager.focusNodes.clear();
    focusManager.focusNodes = List.generate(totalNodes, (index) => FocusNode(debugLabel: 'Node$index'));
    focusManager.focusGroupIndices.clear();

    _categoryStartIndex = 0;
    _groupStartIndex = _categories.length;
    _channelStartIndex = _categories.length + _keys.length;

    for (int i = 0; i < _categories.length; i++) {
      focusManager.focusGroupIndices[i] = 0;
    }
    for (int i = 0; i < _keys.length; i++) {
      focusManager.focusGroupIndices[_groupStartIndex + i] = 1;
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      for (int i = 0; i < _values[_groupIndex].length; i++) {
        focusManager.focusGroupIndices[_channelStartIndex + i] = 2;
      }
    }

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
        'firstFocusNode': focusManager.focusNodes[_categoryListFirstIndex],
        'lastFocusNode': focusManager.focusNodes[_categoryListLastIndex]
      };
    }
    if (_keys.isNotEmpty) {
      _groupFocusCache[1] = {
        'firstFocusNode': focusManager.focusNodes[_groupListFirstIndex],
        'lastFocusNode': focusManager.focusNodes[_groupListLastIndex]
      };
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      _groupFocusCache[2] = {
        'firstFocusNode': focusManager.focusNodes[_channelListFirstIndex],
        'lastFocusNode': focusManager.focusNodes[_channelListLastIndex]
      };
    }

    final groupFocusCacheLog = _groupFocusCache.map((key, value) => MapEntry(
          key,
          '{first: ${focusManager.focusNodes.indexOf(value['firstFocusNode']!)}, last: ${focusManager.focusNodes.indexOf(value['lastFocusNode']!)}}',
        ));
    LogUtil.i('焦点逻辑更新: categoryStart=$_categoryStartIndex, groupStart=$_groupStartIndex, '
        'channelStart=$_channelStartIndex');

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

  // 处理分类点击 - 更新状态并滚动到相关位置
  void _onCategoryTap(int index) async {
    if (_categoryIndex == index) return;

    _categoryIndex = index;
    focusManager.focusStates.clear();
    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];
    if (categoryMap == null || categoryMap.isEmpty) {
      _resetChannelData();
      _isSystemAutoSelected = true;
    } else {
      _initializeChannelData();
      final currentPlayModel = widget.playModel;
      if (currentPlayModel != null && categoryMap.containsKey(currentPlayModel.group)) {
        _groupIndex = _keys.indexOf(currentPlayModel.group!);
        if (_groupIndex != -1) {
          final channelList = _values[_groupIndex].keys.toList();
          _channelIndex = channelList.indexOf(currentPlayModel.title ?? '');
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

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.deactivateFocusManagement();
    }

    await updateFocusLogic(false, initialIndexOverride: index);

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.activateFocusManagement();
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

  // 处理分组点击 - 更新状态并滚动到相关频道
  void _onGroupTap(int index) async {
    _groupIndex = index;
    _isSystemAutoSelected = false;
    focusManager.focusStates.clear();

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
      _tvKeyNavigationState!.activateFocusManagement();
    }

    setState(() {});
    if (focusManager.focusNodes.isNotEmpty && _groupStartIndex + index < focusManager.focusNodes.length) {
      focusManager.focusNodes[_groupStartIndex + index].requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentPlayModel = widget.playModel;
      final currentGroup = _keys[index];
      final isChannelInGroup = currentPlayModel != null && currentPlayModel.group == currentGroup;

      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        scrollTo(
          targetList: 'channel',
          index: isChannelInGroup ? _channelIndex : 0,
          alignment: isChannelInGroup ? null : 0.0,
        );
      }
    });
  }

  // 处理频道点击 - 更新播放模型并加载EPG
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

  // 调整滚动位置 - 将分组和频道滚动到可见区域
  void _adjustScrollPositions() {
    scrollTo(targetList: 'group', index: _groupIndex, alignment: null);
    scrollTo(targetList: 'channel', index: _channelIndex, alignment: null);
  }

  // 加载EPG数据 - 从缓存或网络获取并更新状态
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
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  // 获取初始选中EPG索引 - 基于当前时间
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

    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: useFocusNavigation,
      startIndex: 0,
      scrollController: _categoryScrollController,
    );

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
      startIndex: _categories.length,
      isSystemAutoSelected: _isSystemAutoSelected,
    );

    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        String? selectedChannelName = _channelIndex >= 0 && _values[_groupIndex].isNotEmpty
            ? _values[_groupIndex].keys.toList()[_channelIndex]
            : null;
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: selectedChannelName,
          onChannelTap: _onChannelTap,
          isTV: useFocusNavigation,
          scrollController: _scrollChannelController,
          startIndex: _categories.length + _keys.length,
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
      focusNodes: focusManager.focusNodes,
      groupFocusCache: _groupFocusCache,
      cacheName: 'ChannelDrawerPage',
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),
    );
  }

  // 构建抽屉布局 - 横向排列分类、分组、频道和EPG
  Widget _buildOpenDrawer(
    bool isTV,
    Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelListWidget,
    Widget? epgListWidget,
  ) {
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
