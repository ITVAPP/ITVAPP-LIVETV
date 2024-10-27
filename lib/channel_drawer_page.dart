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

// 焦点管理的 Mixin
mixin FocusManagementMixin<T extends StatefulWidget> on State<T> {
  final Map<int, bool> _localFocusStates = {};
  
  void initializeFocusStates(int startIndex, int length) {
    for (var i = 0; i < length; i++) {
      _localFocusStates[startIndex + i] = false;
    }
  }

  void handleFocusChange(int startIndex, int length) {
    bool needsUpdate = false;
    for (var i = 0; i < length; i++) {
      final nodeIndex = startIndex + i;
      final newState = GlobalFocusManager.focusNodes[nodeIndex].hasFocus;
      if (_localFocusStates[nodeIndex] != newState) {
        _localFocusStates[nodeIndex] = newState;
        needsUpdate = true;
      }
    }
    if (needsUpdate && mounted) {
      setState(() {});
    }
  }

  void cleanupFocusStates() {
    _localFocusStates.clear();
  }

  bool hasFocus(int index) => _localFocusStates[index] ?? false;
}

// UI常量
class UIConstants {
  static const verticalDivider = VerticalDivider(
    width: 0.1,
    color: Colors.white10,
  );

  static const defaultTextStyle = TextStyle(fontSize: 16);

  static const selectedTextStyle = TextStyle(
    fontWeight: FontWeight.bold,
    color: Colors.white,
    shadows: [
      Shadow(offset: Offset(1.0, 1.0), blurRadius: 3.0, color: Colors.black54),
    ],
  );

  static const defaultMinHeight = 42.0;
  static const defaultBackgroundColor = Colors.black38;
  static const defaultPadding = EdgeInsets.all(6.0);
  static const selectedColor = Color(0xFFEB144C);
  static const unselectedColor = Color(0xFFDFA02A);

  static BoxDecoration buildItemDecoration({
    bool isSelected = false,
    bool hasFocus = false,
  }) {
    return BoxDecoration(
      color: hasFocus
          ? unselectedColor
          : (isSelected ? selectedColor : Colors.transparent),
    );
  }
}

// 全局焦点管理
class GlobalFocusManager {
  static final List<FocusNode> _focusNodes = [];
  static final Map<int, bool> _focusStates = {};

  static void initializeFocusNodes(int totalCount) {
    if (_focusNodes.length != totalCount) {
      // 清理旧的焦点节点
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes.clear();
      _focusStates.clear();

      // 添加新的焦点节点
      for (var i = 0; i < totalCount; i++) {
        _focusNodes.add(FocusNode());
      }
      
      LogUtil.v('频道抽屉节点数量: $totalCount');
    }
  }

  static void addFocusListeners(
    int startIndex,
    int length,
    VoidCallback onFocusChange,
  ) {
    if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
      return;
    }

    for (var i = startIndex; i < startIndex + length; i++) {
      _focusStates[i] = _focusNodes[i].hasFocus;
      _focusNodes[i].removeListener(() {});
      _focusNodes[i].addListener(() {
        final currentFocus = _focusNodes[i].hasFocus;
        if (_focusStates[i] != currentFocus) {
          _focusStates[i] = currentFocus;
          onFocusChange();
        }
      });
    }
  }

  static void removeFocusListeners(int startIndex, int length) {
    for (var i = startIndex; i < startIndex + length; i++) {
      _focusNodes[i].removeListener(() {});
      _focusStates.remove(i);
    }
  }

  static List<FocusNode> get focusNodes => _focusNodes;
  
  static void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
  }
}

// 通用列表项构建器
class ListItemBuilder {
  static Widget build({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    required BuildContext context,
    bool isCentered = true,
    double minHeight = UIConstants.defaultMinHeight,
    EdgeInsets padding = UIConstants.defaultPadding,
    bool isTV = false,
    int? index,
    bool useFocusableItem = true,
  }) {
    FocusNode? focusNode = (index != null && 
                           index >= 0 && 
                           index < GlobalFocusManager.focusNodes.length)
        ? GlobalFocusManager.focusNodes[index]
        : null;

    Widget content = GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        decoration: UIConstants.buildItemDecoration(
          isSelected: isSelected,
          hasFocus: focusNode?.hasFocus ?? false,
        ),
        child: Text(
          title,
          style: (focusNode?.hasFocus ?? false)
              ? UIConstants.defaultTextStyle.merge(UIConstants.selectedTextStyle)
              : (isSelected 
                  ? UIConstants.defaultTextStyle.merge(UIConstants.selectedTextStyle) 
                  : UIConstants.defaultTextStyle),
          softWrap: true,
          maxLines: null,
          overflow: TextOverflow.visible,
        ),
      ),
    );

    return useFocusableItem && focusNode != null
        ? FocusableItem(focusNode: focusNode, child: content)
        : content;
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

