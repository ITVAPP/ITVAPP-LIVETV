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
  
  // 添加常用 UI 元素常量，减少创建实例次数
  static const _spacer8 = SizedBox(width: 8);
  static const _spacer5 = SizedBox(height: 5);
  static const _controlPadding = EdgeInsets.all(10.0);
  static const _iconSize = 68.0;
  static const _menuHeight = 32.0;
  static const _horizontalPadding = EdgeInsets.symmetric(horizontal: 15);

  late final ValueNotifier<VideoUIState> _uiStateNotifier; // UI 状态管理器
  Timer? _pauseIconTimer; // 暂停图标显示定时器
  VideoUIState get _currentState => _uiStateNotifier.value; // 当前 UI 状态便捷访问

  // 缓存变量，优化性能避免重复计算
  double? _playerHeight; // 播放器高度
  double? _progressBarWidth; // 进度条宽度
  double? _adAnimationWidth; // 广告动画宽度
  late bool _isFavorite; // 缓存收藏状态
  bool? _lastIsLandscape; // 缓存上次横屏状态
  
  // 更新 UI 状态，支持动态调整，优化状态更新逻辑
  void _updateUIState({
    bool? showMenuBar,
    bool? showPauseIcon,
    bool? showPlayIcon,
    bool? drawerIsOpen,
  }) {
    final current = _currentState;
    
    // 检查是否有属性需要更新
    bool needsUpdate = false;
    if (showMenuBar != null && showMenuBar != current.showMenuBar) needsUpdate = true;
    else if (showPauseIcon != null && showPauseIcon != current.showPauseIcon) needsUpdate = true;
    else if (showPlayIcon != null && showPlayIcon != current.showPlayIcon) needsUpdate = true;
    else if (drawerIsOpen != null && drawerIsOpen != current.drawerIsOpen) needsUpdate = true;
    
    if (needsUpdate) {
      _uiStateNotifier.value = VideoUIState(
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
    _lastIsLandscape = widget.isLandscape; // 初始化横屏状态缓存
    widget.adManager.initTextAdAnimation(this, MediaQuery.of(context).size.width); // 初始化广告动画
    // 非移动端注册窗口监听器
    LogUtil.safeExecute(() {
      if (!EnvUtil.isMobile) windowManager.addListener(this);
    }, '注册窗口监听器发生错误');
  }

  // 优化：计算播放器高度和进度条宽度，避免重复计算
  void _updateDimensions() {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final isWidthChanged = _adAnimationWidth != width;
    
    // 首次初始化或尺寸/方向变化时更新
    if (isWidthChanged || _lastIsLandscape != widget.isLandscape || _playerHeight == null) {
      _playerHeight = width / (16 / 9);
      _progressBarWidth = widget.isLandscape ? width * 0.3 : width * 0.5;
      
      // 只有在宽度实际变化时才更新广告动画
      if (isWidthChanged || _adAnimationWidth == null) {
        _adAnimationWidth = width;
        widget.adManager.updateTextAdAnimation(width);
      }
      
      _lastIsLandscape = widget.isLandscape;
    }
  }

  // 优化：使用 _updateDimensions 统一管理尺寸计算
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDimensions();
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
    } 
    
    // 更新尺寸计算（整合横竖屏切换逻辑）
    if (widget.isLandscape != oldWidget.isLandscape) {
      _updateDimensions();
    }
  }

  @override
  void dispose() {
    // 清理资源
    _uiStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null;
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
      _updateDimensions(); // 使用集中管理的尺寸更新方法
    }, '进入全屏时发生错误');
  }

  @override
  void onWindowLeaveFullScreen() {
    // 退出全屏时调整标题栏和动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      if (EnvUtil.isMobile) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      _updateDimensions(); // 使用集中管理的尺寸更新方法
    }, '退出全屏时发生错误');
  }

  @override
  void onWindowResize() {
    // 窗口调整时更新标题栏和动画
    LogUtil.safeExecute(() {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: !widget.isLandscape);
      _closeDrawerIfOpen();
      _updateDimensions(); // 使用集中管理的尺寸更新方法
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

  // 优化：统一管理播放/暂停逻辑
  Future<void> _handleSelectPress() async {
    if (widget.controller?.isPlaying() ?? false) {
      await _handlePause();
    } else {
      await _handlePlay();
    }
    _toggleMenuBar();
  }

  // 优化：集中管理暂停图标显示定时器
  void _showPauseIconWithTimer({bool checkActive = true}) {
    // 检查定时器是否活动（如果需要）
    if (checkActive && (_pauseIconTimer?.isActive ?? false)) {
      // 定时器活动时的特殊处理
      _pauseIconTimer?.cancel();
      _updateUIState(showPauseIcon: false);
      widget.controller?.pause();
      widget.onUserPaused?.call();
      return;
    }
    
    // 常规处理：取消旧定时器，显示图标，设置新定时器
    _pauseIconTimer?.cancel();
    _updateUIState(showPauseIcon: true);
    _pauseIconTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _updateUIState(showPauseIcon: false);
    });
  }

  // 处理暂停逻辑，使用优化后的定时器管理
  Future<void> _handlePause() async {
    if (!(_pauseIconTimer?.isActive ?? false)) {
      _showPauseIconWithTimer();
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

  // 优化：处理双击播放/暂停事件
  Future<void> _togglePlayPause() async {
    try {
      if (widget.isPlaying) {
        await widget.controller?.pause();
        widget.onUserPaused?.call();
      } else {
        if (widget.isHls) widget.onRetry?.call();
        else await widget.controller?.play();
      }
    } catch (e) {
      LogUtil.e('双击播放/暂停发生错误: $e');
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
        padding: _controlPadding,
        child: Icon(icon, size: _iconSize, color: iconColor.withOpacity(0.85)),
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

  // 优化：检查是否应显示提示信息和进度条
  bool get _shouldShowToast => 
    widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString);

  // 优化：检查是否应显示文本广告
  bool get _shouldShowTextAd => 
    widget.adManager.getShowTextAd() && 
    widget.adManager.getAdData()?.textAdContent != null && 
    widget.adManager.getTextAdAnimation() != null;

  // 优化：构建提示信息和进度条组件
  Widget _buildToastWithProgress() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientProgressBar(width: _progressBarWidth!, height: 5),
            _spacer5,
            ScrollingToastMessage(
              message: widget.toastString!,
              containerWidth: constraints.maxWidth,
              isLandscape: widget.isLandscape,
            ),
          ],
        ),
      ),
    );
  }

  // 优化：构建文本广告组件
  Widget _buildTextAdWidget() {
    final content = widget.adManager.getAdData()!.textAdContent!;
    return Positioned(
      top: widget.isLandscape ? 50.0 : 80.0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: widget.adManager.getTextAdAnimation()!,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(widget.adManager.getTextAdAnimation()!.value, 0),
            child: Text(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [Shadow(offset: Offset(1.0, 1.0), blurRadius: 0.0, color: Colors.black)],
              ),
            ),
          );
        },
      ),
    );
  }

  // 优化：构建右侧按钮组（竖屏模式）
  Widget _buildPortraitRightButtons() {
    return Positioned(
      right: 9,
      bottom: 9,
      child: Container(
        width: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildFavoriteButton(widget.currentChannelId, false),
            _spacer5,
            buildChangeChannelSourceButton(false),
            _spacer5,
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
    );
  }

  // 优化：构建菜单栏按钮（横屏模式）
  List<Widget> _buildMenuBarButtons() {
    return [
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
      _spacer8,
      buildFavoriteButton(widget.currentChannelId, true),
      _spacer8,
      buildChangeChannelSourceButton(true),
      _spacer8,
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
      _spacer8,
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
        _spacer8,
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
    ];
  }

  // 优化：构建横屏菜单栏
  Widget _buildLandscapeMenuBar(bool showMenuBar) {
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: showMenuBar ? 18 : -50,
      duration: const Duration(milliseconds: 200),
      child: Container(
        height: _menuHeight,
        padding: _horizontalPadding,
        child: Row(
          children: _buildMenuBarButtons(),
        ),
      ),
    );
  }

  // 优化：构建播放器容器和核心控件
  Widget _buildPlayerContainer(VideoUIState uiState) {
    return Container(
      alignment: Alignment.center,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildVideoPlayer(_playerHeight!),
          if (widget.showPlayIcon) 
            _buildControlIcon(icon: Icons.play_arrow, onTap: () => _handleSelectPress()),
          if (uiState.showPauseIcon || widget.showPauseIconFromListener)
            _buildControlIcon(icon: Icons.pause),
          if (_shouldShowToast)
            _buildToastWithProgress(),
        ],
      ),
    );
  }

  // 优化：构建静态叠加层，使用 RepaintBoundary 减少重绘范围
  Widget _buildStaticOverlay() {
    return RepaintBoundary(
      child: Stack(
        children: [
          if (!widget.isLandscape) _buildPortraitRightButtons(),
          if (_shouldShowTextAd) _buildTextAdWidget(),
        ],
      ),
    );
  }

  // 优化：构建播放器手势区域
  Widget _buildPlayerGestureDetector(VideoUIState uiState) {
    final isActive = !uiState.drawerIsOpen;
    return GestureDetector(
      onTap: isActive ? () => _handleSelectPress() : null,
      onDoubleTap: isActive 
        ? () => _togglePlayPause() 
        : null,
      child: _buildPlayerContainer(uiState),
    );
  }

  // 优化：构建播放器和控件
  Widget _buildVideoPlayerWithControls() {
    return ValueListenableBuilder<VideoUIState>(
      valueListenable: _uiStateNotifier,
      builder: (context, uiState, _) {
        return Stack(
          children: [
            _buildPlayerGestureDetector(uiState),
            if (!uiState.drawerIsOpen) const VolumeBrightnessWidget(),
            if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar) 
              const DatePositionWidget(),
            if (widget.isLandscape && !uiState.drawerIsOpen) 
              _buildLandscapeMenuBar(uiState.showMenuBar),
          ],
        );
      },
    );
  }

  // 优化：整体 build 方法，拆分为更可管理的子组件
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildVideoPlayerWithControls(),
        _buildStaticOverlay(),
      ],
    );
  }
}
