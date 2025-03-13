import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:collection/collection.dart'; 
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

//是否在非TV 模式下启用 TV 模式的焦点逻辑（用于调试）
const bool enableFocusInNonTVMode = true; //默认关闭

// 分割线样式
final verticalDivider = Container(
  width: 1.5, //加粗
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
const double categoryWidthPortrait = 110.0; //竖屏分类宽度
const double categoryWidthLandscape = 120.0; // 横屏分类宽度
const double groupWidthPortrait = 120.0; // 竖屏分组宽度
const double groupWidthLandscape = 130.0; // 横屏分组宽度
const double channelWidthLandscape = 160.0; // 横屏频道宽度

// 缓存大小常量
const int defaultCacheSize = 50; // 默认 LinkedHashMap 最大容量
const int epgCacheSize = 30; // EPG 缓存最大容量

LinearGradient? getGradientForDecoration({
  required bool isTV,
  required bool hasFocus,required bool isSelected,
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
  // 添加监听器映射表，用于正确移除监听器
  static Map<int, VoidCallback> _listenerMap = {};

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
          // 正确移除监听器
          removeFocusListener(i);
          _focusNodes[i].dispose();
        }_focusNodes = _focusNodes.sublist(0, totalCount);
      } else {
        // 增加节点：追加新节点
        _focusNodes.addAll(
          List.generate(totalCount - _focusNodes.length, (_) => FocusNode()),
        );
      }
      LogUtil.d('调整焦点节点数量:  $ {_focusNodes.length} ->  $ totalCount');
    }
    // 验证焦点节点状态一致性
    _validateFocusNodes();
  }
  
  /// 验证焦点节点状态一致性
  static void _validateFocusNodes() {
    // 移除超出范围的监听器
    Set<int> invalidKeys = _listenerMap.keys.where((key) => key >= _focusNodes.length || key < 0).toSet();
    for (int key in invalidKeys) {
      _listenerMap.remove(key);
    }
    
    // 检查是否有节点已被处置但仍在列表中
    for (int i = 0; i < _focusNodes.length; i++) {
      if (_focusNodes[i].debugLabel =='DISPOSED') {
        LogUtil.e('发现已处置的焦点节点在索引: $i');
        _focusNodes[i] = FocusNode(); // 替换已处置的节点
      }
    }}

  /// 移除特定索引的焦点监听器
  static void removeFocusListener(int index) {
    if (index < 0 || index >= _focusNodes.length) {
      return;
    }
    if (_listenerMap.containsKey(index)) {
      _focusNodes[index].removeListener(_listenerMap[index]!);
      _listenerMap.remove(index);
    }
  }
  
  /// 移除指定范围的焦点监听器
  static void removeFocusListeners(int startIndex, int length) {
    if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
      return;
    }
    
    for (var i = 0; i < length; i++) {
      removeFocusListener(startIndex + i);
    }
  }

  /// 添加焦点监听器，确保只绑定一次并支持滚动
  static void addFocusListeners(
    int startIndex,
    int length,
    State state, {
    ScrollController? scrollController,
    ScrollController? groupController, // 新增：明确指定分组控制器
    ScrollController? channelController, // 新增：明确指定频道控制器double? viewPortHeight,
    required String listType, // 新增：区分列表类型}) {
    if (startIndex < 0 || length <= 0 || startIndex + length > _focusNodes.length) {
      LogUtil.e('焦点监听器索引越界: startIndex= $ startIndex, length= $ length, total=${_focusNodes.length}');
      return;
    }

    // 添加日志记录所有节点索引范围
    LogUtil.d('绑定焦点监听器: listType= $ listType, startIndex= $ startIndex, endIndex= $ {startIndex + length - 1}, totalNodes= $ {_focusNodes.length}');

    // 先移除该范围内的旧监听器
    removeFocusListeners(startIndex, length);
    
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      
      // 创建监听器并保存引用
      VoidCallback listener = () {
        if (state.mounted && _focusNodes[index].hasFocus) {
          LogUtil.d('焦点变化: 索引= $ index, listType= $ listType');
          // 使用安全的状态更新
          if (state.mounted) {
            state.setState(() {});
          }
          // 添加空值检查和类型区分
          if (scrollController != null && viewPortHeight != null && viewPortHeight > 0) {
            final itemIndex = index - startIndex;
            // 使用listType进行滚动判断，不依赖控制器比较
            if (listType == "group") {
              LogUtil.d('触发分组列表滚动: groupIndex=$itemIndex');
              ScrollUtil.scrollToCurrentItem(
                groupIndex: itemIndex,
                groupController: scrollController,
                viewPortHeight: viewPortHeight,
                isSwitching: false,
              );
            } else if (listType == "channel") {
              LogUtil.d('触发频道列表滚动: channelIndex=$itemIndex');
              ScrollUtil.scrollToCurrentItem(
                channelIndex: itemIndex,
                channelController: scrollController,
                viewPortHeight: viewPortHeight,
                isSwitching: false,
              );
            }//分类列表不滚动
          }
        }
      };
      
      // 保存监听器引用并添加
      _listenerMap[index] = listener;_focusNodes[index].addListener(listener);
    }
  }

  static List<FocusNode> getFocusNodes() => _focusNodes;

  /// 清理所有焦点节点，释放资源
  static void dispose() {
    // 正确移除所有监听器
    _listenerMap.forEach((index, listener) {
      if (index < _focusNodes.length) {
        _focusNodes[index].removeListener(listener);}
    });
    _listenerMap.clear();
    
    for (var node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
  }/// 检查焦点节点状态是否健康
  static bool isHealthy() {
    return _focusNodes.every((node) => node.debugLabel != 'DISPOSED');
  }
  
  /// 获取当前活动焦点节点索引
  static int? getActiveFocusIndex() {
    for (int i = 0; i < _focusNodes.length; i++) {
      if (_focusNodes[i].hasFocus) {
        return i;
      }
    }
    return null;
  }
}

