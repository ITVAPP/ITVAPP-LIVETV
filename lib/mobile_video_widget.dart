import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/table_video_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart'; 

import 'generated/l10n.dart';
import 'util/env_util.dart';

// 创建 MobileVideoWidget 组件，用于在移动设备上显示视频内容
class MobileVideoWidget extends StatefulWidget {
  final VideoPlayerController? controller; // 视频播放器控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源的回调
  final String? toastString; // 提示信息字符串
  final bool isLandscape; // 是否为横屏模式
  final Widget drawChild; // 传入的自定义子组件，通常为频道列表或相关界面
  final bool isBuffering; // 是否正在缓冲
  final bool isPlaying; // 是否正在播放
  final double aspectRatio; // 视频宽高比
  final GestureTapCallback onChangeSubSource; // 数据源更改回调

  // MobileVideoWidget 构造函数
  const MobileVideoWidget({
    Key? key,
    required this.controller,
    required this.drawChild,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.onChangeSubSource,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
  }) : super(key: key);

  @override
  State<MobileVideoWidget> createState() => _MobileVideoWidgetState();
}

// State 类，用于管理 MobileVideoWidget 的状态
class _MobileVideoWidgetState extends State<MobileVideoWidget> {

  @override
  Widget build(BuildContext context) {
    // 动态判断当前设备的方向，设置是否为横屏
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,  // 顶部 AppBar 背景为黑色
        centerTitle: true,  // 标题居中显示
        title: Text(S.current.appName),  // 动态获取应用名称
        actions: [
          // 添加按钮
          IconButton(
            onPressed: () async {
              // 如果不是移动设备，隐藏窗口标题栏
              if (!EnvUtil.isMobile) {
                windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
              }
              // 暂停视频播放
              final isPlaying = widget.controller?.value.isPlaying ?? false;
              if (isPlaying) {
                widget.controller?.pause();
              }
              // 跳转到订阅页面
              await Navigator.of(context).pushNamed(RouterKeys.subScribe);
              // 返回后继续播放视频
              widget.controller?.play();
              // 检查缓存的 m3u 数据源
              final m3uData = SpUtil.getString('m3u_cache', defValue: '') ?? '';
              // 如果数据为空，调用切换数据源的回调
              if (m3uData.isEmpty) {
                widget.onChangeSubSource();
              }
              // 恢复窗口标题栏显示
              if (!EnvUtil.isMobile) {
                windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
              }
            },
            icon: const Icon(Icons.add),  // 添加频道的图标
          ),
          // 设置按钮
          IconButton(
            onPressed: () async {
              // 如果不是移动设备，隐藏窗口标题栏
              if (!EnvUtil.isMobile) {
                windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
              }
              // 暂停视频播放
              widget.controller?.pause();
              // 跳转到设置页面
              await Navigator.of(context).pushNamed(RouterKeys.setting);
              // 返回后继续播放视频
              widget.controller?.play();
              // 恢复窗口标题栏显示
              if (!EnvUtil.isMobile) {
                windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
              }
            },
            icon: const Icon(Icons.settings_outlined),  // 设置图标
          ),
        ],
      ),
      body: Column(
        children: [
          // 视频播放器的展示区域，保持固定的宽高比
          AspectRatio(
            aspectRatio: widget.aspectRatio,  // 使用传入的宽高比
            child: TableVideoWidget(
              controller: widget.controller,  // 传入视频控制器
              toastString: widget.toastString,  // 提示信息
              isLandscape: isLandscape,  // 动态判断是否为横屏
              aspectRatio: widget.aspectRatio,  // 传递视频宽高比
              isBuffering: widget.isBuffering,  // 是否缓冲
              isPlaying: widget.isPlaying,  // 是否正在播放
              drawerIsOpen: false,  // 抽屉菜单关闭状态
            ),
          ),
          // 如果 toastString 为 'UNKNOWN' 显示空页面，否则显示传入的子组件
          Flexible(
            child: widget.toastString == 'UNKNOWN'
                ? EmptyPage(onRefresh: widget.onChangeSubSource)  // 空页面，点击刷新调用 onChangeSubSource 回调
                : widget.drawChild,  // 显示自定义的子组件
          ),
        ],
      ),
    );
  }
}
