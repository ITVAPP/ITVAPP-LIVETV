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

// 最小高度约束
const defaultMinHeight = 42.0;

// 背景色
const defaultBackgroundColor = Colors.black38;

// padding设置
const defaultPadding = EdgeInsets.all(6.0);

// 装饰设置，不使用渐变
const Color selectedColor = Color(0xFFEB144C); // 选中颜色
const Color unselectedColor = Color(0xFFDFA02A); // 焦点颜色

BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    color: isSelected
        ? selectedColor // 选中项颜色
        : (hasFocus ? unselectedColor : Colors.transparent), // 焦点项使用未选中颜色，其他为透明
  );
}

// 用于管理所有 FocusNode 的列表
List<FocusNode> _focusNodes = [];

// 初始化 FocusNode 列表
void _initializeFocusNodes(int totalCount) {
  // 清空并销毁已有的 FocusNodes，避免内存泄漏
  for (final node in _focusNodes) {
    node.dispose();
  }
  _focusNodes.clear();

  // 生成新的 FocusNode 列表
  LogUtil.v('频道抽屉节点数量: $totalCount');
  _focusNodes = List.generate(totalCount, (index) => FocusNode());
}

// 创建或获取已有的 FocusNode
FocusNode getOrCreateFocusNode(int index) {
  if (index >= 0 && index < _focusNodes.length) {
    return _focusNodes[index];
  }
  // 如果索引无效，返回默认FocusNode或者抛出异常
  return FocusNode();
}

// 通用列表项构建函数
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true, // 控制文本是否居中对齐
  double minHeight = defaultMinHeight, // 默认最小高度
  EdgeInsets padding = defaultPadding, // 默认内边距
  bool isTV = false,
  int? index, // index 参数设为可选，用于获取 FocusNode
  bool useFocusableItem = true, // 控制是否使用 FocusableItem 包裹
}) {
  FocusNode? focusNode;

  // 如果 useFocusableItem 为 true，创建 FocusNode
  if (useFocusableItem && index != null) {
    focusNode = getOrCreateFocusNode(index);
  }

  Widget listItemContent = GestureDetector(
    LogUtil.v('GroupList 索引: index = $index');
    onTap: onTap, // 处理点击事件
    child: Container(
      constraints: BoxConstraints(minHeight: minHeight), // 最小高度
      padding: padding,
      decoration: buildItemDecoration(isSelected: isSelected, hasFocus: focusNode?.hasFocus ?? false), // 使用修正的装饰函数
      child: Align(
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          title,
          style: isSelected || (focusNode?.hasFocus ?? false)
              ? defaultTextStyle.merge(selectedTextStyle)
              : defaultTextStyle, // 统一样式 + 选中项样式
          softWrap: true,
          maxLines: null, // 不限制行数
          overflow: TextOverflow.visible, // 允许文字显示超出
        ),
      ),
    ),
  );

  // 根据 useFocusableItem 决定是否使用 FocusableItem 包裹
  return useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

// 分类列表组件
class CategoryList extends StatelessWidget {
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
    required this.startIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: defaultBackgroundColor,
      child: Group(
        groupIndex: 0,
        child: Column(
          children: List.generate(categories.length, (index) {
            final category = categories[index];
            final displayTitle = category == Config.myFavoriteKey
                ? S.of(context).myfavorite
                : category == Config.allChannelsKey
                    ? S.of(context).allchannels
                    : category;

            return buildListItem(
              title: displayTitle,
              isSelected: selectedCategoryIndex == index,
              onTap: () => onCategoryTap(index),
              isCentered: true,
              isTV: isTV,
              context: context,
              index: startIndex + index, // 使用 startIndex 来分配焦点索引
            );
          }),
        ),
      ),
    );
  }
}

