import 'dart:async';
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
  final String currentChannelId;
  final VoidCallback? onToggleDrawer;

  const TableVideoWidget({
    super.key,
    required this.controller,
    required this.isBuffering,
    required this.isPlaying,
    required this.aspectRatio,
    required this.drawerIsOpen,
    required this.toggleFavorite,
    required this.isChannelFavorite,
    required this.currentChannelId,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.onToggleDrawer,
  });

  @override
  State<TableVideoWidget> createState() => _TableVideoWidgetState();
}

class _TableVideoWidgetState extends State<TableVideoWidget> with WindowListener {
  // 样式常量
  final Color _iconColor = Colors.white;
  final Color _backgroundColor = Colors.black45;
  final BorderSide _iconBorderSide = const BorderSide(color: Colors.white);

  bool _isShowMenuBar = true; // 控制是否显示底部菜单栏
  bool _isShowPauseIcon = false; // 控制是否显示暂停图标
  bool _isShowPlayIcon = false; // 新增：控制播放图标显示
  Timer? _pauseIconTimer; // 用于控制暂停图标显示时间的计时器

  // 维护 drawerIsOpen 的本地状态
  bool _drawerIsOpen = false;

  // 统一的控制图标样式方法
  Widget _buildControlIcon({
    required IconData icon,
    Color backgroundColor = Colors.black,
    Color iconColor = Colors.white,
    VoidCallback? onTap,
  }) {
    Widget iconWidget = Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor.withOpacity(0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7),
              spreadRadius: 2,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10.0),
        child: Icon(
          icon,
          size: 78,
          color: iconColor.withOpacity(0.85),
        ),
      ),
    );

    // 如果有点击事件,则包装 GestureDetector
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: iconWidget,
      );
    }
    return iconWidget;
  }

  // 新增：处理选择键和确认键的点击事件
  Future<void> _handleSelectPress() async {
    // 1. 如果视频正在播放
    if (widget.isPlaying) {
      // 1.1 如果没有定时器在运行
      if (!(_pauseIconTimer?.isActive ?? false)) {
        // 1.11 如果正在播放中，显示暂停图标，并启动一个 3 秒的定时器
        setState(() {
          _isShowPauseIcon = true;
          _isShowPlayIcon = false; // 确保播放图标隐藏
        });
        _pauseIconTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isShowPauseIcon = false; // 在定时器结束时，隐藏暂停图标
            });
          }
        });
      } else {
        // 1.2 如果有定时器在运行
        await widget.controller?.pause(); // 暂停视频播放
        _pauseIconTimer?.cancel(); // 取消定时器
        setState(() {
          _isShowPauseIcon = false; // 隐藏暂停图标
          _isShowPlayIcon = true;   // 显示播放图标
        });
      }
    } else {
      // 1.12 如果正在暂停中，隐藏播放图标，播放视频
      await widget.controller?.play();
      setState(() {
        _isShowPlayIcon = false; // 隐藏播放图标
      });
    }

    // 2. 仅在横屏模式下切换菜单栏显示状态，菜单栏显示同时显示时间
    if (widget.isLandscape) {
      setState(() {
        _isShowMenuBar = !_isShowMenuBar;
      });
    }
  }

  // 创建一个私有方法，用于关闭抽屉
  void _closeDrawerIfOpen() {
    if (_drawerIsOpen) {
      setState(() {
        _drawerIsOpen = false;  // 更新本地状态，确保抽屉关闭
        widget.onToggleDrawer?.call();  // 调用关闭抽屉的回调
      });
    }
  }
  
@override
  void initState() {
    super.initState();
    _drawerIsOpen = widget.drawerIsOpen; // 初始状态设置为 widget 传递的值

    // 非移动设备时，注册窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当父组件的 drawerIsOpen 状态变化时，同步本地 _drawerIsOpen 状态
    if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      setState(() {
        _drawerIsOpen = widget.drawerIsOpen;
      });
    }
  }

  @override
  void dispose() {
    // 非移动设备时，移除窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    _pauseIconTimer?.cancel(); // 取消计时器
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
      _closeDrawerIfOpen();  // 调用封装的关闭抽屉方法
    }, '调整窗口大小时发生错误');
  }

  // 收藏按钮的逻辑
  Widget buildFavoriteButton(String currentChannelId, bool showBackground) {
    return Container(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: widget.isChannelFavorite(currentChannelId) ? S.current.removeFromFavorites : S.current.addToFavorites,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor,
                side: _iconBorderSide,
              )
            : null,
        icon: Icon(
          widget.isChannelFavorite(currentChannelId) ? Icons.favorite : Icons.favorite_border,
          color: widget.isChannelFavorite(currentChannelId) ? Colors.red : _iconColor,
          size: 24, // 固定图标大小
        ),
        onPressed: () {
          widget.toggleFavorite(currentChannelId);
          setState(() {});
        },
      ),
    );
  }

  // 切换频道源按钮的逻辑
  Widget buildChangeChannelSourceButton(bool showBackground) {
    return Container(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: S.of(context).tipChangeLine,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor,
                side: _iconBorderSide,
              )
            : null,
        icon: Icon(
          Icons.legend_toggle,
          color: _iconColor,
          size: 24, // 固定图标大小
        ),
        onPressed: () {
          if (widget.isLandscape) {
            _closeDrawerIfOpen();
            setState(() => _isShowMenuBar = false);
          }
          widget.changeChannelSources?.call();
        },
      ),
    );
  }
  
