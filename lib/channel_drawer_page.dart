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

// 保持原有的分割线样式和文字样式
final verticalDivider = VerticalDivider(
  width: 0.1,
  color: Colors.white.withOpacity(0.1),
);

const defaultTextStyle = TextStyle(
  fontSize: 17,
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

// 保持原有的装饰设置
BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    color: hasFocus
        ? unselectedColor
        : (isSelected ? selectedColor : Colors.transparent),
  );
}

// 主组件 ChannelDrawerPage 
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
  // 状态管理
  late final DrawerState _drawerState;
  
  // 滚动管理器
  late final ScrollManager _groupScrollManager;
  late final ScrollManager _channelScrollManager;
  final ItemScrollController _epgItemScrollController = ItemScrollController();
  
  // 焦点管理
  List<FocusNode> _focusNodes = [];
  Map<int, bool> _focusStates = {};
  TvKeyNavigationState? _tvKeyNavigationState;
  
  // EPG相关状态
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;

  // 视图相关
  final GlobalKey _viewPortKey = GlobalKey();
  double? _viewPortHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 初始化状态管理器
    _drawerState = DrawerState();
    _groupScrollManager = ScrollManager();
    _channelScrollManager = ScrollManager();
    
    _initializeData();
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
          _tvKeyNavigationState!.initializeFocusLogic(
            initialIndexOverride: _drawerState.categoryIndex
          );
        }
        _reInitializeFocusListeners();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // 释放资源
    _groupScrollManager.dispose();
    _channelScrollManager.dispose();
    
    // 清理焦点节点
    for (var node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
    
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final newHeight = MediaQuery.of(context).size.height * 0.5;
    if (newHeight != _viewPortHeight) {
      setState(() {
        _viewPortHeight = newHeight;
        _adjustScrollPositions();
      });
    }
  }
  
  // 统一的初始化方法
  void _initializeData() {
    // 初始化分类数据
    _initializeCategoryData();
    
    // 初始化焦点节点
    _initializeFocusNodes(_drawerState.calculateTotalFocusNodes());
    
    // 计算视图高度
    _calculateViewportHeight();
    
    // 加载EPG数据
    if (_shouldLoadEpg()) {
      _loadEPGMsg(widget.playModel);
    }
  }

  // 初始化分类数据
  void _initializeCategoryData() {
    // 获取所有分类
    final categories = widget.videoMap?.playList?.keys.toList() ?? <String>[];
    _drawerState.initializeCategories(categories);

    // 查找当前播放的频道所属的分类
    for (int i = 0; i < categories.length; i++) {
      final category = categories[i];
      final categoryMap = widget.videoMap?.playList[category];

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        // 查找当前频道
        for (var groupEntry in categoryMap.entries) {
          final group = groupEntry.key;
          final channelMap = groupEntry.value;

          if (channelMap.containsKey(widget.playModel?.title)) {
            // 找到匹配的分类和分组
            _drawerState.updateCategory(i, categoryMap);
            _drawerState.updateGroup(categoryMap.keys.toList().indexOf(group));
            _drawerState.updateChannel(
                channelMap.keys.toList().indexOf(widget.playModel?.title ?? ''));
            return;
          }
        }
      }
    }

    // 如果未找到当前播放频道的分类，寻找第一个非空分类
    if (_drawerState.categoryIndex == -1) {
      for (int i = 0; i < categories.length; i++) {
        final categoryMap = widget.videoMap?.playList[categories[i]];
        if (categoryMap != null && categoryMap.isNotEmpty) {
          _drawerState.updateCategory(i, categoryMap);
          break;
        }
      }
    }
  }

  // 初始化焦点节点
  void _initializeFocusNodes(int totalCount) {
    // 清理现有的焦点节点
    for (var node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
    
    // 创建新的焦点节点
    _focusNodes = List.generate(totalCount, (index) => FocusNode());
  }

  // 重新初始化焦点监听器
  void _reInitializeFocusListeners() {
    // 移除所有现有监听器
    for (var node in _focusNodes) {
      node.removeListener(() {});
    }

    // 添加分类监听器
    addFocusListeners(0, _drawerState.categories.length, this);

    // 如果有分组，添加分组监听器
    if (_drawerState.keys.isNotEmpty) {
      addFocusListeners(
        _drawerState.categories.length, 
        _drawerState.keys.length, 
        this
      );

      // 如果有频道，添加频道监听器
      final channels = _drawerState.getCurrentChannels();
      if (channels != null) {
        addFocusListeners(
          _drawerState.categories.length + _drawerState.keys.length,
          channels.length,
          this
        );
      }
    }
  }

  // 计算视图窗口的高度
  void _calculateViewportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  // 调整滚动位置
  void _adjustScrollPositions() {
    if (_viewPortHeight == null) return;
    
    // 调整分组列表滚动位置
    _groupScrollManager.scrollToPosition(
      _drawerState.groupIndex,
      _viewPortHeight
    );
    
    // 调整频道列表滚动位置
    _channelScrollManager.scrollToPosition(
      _drawerState.channelIndex,
      _viewPortHeight
    );
  }

  // 检查是否需要加载EPG
  bool _shouldLoadEpg() {
    final channels = _drawerState.getCurrentChannels();
    return channels != null && channels.isNotEmpty;
  }

  // 处理EPG数据
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (playModel == null) return;

    try {
      // 检查缓存
      if (channelKey != null && EPGCacheManager.isValidCache(channelKey)) {
        final cachedData = EPGCacheManager.getCache(channelKey);
        if (cachedData != null) {
          setState(() {
            _epgData = cachedData;
            _selEPGIndex = _getInitialSelectedIndex(_epgData);
          });

          // 滚动到当前节目
          _scrollToCurrentEpg();
          return;
        }
      }

      // 获取新数据
      final res = await EpgUtil.getEpg(playModel);
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      setState(() {
        _epgData = res.epgData;
        _selEPGIndex = _getInitialSelectedIndex(_epgData);
      });

      // 缓存数据
      if (channelKey != null) {
        EPGCacheManager.setCache(channelKey, res.epgData!);
      }

      // 滚动到当前节目
      _scrollToCurrentEpg();
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  // 滚动到当前EPG节目
  void _scrollToCurrentEpg() {
    if (_epgData != null && _epgData!.isNotEmpty) {
      _epgItemScrollController.scrollTo(
        index: _selEPGIndex,
        duration: Duration.zero,
      );
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
    
    return 0;
  }
  
// 保存 TvKeyNavigation 状态
  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  // 切换分类时更新分组和频道
  void _onCategoryTap(int index) {
    if (_drawerState.categoryIndex == index) return;

    setState(() {
      // 获取新分类的数据
      final selectedCategory = _drawerState.categories[index];
      final categoryMap = widget.videoMap?.playList[selectedCategory];
      
      // 更新状态
      _drawerState.updateCategory(index, categoryMap);
      
      // 重置焦点状态
      _focusStates.clear();
      
      // 如果分组为空，只保留分类焦点
      if (categoryMap == null || categoryMap.isEmpty) {
        _initializeFocusNodes(_drawerState.categories.length);
      } else {
        // 分组不为空时，初始化所有焦点节点
        _initializeFocusNodes(_drawerState.calculateTotalFocusNodes());
      }
      
      // 重置滚动位置
      _groupScrollManager.scrollToTop();
      _channelScrollManager.scrollToTop();
    });
    
    // 确保在状态更新后重新初始化焦点系统
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(
          initialIndexOverride: index
        );
      }
      _reInitializeFocusListeners();
    });
  }

  // 切换分组时更新频道
  void _onGroupTap(int index) {
    setState(() {
      // 更新分组选择
      _drawerState.updateGroup(index);
      
      // 重置焦点状态
      _focusStates.clear();

      // 重新计算并初始化焦点节点
      _initializeFocusNodes(_drawerState.calculateTotalFocusNodes());
      
      // 重置频道列表滚动位置
      _channelScrollManager.scrollToTop();
    });

    // 状态更新后重新初始化焦点系统
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 计算当前分组第一个频道项的焦点索引
      int firstChannelFocusIndex = _drawerState.categories.length + 
                                 _drawerState.keys.length + 
                                 _drawerState.channelIndex;
                                 
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(
          initialIndexOverride: firstChannelFocusIndex
        );
      }
      _reInitializeFocusListeners();
    });
  }

  // 切换频道
  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;

    // 通知父组件频道变更
    widget.onTapChannel?.call(newModel);
    
    setState(() {
      // 更新频道选择
      if (newModel?.title != null) {
        final channels = _drawerState.getCurrentChannels();
        if (channels != null) {
          final index = channels.keys.toList().indexOf(newModel!.title!);
          if (index != -1) {
            _drawerState.updateChannel(index);
          }
        }
      }
      
      // 重置EPG数据
      _epgData = null;
      _selEPGIndex = 0;
    });
    
    // 加载新频道的EPG数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEPGMsg(newModel, channelKey: newModel?.title);
    });
  }

  // 检查焦点列表是否正确
  List<FocusNode> _ensureCorrectFocusNodes() {
    final totalNodesExpected = _drawerState.calculateTotalFocusNodes();
    
    // 如果焦点节点数量不正确，重新初始化
    if (_focusNodes.length != totalNodesExpected) {
      _initializeFocusNodes(totalNodesExpected);
    }
    return _focusNodes;
  }
  
