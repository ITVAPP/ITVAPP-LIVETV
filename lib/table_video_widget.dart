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
  final AdManager adManager; // 新增 AdManager 参数
  // 新增参数
  final bool showPlayIcon; // 从 LiveHomePage 传递，控制播放图标显示
  final bool showPauseIconFromListener; // 从 LiveHomePage 传递，控制非用户触发的暂停图标显示
  final VoidCallback? onUserPaused; // 回调通知 LiveHomePage 用户触发暂停
  final VoidCallback? onRetry; // 回调通知 LiveHomePage 触发 HLS 重试
  final bool isHls; // 是否为 HLS 流

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
    required this.adManager, // 添加必填参数
    required this.showPlayIcon, // 新增必填参数
    required this.showPauseIconFromListener, // 新增必填参数
    required this.isHls, // 新增必填参数
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.onToggleDrawer,
    this.onUserPaused, // 可选回调
    this.onRetry, // 可选回调
    this.isAudio = false,
  });

  @override
  State<TableVideoWidget> createState() => _TableVideoWidgetState();
}

class _TableVideoWidgetState extends State<TableVideoWidget> with WindowListener, SingleTickerProviderStateMixin {
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

  // 添加缓存变量，用于预计算播放器高度和进度条宽度，避免重复计算
  double? _playerHeight;
  double? _progressBarWidth;

  // 缓存视频播放器组件，避免重复构建
  Widget? _cachedVideoPlayer;

  // 预定义控制图标的装饰样式，避免重复创建，提高性能
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
    // 初始化 UI 状态管理器，同步外部传入的状态
    _uiStateNotifier = ValueNotifier(VideoUIState(
      showMenuBar: true,
      showPauseIcon: widget.showPauseIconFromListener,
      showPlayIcon: widget.showPlayIcon,
      drawerIsOpen: widget.drawerIsOpen,
    ));

    // 初始化文字广告动画
    widget.adManager.initTextAdAnimation(this, MediaQuery.of(context).size.width);

    // 非移动端时注册窗口监听器，处理窗口事件
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  // 将播放器高度和进度条宽度的计算移到 didChangeDependencies 中，并考虑横竖屏变化
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    final newPlayerHeight = mediaQuery.size.width / (widget.isLandscape ? 16 / 9 : 9 / 16);
    final newProgressBarWidth = widget.isLandscape ? mediaQuery.size.width * 0.3 : mediaQuery.size.width * 0.5;

