import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:itvapp_live_tv/widget/volume_brightness_widget.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'generated/l10n.dart';

// 视频播放器状态管理类
class VideoPlayerState {
  bool isShowMenuBar;
  bool isShowPauseIcon;
  bool isShowPlayIcon;
  bool drawerIsOpen;
  Timer? pauseIconTimer;

  VideoPlayerState({
    this.isShowMenuBar = true,
    this.isShowPauseIcon = false,
    this.isShowPlayIcon = false,
    this.drawerIsOpen = false,
    this.pauseIconTimer,
  });

  void dispose() {
    pauseIconTimer?.cancel();
  }
}

class TableVideoWidget extends StatefulWidget {
  final BetterPlayerController? controller; // 视频控制器，用于控制视频播放
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
  final String currentChannelLogo;
  final String currentChannelTitle;
  final VoidCallback? onToggleDrawer;
  final bool isAudio; // 音频模式参数

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
    required this.currentChannelLogo,
    required this.currentChannelTitle,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.onToggleDrawer,
    this.isAudio = false,
  });

  @override
  State<TableVideoWidget> createState() => _TableVideoWidgetState();
}

class _TableVideoWidgetState extends State<TableVideoWidget> with WindowListener {
  // 状态管理实例
  late final VideoPlayerState _playerState;

  // 样式常量
  final Color _iconColor = Colors.white;
  final Color _backgroundColor = Colors.black45;
  final BorderSide _iconBorderSide = const BorderSide(color: Colors.white);

  // 动画相关常量
  static const Duration _animationDuration = Duration(milliseconds: 200);
  static const Curve _animationCurve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    // 初始化播放器状态
    _playerState = VideoPlayerState(
      isShowMenuBar: true,
      drawerIsOpen: widget.drawerIsOpen,
    );