@override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    
    // 构建列表组件
    Widget categoryListWidget = CategoryList(
      categories: _drawerState.categories,
      selectedCategoryIndex: _drawerState.categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: isTV,
      startIndex: 0,
    );

    // 初始化其他列表组件为null
    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    // 构建分组列表
    if (_drawerState.keys.isNotEmpty) {
      groupListWidget = GroupList(
        keys: _drawerState.keys,
        scrollController: _groupScrollManager.controller,
        selectedGroupIndex: _drawerState.groupIndex,
        onGroupTap: _onGroupTap,
        isTV: isTV,
        startIndex: _drawerState.categories.length,
        isFavoriteCategory: _drawerState.categories[_drawerState.categoryIndex] == Config.myFavoriteKey,
      );

      // 构建频道列表
      final channels = _drawerState.getCurrentChannels();
      if (channels != null) {
        channelListWidget = ChannelList(
          channels: channels,
          scrollController: _channelScrollManager.controller,
          selectedChannelName: channels.keys.toList()[_drawerState.channelIndex],
          onChannelTap: _onChannelTap,
          isTV: isTV,
          startIndex: _drawerState.categories.length + _drawerState.keys.length,
        );

        // 构建EPG列表
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
      focusNodes: _ensureCorrectFocusNodes(),
      cacheName: 'ChannelDrawerPage',
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildDrawerContainer(
        isTV,
        categoryListWidget,
        groupListWidget,
        channelListWidget,
        epgListWidget,
      ),
    );
  }

  // 构建抽屉容器
  Widget _buildDrawerContainer(
    bool isTV,
    Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelListWidget,
    Widget? epgListWidget,
  ) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    // 计算各列表宽度
    double categoryWidth = isPortrait ? 110 : 120;
    double groupWidth = groupListWidget != null ? (isPortrait ? 120 : 130) : 0;

    double channelListWidth = (groupListWidget != null && channelListWidget != null)
        ? (isPortrait 
            ? MediaQuery.of(context).size.width - categoryWidth - groupWidth 
            : 160)
        : 0;

    double epgListWidth = (groupListWidget != null && 
                          channelListWidget != null && 
                          epgListWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth
        : 0;
    
    // 构建抽屉容器
    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape
          ? categoryWidth + groupWidth + channelListWidth + epgListWidth
          : MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent]),
      ),
      child: _buildDrawerContent(
        categoryWidth,
        groupWidth,
        channelListWidth,
        epgListWidth,
        categoryListWidget,
        groupListWidget,
        channelListWidget,
        epgListWidget,
      ),
    );
  }

  // 构建抽屉内容
  Widget _buildDrawerContent(
    double categoryWidth,
    double groupWidth,
    double channelListWidth,
    double epgListWidth,
    Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelListWidget,
    Widget? epgListWidget,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 分类列表
        Container(
          width: categoryWidth,
          child: categoryListWidget,
        ),
        
        // 分组列表
        if (groupListWidget != null) ...[
          verticalDivider,
          Container(
            width: groupWidth,
            child: groupListWidget,
          ),
        ],
        
        // 频道列表
        if (channelListWidget != null) ...[
          verticalDivider,
          Container(
            width: channelListWidth,
            child: channelListWidget,
          ),
        ],
        
        // EPG列表
        if (epgListWidget != null) ...[
          verticalDivider,
          Container(
            width: epgListWidth,
            child: epgListWidget,
          ),
        ],
      ],
    );
  }
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

