import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
final verticalDivider = VerticalDivider(
  width: 0.1,
  color: Colors.white.withOpacity(0.1),
);

// 文字样式
const defaultTextStyle = TextStyle(
  fontSize: 16, // 字体大小
);

const selectedTextStyle = TextStyle(
  fontWeight: FontWeight.bold, // 选中的字体加粗
  color: Colors.white, // 选中项的字体颜色
  shadows: [
    Shadow(
      offset: Offset(1.0, 1.0),
      blurRadius: 3.0,
      color: Colors.black54,
    ),
  ],
);

// 最小高度
const defaultMinHeight = 42.0;

// 背景色
const defaultBackgroundColor = Colors.black38;

// padding设置
const defaultPadding = EdgeInsets.all(6.0);

// 装饰设置
const Color selectedColor = Color(0xFFEB144C); // 选中颜色
const Color unselectedColor = Color(0xFFDFA02A); // 焦点颜色

BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    color: hasFocus
        ? unselectedColor // 焦点优先
        : (isSelected ? selectedColor : Colors.transparent), // 没有焦点时使用选中颜色
  );
}

// 用于管理所有 FocusNode 的列表和全局焦点状态
List<FocusNode> _focusNodes = [];
Map<int, bool> _focusStates = {};

// 添加焦点监听逻辑的通用函数
void addFocusListeners(int startIndex, int length, State state) {
  // 确保索引范围有效
  if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
    return;
  }

  // 初始化这个范围内的焦点状态
  for (var i = 0; i < length; i++) {
    _focusStates[startIndex + i] = _focusNodes[startIndex + i].hasFocus;
  }

  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    // 移除旧的监听器
    _focusNodes[index].removeListener(() {});
    // 添加新的监听器，调用通用的焦点变化处理函数
    _focusNodes[index].addListener(() {
      final currentFocus = _focusNodes[index].hasFocus;
      if (_focusStates[index] != currentFocus) {
        _focusStates[index] = currentFocus;
        state.setState(() {}); // 在state中调用setState
      }
    });
  }
}

// 移除焦点监听逻辑的通用函数
void removeFocusListeners(int startIndex, int length) {
  for (var i = 0; i < length; i++) {
    _focusNodes[startIndex + i].removeListener(() {});
    _focusStates.remove(startIndex + i); // 清理对应的状态
  }
}

