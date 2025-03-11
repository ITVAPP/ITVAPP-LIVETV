import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

// 分割线样式
final verticalDivider = Container(
  width: 1.5,
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
  fontSize: 16,
  height: 1.4,
  color: Colors.white,
);

// 选中文字样式
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

// 最小高度
const defaultMinHeight = 48.0;

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
const defaultPadding = EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0);

// 装饰设置
const Color selectedColor = Color(0xFFEB144C);
const Color focusColor = Color(0xFFFFA726);

// 构建列表项装饰
BoxDecoration buildItemDecoration({
  bool isSelected = false,
  bool hasFocus = false,
  bool isTV = false,
  bool isSystemAutoSelected = false,
}) {
  return BoxDecoration(
    gradient: isTV
        ? (hasFocus
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
                : null))
        : (isSelected && !isSystemAutoSelected
            ? LinearGradient(
                colors: [
                  selectedColor.withOpacity(0.9),
                  selectedColor.withOpacity(0.7),
                ],
              )
            : null),
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

// 修改部分开始：调整 FocusHelper 为静态焦点管理风格
class FocusHelper {
  List<FocusNode> nodes;
  Map<int, bool> states = {};

  FocusHelper(this.nodes);

  // 初始化焦点节点，基于参考代码的静态管理逻辑
  void initialize(int count) {
    if (count < 0) return; // 边界检查
    if (nodes.length != count) {
      // 如果当前节点数量与目标不符，先清理所有现有节点
      for (var node in nodes) {
        node.dispose();
      }
      nodes.clear();
      states.clear();
      // 生成新的焦点节点列表
      nodes = List.generate(count, (_) => FocusNode());
    }
  }

  // 添加焦点监听
  void addListeners(int startIndex, int length, State state) {
    if (startIndex < 0 || length <= 0 || startIndex + length > nodes.length) return;
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      // 移除旧监听器并初始化状态
      nodes[index].removeListener(() {});
      states[index] = nodes[index].hasFocus;
      nodes[index].addListener(() {
        final currentFocus = nodes[index].hasFocus;
        if (states[index] != currentFocus) {
          states[index] = currentFocus;
          state.setState(() {});
        }
      });
    }
  }

  // 移除焦点监听
  void removeListeners(int startIndex, int length) {
    if (startIndex < 0 || length <= 0 || startIndex + length > nodes.length) return;
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      nodes[index].removeListener(() {});
      states.remove(index);
    }
  }

  // 清理所有资源
  void dispose() {
    for (var node in nodes) {
      node.dispose();
    }
    nodes.clear();
    states.clear();
  }
}
// 修改部分结束

// 判断是否超出可视区域函数
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

// 通用列表项构建函数 - 使用 FocusHelper 的 nodes
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
  required FocusHelper focusHelper,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
}) {
  FocusNode? focusNode = (index != null && index >= 0 && index < focusHelper.nodes.length)
      ? focusHelper.nodes[index]
      : null;

  final hasFocus = focusNode?.hasFocus ?? false;

  Widget listItemContent = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MouseRegion(
        onEnter: (_) => !isTV ? (context as Element).markNeedsBuild() : null,
        onExit: (_) => !isTV ? (context as Element).markNeedsBuild() : null,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: padding,
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            decoration: buildItemDecoration(
              isSelected: isSelected,
              hasFocus: hasFocus,
              isTV: isTV,
              isSystemAutoSelected: isSystemAutoSelected,
            ),
            child: Text(
              title,
              style: isTV
                  ? (hasFocus
                      ? defaultTextStyle.merge(selectedTextStyle)
                      : (isSelected && !isSystemAutoSelected
                          ? defaultTextStyle.merge(selectedTextStyle)
                          : defaultTextStyle))
                  : (isSelected && !isSystemAutoSelected
                      ? defaultTextStyle.merge(selectedTextStyle)
                      : defaultTextStyle),
              softWrap: true,
              maxLines: null,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
      ),
      // 如果不是最后一个项目，则添加水平分割线
      if (!isLastItem) horizontalDivider,
    ],
  );

  // 如果使用焦点项且焦点节点存在，则返回带焦点的列表项，否则返回普通内容
  return useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

