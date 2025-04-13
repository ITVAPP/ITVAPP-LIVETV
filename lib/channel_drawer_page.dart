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

// 新增：防抖工具类，用于统一管理防抖逻辑
class Debouncer {
  Timer? _timer;
  void run(VoidCallback action, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }
  void dispose() => _timer?.cancel();
}

const bool enableFocusInNonTVMode = true; // 是否在非TV模式启用焦点逻辑（调试用）

// 修改：合并宽度常量为映射表，减少重复定义
const Map<String, double> widthConfig = {
  'categoryPortrait': 110.0,
  'categoryLandscape': 120.0,
  'groupPortrait': 120.0,
  'groupLandscape': 130.0,
  'channelTV': 160.0,
  'channelNonTV': 150.0,
};

// 修改：定义统一高度常量，替换硬编码
const double defaultMinHeight = 42.0;
const double itemHeight = defaultMinHeight + 1.0;
const double epgItemHeight = defaultMinHeight * 1.3 + 1;

// 修改：提取公共分割线样式，参数化渐变和阴影
Widget createDivider({
  bool isVertical = false,
  double opacityStart = 0.05,
  double opacityEnd = 0.25,
  bool withShadow = false,
}) {
  return Container(
    width: isVertical ? 1.5 : null,
    height: isVertical ? null : 1.0,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.white.withOpacity(opacityStart),
          Colors.white.withOpacity((opacityStart + opacityEnd) / 2),
          Colors.white.withOpacity(opacityEnd),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      boxShadow: withShadow
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    ),
  );
}

final verticalDivider = createDivider(isVertical: true, opacityStart: 0.05, opacityEnd: 0.25);
final horizontalDivider = createDivider(isVertical: false, opacityStart: 0.05, opacityEnd: 0.15, withShadow: true);

const defaultTextStyle = TextStyle(
  fontSize: 16,
  height: 1.4,
  color: Colors.white,
);

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

final defaultBackgroundColor = LinearGradient(
  colors: [
    Color(0xFF1A1A1A),
    Color(0xFF2C2C2C),
  ],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0);

const Color selectedColor = Color(0xFFEB144C);
const Color focusColor = Color(0xFFDFA02A);

