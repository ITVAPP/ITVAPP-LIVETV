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

// 分割线样式 - 垂直分割线优化为更柔和的渐变效果（修改）
final verticalDivider = Container(
  width: 1.5, // 修改：加粗至1.5，增强视觉效果
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withOpacity(0.05), // 修改：顶部更柔和
        Colors.white.withOpacity(0.25), // 修改：中间高亮
        Colors.white.withOpacity(0.05), // 修改：底部渐淡
      ],
    ),
  ),
);

// 水平分割线样式 - 添加微妙阴影和渐变（修改）
final horizontalDivider = Container(
  height: 1,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Colors.white.withOpacity(0.05), // 修改：渐变更柔和
        Colors.white.withOpacity(0.15), // 修改：高亮部分调整
        Colors.white.withOpacity(0.05), // 修改：渐变更柔和
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1), // 修改：添加微妙阴影
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
  ),
);

// 文字样式 - 优化字体大小和行高（修改）
const defaultTextStyle = TextStyle(
  fontSize: 16, // 修改：调整为16，更符合现代设计
  height: 1.4, // 修改：增加行高，提升可读性
  color: Colors.white, // 修改：默认白色文字
);

// 选中文字样式 - 添加阴影和动态效果（修改）
const selectedTextStyle = TextStyle(
  fontWeight: FontWeight.w600, // 修改：更强的粗体效果
  color: Colors.white,
  shadows: [
    Shadow(
      offset: Offset(0, 1), // 修改：调整阴影位置
      blurRadius: 4.0, // 修改：增加模糊半径
      color: Colors.black45, // 修改：阴影颜色更柔和
    ),
  ],
);

// 最小高度 - 略微增加以适应现代设计（修改）
const defaultMinHeight = 48.0; // 修改：从42.0增加到48.0

// 背景色 - 使用更深的渐变背景（修改）
final defaultBackgroundColor = LinearGradient(
  colors: [
    Color(0xFF1A1A1A), // 修改：深灰色背景
    Color(0xFF2C2C2C), // 修改：略浅的灰色
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// padding设置 - 增加垂直间距（修改）
const defaultPadding = EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0); // 修改：增加垂直间距

// 装饰设置 - 优化选中和焦点颜色（修改）
const Color selectedColor = Color(0xFFEB144C); // 保持不变：红色高亮
const Color focusColor = Color(0xFFFFA726); // 修改：橙色焦点替代unselectedColor

// 构建列表项装饰 - 添加渐变和阴影（修改）
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
                  focusColor.withOpacity(0.9), // 修改：使用渐变焦点颜色
                  focusColor.withOpacity(0.7),
                ],
              )
            : (isSelected && !isSystemAutoSelected
                ? LinearGradient(
                    colors: [
                      selectedColor.withOpacity(0.9), // 修改：使用渐变选中颜色
                      selectedColor.withOpacity(0.7),
                    ],
                  )
                : null))
        : (isSelected && !isSystemAutoSelected
            ? LinearGradient(
                colors: [
                  selectedColor.withOpacity(0.9), // 修改：使用渐变选中颜色
                  selectedColor.withOpacity(0.7),
                ],
              )
            : null),
    border: Border.all(
      color: hasFocus || (isSelected && !isSystemAutoSelected)
          ? Colors.white.withOpacity(0.3) // 修改：边框颜色更柔和
          : Colors.transparent,
      width: 1.5, // 修改：边框宽度增加
    ),
    borderRadius: BorderRadius.circular(8), // 修改：添加圆角
    boxShadow: hasFocus
        ? [
            BoxShadow(
              color: focusColor.withOpacity(0.3), // 修改：焦点状态添加阴影
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ]
        : [],
  );
}

// 焦点管理类
class FocusManager {
  static List<FocusNode> nodes = [];
  static Map<int, bool> states = {};

  static void initialize(int count) {
    if (nodes.length != count) {
      if (nodes.length > count) {
        for (var i = count; i < nodes.length; i++) {
          nodes[i].dispose();
        }
        nodes.removeRange(count, nodes.length);
        states.removeWhere((key, _) => key >= count);
      } else {
        nodes.addAll(List.generate(count - nodes.length, (index) => FocusNode()));
      }
    }
  }

  static void dispose() {
    nodes.forEach((node) => node.dispose());
    nodes.clear();
    states.clear();
  }
}

