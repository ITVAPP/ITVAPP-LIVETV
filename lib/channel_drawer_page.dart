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

// 启用非TV模式焦点逻辑（调试用）
const bool enableFocusInNonTVMode = true;

// 频道抽屉配置常量
class ChannelDrawerConfig {
  // 字体大小配置
  static const double fontSizeNormal = 16.0;
  static const double fontSizeTV = 20.0;
  static const double fontSizeSmallNormal = 14.0;
  static const double fontSizeSmallTV = 18.0;
  static const double fontSizeTitleNormal = 18.0;
  static const double fontSizeTitleTV = 22.0;
  
  // 列表项高度配置
  static const double itemHeightNormal = 42.0;
  static const double itemHeightTV = 50.0;
  static const double itemHeightEpgFactorNormal = 1.3;
  static const double itemHeightEpgFactorTV = 1.4;
  
  // TV模式列表宽度配置
  static const Map<String, Map<bool, double>> tvWidthMap = {
    'category': {true: 100.0, false: 120.0},
    'group': {true: 150.0, false: 180.0},
    'channel': {true: 160.0, false: 190.0},
  };
  
  // 普通模式列表宽度配置
  static const Map<String, Map<bool, double>> normalWidthMap = {
    'category': {true: 90.0, false: 100.0},
    'group': {true: 130.0, false: 140.0},
    'channel': {true: 140.0, false: 150.0},
  };
  
  // 获取字体大小
  static double getFontSize(bool isTV, {bool isSmall = false, bool isTitle = false}) {
    if (isTitle) return isTV ? fontSizeTitleTV : fontSizeTitleNormal;
    if (isSmall) return isTV ? fontSizeSmallTV : fontSizeSmallNormal;
    return isTV ? fontSizeTV : fontSizeNormal;
  }
  
  // 获取列表项高度
  static double getItemHeight(bool isTV, {bool isEpg = false}) {
    final baseHeight = isTV ? itemHeightTV : itemHeightNormal;
    final factor = isEpg ? (isTV ? itemHeightEpgFactorTV : itemHeightEpgFactorNormal) : 1.0;
    return baseHeight * factor;
  }
  
  // 获取列表宽度
  static double getListWidth(String type, bool isPortrait, bool isTV) {
    final widthMap = isTV ? tvWidthMap : normalWidthMap;
    return widthMap[type]?[isPortrait] ?? 0.0;
  }
  
  // 获取文本样式
  static TextStyle getTextStyle(bool isTV, {bool isSelected = false}) {
    return TextStyle(
      fontSize: getFontSize(isTV),
      height: 1.4,
      color: Colors.white,
      fontWeight: isSelected ? FontWeight.w600 : null,
      shadows: isSelected ? [
        Shadow(
          offset: Offset(0, 1),
          blurRadius: 4.0,
          color: Colors.black45,
        ),
      ] : null,
    );
  }
}

// 垂直分割线
final verticalDivider = Container(
  width: 1.5,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color.fromRGBO(255, 255, 255, 0.05),
        Color.fromRGBO(255, 255, 255, 0.10),
        Color.fromRGBO(255, 255, 255, 0.15),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  ),
);