// 修改：合并 _getGradientColor 和 buildItemDecoration，统一装饰逻辑
BoxDecoration getItemDecoration({
  required bool isTV,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  final shouldHighlight = (useFocus && hasFocus) || (isSelected && !isSystemAutoSelected);
  
  final gradient = shouldHighlight
      ? LinearGradient(
          colors: [
            (useFocus && hasFocus ? focusColor : selectedColor).withOpacity(0.9),
            (useFocus && hasFocus ? focusColor : selectedColor).withOpacity(0.7),
          ],
        )
      : null;

  return BoxDecoration(
    gradient: gradient,
    border: Border.all(
      color: shouldHighlight ? Colors.white.withOpacity(0.3) : Colors.transparent,
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

// 修改：优化焦点状态管理，合并 initialize 和 updateDynamicNodes
class FocusStateManager {
  static final FocusStateManager _instance = FocusStateManager._internal();
  factory FocusStateManager() => _instance;
  FocusStateManager._internal();

  List<FocusNode> focusNodes = [];
  Map<int, bool> focusStates = {};
  int lastFocusedIndex = -1;
  List<FocusNode> categoryFocusNodes = [];
  final Map<int, VoidCallback> _focusListeners = {};

  // 修改：合并节点配置逻辑
  void configureNodes(int count, {bool isCategory = false}) {
    if (count <= 0) return;

    final targetNodes = isCategory ? categoryFocusNodes : focusNodes;
    final startIndex = isCategory ? 0 : categoryFocusNodes.length;

    // 清理旧节点
    if (isCategory || targetNodes.length > categoryFocusNodes.length) {
      for (var i = startIndex; i < targetNodes.length; i++) {
        if (_focusListeners.containsKey(i)) {
          targetNodes[i].removeListener(_focusListeners[i]!);
          _focusListeners.remove(i);
        }
        targetNodes[i].dispose();
      }
      if (!isCategory) {
        targetNodes.length = categoryFocusNodes.length;
      } else {
        targetNodes.clear();
      }
    }

    // 创建新节点
    final newNodes = List.generate(
      count,
      (index) => FocusNode(debugLabel: '${isCategory ? "Category" : "Dynamic"}Node${index + startIndex}'),
    );

    if (isCategory) {
      categoryFocusNodes = newNodes;
      focusNodes = List.from(newNodes);
      focusStates.clear();
      lastFocusedIndex = -1;
    } else {
      focusNodes.addAll(newNodes);
    }
  }

  void dispose() {
    _focusListeners.forEach((index, listener) {
      if (index < focusNodes.length) {
        focusNodes[index].removeListener(listener);
      }
    });
    _focusListeners.clear();

    for (var node in focusNodes) {
      node.dispose();
    }
    for (var node in categoryFocusNodes) {
      node.dispose();
    }

    focusNodes.clear();
    categoryFocusNodes.clear();
    focusStates.clear();
    lastFocusedIndex = -1;
  }

  void addListenerReference(int index, VoidCallback listener) {
    _focusListeners[index] = listener;
  }

  void removeListenerReference(int index) {
    _focusListeners.remove(index);
  }
}

final focusManager = FocusStateManager();

// 移除：_itemKey 被确认无用，移除以减少冗余

// 修改：优化焦点监听器管理
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

  final nodes = focusManager.focusNodes;
  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    if (!focusManager.focusStates.containsKey(index)) {
      final listener = () {
        final currentFocus = nodes[index].hasFocus;
        if (focusManager.focusStates[index] != currentFocus) {
          focusManager.focusStates[index] = currentFocus;
          if (state.mounted) {
            state.setState(() {});
          }
          if (scrollController != null && currentFocus && scrollController.hasClients) {
            _handleScroll(index, startIndex, state, scrollController, length);
          }
        }
      };
      nodes[index].addListener(listener);
      focusManager.addListenerReference(index, listener);
      focusManager.focusStates[index] = nodes[index].hasFocus;
    }
  }
}

// 修改：统一滚动偏移计算
double calculateScrollOffset({
  required int index,
  required int startIndex,
  required double itemHeight,
  required double viewportHeight,
  required int length,
  required bool isMovingDown,
  required bool isInitialFocus,
  required double currentOffset,
}) {
  final itemIndex = index - startIndex;
  final itemTop = itemIndex * itemHeight;
  final itemBottom = itemTop + itemHeight;
  final fullItemsInViewport = (viewportHeight / itemHeight).floor();

  if (length <= fullItemsInViewport) return 0.0;

  if (itemIndex == 0) return 0.0;
  if (itemIndex == length - 1) return double.infinity; // 滚动到最大

  if (isMovingDown && itemBottom > currentOffset + viewportHeight) {
    return itemBottom - viewportHeight;
  }
  if (!isMovingDown && itemTop < currentOffset) {
    return itemTop;
  }

  return currentOffset;
}

// 修改：优化滚动处理，调用 calculateScrollOffset
void _handleScroll(int index, int startIndex, State state, ScrollController scrollController, int length) {
  final channelDrawerState = state is _ChannelDrawerPageState
      ? state
      : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
  if (channelDrawerState == null) return;

  int currentGroup;
  if (index >= channelDrawerState._categoryStartIndex && index < channelDrawerState._groupStartIndex) {
    currentGroup = 0;
  } else if (index >= channelDrawerState._groupStartIndex && index < channelDrawerState._channelStartIndex) {
    currentGroup = 1;
  } else if (index >= channelDrawerState._channelStartIndex) {
    currentGroup = 2;
  } else {
    currentGroup = -1;
  }

  int lastGroup = -1;
  if (focusManager.lastFocusedIndex != -1) {
    if (focusManager.lastFocusedIndex >= channelDrawerState._categoryStartIndex &&
        focusManager.lastFocusedIndex < channelDrawerState._groupStartIndex) {
      lastGroup = 0;
    } else if (focusManager.lastFocusedIndex >= channelDrawerState._groupStartIndex &&
        focusManager.lastFocusedIndex < channelDrawerState._channelStartIndex) {
      lastGroup = 1;
    } else if (focusManager.lastFocusedIndex >= channelDrawerState._channelStartIndex) {
      lastGroup = 2;
    }
  }

  final isInitialFocus = focusManager.lastFocusedIndex == -1;
  final isMovingDown = !isInitialFocus && index > focusManager.lastFocusedIndex;
  focusManager.lastFocusedIndex = index;

  if (currentGroup == 0) return;

  final targetOffset = calculateScrollOffset(
    index: index,
    startIndex: startIndex,
    itemHeight: itemHeight,
    viewportHeight: channelDrawerState._drawerHeight,
    length: length,
    isMovingDown: isMovingDown,
    isInitialFocus: isInitialFocus,
    currentOffset: scrollController.offset,
  );

  if (targetOffset != scrollController.offset) {
    channelDrawerState.scrollTo(
      targetList: _getTargetList(currentGroup),
      index: index - startIndex,
      alignment: targetOffset == 0.0 ? 0.0 : (targetOffset == double.infinity ? 1.0 : null),
    );
  }
}

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

void removeFocusListeners(int startIndex, int length) {
  if (startIndex < 0 || startIndex >= focusManager.focusNodes.length) {
    LogUtil.e('removeFocusListeners: startIndex 超出范围: $startIndex');
    return;
  }
  int safeLength = (startIndex + length > focusManager.focusNodes.length) ? (focusManager.focusNodes.length - startIndex) : length;
  for (var i = 0; i < safeLength; i++) {
    final index = startIndex + i;
    focusManager.removeListenerReference(index);
    focusManager.focusStates.remove(index);
  }
}

// 修改：简化文字样式获取，使用逻辑运算
TextStyle getItemTextStyle({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final shouldHighlight = (useFocus && hasFocus) || (isSelected && !isSystemAutoSelected);
  return shouldHighlight ? defaultTextStyle.merge(selectedTextStyle) : defaultTextStyle;
}

// 修改：抽象通用列表组件
class GenericListWidget<T> extends StatefulWidget {
  final List<T> items;
  final int selectedIndex;
  final Function(int) onTap;
  final ScrollController scrollController;
  final bool isTV;
  final int startIndex;
  final bool isCentered;
  final bool isFavoriteCategory;
  final bool isSystemAutoSelected;
  final String Function(T, BuildContext)? displayTitle;

  const GenericListWidget({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.scrollController,
    required this.isTV,
    this.startIndex = 0,
    this.isCentered = true,
    this.isFavoriteCategory = false,
    this.isSystemAutoSelected = false,
    this.displayTitle,
  });

  @override
  _GenericListState<T> createState() => _GenericListState<T>();
}

class _GenericListState<T> extends State<GenericListWidget<T>> {
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.items.length, this, scrollController: widget.scrollController);
  }

  @override
  void dispose() {
    if (focusManager.focusNodes.isNotEmpty && widget.startIndex >= 0 && widget.startIndex < focusManager.focusNodes.length) {
      removeFocusListeners(widget.startIndex, widget.items.length);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty && widget.isFavoriteCategory) {
      return ListView(
        controller: widget.scrollController,
        children: [
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: defaultMinHeight),
            child: Center(
              child: Text(
                S.of(context).nofavorite,
                textAlign: TextAlign.center,
                style: defaultTextStyle.merge(const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: ListView(
        controller: widget.scrollController,
        shrinkWrap: true,
        children: [
          RepaintBoundary(
            child: Group(
              groupIndex: widget.startIndex == 0 ? 0 : 1,
              children: List.generate(widget.items.length, (index) {
                final item = widget.items[index];
                final displayTitle = widget.displayTitle != null
                    ? widget.displayTitle!(item, context)
                    : item.toString();
                final useFocus = widget.isTV || enableFocusInNonTVMode;
                final focusNode = (widget.startIndex + index < focusManager.focusNodes.length)
                    ? focusManager.focusNodes[widget.startIndex + index]
                    : null;
                final hasFocus = focusNode?.hasFocus ?? false;

                final textStyle = getItemTextStyle(
                  useFocus: useFocus,
                  hasFocus: hasFocus,
                  isSelected: widget.selectedIndex == index,
                  isSystemAutoSelected: widget.isSystemAutoSelected,
                );

                Widget content = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MouseRegion(
                      onEnter: (_) => !widget.isTV ? (context as Element).markNeedsBuild() : null,
                      onExit: (_) => !widget.isTV ? (context as Element).markNeedsBuild() : null,
                      child: GestureDetector(
                        onTap: () => widget.onTap(index),
                        child: Container(
                          height: defaultMinHeight,
                          padding: defaultPadding,
                          alignment: widget.isCentered ? Alignment.center : Alignment.centerLeft,
                          decoration: getItemDecoration(
                            isTV: widget.isTV,
                            hasFocus: hasFocus,
                            isSelected: widget.selectedIndex == index,
                            isSystemAutoSelected: widget.isSystemAutoSelected,
                          ),
                          child: Text(
                            displayTitle,
                            style: textStyle,
                            softWrap: false,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (index != widget.items.length - 1) horizontalDivider,
                  ],
                );

                return useFocus && focusNode != null
                    ? FocusableItem(focusNode: focusNode, child: content)
                    : content;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// 修改：使用 GenericListWidget 替换 CategoryList
class CategoryList extends GenericListWidget<String> {
  CategoryList({
    super.key,
    required List<String> categories,
    required int selectedCategoryIndex,
    required Function(int) onCategoryTap,
    required bool isTV,
    super.startIndex = 0,
    required super.scrollController,
  }) : super(
          items: categories,
          selectedIndex: selectedCategoryIndex,
          onTap: onCategoryTap,
          isTV: isTV,
          isCentered: true,
          displayTitle: (category, context) => category == Config.myFavoriteKey
              ? S.of(context).myfavorite
              : category == Config.allChannelsKey
                  ? S.of(context).allchannels
                  : category,
        );
}

// 修改：使用 GenericListWidget 替换 GroupList
class GroupList extends GenericListWidget<String> {
  GroupList({
    super.key,
    required List<String> keys,
    required int selectedGroupIndex,
    required Function(int) onGroupTap,
    required bool isTV,
    super.startIndex = 0,
    required super.scrollController,
    bool isFavoriteCategory = false,
    required bool isSystemAutoSelected,
  }) : super(
          items: keys,
          selectedIndex: selectedGroupIndex,
          onTap: onGroupTap,
          isTV: isTV,
          isCentered: false,
          isFavoriteCategory: isFavoriteCategory,
          isSystemAutoSelected: isSystemAutoSelected,
        );
}

// 修改：使用 GenericListWidget 替换 ChannelList
class ChannelList extends GenericListWidget<MapEntry<String, PlayModel>> {
  ChannelList({
    super.key,
    required Map<String, PlayModel> channels,
    required Function(PlayModel?) onChannelTap,
    String? selectedChannelName,
    required bool isTV,
    super.startIndex = 0,
    required super.scrollController,
    bool isSystemAutoSelected = false,
  }) : super(
          items: channels.entries.toList(),
          selectedIndex: selectedChannelName != null
              ? channels.keys.toList().indexOf(selectedChannelName)
              : -1,
          onTap: (index) => onChannelTap(channels.entries.toList()[index].value),
          isTV: isTV,
          isCentered: false,
          isSystemAutoSelected: isSystemAutoSelected,
          displayTitle: (entry, _) => entry.key,
        );

  @override
  Widget buildContent(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return super.buildContent(context);
  }
}

// 修改：优化 EPGList，使用 Debouncer
class EPGList extends StatefulWidget {
  final List<EpgData>? epgData;
  final int selectedIndex;
  final bool isTV;
  final ScrollController epgScrollController;
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
  State<EPGList> createState() => EPGListState();
}

class EPGListState extends State<EPGList> {
  bool _shouldScroll = true;
  final Debouncer _debouncer = Debouncer();
  static int currentEpgDataLength = 0;

  @override
  void initState() {
    super.initState();
    currentEpgDataLength = widget.epgData?.length ?? 0;
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData) {
      currentEpgDataLength = widget.epgData?.length ?? 0;
    }
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      _shouldScroll = true;
      _scheduleScroll();
    }
  }

  void _scheduleScroll() {
    if (!_shouldScroll || !mounted) return;
    _debouncer.run(() {
      if (mounted && widget.epgData != null && widget.epgData!.isNotEmpty) {
        final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
        if (state != null && state._epgItemScrollController.hasClients) {
          state.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: null);
          _shouldScroll = false;
          LogUtil.i('EPG 滚动完成: index=${widget.selectedIndex}');
        }
      }
    }, Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  static final _appBarDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        spreadRadius: 2,
        offset: Offset(0, 2),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) return const SizedBox.shrink();
    final useFocus = widget.isTV || enableFocusInNonTVMode;
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: Column(
        children: [
          Container(
            height: defaultMinHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            decoration: _appBarDecoration,
            child: Text(
              S.of(context).programListTitle,
              style: defaultTextStyle.merge(const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          verticalDivider,
          Flexible(
            child: ListView(
              controller: widget.epgScrollController,
              children: List.generate(widget.epgData!.length, (index) {
                final data = widget.epgData![index];
                final isSelect = index == widget.selectedIndex;
                final focusNode = useFocus ? FocusNode(debugLabel: 'EpgNode$index') : null;
                final hasFocus = focusNode?.hasFocus ?? false;
                final textStyle = getItemTextStyle(
                  useFocus: useFocus,
                  hasFocus: hasFocus,
                  isSelected: isSelect,
                  isSystemAutoSelected: false,
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: widget.onCloseDrawer,
                      child: Container(
                        height: epgItemHeight,
                        padding: defaultPadding,
                        alignment: Alignment.centerLeft,
                        decoration: getItemDecoration(
                          isTV: widget.isTV,
                          hasFocus: hasFocus,
                          isSelected: isSelect,
                          isSystemAutoSelected: false,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${data.start}-${data.end}',
                              style: textStyle.merge(const TextStyle(fontSize: 14)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              data.title ?? '无标题',
                              style: textStyle.merge(const TextStyle(fontSize: 16)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (index != widget.epgData!.length - 1) horizontalDivider,
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class ChannelDrawerPage extends StatefulWidget {
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
  }) : super(key: _stateKey);

  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final Function(PlayModel? newModel)? onTapChannel;
  final bool isLandscape;
  final VoidCallback onCloseDrawer;
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated;
  final ValueKey<int>? refreshKey;

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();

  static Future<void> initializeData() async {
    final state = _stateKey.currentState;
    if (state != null) await state.initializeData();
  }

  static Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    final state = _stateKey.currentState;
    if (state != null) await state.updateFocusLogic(isInitial, initialIndexOverride: initialIndexOverride);
  }
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _epgItemScrollController = ScrollController();
  TvKeyNavigationState? _tvKeyNavigationState;
  bool isPortrait = true;
  bool _isSystemAutoSelected = false;

  final GlobalKey _viewPortKey = GlobalKey();
  List<String> _categories = [];
  List<String> _keys = [];
  List<Map<String, PlayModel>> _values = [];
  int _groupIndex = -1;
  int _channelIndex = -1;
  int _categoryIndex = -1;
  int _categoryStartIndex = 0;
  int _groupStartIndex = 0;
  int _channelStartIndex = 0;

  double _drawerHeight = 0.0;

  Map<int, Map<String, FocusNode>> _groupFocusCache = {};

  static final Map<String, Map<String, dynamic>> _scrollConfig = {
    'category': {'controllerKey': '_categoryScrollController', 'countKey': '_categories'},
    'group': {'controllerKey': '_scrollController', 'countKey': '_keys'},
    'channel': {'controllerKey': '_scrollChannelController', 'countKey': '_values'},
    'epg': {'controllerKey': '_epgItemScrollController', 'countKey': null, 'customHeight': epgItemHeight},
  };

  double getStatusBarHeight() {
    final height = appui.window.viewPadding.top / appui.window.devicePixelRatio;
    return height;
  }

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

  // 修改：优化 scrollTo，使用 calculateScrollOffset
  Future<void> scrollTo({
    required String targetList,
    required int index,
    double? alignment,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    final config = _scrollConfig[targetList];
    if (config == null || !mounted) {
      LogUtil.i('滚动目标无效或组件已销毁: $targetList');
      return;
    }

    final scrollController = this.getField(config['controllerKey']) as ScrollController;
    if (!scrollController.hasClients) {
      LogUtil.i('$targetList 控制器未附着');
      return;
    }

    int itemCount;
    if (targetList == 'epg') {
      itemCount = EPGListState.currentEpgDataLength;
    } else if (targetList == 'channel') {
      itemCount = _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0;
    } else {
      itemCount = (this.getField(config['countKey']) as List?)?.length ?? 0;
    }

    if (itemCount == 0) {
      LogUtil.i('$targetList 数据为空');
      return;
    }

    if (index < 0 || index >= itemCount) {
      LogUtil.i('$targetList 索引超出范围: index=$index, itemCount=$itemCount');
      return;
    }

    final double itemHeight = config['customHeight'] ?? itemHeight;
    final targetOffset = calculateScrollOffset(
      index: index,
      startIndex: 0,
      itemHeight: itemHeight,
      viewportHeight: _drawerHeight,
      length: itemCount,
      isMovingDown: focusManager.lastFocusedIndex != -1 && index > focusManager.lastFocusedIndex,
      isInitialFocus: focusManager.lastFocusedIndex == -1,
      currentOffset: scrollController.offset,
    );

    final finalOffset = targetOffset == double.infinity
        ? scrollController.position.maxScrollExtent
        : targetOffset.clamp(0.0, scrollController.position.maxScrollExtent);

    await scrollController.animateTo(
      finalOffset,
      duration: duration,
      curve: Curves.easeInOut,
    );
  }

  dynamic getField(String fieldName) {
    switch (fieldName) {
      case '_categoryScrollController':
        return _categoryScrollController;
      case '_scrollController':
        return _scrollController;
      case '_scrollChannelController':
        return _scrollChannelController;
      case '_epgItemScrollController':
        return _epgItemScrollController;
      case '_categories':
        return _categories;
      case '_keys':
        return _keys;
      case '_values':
        return _values;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _calculateDrawerHeight();
    WidgetsBinding.instance.addObserver(this);
    initializeData();
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey) {
      LogUtil.i('didUpdateWidget 开始: refreshKey=${widget.refreshKey?.value}, oldRefreshKey=${oldWidget.refreshKey?.value}');
      initializeData().then((_) {
        int initialFocusIndex = _categoryIndex >= 0 ? _categoryStartIndex + _categoryIndex : 0;
        Future<void> updateFocus() async {
          try {
            _tvKeyNavigationState?.deactivateFocusManagement();
            await updateFocusLogic(false, initialIndexOverride: initialFocusIndex);
            if (mounted && _tvKeyNavigationState != null) {
              _tvKeyNavigationState!.activateFocusManagement(initialIndexOverride: initialFocusIndex);
              setState(() {});
            }
          } catch (e) {
            LogUtil.e('updateFocus 失败: $e, stackTrace=${StackTrace.current}');
          }
        }
        updateFocus();
      }).catchError((e) {
        LogUtil.e('initializeData 失败: $e, stackTrace=${StackTrace.current}');
      });
    }
  }

  Future<void> initializeData() async {
    _initializeCategoryData();
    _initializeChannelData();
    if (_categories.isEmpty) {
      LogUtil.i('分类列表为空');
      return;
    }
    focusManager.configureNodes(_categories.length, isCategory: true);
    _initGroupFocusCacheForCategories();
    await updateFocusLogic(true);
  }

  void _initGroupFocusCacheForCategories() {
    if (_categories.isNotEmpty) {
      _groupFocusCache[0] = {
        'firstFocusNode': focusManager.focusNodes[0],
        'lastFocusNode': focusManager.focusNodes[_categories.length - 1]
      };
    }
  }

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

  bool shouldLoadEpg(List<String> keys, List<Map<String, PlayModel>> values, int groupIndex) {
    return keys.isNotEmpty && values.isNotEmpty && groupIndex >= 0 && groupIndex < values.length && values[groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _scrollController.dispose();
    _scrollChannelController.dispose();
    _categoryScrollController.dispose();
    _epgItemScrollController.dispose();

    _tvKeyNavigationState?.releaseResources(preserveFocus: false);
    _tvKeyNavigationState = null;

    _groupFocusCache.clear();

    focusManager.dispose();

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final newOrientation = MediaQuery.of(context).orientation == Orientation.portrait;
      final oldHeight = _drawerHeight;
      _calculateDrawerHeight();
      if (newOrientation != isPortrait || oldHeight != _drawerHeight) {
        setState(() {
          isPortrait = newOrientation;
        });
      }
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
          break;
        }
      }
    }
  }

  void _updateIndicesFromPlayModel(PlayModel? playModel, Map<String, Map<String, PlayModel>> categoryMap) {
    if (playModel?.group != null && categoryMap.containsKey(playModel?.group)) {
      _groupIndex = _keys.indexOf(playModel!.group!);
      if (_groupIndex != -1) {
        _channelIndex = _values[_groupIndex].keys.toList().indexOf(playModel.title ?? '');
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

  void _initializeChannelData() {
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    _updateIndicesFromPlayModel(widget.playModel, categoryMap);

    _isSystemAutoSelected = widget.playModel?.group != null && !categoryMap.containsKey(widget.playModel?.group);
  }

  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
  }

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

  Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    if (isInitial) {
      focusManager.lastFocusedIndex = -1;
    }

    final groupCount = _keys.length;
    final channelCount = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) ? _values[_groupIndex].length : 0;
    focusManager.focusStates.clear();
    focusManager.configureNodes(groupCount + channelCount);

    _categoryStartIndex = 0;
    _groupStartIndex = _categories.length;
    _channelStartIndex = _categories.length + _keys.length;

    _groupFocusCache.remove(1);
    _groupFocusCache.remove(2);
    if (_keys.isNotEmpty) {
      _groupFocusCache[1] = {
        'firstFocusNode': focusManager.focusNodes[_groupStartIndex],
        'lastFocusNode': focusManager.focusNodes[_groupStartIndex + _keys.length - 1]
      };
    }
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      _groupFocusCache[2] = {
        'firstFocusNode': focusManager.focusNodes[_channelStartIndex],
        'lastFocusNode': focusManager.focusNodes[_channelStartIndex + _values[_groupIndex].length - 1]
      };
    }

    LogUtil.i('焦点逻辑更新: categoryStart=$_categoryStartIndex, groupStart=$_groupStartIndex, '
        'channelStart=$_channelStartIndex');

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.updateNamedCache(cache: _groupFocusCache);
      if (!isInitial) {
        _tvKeyNavigationState!.releaseResources(preserveFocus: true);
        int safeIndex = initialIndexOverride ?? 0;
        if (safeIndex < 0 || safeIndex >= focusManager.focusNodes.length) {
          safeIndex = 0;
        }
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: safeIndex);
        _reInitializeFocusListeners();
      }
    }
  }

  void _onCategoryTap(int index) async {
    if (_categoryIndex == index) return;

    _categoryIndex = index;
    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];
    if (categoryMap == null || categoryMap.isEmpty) {
      _resetChannelData();
      _isSystemAutoSelected = true;
    } else {
      _keys = categoryMap.keys.toList();
      _values = categoryMap.values.toList();
      final currentPlayModel = widget.playModel;
      _updateIndicesFromPlayModel(currentPlayModel, categoryMap);
      _isSystemAutoSelected = false;
    }

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.deactivateFocusManagement();
    }

    await updateFocusLogic(false, initialIndexOverride: index);

    if (_tvKeyNavigationState != null) {
      _tvKeyNavigationState!.activateFocusManagement(initialIndexOverride: index);
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

  void _onGroupTap(int index) async {
    _groupIndex = index;
    _isSystemAutoSelected = false;

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
      _tvKeyNavigationState!.activateFocusManagement(initialIndexOverride: _groupStartIndex + index);
    }

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final isChannelInGroup = currentPlayModel != null && currentPlayModel.group == currentGroup;
        scrollTo(
          targetList: 'channel',
          index: isChannelInGroup ? _channelIndex : 0,
          alignment: isChannelInGroup ? null : 0.0,
        );
      }
    });
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
    Widget? channelContentWidget;

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

    if (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      channelContentWidget = ChannelContent(
        keys: _keys,
        values: _values,
        groupIndex: _groupIndex,
        playModel: widget.playModel,
        onTapChannel: widget.onTapChannel ?? (_) {},
        isTV: useFocusNavigation,
        channelScrollController: _scrollChannelController,
        epgScrollController: _epgItemScrollController,
        onCloseDrawer: widget.onCloseDrawer,
        channelStartIndex: _channelStartIndex,
      );
    }

    return TvKeyNavigation(
      focusNodes: focusManager.focusNodes,
      groupFocusCache: _groupFocusCache,
      cacheName: 'ChannelDrawerPage',
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: _handleTvKeyNavigationStateCreated,
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelContentWidget),
    );
  }

  // 修改：优化 _buildOpenDrawer，内联宽度计算
  Widget _buildOpenDrawer(
    bool isTV,
    Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelContentWidget,
  ) {
    final categoryWidth = isPortrait ? widthConfig['categoryPortrait']! : widthConfig['categoryLandscape']!;
    final groupWidth = groupListWidget != null
        ? (isPortrait ? widthConfig['groupPortrait']! : widthConfig['groupLandscape']!)
        : 0.0;

    final channelContentWidth = (groupListWidget != null && channelContentWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - 2 * 1.2
        : 0.0;

    final totalWidth = widget.isLandscape
        ? categoryWidth + groupWidth + channelContentWidth + 2 * 1.2
        : MediaQuery.of(context).size.width;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: totalWidth,
      decoration: BoxDecoration(
        gradient: defaultBackgroundColor,
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
              if (channelContentWidget != null) ...[
                verticalDivider,
                SizedBox(
                  width: channelContentWidth,
                  height: constraints.maxHeight,
                  child: channelContentWidget,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ChannelContent extends StatefulWidget {
  final List<String> keys;
  final List<Map<String, PlayModel>> values;
  final int groupIndex;
  final PlayModel? playModel;
  final Function(PlayModel?) onTapChannel;
  final bool isTV;
  final ScrollController channelScrollController;
  final ScrollController epgScrollController;
  final VoidCallback onCloseDrawer;
  final int channelStartIndex;

  const ChannelContent({
    Key? key,
    required this.keys,
    required this.values,
    required this.groupIndex,
    required this.playModel,
    required this.onTapChannel,
    required this.isTV,
    required this.channelScrollController,
    required this.epgScrollController,
    required this.onCloseDrawer,
    required this.channelStartIndex,
  }) : super(key: key);

  @override
  _ChannelContentState createState() => _ChannelContentState();
}

class _ChannelContentState extends State<ChannelContent> {
  int _channelIndex = 0;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;
  bool _isSystemAutoSelected = false;
  bool _isChannelAutoSelected = false;
  final Debouncer _epgDebouncer = Debouncer();
  DateTime? _lastRequestTime;

  @override
  void initState() {
    super.initState();
    _initializeChannelIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.playModel != null) {
        _loadEPGMsg(widget.playModel, channelKey: widget.playModel?.title ?? '');
      }
    });
  }

  @override
  void didUpdateWidget(ChannelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupIndex != widget.groupIndex) {
      _initializeChannelIndex();
    }

    if (oldWidget.playModel?.title != widget.playModel?.title) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEPGMsg(widget.playModel, channelKey: widget.playModel?.title ?? '');
      });
    }
  }

  void _initializeChannelIndex() {
    if (widget.groupIndex >= 0 && widget.groupIndex < widget.values.length) {
      _channelIndex = widget.values[widget.groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
      if (_channelIndex == -1) _channelIndex = 0;
      _isSystemAutoSelected = widget.playModel?.group != null && !widget.keys.contains(widget.playModel?.group);
      _isChannelAutoSelected = _channelIndex == 0;
      setState(() {});
    }
  }

  bool shouldLoadEpg(List<String> keys, List<Map<String, PlayModel>> values, int groupIndex) {
    return keys.isNotEmpty && values.isNotEmpty && groupIndex >= 0 && groupIndex < values.length && values[groupIndex].isNotEmpty;
  }

  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;

    _isSystemAutoSelected = false;
    _isChannelAutoSelected = false;

    widget.onTapChannel(newModel);

    setState(() {
      _channelIndex = widget.values[widget.groupIndex].keys.toList().indexOf(newModel?.title ?? '');
      _epgData = null;
      _selEPGIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEPGMsg(newModel, channelKey: newModel?.title ?? '');
    });
  }

  // 修改：优化 EPG 加载，使用 Debouncer
  void _loadEPGMsg(PlayModel? playModel, {String? channelKey}) {
    if (playModel == null || !mounted) return;

    _epgDebouncer.run(() {
      final now = DateTime.now();
      if (_lastRequestTime != null && now.difference(_lastRequestTime!).inMilliseconds < 500) {
        LogUtil.i('跳过频繁EPG请求: channelKey=$channelKey, 间隔=${now.difference(_lastRequestTime!).inMilliseconds}ms');
        return;
      }
      _lastRequestTime = now;

      EpgUtil.getEpg(playModel).then((res) {
        LogUtil.i('EpgUtil.getEpg 返回结果: ${res != null ? "成功" : "为null"}, 播放模型: ${playModel.title}');
        if (res == null || res.epgData == null || res.epgData!.isEmpty || !mounted) return;
        setState(() {
          _epgData = res.epgData!;
          _selEPGIndex = _getInitialSelectedIndex(_epgData);
        });
      });
    }, Duration(milliseconds: 300));
  }

  int _getInitialSelectedIndex(List<EpgData>? epgData) {
    if (epgData == null || epgData.isEmpty) return 0;
    final currentTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');
    for (int i = epgData.length - 1; i >= 0; i--) {
      if (epgData[i].start!.compareTo(currentTime) < 0) return i;
    }
    return 0;
  }

  @override
  void dispose() {
    _epgDebouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groupIndex < 0 || widget.groupIndex >= widget.values.length) {
      return const SizedBox.shrink();
    }

    String? selectedChannelName;
    if (_channelIndex >= 0 && _channelIndex < widget.values[widget.groupIndex].keys.length) {
      selectedChannelName = widget.values[widget.groupIndex].keys.toList()[_channelIndex];
    }

    final channelWidth = widget.isTV ? widthConfig['channelTV']! : widthConfig['channelNonTV']!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: channelWidth,
          child: ChannelList(
            channels: widget.values[widget.groupIndex],
            selectedChannelName: selectedChannelName,
            onChannelTap: _onChannelTap,
            isTV: widget.isTV,
            scrollController: widget.channelScrollController,
            startIndex: widget.channelStartIndex,
            isSystemAutoSelected: _isSystemAutoSelected,
          ),
        ),
        if (_epgData != null) ...[
          verticalDivider,
          Expanded(
            child: EPGList(
              epgData: _epgData,
              selectedIndex: _selEPGIndex,
              isTV: widget.isTV,
              epgScrollController: widget.epgScrollController,
              onCloseDrawer: widget.onCloseDrawer,
            ),
          ),
        ],
      ],
    );
  }
}
