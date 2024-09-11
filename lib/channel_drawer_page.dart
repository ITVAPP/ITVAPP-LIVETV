import 'dart:math';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'provider/theme_provider.dart';
import 'entity/playlist_model.dart';
import 'util/env_util.dart';

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
  final double _itemHeight = 50.0; // 每个列表项的高度

  @override
  void initState() {
    super.initState();
    LogUtil.safeExecute(() {
      _initializeChannelData(); // 初始化频道数据
      _calculateViewportHeight(); // 计算视图窗口的高度
      _loadEPGMsg(widget.playModel); // 加载EPG（节目单）数据
    }, '初始化频道数据时发生错误');
  }

  // 初始化频道数据
  void _initializeChannelData() {
    LogUtil.safeExecute(() {
      _keys = widget.videoMap?.playList?.keys.toList() ?? <String>[]; // 获取所有分组的键
      _values = widget.videoMap?.playList?.values.toList().cast<Map<String, PlayModel>>() ?? <Map<String, PlayModel>>[]; // 获取所有分组的值
      _groupIndex = _keys.indexOf(widget.playModel?.group ?? ''); // 当前分组的索引
      _channelIndex = _groupIndex != -1
          ? _values[_groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
          : 0; // 当前频道的索引

      // 如果分组或频道索引未找到，默认设置为0
      if (_groupIndex == -1) _groupIndex = 0;
      if (_channelIndex == -1) _channelIndex = 0;
    }, '初始化频道数据时出错');
  }

  // 计算视图窗口的高度
  void _calculateViewportHeight() {
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      LogUtil.safeExecute(() {
        final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final height = renderBox.size.height * 0.5; // 取窗口高度的一半
          setState(() {
            _viewPortHeight = height;
            _adjustScrollPositions(); // 调整滚动位置
          });
        }
      }, '计算视图窗口高度时出错');
    });
  }

  // 调整分组和频道列表的滚动位置
  void _adjustScrollPositions() {
    LogUtil.safeExecute(() {
      if (_viewPortHeight == null) return;
      _scrollToPosition(_scrollController, _groupIndex); // 调整分组列表的滚动位置
      _scrollToPosition(_scrollChannelController, _channelIndex); // 调整频道列表的滚动位置
    }, '调整滚动位置时出错');
  }

  // 根据索引调整滚动位置
  void _scrollToPosition(ScrollController controller, int index) {
    LogUtil.safeExecute(() {
      if (!controller.hasClients) return;
      final maxScrollExtent = controller.position.maxScrollExtent; // 最大滚动范围
      final double viewPortHeight = _viewPortHeight!;
      final shouldOffset = index * _itemHeight - viewPortHeight + _itemHeight * 0.5; // 计算偏移量
      if (shouldOffset < maxScrollExtent) {
        controller.jumpTo(max(0.0, shouldOffset)); // 滚动到计算的偏移量位置
      } else {
        controller.jumpTo(maxScrollExtent); // 滚动到最大范围
      }
    }, '根据索引调整滚动位置时出错');
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
    LogUtil.safeExecute(() {
      _scrollController.dispose();
      _scrollChannelController.dispose();
      super.dispose();
    }, '释放资源时出错');
  }

  @override
  void didUpdateWidget(covariant ChannelDrawerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    LogUtil.safeExecute(() {
      // 如果频道或分组变化，重新初始化数据并加载EPG
      if (widget.playModel != oldWidget.playModel) {
        _initializeChannelData();
        _loadEPGMsg(widget.playModel);
        _calculateViewportHeight();
      }
    }, '更新小部件时出错');
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
    double groupWidth = 100 * context.read<ThemeProvider>().textScaleFactor; // 分组列表宽度
    double channelListWidth = isPortrait ? 120 : 160; // 频道列表宽度，竖屏下缩小
    double epgListWidth = isPortrait ? 180 : 290; // EPG列表宽度，横屏下增加

    double drawWidth = groupWidth + channelListWidth + (widget.isLandscape ? epgListWidth : 0);
    final screenWidth = MediaQuery.of(context).size.width;
    bool isShowEPG = drawWidth < screenWidth;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape ? drawWidth : screenWidth, // 横屏时使用计算的宽度
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent]), // 渐变背景
      ),
      child: Row(
        children: [
          _buildGroupListView(context, groupWidth, isTV), // 分组列表
          VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
          if (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
            SizedBox(
              width: channelListWidth, // 频道列表宽度
              child: _buildChannelListView(context, isPortrait, isTV), // 频道列表
            ),
          if (isShowEPG && _epgData != null && _epgData!.isNotEmpty)
            VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
          if (isShowEPG && _epgData != null && _epgData!.isNotEmpty)
            SizedBox(
              width: epgListWidth, // EPG显示区宽度
              child: _buildEPGListView(), // EPG列表
            ),
        ],
      ),
    );
  }

  // 构建分组列表视图
  Widget _buildGroupListView(BuildContext context, double width, bool isTV) {
    return SizedBox(
      width: width, // 动态调整宽度
      child: ListView.builder(
        cacheExtent: _itemHeight, // 预缓存区域
        padding: const EdgeInsets.only(bottom: 100.0), // 列表底部留白
        controller: _scrollController, // 使用滚动控制器
        itemBuilder: (context, index) => _buildGroupListTile(context, index, isTV), // 构建每个分组项
        itemCount: _keys.length, // 分组数目
      ),
    );
  }

  // 构建单个分组列表项
  Widget _buildGroupListTile(BuildContext context, int index, bool isTV) {
    final title = _keys[index];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        overlayColor: isTV ? WidgetStateProperty.all(Colors.greenAccent.withOpacity(0.2)) : null, // TV设备上的特殊样式
        onTap: () {
          LogUtil.safeExecute(() {
            if (_groupIndex != index) {
              setState(() {
                _groupIndex = index;
                final name = _values[_groupIndex].keys.first.toString();
                widget.onTapChannel?.call(_values[_groupIndex][name]); // 回调通知选中分组
              });
              _scrollChannelController.jumpTo(0); // 滚动到顶部
              if (context.mounted) {
                Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
              }
            } else {
              Scaffold.of(context).closeDrawer(); // 关闭抽屉
            }
          }, '分组列表项点击时出错');
        },
        onFocusChange: (focus) {
          LogUtil.safeExecute(() {
            if (focus && context.mounted) {
              Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
            }
          }, '焦点变化时出错');
        },
        splashColor: Colors.white.withOpacity(0.3),
        child: Ink(
          width: double.infinity,
          height: _itemHeight,
          decoration: BoxDecoration(
            gradient: _groupIndex == index ? LinearGradient(colors: [Colors.red.withOpacity(0.6), Colors.red.withOpacity(0.3)]) : null,
          ),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              title,
              style: TextStyle(color: _groupIndex == index ? Colors.red : Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  // 构建频道列表视图
  Widget _buildChannelListView(BuildContext context, bool isPortrait, bool isTV) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100.0),
      cacheExtent: _itemHeight, // 预缓存区域
      controller: _scrollChannelController, // 使用滚动控制器
      physics: const ScrollPhysics(),
      itemBuilder: (context, index) => _buildChannelListTile(context, index, isPortrait, isTV), // 构建每个频道项
      itemCount: _values[_groupIndex].length, // 频道数目
    );
  }

  // 构建单个频道列表项
  Widget _buildChannelListTile(BuildContext context, int index, bool isPortrait, bool isTV) {
    final name = _values[_groupIndex].keys.toList()[index].toString();
    final isSelect = widget.playModel?.title == name;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double maxWidth = isPortrait ? 120 : 160; // 设置最大宽度：竖屏为120，横屏为160
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth > maxWidth ? maxWidth : constraints.maxWidth, // 限制最大宽度
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              overlayColor: isTV ? WidgetStateProperty.all(Colors.greenAccent.withOpacity(0.2)) : null, // TV设备上的特殊样式
              canRequestFocus: isTV,
              onTap: () {
                LogUtil.safeExecute(() {
                  if (isSelect) {
                    Scaffold.of(context).closeDrawer();
                    return;
                  }
                  final newModel = _values[_groupIndex][name];
                  widget.onTapChannel?.call(newModel); // 回调通知选中频道
                  if (context.mounted) {
                    Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                  }
                }, '频道列表项点击时出错');
              },
              onFocusChange: (focus) {
                LogUtil.safeExecute(() {
                  if (focus && context.mounted) {
                    Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                  }
                }, '焦点变化时出错');
              },
              splashColor: Colors.white.withOpacity(0.3),
              child: Ink(
                width: double.infinity,
                height: _itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isSelect ? Colors.black38 : Colors.black26, // 为频道项添加透明的黑色背景
                  borderRadius: BorderRadius.circular(5), // 圆角
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    style: TextStyle(color: isSelect ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 构建EPG列表视图
  Widget _buildEPGListView() {
    return Column(
      children: [
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 10),  // 添加左边距，使标题不贴边
          decoration: BoxDecoration(
            color: Colors.black38, // 设置与EPG项一致的背景色
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            '节目单',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)), // 分割线
        Flexible(
          child: ScrollablePositionedList.builder(
            initialScrollIndex: _selEPGIndex, // 初始滚动到选中的节目项
            itemBuilder: (BuildContext context, int index) {
              final data = _epgData?[index];
              if (data == null) return const SizedBox.shrink(); // 如果没有数据则返回空视图
              final isSelect = index == _selEPGIndex; // 判断是否为选中的节目
              return Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.all(10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: isSelect ? Colors.black38 : Colors.black26, // 为EPG项添加透明的黑色背景
                  borderRadius: BorderRadius.circular(5), // 圆角
                ),
                child: Text(
                  '${data.start}-${data.end}\n${data.title}', // 显示节目开始时间、结束时间和标题
                  style: TextStyle(
                    fontWeight: isSelect ? FontWeight.bold : FontWeight.normal, // 选中项加粗显示
                    color: isSelect ? Colors.redAccent : Colors.white, // 选中项显示红色，其他为白色
                  ),
                ),
              );
            },
            itemCount: _epgData?.length ?? 0, // 节目单项数目
          ),
        ),
      ],
    );
  }
}
