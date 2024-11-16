import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:window_manager/window_manager.dart';
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/table_video_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'generated/l10n.dart';

// 创建 MobileVideoWidget 组件，用于在移动设备上显示视频内容
class MobileVideoWidget extends StatefulWidget {
  final BetterPlayerController? controller; // 视频播放器控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源的回调
  final String? toastString; // 提示信息字符串
  final bool? isLandscape; // 是否为横屏模式
  final Widget drawChild; // 传入的自定义子组件，通常为频道列表或相关界面
  final bool isBuffering; // 是否正在缓冲
  final bool isPlaying; // 是否正在播放
  final double aspectRatio; // 视频宽高比
  final GestureTapCallback onChangeSubSource; // 数据源更改回调
  final Function(String) toggleFavorite; 
  final bool Function(String) isChannelFavorite;
  final String currentChannelId; // 当前频道ID
  final String currentChannelLogo;  // 当前频道LOGO
  final String currentChannelTitle; // 当前频道名字
  final bool isAudio; // 新增音频模式参数

  // MobileVideoWidget 构造函数
  const MobileVideoWidget({
    Key? key,
    required this.controller,
    required this.drawChild,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.onChangeSubSource,
    required this.toggleFavorite, 
    required this.isChannelFavorite,
    required this.currentChannelId,
    required this.currentChannelLogo,
    required this.currentChannelTitle,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.isAudio = false, // 默认为视频模式
  }) : super(key: key);

  @override
  State<MobileVideoWidget> createState() => _MobileVideoWidgetState();
}

class _MobileVideoWidgetState extends State<MobileVideoWidget> {

  @override
  Widget build(BuildContext context) {
    // 优先使用传入的 isLandscape 参数，如果为空，则动态判断当前设备的方向
    bool isLandscape = widget.isLandscape ?? MediaQuery.of(context).orientation == Orientation.landscape;

    // 计算播放器固定高度
    final playerHeight = MediaQuery.of(context).size.width / (16 / 9);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,  // 顶部 AppBar 背景为黑色
        centerTitle: true,  // 标题居中显示
        title: Text(S.of(context).appName),  // 动态获取应用名称
        actions: [
          // 添加按钮
          IconButton(
            onPressed: () async {
              LogUtil.safeExecute(() async {
                // 如果不是移动设备，隐藏窗口标题栏
                if (!EnvUtil.isMobile) {
                  windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                }

                // 暂停视频播放，如果当前视频正在播放
                final wasPlaying = widget.controller?.isPlaying() ?? false;
                if (wasPlaying) {
                  widget.controller?.pause();
                }

                // 跳转到订阅页面
                await Navigator.of(context).pushNamed(RouterKeys.subScribe);

                // 返回后如果视频之前是播放状态，继续播放视频
                if (wasPlaying) {
                  widget.controller?.play();
                }

                // 检查缓存的 m3u 数据源是否存在且有效
                final m3uData = SpUtil.getString('m3u_cache', defValue: '');
                if (m3uData?.isEmpty ?? true || !isValidM3U(m3uData ?? '')) {
                  widget.onChangeSubSource();
                }

                // 恢复窗口标题栏显示
                if (!EnvUtil.isMobile) {
                  windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                }
              }, '执行操作按钮发生错误');
            },
            icon: const Icon(Icons.add),  // 添加频道的图标
          ),
          // 以控制图标间距
          const SizedBox(width: 5),
          // 设置按钮
          IconButton(
            onPressed: () async {
              LogUtil.safeExecute(() async {
                // 如果不是移动设备，隐藏窗口标题栏
                if (!EnvUtil.isMobile) {
                  windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                }

                // 暂停视频播放
                final wasPlaying = widget.controller?.isPlaying() ?? false;
                if (wasPlaying) {
                  widget.controller?.pause();
                }

                // 跳转到设置页面
                await Navigator.of(context).pushNamed(RouterKeys.setting);

                // 返回后如果视频之前是播放状态，继续播放视频
                if (wasPlaying) {
                  widget.controller?.play();
                }

                // 恢复窗口标题栏显示
                if (!EnvUtil.isMobile) {
                  windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                }
              }, '执行操作设置按钮发生错误');
            },
            icon: const Icon(Icons.settings_outlined),  // 设置图标
          ),
        ],
      ),
      body: Column(
        children: [
          // 设置固定高度以保持一致的视频显示区域
          Container(
            color: Colors.black, // 保持背景黑色，避免显示视频以外的区域
            width: double.infinity,
            height: playerHeight, // 固定播放器高度为16:9比例宽高比
            child: TableVideoWidget(
              controller: widget.controller,  // 传入视频控制器
              toastString: widget.toastString,  // 提示信息
              isLandscape: isLandscape,  // 动态判断是否为横屏
              aspectRatio: widget.controller?.videoPlayerController?.value.aspectRatio ?? widget.aspectRatio,  // 动态获取视频的宽高比
              isBuffering: widget.isBuffering,  // 是否缓冲
              isPlaying: widget.isPlaying,  // 是否正在播放
              drawerIsOpen: false,  // 抽屉菜单关闭状态
              toggleFavorite: widget.toggleFavorite,  // 传递收藏回调
              isChannelFavorite: widget.isChannelFavorite,  // 传递判断收藏状态回调
              currentChannelId: widget.currentChannelId,  // 传递当前频道ID
              currentChannelLogo: widget.currentChannelLogo,  // 传递当前频道LOGO
              currentChannelTitle: widget.currentChannelTitle,  // 传递当前频道名字
              changeChannelSources: widget.changeChannelSources,  // 传递切换频道源的回调
              isAudio: widget.isAudio, // 传递音频状态
            ),
          ),
          // 如果 toastString 为错误状态，显示空页面，否则显示传入的子组件
          Flexible(
            child: widget.toastString == 'UNKNOWN'
                ? EmptyPage(onRefresh: widget.onChangeSubSource)  // 空页面，点击刷新调用 onChangeSubSource 回调
                : widget.drawChild,  // 显示自定义的子组件
          ),
        ],
      ),
    );
  }

  // 判断 m3u 数据是否有效的简单方法
  bool isValidM3U(String data) {
    return data.contains('#EXTM3U');  // 检查是否包含 M3U 文件的必要标识
  }
}
