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

// 分割线样式 - 垂直分割线加粗且增加渐变效果
final verticalDivider = Container(
  width: 1,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withOpacity(0.1),
        Colors.white.withOpacity(0.2),
        Colors.white.withOpacity(0.1),
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
        Colors.white.withOpacity(0.08),
        Colors.white.withOpacity(0.2),
        Colors.white.withOpacity(0.08),
      ],
    ),
  ),
);

// 文字样式
const defaultTextStyle = TextStyle(
  fontSize: 17, // 字体大小
  height: 1.3,  // 调整行高
);

const selectedTextStyle = TextStyle(
  fontWeight: FontWeight.bold,
  color: Colors.white, 
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
const defaultBackgroundColor = Colors.black54;

// padding设置
const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0);

// 装饰设置
const Color selectedColor = Color(0xFFEB144C); // 选中颜色
const Color unselectedColor = Color(0xFFDFA02A); // 焦点颜色

BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false, bool isTV = false}) {
  return BoxDecoration(
    color: isTV
        ? (hasFocus 
            ? unselectedColor.withOpacity(0.8)  
            : (isSelected ? selectedColor.withOpacity(0.9) : Colors.transparent))
        : (isSelected ? selectedColor.withOpacity(0.9) : Colors.transparent),
    border: Border.all(
      color: isSelected || (isTV && hasFocus) 
          ? Colors.white.withOpacity(0.15)
          : Colors.transparent,
      width: 1,
    ),
  );
}

// 用于管理所有 FocusNode 的列表和全局焦点状态
List<FocusNode> _focusNodes = [];
Map<int, bool> _focusStates = {};

// 添加焦点监听逻辑的通用函数
void addFocusListeners(int startIndex, int length, State state) {
  if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
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
  bool isLastItem = false, // 新增参数，用于判断是否为最后一项
}) {
  FocusNode? focusNode = (index != null && index >= 0 && index < _focusNodes.length)
      ? _focusNodes[index]
      : null;

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
              hasFocus: focusNode?.hasFocus ?? false,
              isTV: isTV,
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
                isSelected: isSelect,
                onTap: () => widget.onChannelTap(widget.channels[channelName]),
                isCentered: false,
                minHeight: defaultMinHeight,
                isTV: widget.isTV,
                context: context,
                index: widget.startIndex + index,
                isLastItem: index == channelList.length - 1,
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
    // 1. 初始化基础数据
    _initializeCategoryData();
    _initializeChannelData();

    // 2. 计算并初始化焦点节点
    int totalFocusNodes = _calculateTotalFocusNodes();
    _initializeFocusNodes(totalFocusNodes);

    // 3. 计算视图高度
    _calculateViewportHeight();

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
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    // 如果有位置信息，进行排序
    _sortByLocation();

    _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

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
    String? region;
    String? city;
    
    for (String line in lines) {
      if (line.startsWith('地区:')) {
        region = line.substring(3).trim().toLowerCase();
      } else if (line.startsWith('城市:')) {
        city = line.substring(3).trim().toLowerCase();
      }
    }

    if ((region?.isEmpty ?? true) && (city?.isEmpty ?? true)) return;

    List<String> exactMatches = [];    // 城市匹配
    List<String> partialMatches = [];  // 地区匹配
    List<String> otherGroups = [];     // 其他分组

    for (String key in _keys) {
      String lowercaseKey = key.toLowerCase();
      if (city != null && city.isNotEmpty && 
          (lowercaseKey.contains(city) || city.contains(lowercaseKey))) {
        exactMatches.add(key);
      } else if (region != null && region.isNotEmpty && 
                 (lowercaseKey.contains(region) || region.contains(lowercaseKey))) {
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

  } catch (e) {
    LogUtil.e('解析位置信息失败: $e');
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
  for (var node in _focusNodes) {
    node.removeListener(() {});
  }

  // 添加新的监听器并检查焦点变化
  addFocusListeners(0, _categories.length, this);

  // 如果有分组，初始化分组的监听器
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

// 切换分类时更新分组和频道
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
      _initializeFocusNodes(_categories.length); // 初始化焦点节点，仅包含分类节点
      _updateStartIndexes(includeGroupsAndChannels: false);
    } else {
      // 分组不为空时，初始化频道数据
      _initializeChannelData();

      // 计算新分类下的总节点数，并初始化 FocusNode
      int totalFocusNodes = _categories.length;
      
      // 确保 _keys 不为空且 _values 有效时才添加其长度
      if (_keys.isNotEmpty) {
        totalFocusNodes += _keys.length;
        // 确保 _groupIndex 有效且 _values[_groupIndex] 存在
        if (_groupIndex >= 0 && _groupIndex < _values.length && _values[_groupIndex].isNotEmpty) {
          totalFocusNodes += _values[_groupIndex].length;
        }
      }
      
      _initializeFocusNodes(totalFocusNodes);
      _updateStartIndexes(includeGroupsAndChannels: true);

      // 重置滚动位置
      _scrollToTop(_scrollController);
      _scrollToTop(_scrollChannelController);
    }
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
      
// 切换分组时更新频道
void _onGroupTap(int index) {
  setState(() {
    _groupIndex = index;
    
    // 更安全的方式处理可空类型
    final currentTitle = widget.playModel?.title;
    if (currentTitle != null) {
      _channelIndex = _values[index].keys.toList().indexOf(currentTitle);
      if (_channelIndex == -1) {
        _channelIndex = -1; // 如果在新分组中找不到当前播放的频道
      }
    } else {
      _channelIndex = -1; // 如果没有正在播放的频道
    }
    
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

  // 状态更新后重新初始化焦点系统
  WidgetsBinding.instance.addPostFrameCallback((_) {
      // 计算焦点索引，如果没有选中的频道则默认焦点在分组列表的末尾
      int channelFocusIndex = _channelIndex != -1 
          ? _categories.length + _keys.length + _channelIndex
          : _categories.length + _keys.length;
          
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: channelFocusIndex);
      }
      // 重新初始化所有焦点监听器
      _reInitializeFocusListeners();
  });
}

  // 切换频道
void _onChannelTap(PlayModel? newModel) {
  if (newModel?.title == widget.playModel?.title) return; // 防止重复点击已选频道

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
    if (!controller.hasClients) return;
    final maxScrollExtent = controller.position.maxScrollExtent;
    final double viewPortHeight = _viewPortHeight!;
    final shouldOffset = index * defaultMinHeight - viewPortHeight + defaultMinHeight * 0.5;
    controller.jumpTo(shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent);
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
   if (channelKey != null) {
     epgCache[channelKey] = {
       'data': res.epgData!,
       'timestamp': currentTime,
     };
   }
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
    int totalNodesExpected = _categories.length + (_keys.isNotEmpty ? _keys.length : 0) + (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);
    if (_focusNodes.length != totalNodesExpected) {
      _initializeFocusNodes(totalNodesExpected); 
    }
    return _focusNodes;
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
        selectedChannelName: _channelIndex != -1 && _channelIndex < _values[_groupIndex].keys.length 
            ? _values[_groupIndex].keys.toList()[_channelIndex]
            : null,
        onChannelTap: _onChannelTap,
        isTV: isTV,
        scrollController: _scrollChannelController,
        startIndex: currentFocusIndex,
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

// 构建抽屉视图
Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
  
  double categoryWidth = isPortrait ? 110 : 120; // 分类列表宽度
  double groupWidth = groupListWidget != null ? (isPortrait ? 120 : 130) : 0;  // 设置分组列表宽度

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
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Colors.black, Colors.transparent]),
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
