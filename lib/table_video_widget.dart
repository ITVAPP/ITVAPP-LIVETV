import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iapp_player/iapp_player.dart';
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

// 管理播放器界面状态
class VideoUIState {
  final bool showMenuBar; // 控制菜单栏显示
  final bool showPauseIcon; // 控制暂停图标显示
  final bool showPlayIcon; // 控制播放图标显示
  final bool drawerIsOpen; // 控制抽屉开启状态

  const VideoUIState({
    this.showMenuBar = true, // 默认显示菜单栏
    this.showPauseIcon = false, // 默认隐藏暂停图标
    this.showPlayIcon = false, // 默认隐藏播放图标
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

// 视频播放器组件，支持交互和状态管理
class TableVideoWidget extends StatefulWidget {
  final IAppPlayerController? controller; // 视频播放控制器
  final GestureTapCallback? changeChannelSources; // 切换频道源回调
  final String? toastString; // 提示信息文本
  final bool isLandscape; // 是否为横屏模式
  final bool isBuffering; // 是否处于缓冲状态
  final bool isPlaying; // 是否正在播放
  final double aspectRatio; // 视频宽高比
  final bool drawerIsOpen; // 抽屉是否打开
  final Function(String) toggleFavorite; // 切换收藏状态回调
  final bool Function(String) isChannelFavorite; // 检查频道是否收藏
  final String currentChannelId; // 当前频道 ID
  final String currentChannelLogo; // 当前频道 Logo
  final String currentChannelTitle; // 当前频道标题
  final VoidCallback? onToggleDrawer; // 切换抽屉状态回调
  final bool isAudio; // 是否为音频模式
  final AdManager adManager; // 广告管理器实例
  final bool showPlayIcon; // 控制播放图标显示
  final bool showPauseIconFromListener; // 非用户触发的暂停图标显示
  final VoidCallback? onUserPaused; // 用户暂停回调
  final VoidCallback? onRetry; // HLS 重试回调
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

class _TableVideoWidgetState extends State<TableVideoWidget> with SingleTickerProviderStateMixin {
  // 定义图标和背景颜色常量，统一样式
  static const Color _iconColor = Colors.white; // 图标颜色
  static const Color _backgroundColor = Colors.black45; // 背景颜色
  static const BorderSide _iconBorderSide = BorderSide(color: Colors.white); // 图标边框

  // 预定义控制图标样式，提升性能
  static const _controlIconDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.black45,
    boxShadow: [BoxShadow(color: Colors.black54, spreadRadius: 2, blurRadius: 10, offset: Offset(0, 3))],
  );

  // 定义常用 UI 元素常量，减少实例创建
  static const _spacer8 = SizedBox(width: 8); // 水平间距 8
  static const _spacer5 = SizedBox(height: 5); // 垂直间距 5
  static const _controlPadding = EdgeInsets.all(10.0); // 控制按钮内边距
  static const _iconSize = 68.0; // 图标尺寸
  static const _menuHeight = 32.0; // 菜单栏高度
  static const _horizontalPadding = EdgeInsets.symmetric(horizontal: 15); // 水平内边距
  static const _buttonSize = 32.0; // 按钮尺寸
  static const _iconButtonSize = 24.0; // 图标按钮尺寸
  static const _aspectRatio = 16.0 / 9.0; // 视频宽高比常量

  late final ValueNotifier<VideoUIState> _uiStateNotifier; // 管理播放器界面状态
  Timer? _pauseIconTimer; // 暂停图标显示定时器
  VideoUIState get _currentState => _uiStateNotifier.value; // 获取当前界面状态

  // 缓存变量，优化性能
  double? _playerHeight; // 播放器高度
  double? _progressBarWidth; // 进度条宽度
  double? _adAnimationWidth; // 广告动画宽度
  late bool _isFavorite; // 频道收藏状态
  bool? _lastIsLandscape; // 上次横屏状态
  bool _adManagerNeedsUpdate = false; // 标记广告管理器需更新

  // 标记布局是否需重新计算
  bool _needsLayoutRecalculation = true; // 是否需重新计算布局

  // 更新界面状态，优化更新逻辑
  void _updateUIState({
    bool? showMenuBar,
    bool? showPauseIcon,
    bool? showPlayIcon,
    bool? drawerIsOpen,
  }) {
    final current = _currentState;
    bool needsUpdate = (showMenuBar != null && showMenuBar != current.showMenuBar) ||
        (showPauseIcon != null && showPauseIcon != current.showPauseIcon) ||
        (showPlayIcon != null && showPlayIcon != current.showPlayIcon) ||
        (drawerIsOpen != null && drawerIsOpen != current.drawerIsOpen);

    if (needsUpdate) {
      _uiStateNotifier.value = current.copyWith(
        showMenuBar: showMenuBar,
        showPauseIcon: showPauseIcon,
        showPlayIcon: showPlayIcon,
        drawerIsOpen: drawerIsOpen,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _uiStateNotifier = ValueNotifier(VideoUIState(drawerIsOpen: widget.drawerIsOpen)); // 初始化界面状态
    _isFavorite = widget.isChannelFavorite(widget.currentChannelId); // 初始化收藏状态
    _lastIsLandscape = widget.isLandscape; // 初始化横屏状态

    // 添加广告管理器状态监听
    widget.adManager.addListener(_onAdManagerUpdate);

    // 延迟到第一帧渲染后更新广告管理器信息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAdManagerInfo();
    });
  }

  // 更新广告管理器信息
  void _updateAdManagerInfo() {
    if (!mounted) return;
    final mediaQuery = MediaQuery.of(context);
    widget.adManager.updateScreenInfo(
      mediaQuery.size.width,
      mediaQuery.size.height,
      widget.isLandscape,
      this,
    );
    _adManagerNeedsUpdate = false;
  }

  // 响应广告管理器状态变化，标记需更新
  void _onAdManagerUpdate() {
    if (mounted && !_adManagerNeedsUpdate) {
      _adManagerNeedsUpdate = true;
      // 使用微任务批量处理更新
      Future.microtask(() {
        if (mounted && _adManagerNeedsUpdate) {
          setState(() {
            _adManagerNeedsUpdate = false;
          });
        }
      });
    }
  }

  // 计算播放器和进度条尺寸
  void _updateDimensions() {
    if (!mounted || !_needsLayoutRecalculation) return;
    
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final isLandscape = widget.isLandscape;
    
    final isWidthChanged = _adAnimationWidth != width;
    final isOrientationChanged = _lastIsLandscape != isLandscape;
    final isInitialCalculation = _playerHeight == null;
    
    if (isWidthChanged || isOrientationChanged || isInitialCalculation) {
      // 使用常量简化计算
      _playerHeight = width / _aspectRatio;
      _progressBarWidth = width * (isLandscape ? 0.3 : 0.5);
      
      if (isWidthChanged || _adAnimationWidth == null) {
        _adAnimationWidth = width;
      }
      
      _lastIsLandscape = isLandscape;
      _updateAdManagerInfo();
      _needsLayoutRecalculation = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _needsLayoutRecalculation = true; // 标记需重新计算布局
    _updateDimensions(); // 更新尺寸
  }

  @override
  void didUpdateWidget(covariant TableVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 频道变更时更新状态
    if (widget.currentChannelId != oldWidget.currentChannelId) {
      _handleChannelChanged();
    }
    // 抽屉状态变更
    else if (widget.drawerIsOpen != oldWidget.drawerIsOpen) {
      _updateUIState(drawerIsOpen: widget.drawerIsOpen);
    }

    // 横竖屏切换时重新计算尺寸
    if (widget.isLandscape != oldWidget.isLandscape) {
      _needsLayoutRecalculation = true;
      _updateDimensions();
    }
  }

  // 处理频道变更，重置状态
  void _handleChannelChanged() {
    _updateUIState(showPauseIcon: false, showPlayIcon: false); // 重置界面状态
    _cancelPauseIconTimer(); // 取消暂停图标定时器
    _isFavorite = widget.isChannelFavorite(widget.currentChannelId); // 更新收藏状态
    widget.adManager.reset(); // 重置广告状态
  }

  // 取消暂停图标定时器
  void _cancelPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null;
  }

  @override
  void dispose() {
    _cancelPauseIconTimer(); // 释放暂停图标定时器
    _uiStateNotifier.dispose(); // 释放状态管理器
    widget.adManager.removeListener(_onAdManagerUpdate); // 移除广告管理器监听
    super.dispose();
  }

  // 构建视频播放器，支持音频模式
  Widget _buildVideoPlayer(double containerHeight) {
    if (widget.controller == null ||
        !(widget.controller!.isVideoInitialized() ?? false) ||
        widget.isAudio) {
      return VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _currentState.drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      ); // 显示背景占位组件
    }

    // 构建视频播放器，优化容器嵌套
    return SizedBox(
      width: double.infinity,
      height: containerHeight,
      child: ColoredBox(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: IAppPlayer(controller: widget.controller!),
        ),
      ),
    );
  }

  // 处理点击事件，切换播放或暂停
  Future<void> _handleSelectPress() async {
    final isPlaying = widget.controller?.isPlaying() ?? false;
    isPlaying ? await _handlePause() : await _handlePlay(); // 切换播放/暂停
    _toggleMenuBar(); // 切换菜单栏显示
  }

  // 显示暂停图标并设置定时器
  void _showPauseIconWithTimer({bool checkActive = true}) {
    final isTimerActive = _pauseIconTimer?.isActive ?? false;
    
    if (checkActive && isTimerActive) {
      _cancelPauseIconTimer();
      _updateUIState(showPauseIcon: false);
      widget.controller?.pause();
      widget.onUserPaused?.call();
      return;
    }

    _cancelPauseIconTimer();
    _updateUIState(showPauseIcon: true);
    _pauseIconTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _updateUIState(showPauseIcon: false);
    });
  }

  // 处理暂停逻辑
  Future<void> _handlePause() async {
    final isTimerActive = _pauseIconTimer?.isActive ?? false;
    if (!isTimerActive) {
      _showPauseIconWithTimer();
    } else {
      await widget.controller?.pause();
      _cancelPauseIconTimer();
      _updateUIState(showPauseIcon: false);
      widget.onUserPaused?.call();
    }
  }

  // 处理播放逻辑，支持 HLS 重试
  Future<void> _handlePlay() async {
    if (widget.isHls) {
      widget.onRetry?.call(); // HLS 重试
    } else {
      await widget.controller?.play();
      _updateUIState(showPlayIcon: false); // 隐藏播放图标
    }
  }

  // 切换菜单栏显示，仅横屏有效
  void _toggleMenuBar() {
    if (widget.isLandscape) {
      _updateUIState(showMenuBar: !_currentState.showMenuBar);
    }
  }

  // 关闭抽屉并触发回调
  void _closeDrawerIfOpen() {
    if (_currentState.drawerIsOpen) {
      _updateUIState(drawerIsOpen: false);
      widget.onToggleDrawer?.call();
    }
  }

  // 处理双击切换播放/暂停
  Future<void> _togglePlayPause() async {
    try {
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
    } catch (e) {
      LogUtil.e('双击切换播放/暂停失败: $e');
    }
  }

  // 构建控制图标
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

  // 构建统一样式的图标按钮
  Widget buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color iconColor = _iconColor,
    bool showBackground = false,
    double size = _iconButtonSize,
    bool isFavoriteButton = false,
    String? channelId,
  }) {
    // 优化样式创建
    final buttonStyle = showBackground 
        ? IconButton.styleFrom(backgroundColor: _backgroundColor, side: _iconBorderSide) 
        : null;
    
    // 缓存收藏状态
    final isFavorite = isFavoriteButton && channelId != null && _isFavorite;
    final effectiveColor = isFavorite ? Colors.red : iconColor;
    
    final effectiveOnPressed = isFavoriteButton && channelId != null
        ? () {
            widget.toggleFavorite(channelId);
            setState(() {
              _isFavorite = widget.isChannelFavorite(channelId);
            });
          }
        : onPressed;
    
    return SizedBox(
      width: _buttonSize,
      height: _buttonSize,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: buttonStyle,
        icon: Icon(
          icon,
          color: effectiveColor,
          size: size,
        ),
        onPressed: effectiveOnPressed,
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

  // 检查是否显示提示信息和进度条
  bool get _shouldShowToast =>
      widget.toastString != null &&
      !["HIDE_CONTAINER", ""].contains(widget.toastString);

  // 构建提示信息和进度条
  Widget _buildToastWithProgress() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientProgressBar(width: _progressBarWidth!, height: 5), // 显示进度条
            _spacer5,
            ScrollingToastMessage(
              message: widget.toastString!,
              containerWidth: constraints.maxWidth,
              isLandscape: widget.isLandscape,
            ), // 显示滚动提示信息
          ],
        ),
      ),
    );
  }

  // 构建竖屏右侧按钮组
  Widget _buildPortraitRightButtons() {
    return Positioned(
      right: 9,
      bottom: 9,
      child: SizedBox(
        width: _buttonSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildFavoriteButton(widget.currentChannelId, false), // 收藏按钮
            _spacer5,
            buildChangeChannelSourceButton(false), // 切换频道源按钮
            _spacer5,
            buildIconButton(
              icon: Icons.screen_rotation,
              tooltip: S.of(context).landscape,
              onPressed: () async {
                SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
              },
            ), // 切换横屏按钮
          ],
        ),
      ),
    );
  }

  // 构建横屏菜单栏按钮
  List<Widget> _buildMenuBarButtons() {
    return [
      const Spacer(),
      buildIconButton(
        icon: Icons.list_alt,
        tooltip: S.of(context).tipChannelList,
        showBackground: true,
        onPressed: () => LogUtil.safeExecute(() {
          _updateUIState(showMenuBar: false);
          widget.onToggleDrawer?.call();
        }, '安全执行频道切换'),
      ), // 频道列表按钮
      _spacer8,
      buildFavoriteButton(widget.currentChannelId, true), // 收藏按钮
      _spacer8,
      buildChangeChannelSourceButton(true), // 切换频道源按钮
      _spacer8,
      buildIconButton(
        icon: Icons.settings,
        tooltip: S.of(context).settings,
        showBackground: true,
        onPressed: () {
          _closeDrawerIfOpen();
          LogUtil.safeExecute(() {
            _updateUIState(showMenuBar: false);
            Navigator.push(context, MaterialPageRoute(builder: (context) => SettingPage()));
          }, '安全执行设置页面跳转');
        },
      ), // 设置按钮
      _spacer8,
      buildIconButton(
        icon: Icons.screen_rotation,
        tooltip: S.of(context).portrait,
        showBackground: true,
        onPressed: () => LogUtil.safeExecute(() async {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }, '安全执行竖屏切换'),
      ), // 切换竖屏按钮
    ];
  }

  // 构建横屏菜单栏
  Widget _buildLandscapeMenuBar(bool showMenuBar) {
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: showMenuBar ? 18 : -50,
      duration: const Duration(milliseconds: 200),
      child: Container(
        height: _menuHeight,
        padding: _horizontalPadding,
        child: Row(children: _buildMenuBarButtons()),
      ),
    ); // 动态显示横屏菜单栏
  }

  // 构建播放器容器和核心控件
  Widget _buildPlayerContainer(VideoUIState uiState) {
    return Container(
      alignment: Alignment.center,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildVideoPlayer(_playerHeight!), // 视频播放器
          if (widget.showPlayIcon) _buildControlIcon(icon: Icons.play_arrow, onTap: _handleSelectPress), // 播放图标
          if (uiState.showPauseIcon || widget.showPauseIconFromListener) _buildControlIcon(icon: Icons.pause), // 暂停图标
          if (_shouldShowToast) _buildToastWithProgress(), // 提示信息和进度条
        ],
      ),
    );
  }

  // 构建文字广告层
  Widget _buildTextAdLayer() {
    return widget.adManager.buildTextAdWidget(context); // 显示文字广告
  }

  // 构建播放器手势区域
  Widget _buildPlayerGestureDetector(VideoUIState uiState) {
    final isActive = !uiState.drawerIsOpen;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,  // 让播放器点击事件能穿透	
      onTap: isActive ? _handleSelectPress : null,  // 单点切换播放/暂停
      onDoubleTap: isActive ? _togglePlayPause : null, // 双击切换播放/暂停
      child: _buildPlayerContainer(uiState),
    );
  }

  // 构建播放器和控件
  Widget _buildVideoPlayerWithControls() {
    return ValueListenableBuilder<VideoUIState>(
      valueListenable: _uiStateNotifier,
      builder: (context, uiState, _) => Stack(
        children: [
          _buildPlayerGestureDetector(uiState), // 播放器手势区域
          if (!uiState.drawerIsOpen) const VolumeBrightnessWidget(), // 音量亮度控件
          if (widget.isLandscape && !uiState.drawerIsOpen && uiState.showMenuBar) const DatePositionWidget(), // 日期位置显示
          if (widget.isLandscape && !uiState.drawerIsOpen) _buildLandscapeMenuBar(uiState.showMenuBar), // 横屏菜单栏
        ],
      ),
    );
  }

  // 构建图片广告覆盖层
  Widget _buildImageAdOverlay() {
    return widget.adManager.getShowImageAd()
        ? widget.adManager.buildImageAdWidget()
        : const SizedBox.shrink(); // 显示图片广告或空占位
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildVideoPlayerWithControls(), // 播放器和控件层
        _buildTextAdLayer(), // 文字广告层
        if (!widget.isLandscape) _buildPortraitRightButtons(), // 竖屏右下角按钮组
        _buildImageAdOverlay(), // 图片广告层
      ],
    ); // 构建完整播放器界面
  }
}
