import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'package:itvapp_live_tv/util/date_util.dart';

// 分割线样式
final verticalDivider = VerticalDivider(
  width: 0.1,
  color: Colors.white.withOpacity(0.1),
);

// 通用列表项构建函数
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  bool isCentered = true, // 控制文本是否居中对齐
  double? minHeight, // 允许传入一个可选的最小高度
  EdgeInsets padding = const EdgeInsets.all(6.0), // 默认内边距
  Color selectedColor = Colors.red,
  bool isTV = false, // 是否为 TV 设备
  Function(bool)? onFocusChange, // 焦点改变时的回调
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 0),  // 分类、分组、频道、EPG 列表项的上下外边距
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withOpacity(0.3),
        canRequestFocus: isTV, // 仅在 TV 上允许请求焦点
        onFocusChange: onFocusChange,
        overlayColor: isTV ? MaterialStateProperty.all(Colors.greenAccent.withOpacity(0.2)) : null, // TV 焦点颜色变化
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight ?? 38.0), // 默认最小高度为 38.0
          padding: padding,
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      selectedColor.withOpacity(0.6),
                      selectedColor.withOpacity(0.3),
                    ],
                  )
                : BoxDecoration(
                       color: Colors.black38, // 未选中时背景色
                  ),
          ),
          child: Align(
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),  // 未选中文字颜色
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: isSelected ? 16 : 15, // 选中时文字稍大
              ),
              softWrap: true,
              maxLines: null,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
      ),
    ),
  );
}

// 分类列表组件
class CategoryList extends StatelessWidget {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;
  final bool isTV;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.onCategoryTap,
    required this.isTV,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, index) {
        return buildListItem(
          title: categories[index],
          isSelected: selectedCategoryIndex == index,
          onTap: () => onCategoryTap(index),
          isCentered: true, // 分类列表项居中
          minHeight: 48.0, // 设置分类列表项的最小高度
          isTV: isTV, // 是否为 TV 设备
          onFocusChange: (focus) {
            if (isTV && focus) {
              Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
            }
          },
        );
      },
    );
  }
}

// 分组列表组件
class GroupList extends StatelessWidget {
  final List<String> keys;
  final ScrollController scrollController;
  final double itemHeight;
  final int selectedGroupIndex;
  final Function(int index) onGroupTap;
  final bool isTV;

  const GroupList({
    super.key,
    required this.keys,
    required this.scrollController,
    required this.itemHeight,
    required this.selectedGroupIndex,
    required this.onGroupTap,
    required this.isTV,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      cacheExtent: itemHeight, // 预缓存区域
      padding: const EdgeInsets.only(bottom: 100.0), // 列表底部留白
      controller: scrollController, // 使用滚动控制器
      itemCount: keys.length, // 分组数目
      itemBuilder: (context, index) {
        return buildListItem(
          title: keys[index],
          isSelected: selectedGroupIndex == index,
          onTap: () => onGroupTap(index),
          isCentered: true, // 分组列表项居中
          minHeight: itemHeight, // 使用传入的 itemHeight 设置最小高度
          isTV: isTV, // 是否为 TV 设备
          onFocusChange: (focus) {
            if (isTV && focus) {
              Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
            }
          },
        );
      },
    );
  }
}

// 频道列表组件
class ChannelList extends StatelessWidget {
  final Map<String, PlayModel> channels;
  final ScrollController scrollController;
  final double itemHeight;
  final Function(PlayModel?) onChannelTap;
  final String? selectedChannelName;
  final bool isTV;

  const ChannelList({
    super.key,
    required this.channels,
    required this.scrollController,
    required this.itemHeight,
    required this.onChannelTap,
    this.selectedChannelName,
    required this.isTV,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100.0),
      cacheExtent: itemHeight, // 预缓存区域
      controller: scrollController, // 使用滚动控制器
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channelName = channels.keys.toList()[index];
        final isSelect = selectedChannelName == channelName;
        return buildListItem(
          title: channelName,
          isSelected: isSelect,
          onTap: () => onChannelTap(channels[channelName]),
          isCentered: true, // 频道列表项居中
          minHeight: itemHeight, // 使用传入的 itemHeight 设置最小高度
          isTV: isTV, // 是否为 TV 设备
          onFocusChange: (focus) {
            if (isTV && focus) {
              Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
            }
          },
        );
      },
    );
  }
}

