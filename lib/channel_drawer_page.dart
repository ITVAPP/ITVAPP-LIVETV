import 'dart:math';

import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'entity/playlist_model.dart';
import 'util/env_util.dart';

// 定义频道抽屉页面的状态组件
class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;  // 视频播放列表数据模型
  final PlayModel? playModel;  // 当前播放的视频数据模型
  final bool isLandscape;  // 是否横屏模式
  final Function(PlayModel? newModel)? onTapChannel;  // 频道点击回调函数

  const ChannelDrawerPage({super.key, this.videoMap, this.playModel, this.onTapChannel, this.isLandscape = true});

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> {
  final _scrollController = ScrollController();  // 控制组列表的滚动
  final _scrollChannelController = ScrollController();  // 控制频道列表的滚动
  final _epgScrollController = ItemScrollController();  // 控制EPG（节目单）列表的滚动
  List<EpgData>? _epgData;  // EPG数据
  int _selEPGIndex = 0;  // 选中的EPG索引

  final _viewPortKey = GlobalKey();  // 用于获取视窗的高度
  double? _viewPortHeight;  // 视窗高度

  late List<String> _keys;  // 组列表键
  late List<Map> _values;  // 组列表值
  late int _groupIndex = 0;  // 当前选中的组索引
  late int _channelIndex = 0;  // 当前选中的频道索引
  final _itemHeight = 50.0;  // 每个列表项的高度
  bool _isShowEPG = true;  // 是否显示EPG
  final isTV = EnvUtil.isTV();  // 判断是否是电视设备

  CancelToken? _cancelToken;  // 取消网络请求的Token

  // 加载EPG信息的方法
  _loadEPGMsg() async {
    if (!_isShowEPG) return;  // 如果不显示EPG，直接返回
    setState(() {
      _epgData = null;  // 清空现有的EPG数据
      _selEPGIndex = 0;  // 重置选中的EPG索引
    });
    _cancelToken?.cancel();  // 取消之前的请求
    _cancelToken = CancelToken();  // 创建新的取消Token
    final res = await EpgUtil.getEpg(widget.playModel, cancelToken: _cancelToken);  // 获取EPG数据
    if (res == null || res!.epgData == null || res!.epgData!.isEmpty) return;  // 如果EPG数据为空，直接返回
    _epgData = res.epgData!;  // 设置EPG数据
    final epgRangeTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');  // 获取当前时间格式
    final selectTimeData = _epgData!.where((element) => element.start!.compareTo(epgRangeTime) < 0).last.start;  // 获取选中的EPG时间
    final selIndex = _epgData!.indexWhere((element) => element.start == selectTimeData);  // 获取选中的EPG索引
    _selEPGIndex = selIndex;  // 设置选中的EPG索引
    setState(() {});  // 更新界面
  }

  @override
  void initState() {
    LogUtil.v('ChannelDrawerPage:isTV:::$isTV');  // 输出是否为电视设备的日志
    _keys = widget.videoMap?.playList?.keys.toList() ?? <String>[];  // 获取播放列表的组键
    _values = widget.videoMap?.playList?.values.toList().cast<Map>() ?? <Map>[];  // 获取播放列表的组值
    _groupIndex = _keys.indexWhere((element) => element == (widget.playModel?.group ?? ''));  // 找到当前播放组的索引
    if (_groupIndex != -1) {
      _channelIndex = _values[_groupIndex].keys.toList().indexWhere((element) => element == widget.playModel!.title);  // 找到当前播放频道的索引
    }
    if (_groupIndex == -1) {
      _groupIndex = 0;  // 如果没有找到，设置默认组索引为0
    }
    if (_channelIndex == -1) {
      _channelIndex = 0;  // 如果没有找到，设置默认频道索引为0
    }
    LogUtil.v('ChannelDrawerPage:initState:::groupIndex=$_groupIndex==channelIndex=$_channelIndex');  // 输出组和频道索引的日志
    Future.delayed(Duration.zero, () {
      if (_viewPortHeight == null) {
        final RenderBox? renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;  // 获取视窗渲染盒子
        final double height = renderBox?.size?.height ?? 0;  // 获取视窗高度
        _viewPortHeight = height * 0.5;  // 计算视窗的一半高度
        LogUtil.v('ChannelDrawerPage:initState:_viewPortHeight::height=$height');  // 输出视窗高度的日志
      }
      if (_groupIndex != 0) {  // 如果组索引不为0，滚动到相应位置
        final maxScrollExtent = _scrollController.position.maxScrollExtent;  // 获取最大滚动距离
        final shouldOffset = _groupIndex * _itemHeight - _viewPortHeight! + _itemHeight * 0.5;  // 计算滚动偏移
        if (shouldOffset < maxScrollExtent) {
          _scrollController.jumpTo(max(0.0, shouldOffset));  // 滚动到指定位置
        } else {
          _scrollController.jumpTo(maxScrollExtent);  // 滚动到最大位置
        }
      }
      if (_channelIndex != 0) {  // 如果频道索引不为0，滚动到相应位置
        final maxScrollExtent = _scrollChannelController.position.maxScrollExtent;  // 获取最大滚动距离
        final shouldOffset = _channelIndex * _itemHeight - _viewPortHeight! + _itemHeight * 0.5;  // 计算滚动偏移
        if (shouldOffset < maxScrollExtent) {
          _scrollChannelController.jumpTo(max(0.0, shouldOffset));  // 滚动到指定位置
        } else {
          _scrollChannelController.jumpTo(maxScrollExtent);  // 滚动到最大位置
        }
      }
    });
    _loadEPGMsg();  // 加载EPG信息
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();  // 释放滚动控制器
    _scrollChannelController.dispose();  // 释放滚动频道控制器
    _cancelToken?.cancel();  // 取消网络请求
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChannelDrawerPage oldWidget) {
    if (widget.playModel != oldWidget.playModel) {  // 如果播放模型发生变化
      setState(() {
        _epgData = null;  // 清空旧的EPG数据
        _selEPGIndex = 0; // 重置EPG索引
        _keys = widget.videoMap?.playList?.keys.toList() ?? <String>[];  // 更新组键
        _values = widget.videoMap?.playList?.values.toList().cast<Map>() ?? <Map>[];  // 更新组值
        int groupIndex = _keys.indexWhere((element) => element == widget.playModel?.group);  // 更新组索引
        int channelIndex = _channelIndex;
        if (groupIndex != -1) {
          channelIndex = _values[groupIndex].keys.toList().indexWhere((element) => element == widget.playModel?.title);  // 更新频道索引
        }
        if (groupIndex == -1) {
          groupIndex = 0;
        }
        if (channelIndex == -1) {
          channelIndex = 0;
        }
        _groupIndex = groupIndex;  // 设置新的组索引
        _channelIndex = channelIndex;  // 设置新的频道索引
        if (_groupIndex == 0 && _scrollController.positions.isNotEmpty) {
          Future.delayed(Duration.zero, () => _scrollController.jumpTo(0));  // 如果组索引为0，滚动到顶部
        }
        if (_channelIndex == 0 && _scrollChannelController.positions.isNotEmpty) {
          Future.delayed(Duration.zero, () => _scrollChannelController.jumpTo(0));  // 如果频道索引为0，滚动到顶部
        }
      });
      _loadEPGMsg();  // 加载新的EPG信息
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return _buildOpenDrawer();  // 构建抽屉组件
  }

  // 构建打开抽屉的UI
  Widget _buildOpenDrawer() {
    double screenWidth = MediaQuery.of(context).size.width;  // 获取屏幕宽度
    double drawWidth;  // 抽屉宽度
    double egpWidth;  // EPG宽度

    if (widget.isLandscape) {
      drawWidth = max(screenWidth * 0.6, 400);  // 如果是横屏模式，计算抽屉宽度
      egpWidth = drawWidth - 100 - 150;  // 计算EPG宽度
    } else {
      drawWidth = screenWidth;  // 如果是竖屏模式，抽屉宽度等于屏幕宽度
      egpWidth = (screenWidth - 80) / 2;  // 计算EPG宽度
    }

    _isShowEPG = (drawWidth + egpWidth) < screenWidth;  // 判断是否显示EPG
    if (_isShowEPG && _epgData != null && _epgData!.isNotEmpty) {
      drawWidth += egpWidth;  // 如果显示EPG，调整抽屉宽度
    }
    bool isShowEpgWidget = _isShowEPG && _epgData != null && _epgData!.isNotEmpty;  // 是否显示EPG组件

    return AnimatedContainer(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),  // 设置左边距
      width: drawWidth,  // 设置宽度
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.black, Colors.transparent])),  // 设置背景渐变
      duration: const Duration(milliseconds: 300),  // 设置动画持续时间
      curve: Curves.easeInOut,  // 设置动画曲线
      child: Row(children: [
        _buildGroupList(),  // 构建组列表
        VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)),  // 垂直分隔线
        if (_values.isNotEmpty && _values[_groupIndex].isNotEmpty)
          _buildChannelList(),  // 构建频道列表
        if (isShowEpgWidget)
          _buildEpgList(egpWidth),  // 构建EPG列表
      ]),
    );
  }

  // 构建组列表
  Widget _buildGroupList() {
    return SizedBox(
      width: widget.isLandscape ? 100 : 80,  // 根据屏幕方向设置宽度
      child: ListView.builder(
          itemExtent: _itemHeight,  // 设置列表项高度
          padding: const EdgeInsets.only(bottom: 100.0),  // 设置底部边距
          controller: _scrollController,  // 绑定滚动控制器
          itemBuilder: (context, index) {
            final title = _keys[index];  // 获取组标题
            return _buildGroupItem(title, index);  // 构建组列表项
          },
          itemCount: _keys.length),  // 设置列表项数
    );
  }

  // 构建组列表项
  Widget _buildGroupItem(String title, int index) {
    return Material(
      color: Colors.transparent,  // 设置背景透明
      child: InkWell(
        overlayColor: isTV ? WidgetStateProperty.all(Colors.greenAccent.withOpacity(0.2)) : null,  // 设置选中颜色
        onTap: () {
          setState(() {
            _epgData = null;  // 清空EPG数据
            _selEPGIndex = 0;  // 重置EPG索引
          });
          if (_groupIndex != index) {  // 如果组索引不相等
            setState(() {
              _groupIndex = index;  // 更新组索引
              final name = _values[_groupIndex].keys.toList()[0].toString();  // 获取频道名称
              final newModel = widget.videoMap!.playList![_keys[_groupIndex]]![name];  // 获取新的播放模型
              widget.onTapChannel?.call(newModel);  // 调用回调函数
            });
            _scrollChannelController.jumpTo(0);  // 滚动到顶部
            Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);  // 确保可见
          } else {
            Scaffold.of(context).closeDrawer();  // 关闭抽屉
          }
        },
        onFocusChange: (focus) async {
          if (focus) {
            Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);  // 确保可见
          }
        },
        splashColor: Colors.white.withOpacity(0.3),  // 设置点击效果
        child: Ink(
          width: double.infinity,
          height: _itemHeight,
          decoration: BoxDecoration(
            gradient: _groupIndex == index ? LinearGradient(colors: [Colors.red.withOpacity(0.6), Colors.red.withOpacity(0.3)]) : null,  // 设置选中背景
          ),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              title,  // 显示组标题
              style: TextStyle(color: _groupIndex == index ? Colors.red : Colors.white, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }

  // 构建频道列表
  Widget _buildChannelList() {
    return Expanded(
      child: ListView.builder(
          itemExtent: _itemHeight,  // 设置列表项高度
          padding: const EdgeInsets.only(bottom: 100.0),  // 设置底部边距
          controller: _scrollChannelController,  // 绑定滚动控制器
          physics: const ScrollPhysics(),
          itemBuilder: (context, index) {
            final name = _values[_groupIndex].keys.toList()[index].toString();  // 获取频道名称
            return _buildChannelItem(name, index);  // 构建频道列表项
          },
          itemCount: _values[_groupIndex].length),  // 设置列表项数
    );
  }

  // 构建频道列表项
  Widget _buildChannelItem(String name, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        overlayColor: isTV ? WidgetStateProperty.all(Colors.greenAccent.withOpacity(0.2)) : null,
        canRequestFocus: isTV,
        autofocus: isTV && _channelIndex == index,
        onTap: () async {
          if (widget.playModel?.title == name) {
            Scaffold.of(context).closeDrawer();  // 如果选中的频道已经在播放，关闭抽屉
            return;
          }
          final newModel = widget.videoMap!.playList![_keys[_groupIndex]]![name];  // 获取新的播放模型
          widget.onTapChannel?.call(newModel);  // 调用回调函数
          Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);  // 确保可见
        },
        onFocusChange: (focus) async {
          if (focus) {
            Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);  // 确保可见
          }
        },
        splashColor: Colors.white.withOpacity(0.3),
        child: Ink(
          width: double.infinity,
          height: _itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: widget.playModel?.title == name ? LinearGradient(colors: [Colors.red.withOpacity(0.3), Colors.transparent]) : null,  // 设置选中背景
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,  // 显示频道名称
                  style: TextStyle(color: widget.playModel?.title == name ? Colors.red : Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建EPG列表
  Widget _buildEpgList(double egpWidth) {
    return SizedBox(
      width: egpWidth,
      child: Material(
        color: Colors.black.withOpacity(0.1),
        child: Column(
          children: [
            Container(
              height: 44,
              alignment: Alignment.center,
              child: const Text(
                '节目单',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            VerticalDivider(width: 0.1, color: Colors.white.withOpacity(0.1)),  // 垂直分隔线
            Flexible(
              child: ScrollablePositionedList.builder(
                  initialScrollIndex: _selEPGIndex,  // 初始滚动到选中的EPG索引
                  itemScrollController: _epgScrollController,  // 绑定EPG滚动控制器
                  initialAlignment: 0.3,
                  physics: const ClampingScrollPhysics(),
                  padding: isTV ? EdgeInsets.only(bottom: MediaQuery.of(context).size.height) : null,
                  itemBuilder: (BuildContext context, int index) {
                    final data = _epgData![index];  // 获取EPG数据
                    final isSelect = index == _selEPGIndex;  // 判断是否选中
                    Widget child = Container(
                      constraints: const BoxConstraints(
                        minHeight: 40,
                      ),
                      padding: const EdgeInsets.all(10),
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${data.start}-${data.end}',  // 显示节目开始和结束时间
                              style: TextStyle(
                                  fontWeight: isSelect ? FontWeight.bold : FontWeight.normal,
                                  color: isSelect ? Colors.redAccent : Colors.white,
                                  fontSize: isSelect ? 17 : 15)),
                          Text('${data.title}',  // 显示节目标题
                              style: TextStyle(
                                  fontWeight: isSelect ? FontWeight.bold : FontWeight.normal,
                                  color: isSelect ? Colors.redAccent : Colors.white,
                                  fontSize: isSelect ? 17 : 15)),
                        ],
                      ),
                    );
                    if (isTV) {
                      child = InkWell(
                        onTap: () {},
                        onFocusChange: (bool isFocus) {
                          if (isFocus) {
                            _epgScrollController.scrollTo(index: index, alignment: 0.3, duration: const Duration(milliseconds: 220));  // 确保选中项可见
                          }
                        },
                        overlayColor: isTV ? WidgetStateProperty.all(Colors.greenAccent.withOpacity(0.2)) : null,
                        child: child,
                      );
                    }
                    return child;
                  },
                  itemCount: _epgData!.length),  // 设置EPG项数
            ),
          ],
        ),
      ),
    );
  }
}