abstract class FocusableListWidget<T> extends StatefulWidget {
  final List<T> items;
  final int selectedIndex;
  final Function(int index) onItemTap;
  final bool isTV;
  final int startIndex;
  final FocusHelper focusHelper;

  const FocusableListWidget({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemTap,
    required this.isTV,
    required this.focusHelper,
    this.startIndex = 0,
  });
}

// 分类列表组件
class CategoryList extends FocusableListWidget<String> {
  const CategoryList({
    super.key,
    required super.items,
    required super.selectedIndex,
    required super.onItemTap,
    required super.isTV,
    required super.focusHelper,
    super.startIndex = 0,
  });

  @override
  _CategoryListState createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  @override
  void initState() {
    super.initState();
    // 初始化时为分类列表添加焦点监听
    widget.focusHelper.addListeners(widget.startIndex, widget.items.length, this);
  }

  @override
  void dispose() {
    // 组件销毁时移除焦点监听
    widget.focusHelper.removeListeners(widget.startIndex, widget.items.length);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Group(
        groupIndex: 0,
        child: Column(
          children: List.generate(widget.items.length, (index) {
            final category = widget.items[index];
            final displayTitle = category == Config.myFavoriteKey
                ? S.of(context).myfavorite
                : category == Config.allChannelsKey
                    ? S.of(context).allchannels
                    : category;

            return buildListItem(
              title: displayTitle,
              isSelected: widget.selectedIndex == index,
              onTap: () => widget.onItemTap(index),
              isCentered: true,
              isTV: widget.isTV,
              context: context,
              index: widget.startIndex + index,
              focusHelper: widget.focusHelper,
              isLastItem: index == widget.items.length - 1,
            );
          }),
        ),
      ),
    );
  }
}

// 分组列表组件
class GroupList extends FocusableListWidget<String> {
  final ScrollController scrollController;
  final bool isFavoriteCategory;
  final bool isSystemAutoSelected;

  const GroupList({
    super.key,
    required super.items,
    required this.scrollController,
    required super.selectedIndex,
    required super.onItemTap,
    required super.isTV,
    required super.focusHelper,
    super.startIndex = 0,
    this.isFavoriteCategory = false,
    required this.isSystemAutoSelected,
  });

  @override
  _GroupListState createState() => _GroupListState();
}

class _GroupListState extends State<GroupList> {
  late List<GlobalKey> _itemKeys;

  @override
  void initState() {
    super.initState();
    // 初始化每个列表项的 GlobalKey，用于定位
    _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    // 为分组列表添加焦点监听
    widget.focusHelper.addListeners(widget.startIndex, widget.items.length, this);
  }

  @override
  void dispose() {
    // 组件销毁时移除焦点监听
    widget.focusHelper.removeListeners(widget.startIndex, widget.items.length);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果分组列表为空且不是收藏夹类别，则返回空占位符
    if (widget.items.isEmpty && !widget.isFavoriteCategory) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: widget.items.isEmpty && widget.isFavoriteCategory
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
                  children: List.generate(widget.items.length, (index) {
                    return Container(
                      key: _itemKeys[index],
                      child: buildListItem(
                        title: widget.items[index],
                        isSelected: widget.selectedIndex == index,
                        onTap: () => widget.onItemTap(index),
                        isCentered: false,
                        isTV: widget.isTV,
                        minHeight: defaultMinHeight,
                        context: context,
                        index: widget.startIndex + index,
                        focusHelper: widget.focusHelper,
                        isLastItem: index == widget.items.length - 1,
                        isSystemAutoSelected: widget.isSystemAutoSelected,
                      ),
                    );
                  }),
                ),
              ],
            ),
    );
  }

  // 获取指定索引项的上下文，用于定位或滚动
  BuildContext? getItemContext(int index) {
    // 如果索引有效，则返回对应的上下文，否则返回 null
    if (index >= 0 && index < _itemKeys.length) {
      return _itemKeys[index].currentContext;
    }
    return null;
  }
}

// 频道列表组件
class ChannelList extends StatefulWidget {
  final Map<String, PlayModel> channels;
  final ScrollController scrollController;
  final Function(PlayModel?) onChannelTap;
  final String? selectedChannelName;
  final bool isTV;
  final int startIndex;
  final bool isSystemAutoSelected;
  final FocusHelper focusHelper;

