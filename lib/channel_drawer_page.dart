import 'dart:math';
import 'dart:async'; 
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:debounce_throttle/debounce_throttle.dart'; // 引入 debounce 库
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';

// 频道列表组件，提取到独立组件
class ChannelListView extends StatelessWidget {
  final List<Map<String, PlayModel>> values;
  final int groupIndex;
  final Function(PlayModel?) onTapChannel;
  final bool isPortrait;
  final bool isTV;
  final ScrollController scrollChannelController;

  const ChannelListView({
    required this.values,
    required this.groupIndex,
    required this.onTapChannel,
    required this.isPortrait,
    required this.isTV,
    required this.scrollChannelController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100.0),
      cacheExtent: 50.0, // 预缓存区域
      controller: scrollChannelController, // 使用滚动控制器
      physics: const ScrollPhysics(),
      itemBuilder: (context, index) => _buildChannelListTile(context, index),
      itemCount: values[groupIndex].length, // 频道数目
    );
  }

  // 构建单个频道列表项
  Widget _buildChannelListTile(BuildContext context, int index) {
    final name = values[groupIndex].keys.toList()[index].toString();
    final isSelect = context.read<PlayModel?>()?.title == name;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double maxWidth = isPortrait ? 120 : 160; // 设置最大宽度
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth > maxWidth ? maxWidth : constraints.maxWidth, // 限制最大宽度
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              overlayColor: isTV
                  ? WidgetStateProperty.all(Colors.greenAccent.withOpacity(0.2))
                  : null,
              canRequestFocus: isTV,
              onTap: () {
                if (isSelect) {
                  Scaffold.of(context).closeDrawer();
                  return;
                }
                final newModel = values[groupIndex][name];
                onTapChannel(newModel);
              },
              splashColor: Colors.white.withOpacity(0.3),
              child: Ink(
                width: double.infinity,
                height: 50.0,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelect ? Colors.black38 : Colors.black26,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isSelect ? Colors.redAccent : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// EPG 列表组件，提取到独立组件
class EpgListView extends StatelessWidget {
  final List<EpgData>? epgData;
  final int selEPGIndex;

  const EpgListView({
    required this.epgData,
    required this.selEPGIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 8), // 添加左边距
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            S.of(context).programListTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        VerticalDivider(
          width: 0.1,
          color: Colors.white.withOpacity(0.1),
        ),
        Flexible(
          child: ScrollablePositionedList.builder(
            initialScrollIndex: selEPGIndex,
            itemBuilder: (BuildContext context, int index) {
              final data = epgData?[index];
              if (data == null) return const SizedBox.shrink();
              final isSelect = index == selEPGIndex;
              return Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.all(10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: isSelect ? Colors.black38 : Colors.black26,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${data.start}-${data.end}\n${data.title}',
                  style: TextStyle(
                    fontWeight: isSelect ? FontWeight.bold : FontWeight.normal,
                    color: isSelect ? Colors.redAccent : Colors.white,
                  ),
                ),
              );
            },
            itemCount: epgData?.length ?? 0,
          ),
        ),
      ],
    );
  }
}

class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final bool isLandscape;
  final Function(PlayModel? newModel)? onTapChannel;

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
  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;

  final GlobalKey _viewPortKey = GlobalKey();
  double? _viewPortHeight;

  late List<String> _keys;
  late List<Map<String, PlayModel>> _values;
  late int _groupIndex;
  late int _channelIndex;
  final double _itemHeight = 50.0;

  // 使用 debounce 库代替 Timer 防抖逻辑
  final _debouncer = Debouncer(const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    LogUtil.safeExecute(() {
      _initializeChannelData();
      _calculateViewportHeight();
      _loadEPGMsg(widget.playModel);
    }, '初始化频道数据时发生错误');
  }

  // 初始化频道数据
  void _initializeChannelData() {
    LogUtil.safeExecute(() {
      _keys = widget.videoMap?.playList?.keys.toList() ?? <String>[];
      _values = widget.videoMap?.playList?.values
              .toList()
              .cast<Map<String, PlayModel>>() ??
          <Map<String, PlayModel>>[];

      for (int i = 0; i < _values.length; i++) {
        var sortedChannels = Map<String, PlayModel>.fromEntries(
          _values[i].entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)),
        );
        _values[i] = sortedChannels;
      }
      _groupIndex = _keys.indexOf(widget.playModel?.group ?? '');
      _channelIndex = _groupIndex != -1
          ? _values[_groupIndex].keys
              .toList()
              .indexOf(widget.playModel?.title ?? '')
          : 0;
      if (_groupIndex == -1) _groupIndex = 0;
      if (_channelIndex == -1) _channelIndex = 0;
    }, '初始化频道数据时出错');
  }

  void _onTapChannelDebounced(PlayModel? newModel) {
    _debouncer.call(() {
      widget.onTapChannel?.call(newModel); // 防抖逻辑，控制多次点击
    });
  }

  // 渲染方法保持不变
  @override
  Widget build(BuildContext context) {
    bool isTV = context.read<ThemeProvider>().isTV;
    bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double groupWidth = 100 * context.read<ThemeProvider>().textScaleFactor;
    double channelListWidth = isPortrait ? 120 : 160;
    double epgListWidth = isPortrait ? 180 : 290;
    double drawWidth = groupWidth + channelListWidth + (widget.isLandscape ? epgListWidth : 0);
    final screenWidth = MediaQuery.of(context).size.width;
    bool isShowEPG = drawWidth < screenWidth;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape ? drawWidth : screenWidth,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent]),
      ),
      child: Row(
        children: [
          _buildGroupListView(context, groupWidth, isTV), // 分组列表
          VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)),
          if (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
            SizedBox(
              width: channelListWidth,
              child: ChannelListView(
                values: _values,
                groupIndex: _groupIndex,
                onTapChannel: _onTapChannelDebounced,
                isPortrait: isPortrait,
                isTV: isTV,
                scrollChannelController: _scrollChannelController,
              ),
            ),
          if (isShowEPG && _epgData != null && _epgData!.isNotEmpty)
            VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)),
          if (isShowEPG && _epgData != null && _epgData!.isNotEmpty)
            SizedBox(
              width: epgListWidth,
              child: EpgListView(
                epgData: _epgData,
                selEPGIndex: _selEPGIndex,
              ),
            ),
        ],
      ),
    );
  }
}
