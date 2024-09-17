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

// 分类列表组件
class CategoryList extends StatelessWidget {
  final List<String> categories;
  final int selectedCategoryIndex;
  final Function(int index) onCategoryTap;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryIndex,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final title = categories[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5), // 添加适当的间距
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onCategoryTap(index),
              child: Container(
                constraints: const BoxConstraints(minHeight: 38.0), // 最小高度为 38 像素
                padding: const EdgeInsets.all(8.0), // 添加内边距
                child: Text(
                  title,
                  style: TextStyle(
                    color: selectedCategoryIndex == index ? Colors.red : Colors.white,
                    fontWeight: selectedCategoryIndex == index ? FontWeight.bold : FontWeight.normal,
                  ),
                  softWrap: true, // 允许文字换行
                  maxLines: null, // 行数不限，根据内容自动调整高度
                  overflow: TextOverflow.visible, // 确保文字不会被截断
                ),
              ),
            ),
          ),
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

  const GroupList({
    super.key,
    required this.keys,
    required this.scrollController,
    required this.itemHeight,
    required this.selectedGroupIndex,
    required this.onGroupTap,
  });

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    return ListView.builder(
      cacheExtent: itemHeight, // 预缓存区域
      padding: const EdgeInsets.only(bottom: 100.0), // 列表底部留白
      controller: scrollController, // 使用滚动控制器
      itemBuilder: (context, index) => _buildGroupListTile(context, index, isTV), // 构建每个分组项
      itemCount: keys.length, // 分组数目
    );
  }

  Widget _buildGroupListTile(BuildContext context, int index, bool isTV) {
    final title = keys[index];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onGroupTap(index), // 传递点击回调
        splashColor: Colors.white.withOpacity(0.3),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38.0), // 最小高度为 38 像素
          padding: const EdgeInsets.all(8.0), // 添加内边距
          decoration: BoxDecoration(
            gradient: selectedGroupIndex == index
                ? LinearGradient(colors: [Colors.red.withOpacity(0.6), Colors.red.withOpacity(0.3)])
                : null,
          ),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              title,
              style: TextStyle(
                color: selectedGroupIndex == index ? Colors.red : Colors.white,
                fontWeight: FontWeight.bold,
              ),
              softWrap: true, // 允许文字换行
              maxLines: null, // 行数不限，根据内容自动调整高度
              overflow: TextOverflow.visible, // 确保文字不会被截断
            ),
          ),
        ),
      ),
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

  const ChannelList({
    super.key,
    required this.channels,
    required this.scrollController,
    required this.itemHeight,
    required this.onChannelTap,
    this.selectedChannelName,
  });

  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100.0),
      cacheExtent: itemHeight, // 预缓存区域
      controller: scrollController, // 使用滚动控制器
      itemBuilder: (context, index) {
        final channelName = channels.keys.toList()[index];
        final isSelect = selectedChannelName == channelName;
        return _buildChannelListTile(context, channelName, isSelect, isTV);
      },
      itemCount: channels.length,
    );
  }

  Widget _buildChannelListTile(BuildContext context, String name, bool isSelect, bool isTV) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChannelTap(channels[name]),
        splashColor: Colors.white.withOpacity(0.3),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38.0), // 最小高度为 38 像素
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isSelect ? Colors.black38 : Colors.black26, // 频道项背景
            borderRadius: BorderRadius.circular(5), // 圆角
          ),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              name,
              style: TextStyle(
                color: isSelect ? Colors.redAccent : Colors.white,
                fontWeight: FontWeight.bold,
              ),
              softWrap: true, // 允许文字换行
              maxLines: null, // 行数不限，根据内容自动调整高度
              overflow: TextOverflow.visible, // 确保文字不会被截断
            ),
          ),
        ),
      ),
    );
  }
}

