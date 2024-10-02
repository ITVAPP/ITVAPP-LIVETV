import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

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
  bool isTV = false,
  Function(bool)? onFocusChange,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 0),  // 列表项的上下外边距
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
                      selectedColor.withOpacity(0.8),
                      selectedColor.withOpacity(0.6),
                    ],
                  )
                : null,
          ),
          child: Align(
            alignment: isCentered ? Alignment.center : Alignment.centerLeft,
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),  // 未选中文字颜色
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: isSelected ? 16 : 16, // 选中时文字稍大
                shadows: isSelected
                    ? [ // 给选中的文字加阴影
                    Shadow(
                    offset: Offset(1.0, 1.0), // 阴影偏移
                    blurRadius: 3.0, // 模糊半径
                    color: Colors.black.withOpacity(0.5), // 阴影颜色
                ),
                      ]
                    : null,
              ),
              softWrap: true, // 自动换行
              maxLines: null, // 不限制行数
              overflow: TextOverflow.visible, // 允许文字显示超出
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
    return Container(
      color: Colors.black38, // 设置背景色
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          // 检查分类是否为 "我的收藏" 或 "所有频道"，并使用国际化文本
          String displayTitle;
          if (categories[index] == Config.myFavoriteKey) {
            displayTitle = S.of(context).myfavorite;
          } else if (categories[index] == Config.allChannelsKey) {
            displayTitle = S.of(context).allchannels;
          } else {
            displayTitle = categories[index]; // 使用原始分类名
          }

          return buildListItem(
            title: displayTitle,
            isSelected: selectedCategoryIndex == index,
            onTap: () => onCategoryTap(index),
            isCentered: true, // 分类列表项居中
            minHeight: 42.0, // 分类列表项的最小高度
            isTV: isTV,
            onFocusChange: (focus) {
              if (isTV && focus) {
                Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
              }
            },
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
  final double itemHeight;
  final int selectedGroupIndex;
  final Function(int index) onGroupTap;
  final bool isTV;
  final bool isFavoriteCategory; // 标识是否为收藏分类

  const GroupList({
    super.key,
    required this.keys,
    required this.scrollController,
    required this.itemHeight,
    required this.selectedGroupIndex,
    required this.onGroupTap,
    required this.isTV,
    this.isFavoriteCategory = false, 
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38, // 设置背景色
      child: ListView.builder(
        cacheExtent: itemHeight, 
        padding: const EdgeInsets.only(bottom: 100.0), 
        controller: scrollController, // 使用滚动控制器
        itemCount: keys.isEmpty && isFavoriteCategory ? 1 : keys.length,
        itemBuilder: (context, index) {
          if (keys.isEmpty && isFavoriteCategory) {
            return Center(
              child: Container( 
                constraints: BoxConstraints(minHeight: itemHeight),
                child: Center(
                  child: Text(
                    S.of(context).nofavorite,  // 暂无收藏
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    softWrap: true, // 自动换行
                    maxLines: null, // 不限制行数
                    overflow: TextOverflow.visible, // 允许文字显示超出
                  ),
                ),
              ),
            );
          }
          return buildListItem(
            title: keys[index],
            isSelected: selectedGroupIndex == index,
            onTap: () => onGroupTap(index),
            isCentered: true, // 分组列表项居中
            minHeight: itemHeight, // 使用传入的最小高度
            isTV: isTV,
            onFocusChange: (focus) {
              if (isTV && focus) {
                Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
              }
            },
          );
        },
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
    return Container(
      color: Colors.black38, // 设置背景色
      child: ListView.builder(
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
            minHeight: itemHeight, // 使用传入的最小高度
            isTV: isTV,
            onFocusChange: (focus) {
              if (isTV && focus) {
                Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
              }
            },
          );
        },
      ),
    );
  }
}

// EPG列表组件
class EPGList extends StatelessWidget {
  final List<EpgData>? epgData;
  final int selectedIndex;
  final bool isTV;
  final ItemScrollController epgScrollController; // 新增的控制器参数
  const EPGList({
    super.key,
    required this.epgData,
    required this.selectedIndex,
    required this.isTV,
    required this.epgScrollController, // 传入控制器
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38, // 设置背景色
      child: Column(
        children: [
          Container(
            height: 42,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),  // 添加左边距
            decoration: BoxDecoration(
              color: Colors.black38, // 设置背景色
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              S.of(context).programListTitle, // 节目单列表
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // 加粗样式
              softWrap: true, // 自动换行
              maxLines: null, // 不限制行数
              overflow: TextOverflow.visible, // 允许文字显示超出
            ),
          ),
          verticalDivider,
          Flexible(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: selectedIndex, // 初始滚动到选中的频道项
              itemScrollController: epgScrollController, // 传入控制器
              itemCount: epgData?.length ?? 0,
              itemBuilder: (BuildContext context, int index) {
                final data = epgData?[index];
                if (data == null) return const SizedBox.shrink();
                final isSelect = index == selectedIndex;
                return buildListItem(
                  title: '${data.start}-${data.end}\n${data.title}', // 显示节目时间与标题
                  isSelected: isSelect,
                  onTap: () {
                    Navigator.pop(context); // 点击节目单项时关闭抽屉
                  },
                  isCentered: false, // EPG列表项左对齐
                  minHeight: 42.0, // 固定的最小高度
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
  final ItemScrollController _epgItemScrollController = ItemScrollController(); // EPG列表的滚动控制器
  List<EpgData>? _epgData; // 节目单数据
  int _selEPGIndex = 0; // 当前选中的节目单索引

  final GlobalKey _viewPortKey = GlobalKey(); // 视图窗口的Key
  double? _viewPortHeight; // 视图窗口的高度

  late List<String> _keys; // 视频分组的键列表
  late List<Map<String, PlayModel>> _values; // 视频分组的值列表
  late int _groupIndex; // 当前分组的索引
  late int _channelIndex; // 当前频道的索引
  final double _itemHeight = 42.0; // 每个列表项的高度
  late List<String> _categories; // 分类的列表
  late int _categoryIndex; // 当前选中的分类索引

  Timer? _debounceTimer; // 用于节流或防抖

  @override
  void initState() {
    super.initState();
    _initializeCategoryData(); // 初始化分类数据
    _initializeChannelData(); // 初始化频道数据
    _calculateViewportHeight(); // 计算视图窗口的高度

    // 只有当分类非空且有频道数据时加载 EPG
    if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel); // 加载EPG（节目单）数据
    }
  }

  // 初始化分类数据
  void _initializeCategoryData() {
    _categories = widget.videoMap?.playList?.keys.toList() ?? <String>[]; // 获取所有分类的键

    // 查找第一个非空的分类，并在找到后停止遍历
    for (int i = 0; i < _categories.length; i++) {
      final categoryMap = widget.videoMap?.playList[_categories[i]];

      // 如果分类不为空，立即设置为选中的分类并退出循环
      if (categoryMap != null && categoryMap.isNotEmpty) {
        _categoryIndex = i; // 选中第一个非空分类
        break; // 找到后立即退出循环
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

      // 空分类不加载 EPG 数据
      _epgData = null; // 确保 EPG 数据为空
      _selEPGIndex = 0;
      return;
    }

    if (categoryMap is Map<String, Map<String, PlayModel>>) {
      // 三层结构：处理分组 -> 频道
      _keys = categoryMap.keys.toList(); // 获取分组
      _values = categoryMap.values.toList(); // 获取每个分组下的频道

      // 对每个分组中的频道按名字进行 Unicode 排序
      for (int i = 0; i < _values.length; i++) {
        _values[i] = Map<String, PlayModel>.fromEntries(
          _values[i].entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        );
      }

      _groupIndex = _keys.indexOf(widget.playModel?.group ?? ''); // 获取当前选中分组的索引
      _channelIndex = _groupIndex != -1
          ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
          : 0; // 获取当前选中的频道索引
    } else if (categoryMap is Map<String, PlayModel>) {
      // 两层结构：直接处理频道
      _keys = [Config.allChannelsKey]; // 使用一个默认分组
      _values = [categoryMap]; // 频道直接作为值

      _groupIndex = 0; // 没有分组，固定为 0
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
        _scrollToTop(_scrollController);
        _scrollToTop(_scrollChannelController);

        // 只有在非空分组和频道的情况下加载 EPG 数据
        if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
          _loadEPGMsg(widget.playModel); // 加载EPG数据
        } else {
          _epgData = null; // 清空 EPG 数据
          _selEPGIndex = 0;
        }
      });
    });
  }

  // 切换分组时更新频道
  void _onGroupTap(int index) {
    _onTapThrottled(() {
      setState(() {
        _groupIndex = index;
        _channelIndex = 0;    // 重置频道索引
        _scrollToTop(_scrollChannelController);

        // 根据当前分组是否有频道决定是否加载 EPG 数据
        if (_values[_groupIndex].isNotEmpty) {
          _loadEPGMsg(widget.playModel);
        } else {
          _epgData = null; // 清空 EPG 数据
          _selEPGIndex = 0;
        }
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
    final maxScrollExtent = controller.position.maxScrollExtent;
    final double viewPortHeight = _viewPortHeight!;
    final shouldOffset = index * _itemHeight - viewPortHeight + _itemHeight * 0.5;
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
        // 在节目单数据更新后滚动到当前选中的节目项
        if (_epgData != null && _epgData!.isNotEmpty && _selEPGIndex < _epgData!.length) {
          _epgItemScrollController.scrollTo(
            index: _selEPGIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
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
      // 只有在有效分组和频道数据时加载 EPG
      if (_keys.isNotEmpty && _values.isNotEmpty && _values[_groupIndex].isNotEmpty) {
        _loadEPGMsg(widget.playModel);
      }
      _calculateViewportHeight();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取 isTV 状态
    bool isTV = context.read<ThemeProvider>().isTV;
    return _buildOpenDrawer(isTV); // 将 isTV 传递给 _buildOpenDrawer
  }

  // 构建抽屉视图
  Widget _buildOpenDrawer(bool isTV) {
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double categoryWidth = 110; // 固定分类列表宽度

    // 设置分组列表宽度，只有当 _keys 非空时显示，取消 textScaleFactor
    double groupWidth = (_keys.isNotEmpty || _categories[_categoryIndex] == Config.myFavoriteKey) ? 120 : 0; 

    // 设置频道列表宽度，只有当 _values 和 _groupIndex 下有频道时显示
    double channelListWidth = (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
        ? (isPortrait
            ? MediaQuery.of(context).size.width - categoryWidth - groupWidth // 频道列表宽度
            : 160) // 横屏时频道列表宽度为固定160
        : 0;

    // 设置 EPG 列表宽度，只有当有 EPG 数据时显示
    double epgListWidth = (isPortrait || _epgData == null || _epgData!.isEmpty)
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
            child: CategoryList(
              categories: _categories,
              selectedCategoryIndex: _categoryIndex,
              onCategoryTap: _onCategoryTap, // 分类点击事件
              isTV: isTV,
            ),
          ),
          verticalDivider,
          if (groupWidth > 0)
            SizedBox(
              width: groupWidth,
              child: GroupList(
                keys: _keys,
                scrollController: _scrollController,
                itemHeight: _itemHeight,
                selectedGroupIndex: _groupIndex,
                onGroupTap: _onGroupTap, // 分组点击事件
                isTV: isTV,
                isFavoriteCategory: _categories[_categoryIndex] == Config.myFavoriteKey, // 传递是否为收藏分类的标识
              ),
            ),
          verticalDivider,
          if (channelListWidth > 0)
            SizedBox(
              width: channelListWidth, // 频道列表宽度
              child: ChannelList(
                channels: _values[_groupIndex],
                scrollController: _scrollChannelController,
                itemHeight: _itemHeight,
                selectedChannelName: widget.playModel?.title,
                onChannelTap: _onChannelTap, // 频道点击事件
                isTV: isTV,
              ),
            ),
          if (epgListWidth > 0 && _epgData != null && _epgData!.isNotEmpty)
            verticalDivider,
            if (epgListWidth > 0)
              SizedBox(
                width: epgListWidth, // EPG列表宽度
                child: EPGList(
                  epgData: _epgData,
                  selectedIndex: _selEPGIndex,
                  isTV: isTV,
                  epgScrollController: _epgItemScrollController, // 传递滚动控制器
                ),
              ),
        ],
      ),
    );
  }
}