// 添加焦点监听逻辑的通用函数
void addFocusListeners(int startIndex, int length, State state) {
  if (startIndex < 0 || length <= 0 || startIndex + length > FocusManager.nodes.length) {
    return;
  }
  for (var i = 0; i < length; i++) {
    FocusManager.states[startIndex + i] = FocusManager.nodes[startIndex + i].hasFocus;
  }
  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    FocusManager.nodes[index].removeListener(() {});
    FocusManager.nodes[index].addListener(() {
      final currentFocus = FocusManager.nodes[index].hasFocus;
      if (FocusManager.states[index] != currentFocus) {
        FocusManager.states[index] = currentFocus;
        state.setState(() {});
      }
    });
  }
}

// 移除焦点监听逻辑的通用函数
void removeFocusListeners(int startIndex, int length) {
  for (var i = 0; i < length; i++) {
    FocusManager.nodes[startIndex + i].removeListener(() {});
    FocusManager.states.remove(startIndex + i);
  }
}

// 初始化 FocusNode 列表
void _initializeFocusNodes(int totalCount) {
  FocusManager.initialize(totalCount);
}

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

// 通用列表项构建函数 - 添加动画效果（修改）
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
  FocusNode? focusNode = (index != null && index >= 0 && index < FocusManager.nodes.length)
      ? FocusManager.nodes[index]
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
          child: AnimatedContainer( // 修改：添加动画效果
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
      if (!isLastItem) horizontalDivider, // 不是最后一项时添加分割线
    ],
  );

  return useFocusableItem && focusNode != null
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
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.categories.length, this);
  }

  @override
  void dispose() {
    removeFocusListeners(widget.startIndex, widget.categories.length);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor), // 修改：使用渐变背景
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
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.keys.length, this);
  }

  @override
  void dispose() {
    removeFocusListeners(widget.startIndex, widget.keys.length);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty && !widget.isFavoriteCategory) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor), // 修改：使用渐变背景
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
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.channels.length, this);

    if (widget.isTV && widget.selectedChannelName != null) {
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        final index = widget.channels.keys.toList().indexOf(widget.selectedChannelName!);
        if (index != -1 && isOutOfView(context)) {
          Scrollable.ensureVisible(context, alignment: 0.5, duration: Duration.zero);
        }
      });
    }
  }

  @override
  void dispose() {
    removeFocusListeners(widget.startIndex, widget.channels.length);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    if (channelList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor), // 修改：使用渐变背景
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
      decoration: BoxDecoration(gradient: defaultBackgroundColor), // 修改：使用渐变背景
      child: Column(
        children: [
          Container(
            height: defaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 10), // 修改：调整内边距
            decoration: BoxDecoration(
              gradient: LinearGradient( // 修改：使用渐变背景
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(8), // 修改：添加圆角
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
  static const int _epgCacheLimit = 50; // 设置 EPG 缓存上限
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
      });
    });
    _initializeData(); // 统一的初始化方法
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当刷新键变化时重新初始化
    if (widget.refreshKey != oldWidget.refreshKey) {
      _initializeData();
      // 重置焦点管理
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        }
        // 重新初始化所有焦点监听器
        _reInitializeFocusListeners();
      });
    }
  }

  // 统一的初始化方法
  void _initializeData() {
    // 初始化分类数据
    _initializeCategoryData();

    // 初始化频道和分组数据
    _initializeChannelData();

    // 初始化焦点节点
    _initializeFocusNodes(_calculateTotalFocusNodes());

    // 延迟执行布局相关操作
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateViewportHeight();
      if (_shouldLoadEpg()) _loadEPGMsg(widget.playModel);
    });
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
    if (_scrollController.hasClients) {
      _scrollController.dispose();
    }
    if (_scrollChannelController.hasClients) {
      _scrollChannelController.dispose();
    }
    FocusManager.dispose(); // 使用封装类清理焦点资源
    _tvKeyNavigationState?.releaseResources(); // 确保 TvKeyNavigationState 资源释放
    _tvKeyNavigationState = null;
    _clearEpgCacheIfNeeded(); // 清理 EPG 缓存
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
    final newHeight = MediaQuery.of(context).size.height * 0.5;
    if (newHeight != _viewPortHeight) {
      setState(() {
        _viewPortHeight = newHeight;
        _adjustScrollPositions();
        _updateStartIndexes(
          includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty,
        );
      });
    }
  }

  // 保存 TvKeyNavigationState
  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  // 计算视图窗口的高度
  void _calculateViewportHeight() {
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
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
            _channelIndex = channelMap.keys.toList().indexOf(widget.playModel?.title ?? ''); // 设置匹配的频道
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
    final categoryMap = widget.videoMap?.playList[selectedCategory] ?? {};
    final keys = categoryMap.keys.toList();
    final values = categoryMap.values.toList();

    _keys = keys;
    _values = values;

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

  // 位置排序逻辑
  void _sortByLocation() {
    const String locationKey = 'user_location_info';

    String? locationStr = SpUtil.getString(locationKey);
    if (locationStr == null || locationStr.isEmpty) return;

    try {
      // 解析格式化的字符串
      List<String> lines = locationStr.split('\n');
      String? region = lines.firstWhere((line) => line.startsWith('地区:'), orElse: () => '').substring(3).trim().toLowerCase();
      String? city = lines.firstWhere((line) => line.startsWith('城市:'), orElse: () => '').substring(3).trim().toLowerCase();

      if (region.isEmpty && city.isEmpty) return;

      List<String> exactMatches = [];    // 城市匹配
      List<String> partialMatches = [];  // 地区匹配
      List<String> otherGroups = [];     // 其他分组

      for (String key in _keys) {
        String lowercaseKey = key.toLowerCase();
        if (city.isNotEmpty && (lowercaseKey.contains(city) || city.contains(lowercaseKey))) {
          exactMatches.add(key);
        } else if (region.isNotEmpty && (lowercaseKey.contains(region) || region.contains(lowercaseKey))) {
          partialMatches.add(key);
        } else {
          otherGroups.add(key);
        }
      }

      _keys = [...exactMatches, ...partialMatches, ...otherGroups];

      List<Map<String, PlayModel>> newValues = [];
      for (String key in _keys) {
        int oldIndex = widget.videoMap?.playList[_categories[_categoryIndex]]?.keys.toList().indexOf(key) ?? -1;
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
    //  _epgData = null;
    _selEPGIndex = 0;
  }

  // 重新初始化所有焦点监听器的方法
  void _reInitializeFocusListeners() {
    for (var i = 0; i < FocusManager.nodes.length; i++) {
      if (FocusManager.nodes[i].hasListeners) {
        FocusManager.nodes[i].removeListener(() {});
      }
    }

    void addListeners(int start, int count) {
      if (start + count > FocusManager.nodes.length) return;
      addFocusListeners(start, count, this);
    }

    addListeners(0, _categories.length);
    if (_keys.isNotEmpty) {
      addListeners(_categories.length, _keys.length);
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        addListeners(_categories.length + _keys.length, _values[_groupIndex].length);
      }
    }
  }

  // 切换分类时更新分组和频道
  void _onCategoryTap(int index) {
    if (_categoryIndex == index) return;
    final selectedCategory = _categories[index];
    final categoryMap = widget.videoMap?.playList[selectedCategory];
    if (categoryMap == null || categoryMap.isEmpty) {
      _resetChannelData();
      _updateStateAndFocus(index, -1);
      _scrollToTop(_scrollController);
      _scrollToTop(_scrollChannelController);
    } else {
      _initializeChannelData();
      _updateStateAndFocus(index, _groupIndex);
    }
  }

  // 切换分组时更新频道
  void _onGroupTap(int index) {
    if (_groupIndex == index) return;
    _updateStateAndFocus(_categoryIndex, index, resetChannel: true);
  }

  // 更新状态和焦点（新增：提取的公共逻辑）
  void _updateStateAndFocus(int newCategoryIndex, int newGroupIndex, {bool resetChannel = false}) {
    setState(() {
      _categoryIndex = newCategoryIndex;
      _groupIndex = newGroupIndex;
      if (resetChannel) _channelIndex = 0;
      _isSystemAutoSelected = false;
      FocusManager.states.clear();
      _initializeFocusNodes(_calculateTotalFocusNodes());
      _updateStartIndexes(includeGroupsAndChannels: _keys.isNotEmpty);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tvKeyNavigationState?.releaseResources();
      _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: newCategoryIndex);
      _reInitializeFocusListeners();
      _adjustScrollPositions();
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
    controller.jumpTo(0);
  }

  // 更新分类、分组、频道的 startIndex
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
  }

  // 调整分组和频道列表的滚动位置
  void _adjustScrollPositions() {
    if (_viewPortHeight == null) return;
    _scrollToPosition(_scrollController, _groupIndex);
    _scrollToPosition(_scrollChannelController, _channelIndex);
  }

  // 根据索引调整滚动位置
  void _scrollToPosition(ScrollController controller, int index) {
    if (!controller.hasClients || _viewPortHeight == null) {
      LogUtil.i('滚动控制器未就绪或视口高度未初始化，跳过滚动');
      return;
    }
    final maxScrollExtent = controller.position.maxScrollExtent;
    final double viewPortHeight = _viewPortHeight!;
    final double targetOffset = (index * defaultMinHeight - viewPortHeight * 0.5).clamp(0.0, maxScrollExtent);
    controller.animateTo(targetOffset, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  // 加载EPG
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (isPortrait || playModel == null || channelKey == null) return;
    _clearEpgCacheIfNeeded(); // 在加载新数据前检查并清理缓存
    try {
      final currentTime = DateTime.now();
      // 检查缓存是否存在且未过期
      if (epgCache.containsKey(channelKey) &&
          epgCache[channelKey]!['timestamp'].day == currentTime.day) {
        setState(() {
          _epgData = epgCache[channelKey]!['data'];
          _selEPGIndex = _getInitialSelectedIndex(_epgData);
        });
        // 在节目单数据更新后滚动到当前选中的节目项
        if (_epgData!.isNotEmpty) {
          _epgItemScrollController.scrollTo(
            index: _selEPGIndex,
            duration: Duration.zero,
          );
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
      epgCache[channelKey] = {
        'data': res.epgData!,
        'timestamp': currentTime,
      };
      // 在节目单数据更新后滚动到当前选中的节目项
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

  // 清理 EPG 缓存（新增：限制缓存大小）
  void _clearEpgCacheIfNeeded() {
    if (epgCache.length > _epgCacheLimit) {
      final keysToRemove = epgCache.keys.take(epgCache.length - _epgCacheLimit).toList();
      keysToRemove.forEach(epgCache.remove);
      LogUtil.i('EPG 缓存超出限制，已清理 ${keysToRemove.length} 项');
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
    int totalNodesExpected = _categories.length + _keys.length + (_groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);
    _initializeFocusNodes(totalNodesExpected);
    return FocusManager.nodes;
  }

  @override
  Widget build(BuildContext context) {
    // 获取 isTV 状态
    bool isTV = context.read<ThemeProvider>().isTV;

    // 索引管理
    int currentFocusIndex = 0; // 从0开始

    // 分类列表
    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: isTV,
      startIndex: currentFocusIndex,  // 分类列表起始索引
    );
    currentFocusIndex += _categories.length; // 更新焦点索引

    // 如果 _keys 为空，则不显示分组、频道和 EPG 列表
    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    // 分组列表
    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
      onGroupTap: _onGroupTap,
      isTV: isTV,
      scrollController: _scrollController,
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,  // 分组列表起始索引
      isSystemAutoSelected: _isSystemAutoSelected,
    );

    if (_keys.isNotEmpty) {
      // 频道列表
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length; // 更新焦点索引
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: _values[_groupIndex].keys.toList()[_channelIndex],
          onChannelTap: _onChannelTap,
          isTV: isTV,
          scrollController: _scrollChannelController,
          startIndex: currentFocusIndex,  // 频道列表起始索引
          isSystemAutoSelected: _isChannelAutoSelected,
        );

        // EPG 列表
        epgListWidget = EPGList(
          epgData: _epgData,
          selectedIndex: _selEPGIndex,
          isTV: isTV,
          epgScrollController: _epgItemScrollController,
          onCloseDrawer: widget.onCloseDrawer,
        );
      }
    }

    return TvKeyNavigation(  // 处理焦点和导航
      focusNodes: _ensureCorrectFocusNodes(),
      cacheName: 'ChannelDrawerPage',  // 指定缓存名称
      isVerticalGroup: true, // 启用竖向分组
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),  // 构建抽屉页面
    );
  }

  // 构建抽屉视图 - 添加整体样式（修改）
  Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
    double categoryWidth = isPortrait ? 110 : 120; // 分类列表宽度
    double groupWidth = groupListWidget != null ? (isPortrait ? 120 : 130) : 0;  // 设置分组列表宽度
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
        gradient: LinearGradient( // 修改：使用深灰色渐变
          colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12), // 修改：添加圆角
        boxShadow: [ // 修改：添加阴影
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