  const ChannelList({
    super.key,
    required this.channels,
    required this.scrollController,
    required this.onChannelTap,
    this.selectedChannelName,
    required this.isTV,
    required this.focusHelper,
    this.startIndex = 0,
    this.isSystemAutoSelected = false,
  });

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList> {
  late List<GlobalKey> _itemKeys;

  @override
  void initState() {
    super.initState();
    // 初始化每个频道项的 GlobalKey，用于定位
    _itemKeys = List.generate(widget.channels.length, (_) => GlobalKey());
    // 为频道列表添加焦点监听
    widget.focusHelper.addListeners(widget.startIndex, widget.channels.length, this);

    // 如果是TV模式且有选中频道，则在界面构建后调整滚动位置
    if (widget.isTV && widget.selectedChannelName != null) {
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        final index = widget.channels.keys.toList().indexOf(widget.selectedChannelName!);
        // 如果找到选中频道且超出可视区域，则滚动到可见位置
        if (index != -1 && isOutOfView(context)) {
          Scrollable.ensureVisible(context, alignment: 0.5, duration: Duration.zero);
        }
      });
    }
  }

  @override
  void dispose() {
    // 组件销毁时移除焦点监听
    widget.focusHelper.removeListeners(widget.startIndex, widget.channels.length);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    // 如果频道列表为空，则返回空占位符
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
                return Container(
                  key: _itemKeys[index],
                  child: buildListItem(
                    title: channelName,
                    isSelected: !widget.isSystemAutoSelected && isSelect,
                    onTap: () => widget.onChannelTap(widget.channels[channelName]),
                    isCentered: false,
                    minHeight: defaultMinHeight,
                    isTV: widget.isTV,
                    context: context,
                    index: widget.startIndex + index,
                    focusHelper: widget.focusHelper,
                    isLastItem: index == channelList.length - 1,
                    isSystemAutoSelected: widget.isSystemAutoSelected,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // 获取指定索引项的上下文，用于定位或滚动
  BuildContext? getItemContext(int index) {
    // 如果索引有效，则返回对应的上下文，否则返回 null
    if (index >= 0 && index < _itemKeys.length) {
      return _itemKeys[index].currentContext;
    }
    return null;
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
    // 如果 EPG 数据或选中索引发生变化，则触发状态更新
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果 EPG 数据为空或不存在，则返回空占位符
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
            padding: const EdgeInsets.only(left: 10),
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
                // 如果数据为空，则返回空占位符
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
                  focusHelper: FocusHelper([]), // EPG 不需要焦点管理
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
  static const int _epgCacheLimit = 50;
  static const Duration _epgCacheExpiry = Duration(hours: 24);
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
  double? _viewPortHeight;

  late List<String> _keys;
  late List<Map<String, PlayModel>> _values;
  late int _groupIndex;
  late int _channelIndex;
  late List<String> _categories;
  late int _categoryIndex;
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  final GlobalKey<_GroupListState> _groupListKey = GlobalKey<_GroupListState>();
  final GlobalKey<_ChannelListState> _channelListKey = GlobalKey<_ChannelListState>();

  late FocusHelper _focusHelper;

  @override
  void initState() {
    super.initState();
    // 初始化焦点管理器
    _focusHelper = FocusHelper([]);
    // 添加屏幕方向变化监听
    WidgetsBinding.instance.addObserver(this);
    // 在界面构建完成后检查屏幕方向
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
      });
    });
    // 初始化数据
    _initializeData();
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果刷新键发生变化，则重新初始化数据并调整焦点
    if (widget.refreshKey != oldWidget.refreshKey) {
      _initializeData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 释放并重新初始化焦点导航逻辑
        _tvKeyNavigationState?.releaseResources();
        _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        _reInitializeFocusListeners();
      });
    }
  }

  // 初始化数据
  void _initializeData() {
    // 初始化分类数据
    _initializeCategoryData();
    // 初始化频道数据
    _initializeChannelData();
    // 修改部分开始：使用静态焦点初始化替代动态调整
    _focusHelper.initialize(_calculateTotalFocusNodes());
    // 修改部分结束
    // 在界面构建完成后计算视口高度并加载EPG数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateViewportHeight();
      // 如果需要加载EPG，则执行加载操作
      if (_shouldLoadEpg()) _loadEPGMsg(widget.playModel);
    });
  }

  // 计算所需的总焦点节点数
  int _calculateTotalFocusNodes() {
    int total = _categories.length;
    // 如果分类索引有效，则加上分组数
    if (_categoryIndex >= 0 && _categoryIndex < _categories.length) {
      total += _keys.length;
      // 如果分组索引有效，则加上频道数
      if (_groupIndex >= 0 && _groupIndex < _values.length) {
        total += _values[_groupIndex].length;
      }
    }
    return total;
  }

  // 判断是否需要加载EPG数据
  bool _shouldLoadEpg() {
    // 如果分组和频道数据不为空，则返回 true
    return _keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    // 移除屏幕方向变化监听
    WidgetsBinding.instance.removeObserver(this);
    // 释放滚动控制器资源
    _scrollController.dispose();
    _scrollChannelController.dispose();
    // 释放焦点管理器资源
    _focusHelper.dispose();
    // 释放TV焦点导航资源
    _tvKeyNavigationState?.releaseResources();
    _tvKeyNavigationState = null;
    // 清理EPG缓存
    _clearEpgCacheIfNeeded();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 获取当前屏幕方向
    final newOrientation = MediaQuery.of(context).orientation == Orientation.portrait;
    // 如果屏幕方向发生变化，则更新状态
    if (newOrientation != isPortrait) {
      setState(() {
        isPortrait = newOrientation;
      });
    }
    // 计算新的视口高度
    final newHeight = MediaQuery.of(context).size.height * 0.5;
    // 如果视口高度发生变化，则调整滚动位置和焦点索引
    if (newHeight != _viewPortHeight) {
      setState(() {
        _viewPortHeight = newHeight;
        _adjustScrollPositions();
        _updateStartIndexes();
      });
    }
  }

  // 处理TV焦点导航状态创建
  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    // 调用外部传入的回调函数
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  // 计算视口高度
  void _calculateViewportHeight() {
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
      // 如果渲染对象存在，则计算并更新视口高度
      if (renderBox != null) {
        final height = renderBox.size.height * 0.5;
        setState(() {
          _viewPortHeight = height;
          _adjustScrollPositions();
        });
      }
    });
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

      // 如果分类映射是有效类型，则遍历分组
      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = 0; groupIndex < categoryMap.keys.length; groupIndex++) {
          final group = categoryMap.keys.toList()[groupIndex];
          final channelMap = categoryMap[group];

          // 如果频道映射存在且包含当前播放模型标题，则更新索引
          if (channelMap != null && channelMap.containsKey(widget.playModel?.title)) {
            _categoryIndex = i;
            _groupIndex = groupIndex;
            _channelIndex = channelMap.keys.toList().indexOf(widget.playModel?.title ?? '');
            return;
          }
        }
      }
    }

    // 如果未找到匹配项，则选择第一个非空分类
    if (_categoryIndex == -1) {
      for (int i = 0; i < _categories.length; i++) {
        final categoryMap = widget.videoMap?.playList[_categories[i]];
        // 如果找到非空分类，则初始化索引并退出循环
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
    // 如果分类索引无效，则重置频道数据
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory] ?? {};
    final keys = categoryMap.keys.toList();
    final values = categoryMap.values.toList();

    _keys = keys;
    _values = values;

    // 根据位置排序
    _sortByLocation();

    _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

    _isSystemAutoSelected = _groupIndex == -1 || _channelIndex == -1;
    _isChannelAutoSelected = _groupIndex == -1 || _channelIndex == -1;

    // 如果分组索引无效，则设置为0
    if (_groupIndex == -1) _groupIndex = 0;
    // 如果频道索引无效，则设置为0
    if (_channelIndex == -1) _channelIndex = 0;
  }

  // 根据用户位置排序分组
  void _sortByLocation() {
    const String locationKey = 'user_location_info';

    String? locationStr = SpUtil.getString(locationKey);
    // 如果位置信息为空，则直接返回
    if (locationStr == null || locationStr.isEmpty) return;

    try {
      List<String> lines = locationStr.split('\n');
      String? region = lines.firstWhere((line) => line.startsWith('地区:'), orElse: () => '').substring(3).trim().toLowerCase();
      String? city = lines.firstWhere((line) => line.startsWith('城市:'), orElse: () => '').substring(3).trim().toLowerCase();

      // 如果地区和城市信息均为空，则直接返回
      if (region.isEmpty && city.isEmpty) return;

      List<String> exactMatches = [];
      List<String> partialMatches = [];
      List<String> otherGroups = [];

      for (String key in _keys) {
        String lowercaseKey = key.toLowerCase();
        // 如果城市信息匹配，则加入精确匹配列表
        if (city.isNotEmpty && (lowercaseKey.contains(city) || city.contains(lowercaseKey))) {
          exactMatches.add(key);
        } 
        // 如果地区信息匹配，则加入部分匹配列表
        else if (region.isNotEmpty && (lowercaseKey.contains(region) || region.contains(lowercaseKey))) {
          partialMatches.add(key);
        } 
        // 其他分组加入剩余列表
        else {
          otherGroups.add(key);
        }
      }

      _keys = [...exactMatches, ...partialMatches, ...otherGroups];

      List<Map<String, PlayModel>> newValues = [];
      for (String key in _keys) {
        int oldIndex = widget.videoMap?.playList[_categories[_categoryIndex]]?.keys.toList().indexOf(key) ?? -1;
        // 如果找到旧索引，则更新值列表
        if (oldIndex != -1) {
          newValues.add(_values[oldIndex]);
        }
      }
      _values = newValues;

    } catch (e, stackTrace) {
      LogUtil.e('解析位置信息失败: $e\n堆栈: $stackTrace');
    }
  }

  // 重置频道数据
  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _selEPGIndex = 0;
  }

  // 重新初始化焦点监听器
  void _reInitializeFocusListeners() {
    // 移除所有现有监听器
    _focusHelper.removeListeners(0, _focusHelper.nodes.length);
    // 为分类添加监听器
    _focusHelper.addListeners(0, _categories.length, this);
    // 如果分组不为空，则为其添加监听器
    if (_keys.isNotEmpty) {
      _focusHelper.addListeners(_categories.length, _keys.length, this);
      // 如果频道数据有效，则为其添加监听器
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        _focusHelper.addListeners(_categories.length + _keys.length, _values[_groupIndex].length, this);
      }
    }
  }

  // 处理分类点击事件
  void _onCategoryTap(int index) {
    // 如果点击的是当前分类，则直接返回
    if (_categoryIndex == index) return;
    final selectedCategory = _categories[index];
    final categoryMap = widget.videoMap?.playList[selectedCategory];
    setState(() {
      _categoryIndex = index;
      // 如果分类映射为空，则重置数据并标记为系统自动选择
      if (categoryMap == null || categoryMap.isEmpty) {
        _resetChannelData();
        _isSystemAutoSelected = true;
        // 修改部分开始：使用静态焦点初始化
        _focusHelper.initialize(_categories.length);
        // 修改部分结束
        _updateStartIndexes();
        _scrollToTop(_scrollController);
        _scrollToTop(_scrollChannelController);
      } 
      // 否则初始化频道数据并更新焦点
      else {
        _initializeChannelData();
        _isSystemAutoSelected = false;
        // 修改部分开始：使用静态焦点初始化
        _focusHelper.initialize(_calculateTotalFocusNodes());
        // 修改部分结束
        _updateStartIndexes();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 释放并重新初始化焦点导航逻辑
      _tvKeyNavigationState?.releaseResources();
      _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: index);
      _reInitializeFocusListeners();
      _adjustScrollPositions();
    });
  }

  // 处理分组点击事件
  void _onGroupTap(int index) {
    // 如果点击的是当前分组，则直接返回
    if (_groupIndex == index) return;
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;
      _channelIndex = 0;
      _isChannelAutoSelected = true;
      // 修改部分开始：使用静态焦点初始化
      _focusHelper.initialize(_calculateTotalFocusNodes());
      // 修改部分结束
      _updateStartIndexes();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 释放并重新初始化焦点导航逻辑，聚焦到第一个频道
      _tvKeyNavigationState?.releaseResources();
      int firstChannelFocusIndex = _categories.length + _keys.length;
      _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      _reInitializeFocusListeners();
      _scrollToGroupItem(index);
      _scrollToChannelItem(_channelIndex);
    });
  }

  // 处理频道点击事件
  void _onChannelTap(PlayModel? newModel) {
    // 如果点击的是当前播放模型，则直接返回
    if (newModel?.title == widget.playModel?.title) return;

    _isSystemAutoSelected = false;
    _isChannelAutoSelected = false;

    // 调用外部传入的频道点击回调
    widget.onTapChannel?.call(newModel);

    setState(() {
      _channelIndex = _values[_groupIndex].keys.toList().indexOf(newModel?.title ?? '');
      _epgData = null;
      _selEPGIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 加载新的EPG数据并滚动到选中频道
      _loadEPGMsg(newModel, channelKey: newModel?.title ?? '');
      _scrollToChannelItem(_channelIndex);
    });
  }

  // 将滚动控制器滚动到顶部
  void _scrollToTop(ScrollController controller) {
    // 如果控制器已绑定，则滚动到顶部
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  // 更新焦点起始索引
  void _updateStartIndexes() {
    _categoryStartIndex = 0;
    _groupStartIndex = _categoryStartIndex + _categories.length;
    _channelStartIndex = _groupStartIndex + _keys.length;
  }

  // 调整滚动位置
  void _adjustScrollPositions() {
    // 如果视口高度未初始化，则直接返回
    if (_viewPortHeight == null) return;
    _scrollToPosition(_scrollController, _groupIndex);
    _scrollToPosition(_scrollChannelController, _channelIndex);
  }

  // 将滚动控制器滚动到指定位置（修改部分）
  void _scrollToPosition(ScrollController controller, int index) {
    // 如果控制器未绑定、视口高度未初始化或索引无效，则记录日志并返回
    if (!controller.hasClients || _viewPortHeight == null || index < 0) {
      LogUtil.i('滚动控制器未就绪或视口高度未初始化，跳过滚动');
      return;
    }
    final maxScrollExtent = controller.position.maxScrollExtent;
    final double viewPortHeight = _viewPortHeight!;
    // 使用实际项高 65.0（minHeight 48.0 + padding.vertical 16.0 + divider 1.0）
    const double itemHeight = 65.0;
    final double targetOffset = (index * itemHeight - viewPortHeight * 0.5).clamp(0.0, maxScrollExtent);
    controller.jumpTo(targetOffset);
  }

  // 滚动到指定分组项
  void _scrollToGroupItem(int index) {
    // 如果分组列表为空或索引无效，则直接返回
    if (_keys.isEmpty || index < 0 || index >= _keys.length) return;
    final groupListState = _groupListKey.currentState;
    // 如果分组状态不存在，则直接返回
    if (groupListState == null) return;

    final itemContext = groupListState.getItemContext(index);
    // 如果上下文存在且超出可视区域，则滚动到可见位置
    if (itemContext != null && isOutOfView(itemContext)) {
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  // 滚动到指定频道项
  void _scrollToChannelItem(int index) {
    // 如果频道数据无效或索引无效，则直接返回
    if (_values.isEmpty || _groupIndex < 0 || _groupIndex >= _values.length || _values[_groupIndex].isEmpty || index < 0 || index >= _values[_groupIndex].length) return;
    final channelListState = _channelListKey.currentState;
    // 如果频道状态不存在，则直接返回
    if (channelListState == null) return;

    final itemContext = channelListState.getItemContext(index);
    // 如果上下文存在且超出可视区域，则滚动到可见位置
    if (itemContext != null && isOutOfView(itemContext)) {
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  // 加载EPG信息
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    // 如果是竖屏模式或播放模型/频道键为空，则直接返回
    if (isPortrait || playModel == null || channelKey == null) return;
    // 清理过期或超限的EPG缓存
    _clearEpgCacheIfNeeded();
    try {
      final currentTime = DateTime.now();
      // 如果缓存中已有该频道的EPG数据且未过期，则直接使用缓存
      if (epgCache.containsKey(channelKey)) {
        final cacheEntry = epgCache[channelKey]!;
        if (currentTime.difference(cacheEntry['timestamp'] as DateTime) < _epgCacheExpiry) {
          setState(() {
            _epgData = cacheEntry['data'];
            _selEPGIndex = _getInitialSelectedIndex(_epgData);
          });
          // 如果EPG数据不为空，则滚动到选中项
          if (_epgData!.isNotEmpty) {
            _epgItemScrollController.scrollTo(
              index: _selEPGIndex,
              duration: Duration.zero,
            );
          }
          return;
        }
      }
      // 从网络获取EPG数据
      final res = await EpgUtil.getEpg(playModel);
      // 如果返回的EPG数据为空，则直接返回
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      final selectedIndex = _getInitialSelectedIndex(res.epgData);

      setState(() {
        _epgData = res.epgData!;
        _selEPGIndex = selectedIndex;
      });
      // 将新数据存入缓存
      epgCache[channelKey] = {
        'data': res.epgData!,
        'timestamp': currentTime,
      };
      // 如果EPG数据不为空，则滚动到选中项
      if (_epgData!.isNotEmpty) {
        _epgItemScrollController.scrollTo(
          index: _selEPGIndex,
          duration: Duration.zero,
        );
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  // 清理EPG缓存
  void _clearEpgCacheIfNeeded() {
    final now = DateTime.now();
    // 移除过期的缓存项
    epgCache.removeWhere((key, value) {
      final timestamp = value['timestamp'] as DateTime;
      return now.difference(timestamp) > _epgCacheExpiry;
    });
    // 如果缓存超出限制，则移除最早的项
    if (epgCache.length > _epgCacheLimit) {
      final keysToRemove = epgCache.keys.take(epgCache.length - _epgCacheLimit).toList();
      keysToRemove.forEach(epgCache.remove);
      LogUtil.i('EPG 缓存超出限制，已清理 ${keysToRemove.length} 项');
    }
  }

  // 获取初始选中的EPG索引
  int _getInitialSelectedIndex(List<EpgData>? epgData) {
    // 如果EPG数据为空，则返回0
    if (epgData == null || epgData.isEmpty) return 0;

    final currentTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');

    for (int i = epgData.length - 1; i >= 0; i--) {
      // 找到第一个开始时间早于当前时间的节目
      if (epgData[i].start!.compareTo(currentTime) < 0) {
        return i;
      }
    }
    // 如果没有符合条件的节目，则返回0
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;

    int currentFocusIndex = 0;

    Widget categoryListWidget = CategoryList(
      items: _categories,
      selectedIndex: _categoryIndex,
      onItemTap: _onCategoryTap,
      isTV: isTV,
      startIndex: currentFocusIndex,
      focusHelper: _focusHelper,
    );
    currentFocusIndex += _categories.length;

    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    groupListWidget = GroupList(
      key: _groupListKey,
      items: _keys,
      selectedIndex: _groupIndex,
      onItemTap: _onGroupTap,
      isTV: isTV,
      scrollController: _scrollController,
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,
      isSystemAutoSelected: _isSystemAutoSelected,
      focusHelper: _focusHelper,
    );

    // 如果分组不为空，则构建频道列表和EPG列表
    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length;
        channelListWidget = ChannelList(
          key: _channelListKey,
          channels: _values[_groupIndex],
          selectedChannelName: _values[_groupIndex].keys.toList()[_channelIndex],
          onChannelTap: _onChannelTap,
          isTV: isTV,
          scrollController: _scrollChannelController,
          startIndex: currentFocusIndex,
          isSystemAutoSelected: _isChannelAutoSelected,
          focusHelper: _focusHelper,
        );

        epgListWidget = EPGList(
          epgData: _epgData,
          selectedIndex: _selEPGIndex,
          isTV: isTV,
          epgScrollController: _epgItemScrollController,
          onCloseDrawer: widget.onCloseDrawer,
        );
      }
    }

    return TvKeyNavigation(
      focusNodes: _focusHelper.nodes,
      cacheName: 'ChannelDrawerPage',
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),
    );
  }

  // 构建抽屉界面
  Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
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
          // 如果分组列表存在，则添加垂直分割线和分组列表
          if (groupListWidget != null) ...[
            verticalDivider,
            Container(
              width: groupWidth,
              child: groupListWidget,
            ),
          ],
          // 如果频道列表存在，则添加垂直分割线和频道列表
          if (channelListWidget != null) ...[
            verticalDivider,
            Container(
              width: channelListWidth,
              child: channelListWidget,
            ),
          ],
          // 如果EPG列表存在，则添加垂直分割线和EPG列表
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