// 水平分割线
final horizontalDivider = Container(
  height: 1,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color.fromRGBO(255, 255, 255, 0.05),
        Color.fromRGBO(255, 255, 255, 0.10),
        Color.fromRGBO(255, 255, 255, 0.15),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
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

// 选中状态文本样式
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

// 获取背景渐变，根据屏幕方向调整透明度
LinearGradient getBackgroundGradient(bool isLandscape) {
  final opacity = isLandscape ? 0.7 : 1.0;
  return LinearGradient(
    colors: [
      Color(0xFF1A1A1A).withOpacity(opacity),
      Color(0xFF2C2C2C).withOpacity(opacity),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// 默认内边距
const defaultPadding = EdgeInsets.symmetric(horizontal: 8.0);

// 选中和高亮颜色
const Color selectedColor = Color(0xFFEB144C);
const Color focusColor = Color(0xFFDFA02A);

// 构建列表项装饰样式
BoxDecoration buildItemDecoration({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  final shouldHighlight = (useFocus && hasFocus) || isSelected;
  final baseColor = useFocus && hasFocus ? focusColor : selectedColor;

  return BoxDecoration(
    gradient: shouldHighlight
        ? LinearGradient(
            colors: [
              baseColor.withOpacity(0.9),
              baseColor.withOpacity(0.7),
            ],
          )
        : null,
    border: Border.all(
        color: shouldHighlight ? Colors.white.withOpacity(0.3) : Colors.transparent,
        width: 1.5),
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

// 获取列表项文本样式
TextStyle getItemTextStyle({
  required bool useFocus,
  required bool hasFocus,
  required bool isSelected,
  required bool isTV,
}) {
  final baseStyle = ChannelDrawerConfig.getTextStyle(isTV);
  return (useFocus && hasFocus) || isSelected 
    ? baseStyle.merge(selectedTextStyle) 
    : baseStyle;
}

// 焦点状态管理单例类
class FocusStateManager {
  static final FocusStateManager _instance = FocusStateManager._internal();
  factory FocusStateManager() => _instance;
  FocusStateManager._internal();

  List<FocusNode> focusNodes = [];
  Map<int, bool> focusStates = {};
  int lastFocusedIndex = -1;
  List<FocusNode> categoryFocusNodes = [];
  bool _isUpdating = false;

  // 验证索引范围
  bool _restrictIndexRange(int startIndex, int length, {bool logError = false}) {
    if (startIndex < 0 || length <= 0 || startIndex + length > focusNodes.length) {
      if (logError) {
        LogUtil.e('索引越界: startIndex=$startIndex, length=$length, total=${focusNodes.length}');
      }
      return false;
    }
    return true;
  }

  // 清理焦点节点
  void _clearNodes(List<FocusNode> nodes) {
    for (var node in nodes) {
      node.removeListener(() {});
      node.dispose();
    }
    nodes.clear();
  }

  // 统一管理焦点节点
  void manageFocusNodes({
    required int categoryCount,
    int groupCount = 0,
    int channelCount = 0,
    bool resetAll = false,
  }) {
    if (_isUpdating || (categoryCount <= 0 && !resetAll)) return;
    _isUpdating = true;

    try {
      // 只在必要时重建分类节点
      if (resetAll || categoryFocusNodes.length != categoryCount) {
        _clearNodes(categoryFocusNodes);
        _clearNodes(focusNodes);
        categoryFocusNodes = List.generate(
          categoryCount,
          (index) => FocusNode(debugLabel: 'CategoryNode$index'),
        );
        focusNodes.addAll(categoryFocusNodes);
        focusStates.clear();
        lastFocusedIndex = -1;
      } else {
        // 复用现有分类节点，只处理动态节点
        final existingDynamicNodesCount = focusNodes.length - categoryFocusNodes.length;
        final requiredDynamicNodesCount = groupCount + channelCount;
        
        if (existingDynamicNodesCount != requiredDynamicNodesCount) {
          // 移除旧的动态节点
          for (int i = categoryFocusNodes.length; i < focusNodes.length; i++) {
            focusNodes[i].dispose();
          }
          focusNodes.length = categoryFocusNodes.length;
          
          // 添加新的动态节点
          if (requiredDynamicNodesCount > 0) {
            final dynamicNodes = List.generate(
              requiredDynamicNodesCount,
              (index) => FocusNode(debugLabel: 'DynamicNode$index'),
            );
            focusNodes.addAll(dynamicNodes);
          }
        }
      }
    } finally {
      _isUpdating = false;
    }
  }

  bool get isUpdating => _isUpdating;

  // 清理所有焦点节点
  void dispose() {
    if (_isUpdating) return;
    _isUpdating = true;
    _clearNodes(focusNodes);
    _clearNodes(categoryFocusNodes);
    focusStates.clear();
    lastFocusedIndex = -1;
    _isUpdating = false;
  }
}

// 全局焦点管理实例
final focusManager = FocusStateManager();

// 为焦点节点添加监听器
void addFocusListeners(
  int startIndex,
  int length,
  State state, {
  ScrollController? scrollController,
  bool isTV = false,
}) {
  if (focusManager.focusNodes.isEmpty) {
    LogUtil.e('焦点节点未初始化，无法添加监听器');
    return;
  }
  if (!focusManager._restrictIndexRange(startIndex, length, logError: true)) return;

  final nodes = focusManager.focusNodes;

  for (var i = 0; i < length; i++) {
    final index = startIndex + i;

    if (focusManager.focusStates.containsKey(index)) continue;

    final listener = () {
      final currentFocus = nodes[index].hasFocus;
      if (focusManager.focusStates[index] != currentFocus) {
        focusManager.focusStates[index] = currentFocus;

        if (state.mounted) {
          state.setState(() {});
        }

        if (scrollController != null && currentFocus && scrollController.hasClients) {
          _handleScroll(index, startIndex, state, scrollController, length, isTV);
        }
      }
    };

    nodes[index].addListener(listener);
    focusManager.focusStates[index] = nodes[index].hasFocus;
  }
}

// 处理焦点切换时的滚动逻辑
void _handleScroll(int index, int startIndex, State state, ScrollController scrollController, int length, bool isTV) {
  final itemIndex = index - startIndex;
  final channelDrawerState = state is _ChannelDrawerPageState
      ? state
      : state.context.findAncestorStateOfType<_ChannelDrawerPageState>();
  if (channelDrawerState == null) return;

  // 确定当前组
  int currentGroup = -1;
  if (index < channelDrawerState._groupStartIndex) {
    currentGroup = 0;
  } else if (index < channelDrawerState._channelStartIndex) {
    currentGroup = 1;
  } else {
    currentGroup = 2;
  }

  final isInitialFocus = focusManager.lastFocusedIndex == -1;
  final isMovingDown = !isInitialFocus && index > focusManager.lastFocusedIndex;
  focusManager.lastFocusedIndex = index;

  // 分类组无需滚动
  if (currentGroup == 0) return;

  final viewportHeight = channelDrawerState._drawerHeight;
  final itemHeight = ChannelDrawerConfig.getItemHeight(isTV, isEpg: false);
  final fullItemsInViewport = (viewportHeight / itemHeight).floor();

  // 添加调试日志
  LogUtil.d('''
  滚动调试信息 [${['category', 'group', 'channel'][currentGroup]}]:
  - itemIndex: $itemIndex / total: $length
  - isMovingDown: $isMovingDown
  - viewportHeight: $viewportHeight
  - itemHeight(含分割线): $fullItemHeight
  - fullItemsInViewport: $fullItemsInViewport
  - currentOffset: ${scrollController.offset}
  - maxScrollExtent: ${scrollController.position.maxScrollExtent}
  ''');

  // 列表项少于视口容量，滚动到顶部
  if (length <= fullItemsInViewport) {
    channelDrawerState.scrollTo(
      targetList: ['category', 'group', 'channel'][currentGroup], 
      index: 0
    );
    return;
  }

  // 修复：考虑分割线的实际高度
  // getItemHeight 已经包含了 +1，但实际布局中还有额外的分割线
  // 所以每个项目（除最后一个）的实际高度是 itemHeight + 1
  final actualItemHeight = itemHeight + 1;
  final itemTop = itemIndex * actualItemHeight;
  final itemBottom = itemTop + itemHeight; // 底部位置不包括下一个项目的分割线

  // 计算滚动位置
  double? alignment;
  if (itemIndex == 0) {
    alignment = 0.0;
  } else if (itemIndex == length - 1) {
    alignment = 1.0;
  } else {
    final currentOffset = scrollController.offset;
    
    // 向下移动时，确保项目完全可见（减去一个小缓冲区以提前触发）
    if (isMovingDown && itemBottom > currentOffset + viewportHeight - 2) {
      alignment = 2.0;
    } else if (!isMovingDown && itemTop < currentOffset) {
      alignment = 0.0;
    } else {
      return; // 在可视区域内，无需滚动
    }
  }

  channelDrawerState.scrollTo(
    targetList: ['category', 'group', 'channel'][currentGroup], 
    index: itemIndex, 
    alignment: alignment
  );
}

// 移除焦点监听器
void removeFocusListeners(int startIndex, int length) {
  if (!focusManager._restrictIndexRange(startIndex, length)) {
    LogUtil.e('removeFocusListeners: startIndex 超出范围: $startIndex');
    return;
  }
  for (var i = 0; i < length; i++) {
    final index = startIndex + i;
    focusManager.focusStates.remove(index);
  }
}

// 构建通用列表项
Widget buildGenericItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true,
  bool isEpg = false,
  List<Widget>? epgChildren,
  double? minHeight,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
  Key? key,
}) {
  final useFocus = isTV || enableFocusInNonTVMode;
  final focusNode =
      (index != null && index >= 0 && index < focusManager.focusNodes.length)
          ? focusManager.focusNodes[index]
          : null;
  final hasFocus = focusNode?.hasFocus ?? false;

  final textStyle = getItemTextStyle(
    useFocus: useFocus,
    hasFocus: hasFocus,
    isSelected: isSelected,
    isTV: isTV,
  );
  
  // 使用配置的高度
  final itemHeight = minHeight ?? ChannelDrawerConfig.getItemHeight(isTV, isEpg: isEpg);

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
            height: itemHeight,
            padding: defaultPadding,
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            decoration: buildItemDecoration(
              useFocus: useFocus,
              hasFocus: hasFocus,
              isSelected: isSelected,
              isSystemAutoSelected: isSystemAutoSelected,
            ),
            child: isEpg && epgChildren != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: epgChildren,
                  )
                : Text(
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

// 统一列表组件（合并CategoryList、GroupList、ChannelList）
class UnifiedListWidget extends StatefulWidget {
  final List<dynamic> items;
  final int selectedIndex;
  final Function(dynamic) onItemTap;  // 修改：从 Function(int) 改为 Function(dynamic)
  final ScrollController scrollController;
  final bool isTV;
  final int startIndex;
  final String listType; // 'category' | 'group' | 'channel'
  final bool isFavoriteCategory;
  final bool isSystemAutoSelected;
  final String? selectedChannelName;
  final BuildContext parentContext;

  const UnifiedListWidget({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemTap,
    required this.scrollController,
    required this.isTV,
    required this.startIndex,
    required this.listType,
    this.isFavoriteCategory = false,
    this.isSystemAutoSelected = false,
    this.selectedChannelName,
    required this.parentContext,
  });

  @override
  State<UnifiedListWidget> createState() => _UnifiedListWidgetState();
}

class _UnifiedListWidgetState extends State<UnifiedListWidget> {
  @override
  void initState() {
    super.initState();
    addFocusListeners(widget.startIndex, widget.items.length, this,
        scrollController: widget.scrollController, isTV: widget.isTV);
  }

  @override
  void dispose() {
    if (focusManager.focusNodes.isNotEmpty &&
        widget.startIndex >= 0 &&
        widget.startIndex < focusManager.focusNodes.length) {
      removeFocusListeners(widget.startIndex, widget.items.length);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // 处理空收藏夹的特殊情况
    if (widget.listType == 'group' && widget.items.isEmpty && widget.isFavoriteCategory) {
      return Container(
        decoration: BoxDecoration(gradient: getBackgroundGradient(isLandscape)),
        child: ListView(
          controller: widget.scrollController,
          children: [
            Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: ChannelDrawerConfig.getItemHeight(widget.isTV)),
              child: Center(
                child: Text(
                  S.of(widget.parentContext).nofavorite,
                  textAlign: TextAlign.center,
                  style: ChannelDrawerConfig.getTextStyle(widget.isTV, isSelected: true),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: getBackgroundGradient(isLandscape)),
      child: ListView(
        controller: widget.scrollController,
        shrinkWrap: false,
        children: [
          RepaintBoundary(
            child: Group(
              groupIndex: widget.listType == 'category' ? 0 : widget.listType == 'group' ? 1 : 2,
              children: List.generate(widget.items.length, (index) {
                String displayTitle;
                bool isSelected;
                
                if (widget.listType == 'category') {
                  final category = widget.items[index] as String;
                  displayTitle = category == Config.myFavoriteKey
                      ? S.of(widget.parentContext).myfavorite
                      : category == Config.allChannelsKey
                          ? S.of(widget.parentContext).allchannels
                          : category;
                  isSelected = widget.selectedIndex == index;
                } else if (widget.listType == 'group') {
                  displayTitle = widget.items[index] as String;
                  isSelected = widget.selectedIndex == index;
                } else {
                  final channelEntry = widget.items[index] as MapEntry<String, PlayModel>;
                  displayTitle = channelEntry.key;
                  
                  final channelDrawerState = widget.parentContext.findAncestorStateOfType<_ChannelDrawerPageState>();
                  final currentGroupIndex = channelDrawerState?._groupIndex ?? -1;
                  final currentPlayingGroup = channelDrawerState?.widget.playModel?.group;
                  final currentGroupKeys = channelDrawerState?._keys ?? [];
                  final currentGroupName = (currentGroupIndex >= 0 && currentGroupIndex < currentGroupKeys.length)
                      ? currentGroupKeys[currentGroupIndex]
                      : null;
                  final isCurrentPlayingGroup = currentGroupName == currentPlayingGroup;
                  isSelected = isCurrentPlayingGroup && widget.selectedChannelName == displayTitle;
                }

                return buildGenericItem(
                  title: displayTitle,
                  isSelected: isSelected,
                  onTap: () {
                    if (widget.listType == 'channel') {
                      // 修改：直接传递 PlayModel，不再进行类型转换
                      final channelEntry = widget.items[index] as MapEntry<String, PlayModel>;
                      widget.onItemTap(channelEntry.value);
                    } else {
                      // 传递索引
                      widget.onItemTap(index);
                    }
                  },
                  isCentered: widget.listType == 'category',
                  isTV: widget.isTV,
                  context: context,
                  index: widget.startIndex + index,
                  isLastItem: index == widget.items.length - 1,
                  isSystemAutoSelected: widget.isSystemAutoSelected,
                  key: widget.listType == 'category' && index == 0 ? GlobalKey() : null,
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
  Timer? _scrollDebounceTimer;

  static int currentEpgDataLength = 0;

  @override
  void initState() {
    super.initState();
    EPGListState.currentEpgDataLength = widget.epgData?.length ?? 0;
    _scheduleScrollWithDebounce();
  }

  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData) {
      EPGListState.currentEpgDataLength = widget.epgData?.length ?? 0;
    }
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      _shouldScroll = true;
      _scheduleScrollWithDebounce();
    }
  }

  void _scheduleScrollWithDebounce() {
    if (!_shouldScroll || !mounted) return;

    _scrollDebounceTimer?.cancel();

    _scrollDebounceTimer = Timer(Duration(milliseconds: 150), () {
      if (mounted && widget.epgData != null && widget.epgData!.isNotEmpty) {
        final state = context.findAncestorStateOfType<_ChannelDrawerPageState>();
        if (state != null && state._epgItemScrollController.hasClients) {
          state.scrollTo(targetList: 'epg', index: widget.selectedIndex, alignment: null);
          _shouldScroll = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.epgData == null || widget.epgData!.isEmpty) return const SizedBox.shrink();
    final useFocus = widget.isTV || enableFocusInNonTVMode;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    final appBarDecoration = BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFF1A1A1A).withOpacity(isLandscape ? 0.7 : 1.0),
          Color(0xFF2C2C2C).withOpacity(isLandscape ? 0.7 : 1.0),
        ],
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
    
    return Container(
      decoration: BoxDecoration(gradient: getBackgroundGradient(isLandscape)),
      child: Column(
        children: [
          Container(
            height: ChannelDrawerConfig.getItemHeight(widget.isTV),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            decoration: appBarDecoration,
            child: Text(
              S.of(context).programListTitle,
              style: ChannelDrawerConfig.getTextStyle(widget.isTV, isSelected: true).merge(
                TextStyle(fontSize: ChannelDrawerConfig.getFontSize(widget.isTV, isTitle: true))
              ),
            ),
          ),
          verticalDivider,
          Flexible(
            child: ListView.builder(
              controller: widget.epgScrollController,
              itemCount: widget.epgData!.length,
              itemBuilder: (context, index) {
                final data = widget.epgData![index];
                final isSelect = index == widget.selectedIndex;
                final focusNode = useFocus ? FocusNode(debugLabel: 'EpgNode$index') : null;
                final hasFocus = focusNode?.hasFocus ?? false;
                final textStyle = getItemTextStyle(
                  useFocus: useFocus,
                  hasFocus: hasFocus,
                  isSelected: isSelect,
                  isTV: widget.isTV,
                );

                return buildGenericItem(
                  title: data.title ?? S.of(context).parseError,
                  isSelected: isSelect,
                  onTap: widget.onCloseDrawer,
                  context: context,
                  isEpg: true,
                  isTV: widget.isTV,
                  isLastItem: index == widget.epgData!.length - 1,
                  isCentered: false,
                  epgChildren: [
                    Text(
                      '${data.start}-${data.end}',
                      style: textStyle.merge(
                        TextStyle(fontSize: ChannelDrawerConfig.getFontSize(widget.isTV, isSmall: true))
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      data.title ?? S.of(context).parseError,
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 频道抽屉页面主组件
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

  // 初始化数据
  static Future<void> initializeData() async {
    final state = _stateKey.currentState;
    if (state != null) await state.initializeData();
  }

  // 更新焦点逻辑
  static Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    final state = _stateKey.currentState;
    if (state != null)
      await state.updateFocusLogic(isInitial, initialIndexOverride: initialIndexOverride);
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
  
  // 在初始化时获取一次isTV值
  late final bool isTV;

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

  // 计算抽屉高度
  void _calculateDrawerHeight() {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = appui.window.viewPadding.top / appui.window.devicePixelRatio;
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

  // 滚动到指定列表项
  Future<void> scrollTo({
    required String targetList,
    required int index,
    double? alignment,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    ScrollController? scrollController;
    int itemCount;
    double localItemHeight = ChannelDrawerConfig.getItemHeight(isTV, isEpg: false);
    
    // 考虑实际项目高度（包含分割线）
    double actualItemHeight = localItemHeight + 1;

    // 根据目标列表获取相应的控制器和数据
    switch (targetList) {
      case 'category':
        scrollController = _categoryScrollController;
        itemCount = _categories.length;
        break;
      case 'group':
        scrollController = _scrollController;
        itemCount = _keys.length;
        break;
      case 'channel':
        scrollController = _scrollChannelController;
        itemCount = _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0;
        break;
      case 'epg':
        scrollController = _epgItemScrollController;
        itemCount = EPGListState.currentEpgDataLength;
        localItemHeight = ChannelDrawerConfig.getItemHeight(isTV, isEpg: true);
        actualItemHeight = localItemHeight + 1;
        break;
      default:
        LogUtil.i('滚动目标无效: $targetList');
        return;
    }

    if (!mounted || scrollController == null || !scrollController.hasClients) {
      LogUtil.i('$targetList 控制器未附着');
      return;
    }

    if (itemCount == 0) {
      LogUtil.i('$targetList 数据为空');
      return;
    }

    if (index < 0 || index >= itemCount) {
      LogUtil.i('$targetList 索引超出范围: index=$index, itemCount=$itemCount');
      return;
    }

    double targetOffset;
    if (alignment == 0.0) {
      // 滚动到顶部对齐
      targetOffset = index * actualItemHeight;
    } else if (alignment == 1.0) {
      // 滚动到最底部
      targetOffset = scrollController.position.maxScrollExtent;
    } else if (alignment == 2.0) {
      // 滚动到底部对齐（让项目显示在视口底部）
      // 考虑最后一个项目没有分割线
      final totalHeight = (index + 1) * actualItemHeight - 1; // 减去最后一个分割线
      targetOffset = totalHeight - _drawerHeight;
      targetOffset = targetOffset < 0 ? 0 : targetOffset;
    } else {
      // 默认滚动逻辑
      final offsetAdjustment =
          (targetList == 'group' || targetList == 'channel') ? _categoryIndex.clamp(0, 6) : 2;
      targetOffset = (index - offsetAdjustment) * actualItemHeight;
      if (targetList == 'epg') {
          targetOffset += (actualItemHeight - ChannelDrawerConfig.getItemHeight(isTV)); // 添加额外偏移
      }
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
    // 在initState中获取isTV值，确保在使用context之前
    isTV = context.read<ThemeProvider>().isTV;
    _calculateDrawerHeight();
    WidgetsBinding.instance.addObserver(this);
    initializeData();
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey) {
      LogUtil.i(
          'didUpdateWidget 开始: refreshKey=${widget.refreshKey?.value}, oldRefreshKey=${oldWidget.refreshKey?.value}');
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

  // 初始化数据
  Future<void> initializeData() async {
    _initializeCategoryData();
    _initializeChannelData();
    if (_categories.isEmpty) {
      LogUtil.i('分类列表为空');
      return;
    }
    focusManager.manageFocusNodes(categoryCount: _categories.length, resetAll: true);
    _initGroupFocusCacheForCategories();
    await updateFocusLogic(true);
  }

  // 初始化分类焦点缓存
  void _initGroupFocusCacheForCategories() {
    if (_categories.isNotEmpty) {
      _groupFocusCache[0] = {
        'firstFocusNode': focusManager.focusNodes[0],
        'lastFocusNode': focusManager.focusNodes[_categories.length - 1]
      };
    }
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

  // 处理TV键盘导航状态创建
  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

  // 初始化分类数据
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

  // 根据播放模型更新索引
  void _updateIndicesFromPlayModel(
      PlayModel? playModel, Map<String, Map<String, PlayModel>> categoryMap) {
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

    _updateIndicesFromPlayModel(widget.playModel, categoryMap);

    _isSystemAutoSelected =
        widget.playModel?.group != null && !categoryMap.containsKey(widget.playModel?.group);
  }

  // 重置频道数据
  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
  }

  // 重新初始化焦点监听器
  void _reInitializeFocusListeners() {
    for (var node in focusManager.focusNodes) {
      node.removeListener(() {});
    }

    addFocusListeners(0, _categories.length, this, scrollController: _categoryScrollController, isTV: isTV);

    if (_keys.isNotEmpty) {
      addFocusListeners(_categories.length, _keys.length, this,
          scrollController: _scrollController, isTV: isTV);
      if (_values.isNotEmpty && _groupIndex >= 0) {
        addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          this,
          scrollController: _scrollChannelController,
          isTV: isTV,
        );
      }
    }
  }

  // 更新焦点逻辑
  Future<void> updateFocusLogic(bool isInitial, {int? initialIndexOverride}) async {
    if (isInitial) {
      focusManager.lastFocusedIndex = -1;
    }

    final groupCount = _keys.length;
    final channelCount = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length)
        ? _values[_groupIndex].length
        : 0;
    focusManager.focusStates.clear();
    focusManager.manageFocusNodes(
        categoryCount: _categories.length, groupCount: groupCount, channelCount: channelCount);

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
        'lastFocusNode':
            focusManager.focusNodes[_channelStartIndex + _values[_groupIndex].length - 1]
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

  // 更新选中状态
  Future<void> updateSelection(String listType, int index) async {
    if (listType == 'category' && _categoryIndex == index || listType == 'group' && _groupIndex == index) return;
    final newIndex = listType == 'category' ? index : _groupStartIndex + index;
    _tvKeyNavigationState?.deactivateFocusManagement();
    setState(() {
      if (listType == 'category') {
        _categoryIndex = index;
        _initializeChannelData();
      } else {
        _groupIndex = index;
        final currentPlayModel = widget.playModel;
        final currentGroup = _keys[index];
        if (currentPlayModel != null && currentPlayModel.group == currentGroup) {
          _channelIndex = _values[_groupIndex].keys.toList().indexOf(currentPlayModel.title ?? '');
          if (_channelIndex == -1) _channelIndex = 0;
        } else {
          _channelIndex = 0;
        }
        _isSystemAutoSelected = false;
      }
    });
    await updateFocusLogic(false, initialIndexOverride: newIndex);
    _tvKeyNavigationState?.activateFocusManagement(initialIndexOverride: newIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToList(listType, index));
  }

  // 滚动到指定列表
  void _scrollToList(String listType, int index) {
    if (listType == 'category') {
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
    } else {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final currentPlayModel = widget.playModel;
        final currentGroup = _keys[index];
        final isChannelInGroup = currentPlayModel != null && currentPlayModel.group == currentGroup;
        scrollTo(
          targetList: 'channel',
          index: isChannelInGroup ? _channelIndex : 0,
          alignment: isChannelInGroup ? null : 0.0,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;

    Widget categoryListWidget = UnifiedListWidget(
      items: _categories,
      selectedIndex: _categoryIndex,
      onItemTap: (dynamic value) => updateSelection('category', value as int),  // 修改：明确类型处理
      isTV: isTV,
      startIndex: 0,
      scrollController: _categoryScrollController,
      listType: 'category',
      parentContext: context,
    );

    Widget? groupListWidget;
    Widget? channelContentWidget;

    groupListWidget = UnifiedListWidget(
      items: _keys,
      selectedIndex: _groupIndex,
      onItemTap: (dynamic value) => updateSelection('group', value as int),  // 修改：明确类型处理
      isTV: isTV,
      scrollController: _scrollController,
      listType: 'group',
      isFavoriteCategory: _categoryIndex >= 0 && _categories.isNotEmpty && _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: _categories.length,
      isSystemAutoSelected: _isSystemAutoSelected,
      parentContext: context,
    );

    if (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      channelContentWidget = ChannelContent(
        keys: _keys,
        values: _values,
        groupIndex: _groupIndex,
        playModel: widget.playModel,
        onTapChannel: widget.onTapChannel ?? (_) {},
        isTV: isTV,
        isPortrait: isPortrait,
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
      child: _buildOpenDrawer(useFocusNavigation, categoryListWidget, groupListWidget, channelContentWidget),
    );
  }

  // 构建抽屉页面
  Widget _buildOpenDrawer(
    bool useFocusNavigation,
    Widget categoryListWidget,
    Widget? groupListWidget,
    Widget? channelContentWidget,
  ) {
    final double categoryWidth = ChannelDrawerConfig.getListWidth('category', isPortrait, isTV);
    final double groupWidth = groupListWidget != null ? ChannelDrawerConfig.getListWidth('group', isPortrait, isTV) : 0.0;

    final double channelContentWidth = (groupListWidget != null && channelContentWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - 2 * 1.5
        : 0.0;

    final totalWidth = widget.isLandscape
        ? categoryWidth + groupWidth + channelContentWidth + 2 * 1.5
        : MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: totalWidth,
      decoration: BoxDecoration(
        gradient: getBackgroundGradient(!isPortrait),
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

// 频道内容组件
class ChannelContent extends StatefulWidget {
  final List<String> keys;
  final List<Map<String, PlayModel>> values;
  final int groupIndex;
  final PlayModel? playModel;
  final Function(PlayModel?) onTapChannel;
  final bool isTV;
  final bool isPortrait;
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
    required this.isPortrait,
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
  Timer? _epgDebounceTimer;
  String? _lastChannelKey;
  
  @override
  void initState() {
    super.initState();
    _initializeChannelIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.playModel != null) {
        _loadEPGMsgWithDebounce(widget.playModel, channelKey: widget.playModel?.title ?? '');
      }
    });
  }

  @override
  void didUpdateWidget(ChannelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupIndex != widget.groupIndex) {
      _initializeChannelIndex();
    }

    if (oldWidget.playModel?.title != widget.playModel?.title &&
        widget.playModel?.title != _lastChannelKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEPGMsgWithDebounce(widget.playModel, channelKey: widget.playModel?.title ?? '');
      });
    }
  }

  // 初始化频道索引
  void _initializeChannelIndex() {
    if (widget.groupIndex >= 0 && widget.groupIndex < widget.values.length) {
      _channelIndex = widget.values[widget.groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
      if (_channelIndex == -1) _channelIndex = 0;
      _isSystemAutoSelected = widget.playModel?.group != null && !widget.keys.contains(widget.playModel?.group);
      if (mounted) {
        setState(() {});
      }
    }
  }

  // 处理频道点击
  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;

    _isSystemAutoSelected = false;

    widget.onTapChannel(newModel);

    setState(() {
      _channelIndex = widget.values[widget.groupIndex].keys.toList().indexOf(newModel?.title ?? '');
      _epgData = null;
      _selEPGIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEPGMsgWithDebounce(newModel, channelKey: newModel?.title ?? '');
    });
  }

  // 防抖加载EPG数据
  void _loadEPGMsgWithDebounce(PlayModel? playModel, {String? channelKey}) {
    _epgDebounceTimer?.cancel();

    if (playModel == null || channelKey == null || channelKey.isEmpty) return;

    // 避免重复加载相同频道
    if (channelKey == _lastChannelKey && _epgData != null) {
      LogUtil.i('忽略重复EPG加载: channelKey=$channelKey');
      return;
    }

    _lastChannelKey = channelKey;

    _epgDebounceTimer = Timer(Duration(milliseconds: 300), () {
      _loadEPGMsg(playModel, channelKey: channelKey);
    });
  }

  // 加载EPG数据
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (playModel == null || !mounted) return;
    final res = await EpgUtil.getEpg(playModel);
    LogUtil.i('EpgUtil.getEpg 返回结果: ${res != null ? "成功" : "为null"}, 播放模型: ${playModel.title}');
    if (res == null || res.epgData == null || res.epgData!.isEmpty) return;

    if (mounted) {
      setState(() {
        _epgData = res.epgData!;
        _selEPGIndex = _getInitialSelectedIndex(_epgData);
      });
    }
  }

  // 获取初始选中EPG索引
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
    _epgDebounceTimer?.cancel();
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

    final double channelWidth = ChannelDrawerConfig.getListWidth('channel', widget.isPortrait, widget.isTV);
    final channelEntries = widget.values[widget.groupIndex].entries.toList();
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: channelWidth,
          child: UnifiedListWidget(
            items: channelEntries,
            selectedIndex: _channelIndex,
            onItemTap: (dynamic value) => _onChannelTap(value as PlayModel?),
            isTV: widget.isTV,
            scrollController: widget.channelScrollController,
            startIndex: widget.channelStartIndex,
            listType: 'channel',
            isSystemAutoSelected: _isSystemAutoSelected,
            selectedChannelName: selectedChannelName,
            parentContext: context,
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