// 分组列表组件
class GroupList extends StatelessWidget {
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
    required this.startIndex,
    this.isFavoriteCategory = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: defaultBackgroundColor,
      child: SingleChildScrollView(
        controller: scrollController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height), // 设置最小高度为屏幕高度
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 确保内容从顶部对齐
              children: keys.isEmpty && isFavoriteCategory
                  ? [
                      Container(
                        constraints: BoxConstraints(minHeight: defaultMinHeight),
                        child: Center(
                          child: Text(
                            S.of(context).nofavorite, // 暂无收藏
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
                        children: List.generate(keys.length, (index) {
                          return buildListItem(
                            title: keys[index],
                            isSelected: selectedGroupIndex == index,
                            onTap: () => onGroupTap(index),
                            isCentered: true,
                            isTV: isTV,
                            minHeight: defaultMinHeight,
                            context: context,
                            index: startIndex + index, // 使用 startIndex 来分配焦点索引
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
    required this.startIndex,
  });

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList> {
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final channelList = widget.channels.entries.toList();

    // 当频道列表为空时，直接返回空容器
    if (channelList.isEmpty) {
      return const SizedBox.shrink(); // 空容器
    }

    return Container(
      color: defaultBackgroundColor,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height), // 设置最小高度为屏幕高度
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 确保内容从顶部对齐
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
                      index: widget.startIndex + index, // 使用 startIndex 来分配焦点索引
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
  final VoidCallback onCloseDrawer;  // 添加的关闭抽屉回调

  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.isTV,
    required this.epgScrollController, // 传入控制器
    required this.onCloseDrawer,       // 传入关闭抽屉回调
  });

  @override
  State<EPGList> createState() => _EPGListState();
}

class _EPGListState extends State<EPGList> {
  @override
  void didUpdateWidget(covariant EPGList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.epgData != oldWidget.epgData || widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {}); // 只更新 EPG 列表
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有EPG数据，返回空容器
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
            padding: const EdgeInsets.only(left: 8), // 添加左边距
            decoration: BoxDecoration(
              color: defaultBackgroundColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              S.of(context).programListTitle, // 节目单列表
              style: defaultTextStyle.merge(
                const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold), // 加粗样式
              ),
            ),
          ),
          verticalDivider,
          Flexible(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: widget.selectedIndex, // 初始滚动到选中的频道项
              itemScrollController: widget.epgScrollController,
              itemCount: widget.epgData?.length ?? 0,
              itemBuilder: (BuildContext context, int index) {
                final data = widget.epgData?[index];
                if (data == null) return const SizedBox.shrink();
                final isSelect = index == widget.selectedIndex;
                return buildListItem(
                  title: '${data.start}-${data.end}\n${data.title}', // 显示节目时间与标题
                  isSelected: isSelect,
                  onTap: () {
                    widget.onCloseDrawer();  // 调用关闭抽屉回调
                  },
                  isCentered: false, // EPG列表项左对齐
                  isTV: widget.isTV,
                  context: context,
                  useFocusableItem: false, // 不使用 FocusableItem 包裹
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
  final PlaylistModel? videoMap; // 视频数据的映射
  final PlayModel? playModel; // 播放模型
  final bool isLandscape; // 是否为横屏模式
  final Function(PlayModel? newModel)? onTapChannel; // 频道点击回调
  final VoidCallback onCloseDrawer;  // 添加关闭抽屉回调

  const ChannelDrawerPage({
    super.key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
    required this.onCloseDrawer,  // 接收关闭抽屉回调
  });

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController(); // 分组列表的滚动控制器
  final ScrollController _scrollChannelController = ScrollController(); // 频道列表的滚动控制器
  final ItemScrollController _epgItemScrollController = ItemScrollController(); // EPG列表的滚动控制器
  List<EpgData>? _epgData; // 节目单数据
  int _selEPGIndex = 0; // 当前选中的节目单索引

  final GlobalKey _viewPortKey = GlobalKey(); // 视图窗口的Key
  double? _viewPortHeight; // 视图窗口的高度

  late List<String> _keys; // 视频分组的键列表
  late List<Map<String, PlayModel>> _values; // 视频分组的值列表
  late int _groupIndex; // 当前分组的索引
  late int _channelIndex; // 当前频道的索引
  late List<String> _categories; // 分类的列表
  late int _categoryIndex; // 当前选中的分类索引

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 开始监听窗口大小变化
    _initializeCategoryData(); // 初始化分类数据
    _initializeChannelData(); // 初始化频道数据

    // 计算所需的 FocusNode 总数，加入空值判断
    int totalFocusNodes = _categories.length;
    totalFocusNodes += _keys.length;
    if (_values.isNotEmpty &&
        _groupIndex >= 0 &&
        _groupIndex < _values.length &&
        (_values[_groupIndex].length > 0)) {
      totalFocusNodes += (_values[_groupIndex].length); // 频道为空时返回0
    }
    _initializeFocusNodes(totalFocusNodes);  // 使用计算出的总数初始化FocusNode列表

    _calculateViewportHeight(); // 计算视图窗口的高度

    // 只有当分类非空且有频道数据时加载 EPG
    if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 停止监听窗口变化
    if (_scrollController.hasClients) {
      _scrollController.dispose();
    }
    if (_scrollChannelController.hasClients) {
      _scrollChannelController.dispose();
    }
    _focusNodes.forEach((node) => node.dispose()); // 销毁所有 FocusNode
    _focusNodes.clear(); // 清空 FocusNode 列表
    super.dispose();
  }

  // 重写didChangeMetrics监听窗口大小变化
  @override
  void didChangeMetrics() {
    final newHeight = MediaQuery.of(context).size.height * 0.5;
    if (newHeight != _viewPortHeight) {
      setState(() {
        _viewPortHeight = newHeight;
        _adjustScrollPositions(); // 调整滚动位置
      });
    }
  }

  // 初始化分类数据
  void _initializeCategoryData() {
    _categories = widget.videoMap?.playList?.keys.toList() ?? <String>[]; // 获取所有分类
    _categoryIndex = -1;
    _groupIndex = -1;
    _channelIndex = -1;

    // 如果分类为空，直接返回，保持-1的索引状态
    if (_categories.isEmpty) {
      return;
    }

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
    // 如果分类索引无效，重置所有数据
    if (_categoryIndex < 0 || _categoryIndex >= _categories.length) {
      _resetChannelData();
      return;
    }

    final selectedCategory = _categories[_categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    if (categoryMap == null || categoryMap.isEmpty) {
      _resetChannelData();
      return;
    }

    // 三层结构：处理分组 -> 频道
    _keys = categoryMap.keys.toList();
    _values = categoryMap.values.toList();

    // 频道按名字进行 Unicode 排序
    for (int i = 0; i < _values.length; i++) {
      _values[i] = Map<String, PlayModel>.fromEntries(
        _values[i].entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
    }

    // 保持现有的索引计算逻辑
    _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

    // 确保索引有效
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

  // 切换分类时更新分组和频道
  void _onCategoryTap(int index) {
    setState(() {
      _categoryIndex = index; // 更新选中的分类索引
      _initializeChannelData(); // 根据新的分类重新初始化频道数据

      // 计算新分类下的总节点数，并初始化FocusNode
      int totalFocusNodes = _categories.length
          + (_keys.isNotEmpty ? _keys.length : 0)
          + (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
          ? _values[_groupIndex].length
          : 0);
      _initializeFocusNodes(totalFocusNodes);

      _scrollToTop(_scrollController);
      _scrollToTop(_scrollChannelController);
    });
  }

  // 切换分组时更新频道
  void _onGroupTap(int index) {
    setState(() {
      _groupIndex = index;
      _channelIndex = 0; // 重置频道索引

      // 重新计算所需节点数，并初始化FocusNode
      int totalFocusNodes = _categories.length
          + (_keys.isNotEmpty ? _keys.length : 0)
          + (_keys.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length
          ? _values[_groupIndex].length
          : 0);
      _initializeFocusNodes(totalFocusNodes);

      _scrollToTop(_scrollChannelController);
    });
  }

  // 切换频道
  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return; // 防止重复点击已选频道
    setState(() {
      widget.onTapChannel?.call(newModel); // 执行频道切换回调
    });

    // 异步加载 EPG 数据，避免阻塞 UI 渲染
    _loadEPGMsg(newModel).then((_) {
      setState(() {}); // 当 EPG 数据加载完后，更新 UI
    });
  }

  // 滚动到顶部
  void _scrollToTop(ScrollController controller) {
    controller.jumpTo(0);
  }

  // 计算视图窗口的高度
  void _calculateViewportHeight() {
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final height = renderBox.size.height * 0.5; // 取窗口高度的一半
        setState(() {
          _viewPortHeight = height;
          _adjustScrollPositions(); // 调整滚动位置
        });
      }
    });
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

  @override
  void didUpdateWidget(covariant ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playModel != oldWidget.playModel) {
      _initializeChannelData();
      // 只有在有效分组和频道数据时加载 EPG
      if (_keys.isNotEmpty &&
          _values.isNotEmpty &&
          _values[_groupIndex].isNotEmpty) {
        _loadEPGMsg(widget.playModel);
      }
      _calculateViewportHeight();
    }
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

    // 分组列表
    Widget groupListWidget = GroupList(
      keys: _keys,
      selectedGroupIndex: _groupIndex,
      onGroupTap: _onGroupTap,
      isTV: isTV,
      scrollController: _scrollController,
      isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey,
      startIndex: currentFocusIndex,  // 分组列表起始索引
    );
    currentFocusIndex += _keys.length; // 更新焦点索引

    // 频道列表
    Widget channelListWidget = ChannelList(
      channels: _values[_groupIndex],
      selectedChannelName: widget.playModel?.title,
      onChannelTap: _onChannelTap,
      isTV: isTV,
      scrollController: _scrollChannelController,
      startIndex: currentFocusIndex,  // 频道列表起始索引
    );

    // EPG 列表
    Widget epgListWidget = EPGList(
      epgData: _epgData,
      selectedIndex: _selEPGIndex,
      isTV: isTV,
      epgScrollController: _epgItemScrollController,
      onCloseDrawer: widget.onCloseDrawer,
    );

    return TvKeyNavigation(  // 包裹整个抽屉页面，处理焦点和导航
      focusNodes: _ensureCorrectFocusNodes(), // 检查并确保焦点列表正确
      isVerticalGroup: true, // 启用竖向分组
      initialIndex: 0, // 组件不自动设置初始焦点
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),  // 构建抽屉页面
    );
  }

  // 检查焦点列表是否正确，如果不正确则重建
  List<FocusNode> _ensureCorrectFocusNodes() {
    int totalNodesExpected = _categories.length + _keys.length + (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length ? _values[_groupIndex].length : 0);
    // 如果焦点节点的数量不符合预期，则重新生成焦点列表
    if (_focusNodes.length != totalNodesExpected) {
      _initializeFocusNodes(totalNodesExpected); // 根据需要重新初始化焦点节点
    }
    return _focusNodes; // 返回更新后的焦点列表
  }

  // 构建抽屉视图
  Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget groupListWidget, Widget channelListWidget, Widget epgListWidget) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double categoryWidth = 110; // 分类列表宽度

    // 设置分组列表宽度
    double groupWidth = (_keys.isNotEmpty && _categoryIndex >= 0 && _categoryIndex < _categories.length && _categories[_categoryIndex] == Config.myFavoriteKey)
        ? 120
        : (_keys.isNotEmpty ? 120 : 0);

    // 设置频道列表宽度
    double channelListWidth = (_values.isNotEmpty && _groupIndex >= 0 && _groupIndex < _values.length && _values[_groupIndex].isNotEmpty)
        ? (isPortrait
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth
        : 160)
        : 0;

    // 设置 EPG 列表宽度
    double epgListWidth =
        (isPortrait || _epgData == null || _epgData!.isEmpty)
            ? 0
            : MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth;

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
          if (groupWidth > 0)
            SizedBox(
              width: groupWidth,
              child: groupListWidget,
            ),
          verticalDivider,
          if (channelListWidth > 0)
            SizedBox(
              width: channelListWidth, // 频道列表宽度
              child: channelListWidget,
            ),
          if (epgListWidth > 0 && _epgData != null && _epgData!.isNotEmpty) ...[
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
