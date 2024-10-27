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

// 分割线样式定义
final verticalDivider = VerticalDivider(
  width: 0.1,
  color: Colors.white.withOpacity(0.1),
);

// 文字样式定义
const defaultTextStyle = TextStyle(
  fontSize: 16,
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

// 常量定义
const defaultMinHeight = 42.0;
const defaultBackgroundColor = Colors.black38;
const defaultPadding = EdgeInsets.all(6.0);
const Color selectedColor = Color(0xFFEB144C);
const Color unselectedColor = Color(0xFFDFA02A);

// 焦点管理器类，用于管理焦点状态
class FocusManager {
  static final List<FocusNode> _focusNodes = [];
  static final Map<int, bool> _focusStates = {};
  static final Map<int, List<VoidCallback>> _focusListeners = {};

  // 初始化焦点节点，确保节点数量与指定数量一致
  static void initialize(int totalCount) {
    // 如果节点数量不同，则清理已有节点并重新生成指定数量的焦点节点
    if (_focusNodes.length != totalCount) {
      disposeAll();
      _focusNodes.addAll(
        List.generate(totalCount, (index) => FocusNode())
      );
      LogUtil.v('频道抽屉节点数量: $totalCount');
    }
  }

  // 添加焦点监听器，监测焦点变化
  static void addListeners(int startIndex, int length, VoidCallback onChange) {
    // 如果索引或长度无效，则直接返回
    if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
      return;
    }

    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      _focusStates[index] = _focusNodes[index].hasFocus;
      
      // 如果已存在监听器，先移除以避免重复
      if (_focusListeners.containsKey(index)) {
        final oldListeners = _focusListeners[index] ?? [];
        for (final listener in oldListeners) {
          _focusNodes[index].removeListener(listener);
        }
      }

      // 添加新的监听器，监测焦点变化
      final listener = () {
        final currentFocus = _focusNodes[index].hasFocus;
        // 当焦点状态变化时触发onChange回调
        if (_focusStates[index] != currentFocus) {
          _focusStates[index] = currentFocus;
          onChange();
        }
      };
      
      _focusNodes[index].addListener(listener);
      _focusListeners[index] = [listener];
    }
  }

  // 移除指定范围内的焦点监听器
  static void removeListeners(int startIndex, int length) {
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      if (_focusListeners.containsKey(index)) {
        final listeners = _focusListeners[index] ?? [];
        for (final listener in listeners) {
          _focusNodes[index].removeListener(listener);
        }
        _focusListeners.remove(index);
      }
      _focusStates.remove(index);
    }
  }

  // 清除所有焦点节点及其监听器
  static void disposeAll() {
    // 销毁所有焦点节点并清理相关状态
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
    _focusListeners.clear();
  }

  // 获取指定索引的焦点节点
  static FocusNode? getNode(int index) {
    if (index >= 0 && index < _focusNodes.length) {
      return _focusNodes[index];
    }
    return null;
  }

  // 获取所有焦点节点
  static List<FocusNode> getAllNodes() => _focusNodes;
}

