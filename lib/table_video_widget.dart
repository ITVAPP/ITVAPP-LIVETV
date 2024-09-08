import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
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
  final VideoPlayerController? controller; // 视频控制器
  final GestureTapCallback? changeChannelSources; // 更改频道源的回调
  final String? toastString; // 提示信息字符串
  final bool isLandscape; // 是否处于横屏模式
  final bool isBuffering; // 是否正在缓冲
  final bool isPlaying; // 是否正在播放视频
  final double aspectRatio; // 视频宽高比
  final bool drawerIsOpen; // 是否打开了抽屉菜单

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
    // 非移动端注册窗口监听器
    if (!EnvUtil.isMobile) windowManager.addListener(this);
  }

  @override
  void dispose() {
    // 非移动端移除窗口监听器
    if (!EnvUtil.isMobile) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    super.onWindowEnterFullScreen();
    // 全屏时隐藏标题栏，并显示窗口按钮
    windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
  }

  @override
  void onWindowLeaveFullScreen() {
    // 离开全屏时，根据是否横屏设置窗口标题栏样式和按钮可见性
    if (widget.isLandscape) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    } else {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }
  }

  @override
  void onWindowResize() {
    // 调整窗口大小时记录日志，并根据是否横屏调整窗口标题栏样式
    LogUtil.v('onWindowResize:::::${widget.isLandscape}');
    if (widget.isLandscape) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    } else {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 视频播放器区域
        GestureDetector(
          onTap: widget.isLandscape
              ? () {
                  // 横屏时点击播放器切换菜单栏显示状态
                  _isShowMenuBar = !_isShowMenuBar;
                  setState(() {});
                }
              : null,
          onDoubleTap: () {
            // 双击播放或暂停视频
            if (widget.isPlaying) {
              widget.controller?.pause();
            } else {
              widget.controller?.play();
            }
          },
          child: Container(
            alignment: Alignment.center,
            color: Colors.black, // 视频背景颜色设置为黑色
            // 检查是否有视频控制器，并且是否已初始化
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 播放器窗口，调整为视频的宽高比
                      AspectRatio(
                        aspectRatio: widget.aspectRatio,
                        child: SizedBox(
                          width: double.infinity,
                          child: VideoPlayer(widget.controller!),
                        ),
                      ),
                      // 如果视频未播放且抽屉未打开，显示播放按钮
                      if (!widget.isPlaying && !widget.drawerIsOpen)
                        GestureDetector(
                          onTap: () {
                            widget.controller?.play();
                          },
                          child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 50),
                        ),
                      // 如果正在缓冲且抽屉未打开，显示缓冲动画
                      if (widget.isBuffering && !widget.drawerIsOpen) const SpinKitSpinningLines(color: Colors.white),
                    ],
                  )
                // 如果没有控制器或视频未初始化，显示 VideoHoldBg
                : widget.controller != null
                    ? VideoHoldBg(
                        toastString: widget.drawerIsOpen ? '' : widget.toastString,
                        videoController: widget.controller!,
                      )
                    : const Center(child: Text("No video controller available", style: TextStyle(color: Colors.white))),
          ),
        ),
        // 时间与日期位置显示组件
        if (widget.drawerIsOpen || (!widget.drawerIsOpen && _isShowMenuBar && widget.isLandscape))
          const DatePositionWidget(),
        // 音量和亮度控制组件
        const VolumeBrightnessWidget(),

        // 横屏模式下的底部菜单栏按钮
        if (widget.isLandscape && !widget.drawerIsOpen)
          AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: _isShowMenuBar || !widget.isPlaying ? 20 : -50, // 控制菜单栏的显隐
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  const Spacer(),
                  // 频道列表按钮
                  IconButton(
                    tooltip: S.current.tipChannelList,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.white),
                    ),
                    icon: const Icon(Icons.list_alt, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isShowMenuBar = false; // 隐藏菜单栏
                      });
                      Scaffold.of(context).openDrawer(); // 打开抽屉菜单
                    },
                  ),
                  const SizedBox(width: 6),
                  // 切换频道源按钮
                  IconButton(
                    tooltip: S.current.tipChangeLine,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.white),
                    ),
                    icon: const Icon(Icons.legend_toggle, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isShowMenuBar = false;
                      });
                      widget.changeChannelSources?.call(); // 调用更改频道源回调
                    },
                  ),
                  const SizedBox(width: 6),
                  // 设置按钮
                  IconButton(
                    tooltip: S.current.settings,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.white),
                    ),
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () {
                      // 打开设置页面逻辑
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SettingPage()), // 假设有SettingPage
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  // 切换竖屏按钮
                  IconButton(
                    tooltip: S.current.portrait,
                    onPressed: () async {
                      // 移动设备设置为竖屏，否则调整窗口大小为竖屏比例
                      if (EnvUtil.isMobile) {
                        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                        return;
                      }
                      await windowManager.setSize(const Size(414, 414 * 16 / 9), animate: true);
                      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                      Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.white),
                    ),
                    icon: const Icon(Icons.screen_rotation, color: Colors.white),
                  ),
                  if (!EnvUtil.isMobile) const SizedBox(width: 6),
                  // 全屏切换按钮
                  if (!EnvUtil.isMobile)
                    IconButton(
                      tooltip: S.current.fullScreen,
                      onPressed: () async {
                        // 切换全屏状态
                        final isFullScreen = await windowManager.isFullScreen();
                        LogUtil.v('isFullScreen:::::$isFullScreen');
                        windowManager.setFullScreen(!isFullScreen);
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.white),
                      ),
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
                    ),
                ],
              ),
            ),
          ),
        // 非横屏时右下角的旋转按钮，点击切换横屏
        if (!widget.isLandscape)
          Positioned(
            right: 15,
            bottom: 15,
            child: IconButton(
              tooltip: S.current.landscape,
              onPressed: () async {
                // 移动设备切换为横屏，否则调整窗口大小为横屏比例
                if (EnvUtil.isMobile) {
                  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                  return;
                }
                await windowManager.setSize(const Size(800, 800 * 9 / 16), animate: true);
                await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
              },
              style: IconButton.styleFrom(backgroundColor: Colors.black45, iconSize: 20),
              icon: const Icon(Icons.screen_rotation, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
