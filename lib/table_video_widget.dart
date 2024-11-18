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

// 视频 UI 状态管理类，用于管理视频界面不同组件的显示状态
class VideoUIState {
  final bool showMenuBar; // 菜单栏显示状态
  final bool showPauseIcon; // 暂停图标显示状态
  final bool showPlayIcon; // 播放图标显示状态
  final bool drawerIsOpen; // 抽屉打开状态

  const VideoUIState({
    this.showMenuBar = true,
    this.showPauseIcon = false,
    this.showPlayIcon = false,
    this.drawerIsOpen = false,
  });

  // 用于生成一个新实例的方法，只替换需要改变的属性
  VideoUIState copyWith({
    bool? showMenuBar,
    bool? showPauseIcon,
    bool? showPlayIcon,
    bool? drawerIsOpen,
  }) {
    return VideoUIState(
      showMenuBar: showMenuBar ?? this.showMenuBar,
      showPauseIcon: showPauseIcon ?? this.showPauseIcon,
      showPlayIcon: showPlayIcon ?? this.showPlayIcon,
      drawerIsOpen: drawerIsOpen ?? this.drawerIsOpen,
    );
  }
}

// 视频播放器界面的 Widget
class TableVideoWidget extends StatefulWidget {
  final BetterPlayerController? controller;
  final GestureTapCallback? changeChannelSources; // 频道切换操作的回调函数
  final String? toastString;
  final bool isLandscape; // 是否为横屏状态
  final bool isBuffering; // 是否正在缓冲
  final bool isPlaying; // 是否正在播放
  final double aspectRatio; // 视频宽高比
  final bool drawerIsOpen; // 是否打开抽屉
  final Function(String) toggleFavorite; // 收藏/取消收藏频道的回调函数
  final bool Function(String) isChannelFavorite; // 判断某频道是否被收藏的函数
  final String currentChannelId;
  final String currentChannelLogo;
  final String currentChannelTitle;
  final VoidCallback? onToggleDrawer; // 切换抽屉状态的函数
  final bool isAudio; // 是否为音频

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
  // 添加 VideoHoldBg 的 key
  final GlobalKey<_VideoHoldBgState> _videoHoldBgKey = GlobalKey();
  
  // 样式常量
  final Color _iconColor = Colors.white;
  final Color _backgroundColor = Colors.black45;
  final BorderSide _iconBorderSide = const BorderSide(color: Colors.white);

  // 使用 ValueNotifier 管理 UI 状态
  late final ValueNotifier<VideoUIState> _uiStateNotifier;
  Timer? _pauseIconTimer;

  // 当前 UI 状态
  VideoUIState get _currentState => _uiStateNotifier.value;

  // 统一管理 UI 状态更新的方法
  void _updateUIState({
    bool? showMenuBar,
    bool? showPauseIcon,
    bool? showPlayIcon,
    bool? drawerIsOpen,
  }) {
    _uiStateNotifier.value = _currentState.copyWith(
      showMenuBar: showMenuBar,
      showPauseIcon: showPauseIcon,
      showPlayIcon: showPlayIcon,
      drawerIsOpen: drawerIsOpen,
    );
  }
  