    // 窗口监听器注册逻辑
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 同步drawer状态
    if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      setState(() {
        _playerState.drawerIsOpen = widget.drawerIsOpen;
      });
    }
  }

  @override
  void dispose() {
    _playerState.dispose();
    // 窗口监听器移除逻辑
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    super.dispose();
  }

  // 窗口监听器回调方法
  @override
  void onWindowEnterFullScreen() {
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }, '离开全屏时发生错误');
  }

  @override
  void onWindowResize() {
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      _closeDrawerIfOpen();
    }, '调整窗口大小时发生错误');
  }

  // 封装关闭抽屉逻辑
  void _closeDrawerIfOpen() {
    if (_playerState.drawerIsOpen) {
      setState(() {
        _playerState.drawerIsOpen = false;
        widget.onToggleDrawer?.call();
      });
    }
  }

  // 视频播放控制核心方法
  Future<void> _handleSelectPress() async {
    // 如果视频正在播放
    if (widget.controller?.isPlaying() ?? false) {
      // 如果暂停图标的计时器未激活
      if (!(_playerState.pauseIconTimer?.isActive ?? false)) {
        setState(() {
          _playerState.isShowPauseIcon = true;
          _playerState.isShowPlayIcon = false;
        });

        // 启动暂停图标的计时器
        _playerState.pauseIconTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _playerState.isShowPauseIcon = false;
            });
          }
        });
      } else {
        // 暂停视频播放
        await widget.controller?.pause();
        _playerState.pauseIconTimer?.cancel();
        setState(() {
          _playerState.isShowPauseIcon = false;
          _playerState.isShowPlayIcon = true;
        });
      }
    } else {
      // 播放视频
      await widget.controller?.play();
      setState(() {
        _playerState.isShowPlayIcon = false;
      });
    }

    // 如果是横屏模式，切换菜单栏显示状态
    if (widget.isLandscape) {
      setState(() {
        _playerState.isShowMenuBar = !_playerState.isShowMenuBar;
      });
    }
  }
  
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

    return onTap != null
        ? GestureDetector(onTap: onTap, child: iconWidget)
        : iconWidget;
  }

  // 统一的控制按钮构建方法
  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
    bool showBackground = false,
  }) {
    return Container(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor,
                side: _iconBorderSide,
              )
            : null,
        icon: Icon(
          icon,
          color: iconColor ?? _iconColor,
          size: 24,
        ),
        onPressed: onPressed,
      ),
    );
  }

  // 收藏按钮构建方法
  Widget _buildFavoriteButton(String currentChannelId, bool showBackground) {
    return Container(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: widget.isChannelFavorite(currentChannelId)
            ? S.current.removeFromFavorites
            : S.current.addToFavorites,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor,
                side: _iconBorderSide,
              )
            : null,
        icon: Icon(
          widget.isChannelFavorite(currentChannelId)
              ? Icons.favorite
              : Icons.favorite_border,
          color: widget.isChannelFavorite(currentChannelId)
              ? Colors.red
              : _iconColor,
          size: 24,
        ),
        onPressed: () {
          widget.toggleFavorite(currentChannelId);
          setState(() {});
        },
      ),
    );
  }

  // 切换频道源按钮构建方法
  Widget _buildChangeSourceButton(bool showBackground) {
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
          size: 24,
        ),
        onPressed: () {
          if (widget.isLandscape) {
            _closeDrawerIfOpen();
            setState(() => _playerState.isShowMenuBar = false);
          }
          widget.changeChannelSources?.call();
        },
      ),
    );
  }

  // 视频播放器核心组件构建方法
  Widget _buildVideoPlayer() {
    final containerHeight = MediaQuery.of(context).size.width / (16 / 9);

    if (widget.controller == null ||
        widget.controller!.isVideoInitialized() != true ||
        widget.isAudio) {
      return VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _playerState.drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      );
    }

    return Container(
      width: double.infinity,
      height: containerHeight,
      color: Colors.black,
      child: Center(
        child: BetterPlayer(controller: widget.controller!),
      ),
    );
  }

  // 视频区域构建方法，包括播放器和控制图标
  Widget _buildVideoSection() {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _playerState.drawerIsOpen ? null : () => _handleSelectPress(),
        onDoubleTap: _playerState.drawerIsOpen ? null : () {
          LogUtil.safeExecute(() {
            widget.isPlaying
                ? widget.controller?.pause()
                : widget.controller?.play();
          }, '双击播放/暂停发生错误');
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildVideoPlayer(),

            // 播放/暂停控制图标
            if ((widget.controller != null &&
                 widget.controller!.isVideoInitialized() == true &&
                 !(widget.controller!.isPlaying() ?? false) &&
                 !_playerState.drawerIsOpen) ||
                _playerState.isShowPlayIcon)
              _buildControlIcon(
                icon: Icons.play_arrow,
                onTap: () => _handleSelectPress(),
              ),
            if (_playerState.isShowPauseIcon)
              _buildControlIcon(
                icon: Icons.pause,
              ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    String currentChannelId = widget.currentChannelId;

    return Stack(
      children: [
        // 视频播放区域
        Positioned.fill(
          child: _buildVideoSection(),
        ),

        // 使用RepaintBoundary包装各个独立更新的UI组件
        if (!_playerState.drawerIsOpen) ...[
          // 音量和亮度控制组件
          RepaintBoundary(
              child: const VolumeBrightnessWidget(),
            ),

          // 时间显示（仅在横屏模式且菜单栏显示时）
          if (_playerState.isShowMenuBar && widget.isLandscape)
            RepaintBoundary(
                child: const DatePositionWidget(),
              ),

          // 横屏模式下的底部菜单栏
          if (widget.isLandscape && _playerState.isShowMenuBar)
            AnimatedPositioned(
              duration: _animationDuration,
              curve: _animationCurve,
              left: 0,
              right: 0,
              bottom: _playerState.isShowMenuBar ? 15 : -50,
              child: RepaintBoundary(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        const Spacer(),
                        // 频道列表按钮
                        _buildControlButton(
                          icon: Icons.list_alt,
                          tooltip: S.of(context).tipChannelList,
                          showBackground: true,
                          onPressed: () {
                            LogUtil.safeExecute(() {
                              setState(() {
                                _playerState.isShowMenuBar = false;
                                widget.onToggleDrawer?.call();
                              });
                            }, '切换频道发生错误');
                          },
                        ),
                        const SizedBox(width: 5),
                        // 收藏按钮
                        _buildFavoriteButton(currentChannelId, true),
                        const SizedBox(width: 5),
                        // 切换源按钮
                        _buildChangeSourceButton(true),
                        const SizedBox(width: 5),
                        // 设置按钮
                        _buildControlButton(
                          icon: Icons.settings,
                          tooltip: S.of(context).settings,
                          showBackground: true,
                          onPressed: () {
                            _closeDrawerIfOpen();
                            LogUtil.safeExecute(() {
                              setState(() => _playerState.isShowMenuBar = false);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => SettingPage()),
                              );
                            }, '进入设置页面发生错误');
                          },
                        ),
                        const SizedBox(width: 5),
                        // 横竖屏切换按钮
                        _buildControlButton(
                          icon: Icons.screen_rotation,
                          tooltip: S.of(context).portrait,
                          showBackground: true,
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
                        // 全屏按钮（非移动设备）
                        if (!EnvUtil.isMobile) ...[
                          const SizedBox(width: 5),
                          _buildControlButton(
                            icon: Icons.fit_screen_outlined,
                            tooltip: S.of(context).fullScreen,
                            showBackground: true,
                            onPressed: () async {
                              LogUtil.safeExecute(() async {
                                final isFullScreen = await windowManager.isFullScreen();
                                windowManager.setFullScreen(!isFullScreen);
                              }, '切换为全屏时发生错误');
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
              ),
            ),

          // 竖屏模式下的右下角控制按钮
          if (!widget.isLandscape)
            Positioned(
              right: 8,
              bottom: 8,
              child: RepaintBoundary(
                child: Container(
                  width: 32,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFavoriteButton(currentChannelId, false),
                      const SizedBox(height: 2),
                      _buildChangeSourceButton(false),
                      const SizedBox(height: 2),
                      _buildControlButton(
                        icon: Icons.screen_rotation,
                        tooltip: S.of(context).landscape,
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