// EPG列表组件
class EPGList extends StatelessWidget {
  final List<EpgData>? epgData;
  final int selectedIndex;
  final bool isTV;

  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.isTV,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 8),  // 添加左边距
          decoration: BoxDecoration(
            color: Colors.black38, // 设置背景色
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            S.of(context).programListTitle, // 节目单列表
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // 加粗样式
          ),
        ),
        verticalDivider, // 分割线
        Flexible(
          child: ScrollablePositionedList.builder(
            initialScrollIndex: selectedIndex, // 初始滚动到选中的频道项
            itemCount: epgData?.length ?? 0,
            itemBuilder: (BuildContext context, int index) {
              final data = epgData?[index];
              if (data == null) return const SizedBox.shrink();
              final isSelect = index == selectedIndex;
              return buildListItem(
                title: '${data.start}-${data.end}\n${data.title}', // 显示节目时间与标题
                isSelected: isSelect,
                onTap: () {}, // 禁用点击事件，EPG项不可点击
                isCentered: false, // EPG列表项左对齐
                minHeight: 48.0, // 固定的最小高度
                padding: const EdgeInsets.all(10),
                selectedColor: Colors.redAccent,
                isTV: isTV,
                onFocusChange: (focus) {
                  if (isTV && focus) {
                    Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 220));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// 主组件ChannelDrawerPage
class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap; // 视频数据的映射
  final PlayModel? playModel; // 播放模型
  final bool isLandscape; // 是否为横屏模式
  final Function(PlayModel? newModel)? onTapChannel; // 频道点击回调

  const ChannelDrawerPage({
    super.key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
  });

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> {
  final ScrollController _scrollController = ScrollController(); // 分组列表的滚动控制器
  final ScrollController _scrollChannelController = ScrollController(); // 频道列表的滚动控制器
  List<EpgData>? _epgData; // 节目单数据
  int _selEPGIndex = 0; // 当前选中的节目单索引

  final GlobalKey _viewPortKey = GlobalKey(); // 视图窗口的Key
  double? _viewPortHeight; // 视图窗口的高度

  late List<String> _keys; // 视频分组的键列表
  late List<Map<String, PlayModel>> _values; // 视频分组的值列表
  late int _groupIndex; // 当前分组的索引
  late int _channelIndex; // 当前频道的索引
  final double _itemHeight = 48.0; // 每个列表项的高度
  late List<String> _categories; // 分类的列表
  late int _categoryIndex; // 当前选中的分类索引

  Timer? _debounceTimer; // 用于节流或防抖

  @override
  void initState() {
    super.initState();
    _initializeCategoryData(); // 初始化分类数据
    _initializeChannelData(); // 初始化频道数据
    _calculateViewportHeight(); // 计算视图窗口的高度
    _loadEPGMsg(widget.playModel); // 加载EPG（节目单）数据
  }

  // 初始化分类数据
  void _initializeCategoryData() {
    _categories = widget.videoMap?.playList?.keys.toList() ?? <String>[]; // 获取所有分类的键
    _categoryIndex = 0; // 初始化选中的分类索引
  }

  // 初始化频道数据
void _initializeChannelData() {
  final selectedCategory = _categories[_categoryIndex];
  
  // 判断数据结构是否是三层结构，即 Map<String, Map<String, PlayModel>>
  final categoryMap = widget.videoMap?.playList[selectedCategory];
  
  if (categoryMap is Map<String, Map<String, PlayModel>>) {
    // 三层结构：处理分组 -> 频道
    _keys = categoryMap.keys.toList(); // 获取分组
    _values = categoryMap.values.toList(); // 获取每个分组下的频道
    
    // 对每个分组中的频道按名字进行 Unicode 排序
    for (int i = 0; i < _values.length; i++) {
      _values[i] = Map<String, PlayModel>.fromEntries(
        _values[i].entries.toList()..sort((a, b) => a.key.compareTo(b.key))
      );
    }
    
    _groupIndex = _keys.indexOf(widget.playModel?.group ?? ''); // 获取当前选中分组的索引
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0; // 获取当前选中的频道索引
  } else if (categoryMap is Map<String, PlayModel>) {
    // 两层结构：直接处理频道
    _keys = ['所有频道']; // 使用一个默认分组
    _values = [categoryMap]; // 频道直接作为值
    
    _groupIndex = 0; // 没有分组，固定为 0
    _channelIndex = _values[0].keys.toList().indexOf(widget.playModel?.title ?? '');
  }

  // 默认值处理
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
        final name = _values[_groupIndex].keys.first;
        _onChannelTap(_values[_groupIndex][name]);
        _scrollToTop(_scrollChannelController);
      });
    });
  }

  // 切换频道
  void _onChannelTap(PlayModel? newModel) {
    _onTapThrottled(() {
      widget.onTapChannel?.call(newModel); // 执行频道切换回调
    });
  }

  // 滚动到顶部
  void _scrollToTop(ScrollController controller) {
    controller.animateTo(0,
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); // 平滑滚动到顶部
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
    _scrollToPosition(_scrollController, _groupIndex); // 调整分组列表的滚动位置
    _scrollToPosition(_scrollChannelController, _channelIndex); // 调整频道列表的滚动位置
  }

  // 根据索引调整滚动位置，使用动画滚动
  void _scrollToPosition(ScrollController controller, int index) {
    if (!controller.hasClients) return;
    final maxScrollExtent = controller.position.maxScrollExtent; // 最大滚动范围
    final double viewPortHeight = _viewPortHeight!;
    final shouldOffset = index * _itemHeight - viewPortHeight + _itemHeight * 0.5; // 计算偏移量
    controller.animateTo(
      shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 加载EPG（节目单）数据
  Future<void> _loadEPGMsg(PlayModel? playModel) async {
    if (playModel == null) return;
    setState(() {
      _epgData = null; // 清空当前节目单数据
      _selEPGIndex = 0; // 重置选中的节目单索引
    });
    try {
      final res = await EpgUtil.getEpg(playModel); // 获取EPG数据
      if (res?.epgData == null || res!.epgData!.isEmpty) return;

      setState(() {
        _epgData = res!.epgData!; // 更新节目单数据
        final epgRangeTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm'); // 当前时间
        final selectTimeData = _epgData!.lastWhere(
          (element) => element.start!.compareTo(epgRangeTime) < 0, // 查找当前时间之前的节目
          orElse: () => _epgData!.first, // 如果未找到，默认选中第一个节目
        ).start;
        _selEPGIndex = _epgData!.indexWhere((element) => element.start == selectTimeData); // 设置选中的节目索引
      });
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
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playModel != oldWidget.playModel) {
      _initializeChannelData();
      _loadEPGMsg(widget.playModel);
      _calculateViewportHeight();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 从 ThemeProvider 获取 isTV 状态
    bool isTV = context.read<ThemeProvider>().isTV;
    return _buildOpenDrawer(isTV); // 将 isTV 传递给 _buildOpenDrawer
  }

  // 构建抽屉视图
  Widget _buildOpenDrawer(bool isTV) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double categoryWidth = 110 * context.read<ThemeProvider>().textScaleFactor; // 分类列表宽度
    double groupWidth = 110 * context.read<ThemeProvider>().textScaleFactor; // 分组列表宽度
    double channelListWidth = isPortrait
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth // 频道列表宽度
        : 160; // 横屏时频道列表宽度为固定160
    double epgListWidth = isPortrait ? 0 : MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth; // EPG列表宽度

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape 
          ? categoryWidth + groupWidth + channelListWidth + epgListWidth 
          : MediaQuery.of(context).size.width, // 使用 MediaQuery 来获取屏幕宽度
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent]), // 渐变背景
      ),
      child: Row(
        children: [
          SizedBox(
            width: categoryWidth,
            child: CategoryList(
              categories: _categories,
              selectedCategoryIndex: _categoryIndex,
              onCategoryTap: _onCategoryTap, // 分类点击事件
              isTV: isTV, // 是否为 TV 设备
            ),
          ),
          verticalDivider, // 分割线
          SizedBox(
            width: groupWidth,
            child: GroupList(
              keys: _keys,
              scrollController: _scrollController,
              itemHeight: _itemHeight,
              selectedGroupIndex: _groupIndex,
              onGroupTap: _onGroupTap, // 分组点击事件
              isTV: isTV, // 是否为 TV 设备
            ),
          ),
          verticalDivider, // 分割线
          if (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
            SizedBox(
              width: channelListWidth, // 频道列表宽度
              child: ChannelList(
                channels: _values[_groupIndex],
                scrollController: _scrollChannelController,
                itemHeight: _itemHeight,
                selectedChannelName: widget.playModel?.title,
                onChannelTap: _onChannelTap, // 频道点击事件
                isTV: isTV, // 是否为 TV 设备
              ),
            ),
          if (epgListWidth > 0 && _epgData != null && _epgData!.isNotEmpty) 
            verticalDivider, // 分割线
            SizedBox(
              width: epgListWidth, // EPG显示区宽度
              child: EPGList(
                epgData: _epgData,
                selectedIndex: _selEPGIndex,
                isTV: isTV, // 是否为 TV 设备
              ),
            ),
        ],
      ),
    );
  }
}
