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
import 'gradient_progress_bar.dart';
import 'generated/l10n.dart';

// 视频 UI 状态管理类，用于管理播放器界面不同组件的显示状态
class VideoUIState {
  final bool showMenuBar; // 菜单栏是否显示
  final bool showPauseIcon; // 暂停图标是否显示
  final bool showPlayIcon; // 播放图标是否显示
  final bool drawerIsOpen; // 抽屉是否打开

  const VideoUIState({
    this.showMenuBar = true, // 默认菜单栏显示
    this.showPauseIcon = false, // 默认暂停图标隐藏
    this.showPlayIcon = false, // 默认播放图标隐藏
    this.drawerIsOpen = false, // 默认抽屉关闭
  });

  // 通过更新特定属性，生成一个新的状态实例
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

// 视频播放器 Widget，支持多种交互功能和 UI 状态管理
class TableVideoWidget extends StatefulWidget {
  final BetterPlayerController? controller; // 视频播放器控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源的回调函数
  final String? toastString; // 视频播放器提示信息
  final bool isLandscape; // 是否处于横屏模式
  final bool isBuffering; // 视频是否正在缓冲
  final bool isPlaying; // 视频是否正在播放
  final double aspectRatio; // 视频宽高比
  final bool drawerIsOpen; // 抽屉是否打开
  final Function(String) toggleFavorite; // 切换频道收藏状态的回调函数
  final bool Function(String) isChannelFavorite; // 检查频道是否收藏的回调函数
  final String currentChannelId; // 当前频道 ID
  final String currentChannelLogo; // 当前频道 Logo
  final String currentChannelTitle; // 当前频道标题
  final VoidCallback? onToggleDrawer; // 切换抽屉状态的回调函数
  final bool isAudio; // 是否为音频播放模式

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
  // 图标和背景颜色常量，用于统一控制样式
  final Color _iconColor = Colors.white;
  final Color _backgroundColor = Colors.black45;
  final BorderSide _iconBorderSide = const BorderSide(color: Colors.white);

  // UI 状态管理器
  late final ValueNotifier<VideoUIState> _uiStateNotifier;

  // 暂停图标显示定时器，用于控制暂停图标的显示时间
  Timer? _pauseIconTimer;

  // 当前 UI 状态的便捷访问器
  VideoUIState get _currentState => _uiStateNotifier.value;

  // 更新 UI 状态的方法，支持部分属性更新
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

  @override
  void initState() {
    super.initState();
    // 初始化 UI 状态管理器
    _uiStateNotifier = ValueNotifier(VideoUIState(
      showMenuBar: true,
      showPauseIcon: false,
      showPlayIcon: false,
      drawerIsOpen: widget.drawerIsOpen,
    ));

    // 非移动端时注册窗口监听器，处理窗口事件
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当抽屉状态发生变化时，同步更新 UI 状态
    if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      _updateUIState(drawerIsOpen: widget.drawerIsOpen);
    }
  }