// 滚动助手类，用于控制滚动视图的位置
class ScrollHelper { 
  // 滚动到顶部
  static void scrollToTop(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  // 滚动到指定位置
  static void scrollToPosition(
    ScrollController controller, 
    int index, 
    double viewPortHeight, {
    double alignment = 0.5,
    Duration duration = Duration.zero,
  }) {
    if (!controller.hasClients) return;

    final maxScrollExtent = controller.position.maxScrollExtent;
    final shouldOffset = index * defaultMinHeight - viewPortHeight + defaultMinHeight * alignment;
    controller.jumpTo(shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent);
  }

  // 检查元素是否超出可视区域
  static bool isOutOfView(BuildContext context) {
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

  static void ensureVisible(BuildContext context, {double alignment = 0.5}) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      final ScrollableState? scrollableState = Scrollable.of(context);
      if (scrollableState != null) {
        final ScrollPosition position = scrollableState.position;
        final double offset = position.pixels;
        final double viewportHeight = position.viewportDimension;
        final Offset objectPosition = renderObject.localToGlobal(Offset.zero);

        // 如果元素超出可视范围，滚动使其可见
        if (objectPosition.dy < offset || objectPosition.dy > offset + viewportHeight) {
          Scrollable.ensureVisible(
            context, 
            alignment: alignment, 
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }
}

// 焦点管理 Mixin，用于管理组件的焦点状态
mixin FocusStateMixin<T extends StatefulWidget> on State<T> {
  Map<int, bool> localFocusStates = {};

  // 初始化焦点状态
  void initializeFocusState(int startIndex, int length) {
    for (var i = 0; i < length; i++) {
      localFocusStates[startIndex + i] = false;
    }
    FocusManager.addListeners(startIndex, length, onFocusChange);
  }

  // 当焦点状态变化时，更新状态
  void onFocusChange() {
    bool needsUpdate = false;
    localFocusStates.forEach((index, oldState) {
      final node = FocusManager.getNode(index);
      final newState = node?.hasFocus ?? false;
      if (oldState != newState) {
        localFocusStates[index] = newState;
        needsUpdate = true;
      }
    });
    if (needsUpdate) {
      setState(() {});
    }
  }

  // 销毁时清理焦点监听器
  @override
  void dispose() {
    final indices = localFocusStates.keys.toList();
    if (indices.isNotEmpty) {
      FocusManager.removeListeners(indices.first, indices.length);
    }
    localFocusStates.clear();
    super.dispose();
  }
}

// 创建基础列表项的装饰
BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    color: hasFocus
        ? unselectedColor
        : (isSelected ? selectedColor : Colors.transparent),
  );
}

// 基础列表项组件，显示单个列表项
class BaseListItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isCentered;
  final double minHeight;
  final bool isTV;
  final int? index;
  final bool useFocusableItem;
  final EdgeInsets padding;

  const BaseListItem({
    Key? key,
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.isCentered = true,
    this.minHeight = defaultMinHeight,
    required this.isTV,
    this.index,
    this.useFocusableItem = true,
    this.padding = defaultPadding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final focusNode = (index != null) ? FocusManager.getNode(index!) : null;

    Widget listItemContent = GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        decoration: buildItemDecoration(
          isSelected: isSelected,
          hasFocus: focusNode?.hasFocus ?? false
        ),
        child: Align(
          alignment: isCentered ? Alignment.center : Alignment.centerLeft,
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
    );

    // 根据焦点节点情况确定是否包裹在FocusableItem中
    return useFocusableItem && focusNode != null
        ? FocusableItem(focusNode: focusNode, child: listItemContent)
        : listItemContent;
  }
}

// 基础滚动列表组件，容纳多行内容并支持滚动
class BaseScrollableList extends StatelessWidget {
  final ScrollController? scrollController;
  final List<Widget> children;
  final int groupIndex;
  final Widget? header;

  const BaseScrollableList({
    Key? key,
    this.scrollController,
    required this.children,
    required this.groupIndex,
    this.header,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: defaultBackgroundColor,
      child: Column(
        children: [
          if (header != null) header!,
          Flexible(
            child: SingleChildScrollView(
              controller: scrollController,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Group(
                        groupIndex: groupIndex,
                        children: children,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 分类列表组件，展示频道分类
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

class _CategoryListState extends State<CategoryList> with FocusStateMixin {
  @override
  void initState() {
    super.initState();
    initializeFocusState(widget.startIndex, widget.categories.length);
  }

  // 获取分类标题，包含自定义处理
  String _getCategoryTitle(BuildContext context, String category) {
    if (category == Config.myFavoriteKey) return S.of(context).myfavorite;
    if (category == Config.allChannelsKey) return S.of(context).allchannels;
    return category;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: defaultBackgroundColor,
      child: Group(
        groupIndex: 0,
        child: Column(
          children: List.generate(
            widget.categories.length,
            (index) => BaseListItem(
              title: _getCategoryTitle(context, widget.categories[index]),
              isSelected: widget.selectedCategoryIndex == index,
              onTap: () => widget.onCategoryTap(index),
              isTV: widget.isTV,
              index: widget.startIndex + index,
            ),
          ),
        ),
      ),
    );
  }
}

// 分组列表组件，展示不同的分组内容
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

class _GroupListState extends State<GroupList> with FocusStateMixin {
  @override
  void initState() {
    super.initState();
    initializeFocusState(widget.startIndex, widget.keys.length);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty && !widget.isFavoriteCategory) {
      return const SizedBox.shrink();
    }

    List<Widget> children = widget.keys.isEmpty && widget.isFavoriteCategory
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
        : List.generate(
            widget.keys.length,
            (index) => BaseListItem(
              title: widget.keys[index],
              isSelected: widget.selectedGroupIndex == index,
              onTap: () => widget.onGroupTap(index),
              isTV: widget.isTV,
              index: widget.startIndex + index,
            ),
          );

    return BaseScrollableList(
      scrollController: widget.scrollController,
      groupIndex: 1,
      children: children,
    );
  }
}

// 频道列表组件，展示频道内容
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

class _ChannelListState extends State<ChannelList> with FocusStateMixin {
  @override
  void initState() {
    super.initState();
    initializeFocusState(widget.startIndex, widget.channels.length);

    if (widget.isTV && widget.selectedChannelName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = widget.channels.keys.toList().indexOf(widget.selectedChannelName!);
        if (index != -1 && ScrollHelper.isOutOfView(context)) {
          ScrollHelper.ensureVisible(context, alignment: 0.5);
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

    return BaseScrollableList(
      scrollController: widget.scrollController,
      groupIndex: 2,
      children: List.generate(
        channelList.length, (index) {
          final channelEntry = channelList[index];
          final channelName = channelEntry.key;
          return BaseListItem(
            title: channelName,
            isSelected: widget.selectedChannelName == channelName,
            onTap: () => widget.onChannelTap(widget.channels[channelName]),
            isTV: widget.isTV,
            index: widget.startIndex + index,
          );
        },
      ),
    );
  }
}

// 电子节目表（EPG）列表组件
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

    final header = Container(
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
    );

    return BaseScrollableList(
      groupIndex: 3,
      header: header,
      children: List.generate(
        widget.epgData?.length ?? 0,
        (index) {
          final data = widget.epgData?[index];
          if (data == null) return const SizedBox.shrink();
          return BaseListItem(
            title: '${data.start}-${data.end}\n${data.title}',
            isSelected: index == widget.selectedIndex,
            onTap: widget.onCloseDrawer,
            isCentered: false,
            isTV: widget.isTV,
            useFocusableItem: false,
          );
        },
      ),
    );
  }
}

// 主组件 ChannelDrawerPage，用于展示频道抽屉页面
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

    int totalFocusNodes = _calculateTotalFocusNodes();
    FocusManager.initialize(totalFocusNodes);

    _calculateViewportHeight();

    if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel);
    }
  }

  // 计算焦点节点总数
  int _calculateTotalFocusNodes() {
    int total = _categories.length;
    total += _keys.length;
    if (_values.isNotEmpty &&
        _groupIndex >= 0 &&
        _groupIndex < _values.length &&
        (_values[_groupIndex].length > 0)) {
      total += _values[_groupIndex].length;
    }
    return total;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _scrollChannelController.dispose();
    FocusManager.disposeAll();
    super.dispose();
  }

  // 当窗口尺寸改变时的回调方法
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

  // 计算视口高度
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

  // 处理分类点击事件
  void _onCategoryTap(int index) {
    if (_categoryIndex == index) return;

    setState(() {
      _categoryIndex = index;

      final selectedCategory = _categories[_categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];

      if (categoryMap == null || categoryMap.isEmpty) {
        _resetChannelData();
        FocusManager.initialize(_categories.length);
        _updateStartIndexes(includeGroupsAndChannels: false);
      } else {
        _initializeChannelData();
        FocusManager.initialize(_calculateTotalFocusNodes());
        _updateStartIndexes(includeGroupsAndChannels: true);

        ScrollHelper.scrollToTop(_scrollController);
        ScrollHelper.scrollToTop(_scrollChannelController);
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState?.releaseResources();
        _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: index);
      }
    });
  }

  // 处理分组点击事件
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _channelIndex = 0;

      FocusManager.initialize(_calculateTotalFocusNodes());
      _updateStartIndexes(includeGroupsAndChannels: true);
      
      ScrollHelper.scrollToTop(_scrollChannelController);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        int firstChannelFocusIndex = _categories.length + _keys.length + _channelIndex;
        _tvKeyNavigationState?.releaseResources();
        _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      }
    });
  }

  // 处理频道点击事件
  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;
    setState(() {
      widget.onTapChannel?.call(newModel);
    });

    _loadEPGMsg(newModel).then((_) {
      setState(() {});
    });
  }

  // 更新起始索引
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

  // 调整滚动位置
  void _adjustScrollPositions() {
    if (_viewPortHeight == null) return;
    ScrollHelper.scrollToPosition(_scrollController, _groupIndex, _viewPortHeight!);
    ScrollHelper.scrollToPosition(_scrollChannelController, _channelIndex, _viewPortHeight!);
  }

  // 加载EPG消息
  Future<void> _loadEPGMsg(PlayModel? playModel) async {
    if (playModel == null) return;

    setState(() {
      _epgData = null;
      _selEPGIndex = 0;
    });

    try {
      final res = await EpgUtil.getEpg(playModel);
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      final epgRangeTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');
      final selectTimeData = res.epgData!.lastWhere(
            (element) => element.start!.compareTo(epgRangeTime) < 0,
        orElse: () => res.epgData!.first,
      ).start;
      final selectedIndex = res.epgData!.indexWhere((element) => element.start == selectTimeData);

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
    
    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: isTV,
      startIndex: _categoryStartIndex,
    );

    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
      onGroupTap: _onGroupTap,
      isTV: isTV,
      scrollController: _scrollController,
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: _groupStartIndex,
    );
    
    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: widget.playModel?.title,
          onChannelTap: _onChannelTap,
          isTV: isTV,
          scrollController: _scrollChannelController,
          startIndex: _channelStartIndex,
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
      focusNodes: FocusManager.getAllNodes(),
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: (state) {
        _tvKeyNavigationState = state;
      },
      child: _buildDrawerLayout(
        isTV: isTV,
        categoryListWidget: categoryListWidget,
        groupListWidget: groupListWidget,
        channelListWidget: channelListWidget,
        epgListWidget: epgListWidget,
      ),
    );
  }

  // 构建抽屉布局
  Widget _buildDrawerLayout({
    required bool isTV,
    required Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelListWidget,
    Widget? epgListWidget,
  }) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    double categoryWidth = 110;
    double groupWidth = groupListWidget != null ? 120 : 0;
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
          if (groupListWidget != null) ...[
            SizedBox(
              width: groupWidth,
              child: groupListWidget,
            ),
            verticalDivider,
          ],
          if (channelListWidget != null)
            SizedBox(
              width: channelListWidth,
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