@override
  Widget build(BuildContext context) {
    String currentChannelId = widget.currentChannelId;
    // 计算播放器容器的高度
    final playerHeight = MediaQuery.of(context).size.width / (16 / 9);

    return Stack(
      children: [
        // 视频播放区域
        GestureDetector(
          onTap: _drawerIsOpen ? null : () => _handleSelectPress(),
          onDoubleTap: _drawerIsOpen ? null : () {
            LogUtil.safeExecute(() {
              widget.isPlaying ? widget.controller?.pause() : widget.controller?.play();
            }, '双击播放/暂停发生错误');
          },
          child: Container(
            alignment: Alignment.center,
            color: Colors.black,
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 竖屏模式下的视频显示
                      if (!widget.isLandscape)
                        Container(
                          width: double.infinity,
                          height: playerHeight,
                          child: Stack(
                            children: [
                              // 视频容器
                              Container(
                                width: double.infinity,
                                height: playerHeight,
                                child: Center(
                                  child: SizedBox.expand(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: playerHeight * widget.controller!.value.aspectRatio,
                                        height: playerHeight,
                                        child: VideoPlayer(widget.controller!),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // 黑色背景填充
                              if (widget.controller!.value.aspectRatio < 16/9)
                                Container(
                                  width: double.infinity,
                                  height: playerHeight,
                                  color: Colors.black,
                                ),
                              // 视频显示
                              Center(
                                child: SizedBox(
                                  height: playerHeight,
                                  child: AspectRatio(
                                    aspectRatio: widget.controller!.value.aspectRatio,
                                    child: VideoPlayer(widget.controller!),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // 横屏模式下的视频显示
                      else
                        AspectRatio(
                          aspectRatio: widget.controller!.value.aspectRatio,
                          child: VideoPlayer(widget.controller!),
                        ),
                      // 播放控制图标
                      if (_isShowPlayIcon || (!widget.isPlaying && !_drawerIsOpen))
                        _buildControlIcon(
                          icon: Icons.play_arrow,
                          onTap: () => _handleSelectPress(),
                        ),
                      if (_isShowPauseIcon)
                        _buildControlIcon(
                          icon: Icons.pause,
                        ),
                    ],
                  )
                : VideoHoldBg(
                    toastString: _drawerIsOpen ? '' : widget.toastString,
                    showBingBackground: false,
                  ),
          ),
        ),

        // 音量和亮度控制组件
        const VolumeBrightnessWidget(),

        // 时间显示
        if (_isShowMenuBar && !_drawerIsOpen) 
          const DatePositionWidget(),

        // 横屏模式下的底部菜单栏
        if (widget.isLandscape && !_drawerIsOpen && _isShowMenuBar) ...[
          AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: _isShowMenuBar ? 20 : -50,
            duration: const Duration(milliseconds: 100),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: S.of(context).tipChannelList,
                    style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                    icon: Icon(Icons.list_alt, color: _iconColor),
                    onPressed: () {
                      LogUtil.safeExecute(() {
                        setState(() {
                          _isShowMenuBar = false;
                          widget.onToggleDrawer?.call();
                        });
                      }, '切换频道发生错误');
                    },
                  ),
                  const SizedBox(width: 3),
                  buildFavoriteButton(currentChannelId, true),
                  const SizedBox(width: 3),
                  buildChangeChannelSourceButton(true),
                  const SizedBox(width: 3),
                  IconButton(
                    tooltip: S.of(context).settings,
                    style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                    icon: Icon(Icons.settings, color: _iconColor),
                    onPressed: () {
                      _closeDrawerIfOpen();
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
                  IconButton(
                    tooltip: S.of(context).portrait,
                    style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                    icon: Icon(Icons.screen_rotation, color: _iconColor),
                    onPressed: () async {
                      LogUtil.safeExecute(() async {
                        if (EnvUtil.isMobile) {
                          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                        } else {
                          await windowManager.setSize(const Size(414, 414 * 16 / 9), animate: true);
                          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                          Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                        }
                      }, '切换为竖屏时发生错误');
                    },
                  ),
                  if (!EnvUtil.isMobile) const SizedBox(width: 6),
                  if (!EnvUtil.isMobile)
                    IconButton(
                      tooltip: S.of(context).fullScreen,
                      style: IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide),
                      icon: FutureBuilder<bool>(
                        future: windowManager.isFullScreen(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Icon(
                              snapshot.data! ? Icons.close_fullscreen : Icons.fit_screen_outlined,
                              color: _iconColor,
                            );
                          } else {
                            return Icon(Icons.fit_screen_outlined, color: _iconColor);
                          }
                        },
                      ),
                      onPressed: () async {
                        LogUtil.safeExecute(() async {
                          final isFullScreen = await windowManager.isFullScreen();
                          windowManager.setFullScreen(!isFullScreen);
                        }, '切换为全屏时发生错误');
                      },
                    ),
                ],
              ),
            ),
          ),
        ],

        // 竖屏模式下的右下角控制按钮
        if (!widget.isLandscape)
          Positioned(
            right: 8,
            bottom: 8,  // 固定位置在播放器底部
            child: Container(
              width: 32,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildFavoriteButton(currentChannelId, false),
                  const SizedBox(height: 5),
                  buildChangeChannelSourceButton(false),
                  const SizedBox(height: 5),
                  Container(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      tooltip: S.of(context).landscape,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        if (EnvUtil.isMobile) {
                          SystemChrome.setPreferredOrientations([
                            DeviceOrientation.landscapeLeft,
                            DeviceOrientation.landscapeRight
                          ]);
                          return;
                        }
                        await windowManager.setSize(const Size(800, 800 * 9 / 16), animate: true);
                        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
                        Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                      },
                      icon: Icon(
                        Icons.screen_rotation,
                        color: _iconColor,
                        size: 24, // 固定图标大小
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