class _CategoryListState extends FocusableState<CategoryList> {
  @override
  int get startIndex => widget.startIndex;
  
  @override
  int get length => widget.categories.length;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: defaultBackgroundColor,
      child: Group(
        groupIndex: 0,
        child: Column(
          children: List.generate(widget.categories.length, (index) {
            final category = widget.categories[index];
            // 处理特殊分类的显示
            final displayTitle = category == Config.myFavoriteKey
                ? S.of(context).myfavorite
                : category == Config.allChannelsKey
                    ? S.of(context).allchannels
                    : category;

            return ListItemBuilder.build(
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

class _GroupListState extends ScrollableListBase<GroupList> {
  @override
  int get startIndex => widget.startIndex;
  
  @override
  int get length => widget.keys.length;

  _GroupListState() 
      : super(
          itemHeight: defaultMinHeight,
        );

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
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.keys.isEmpty && widget.isFavoriteCategory
                  ? [
                      // 显示无收藏提示
                      Container(
                        constraints: BoxConstraints(
                          minHeight: defaultMinHeight
                        ),
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
                          return ListItemBuilder.build(
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

  @override
  void didUpdateWidget(GroupList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 处理选中项变化时的滚动位置调整
    if (widget.selectedGroupIndex != oldWidget.selectedGroupIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToIndex(widget.selectedGroupIndex);
      });
    }
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

class _ChannelListState extends ScrollableListBase<ChannelList> {
  @override
  int get startIndex => widget.startIndex;
  
  @override
  int get length => widget.channels.length;

  _ChannelListState() 
      : super(
          itemHeight: defaultMinHeight,
        );

  @override
  void initState() {
    super.initState();
    
    // 如果是TV模式，初始滚动到选中的频道
    if (widget.isTV && widget.selectedChannelName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = widget.channels.keys
            .toList()
            .indexOf(widget.selectedChannelName!);
            
        if (index != -1) {
          scrollToIndex(index);
        }
      });
    }
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
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RepaintBoundary(
                  child: Group(
                    groupIndex: 2,
                    children: List.generate(channelList.length, (index) {
                      final channelEntry = channelList[index];
                      final channelName = channelEntry.key;
                      final isSelect = widget.selectedChannelName == channelName;
                      
                      return ListItemBuilder.build(
                        title: channelName,
                        isSelected: isSelect,
                        onTap: () => widget.onChannelTap(
                          widget.channels[channelName]
                        ),
                        isCentered: true,
                        minHeight: defaultMinHeight,
                        isTV: widget.isTV,
                        context: context,
                        index: widget.startIndex + index,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(ChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 处理选中频道变化时的滚动位置调整
    if (widget.selectedChannelName != oldWidget.selectedChannelName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = widget.channels.keys
            .toList()
            .indexOf(widget.selectedChannelName ?? '');
            
        if (index != -1) {
          scrollToIndex(index);
        }
      });
    }
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

class _EPGListState extends FocusableState<EPGList> {
  @override
  int get startIndex => 0;  // EPG列表不需要偏移索引
  
  @override
  int get length => widget.epgData?.length ?? 0;

  // 处理EPG数据变化
  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData || 
        widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {});
      
      // 更新滚动位置
      if (widget.epgData != null && 
          widget.epgData!.isNotEmpty && 
          widget.selectedIndex >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.epgScrollController.scrollTo(
            index: widget.selectedIndex,
            duration: Duration.zero,
          );
        });
      }
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
          // EPG标题
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
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          verticalDivider,
          // EPG列表
          Flexible(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: widget.selectedIndex,
              itemScrollController: widget.epgScrollController,
              itemCount: widget.epgData?.length ?? 0,
              itemBuilder: (BuildContext context, int index) {
                final data = widget.epgData?[index];
                if (data == null) return const SizedBox.shrink();
                
                return ListItemBuilder.build(
                  title: '${data.start}-${data.end}\n${data.title}',
                  isSelected: index == widget.selectedIndex,
                  onTap: widget.onCloseDrawer,
                  isCentered: false,
                  isTV: widget.isTV,
                  context: context,
                  index: index,
                  useFocusableItem: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    // 清理过期的EPG缓存
    EPGCacheManager.clearExpiredCache();
    super.dispose();
  }
}