// EPG列表组件
class EPGList extends StatelessWidget {
  final List<EpgData>? epgData;
  final int selectedIndex;
  final Function(int index) onSelectEPG;

  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.onSelectEPG,
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), // 加粗样式
          ),
        ),
        VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
        Flexible(
          child: ScrollablePositionedList.builder(
            initialScrollIndex: selectedIndex, // 初始滚动到选中的频道项
            itemBuilder: (BuildContext context, int index) {
              final data = epgData?[index];
              if (data == null) return const SizedBox.shrink();
              final isSelect = index == selectedIndex;
              return _buildEPGListTile(data, isSelect);
            },
            itemCount: epgData?.length ?? 0,
          ),
        ),
      ],
    );
  }

  Widget _buildEPGListTile(EpgData data, bool isSelect) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: isSelect ? Colors.black38 : Colors.black26, // EPG项背景
        borderRadius: BorderRadius.circular(5), // 圆角
      ),
      child: Text(
        '${data.start}-${data.end}\n${data.title}', // 显示节目时间与标题
        style: TextStyle(
          fontWeight: isSelect ? FontWeight.bold : FontWeight.normal, // 选中项加粗显示
          color: isSelect ? Colors.redAccent : Colors.white, // 选中项显示红色
        ),
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
  final double _itemHeight = 38.0; // 每个列表项的高度
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
    final selectedCategory = _categories[_categoryIndex]; // 根据选中的分类获取对应分组
    final categoryMap = widget.videoMap?.playList[selectedCategory] as Map<String, Map<String, PlayModel>>?;

    _keys = categoryMap?.keys.toList() ?? <String>[]; // 获取分组键
    _values = categoryMap?.values.toList().cast<Map<String, PlayModel>>() ?? <Map<String, PlayModel>>[]; // 获取分组值

    // 对每个分组中的频道按名字进行 Unicode 排序
    for (int i = 0; i < _values.length; i++) {
      _values[i] = Map<String, PlayModel>.fromEntries(
        _values[i].entries.toList()..sort((a, b) => a.key.compareTo(b.key)) // 使用 compareTo 进行 Unicode 排序
      );
    }
    _groupIndex = _keys.indexOf(widget.playModel?.group ?? ''); // 当前分组的索引
    _channelIndex = _groupIndex != -1
        ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0; // 当前频道的索引

    // 如果分组或频道索引未找到，默认设置为0
    if (_groupIndex == -1) _groupIndex = 0;
    if (_channelIndex == -1) _channelIndex = 0;
  }

  // 切换分类时更新分组和频道
  void _onCategoryTap(int index) {
    setState(() {
      _categoryIndex = index; // 更新选中的分类索引
      _initializeChannelData(); // 根据新的分类重新初始化频道数据
      _groupIndex = 0; // 重置分组索引
      _channelIndex = 0; // 重置频道索引
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); // 平滑滚动到顶部
      _scrollChannelController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); // 平滑滚动到顶部
    });
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

  // 节流点击处理
  void _onTapChannelThrottled(PlayModel? newModel) {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer?.cancel();
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onTapChannel?.call(newModel); // 执行频道切换回调
    });
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
    double epgListWidth = isPortrait ? 0 : 280; // 竖屏时不显示EPG，横屏时宽度为280

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
            ),
          ),
          VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
          SizedBox(
            width: groupWidth,
            child: GroupList(
              keys: _keys,
              scrollController: _scrollController,
              itemHeight: _itemHeight,
              selectedGroupIndex: _groupIndex,
              onGroupTap: (index) {
                setState(() {
                  _groupIndex = index;
                  final name = _values[_groupIndex].keys.first;
                  _onTapChannelThrottled(_values[_groupIndex][name]);
                  _scrollChannelController.animateTo(0,
                      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); // 平滑滚动到顶部
                });
              },
            ),
          ),
          VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
          if (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
            SizedBox(
              width: channelListWidth, // 频道列表宽度
              child: ChannelList(
                channels: _values[_groupIndex],
                scrollController: _scrollChannelController,
                itemHeight: _itemHeight,
                selectedChannelName: widget.playModel?.title,
                onChannelTap: (newModel) => _onTapChannelThrottled(newModel),
              ),
            ),
          if (epgListWidth > 0 && _epgData != null && _epgData!.isNotEmpty)
            VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
          if (epgListWidth > 0 && _epgData != null && _epgData!.isNotEmpty)
            SizedBox(
              width: epgListWidth, // EPG显示区宽度
              child: EPGList(
                epgData: _epgData,
                selectedIndex: _selEPGIndex,
                onSelectEPG: (index) => setState(() {
                  _selEPGIndex = index;
                }),
              ),
            ),
        ],
      ),
    );
  }
}
