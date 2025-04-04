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
import 'package:itvapp_live_tv/widget/scrolling_toast_message.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'package:itvapp_live_tv/gradient_progress_bar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

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

  // 创建新状态实例，支持部分属性更新
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
  final BetterPlayerController? controller; // 视频播放控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源回调
  final String? toastString; // 提示信息文本
  final bool isLandscape; // 是否横屏模式
  final bool isBuffering; // 是否正在缓冲
  final bool isPlaying; // 是否正在播放
  final double aspectRatio; // 视频宽高比
  final bool drawerIsOpen; // 抽屉是否打开
  final Function(String) toggleFavorite; // 切换收藏状态回调
  final bool Function(String) isChannelFavorite; // 检查频道收藏状态回调
  final String currentChannelId; // 当前频道 ID
  final String currentChannelLogo; // 当前频道 Logo
  final String currentChannelTitle; // 当前频道标题
  final VoidCallback? onToggleDrawer; // 切换抽屉状态回调
  final bool isAudio; // 是否音频模式
  final AdManager adManager; // 广告管理器
  final bool showPlayIcon; // 控制播放图标显示
  final bool showPauseIconFromListener; // 控制非用户触发的暂停图标显示
  final VoidCallback? onUserPaused; // 用户暂停回调
  final VoidCallback? onRetry; // HLS 重试回调
  final bool isHls; // 是否 HLS 流

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
    required this.adManager,
    required this.showPlayIcon,
    required this.showPauseIconFromListener,
    required this.isHls,
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.onToggleDrawer,
    this.onUserPaused,
    this.onRetry,
    this.isAudio = false,
  });

  @override
  State<TableVideoWidget> createState() => _TableVideoWidgetState();
}

class _TableVideoWidgetState extends State<TableVideoWidget> with WindowListener, SingleTickerProviderStateMixin {
  // 定义图标和背景颜色常量，统一样式
  final Color _iconColor = Colors.white;
  final Color _backgroundColor = Colors.black45;
  final BorderSide _iconBorderSide = const BorderSide(color: Colors.white);

  late final ValueNotifier<VideoUIState> _uiStateNotifier; // UI 状态管理器
  Timer? _pauseIconTimer; // 暂停图标显示定时器
  VideoUIState get _currentState => _uiStateNotifier.value; // 当前 UI 状态便捷访问

  // 缓存变量，优化性能避免重复计算
  double? _playerHeight; // 播放器高度
  double? _progressBarWidth; // 进度条宽度
  double? _adAnimationWidth; // 广告动画宽度
  late bool _isFavorite; // 缓存收藏状态

  // 预定义控制图标样式，提高性能
  static const _controlIconDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.black45,
    boxShadow: [
      BoxShadow(
        color: Colors.black54,
        spreadRadius: 2,
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    ],
  );

