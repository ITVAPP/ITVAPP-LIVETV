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

// 装饰设置
BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    gradient: (isSelected || hasFocus) // 选中或获得焦点时的渐变背景
        ? LinearGradient(
            colors: [
              Colors.red.withOpacity(0.6),
              Colors.red.withOpacity(0.3),
            ],
          )
        : null, // 非选中项无背景
  );
}

// 用于管理所有 FocusNode 的列表
List<FocusNode> _focusNodes = [];

// 动态更新 FocusNode 列表
void _updateFocusNodeList(int requiredLength) {
  while (_focusNodes.length < requiredLength) {
    _focusNodes.add(FocusNode());
  }
  while (_focusNodes.length > requiredLength) {
    _focusNodes.removeLast().dispose(); // 移除并销毁多余的 FocusNode
  }
}

// 创建或获取已有的 FocusNode
FocusNode getOrCreateFocusNode(int index) {
  if (_focusNodes.length <= index) {
    _focusNodes.add(FocusNode());
  }
  return _focusNodes[index];
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
  Color selectedColor = Colors.red,
  bool isTV = false,
  Function(bool)? onFocusChange,
  required int index, // index 参数，用于获取 FocusNode
  bool useFocusableItem = true, // 控制是否使用 FocusableItem 包裹
}) {
  FocusNode focusNode = getOrCreateFocusNode(index);
  bool hasFocus = focusNode.hasFocus; // 焦点状态

  Widget listItemContent = InkWell(
    onTap: onTap,
    splashColor: Colors.white.withOpacity(0.3),
    canRequestFocus: isTV, // 仅在 TV 上允许请求焦点
    child: Container(
      constraints: BoxConstraints(minHeight: minHeight), // 最小高度
      padding: padding,
      decoration: buildItemDecoration(isSelected: isSelected, hasFocus: hasFocus),
      child: Align(
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          title,
          style: isSelected || hasFocus
              ? defaultTextStyle.merge(selectedTextStyle)
              : defaultTextStyle, // 统一样式 + 选中项样式
          softWrap: true,
          maxLines: null, // 不限制行数
          overflow: TextOverflow.visible, // 允许文字显示超出
        ),
      ),
    ),
  );

  if (useFocusableItem) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0), // 列表项的上下外边距
      child: Material(
        color: Colors.transparent,
        child: FocusableItem( // 使用 FocusableItem 包裹 InkWell
          focusNode: focusNode,
          child: listItemContent,
        ),
      ),
    );
  } else {
    return listItemContent;
  }
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
        child: ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, index) {
            String displayTitle;
            if (categories[index] == Config.myFavoriteKey) {
              displayTitle = S.of(context).myfavorite;
            } else if (categories[index] == Config.allChannelsKey) {
              displayTitle = S.of(context).allchannels;
            } else {
              displayTitle = categories[index]; // 使用原始分类名
            }

            return Group(
              groupIndex: 0, // 设置分类列表的分组索引为 0
              child: buildListItem(
              title: displayTitle,
              isSelected: selectedCategoryIndex == index,
              onTap: () => onCategoryTap(index),
              isCentered: true, // 分类列表项居中
              isTV: isTV,
              context: context,
              index: startIndex + index, // 将起始索引传递到 buildListItem
            ),
           ); 
          },
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
  final bool isFavoriteCategory; // 标识是否为收藏分类
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
        child: ListView.builder(
          cacheExtent: defaultMinHeight,
          padding: const EdgeInsets.only(bottom: 100.0),
          controller: scrollController, // 使用滚动控制器
          itemCount: keys.isEmpty && isFavoriteCategory ? 1 : keys.length,
          itemBuilder: (context, index) {
            if (keys.isEmpty && isFavoriteCategory) {
              return Center(
                child: Container(
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
              );
            }
            return Group( // 使用 Group 包裹分组列表
              groupIndex: 1, 
              child: buildListItem(
              title: keys[index],
              isSelected: selectedGroupIndex == index,
              onTap: () => onGroupTap(index),
              isCentered: true, // 分组列表项居中
              isTV: isTV,
              minHeight: defaultMinHeight,
              context: context,
              index: startIndex + index,
              ),
            );
          },
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
    return Container(
        color: defaultBackgroundColor,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 100.0),
          cacheExtent: defaultMinHeight,
          controller: widget.scrollController, // 使用滚动控制器
          itemCount: widget.channels.length,
          itemBuilder: (context, index) {
            final channelName = widget.channels.keys.toList()[index];
            final isSelect = widget.selectedChannelName == channelName;
            return Group( // 使用 Group 包裹频道列表
              groupIndex: 2, // 设置频道列表的分组索引为 2
              child: buildListItem(
              title: channelName,
              isSelected: isSelect,
              onTap: () => widget.onChannelTap(widget.channels[channelName]),
              isCentered: true, // 频道列表项居中
              minHeight: defaultMinHeight,
              isTV: widget.isTV,
              context: context,
              index: widget.startIndex + index,
              ),
            );
          },
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
  final int startIndex; 

  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.isTV,
    required this.epgScrollController, // 传入控制器
    required this.onCloseDrawer,       // 传入关闭抽屉回调
    required this.startIndex,          // 传递起始索引
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
                    fontSize: 18, fontWeight: FontWeight.bold), // 加粗样式
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
                    index: widget.startIndex + index, 
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

class _ChannelDrawerPageState extends State<ChannelDrawerPage> {
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

  Timer? _debounceTimer; // 用于节流

  @override
  void initState() {
    super.initState();
    _initializeCategoryData(); // 初始化分类数据
    _initializeChannelData(); // 初始化频道数据
    _calculateViewportHeight(); // 计算视图窗口的高度

    // 只有当分类非空且有频道数据时加载 EPG
    if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel);
    }
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

    // 如果未找到当前播放频道的分类，默认第一个非空分类
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
    final selectedCategory = _categories[_categoryIndex];

    // 判断是否为空分类
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    if (categoryMap == null || categoryMap.isEmpty) {
      // 如果分类是空的，设置空的 keys 和 values
      _keys = [];
      _values = [];
      _groupIndex = 0;
      _channelIndex = 0;
      _epgData = null;
      _selEPGIndex = 0;
      return;
    }

    if (categoryMap is Map<String, Map<String, PlayModel>>) {
      // 三层结构：处理分组 -> 频道
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
          : 0; // 获取当前选中的频道索引
    } else if (categoryMap is Map<String, PlayModel>) {
      // 两层结构：直接处理频道
      _keys = [Config.allChannelsKey];
      _values = [categoryMap];
      _groupIndex = 0; // 没有分组设置宽度为 0
      _channelIndex = _values[0].keys.toList().indexOf(widget.playModel?.title ?? '');
    }
    if (_groupIndex == -1) _groupIndex = 0;
    if (_channelIndex == -1) _channelIndex = 0;
  }

  // 通用节流点击处理
  void _onTapThrottled(Function action) {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer?.cancel();
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      action();
    });
  }

  // 切换分类时更新分组和频道
  void _onCategoryTap(int index) {
    _onTapThrottled(() {
      setState(() {
        _categoryIndex = index; // 更新选中的分类索引
        _initializeChannelData(); // 根据新的分类重新初始化频道数据
        _groupIndex = 0; // 重置分组索引
        _channelIndex = 0; // 重置频道索引

        // 调用 _updateFocusNodeList 动态更新 FocusNode 列表
        _updateFocusNodeList(_categories.length + _keys.length + _values[_groupIndex].length + (_epgData?.length ?? 0));

        _scrollToTop(_scrollController);
        _scrollToTop(_scrollChannelController);
      });
    });
  }

  // 切换分组时更新频道
  void _onGroupTap(int index) {
    _onTapThrottled(() {
      setState(() {
        _groupIndex = index;
        _channelIndex = 0; // 重置频道索引

        // 调用 _updateFocusNodeList 动态更新 FocusNode 列表
        _updateFocusNodeList(_categories.length + _keys.length + _values[_groupIndex].length + (_epgData?.length ?? 0));

        _scrollToTop(_scrollChannelController);
      });
    });
  }

  // 切换频道
  void _onChannelTap(PlayModel? newModel) {
    widget.onTapChannel?.call(newModel); // 执行频道切换回调
    // 使用节流，防止多次加载
    _onTapThrottled(() {
      _loadEPGMsg(newModel); // 加载EPG数据
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
  void dispose() {
    _debounceTimer?.cancel(); // 清理定时器
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
    currentFocusIndex += _values[_groupIndex].length; // 更新焦点索引

    // EPG 列表
    Widget epgListWidget = EPGList(
      epgData: _epgData,
      selectedIndex: _selEPGIndex,
      isTV: isTV,
      epgScrollController: _epgItemScrollController,
      onCloseDrawer: widget.onCloseDrawer,
      startIndex: currentFocusIndex,  // EPG列表起始索引
    );

    return TvKeyNavigation(  // 包裹整个抽屉页面，处理焦点和导航
      focusNodes: _focusNodes, // 使用全局焦点列表
      isVerticalGroup: true, // 启用竖向分组
      initialIndex: _channelIndex, // 设置初始焦点
      child: _buildOpenDrawer(isTV, categoryListWidget, groupListWidget, channelListWidget, epgListWidget),  // 构建抽屉页面
    );
  }

  // 构建抽屉视图
  Widget _buildOpenDrawer(bool isTV, Widget categoryListWidget, Widget groupListWidget, Widget channelListWidget, Widget epgListWidget) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double categoryWidth = 110; // 分类列表宽度

    // 设置分组列表宽度
    double groupWidth = (_keys.isNotEmpty || _categories[_categoryIndex] == Config.myFavoriteKey)
        ? 120
        : 0;

    // 设置频道列表宽度
    double channelListWidth = (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
        ? (isPortrait
            ? MediaQuery.of(context).size.width - categoryWidth - groupWidth // 频道列表宽度
            : 160) // 横屏时为160
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
          if (epgListWidth > 0 && _epgData != null && _epgData!.isNotEmpty)
            verticalDivider,
          if (epgListWidth > 0)
            SizedBox(
              width: epgListWidth, // EPG列表宽度
              child: epgListWidget,
            ),
        ],
      ),
    );
  }
}