  @override
  void dispose() {
    // 销毁资源，包括 UI 状态管理器和定时器
    _uiStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    // 进入全屏时调整窗口标题栏样式
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    // 退出全屏时恢复窗口标题栏样式
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }, '退出全屏时发生错误');
  }

  @override
  void onWindowResize() {
    // 窗口大小变化时关闭抽屉并更新标题栏样式
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      _closeDrawerIfOpen();
    }, '调整窗口大小时发生错误');
  }

  // 构建视频播放器组件，区分有效控制器和音频模式
  Widget _buildVideoPlayer(double containerHeight) {
    if (widget.controller == null || 
        widget.controller!.isVideoInitialized() != true || 
        widget.isAudio == true) {
      // 若控制器无效或是音频模式，显示视频背景组件
      return VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _currentState.drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      );
    }

    // 控制器有效时，加载视频播放器
    return Container(
      width: double.infinity,
      height: containerHeight,
      color: Colors.black,
      child: Center(
        child: BetterPlayer(controller: widget.controller!),
      ),
    );
  }

  // 播放/暂停视频，支持菜单栏显示控制
  Future<void> _handleSelectPress() async {
    if (widget.controller?.isPlaying() ?? false) {
      // 如果视频正在播放，显示暂停图标 3 秒
      if (!(_pauseIconTimer?.isActive ?? false)) {
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

    // 切换菜单栏显示状态（横屏模式下）
    if (widget.isLandscape) {
      _updateUIState(showMenuBar: !_currentState.showMenuBar);
    }
  }

  // 关闭抽屉
  void _closeDrawerIfOpen() {
    if (_currentState.drawerIsOpen) {
      _updateUIState(drawerIsOpen: false);
      widget.onToggleDrawer?.call();
    }
  }

    // 构建通用控制图标
  Widget _buildControlIcon({
    required IconData icon, // 图标
    Color backgroundColor = Colors.black, // 背景颜色
    Color iconColor = Colors.white, // 图标颜色
    VoidCallback? onTap, // 点击事件的回调函数
  }) {
    // 图标组件，支持背景和点击功能
    Widget iconWidget = Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor.withOpacity(0.5), // 半透明背景
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.7), // 添加阴影效果
              spreadRadius: 2,
              blurRadius: 10,
              offset: const Offset(0, 3), // 阴影偏移
            ),
          ],
        ),
        padding: const EdgeInsets.all(10.0), // 图标内边距
        child: Icon(
          icon,
          size: 68, // 图标大小
          color: iconColor.withOpacity(0.85), // 半透明图标颜色
        ),
      ),
    );

    // 如果提供了点击回调，包裹 GestureDetector 以支持点击事件
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: iconWidget,
      );
    }
    return iconWidget; // 否则直接返回图标组件
  }

  // 收藏按钮，显示当前频道是否已收藏，并支持点击切换状态
  Widget buildFavoriteButton(String currentChannelId, bool showBackground) {
    return Container(
      width: 32, // 按钮宽度
      height: 32, // 按钮高度
      child: IconButton(
        tooltip: widget.isChannelFavorite(currentChannelId) 
            ? S.current.removeFromFavorites // 收藏状态提示
            : S.current.addToFavorites, // 非收藏状态提示
        padding: EdgeInsets.zero, // 去除内边距
        constraints: const BoxConstraints(), // 自定义大小限制
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor, // 设置背景颜色
                side: _iconBorderSide, // 添加边框
              )
            : null,
        icon: Icon(
          widget.isChannelFavorite(currentChannelId) 
              ? Icons.favorite // 已收藏的图标
              : Icons.favorite_border, // 未收藏的图标
          color: widget.isChannelFavorite(currentChannelId) 
              ? Colors.red // 已收藏状态下的图标颜色
              : _iconColor, // 未收藏状态下的图标颜色
          size: 24, // 图标大小
        ),
        onPressed: () {
          widget.toggleFavorite(currentChannelId); // 调用切换收藏状态的回调
          setState(() {}); // 更新 UI
        },
      ),
    );
  }

  // 切换频道源的按钮，用于用户在多个流媒体源之间切换
  Widget buildChangeChannelSourceButton(bool showBackground) {
    return Container(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: S.of(context).tipChangeLine, // 按钮提示文字
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor, // 背景颜色
                side: _iconBorderSide, // 添加边框
              )
            : null,
        icon: Icon(
          Icons.legend_toggle, // 切换图标
          color: _iconColor, // 图标颜色
          size: 24, // 图标大小
        ),
        onPressed: () {
          if (widget.isLandscape) {
            _closeDrawerIfOpen(); // 如果抽屉打开，先关闭
            _updateUIState(showMenuBar: false); // 隐藏菜单栏
          }
          widget.changeChannelSources?.call(); // 调用切换频道源的回调函数
        },
      ),
    );
  }

  // 构建控制按钮，支持图标、点击事件、背景样式
  Widget _buildControlButton({
    required IconData icon, // 按钮图标
    required String tooltip, // 按钮提示文字
    VoidCallback? onPressed, // 点击事件的回调
    Color? iconColor, // 图标颜色
    bool showBackground = false, // 是否显示背景
  }) {
    return Container(
      width: 32, // 按钮宽度
      height: 32, // 按钮高度
      child: IconButton(
        tooltip: tooltip, // 提示文字
        padding: EdgeInsets.zero, // 无内边距
        constraints: const BoxConstraints(), // 自定义大小
        style: showBackground
            ? IconButton.styleFrom(
                backgroundColor: _backgroundColor, // 背景颜色
                side: _iconBorderSide, // 边框
              )
            : null,
        icon: Icon(
          icon, // 图标
          color: iconColor ?? _iconColor, // 默认图标颜色
          size: 24, // 图标大小
        ),
        onPressed: onPressed, // 点击事件
      ),
    );
  }

  // 使用 ValueListenableBuilder 动态监听 UI 状态变化，并根据状态重建 UI
  @override
  Widget build(BuildContext context) {
    final playerHeight = MediaQuery.of(context).size.width / (16 / 9); // 视频播放器高度，根据 16:9 比例计算
    // 在每次重建时动态计算宽度和字体大小
   final progressBarWidth = widget.isLandscape
       ? MediaQuery.of(context).size.width * 0.3
       : MediaQuery.of(context).size.width * 0.5;
   final messageFontSize = widget.isLandscape ? 18.0 : 16.0;
  
    return ValueListenableBuilder<VideoUIState>(
      valueListenable: _uiStateNotifier, // 绑定状态监听器
      builder: (context, uiState, child) {
        return Stack(
          children: [
            // 视频播放区域
            GestureDetector(
              onTap: uiState.drawerIsOpen ? null : () => _handleSelectPress(), // 点击播放/暂停
              onDoubleTap: uiState.drawerIsOpen ? null : () {
                LogUtil.safeExecute(() {
                  // 双击播放/暂停
                  widget.isPlaying 
                      ? widget.controller?.pause() 
                      : widget.controller?.play();
                }, '双击播放/暂停发生错误');
              },
              child: Container(
                alignment: Alignment.center, // 视频居中显示
                color: Colors.black, // 背景颜色
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildVideoPlayer(playerHeight), // 视频播放器组件
                    if ((widget.controller != null && 
                         widget.controller!.isVideoInitialized() == true && 
                         !(widget.controller!.isPlaying() ?? false) && 
                         !uiState.drawerIsOpen) || uiState.showPlayIcon)
                      _buildControlIcon(
                        icon: Icons.play_arrow, // 显示播放图标
                        onTap: () => _handleSelectPress(),
                      ),
                    if (uiState.showPauseIcon)
                      _buildControlIcon(icon: Icons.pause), // 显示暂停图标
                      
                   // 显示进度条和提示信息
                   if (widget.toastString != null &&
                       !["HIDE_CONTAINER", ""].contains(widget.toastString) &&
                       (widget.isBuffering || !widget.isPlaying))
                     Positioned(
                       left: 0,
                       right: 0,
                       bottom: 15,
                       child: Column(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           // 进度条
                           GradientProgressBar(
                             width: progressBarWidth, // 竖屏宽度50%
                             height: 5,
                           ),
                           const SizedBox(height: 6),
                           // Toast消息
                           Text(
                             widget.toastString!,
                             style: TextStyle(
                               color: Colors.white,
                               fontSize: messageFontSize, 
                             ),
                           ),
                         ],
                       ),
                     ),
                  ],
                ),
              ),
            ),

            // 音量和亮度控制组件，仅在抽屉关闭时显示
            if (!uiState.drawerIsOpen)
              const VolumeBrightnessWidget(),

            // 显示当前时间和播放进度
            if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar)
              const DatePositionWidget(),

            // 横屏模式下的底部菜单栏
            if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar)
              AnimatedPositioned(
                left: 0,
                right: 0,
                bottom: uiState.showMenuBar ? 18 : -50, // 动画显示/隐藏
                duration: const Duration(milliseconds: 200),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 15), // 添加水平内边距
                  child: Row(
                    children: [
                      const Spacer(), // 左侧间隔
                      // 频道列表按钮
                      _buildControlButton(
                        icon: Icons.list_alt,
                        tooltip: S.of(context).tipChannelList, // 提示：频道列表
                        showBackground: true,
                        onPressed: () {
                          LogUtil.safeExecute(() {
                            _updateUIState(showMenuBar: false);
                            widget.onToggleDrawer?.call(); // 打开频道列表
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
                        tooltip: S.of(context).settings, // 提示：设置
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
                        tooltip: S.of(context).portrait, // 提示：切换到竖屏
                        showBackground: true,
                        onPressed: () async {
                          LogUtil.safeExecute(() async {
                            if (EnvUtil.isMobile) {
                              SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); // 切换竖屏
                            } else {
                              await windowManager.setSize(const Size(414, 414 * 16 / 9), animate: true);
                              await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
                              Future.delayed(const Duration(milliseconds: 500), () => windowManager.center(animate: true));
                            }
                          }, '切换为竖屏时发生错误');
                        },
                      ),
                      // 全屏按钮（仅非移动设备显示）
                      if (!EnvUtil.isMobile) ...[
                        const SizedBox(width: 8),
                        _buildControlButton(
                          icon: Icons.fit_screen_outlined,
                          tooltip: S.of(context).fullScreen, // 提示：切换全屏
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
                  width: 32, // 宽度
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // 最小尺寸
                    children: [
                      buildFavoriteButton(widget.currentChannelId, false), // 收藏按钮
                      const SizedBox(height: 5),
                      buildChangeChannelSourceButton(false), // 切换频道源按钮
                      const SizedBox(height: 5),
                      _buildControlButton(
                        icon: Icons.screen_rotation,
                        tooltip: S.of(context).landscape, // 提示：切换横屏
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