  // 更新 UI 状态，支持动态调整
  void _updateUIState({
    bool? showMenuBar,
    bool? showPauseIcon,
    bool? showPlayIcon,
    bool? drawerIsOpen,
  }) {
    final current = _currentState;
    if ((showMenuBar != null && showMenuBar != current.showMenuBar) ||
        (showPauseIcon != null && showPauseIcon != current.showPauseIcon) ||
        (showPlayIcon != null && showPlayIcon != current.showPlayIcon) ||
        (drawerIsOpen != null && drawerIsOpen != current.drawerIsOpen)) {
      _uiStateNotifier.value = current.copyWith(
        showMenuBar: showMenuBar ?? current.showMenuBar,
        showPauseIcon: showPauseIcon ?? current.showPauseIcon,
        showPlayIcon: showPlayIcon ?? current.showPlayIcon,
        drawerIsOpen: drawerIsOpen ?? current.drawerIsOpen,
      );
    }
  }

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
    _isFavorite = widget.isChannelFavorite(widget.currentChannelId); // 初始化收藏状态
    widget.adManager.initTextAdAnimation(this, MediaQuery.of(context).size.width); // 初始化广告动画
    // 非移动端注册窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  // 计算播放器高度和进度条宽度，避免 build 中重复计算
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _playerHeight = mediaQuery.size.width / (16 / 9); // 计算播放器高度
    _progressBarWidth = widget.isLandscape ? mediaQuery.size.width * 0.3 : mediaQuery.size.width * 0.5; // 计算进度条宽度
    _adAnimationWidth = mediaQuery.size.width; // 缓存广告动画宽度
    widget.adManager.updateTextAdAnimation(_adAnimationWidth!); // 更新广告动画
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 频道变更时重置 UI 状态
    if (widget.currentChannelId != oldWidget.currentChannelId) {
      _updateUIState(showPauseIcon: false, showPlayIcon: false);
      _pauseIconTimer?.cancel();
      _pauseIconTimer = null;
      _isFavorite = widget.isChannelFavorite(widget.currentChannelId); // 更新收藏状态
      widget.adManager.reset(); // 重置广告状态
    } else if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      _updateUIState(drawerIsOpen: widget.drawerIsOpen); // 更新抽屉状态
    } else if (widget.isLandscape != oldWidget.isLandscape) {
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width); // 横竖屏切换更新动画
    }
  }

  @override
  void dispose() {
    // 清理资源
    _uiStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    widget.adManager.dispose();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    // 进入全屏时调整标题栏和动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    // 退出全屏时调整标题栏和动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
    }, '退出全屏时发生错误');
  }

  @override
  void onWindowResize() {
    // 窗口调整时更新标题栏和动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      _closeDrawerIfOpen();
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
    }, '调整窗口大小时发生错误');
  }

  // 构建视频播放器组件，区分控制器状态和音频模式
  Widget _buildVideoPlayer(double containerHeight) {
    if (widget.controller == null ||
        widget.controller!.isVideoInitialized() != true ||
        widget.isAudio == true) {
      return VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _currentState.drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      );
    }
    return Container(
      width: double.infinity,
      height: containerHeight,
      color: Colors.black,
      child: Center(child: BetterPlayer(controller: widget.controller!)),
    );
  }

  // 处理播放/暂停逻辑并切换菜单栏显示
  Future<void> _handleSelectPress() async {
    if (widget.controller?.isPlaying() ?? false) {
      await _handlePause();
    } else {
      await _handlePlay();
    }
    _toggleMenuBar();
  }

  // 处理暂停逻辑，显示暂停图标并设置定时隐藏
  Future<void> _handlePause() async {
    if (!(_pauseIconTimer?.isActive ?? false)) {
      _updateUIState(showPauseIcon: true);
      _pauseIconTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _updateUIState(showPauseIcon: false);
      });
    } else {
      await widget.controller?.pause();
      _pauseIconTimer?.cancel();
      _updateUIState(showPauseIcon: false);
      widget.onUserPaused?.call();
    }
  }

  // 处理播放逻辑，支持 HLS 重试
  Future<void> _handlePlay() async {
    if (widget.isHls) {
      widget.onRetry?.call();
    } else {
      await widget.controller?.play();
      _updateUIState(showPlayIcon: false);
    }
  }

  // 切换菜单栏显示状态，仅横屏有效
  void _toggleMenuBar() {
    if (widget.isLandscape) _updateUIState(showMenuBar: !_currentState.showMenuBar);
  }

  // 关闭抽屉并触发回调
  void _closeDrawerIfOpen() {
    if (_currentState.drawerIsOpen) {
      _updateUIState(drawerIsOpen: false);
      widget.onToggleDrawer?.call();
    }
  }

  // 构建控制图标，使用预定义样式
  Widget _buildControlIcon({
    required IconData icon,
    Color backgroundColor = Colors.black,
    Color iconColor = Colors.white,
    VoidCallback? onTap,
  }) {
    Widget iconWidget = Center(
      child: Container(
        decoration: _controlIconDecoration,
        padding: const EdgeInsets.all(10.0),
        child: Icon(icon, size: 68, color: iconColor.withOpacity(0.85)),
      ),
    );
    return onTap != null ? GestureDetector(onTap: onTap, child: iconWidget) : iconWidget;
  }

  // 构建通用按钮，支持动态样式和行为
  Widget buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color iconColor = Colors.white,
    bool showBackground = false,
    double size = 24,
    bool isFavoriteButton = false,
    String? channelId,
  }) {
    return Container(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: showBackground ? IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide) : null,
        icon: Icon(
          icon,
          color: isFavoriteButton && channelId != null && widget.isChannelFavorite(channelId) ? Colors.red : iconColor,
          size: size,
        ),
        onPressed: isFavoriteButton && channelId != null
            ? () {
                widget.toggleFavorite(channelId);
                _isFavorite = widget.isChannelFavorite(channelId);
                setState(() {});
              }
            : onPressed,
      ),
    );
  }

  // 构建收藏按钮
  Widget buildFavoriteButton(String currentChannelId, bool showBackground) {
    return buildIconButton(
      icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
      tooltip: _isFavorite ? S.current.removeFromFavorites : S.current.addToFavorites,
      onPressed: null,
      showBackground: showBackground,
      isFavoriteButton: true,
      channelId: currentChannelId,
    );
  }

  // 构建切换频道源按钮
  Widget buildChangeChannelSourceButton(bool showBackground) {
    return buildIconButton(
      icon: Icons.legend_toggle,
      tooltip: S.of(context).tipChangeLine,
      onPressed: () {
        if (widget.isLandscape) {
          _closeDrawerIfOpen();
          _updateUIState(showMenuBar: false);
        }
        widget.changeChannelSources?.call();
      },
      showBackground: showBackground,
    );
  }

  // 构建控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
    bool showBackground = false,
  }) {
    return buildIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      iconColor: iconColor ?? _iconColor,
      showBackground: showBackground,
    );
  }

  // 构建静态叠加层，减少重建范围
  Widget _buildStaticOverlay() {
    return Stack(
      children: [
        if (!widget.isLandscape) // 竖屏时显示右侧按钮组
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
        if (widget.adManager.getShowTextAd() && widget.adManager.getAdData()?.textAdContent != null && widget.adManager.getTextAdAnimation() != null) // 显示广告文本动画
          Positioned(
            top: widget.isLandscape ? 50.0 : 80.0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: widget.adManager.getTextAdAnimation()!,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(widget.adManager.getTextAdAnimation()!.value, 0),
                  child: Text(
                    widget.adManager.getAdData()!.textAdContent!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      shadows: [Shadow(offset: Offset(1.0, 1.0), blurRadius: 0.0, color: Colors.black)],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // 构建动态 UI，监听状态变化
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<VideoUIState>(
          valueListenable: _uiStateNotifier,
          builder: (context, uiState, child) {
            return Stack(
              children: [
                GestureDetector(
                  onTap: uiState.drawerIsOpen ? null : () => _handleSelectPress(),
                  onDoubleTap: uiState.drawerIsOpen
                      ? null
                      : () {
                          LogUtil.safeExecute(() async {
                            if (widget.isPlaying) {
                              await widget.controller?.pause();
                              widget.onUserPaused?.call();
                            } else {
                              if (widget.isHls) widget.onRetry?.call();
                              else await widget.controller?.play();
                            }
                          }, '双击播放/暂停发生错误');
                        },
                  child: Container(
                    alignment: Alignment.center,
                    color: Colors.black,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildVideoPlayer(_playerHeight!),
                        if (widget.showPlayIcon) // 显示播放图标
                          _buildControlIcon(icon: Icons.play_arrow, onTap: () => _handleSelectPress()),
                        if (uiState.showPauseIcon || widget.showPauseIconFromListener) // 显示暂停图标
                          _buildControlIcon(icon: Icons.pause),
                        if (widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString)) // 显示提示信息和进度条
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: LayoutBuilder(
                              builder: (context, constraints) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GradientProgressBar(width: _progressBarWidth!, height: 5),
                                  const SizedBox(height: 5),
                                  ScrollingToastMessage(
                                    message: widget.toastString!,
                                    containerWidth: constraints.maxWidth,
                                    isLandscape: widget.isLandscape,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!uiState.drawerIsOpen) const VolumeBrightnessWidget(), // 显示音量亮度控件
                if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar) const DatePositionWidget(), // 横屏显示日期
                if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar) // 横屏显示菜单栏
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
                          buildFavoriteButton(widget.currentChannelId, true),
                          const SizedBox(width: 8),
                          buildChangeChannelSourceButton(true),
                          const SizedBox(width: 8),
                          _buildControlButton(
                            icon: Icons.settings,
                            tooltip: S.of(context).settings,
                            showBackground: true,
                            onPressed: () {
                              _closeDrawerIfOpen();
                              LogUtil.safeExecute(() {
                                _updateUIState(showMenuBar: false);
                                Navigator.push(context, MaterialPageRoute(builder: (context) => SettingPage()));
                              }, '进入设置页面发生错误');
                            },
                          ),
                          const SizedBox(width: 8),
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
              ],
            );
          },
        ),
        _buildStaticOverlay(), // 添加静态叠加层
      ],
    );
  }
}
