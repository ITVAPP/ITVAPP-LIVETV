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
    this.toastString,
    this.changeChannelSources,
    this.isLandscape = true,
    this.onToggleDrawer,
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
    // 初始化 UI 状态管理器
    _uiStateNotifier = ValueNotifier(VideoUIState(
      showMenuBar: true,
      showPauseIcon: false,
      showPlayIcon: false,
      drawerIsOpen: widget.drawerIsOpen,
    ));

    // 初始化文字广告动画
    widget.adManager.initTextAdAnimation(this, MediaQuery.of(context).size.width);

    // 非移动端时注册窗口监听器，处理窗口事件
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  // 将播放器高度和进度条宽度的计算移到 didChangeDependencies 中，避免在 build 中重复计算
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _playerHeight = mediaQuery.size.width / (16 / 9);
    _progressBarWidth = widget.isLandscape ? mediaQuery.size.width * 0.3 : mediaQuery.size.width * 0.5;
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检查频道是否发生变化
    if (widget.currentChannelId != oldWidget.currentChannelId) {
      // 重置所有 UI 状态
      _updateUIState(
        showPauseIcon: false,
        showPlayIcon: false,
      );
      // 取消暂停图标定时器
      _pauseIconTimer?.cancel();
      _pauseIconTimer = null;
    } else if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      _updateUIState(drawerIsOpen: widget.drawerIsOpen);
    } else if (widget.isLandscape != oldWidget.isLandscape) { // 新增：检测横竖屏切换
      widget.adManager.updateTextAdAnimation(MediaQuery.of(context).size.width);
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
        // 将动态部分放入 ValueListenableBuilder，静态部分抽取到 _buildStaticOverlay
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
                          LogUtil.safeExecute(() {
                            widget.isPlaying ? widget.controller?.pause() : widget.controller?.play();
                          }, '双击播放/暂停发生错误');
                        },
                  child: Container(
                    alignment: Alignment.center,
                    color: Colors.black,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildVideoPlayer(_playerHeight!), // 使用缓存的播放器高度
                        if ((widget.controller != null &&
                                widget.controller!.isVideoInitialized() == true &&
                                !(widget.controller!.isPlaying() ?? false) &&
                                !uiState.drawerIsOpen) ||
                            uiState.showPlayIcon)
                          _buildControlIcon(
                            icon: Icons.play_arrow,
                            onTap: () => _handleSelectPress(),
                          ),
                        if (uiState.showPauseIcon) _buildControlIcon(icon: Icons.pause),
                        if (widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString))
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: LayoutBuilder(
                              builder: (context, constraints) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GradientProgressBar(
                                    width: _progressBarWidth!, // 使用缓存的进度条宽度
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
            );
          },
        ),
        // 滚动文字广告，只有在有广告内容时显示
        _buildStaticOverlay(),
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
