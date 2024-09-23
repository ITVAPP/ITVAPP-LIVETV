import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:itvapp_live_tv/widget/volume_brightness_widget.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';
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
  final Function(String) toggleFavorite; // 添加/取消收藏的回调函数
  final bool Function(String) isChannelFavorite; // 判断当前频道是否已收藏

  const TableVideoWidget({
    super.key,
    required this.controller,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.drawerIsOpen,
    required this.toggleFavorite,
    required this.isChannelFavorite,
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
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  @override
  void dispose() {
    // 非移动设备时，移除窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    LogUtil.safeExecute(() {
      // 当进入全屏模式时隐藏标题栏
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    LogUtil.safeExecute(() {
      // 离开全屏时，按横竖屏状态决定是否显示标题栏按钮
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) {
        // 确保移动设备更新屏幕方向
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }, '离开全屏时发生错误');
  }

  @override
  void onWindowResize() {
    LogUtil.safeExecute(() {
      // 调整窗口大小时根据横竖屏状态决定标题栏按钮的显示
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);

      // 在窗口大小变化时关闭抽屉，避免布局错乱
      if (Scaffold.of(context).isDrawerOpen) {
        Navigator.pop(context);
      }
    }, '调整窗口大小时发生错误');
  }

  // 将收藏按钮的逻辑提取为一个独立的函数，以便在横屏和竖屏中复用
  Widget buildFavoriteButton(String currentChannelId) {
    return IconButton(
      tooltip: widget.isChannelFavorite(currentChannelId) ? '取消收藏' : '添加收藏',
      style: IconButton.styleFrom(
        backgroundColor: Colors.black45, // 与其他按钮一致的背景颜色
        side: const BorderSide(color: Colors.white), // 与其他按钮一致的边框
      ),
      icon: Icon(
        widget.isChannelFavorite(currentChannelId) ? Icons.favorite : Icons.favorite_border,
        color: widget.isChannelFavorite(currentChannelId) ? Colors.red : Colors.white,
      ),
      onPressed: () {
        widget.toggleFavorite(currentChannelId); // 切换收藏状态
        setState(() {}); // 刷新UI以更新图标状态
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentChannelId = 'exampleChannelId'; // 获取当前播放频道的ID，实际需要传递或获取该ID

    return Stack(
      children: [
        // 视频播放区域
        GestureDetector(
          onTap: widget.isLandscape
              ? () {
                  if (_isShowMenuBar) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() => _isShowMenuBar = !_isShowMenuBar);
                    });
                  } else {
                    setState(() => _isShowMenuBar = !_isShowMenuBar);
                  }
                }
              : null,
          // 双击播放/暂停视频
          onDoubleTap: () {
            LogUtil.safeExecute(() {
              widget.isPlaying ? widget.controller?.pause() : widget.controller?.play();
            }, '双击播放/暂停发生错误');
          },
          child: Container(
            alignment: Alignment.center,
            color: Colors.black, // 黑色背景
            // 如果视频控制器已初始化，显示视频播放器，否则显示占位背景
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 仅在视频初始化后设置宽高比
                      AspectRatio(
                        aspectRatio: widget.controller!.value.aspectRatio, // 动态获取视频的实际宽高比
                        child: VideoPlayer(widget.controller!),
                      ),
                      // 如果视频未播放且抽屉未打开，显示播放按钮
                      if (!widget.isPlaying)
                        GestureDetector(
                          onTap: () {
                            LogUtil.safeExecute(() => widget.controller?.play(), '显示播放按钮发生错误');
                          },
                          child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 50),
                        ),
                    ],
                  )
                // 如果没有视频控制器或未初始化，显示 VideoHoldBg 占位
                : VideoHoldBg(
                    videoController: widget.controller ?? VideoPlayerController.network(''),
                    toastString: widget.drawerIsOpen ? '' : widget.toastString, // 提示缓冲或加载状态
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
                    style: IconButton.styleFrom(backgroundColor: Colors.black45, side: const BorderSide(color: Colors.white)),
                    icon: const Icon(Icons.list_alt, color: Colors.white),
                    onPressed: () {
                      LogUtil.safeExecute(() {
                        setState(() => _isShowMenuBar = false);
                        Scaffold.of(context).openDrawer(); // 打开抽屉
                      }, '切换频道发生错误');
                    },
                  ),
                  const SizedBox(width: 3),
                  // 调用复用的收藏按钮
                  buildFavoriteButton(currentChannelId),
                  const SizedBox(width: 3),
                  // 切换频道源按钮，调用 changeChannelSources 回调
                  IconButton(
                    tooltip: S.current.tipChangeLine,
                    style: IconButton.styleFrom(backgroundColor: Colors.black45, side: const BorderSide(color: Colors.white)),
                    icon: const Icon(Icons.legend_toggle, color: Colors.white),
                    onPressed: () {
                      LogUtil.safeExecute(() {
                        setState(() => _isShowMenuBar = false);
                        widget.changeChannelSources?.call();
                      }, '切换频道源按钮发生错误');
                    },
                  ),
                  const SizedBox(width: 3),
                  // 设置按钮，点击进入设置页面
                  IconButton(
                    tooltip: S.current.settings,
                    style: IconButton.styleFrom(backgroundColor: Colors.black45, side: const BorderSide(color: Colors.white)),
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () {
                      LogUtil.safeExecute(() {
                        setState(() => _isShowMenuBar = false);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SettingPage()),
                        );
                      }, '进入设置页面发生错误');
                    },
                  ),
                  const SizedBox(width: 3),
                  // 切换竖屏按钮，调整为竖屏模式
                  IconButton(
                    tooltip: S.current.portrait,
                    style: IconButton.styleFrom(backgroundColor: Colors.black45, side: const BorderSide(color: Colors.white)),
                    icon: const Icon(Icons.screen_rotation, color: Colors.white),
                    onPressed: () async {
                      LogUtil.safeExecute(() async {
                        if (EnvUtil.isMobile) {
                          // 移动设备设置为竖屏
                          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                        } else {
                          // 桌面设备调整窗口大小为竖屏
                          await windowManager.setSize(const Size(414, 414 * 16 / 9), animate: true);
                          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                          Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                        }
                      }, '切换为竖屏时发生错误');
                    },
                  ),
                  if (!EnvUtil.isMobile) const SizedBox(width: 6),
                  // 全屏切换按钮，显示或退出全屏
                  if (!EnvUtil.isMobile)
                    IconButton(
                      tooltip: S.current.fullScreen,
                      style: IconButton.styleFrom(backgroundColor: Colors.black45, side: const BorderSide(color: Colors.white)),
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
                        LogUtil.safeExecute(() async {
                          final isFullScreen = await windowManager.isFullScreen();
                          windowManager.setFullScreen(!isFullScreen); // 切换全屏状态
                        }, '切换为全屏时发生错误');
                      },
                    ),
                ],
              ),
            ),
          ),
        // 非横屏时右下角的旋转按钮和收藏按钮
        if (!widget.isLandscape)
          Positioned(
            right: 12,
            bottom: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 收藏按钮
                buildFavoriteButton(currentChannelId),
                const SizedBox(height: 5),
                // 旋转按钮
                IconButton(
                  tooltip: S.current.landscape,
                  onPressed: () async {
                    if (EnvUtil.isMobile) {
                      SystemChrome.setPreferredOrientations(
                          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                      return;
                    }
                    await windowManager.setSize(const Size(800, 800 * 9 / 16), animate: true);
                    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                    Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                  },
                  style: IconButton.styleFrom(backgroundColor: Colors.black45, iconSize: 20),
                  icon: const Icon(Icons.screen_rotation, color: Colors.white),
                ),
              ],
            ),
          )
      ],
    );
  }
}
