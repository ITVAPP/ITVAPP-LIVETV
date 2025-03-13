import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'dart:convert'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 是否在非 TV 模式下启用 TV 模式的焦点逻辑（用于调试）
const bool enableFocusInNonTVMode = true; // 默认关闭

// 分割线样式
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
  fontSize: 16, // 调整字体大小
  height: 1.4, // 调整行高
  color: Colors.white, // 添加默认颜色
);

const selectedTextStyle = TextStyle(
  fontWeight: FontWeight.w600, // 加粗
  color: Colors.white,
  shadows: [
    Shadow(
      offset: Offset(0, 1), // 调整阴影偏移
      blurRadius: 4.0, // 增加模糊半径
      color: Colors.black45, // 调整阴影颜色
    ),
  ],
);

// 最小高度
const double defaultMinHeight = 42.0;

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
const Color selectedColor = Color(0xFFEB144C); // 选中颜色
const Color focusColor = Color(0xFFDFA02A); // 焦点颜色

// 默认顶部偏移量
const double defaultTopOffset = 112.0; // 默认滚动距离顶部的偏移量

// 默认分类和分组宽度
const double categoryWidthPortrait = 110.0; // 竖屏分类宽度
const double categoryWidthLandscape = 120.0; // 横屏分类宽度
const double groupWidthPortrait = 120.0; // 竖屏分组宽度
const double groupWidthLandscape = 130.0; // 横屏分组宽度
const double channelWidthLandscape = 160.0; // 横屏频道宽度

// 缓存大小常量
const int defaultCacheSize = 50; // 默认 LinkedHashMap 最大容量
const int epgCacheSize = 30; // EPG 缓存最大容量

LinearGradient? getGradientForDecoration({
  required bool isTV,
  required bool hasFocus,
  required bool isSelected,
  required bool isSystemAutoSelected,
}) {
  if (isTV) {
    return hasFocus
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
            : null);
  } else {
    return isSelected && !isSystemAutoSelected
        ? LinearGradient(
            colors: [
              selectedColor.withOpacity(0.9),
              selectedColor.withOpacity(0.7),
            ],
          )
        : null;
  }
}

BoxDecoration buildItemDecoration({
  bool isSelected = false,
  bool hasFocus = false,
  bool isTV = false,
  bool isSystemAutoSelected = false,
}) {
  return BoxDecoration(
    gradient: getGradientForDecoration(
      isTV: isTV,
      hasFocus: hasFocus,
      isSelected: isSelected,
      isSystemAutoSelected: isSystemAutoSelected,
    ),
    border: Border.all(
      color: hasFocus || (isSelected && !isSystemAutoSelected)
          ? Colors.white.withOpacity(0.3)
          : Colors.transparent,
      width: 1.5, // 加粗边框
    ),
    borderRadius: BorderRadius.circular(8), // 添加圆角
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

/// 焦点管理工具类
class FocusManager {
  static List<FocusNode> _focusNodes = [];

  /// 初始化或调整焦点节点数量，复用现有节点
  static void initializeFocusNodes(int totalCount) {
    if (totalCount < 0) {
      LogUtil.e('焦点节点数量无效: $totalCount');
      return;
    }
    if (_focusNodes.length != totalCount) {
      if (_focusNodes.length > totalCount) {
        // 减少节点：移除多余的并清理
        for (int i = _focusNodes.length - 1; i >= totalCount; i--) {
          _focusNodes[i].removeListener(() {});
          _focusNodes[i].dispose();
        }
        _focusNodes = _focusNodes.sublist(0, totalCount);
      } else {
        // 增加节点：追加新节点
        _focusNodes.addAll(
          List.generate(totalCount - _focusNodes.length, (_) => FocusNode()),
        );
      }
      LogUtil.d('调整焦点节点数量: ${_focusNodes.length} -> $totalCount');
    }
  }

  /// 添加焦点监听器，优化重复调用并支持滚动
  static void addFocusListeners(
    int startIndex,
    int length,
    State state, {
    ScrollController? scrollController,
    double? viewPortHeight,
    required String listType, // 新增：区分列表类型
  }) {
    if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
      LogUtil.e('焦点监听器索引越界: startIndex=$startIndex, length=$length, total=${_focusNodes.length}');
      return;
    }
    // 移除旧监听器，确保隔离
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      _focusNodes[index].removeListener(() {});
    }
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      _focusNodes[index].addListener(() {
        if (state.mounted && _focusNodes[index].hasFocus) {
          state.setState(() {});
          if (scrollController != null && viewPortHeight != null) {
            final itemIndex = index - startIndex;
            if (listType == "group") {
              ScrollUtil.scrollToCurrentItem(
                groupIndex: itemIndex,
                groupController: scrollController,
                viewPortHeight: viewPortHeight,
                isSwitching: false,
              );
            } else if (listType == "channel") {
              ScrollUtil.scrollToCurrentItem(
                channelIndex: itemIndex,
                channelController: scrollController,
                viewPortHeight: viewPortHeight,
                isSwitching: false,
              );
            }
            // 分类列表不滚动
          }
        }
      });
    }
  }

  static List<FocusNode> getFocusNodes() => _focusNodes;

  /// 清理所有焦点节点，释放资源
  static void dispose() {
    for (var node in _focusNodes) {
      node.removeListener(() {}); // 确保移除所有监听器
      node.dispose();
    }
    _focusNodes.clear();
  }
}