  // 初始化状态
  @override
  void initState() {
    super.initState();
    // 初始化 UI 状态
    _uiStateNotifier = ValueNotifier(VideoUIState(
      showMenuBar: true,
      showPauseIcon: false,
      showPlayIcon: false,
      drawerIsOpen: widget.drawerIsOpen,
    ));

    // 注册窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  // 组件更新时被调用，用于同步更新
  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同步抽屉打开状态
    if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      _updateUIState(drawerIsOpen: widget.drawerIsOpen);
    }
  }

  // 组件销毁时清理资源
  @override
  void dispose() {
    _uiStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    super.dispose();
  }

  // 处理进入全屏状态
  @override
  void onWindowEnterFullScreen() {
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }, '进入全屏时发生错误');
  }

  // 处理退出全屏状态
  @override
  void onWindowLeaveFullScreen() {
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }, '离开全屏时发生错误');
  }

  // 处理窗口大小变化
  @override
  void onWindowResize() {
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      _closeDrawerIfOpen();
    }, '调整窗口大小时发生错误');
  }

  // 构建视频播放器组件
  Widget _buildVideoPlayer(double containerHeight) {
    final controller = widget.controller;
    // 检查是否正在播放视频
    final isPlayingVideo = controller != null && 
                          controller.isVideoInitialized() == true && 
                          (controller.isPlaying() ?? false) && 
                          !widget.isAudio;

    if (isPlayingVideo) {
      // 正在播放视频时，使用现有播放器控制器
      return Container(
        width: double.infinity,
        height: containerHeight,
        color: Colors.black,
        child: Center(
          child: BetterPlayer(controller: controller),
        ),
      );
    }

    // 其他情况(未初始化、音频、未播放)显示背景
    return VideoHoldBg(
      key: _videoHoldBgKey,  // 添加 key 保持状态
      currentChannelLogo: widget.currentChannelLogo,
      currentChannelTitle: widget.currentChannelTitle,
      toastString: _currentState.drawerIsOpen ? '' : widget.toastString,
      showBingBackground: widget.isAudio,
    );
  }
  
  // 处理选择键和确认键点击事件
  Future<void> _handleSelectPress() async {
    if (widget.controller?.isPlaying() ?? false) {
      if (!(_pauseIconTimer?.isActive ?? false)) {
        // 显示暂停图标3秒
        _updateUIState(
          showPauseIcon: true,
          showPlayIcon: false,
        );
        _pauseIconTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _updateUIState(showPauseIcon: false);
          }
        });
      } else {
        // 暂停视频
        await widget.controller?.pause();
        _pauseIconTimer?.cancel();
        _updateUIState(
          showPauseIcon: false,
          showPlayIcon: true,
        );
      }
    } else {
      // 播放视频
      await widget.controller?.play();
      _updateUIState(showPlayIcon: false);
    }

    if (widget.isLandscape) {
      // 切换菜单栏显示
      _updateUIState(showMenuBar: !_currentState.showMenuBar);
    }
  }

  // 关闭抽屉如果它已打开
  void _closeDrawerIfOpen() {
    if (_currentState.drawerIsOpen) {
      _updateUIState(drawerIsOpen: false);
      widget.onToggleDrawer?.call();
    }
  }
  
  // 构建通用控制图标的方法
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
          size: 68,
          color: iconColor.withOpacity(0.85),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: iconWidget,
      );
    }
    return iconWidget;
  }
  
  // 收藏按钮构建方法
  Widget buildFavoriteButton(String currentChannelId, bool showBackground) {
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

  // 切换频道源的按钮构建方法
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
          size: 24,
        ),
        onPressed: () {
          if (widget.isLandscape) {
            _closeDrawerIfOpen();
            _updateUIState(showMenuBar: false);  
          }
          widget.changeChannelSources?.call();
        },
      ),
    );
  }

  // 控制按钮构建方法
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

  // 使用 ValueListenableBuilder 监听 UI 状态变化并重建 UI
  @override
  Widget build(BuildContext context) {
    final playerHeight = MediaQuery.of(context).size.width / (16 / 9);

    return ValueListenableBuilder<VideoUIState>(
      valueListenable: _uiStateNotifier,
      builder: (context, uiState, child) {
        return Stack(
          children: [
            // 视频播放区域
            GestureDetector(
              onTap: uiState.drawerIsOpen ? null : () => _handleSelectPress(),
              onDoubleTap: uiState.drawerIsOpen ? null : () {
                LogUtil.safeExecute(() {
                  widget.isPlaying 
                      ? widget.controller?.pause() 
                      : widget.controller?.play();
                }, '双击播放/暂停发生错误');
              },
              child: Container(
                alignment: Alignment.center,
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildVideoPlayer(playerHeight),
                    if ((widget.controller != null && 
                         widget.controller!.isVideoInitialized() == true && 
                         !(widget.controller!.isPlaying() ?? false) && 
                         !uiState.drawerIsOpen) || uiState.showPlayIcon)
                      _buildControlIcon(
                        icon: Icons.play_arrow,
                        onTap: () => _handleSelectPress(),
                      ),
                    if (uiState.showPauseIcon)
                      _buildControlIcon(icon: Icons.pause),
                  ],
                ),
              ),
            ),

            // 音量和亮度控制组件
            if (!uiState.drawerIsOpen)
              const VolumeBrightnessWidget(),

            // 时间位置组件
            if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar)
              const DatePositionWidget(),

            // 横屏模式下底部菜单栏
            if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar)
              AnimatedPositioned(
                left: 0,
                right: 0,
                bottom: uiState.showMenuBar ? 18 : -50,
                duration: const Duration(milliseconds: 200),
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
                            _updateUIState(showMenuBar: false);
                            widget.onToggleDrawer?.call();
                          }, '切换频道发生错误');
                        },
                      ),
                      const SizedBox(width: 8),
                      // 收藏按钮
                      buildFavoriteButton(widget.currentChannelId, true),
                      const SizedBox(width: 8),
                      // 切换频道源按钮
                      buildChangeChannelSourceButton(true),
                      const SizedBox(width: 8),
                      // 设置按钮
                      _buildControlButton(
                        icon: Icons.settings,
                        tooltip: S.of(context).settings,
                        showBackground: true,
                        onPressed: () {
                          _closeDrawerIfOpen();
                          LogUtil.safeExecute(() {
                            _updateUIState(showMenuBar: false);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => SettingPage()),
                            );
                          }, '进入设置页面发生错误');
                        },
                      ),
                      const SizedBox(width: 8),
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
                        const SizedBox(width: 8),
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

            // 竖屏模式下右下角的控制按钮
            if (!widget.isLandscape)
              Positioned(
                right: 9,
                bottom: 9,
                child: Container(
                  width: 32,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildFavoriteButton(widget.currentChannelId, false),
                      const SizedBox(height: 5),
                      buildChangeChannelSourceButton(false),
                      const SizedBox(height: 5),
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
          ],
        );
      },
    );
  }
}
