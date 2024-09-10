import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:itvapp_live_tv/widget/volume_brightness_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'generated/l10n.dart';

class TableVideoWidget extends StatefulWidget {
  final VideoPlayerController? controller; // 视频控制器，用于控制视频播放
  final GestureTapCallback? changeChannelSources; // 切换频道源的回调函数
  final String? toastString; // 显示提示信息的字符串
  final bool isLandscape; // 标识是否为横屏模式
  final bool isBuffering; // 标识是否正在缓冲视频
  final bool isPlaying; // 标识视频是否正在播放
  final double aspectRatio; // 视频的宽高比
  final bool drawerIsOpen; // 标识抽屉菜单是否已打开

  const TableVideoWidget({
    super.key,
    required this.controller,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.drawerIsOpen,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
  });

  @override
  State<TableVideoWidget> createState() => _TableVideoWidgetState();
}

class _TableVideoWidgetState extends State<TableVideoWidget> with WindowListener {
  bool _isShowMenuBar = true; // 控制是否显示底部菜单栏

  @override
  void initState() {
    super.initState();
    // 非移动设备时，注册窗口监听器
    if (!EnvUtil.isMobile) windowManager.addListener(this);
  }

  @override
  void dispose() {
    // 非移动设备时，移除窗口监听器
    if (!EnvUtil.isMobile) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    // 当进入全屏模式时隐藏标题栏
    windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
  }

  @override
  void onWindowLeaveFullScreen() {
    // 离开全屏时，按横竖屏状态决定是否显示标题栏按钮
    windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
  }

  @override
  void onWindowResize() {
    // 调整窗口大小时根据横竖屏状态决定标题栏按钮的显示
    LogUtil.v('onWindowResize:::::${widget.isLandscape}');
    windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 视频播放区域
        GestureDetector(
          onTap: widget.isLandscape ? () => setState(() => _isShowMenuBar = !_isShowMenuBar) : null,
          // 双击播放/暂停视频
          onDoubleTap: () {
            widget.isPlaying ? widget.controller?.pause() : widget.controller?.play();
          },
          child: Container(
            alignment: Alignment.center,
            color: Colors.black, // 黑色背景
            // 如果视频控制器已初始化，显示视频播放器，否则显示占位背景
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 按宽高比调整播放器窗口
                      AspectRatio(
                        aspectRatio: widget.aspectRatio,
                        child: VideoPlayer(widget.controller!),
                      ),
                      // 如果视频未播放且抽屉未打开，显示播放按钮
                      if (!widget.isPlaying && !widget.drawerIsOpen)
                        GestureDetector(
                          onTap: () => widget.controller?.play(),
                          child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 50),
                        ),
                    ],
                  )
                // 如果没有视频控制器或未初始化，显示 VideoHoldBg 占位
                : VideoHoldBg(
                    videoController: widget.controller ?? VideoPlayerController.network(''),
                  ),
          ),
        ),
        // 显示时间和日期的组件，当抽屉菜单打开或显示菜单栏时才显示
        if (widget.drawerIsOpen || (!widget.drawerIsOpen && _isShowMenuBar && widget.isLandscape))
          const DatePositionWidget(),
        // 音量和亮度控制组件
        const VolumeBrightnessWidget(),
        // 横屏模式下的底部菜单栏按钮
        if (widget.isLandscape && !widget.drawerIsOpen)
          AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: _isShowMenuBar || !widget.isPlaying ? 20 : -50, // 根据播放状态调整菜单栏的显示/隐藏
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  const Spacer(),
                  // 频道列表按钮，点击打开抽屉菜单
                  IconButton(
                    tooltip: S.current.tipChannelList,
                    icon: const Icon(Icons.list_alt, color: Colors.white),
                    onPressed: () {
                      setState(() => _isShowMenuBar = false);
                      Scaffold.of(context).openDrawer(); // 打开抽屉
                    },
                  ),
                  const SizedBox(width: 6),
                  // 切换频道源按钮，调用 changeChannelSources 回调
                  IconButton(
                    tooltip: S.current.tipChangeLine,
                    icon: const Icon(Icons.legend_toggle, color: Colors.white),
                    onPressed: () {
                      setState(() => _isShowMenuBar = false);
                      widget.changeChannelSources?.call();
                    },
                  ),
                  const SizedBox(width: 6),
                  // 设置按钮，点击进入设置页面
                  IconButton(
                    tooltip: S.current.settings,
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SettingPage()),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  // 切换竖屏按钮，调整为竖屏模式
                  IconButton(
                    tooltip: S.current.portrait,
                    icon: const Icon(Icons.screen_rotation, color: Colors.white),
                    onPressed: () async {
                      if (EnvUtil.isMobile) {
                        // 移动设备设置为竖屏
                        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                      } else {
                        // 桌面设备调整窗口大小为竖屏
                        await windowManager.setSize(const Size(414, 414 * 16 / 9), animate: true);
                        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                        Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                      }
                    },
                  ),
                  if (!EnvUtil.isMobile) const SizedBox(width: 6),
                  // 全屏切换按钮，显示或退出全屏
                  if (!EnvUtil.isMobile)
                    IconButton(
                      tooltip: S.current.fullScreen,
                      icon: FutureBuilder<bool>(
                        future: windowManager.isFullScreen(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Icon(
                              snapshot.data! ? Icons.close_fullscreen : Icons.fit_screen_outlined,
                              color: Colors.white,
                            );
                          } else {
                            return const Icon(Icons.fit_screen_outlined, color: Colors.white);
                          }
                        },
                      ),
                      onPressed: () async {
                        final isFullScreen = await windowManager.isFullScreen();
                        windowManager.setFullScreen(!isFullScreen); // 切换全屏状态
                      },
                    ),
                ],
              ),
            ),
          ),
        // 非横屏时右下角的旋转按钮，点击切换为横屏
        if (!widget.isLandscape)
          Positioned(
            right: 15,
            bottom: 15,
            child: IconButton(
              tooltip: S.current.landscape,
              icon: const Icon(Icons.screen_rotation, color: Colors.white),
              onPressed: () async {
                if (EnvUtil.isMobile) {
                  // 移动设备切换为横屏
                  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                } else {
                  // 桌面设备调整窗口大小为横屏
                  await windowManager.setSize(const Size(800, 800 * 9 / 16), animate: true);
                  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                  Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                }
              },
            ),
          ),
      ],
    );
  }
}