//滚动工具类
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
    double topOffset = defaultTopOffset, // 默认112.0
    bool isSwitching = false, // 是否为切换分类/分组场景
  }) {
    LogUtil.d('滚动调用: groupIndex= $ groupIndex, channelIndex= $ channelIndex, isSwitching=$isSwitching');
    const itemHeight = defaultMinHeight;

    //仅滚动分组列表
    if (groupController != null && groupIndex != null && groupController.hasClients) {
      final maxScrollExtent = groupController.position.maxScrollExtent;
      double targetOffset;

      if (isSwitching) {
        // 切换场景：滚动到顶部偏移 112.0
        targetOffset = (groupIndex * itemHeight - topOffset).clamp(0.0, maxScrollExtent);
      } else {
        // 焦点移动场景
        final currentOffset = groupController.offset;
        final itemTop = groupIndex * itemHeight;
        final itemBottom = (groupIndex + 1) * itemHeight;
        if (itemTop < currentOffset) {
          // 超出顶部，顶部对齐
          targetOffset = itemTop.clamp(0.0, maxScrollExtent);
        } else if (itemBottom > currentOffset + viewPortHeight) {
          // 超出底部，底部对齐
          targetOffset = (itemBottom - viewPortHeight).clamp(0.0, maxScrollExtent);
        } else {
          // 未超出视窗，不滚动
          return;
        }
      }
      LogUtil.d('滚动分组列表到: $targetOffset');
      groupController.jumpTo(targetOffset);
    }

    // 仅滚动频道列表
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
          targetOffset = itemTop.clamp(0.0, maxScrollExtent);
        } else if (itemBottom > currentOffset + viewPortHeight) {
          targetOffset = (itemBottom - viewPortHeight).clamp(0.0, maxScrollExtent);
        } else {
          return;
        }
      }
      LogUtil.d('滚动频道列表到: $targetOffset');
      channelController.jumpTo(targetOffset);
    }
  }
}