class _CategoryListState extends State<CategoryList> with FocusManagementMixin {
  @override
  void initState() {
    super.initState();
    initializeFocusStates(widget.startIndex, widget.categories.length);
    GlobalFocusManager.addFocusListeners(
      widget.startIndex,
      widget.categories.length,
      () => handleFocusChange(widget.startIndex, widget.categories.length),
    );
  }

  @override
  void dispose() {
    GlobalFocusManager.removeFocusListeners(widget.startIndex, widget.categories.length);
    cleanupFocusStates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: UIConstants.defaultBackgroundColor,
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

            return ListItemBuilder.build(
              title: displayTitle,
              isSelected: widget.selectedCategoryIndex == index,
              onTap: () => widget.onCategoryTap(index),
              context: context,
              isTV: widget.isTV,
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

class _GroupListState extends State<GroupList> with FocusManagementMixin {
  @override
  void initState() {
    super.initState();
    initializeFocusStates(widget.startIndex, widget.keys.length);
    GlobalFocusManager.addFocusListeners(
      widget.startIndex,
      widget.keys.length,
      () => handleFocusChange(widget.startIndex, widget.keys.length),
    );
  }

  @override
  void dispose() {
    GlobalFocusManager.removeFocusListeners(widget.startIndex, widget.keys.length);
    cleanupFocusStates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty && !widget.isFavoriteCategory) {
      return const SizedBox.shrink();
    }

    return Container(
      color: UIConstants.defaultBackgroundColor,
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
                      Container(
                        constraints: const BoxConstraints(
                          minHeight: UIConstants.defaultMinHeight
                        ),
                        child: Center(
                          child: Text(
                            S.of(context).nofavorite,
                            style: UIConstants.defaultTextStyle.merge(
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
                            context: context,
                            isTV: widget.isTV,
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

class _ChannelListState extends State<ChannelList> with FocusManagementMixin {
  @override
  void initState() {
    super.initState();
    initializeFocusStates(widget.startIndex, widget.channels.length);
    GlobalFocusManager.addFocusListeners(
      widget.startIndex,
      widget.channels.length,
      () => handleFocusChange(widget.startIndex, widget.channels.length),
    );

    if (widget.isTV && widget.selectedChannelName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = widget.channels.keys.toList().indexOf(widget.selectedChannelName!);
        if (index != -1 && isOutOfView(context)) {
          Scrollable.ensureVisible(
            context, 
            alignment: 0.5, 
            duration: Duration.zero
          );
        }
      });
    }
  }

  @override
  void dispose() {
    GlobalFocusManager.removeFocusListeners(widget.startIndex, widget.channels.length);
    cleanupFocusStates();
    super.dispose();
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
        return objectPosition.dy < offset || 
               objectPosition.dy > offset + viewportHeight;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    if (channelList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: UIConstants.defaultBackgroundColor,
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
                Group(
                  groupIndex: 2,
                  children: List.generate(channelList.length, (index) {
                    final channelEntry = channelList[index];
                    final channelName = channelEntry.key;
                    final isSelect = widget.selectedChannelName == channelName;

                    return ListItemBuilder.build(
                      title: channelName,
                      isSelected: isSelect,
                      onTap: () => widget.onChannelTap(widget.channels[channelName]),
                      context: context,
                      isTV: widget.isTV,
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
    if (widget.epgData != oldWidget.epgData || 
        widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: UIConstants.defaultBackgroundColor,
      child: Column(
        children: [
          Container(
            height: UIConstants.defaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: UIConstants.defaultBackgroundColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              S.of(context).programListTitle,
              style: UIConstants.defaultTextStyle.merge(
                const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          UIConstants.verticalDivider,
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
                  context: context,
                  isCentered: false,
                  isTV: widget.isTV,
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

class _ChannelDrawerPageState extends State<ChannelDrawerPage> 
    with WidgetsBindingObserver {
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

    // 计算所需的焦点节点总数
    int totalFocusNodes = _categories.length;
    totalFocusNodes += _keys.length;
    if (_values.isNotEmpty &&
        _groupIndex >= 0 &&
        _groupIndex < _values.length &&
        (_values[_groupIndex].length > 0)) {
      totalFocusNodes += (_values[_groupIndex].length);
    }
    GlobalFocusManager.initializeFocusNodes(totalFocusNodes);

    _calculateViewportHeight();

    if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _scrollChannelController.dispose();
    GlobalFocusManager.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
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

  void _calculateViewportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        setState(() {
          _viewPortHeight = renderBox.size.height * 0.5;
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

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = 0; groupIndex < categoryMap.keys.length; groupIndex++) {
          final group = categoryMap.keys.toList()[groupIndex];
          final channelMap = categoryMap[group];

          if (channelMap != null && 
              channelMap.containsKey(widget.playModel?.title)) {
            _categoryIndex = i;
            _groupIndex = groupIndex;
            _channelIndex = channelMap.keys
                .toList()
                .indexOf(widget.playModel?.title ?? '');
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

    // 频道按名字排序
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

  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _epgData = null;
    _selEPGIndex = 0;
  }

  // 重新初始化焦点监听器
  void _reInitializeFocusListeners() {
    // 先移除所有现有监听器
    for (var i = 0; i < GlobalFocusManager.focusNodes.length; i++) {
      GlobalFocusManager.focusNodes[i].removeListener(() {});
    }

    // 添加新的监听器
    GlobalFocusManager.addFocusListeners(
      0, 
      _categories.length,
      () => setState(() {}),
    );

    if (_keys.isNotEmpty) {
      GlobalFocusManager.addFocusListeners(
        _categories.length,
        _keys.length,
        () => setState(() {}),
      );

      if (_values.isNotEmpty && _groupIndex >= 0) {
        GlobalFocusManager.addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          () => setState(() {}),
        );
      }
    }
  }

  // 处理分类点击
  void _onCategoryTap(int index) {
    if (_categoryIndex == index) return;

    setState(() {
      _categoryIndex = index;

      final selectedCategory = _categories[_categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];

      if (categoryMap == null || categoryMap.isEmpty) {
        _resetChannelData();
        GlobalFocusManager.initializeFocusNodes(_categories.length);
        _updateStartIndexes(includeGroupsAndChannels: false);
      } else {
        _initializeChannelData();

        int totalFocusNodes = _categories.length +
            _keys.length +
            _values[_groupIndex].length;
        GlobalFocusManager.initializeFocusNodes(totalFocusNodes);

        _updateStartIndexes(includeGroupsAndChannels: true);
        _scrollToTop(_scrollController);
        _scrollToTop(_scrollChannelController);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tvKeyNavigationState?.releaseResources();
      _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: index);
      _reInitializeFocusListeners();
    });
  }

  // 处理分组点击
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _channelIndex = 0;

      int totalFocusNodes = _categories.length +
          (_keys.isNotEmpty ? _keys.length : 0) +
          (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
              ? _values[_groupIndex].length
              : 0);
      GlobalFocusManager.initializeFocusNodes(totalFocusNodes);

      _updateStartIndexes(includeGroupsAndChannels: true);
      _scrollToTop(_scrollChannelController);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      int firstChannelFocusIndex = _categories.length + _keys.length + _channelIndex;
      _tvKeyNavigationState?.releaseResources();
      _tvKeyNavigationState?.initializeFocusLogic(
        initialIndexOverride: firstChannelFocusIndex,
      );
      _reInitializeFocusListeners();
    });
  }

  // 处理频道点击
  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;

    setState(() {
      _channelIndex = _values[_groupIndex]
          .keys
          .toList()
          .indexOf(newModel?.title ?? '');
    });

    widget.onTapChannel?.call(newModel);
    _loadEPGMsg(newModel);
  }

  void _scrollToTop(ScrollController controller) {
    controller.jumpTo(0);
  }

  void _updateStartIndexes({bool includeGroupsAndChannels = true}) {
    int categoryStartIndex = 0;
    int groupStartIndex = categoryStartIndex + _categories.length;
    int channelStartIndex = groupStartIndex + 
        (includeGroupsAndChannels && _keys.isNotEmpty ? _keys.length : 0);

    _categoryStartIndex = categoryStartIndex;
    _groupStartIndex = groupStartIndex;
    _channelStartIndex = channelStartIndex;
  }

  void _adjustScrollPositions() {
    if (_viewPortHeight == null) return;
    _scrollToPosition(_scrollController, _groupIndex);
    _scrollToPosition(_scrollChannelController, _channelIndex);
  }

  void _scrollToPosition(ScrollController controller, int index) {
    if (!controller.hasClients) return;
    final maxScrollExtent = controller.position.maxScrollExtent;
    final viewPortHeight = _viewPortHeight!;
    final shouldOffset = index * UIConstants.defaultMinHeight - 
        viewPortHeight + 
        UIConstants.defaultMinHeight * 0.5;
    controller.jumpTo(
      shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent,
    );
  }

  Future<void> _loadEPGMsg(PlayModel? playModel) async {
    if (playModel == null) return;

    setState(() {
      _epgData = null;
      _selEPGIndex = 0;
    });

    try {
      final res = await EpgUtil.getEpg(playModel);
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      final epgRangeTime = DateUtil.formatDate(
        DateTime.now(),
        format: 'HH:mm',
      );
      
      final selectTimeData = res.epgData!.lastWhere(
        (element) => element.start!.compareTo(epgRangeTime) < 0,
        orElse: () => res.epgData!.first,
      ).start;
      
      final selectedIndex = res.epgData!.indexWhere(
        (element) => element.start == selectTimeData
      );

      setState(() {
        _epgData = res.epgData!;
        _selEPGIndex = selectedIndex;
      });

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

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    // 设置各列表宽度
    double categoryWidth = 110;
    double groupWidth = _keys.isNotEmpty ? 120 : 0;
    double channelListWidth = (_keys.isNotEmpty && _values.isNotEmpty)
        ? (isPortrait 
            ? MediaQuery.of(context).size.width - categoryWidth - groupWidth 
            : 160)
        : 0;
    double epgListWidth = (_keys.isNotEmpty && 
                          _values.isNotEmpty && 
                          _epgData != null)
        ? MediaQuery.of(context).size.width - 
            categoryWidth - 
            groupWidth - 
            channelListWidth
        : 0;

    return TvKeyNavigation(
      focusNodes: GlobalFocusManager.focusNodes,
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: (state) {
        _tvKeyNavigationState = state;
      },
      child: Container(
        key: _viewPortKey,
        padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
        width: widget.isLandscape
            ? categoryWidth + groupWidth + channelListWidth + epgListWidth
            : MediaQuery.of(context).size.width,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            // 分类列表
            SizedBox(
              width: categoryWidth,
              child: CategoryList(
                categories: _categories,
                selectedCategoryIndex: _categoryIndex,
                onCategoryTap: _onCategoryTap,
                isTV: isTV,
                startIndex: _categoryStartIndex,
              ),
            ),
            UIConstants.verticalDivider,
            
            // 分组列表
            if (_keys.isNotEmpty) ...[
              SizedBox(
                width: groupWidth,
                child: GroupList(
                  keys: _keys,
                  selectedGroupIndex: _groupIndex,
                  onGroupTap: _onGroupTap,
                  isTV: isTV,
                  scrollController: _scrollController,
                  isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
                  startIndex: _groupStartIndex,
                ),
              ),
              UIConstants.verticalDivider,
            ],
            
            // 频道列表
            if (_keys.isNotEmpty && _values.isNotEmpty) ...[
              SizedBox(
                width: channelListWidth,
                child: ChannelList(
                  channels: _values[_groupIndex],
                  selectedChannelName: widget.playModel?.title,
                  onChannelTap: _onChannelTap,
                  isTV: isTV,
                  scrollController: _scrollChannelController,
                  startIndex: _channelStartIndex,
                ),
              ),
            ],
            
            // EPG列表
            if (_keys.isNotEmpty && _values.isNotEmpty && _epgData != null) ...[
              UIConstants.verticalDivider,
              SizedBox(
                width: epgListWidth,
                child: EPGList(
                  epgData: _epgData,
                  selectedIndex: _selEPGIndex,
                  isTV: isTV,
                  epgScrollController: _epgItemScrollController,
                  onCloseDrawer: widget.onCloseDrawer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