    // 仅在尺寸变化时更新缓存值
    if (_playerHeight != newPlayerHeight || _progressBarWidth != newProgressBarWidth) {
      _playerHeight = newPlayerHeight;
      _progressBarWidth = newProgressBarWidth;
      _updateCachedVideoPlayer(); // 更新缓存的播放器组件
    }
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检查频道是否发生变化
    if (widget.currentChannelId != oldWidget.currentChannelId) {
      // 重置所有 UI 状态
      _updateUIState(
        showPauseIcon: widget.showPauseIconFromListener,
        showPlayIcon: widget.showPlayIcon,
      );
      // 取消暂停图标定时器
      _pauseIconTimer?.cancel();
      _pauseIconTimer = null;
      _updateCachedVideoPlayer(); // 更新缓存的播放器组件
    } else {
      // 同步外部状态
      if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
        _updateUIState(drawerIsOpen: widget.drawerIsOpen);
      }
      if (widget.showPlayIcon != oldWidget.showPlayIcon || widget.showPauseIconFromListener != oldWidget.showPauseIconFromListener) {
        _updateUIState(
          showPlayIcon: widget.showPlayIcon,
          showPauseIcon: widget.showPauseIconFromListener,
        );
      }
      if (widget.controller != oldWidget.controller || widget.isAudio != oldWidget.isAudio) {
        _updateCachedVideoPlayer(); // 控制器或模式变化时更新缓存
      }
      if (widget.isLandscape != oldWidget.isLandscape) {
        widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
      }
    }
  }

  @override
  void dispose() {
    // 销毁资源，确保定时器被清理，避免内存泄漏
    _uiStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null; // 显式置为 null
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.removeListener(this);
    }, '移除窗口监听器发生错误');
    widget.adManager.dispose();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    // 进入全屏时更新动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    // 退出全屏时更新动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
    }, '退出全屏时发生错误');
  }

  @override
  void onWindowResize() {
    // 窗口大小变化时更新动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      _closeDrawerIfOpen();
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
    }, '调整窗口大小时发生错误');
  }

  // 更新缓存的视频播放器组件，仅在必要时重建
  void _updateCachedVideoPlayer() {
    if (widget.controller == null ||
        widget.controller!.isVideoInitialized() != true ||
        widget.isAudio == true) {
      // 若控制器无效或是音频模式，显示视频背景组件
      _cachedVideoPlayer = VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _currentState.drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      );
    } else {
      // 控制器有效时，加载视频播放器
      _cachedVideoPlayer = Container(
        width: double.infinity,
        height: _playerHeight,
        color: Colors.black,
        child: Center(
          child: BetterPlayer(controller: widget.controller!),
        ),
      );
    }
  }

  // 构建视频播放器组件，使用缓存结果
  Widget _buildVideoPlayer(double containerHeight) {
    // 确保缓存存在
    _cachedVideoPlayer ??= _updateCachedVideoPlayer();
    return _cachedVideoPlayer!;
  }

  // 处理播放逻辑
  Future<void> _playVideo() async {
    if (widget.isHls) {
      widget.onRetry?.call(); // HLS 触发重试
    } else {
      await widget.controller?.play();
      _updateUIState(showPlayIcon: false); // 隐藏播放图标
    }
  }

  // 处理暂停逻辑
  Future<void> _pauseVideo() async {
    await widget.controller?.pause();
    _pauseIconTimer?.cancel();
    _updateUIState(showPauseIcon: false);
    widget.onUserPaused?.call(); // 通知 LiveHomePage 用户触发暂停
  }

  // 处理播放/暂停选择事件，重构为更清晰的逻辑
  Future<void> _handleSelectPress() async {
    if (widget.controller == null) return; // 控制器为空时直接返回

    final isPlaying = widget.controller!.isPlaying() ?? false;
    if (isPlaying) {
      if (!(_pauseIconTimer?.isActive ?? false)) {
        // 显示暂停图标 3 秒
        _updateUIState(showPauseIcon: true);
        _pauseIconTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _updateUIState(showPauseIcon: false);
          }
        });
      } else {
        // 用户主动暂停
        await _pauseVideo();
      }
    } else {
      // 从暂停恢复播放
      await _playVideo();
    }

    // 横屏模式下切换菜单栏显示状态
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

  // 优化控制图标的构建方法，使用预定义的装饰样式，避免重复创建
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
        child: Icon(
          icon,
          size: 68,
          color: iconColor.withOpacity(0.85),
        ),
      ),
    );
    return onTap != null ? GestureDetector(onTap: onTap, child: iconWidget) : iconWidget;
  }

  // 通用的图标按钮构建方法，消除重复代码
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? iconColor,
    bool showBackground = false,
    double width = 32,
    double height = 32,
  }) {
    return Container(
      width: width,
      height: height,
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

  // 收藏按钮，使用通用方法构建
  Widget buildFavoriteButton(String currentChannelId, bool showBackground) {
    final isFavorite = widget.isChannelFavorite(currentChannelId);
    return _buildIconButton(
      icon: isFavorite ? Icons.favorite : Icons.favorite_border,
      tooltip: isFavorite ? S.current.removeFromFavorites : S.current.addToFavorites,
      iconColor: isFavorite ? Colors.red : _iconColor,
      showBackground: showBackground,
      onPressed: () {
        widget.toggleFavorite(currentChannelId);
        setState(() {}); // 更新 UI
      },
    );
  }

  // 切换频道源按钮，使用通用方法构建
  Widget buildChangeChannelSourceButton(bool showBackground) {
    return _buildIconButton(
      icon: Icons.legend_toggle,
      tooltip: S.of(context).tipChangeLine,
      showBackground: showBackground,
      onPressed: () {
        if (widget.isLandscape) {
          _closeDrawerIfOpen();
          _updateUIState(showMenuBar: false);
        }
        widget.changeChannelSources?.call();
      },
    );
  }

  // 构建控制按钮，使用通用方法
  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
    bool showBackground = false,
  }) {
    return _buildIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed ?? () {},
      iconColor: iconColor,
      showBackground: showBackground,
    );
  }

  // 将静态 UI 部分抽取为单独的方法，减少 ValueListenableBuilder 的重建范围
  Widget _buildStaticOverlay() {
    return Stack(
      children: [
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
  }

  // 使用 ValueListenableBuilder 动态监听 UI 状态变化，并根据状态重建 UI
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 动态部分使用 ValueListenableBuilder
        ValueListenableBuilder<VideoUIState>(
          valueListenable: _uiStateNotifier,
          builder: (context, uiState, child) {
            return GestureDetector(
              onTap: uiState.drawerIsOpen ? null : () => _handleSelectPress(),
              onDoubleTap: uiState.drawerIsOpen
                  ? null
                  : () {
                      LogUtil.safeExecute(() async {
                        if (widget.isPlaying) {
                          await widget.controller?.pause();
                          widget.onUserPaused?.call();
                        } else {
                          if (widget.isHls) {
                            widget.onRetry?.call();
                          } else {
                            await widget.controller?.play();
                          }
                        }
                      }, '双击播放/暂停发生错误');
                    },
              child: Container(
                alignment: Alignment.center,
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildVideoPlayer(_playerHeight!), // 使用缓存的播放器
                    if (uiState.showPlayIcon) // 使用内部状态控制播放图标
                      _buildControlIcon(
                        icon: Icons.play_arrow,
                        onTap: () => _handleSelectPress(),
                      ),
                    if (uiState.showPauseIcon || widget.showPauseIconFromListener)
                      _buildControlIcon(icon: Icons.pause),
                    if                     if (widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: LayoutBuilder(
                          builder: (context, constraints) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GradientProgressBar(
                                width: _progressBarWidth!,
                                height: 5,
                              ),
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
                    if (!uiState.drawerIsOpen) const VolumeBrightnessWidget(),
                    if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar) const DatePositionWidget(),
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
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => SettingPage()),
                                    );
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
                ),
              ),
            );
          },
        ),
        // 静态部分
        _buildStaticOverlay(),
        // 滚动文字广告
        if (widget.adManager.getShowTextAd() && widget.adManager.getAdData()?.textAdContent != null && widget.adManager.getTextAdAnimation() != null)
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
                      shadows: [
                        Shadow(
                          offset: Offset(1.0, 1.0),
                          blurRadius: 0.0,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