///构建通用列表项
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,required bool isCentered,
  double minHeight = defaultMinHeight,
  EdgeInsets padding = defaultPadding,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
  bool isLastItem = false,
  bool isSystemAutoSelected = false,
}) {
  // 添加索引越界检查
  FocusNode? focusNode;
  if (index != null && index >= 0) {
    final nodes = FocusManager.getFocusNodes();
    if (index < nodes.length) {
      focusNode = nodes[index];
    } else {
      LogUtil.e('列表项索引越界:  $ index, 最大:  $ {nodes.length - 1}');
    }
  }

  final hasFocus = focusNode?.hasFocus ?? false;

  //缓存合并后的文本样式
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
        //优化重绘逻辑，仅在需要时触发
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

// 更新比较函数，使用内容比较而非引用比较
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
  // 使用ListEquality进行内容比较
  bool hasChanged = newData.length != oldData.length || !const ListEquality().equals(newData, oldData);
  if (hasChanged) {
    FocusManager.addFocusListeners(
      startIndex,
      newData.length,
      state,
      scrollController: scrollController,
      viewPortHeight: viewPortHeight,
      listType: listType, // 传递listType
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
    // 延迟到下一帧再绑定焦点监听器，确保布局已完成WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusManager.addFocusListeners(
          widget.startIndex,
          widget.categories.length,
          this,
          listType: "category", // 指定为分类列表
        );
      }
    });
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
    // 确保移除当前组件的所有监听器
    FocusManager.removeFocusListeners(widget.startIndex, widget.categories.length);
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
  double? _viewPortHeight;
  @override
  void initState() {
    super.initState();
    // 延迟到didChangeDependencies初始化视口高度和焦点监听}
  
  // 在didChangeDependencies中安全访问父组件状态
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeViewPortHeight();// 仅在非空时绑定焦点监听器
    if (widget.keys.isNotEmpty) {
      FocusManager.addFocusListeners(
        widget.startIndex,
        widget.keys.length,
        this,
        scrollController: widget.scrollController,
        groupController: widget.scrollController, // 指定分组控制器
        viewPortHeight: _viewPortHeight,listType: "group", // 指定为分组列表
      );
    }
  }
  
  // 安全地获取父级视口高度
  void _initializeViewPortHeight() {
    final parentState = context.findAncestorStateOfType<_ChannelDrawerPageState>();
    if (parentState != null) {
      _viewPortHeight = parentState._viewPortHeight ??MediaQuery.of(context).size.height * 0.5;
    } else {
      _viewPortHeight = MediaQuery.of(context).size.height * 0.5;
    }
  }

  @override
  void didUpdateWidget(covariant GroupList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据变化时，仅在非空时更新焦点监听器，使用内容比较
    bool keysChanged = widget.keys.length != oldWidget.keys.length ||
        !const ListEquality().equals(widget.keys, oldWidget.keys);
    if (keysChanged) {
      if (widget.keys.isNotEmpty) {
        _initializeViewPortHeight(); // 更新视口高度
        FocusManager.addFocusListeners(
          widget.startIndex,
          widget.keys.length,
          this,
          scrollController: widget.scrollController,
          groupController: widget.scrollController,
          viewPortHeight: _viewPortHeight,
          listType: "group",
        );
      }
    }
  }

  @override
  void dispose() {
    // 确保移除当前组件的所有监听器
    FocusManager.removeFocusListeners(widget.startIndex, widget.keys.length);
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
                      isTV: widget.isTV,minHeight: defaultMinHeight,
                      context: context,index: widget.startIndex + index,
                      isLastItem: index == widget.keys.length - 1,isSystemAutoSelected: isSystemAutoSelected,
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
  double? _viewPortHeight;
  @override
  void initState() {
    super.initState();
    // 延迟到didChangeDependencies初始化视口高度和焦点监听}
  
  // 在didChangeDependencies中安全访问父组件状态
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeViewPortHeight();
    FocusManager.addFocusListeners(
      widget.startIndex,
      widget.channels.length,
      this,
      scrollController: widget.scrollController,
      channelController: widget.scrollController, // 指定频道控制器
      viewPortHeight: _viewPortHeight,
      listType: "channel", // 指定为频道列表
    );
  }
  
  // 安全地获取父级视口高度
  void _initializeViewPortHeight() {
    final parentState = context.findAncestorStateOfType<_ChannelDrawerPageState>();
    if (parentState != null) {
      _viewPortHeight = parentState._viewPortHeight ??
          MediaQuery.of(context).size.height * 0.5;
    } else {
      _viewPortHeight = MediaQuery.of(context).size.height * 0.5;
    }
  }

  @override
  void didUpdateWidget(covariant ChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 使用MapEquality进行内容比较
    bool channelsChanged = widget.channels.length != oldWidget.channels.length ||
        !const MapEquality().equals(widget.channels, oldWidget.channels);
    if (channelsChanged) {
      _initializeViewPortHeight(); // 更新视口高度
      FocusManager.addFocusListeners(
        widget.startIndex,
        widget.channels.length,
        this,
        scrollController: widget.scrollController,
        channelController: widget.scrollController,
        viewPortHeight: _viewPortHeight,
        listType: "channel",
      );
    }
  }

  @override
  void dispose() {
    // 确保移除当前组件的所有监听器
    FocusManager.removeFocusListeners(widget.startIndex, widget.channels.length);
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
                  isLastItem: index == channelList.length - 1,isSystemAutoSelected: isSystemAutoSelected,
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
  final ScrollController epgScrollController; // 修改为ScrollController
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
                ],),
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
          verticalDivider,Flexible(
            child: ListView.builder(
              controller: widget.epgScrollController,
              physics: const ClampingScrollPhysics(),
              itemCount: widget.epgData?.length ?? 0,
              itemBuilder: (BuildContext context, int index) {
                final data = widget.epgData?[index];
                if (data == null) return const SizedBox.shrink();
                final isSelect = index == widget.selectedIndex;
                return buildListItem(
                  title: ' $ {data.start}- $ {data.end}\n${data.title}',
                  isSelected: isSelect,
                  onTap: () {
                    widget.onCloseDrawer();},
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

class _ChannelDrawerPageState extends State<ChannelDrawerPage> withWidgetsBindingObserver {
  // 使用 LinkedHashMap 实现容量限制的epgCache
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
  // 添加一个标志，表示组件是否已挂载
  bool _isComponentMounted = false;

  @override
  void initState() {
    super.initState();
    _isComponentMounted = true; // 设置初始挂载状态WidgetsBinding.instance.addObserver(this);
    // 使用安全的异步初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        _viewPortHeight = MediaQuery.of(context).size.height * 0.5;
      });_initializeData();
      
      // 添加额外的检查，确保在数据初始化后调整滚动位置
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _adjustScrollPositions();
      });
    });
  }

  @override
  void didUpdateWidget(ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoMap != oldWidget.videoMap) {
      //数据源变化时重置缓存并重新排序
      _sortedKeysCache.clear();
      _sortedValuesCache.clear();
      _lastLocationStr = null;
      _initializeData();
      // 在异步操作中添加组件挂载检查
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tvKeyNavigationState != null) {
          _tvKeyNavigationState!.releaseResources();
          // 边界检查，确保分类索引有效
          final safeIndex = _categoryIndex.clamp(0, _categories.length - 1);
          _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: safeIndex);
        }
        _reInitializeFocusListeners();
      });
    } else if (widget.refreshKey != oldWidget.refreshKey) {
    // 收藏变化时，检查是否需要切换到"我的收藏"
      bool isAddingFavorite = widget.refreshKey is ValueKey<int> && (widget.refreshKey as ValueKey<int>).value & 1== 1;
      if (isAddingFavorite && widget.onSwitchToFavorites != null && _categories.contains(Config.myFavoriteKey)) {
        widget.onSwitchToFavorites!(); // 只有添加收藏时切换到"我的收藏"
      } else {
        _initializeChannelData(); // 非切换场景，仅刷新当前分类
        
        // 在异步操作中添加组件挂载检查
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          if (_tvKeyNavigationState != null) {
            _tvKeyNavigationState!.releaseResources();
            // 边界检查，确保分类索引有效
            final safeIndex = _categoryIndex.clamp(0, _categories.length - 1);
            _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: safeIndex);
          }
          _reInitializeFocusListeners();
        });
      }
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
    return _keys.isNotEmpty && _values.isNotEmpty && 
           _groupIndex >= 0 && _groupIndex < _values.length && 
           _values[_groupIndex].isNotEmpty;
  }

  @override
  void dispose() {
    _isComponentMounted = false; // 标记组件已卸载
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
    _tvKeyNavigationState?.releaseResources();
    // 取消定时器和清理EPG缓存
    _epgDebounceTimer?.cancel();
    epgCache.removeWhere((key, value) =>
        DateTime.now().difference(value['timestamp']).inDays > 1);
        
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 添加组件挂载检查
    if (!mounted) return;final newOrientation = MediaQuery.of(context).orientation == Orientation.portrait;
    if (newOrientation != isPortrait) {
      setState(() {
        isPortrait = newOrientation;});
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
    _categories = widget.videoMap?.playList?.keys.toList() ??<String>[];_categoryIndex = -1;_groupIndex = -1;
    _channelIndex = -1;

    // 确保_categories不为空
    if (_categories.isEmpty) {
      return;
    }

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
    
    // 确保索引有效
    _categoryIndex = _categoryIndex >= 0 ? _categoryIndex : 0;}

  void _initializeChannelData() {
    // 添加边界检查
    if (_categories.isEmpty || _categoryIndex < 0|| _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    // 更安全地处理空数据
    if (categoryMap == null) {
      _resetChannelData();
      return;
    }

    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    //检查是否已有排序缓存
    if (_sortedKeysCache.containsKey(selectedCategory) &&
        _sortedValuesCache.containsKey(selectedCategory)) {
      _keys = List.from(_sortedKeysCache[selectedCategory]!);
      _values = List.from(_sortedValuesCache[selectedCategory]!);
      LogUtil.d('使用缓存排序结果: $selectedCategory');
    } else {
      _sortByLocation();
      
      // 添加非空检查
      if (_keys.isNotEmpty) {
        _sortedKeysCache[selectedCategory] = List.from(_keys);
        _sortedValuesCache[selectedCategory] = List.from(_values);
      }
    }

    // 边界检查和安全处理
    if (_keys.isEmpty) {
      _groupIndex = -1;
      _channelIndex = -1;} else {
      _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
      _channelIndex = _groupIndex != -1 && _groupIndex < _values.length
          ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
          : -1;

      _isSystemAutoSelected = _groupIndex == -1 || _channelIndex == -1;
      _isChannelAutoSelected = _groupIndex == -1 || _channelIndex == -1;

      if (_groupIndex == -1) _groupIndex = 0;
      if (_channelIndex == -1) _channelIndex = 0;
    }
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
      String? city = locationData?['city'];// 提取 city 字段
      if (region != null && region.isNotEmpty) {
        regionPrefix = region.length >= 2 ? region.substring(0, 2) : region; // 取地区前两个字符
      }
      if (city != null && city.isNotEmpty) {
        cityPrefix = city.length >= 2 ? city.substring(0, 2) : city;// 取城市前两个字符
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

    // 添加安全检查
    if (_keys.isEmpty) {
      LogUtil.i('分组列表为空，跳过排序');
      return;
    }

    // 1. 对分组（_keys）排序，优先使用 regionPrefix
    _keys = _sortByGeoPrefix<String>(
      items: _keys,
      prefix: regionPrefix,
      getName: (key) => key,
    );

    // 更新 _values 以匹配新的_keys 顺序
    List<Map<String, PlayModel>> newValues = [];
    for (String key in _keys) {
      int oldIndex = widget.videoMap?.playList[_categories[_categoryIndex]]?.keys.toList().indexOf(key) ?? -1;
      if (oldIndex != -1 && oldIndex < _values.length) { // 添加范围检查
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
    LogUtil.i('根据地区" $ regionPrefix" 和城市 " $ cityPrefix" 排序完成: $_keys');
  }

  void _resetChannelData() {
    _keys = [];
    _values = [];_groupIndex = -1;
    _channelIndex = -1;
    _selEPGIndex = 0;
  }

  void _reInitializeFocusListeners() {
    // 先清除所有旧监听器
    FocusManager.dispose();
    FocusManager.initializeFocusNodes(_calculateTotalFocusNodes());
    FocusManager.addFocusListeners(
      0,
      _categories.length,
      this,
      listType: "category",
    );if (_keys.isNotEmpty) {
      FocusManager.addFocusListeners(
        _categories.length,
        _keys.length,
        this,
        scrollController: _scrollController,
        groupController: _scrollController, //指定分组控制器
        viewPortHeight: _viewPortHeight,
        listType: "group",
      );if (_values.isNotEmpty && _groupIndex >= 0&& _groupIndex < _values.length) {
        FocusManager.addFocusListeners(
          _categories.length + _keys.length,
          _values[_groupIndex].length,
          this,
          scrollController: _scrollChannelController,
          channelController: _scrollChannelController, // 指定频道控制器
          viewPortHeight: _viewPortHeight,
          listType: "channel",
        );
      }
    }
  }

  void _onCategoryTap(int index) {
    // 增加边界检查
    if (_categoryIndex == index) return;
    if (index < 0 || index >= _categories.length) {
      LogUtil.e('分类索引越界: index= $ index, max= $ {_categories.length - 1}');
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
          ScrollUtil.scrollToTop(_scrollController);ScrollUtil.scrollToTop(_scrollChannelController);
        } else {
          _isSystemAutoSelected = false;
          // 在异步操作中添加组件挂载检查WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // 安全地处理可能的空值
            if (_viewPortHeight != null && _viewPortHeight! > 0) {
              ScrollUtil.scrollToCurrentItem(
                groupIndex: _groupIndex,
                channelIndex: _channelIndex,
                groupController: _scrollController,
                channelController: _scrollChannelController,
                viewPortHeight: _viewPortHeight!,
                isSwitching: true, // 切换场景
              );
            }
          });
        }
      }
    });

    // 在异步操作中添加组件挂载检查
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();_tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: index);
      }_reInitializeFocusListeners();
    });
  }

  void _onGroupTap(int index) {
    // 增加边界检查
    if (index < 0 || index >= _keys.length) {
      LogUtil.e('分组索引越界: index= $ index, max= $ {_keys.length - 1}');
      return;
    }
    setState(() {
      _groupIndex = index;
      _isSystemAutoSelected = false;

      // 计算正确的节点总数
      int totalFocusNodes = _categories.length + _keys.length;
      if (_groupIndex >= 0 && _groupIndex < _values.length) {
        totalFocusNodes += _values[_groupIndex].length;
      }
      FocusManager.initializeFocusNodes(totalFocusNodes); // 调整节点数量
      _updateStartIndexes(includeGroupsAndChannels: true);

      if (widget.playModel?.group == _keys[index]) {
        // 安全获取频道索引
        if (_groupIndex >= 0 && _groupIndex < _values.length) {
          _channelIndex = _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '');if (_channelIndex == -1) _channelIndex = 0;
        } else {
          _channelIndex = 0;
        }
        // 在异步操作中添加组件挂载检查
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          // 安全地使用_viewPortHeight
          if (_viewPortHeight != null && _viewPortHeight! > 0) {
            ScrollUtil.scrollToCurrentItem(
              channelIndex: _channelIndex,
              channelController: _scrollChannelController,
              viewPortHeight: _viewPortHeight!,
              isSwitching: true, // 仅在切换分组时滚动频道
            );
          }
        });
      } else {
        _channelIndex = 0;_isChannelAutoSelected = true;
        ScrollUtil.scrollToTop(_scrollChannelController);//分组列表保持当前位置，不滚动}
    });

    // 在异步操作中添加组件挂载检查及安全的索引计算
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // 安全计算频道焦点索引
      int firstChannelFocusIndex;
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        //确保_channelIndex在有效范围内
        int safeChannelIndex = _channelIndex.clamp(0, _values[_groupIndex].length - 1);
        firstChannelFocusIndex = _categories.length + _keys.length + safeChannelIndex;
      } else {
        // 如果没有频道，则焦点保持在分组
        firstChannelFocusIndex = _categories.length + _groupIndex;
      }
      
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState!.releaseResources();
        _tvKeyNavigationState!.initializeFocusLogic(initialIndexOverride: firstChannelFocusIndex);
      }
      _reInitializeFocusListeners();
    });
  }

  void _adjustScrollPositions({int? groupIndex, int? channelIndex, int retryCount = 0, int maxRetries = 5}) {
    // 添加组件挂载检查
    if (!mounted) return;
    
    if (retryCount >= maxRetries) {
      LogUtil.i('调整滚动位置达到最大重试次数，停止尝试');
      return;
    }
    
    // 添加全面的空值检查
    if (_viewPortHeight == null || _viewPortHeight! <= 0 || 
        !_scrollController.hasClients || !_scrollChannelController.hasClients) {
      // 延迟重试
      WidgetsBinding.instance.addPostFrameCallback((_) =>
        _adjustScrollPositions(
          groupIndex: groupIndex,
          channelIndex: channelIndex,
          retryCount: retryCount + 1,
          maxRetries: maxRetries,
        )
      );
      return;
    }
    
    //仅在 _keys 非空时调整滚动
    if (_keys.isNotEmpty) {
      // 使用安全的索引值
      final safeGroupIndex = groupIndex != null ?groupIndex.clamp(0, _keys.length - 1) : 
          _groupIndex.clamp(0, _keys.length - 1);
      
      //频道索引可能在分组切换时不一致，需要额外检查
      int safeChannelIndex = 0;
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        final channelsLength = _values[_groupIndex].length;
        safeChannelIndex = channelIndex != null ? 
            channelIndex.clamp(0, channelsLength - 1) : 
            _channelIndex.clamp(0, channelsLength - 1);
      }ScrollUtil.scrollToCurrentItem(
        groupIndex: safeGroupIndex,
        channelIndex: safeChannelIndex,
        groupController: _scrollController,
        channelController: _scrollChannelController,
        viewPortHeight: _viewPortHeight!,
        isSwitching: true, // 初始化时视为切换场景
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool useFocusNavigation = isTV || enableFocusInNonTVMode;

    // 当没有分类时提供默认值
    if (_categories.isEmpty) {
      return Container(
        decoration: BoxDecoration(gradient: defaultBackgroundColor),
        child: const Center(
          child: Text("无可用频道", style: defaultTextStyle),
        ),
      );
    }

    int currentFocusIndex =0;

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
      isFavoriteCategory: _categoryIndex >= 0 && _categoryIndex < _categories.length &&_categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,
    );

    if (_keys.isNotEmpty) {
      if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
        currentFocusIndex += _keys.length;channelListWidget = ChannelList(
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
          onCloseDrawer: widget.onCloseDrawer,);
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
    // 添加空值检查
    if (newModel?.title == widget.playModel?.title) return;
    if (newModel == null || newModel.title == null) {
      LogUtil.e('频道切换失败: newModel 或 title 为空');
      return;
    }
    _isSystemAutoSelected = false;
    _isChannelAutoSelected = false;

    widget.onTapChannel?.call(newModel);

    setState(() {
      // 安全获取频道索引
      if (_groupIndex >= 0 && _groupIndex < _values.length) {
        _channelIndex = _values[_groupIndex].keys.toList().indexOf(newModel.title ?? '');if (_channelIndex == -1) {
          LogUtil.e('未找到频道索引: title=${newModel.title}');
          _channelIndex = 0;
        }
      } else {
        _channelIndex = 0;
      }_epgData = null;
      _selEPGIndex = 0;
    });

    // 使用组件挂载状态处理异步操作
    _epgDebounceTimer?.cancel();
    _epgDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _loadEPGMsg(newModel, channelKey: newModel.title ?? '');
    });
  }

  void _updateStartIndexes({bool includeGroupsAndChannels = true}) {
    int categoryStartIndex = 0;
    
    // 更精确地计算索引，避免重叠
    int groupStartIndex = categoryStartIndex + _categories.length;
    int channelStartIndex;
    
    if (!includeGroupsAndChannels || _keys.isEmpty) {
      channelStartIndex = groupStartIndex;  // 无分组/频道时的情况
    } else {
      channelStartIndex = groupStartIndex + _keys.length;
    }

    _categoryStartIndex = categoryStartIndex;
    _groupStartIndex = groupStartIndex;
    _channelStartIndex = channelStartIndex;
  }

  /// 加载 EPG 数据，缓存按天检查有效性
  Future<void> _loadEPGMsg(PlayModel? playModel, {String? channelKey}) async {
    // 添加组件挂载检查和参数验证
    if (!mounted || isPortrait || playModel == null || channelKey == null || channelKey.isEmpty) {
      LogUtil.e('加载 EPG 失败: 参数无效或组件已卸载');
      return;
    }
    
    try {
      final currentTime = DateTime.now();
      //检查缓存是否存在且日期相同（当日有效）
      if (epgCache.containsKey(channelKey) &&
          epgCache[channelKey]!['timestamp'].day == currentTime.day) {
        // 在setState前检查组件是否挂载
        if (!mounted) return;
        
        setState(() {
          _epgData = epgCache[channelKey]!['data'];
          _selEPGIndex = _getInitialSelectedIndex(_epgData);
        });
        // 在回调中检查组件是否挂载WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // 添加空值检查
          if (_epgData != null && _epgData!.isNotEmpty && _viewPortHeight != null && _viewPortHeight! > 0) {
            if (_epgScrollController.hasClients) {
              final targetOffset = (_selEPGIndex * defaultMinHeight).clamp(
                0.0,
                _epgScrollController.position.maxScrollExtent
              );
              _epgScrollController.jumpTo(targetOffset);
            }
          }
        });
        return;
      }
      // 从网络加载EPG数据
      final res = await EpgUtil.getEpg(playModel);
      // 添加组件挂载检查和数据验证
      if (!mounted || res?.epgData == null || res!.epgData!.isEmpty) return;

      final selectedIndex = _getInitialSelectedIndex(res.epgData);

      setState(() {
        _epgData = res.epgData!;
        _selEPGIndex = selectedIndex;
      });
      
      //单线程访问缓存，避免并发问题
      epgCache[channelKey] = {
        'data': res.epgData!,
        'timestamp': currentTime,
      };
      
      // 在回调中检查组件是否挂载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        
        // 添加空值检查
        if (_epgData != null && _epgData!.isNotEmpty && 
            _viewPortHeight != null && _viewPortHeight! > 0 &&
            _epgScrollController.hasClients) {
          final targetOffset = (_selEPGIndex * defaultMinHeight).clamp(
            0.0, 
            _epgScrollController.position.maxScrollExtent
          );
          _epgScrollController.jumpTo(targetOffset);
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
      // 添加空值检查
      final start = epgData[i].start;
      if (start != null && start.compareTo(currentTime) < 0) {
        return i;
      }
    }

    return 0;
  }

  List<FocusNode> _ensureCorrectFocusNodes() {
    // 添加完整的边界检查
    int categoriesCount = _categories.length;
    int keysCount = _keys.isNotEmpty ? _keys.length : 0;
    int channelsCount = 0;
    
    if (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length) {
      channelsCount = _values[_groupIndex].length;
    }int totalNodesExpected = categoriesCount + keysCount + channelsCount;
    
    if (FocusManager.getFocusNodes().length != totalNodesExpected) {
      LogUtil.d('重新调整焦点节点数量:  $ {FocusManager.getFocusNodes().length} ->  $ totalNodesExpected');
      FocusManager.initializeFocusNodes(totalNodesExpected);
    }
    
    // 验证节点健康性
    if (!FocusManager.isHealthy()) {
      LogUtil.w('检测到焦点节点不健康，重新初始化');
      FocusManager.initializeFocusNodes(totalNodesExpected);
    }return FocusManager.getFocusNodes();
  }

  Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget? groupListWidget, Widget? channelListWidget, Widget? epgListWidget) {
    double categoryWidth = isPortrait ? categoryWidthPortrait : categoryWidthLandscape;
    double groupWidth = groupListWidget != null ? (isPortrait ? groupWidthPortrait : groupWidthLandscape) : 0;

    double channelListWidth = (groupListWidget != null && channelListWidget != null)? (isPortrait ? MediaQuery.of(context).size.width - categoryWidth - groupWidth : channelWidthLandscape)
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

//容量限制
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
  
  // 添加基于内容的移除方法
  void removeWhere(bool Function(K, V) test) {
    List<K> keysToRemove = [];
    _map.forEach((key, value) {
      if (test(key, value)) {
        keysToRemove.add(key);
      }
    });
    for (K key in keysToRemove) {
      final removedValue = _map.remove(key);
      if (removedValue != null) {
        onEvict?.call(key, removedValue);
      }
    }
  }
}