// 滚动工具类
class ScrollUtil {
  // 滚动到顶部
  static void scrollToTop(ScrollController controller) {
    if (controller.hasClients) controller.jumpTo(0);
  }

  // 统一滚动到当前播放的频道/分组项
  static void scrollToCurrentItem({
    int? groupIndex,
    int? channelIndex,
    ScrollController? groupController,
    ScrollController? channelController,
    required double viewPortHeight,
    double topOffset = defaultTopOffset, // 默认 112.0
    bool isSwitching = false, // 是否为切换分类/分组场景
  }) {
    const itemHeight = defaultMinHeight;
    const scrollThreshold = itemHeight * 2; // 提前两项触发底部对齐

    // 处理分组滚动
    if (groupController != null && groupIndex != null && groupController.hasClients) {
      final maxScrollExtent = groupController.position.maxScrollExtent;
      double targetOffset;

      if (isSwitching) {
        targetOffset = (groupIndex * itemHeight - topOffset).clamp(0.0, maxScrollExtent);
      } else {
        final currentOffset = groupController.offset;
        final itemTop = groupIndex * itemHeight;
        final itemBottom = (groupIndex + 1) * itemHeight;
        if (itemTop < currentOffset) {
          targetOffset = itemTop.clamp(0.0, maxScrollExtent); // 顶部对齐
        } else if (itemBottom > currentOffset + viewPortHeight - scrollThreshold) {
          targetOffset = (itemBottom - viewPortHeight).clamp(0.0, maxScrollExtent); // 底部对齐
        } else {
          return; // 未超出，不滚动
        }
      }
      groupController.jumpTo(targetOffset);
    }

    // 处理频道滚动
    if (channelController != null && channelIndex != null && channelController.hasClients) {
      final maxScrollExtent = channelController.position.maxScrollExtent;
      double targetOffset;

      if (isSwitching) {
        targetOffset = (channelIndex * itemHeight - topOffset).clamp(0.0, maxScrollExtent);
      } else {
        final currentOffset = channelController.offset;
        final itemTop = channelIndex * itemHeight;
        final itemBottom = (channelIndex + 1) * itemHeight;
        if (itemTop < currentOffset) {
          targetOffset = itemTop.clamp(0.0, maxScrollExtent); // 顶部对齐
        } else if (itemBottom > currentOffset + viewPortHeight - scrollThreshold) {
          targetOffset = (itemBottom - viewPortHeight).clamp(0.0, maxScrollExtent); // 底部对齐
        } else {
          return; // 未超出，不滚动
        }
      }
      channelController.jumpTo(targetOffset);
    }
  }
}