// 初始化 FocusNode 列表
void _initializeFocusNodes(int totalCount) {
  // 如果缓存中的 FocusNode 数量和需要的数量不一致，销毁并重建
  if (_focusNodes.length != totalCount) {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();

    // 生成新的 FocusNode 列表并缓存
    _focusNodes = List.generate(totalCount, (index) => FocusNode());
  }
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
}) {
  FocusNode? focusNode = (index != null && index >= 0 && index < _focusNodes.length)
      ? _focusNodes[index]
      : null;
Widget listItemContent = GestureDetector(
  onTap: onTap,
  child: Container(
    constraints: BoxConstraints(minHeight: minHeight),
    padding: padding,
    alignment: isCentered ? Alignment.center : Alignment.centerLeft,
    decoration: buildItemDecoration(
      isSelected: isSelected,
      hasFocus: focusNode?.hasFocus ?? false,
    ),
    child: Text(
      title,
      style: (focusNode?.hasFocus ?? false)
          ? defaultTextStyle.merge(selectedTextStyle)
          : (isSelected ? defaultTextStyle.merge(selectedTextStyle) : defaultTextStyle),
      softWrap: true,
      maxLines: null,
      overflow: TextOverflow.visible,
    ),
  ),
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
      color: defaultBackgroundColor,
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

  const GroupList({
    super.key,
    required this.keys,
    required this.scrollController,
    required this.selectedGroupIndex,
    required this.onGroupTap,
    required this.isTV,
    this.startIndex = 0,
    this.isFavoriteCategory = false,
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
      color: defaultBackgroundColor,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.keys.isEmpty && widget.isFavoriteCategory
                  ? [
                      Container(
                        constraints: BoxConstraints(minHeight: defaultMinHeight),
                        child: Center(
                          child: Text(
                            S.of(context).nofavorite,
                            style: defaultTextStyle.merge(
                              const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ]
                  : [
                      Group(
                        groupIndex: 1,
                        children: List.generate(widget.keys.length, (index) {
                          return buildListItem(
                            title: widget.keys[index],
                            isSelected: widget.selectedGroupIndex == index,
                            onTap: () => widget.onGroupTap(index),
                            isCentered: true,
                            isTV: widget.isTV,
                            minHeight: defaultMinHeight,
                            context: context,
                            index: widget.startIndex + index,
                          );
                        }),
                      ),
                    ],
            ),
          ),
        ),
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

  const ChannelList({
    super.key,
    required this.channels,
    required this.scrollController,
    required this.onChannelTap,
    this.selectedChannelName,
    required this.isTV,
    this.startIndex = 0,
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
      color: defaultBackgroundColor,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Group(
                  groupIndex: 2,
                  children: List.generate(channelList.length, (index) {
                    final channelEntry = channelList[index];
                    final channelName = channelEntry.key;
                    final isSelect = widget.selectedChannelName == channelName;

                    return buildListItem(
                      title: channelName,
                      isSelected: isSelect,
                      onTap: () => widget.onChannelTap(widget.channels[channelName]),
                      isCentered: true,
                      minHeight: defaultMinHeight,
                      isTV: widget.isTV,
                      context: context,
                      index: widget.startIndex + index,
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
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
      color: defaultBackgroundColor,
      child: Column(
        children: [
          Container(
            height: defaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: defaultBackgroundColor,
              borderRadius: BorderRadius.circular(5),
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

  const ChannelDrawerPage({
    super.key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
    required this.onCloseDrawer,
  });

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  final ItemScrollController _epgItemScrollController = ItemScrollController();
  TvKeyNavigationState? _tvKeyNavigationState;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;

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
    _initializeCategoryData();
    _initializeChannelData();

    int totalFocusNodes = _categories.length;
    totalFocusNodes += _keys.length;
    if (_values.isNotEmpty &&
        _groupIndex >= 0 &&
        _groupIndex < _values.length &&
        (_values[_groupIndex].length > 0)) {
      totalFocusNodes += (_values[_groupIndex].length);
    }
    _initializeFocusNodes(totalFocusNodes);

    _calculateViewportHeight(); // 计算视图窗口的高度

    if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel);
    }
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
    _focusNodes.forEach((node) => node.dispose());
    _focusNodes.clear();
    _focusStates.clear(); 
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final newHeight = MediaQuery.of(context).size.height * 0.5;
    if (newHeight != _viewPortHeight) {
      setState(() {
        _viewPortHeight = newHeight; // 只在高度变化时更新
        _adjustScrollPositions(); // 调整滚动位置
        _updateStartIndexes(
          includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty,
        );
      });
    }
  }

  // 计算视图窗口的高度
  void _calculateViewportHeight() {
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final height = renderBox.size.height * 0.5; // 取窗口高度的一半
        setState(() {
          _viewPortHeight = height; // 仅在初次计算时设置
          _adjustScrollPositions(); // 调整滚动位置
        });
      }
    });
  }

  // 初始化分类数据
  void _initializeCategoryData() {
    _categories = widget.videoMap?.playList?.keys.toList() ?? <String>[]; // 获取所有分类
    _categoryIndex = -1;
    _groupIndex = -1;
    _channelIndex = -1;

    // 遍历每个分类，查找当前播放的频道所属的分组和分类
    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      final categoryMap = widget.videoMap?.playList[category];

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = 0; groupIndex < categoryMap.keys.length; groupIndex++) {
          final group = categoryMap.keys.toList()[groupIndex];
          final channelMap = categoryMap[group];

          // 检查当前播放的频道是否在这个分组中
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
    // 如果索引无效，重置所有数据
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    // 频道按名字进行 Unicode 排序
    for (int i = 0; i < _values.length; i++) {
      _values[i] = Map<String, PlayModel>.fromEntries(
        _values[i].entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
    }

    _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

    if (_groupIndex == -1) _groupIndex = 0;
    if (_channelIndex == -1) _channelIndex = 0;
  }

  // 重置频道数据
  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _epgData = null;
    _selEPGIndex = 0;
  }
  
// 重新初始化所有焦点监听器的方法
void _reInitializeFocusListeners() {
  // 移除所有现有的监听器
  for (var node in _focusNodes) {
    node.removeListener(() {});
  }

  // 添加新的监听器并检查焦点变化
  addFocusListeners(0, _categories.length);

  // 如果有分组，初始化分组的监听器
  if (_keys.isNotEmpty) {
    addFocusListeners(_categories.length, _keys.length);
    // 如果有频道，初始化频道的监听器
    if (_values.isNotEmpty && _groupIndex >= 0) {
      addFocusListeners(
        _categories.length + _keys.length,
        _values[_groupIndex].length,
      );
    }
  }
}

// 切换分类时更新分组和频道
void _onCategoryTap(int index) {
  if (_categoryIndex == index) return; // 避免重复执行

  setState(() {
    _categoryIndex = index; // 更新选中的分类索引

    // 重置所有焦点状态
    _focusStates.clear();

    // 检查选中的分类是否有分组
    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    // 如果分组为空，清空 _keys 并返回
    if (categoryMap == null || categoryMap.isEmpty) {
      _resetChannelData(); 
      _initializeFocusNodes(_categories.length); // 初始化焦点节点，仅包含分类节点
      _updateStartIndexes(includeGroupsAndChannels: false); // 只计算分类的索引
    } else {
      // 分组不为空时，初始化频道数据
      _initializeChannelData();

      // 计算新分类下的总节点数，并初始化 FocusNode
      int totalFocusNodes = _categories.length
          + _keys.length
          + _values[_groupIndex].length;
      _initializeFocusNodes(totalFocusNodes);
      
      _updateStartIndexes(includeGroupsAndChannels: true);

      // 重置滚动位置
      _scrollToTop(_scrollController);
      _scrollToTop(_scrollChannelController);
    }
  });
  
  // 确保在状态更新后重新初始化焦点系统
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 调用刷新焦点组件
      _tvKeyNavigationState?.releaseResources();
      _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: index);
      // 重新初始化所有焦点监听器
      _reInitializeFocusListeners();
  });
}

// 切换分组时更新频道
void _onGroupTap(int index) {
  setState(() {
    _groupIndex = index;
    _channelIndex = 0; // 重置频道索引到第一个频道

    // 重置所有焦点状态
    _focusStates.clear();

    // 重新计算所需节点数，并初始化 FocusNode
    int totalFocusNodes = _categories.length
        + (_keys.isNotEmpty ? _keys.length : 0)
        + (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
            ? _values[_groupIndex].length
            : 0);
    _initializeFocusNodes(totalFocusNodes);

    // 重新分配索引
    _updateStartIndexes(includeGroupsAndChannels: true);
    
    _scrollToTop(_scrollChannelController);
  });

  // 确保在状态更新后重新初始化焦点系统
  WidgetsBinding.instance.addPostFrameCallback((_) {
      // 计算当前分组第一个频道项的焦点索引
      int firstChannelFocusIndex = _categories.length + _keys.length + _channelIndex;
      _tvKeyNavigationState?.releaseResources();
      _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      // 重新初始化所有焦点监听器
      _reInitializeFocusListeners();
  });
}

  // 切换频道
void _onChannelTap(PlayModel? newModel) {
  if (newModel?.title == widget.playModel?.title) return; // 防止重复点击已选频道

  // 更新本地状态，立即应用选中的样式
  setState(() {
    _channelIndex = _values[_groupIndex].keys.toList().indexOf(newModel?.title ?? '');
  });

  // 可以调用父组件的回调来处理其它逻辑
  widget.onTapChannel?.call(newModel);

  // 异步加载 EPG 数据，避免阻塞 UI 渲染
  _loadEPGMsg(newModel).then((_) {
    setState(() {}); // 当 EPG 数据加载完后，更新 UI
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
    if (!controller.hasClients) return;
    final maxScrollExtent = controller.position.maxScrollExtent;
    final double viewPortHeight = _viewPortHeight!;
    final shouldOffset = index * defaultMinHeight - viewPortHeight + defaultMinHeight * 0.5;
    controller.jumpTo(shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent);
  }

  // 加载EPG
  Future<void> _loadEPGMsg(PlayModel? playModel) async {
    if (playModel == null) return;

    setState(() {
      _epgData = null; // 清空当前节目单数据
      _selEPGIndex = 0; // 重置选中的节目单索引
    });

    try {
      final res = await EpgUtil.getEpg(playModel); // 获取EPG数据
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      final epgRangeTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm'); // 当前时间
      final selectTimeData = res.epgData!.lastWhere(
            (element) => element.start!.compareTo(epgRangeTime) < 0,
        orElse: () => res.epgData!.first, // 如果未找到，默认选中第一个节目
      ).start;
      final selectedIndex = res.epgData!.indexWhere((element) => element.start == selectTimeData);

      setState(() {
        _epgData = res.epgData!; // 更新节目单数据
        _selEPGIndex = selectedIndex;
      });

      // 在节目单数据更新后滚动到当前选中的节目项
      if (_epgData!.isNotEmpty && _selEPGIndex < _epgData!.length) {
        _epgItemScrollController.scrollTo(
          index: _selEPGIndex,
          duration: Duration.zero,
        );
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  // 检查焦点列表是否正确，如果不正确则重建
  List<FocusNode> _ensureCorrectFocusNodes() {
    int totalNodesExpected = _categories.length + (_keys.isNotEmpty ? _keys.length : 0) + (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);
    // 如果焦点节点的数量不符合预期，则重新生成焦点列表
    if (_focusNodes.length != totalNodesExpected) {
      _initializeFocusNodes(totalNodesExpected); // 根据需要重新初始化焦点节点
    }
    return _focusNodes; // 返回更新后的焦点列表
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
  );
  
  if (_keys.isNotEmpty) {
    // 频道列表
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      currentFocusIndex += _keys.length; // 更新焦点索引
      channelListWidget = ChannelList(
        channels: _values[_groupIndex],
        selectedChannelName: widget.playModel?.title,
        onChannelTap: _onChannelTap,
        isTV: isTV,
        scrollController: _scrollChannelController,
        startIndex: currentFocusIndex,  // 频道列表起始索引
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

  return TvKeyNavigation(  // 包裹整个抽屉页面，处理焦点和导航
    focusNodes: _ensureCorrectFocusNodes(), // 检查并确保焦点列表正确
    isVerticalGroup: true, // 启用竖向分组
    initialIndex: 0, // 组件不自动设置初始焦点
    onStateCreated: (state) {
      // 当 TvKeyNavigation 的 State 创建时保存引用
      _tvKeyNavigationState = state;
    },
    child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),  // 构建抽屉页面
  );
}

// 构建抽屉视图
Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
  bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
  double categoryWidth = 110; // 分类列表宽度

  // 设置分组列表宽度
  double groupWidth = groupListWidget != null ? 120 : 0;

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
        : MediaQuery.of(context).size.width, // 获取屏幕宽度
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Colors.black, Colors.transparent]),
    ),
    child: Row(
      children: [
        SizedBox(
          width: categoryWidth,
          child: categoryListWidget,
        ),
        verticalDivider,
        if (groupListWidget != null)
          SizedBox(
            width: groupWidth,
            child: groupListWidget,
          ),
        if (groupListWidget != null) verticalDivider,
        if (channelListWidget != null)
          SizedBox(
            width: channelListWidth, // 频道列表宽度
            child: channelListWidget,
          ),
        if (epgListWidget != null) ...[
          verticalDivider,
          SizedBox(
            width: epgListWidth,
            child: epgListWidget,
          ),
        ],
      ],
    ),
  );
}
}