/// 构建通用列表项
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  required bool isCentered,
  double minHeight = defaultMinHeight,
  EdgeInsets padding = defaultPadding,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
}) {
  // 添加索引范围检查
  FocusNode? focusNode = (index != null && index >= 0 && index < FocusManager.getFocusNodes().length)
      ? FocusManager.getFocusNodes()[index]
      : null;

  final hasFocus = focusNode?.hasFocus ?? false;

  // 缓存合并后的文本样式
  final textStyle = (isTV || enableFocusInNonTVMode)
      ? (hasFocus
          ? defaultTextStyle.merge(selectedTextStyle)
          : (isSelected && !isSystemAutoSelected
              ? defaultTextStyle.merge(selectedTextStyle)
              : defaultTextStyle))
      : (isSelected && !isSystemAutoSelected
          ? defaultTextStyle.merge(selectedTextStyle)
          : defaultTextStyle);

  Widget listItemContent = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MouseRegion(
        // 优化重绘逻辑，仅在需要时触发
        onEnter: (_) => (!isTV && !enableFocusInNonTVMode)
            ? setStateOrMarkNeedsBuild(context)
            : null,
        onExit: (_) => (!isTV && !enableFocusInNonTVMode)
            ? setStateOrMarkNeedsBuild(context)
            : null,
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
              isTV: isTV || enableFocusInNonTVMode,
              isSystemAutoSelected: isSystemAutoSelected,
            ),
            child: Text(
              title,
              style: textStyle,
              softWrap: true,
              maxLines: null,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
      ),
      if (!isLastItem) horizontalDivider,
    ],
  );

  return (isTV || enableFocusInNonTVMode) && useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

/// 工具函数
void setStateOrMarkNeedsBuild(BuildContext context) {
  if (context is StatefulElement && context.state.mounted) {
    (context as StatefulElement).state.setState(() {});
  } else {
    (context as Element).markNeedsBuild();
  }
}

void _updateFocusListenersIfDataChanged<T extends StatefulWidget>(
  T oldWidget,
  T widget,
  State state,
  List<dynamic> newData,
  List<dynamic> oldData,
  int startIndex,
  ScrollController? scrollController,
  double? viewPortHeight,
  String listType, // 新增参数
) {
  if (oldData != newData) {
    FocusManager.addFocusListeners(
      startIndex,
      newData.length,
      state,
      scrollController: scrollController,
      viewPortHeight: viewPortHeight,
      listType: listType, // 传递 listType
    );
  }
}

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
    FocusManager.addFocusListeners(
      widget.startIndex,
      widget.categories.length,
      this,
      listType: "category", // 指定为分类列表
    );
  }

  @override
  void didUpdateWidget(covariant CategoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFocusListenersIfDataChanged(
      oldWidget,
      widget,
      this,
      widget.categories,
      oldWidget.categories,
      widget.startIndex,
      null,
      null,
      "category", // 指定为分类列表
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
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
  @override
  void initState() {
    super.initState();
    FocusManager.addFocusListeners(
      widget.startIndex,
      widget.keys.length,
      this,
      scrollController: widget.scrollController,
      viewPortHeight: (context.findAncestorStateOfType<_ChannelDrawerPageState>() as _ChannelDrawerPageState)._viewPortHeight,
      listType: "group", // 指定为分组列表
    );
  }

  @override
  void didUpdateWidget(covariant GroupList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFocusListenersIfDataChanged(
      oldWidget,
      widget,
      this,
      widget.keys,
      oldWidget.keys,
      widget.startIndex,
      widget.scrollController,
      (context.findAncestorStateOfType<_ChannelDrawerPageState>() as _ChannelDrawerPageState)._viewPortHeight,
      "group", // 指定为分组列表
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty && !widget.isFavoriteCategory) {
      return const SizedBox.shrink();
    }
    bool isSystemAutoSelected = false;

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: widget.keys.isEmpty && widget.isFavoriteCategory
          ? ListView(
              controller: widget.scrollController,
              physics: const ClampingScrollPhysics(), // 优化滚动性能
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
              physics: const ClampingScrollPhysics(), // 优化滚动性能
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
                      isSystemAutoSelected: isSystemAutoSelected,
                    );
                  }),
                ),
              ],
            ),
    );
  }
}

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
  @override
  void initState() {
    super.initState();
    FocusManager.addFocusListeners(
      widget.startIndex,
      widget.channels.length,
      this,
      scrollController: widget.scrollController,
      viewPortHeight: (context.findAncestorStateOfType<_ChannelDrawerPageState>() as _ChannelDrawerPageState)._viewPortHeight,
      listType: "channel", // 指定为频道列表
    );
  }

  @override
  void didUpdateWidget(covariant ChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFocusListenersIfDataChanged(
      oldWidget,
      widget,
      this,
      widget.channels.entries.toList(),
      oldWidget.channels.entries.toList(),
      widget.startIndex,
      widget.scrollController,
      (context.findAncestorStateOfType<_ChannelDrawerPageState>() as _ChannelDrawerPageState)._viewPortHeight,
      "channel", // 指定为频道列表
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    if (channelList.isEmpty) {
      return const SizedBox.shrink();
    }

    bool isSystemAutoSelected = false;

    return Container(
      decoration: BoxDecoration(gradient: defaultBackgroundColor),
      child: ListView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(), // 优化滚动性能
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
                  isSelected: !isSystemAutoSelected && isSelect,
                  onTap: () => widget.onChannelTap(widget.channels[channelName]),
                  isCentered: false,
                  minHeight: defaultMinHeight,
                  isTV: widget.isTV,
                  context: context,
                  index: widget.startIndex + index,
                  isLastItem: index == channelList.length - 1,
                  isSystemAutoSelected: isSystemAutoSelected,
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
  final ScrollController epgScrollController; // 修改为 ScrollController
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
            child: ListView.builder(
              controller: widget.epgScrollController,
              physics: const ClampingScrollPhysics(),
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

class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final bool isLandscape;
  final Function(PlayModel? newModel)? onTapChannel;
  final VoidCallback onCloseDrawer;
  final Function(TvKeyNavigationState state)? onTvKeyNavigationStateCreated;
  final Key? refreshKey;
  final VoidCallback? onSwitchToFavorites; // 新增：切换到收藏的回调

  const ChannelDrawerPage({
    super.key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
    required this.onCloseDrawer,
    this.onTvKeyNavigationStateCreated,
    this.refreshKey,
    this.onSwitchToFavorites, // 新增参数
  });

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  // 使用 LinkedHashMap 实现容量限制的 epgCache
  final LinkedHashMap<String, Map<String, dynamic>> epgCache = LinkedHashMap<String, Map<String, dynamic>>(
    equals: (a, b) => a == b,
    keyHashCode: (key) => key.hashCode,
    onEvict: (key, value) => LogUtil.d('EPG缓存移除: $key'),
    maximumSize: epgCacheSize,
  );

  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  final ScrollController _epgScrollController = ScrollController(); // 修改为 ScrollController
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

  // 排序缓存和地理位置记录
  Map<String, List<String>> _sortedKeysCache = {};
  Map<String, List<Map<String, PlayModel>>> _sortedValuesCache = {};
  String? _lastLocationStr; // 记录上次排序时的地理位置

  Timer? _epgDebounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        _viewPortHeight = MediaQuery.of(context).size.height * 0.5;
      });
      _initializeData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _adjustScrollPositions();
      });
    });
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoMap != oldWidget.videoMap) {
      // 数据源变化时重置缓存并重新排序
      _sortedKeysCache.clear();
      _sortedValuesCache.clear();
      _lastLocationStr = null;
      _initializeData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        }
        _reInitializeFocusListeners();
      });
    }
    // 修改部分：移除复杂的 refreshKey 处理逻辑，仅在必要时更新数据
    else if (widget.refreshKey != oldWidget.refreshKey) {
      _initializeChannelData(); // 仅更新当前分类数据，不强制切换
    }
  }

  /// 新增方法：外部调用以切换分类
  void switchToCategory(String categoryKey) {
    final index = _categories.indexOf(categoryKey);
    if (xAI != -1 && index != _categoryIndex) {
      setState(() {
        _categoryIndex = index;
        _initializeChannelData(); // 使用最新的 widget.videoMap 更新数据
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: _categoryIndex);
        }
        _reInitializeFocusListeners();
        ScrollUtil.scrollToCurrentItem(
          groupIndex: _groupIndex,
          channelIndex: _channelIndex,
          groupController: _scrollController,
          channelController: _scrollChannelController,
          viewPortHeight: _viewPortHeight!,
          isSwitching: true,
        );
      });
    }
  }

  /// 初始化数据，确保调用顺序安全
  void _initializeData() {
    _categories = []; // 先初始化，避免空指针
    _keys = [];
    _values = [];
    _initializeCategoryData();
    _initializeChannelData();
    _initializeFocusNodes();
    _loadInitialEpgData();
  }

  /// 初始化焦点节点
  void _initializeFocusNodes() {
    int totalFocusNodes = _calculateTotalFocusNodes();
    FocusManager.initializeFocusNodes(totalFocusNodes);
  }

  /// 加载初始 EPG 数据
  void _loadInitialEpgData() {
    if (_shouldLoadEpg()) {
      _loadEPGMsg(widget.playModel);
    }
  }

  int _calculateTotalFocusNodes() {
    int totalFocusNodes = _categories.length;
    if (_categoryIndex >= 0 && _categoryIndex < _categories.length) {
      if (_keys.isNotEmpty) {
        totalFocusNodes += _keys.length;
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

  bool _shouldLoadEpg() {
    return _keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty;
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
    if (_epgScrollController.hasClients) { // 添加清理
      _epgScrollController.dispose();
    }
    FocusManager.dispose();
    _tvKeyNavigationState?.releaseResources();
    // 添加过期清理机制
    epgCache.removeWhere((key, value) =>
        DateTime.now().difference(value['timestamp']).inDays > 1);
    _epgDebounceTimer?.cancel(); // 确保防抖定时器被清理
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
        _updateStartIndexes(includeGroupsAndChannels: _keys.isNotEmpty && _values.isNotEmpty);
      });
    }
  }

  void _handleTvKeyNavigationStateCreated(TvKeyNavigationState state) {
    _tvKeyNavigationState = state;
    widget.onTvKeyNavigationStateCreated?.call(state);
  }

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

  void _initializeChannelData() {
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _keys = categoryMap?.keys.toList() ?? [];
    _values = categoryMap?.values.toList() ?? [];

    // 检查是否已有排序缓存
    if (_sortedKeysCache.containsKey(selectedCategory) &&
        _sortedValuesCache.containsKey(selectedCategory)) {
      _keys = List.from(_sortedKeysCache[selectedCategory]!);
      _values = List.from(_sortedValuesCache[selectedCategory]!);
      LogUtil.d('使用缓存排序结果: $selectedCategory');
    } else {
      _sortByLocation();
      _sortedKeysCache[selectedCategory] = List.from(_keys);
      _sortedValuesCache[selectedCategory] = List.from(_values);
    }

    _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

    _isSystemAutoSelected = _groupIndex == -1 || _channelIndex == -1;
    _isChannelAutoSelected = _groupIndex == -1 || _channelIndex == -1;

    if (_groupIndex == -1) _groupIndex = 0;
    if (_channelIndex == -1) _channelIndex = 0;
  }

  /// 通用的地理位置前缀排序方法
  List<T> _sortByGeoPrefix<T>({
    required List<T> items,
    required String? prefix,
    required String Function(T) getName,
  }) {
    if (prefix == null || prefix.isEmpty) return items;

    List<T> matchedItems = [];
    List<T> otherItems = [];

    for (T item in items) {
      String name = getName(item);
      if (name.contains(prefix)) {
        matchedItems.add(item);
      } else {
        otherItems.add(item);
      }
    }

    return [...matchedItems, ...otherItems];
  }

  /// 根据用户位置排序分组和频道，仅在无缓存时调用
  void _sortByLocation() {
    const String locationKey = 'user_all_info';
    // 获取存储的地理信息
    String? locationStr = SpUtil.getString(locationKey);
    LogUtil.i('开始频道排序逻辑, locationStr: $locationStr');
    if (locationStr == null || locationStr.isEmpty) {
      LogUtil.i('未找到地理信息，跳过排序');
      return;
    }

    // 检查地理位置是否变化
    if (_lastLocationStr == locationStr) {
      LogUtil.d('地理位置未变化，跳过排序');
      return;
    }
    _lastLocationStr = locationStr;

    // 解析 JSON 数据
    String? regionPrefix;
    String? cityPrefix;
    try {
      Map<String, dynamic> cacheData = jsonDecode(locationStr);
      Map<String, dynamic>? locationData = cacheData['info']?['location']; // 提取 location
      String? region = locationData?['region']; // 提取 region 字段
      String? city = locationData?['city'];     // 提取 city 字段
      if (region != null && region.isNotEmpty) {
        regionPrefix = region.length >= 2 ? region.substring(0, 2) : region; // 取地区前两个字符
      }
      if (city != null && city.isNotEmpty) {
        cityPrefix = city.length >= 2 ? city.substring(0, 2) : city;         // 取城市前两个字符
      }
    } catch (e) {
      LogUtil.e('解析地理信息 JSON 失败: $e');
      return;
    }

    // 如果没有有效的地区或城市信息，则不排序
    if ((regionPrefix == null || regionPrefix.isEmpty) && (cityPrefix == null || cityPrefix.isEmpty)) {
      LogUtil.i('地理信息中未找到地区或城市，跳过排序');
      return;
    }

    // 1. 对分组（_keys）排序，优先使用 regionPrefix
    _keys = _sortByGeoPrefix<String>(
      items: _keys,
      prefix: regionPrefix,
      getName: (key) => key,
    );

    // 更新 _values 以匹配新的 _keys 顺序
    List<Map<String, PlayModel>> newValues = [];
    for (String key in _keys) {
      int oldIndex = widget.videoMap?.playList[_categories[_categoryIndex]]?.keys.toList().indexOf(key) ?? -1;
      if (oldIndex != -1) {
        Map<String, PlayModel> channelMap = _values[oldIndex];
        // 2. 对每个分组内的频道排序，优先使用 cityPrefix
        List<String> sortedChannelKeys = _sortByGeoPrefix<String>(
          items: channelMap.keys.toList(),
          prefix: cityPrefix,
          getName: (key) => key,
        );
        // 根据排序后的键重新构建频道映射
        Map<String, PlayModel> sortedChannels = {
          for (String channelKey in sortedChannelKeys) channelKey: channelMap[channelKey]!
        };
        newValues.add(sortedChannels);
      } else {
        LogUtil.e('位置排序时未找到键: $key');
      }
    }
    _values = newValues;

    // 记录排序结果以便调试
    LogUtil.i('根据地区 "$regionPrefix" 和城市 "$cityPrefix" 排序完成: $_keys');
  }

  void _resetChannelData() {
    _keys = [];
    _values = [];
    _groupIndex = -1;
    _channelIndex = -1;
    _selEPGIndex = 0;
  }

  void _reInitializeFocusListeners() {
    // 清理所有旧监听器
    for (var node in FocusManager.getFocusNodes()) {
      node.removeListener(() {});
    }
    FocusManager.addFocusListeners(
      0,
      _categories.length,
      this,
      listType: "category",
    );
    if (_keys.isNotEmpty) {
      FocusManager.addFocusListeners(
        _categories.length,
        _keys.length,
        this,
        scrollController: _scrollController,
        viewPortHeight: _viewPortHeight,
        listType: "group",
      );
      if (_values.isNotEmpty && _groupIndex >= 0) {
        FocusManager.addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          this,
          scrollController: _scrollChannelController,
          viewPortHeight: _viewPortHeight,
          listType: "channel",
        );
      }
    }
  }

  void _onCategoryTap(int index) {
    if (_categoryIndex == index) return;
    if (index < 0 || index >= _categories.length) {
      LogUtil.e('分类索引越界: index=$index, max=${_categories.length}');
      return;
    }
    setState(() {
      _categoryIndex = index;
      final selectedCategory = _categories[_categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];
      if (categoryMap == null || categoryMap.isEmpty) {
        _resetChannelData();
        _isSystemAutoSelected = true;
        FocusManager.initializeFocusNodes(_categories.length); // 调整节点数量
        _updateStartIndexes(includeGroupsAndChannels: false);
      } else {
        _initializeChannelData();
        int totalFocusNodes = _categories.length;
        if (_keys.isNotEmpty) {
          totalFocusNodes += _keys.length;
          if (_groupIndex >= 0 && _groupIndex < _values.length && _values[_groupIndex].isNotEmpty) {
            totalFocusNodes += _values[_groupIndex].length;
          }
        }
        FocusManager.initializeFocusNodes(totalFocusNodes); // 调整节点数量
        _updateStartIndexes(includeGroupsAndChannels: true);

        if (widget.playModel?.title == null || !_values[_groupIndex].containsKey(widget.playModel?.title)) {
          _isSystemAutoSelected = true;
          _groupIndex = 0; // 重置到分组第一项
          _channelIndex = 0; // 重置到频道第一项
          ScrollUtil.scrollToTop(_scrollController);
          ScrollUtil.scrollToTop(_scrollChannelController);
        } else {
          _isSystemAutoSelected = false;
          WidgetsBinding.instance.addPostFrame splendidCallback((_) {
            ScrollUtil.scrollToCurrentItem(
              groupIndex: _groupIndex,
              channelIndex: _channelIndex,
              groupController: _scrollController,
              channelController: _scrollChannelController,
              viewPortHeight: _viewPortHeight!,
              isSwitching: true, // 切换场景
            );
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: index);
      }
      _reInitializeFocusListeners();
    });
  }

  void _onGroupTap(int index) {
    if (index < 0 || index >= _keys.length) {
      LogUtil.e('分组索引越界: index=$index, max=${_keys.length}');
      return;
    }
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;

      int totalFocusNodes = _categories.length + (_keys.isNotEmpty ? _keys.length : 0);
      if (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        totalFocusNodes += _values[_groupIndex].length;
      }
      FocusManager.initializeFocusNodes(totalFocusNodes); // 调整节点数量
      _updateStartIndexes(includeGroupsAndChannels: true);

      if (widget.playModel?.group == _keys[index]) {
        _channelIndex = _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');
        if (_channelIndex == -1) {
          _channelIndex = 0;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScrollUtil.scrollToCurrentItem(
            channelIndex: _channelIndex,
            channelController: _scrollChannelController,
            viewPortHeight: _viewPortHeight!,
            isSwitching: true, // 切换场景
          );
        });
      } else {
        _channelIndex = 0;
        _isChannelAutoSelected = true;
        ScrollUtil.scrollToTop(_scrollChannelController);
        // 分组列表保持当前位置，不滚动
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      int firstChannelFocusIndex = _categories.length + _keys.length + _channelIndex;
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      }
      _reInitializeFocusListeners();
    });
  }

  void _adjustScrollPositions({int? groupIndex, int? channelIndex, int retryCount = 0, int maxRetries = 5}) {
    if (retryCount >= maxRetries) {
      LogUtil.i('调整滚动位置达到最大重试次数，停止尝试');
      return;
    }
    if (_viewPortHeight == null || !_scrollController.hasClients || !_scrollChannelController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _adjustScrollPositions(
            groupIndex: groupIndex,
            channelIndex: channelIndex,
            retryCount: retryCount + 1,
            maxRetries: maxRetries,
          ));
      return;
    }
    ScrollUtil.scrollToCurrentItem(
      groupIndex: groupIndex ?? _groupIndex,
      channelIndex: channelIndex ?? _channelIndex,
      groupController: _scrollController,
      channelController: _scrollChannelController,
      viewPortHeight: _viewPortHeight!,
      isSwitching: true, // 初始化时视为切换场景
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;

    int currentFocusIndex = 0;

    Widget categoryListWidget = CategoryList(
      categories: _categories,
      selectedCategoryIndex: _categoryIndex,
      onCategoryTap: _onCategoryTap,
      isTV: useFocusNavigation,
      startIndex: currentFocusIndex,
    );
    currentFocusIndex += _categories.length;

    Widget? groupListWidget;
    Widget? channelListWidget;
    Widget? epgListWidget;

    groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
      onGroupTap: _onGroupTap,
      isTV: useFocusNavigation,
      scrollController: _scrollController,
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,
    );

    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length;
        channelListWidget = ChannelList(
          channels: _values[_groupIndex],
          selectedChannelName: _values[_groupIndex].keys.toList()[_channelIndex],
          onChannelTap: _onChannelTap,
          isTV: useFocusNavigation,
          scrollController: _scrollChannelController,
          startIndex: currentFocusIndex,
        );

        epgListWidget = EPGList(
          epgData: _epgData,
          selectedIndex: _selEPGIndex,
          isTV: useFocusNavigation,
          epgScrollController: _epgScrollController, // 使用新的 ScrollController
          onCloseDrawer: widget.onCloseDrawer,
        );
      }
    }

    if (useFocusNavigation) {
      return TvKeyNavigation(
        focusNodes: _ensureCorrectFocusNodes(),
        cacheName: 'ChannelDrawerPage',
        isVerticalGroup: true,
        initialIndex: 0,
        onStateCreated: _handleTvKeyNavigationStateCreated,
        child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),
      );
    } else {
      return _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget);
    }
  }

  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;
    if (newModel == null || newModel.title == null) {
      LogUtil.e('频道切换失败: newModel 或 title 为空');
      return;
    }
    _isSystemAutoSelected = false;
    _isChannelAutoSelected = false;

    widget.onTapChannel?.call(newModel);

    setState(() {
      _channelIndex = _values[_groupIndex].keys.toList().indexOf(newModel.title ?? '');
      if (_channelIndex == -1) {
        LogUtil.e('未找到频道索引: title=${newModel.title}');
        _channelIndex = 0;
      }
      _epgData = null;
      _selEPGIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _epgDebounceTimer?.cancel();
      _epgDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        _loadEPGMsg(newModel, channelKey: newModel.title ?? '');
      });
    });
  }

  void _updateStartIndexes({bool includeGroupsAndChannels = true}) {
    int categoryStartIndex = 0;
    int groupStartIndex = categoryStartIndex + _categories.length;
    int channelStartIndex = includeGroupsAndChannels && _keys.isNotEmpty
        ? groupStartIndex + _keys.length
        : groupStartIndex; // 当不包括组和频道时，避免错误的偏移

    _categoryStartIndex = categoryStartIndex;
    _groupStartIndex = groupStartIndex;
    _channelStartIndex = channelStartIndex;
  }

  /// 加载 EPG 数据，缓存按天检查有效性
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    if (isPortrait || playModel == null || channelKey == null || channelKey.isEmpty) {
      LogUtil.e('加载 EPG 失败: 参数无效');
      return;
    }
    try {
      final currentTime = DateTime.now();
      // 检查缓存是否存在且日期相同（当日有效）
      if (epgCache.containsKey(channelKey) &&
          epgCache[channelKey]!['timestamp'].day == currentTime.day) {
        setState(() {
          _epgData = epgCache[channelKey]!['data'];
          _selEPGIndex = _getInitialSelectedIndex(_epgData);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_epgData!.isNotEmpty) {
            ScrollUtil.scrollToCurrentItem(
              channelIndex: _selEPGIndex,
              channelController: _epgScrollController,
              viewPortHeight: _viewPortHeight!,
              isSwitching: true, // 视为切换场景
            );
          }
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
      // 单线程访问缓存，避免并发问题
      epgCache[channelKey] = {
        'data': res.epgData!,
        'timestamp': currentTime,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_epgData!.isNotEmpty) {
          ScrollUtil.scrollToCurrentItem(
            channelIndex: _selEPGIndex,
            channelController: _epgScrollController,
            viewPortHeight: _viewPortHeight!,
            isSwitching: true, // 视为切换场景
          );
        }
      });
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

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

  List<FocusNode> _ensureCorrectFocusNodes() {
    int totalNodesExpected = _categories.length +
        (_keys.isNotEmpty ? _keys.length : 0) +
        (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);
    if (FocusManager.getFocusNodes().length != totalNodesExpected) {
      FocusManager.initializeFocusNodes(totalNodesExpected);
    }
    return FocusManager.getFocusNodes();
  }

  Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
    double categoryWidth = isPortrait ? categoryWidthPortrait : categoryWidthLandscape;
    double groupWidth = groupListWidget != null ? (isPortrait ? groupWidthPortrait : groupWidthLandscape) : 0;

    double channelListWidth = (groupListWidget != null && channelListWidget != null)
        ? (isPortrait ? MediaQuery.of(context).size.width - categoryWidth - groupWidth : channelWidthLandscape)
        : 0;

    double epgListWidth = (groupListWidget != null && channelListWidget != null && epgListWidget != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth
        : 0;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape ? categoryWidth + groupWidth + channelListWidth + epgListWidth : MediaQuery.of(context).size.width,
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

// 容量限制
class LinkedHashMap<K, V> extends MapBase<K, V> {
  final Map<K, V> _map = {};
  final int maximumSize;
  final bool Function(K, K) equals;
  final int Function(K) keyHashCode;
  final void Function(K, V)? onEvict;

  LinkedHashMap({
    required this.equals,
    required this.keyHashCode,
    this.onEvict,
    this.maximumSize = defaultCacheSize,
  });

  @override
  V? operator [](Object? key) => _map.containsKey(key) ? _map[key as K] : null;

  @override
  void operator []=(K key, V value) {
    if (_map.length >= maximumSize && !_map.containsKey(key)) {
      final firstKey = _map.keys.first;
      final removedValue = _map.remove(firstKey);
      onEvict?.call(firstKey, removedValue!);
    }
    _map[key] = value;
  }

  @override
  void clear() => _map.clear();

  @override
  Iterable<K> get keys => _map.keys;

  @override
  V? remove(Object? key) => _map.remove(key);

  @override
  bool containsKey(Object? key) => _map.containsKey(key);

  @override
  int get hashCode => _map.hashCode;
}
