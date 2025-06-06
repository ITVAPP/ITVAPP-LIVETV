import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/tv/tv_setting_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:itvapp_live_tv/widget/scrolling_toast_message.dart';
import 'package:itvapp_live_tv/widget/remote_control_help.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart'; 
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/channel_drawer_page.dart';
import 'package:itvapp_live_tv/gradient_progress_bar.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 播放器组件，用于视频播放的核心组件
class VideoPlayerWidget extends StatelessWidget {
  final BetterPlayerController? controller;
  final PlayModel? playModel;
  final String? toastString;
  final bool drawerIsOpen;
  final bool isBuffering;
  final bool isError;
  final bool isAudio;
  final String? currentChannelId;
  final String? currentChannelLogo;
  final String? currentChannelTitle;

  const VideoPlayerWidget({
    Key? key,
    required this.controller,
    this.playModel,
    this.toastString,
    this.currentChannelId,
    this.currentChannelLogo,
    this.currentChannelTitle,
    this.drawerIsOpen = false,
    this.isBuffering = false,
    this.isError = false,
    this.isAudio = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 增加 null 检查，避免强制解包导致的运行时异常，提升代码安全性
        if (controller != null &&
            controller!.isVideoInitialized() == true &&
            !isAudio)
          // 如果控制器已初始化并且不是音频模式，则显示视频
          Center(
            child: AspectRatio(
              aspectRatio: controller!.videoPlayerController?.value.aspectRatio ?? 16 / 9,
              child: BetterPlayer(controller: controller!),
            ),
          )
        else
          // 如果控制器未初始化或是音频模式，则显示背景
          VideoHoldBg(
            currentChannelLogo: currentChannelLogo, // 传递当前频道LOGO
            currentChannelTitle: currentChannelTitle, // 传递当前频道名字
            toastString: drawerIsOpen ? '' : toastString,
            showBingBackground: isAudio,
          ),
      ],
    );
  }
}

// 图标状态管理类，定义视频播放状态图标的显示控制
class IconState {
  final bool showPause;
  final bool showPlay;
  final bool showDatePosition;

  const IconState({
    required this.showPause,
    required this.showPlay,
    required this.showDatePosition,
  });

  IconState copyWith({
    bool? showPause,
    bool? showPlay,
    bool? showDatePosition,
  }) {
    return IconState(
      showPause: showPause ?? this.showPause,
      showPlay: showPlay ?? this.showPlay,
      showDatePosition: showDatePosition ?? this.showDatePosition,
    );
  }
}

// 电视播放页面
class TvPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final Function(PlayModel? newModel)? onTapChannel;
  final BetterPlayerController? controller;
  final Future<void> Function()? changeChannelSources;
  final String? toastString;
  final bool isLandscape;
  final bool isBuffering;
  final Function(String)? toggleFavorite;
  final Function(String)? isChannelFavorite;
  final String? currentChannelId;
  final String? currentChannelLogo;
  final String? currentChannelTitle;
  final bool isAudio;
  final AdManager adManager;
  // 新增参数，与 TableVideoWidget 保持一致
  final bool showPlayIcon; // 从 LiveHomePage 接收播放图标状态
  final bool showPauseIconFromListener; // 从 LiveHomePage 接收暂停图标状态
  final bool isHls; // 是否为 HLS 流
  final VoidCallback? onUserPaused; // 用户暂停回调
  final VoidCallback? onRetry; // HLS 重试回调

  const TvPage({
    super.key,
    this.videoMap,
    this.onTapChannel,
    this.controller,
    this.playModel,
    this.changeChannelSources,
    this.toastString,
    this.isLandscape = false,
    this.isBuffering = false,
    this.toggleFavorite,
    this.isChannelFavorite,
    this.currentChannelId,
    this.currentChannelLogo,
    this.currentChannelTitle,
    this.isAudio = false,
    required this.adManager,
    this.showPlayIcon = false, // 默认值
    this.showPauseIconFromListener = false, // 默认值
    this.isHls = false, // 默认值
    this.onUserPaused,
    this.onRetry,
  });

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> with TickerProviderStateMixin {
  static const Duration _pauseIconDisplayDuration = Duration(seconds: 3);
  // 存储是否显示过帮助的键
  static const String _hasShownHelpKey = 'has_shown_remote_control_help';

  final _iconStateNotifier = ValueNotifier<IconState>(
    const IconState(
      showPause: false,
      showPlay: false,
      showDatePosition: false,
    )
  );

  // 使用 ValueNotifier 管理抽屉状态，减少 setState 调用
  final _drawerOpenNotifier = ValueNotifier<bool>(false);
  
  bool _isError = false;
  Timer? _pauseIconTimer;
  bool _blockSelectKeyEvent = false;
  TvKeyNavigationState? _drawerNavigationState;
  ValueKey<int>? _drawerRefreshKey;
  
  // 优化：使用 Map 结构处理键盘事件，提升查找效率
  late final Map<LogicalKeyboardKey, Future<void> Function()> _keyHandlers;

  @override
  void initState() {
    super.initState();
    
    // 初始化键盘事件处理器
    _initKeyHandlers();
    
    // 检查并显示帮助
    _checkAndShowHelp();
    
    // 添加广告管理器状态监听
    widget.adManager.addListener(_onAdManagerUpdate);
    
    // 初始化图标状态，根据传入的 props 更新
    _updateIconState(
      showPlay: widget.showPlayIcon,
      showPause: widget.showPauseIconFromListener,
    );
    
    // 延迟到第一帧渲染后更新广告管理器信息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAdManagerInfo();
    });
  }
  
  // 优化：初始化键盘事件处理器Map
  void _initKeyHandlers() {
    _keyHandlers = {
      LogicalKeyboardKey.arrowLeft: _handleArrowLeft,
      LogicalKeyboardKey.arrowRight: _handleArrowRight,
      LogicalKeyboardKey.arrowUp: _handleArrowUp,
      LogicalKeyboardKey.arrowDown: _handleArrowDown,
      LogicalKeyboardKey.select: _handleSelectPress,
      LogicalKeyboardKey.enter: _handleSelectPress,
    };
  }
  
  // 优化：拆分键盘事件处理方法
  Future<void> _handleArrowLeft() async {
    // 左箭头用于添加或删除收藏
    if (widget.toggleFavorite != null &&
        widget.isChannelFavorite != null &&
        widget.currentChannelId != null) {
      final bool isFavorite = widget.isChannelFavorite!(widget.currentChannelId!);
      widget.toggleFavorite!(widget.currentChannelId!);

      setState(() {
        // 刷新抽屉中的收藏状态
        _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
      });

      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          isFavorite ? S.of(context).removefavorite : S.of(context).newfavorite,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }
  
  Future<void> _handleArrowRight() async {
    // 右箭头用于打开或关闭抽屉
    _toggleDrawer(!_drawerOpenNotifier.value);
  }
  
  Future<void> _handleArrowUp() async {
    // 上箭头用于切换频道源
    await widget.changeChannelSources?.call();
  }
  
  Future<void> _handleArrowDown() async {
    // 下箭头用于打开设置页面
    _opensetting();
  }
  
  // 新增：更新广告管理器信息的方法
  void _updateAdManagerInfo() {
    if (mounted) {
      final mediaQuery = MediaQuery.of(context);
      widget.adManager.updateScreenInfo(
        mediaQuery.size.width,
        mediaQuery.size.height,
        widget.isLandscape,
        this
      );
    }
  }
  
  // 响应广告管理器状态变化
  void _onAdManagerUpdate() {
    if (mounted) {
      setState(() {
        // 触发界面重建
      });
    }
  }

  // 检查并显示帮助的方法
  Future<void> _checkAndShowHelp() async {
    // 获取是否显示过帮助的状态，默认为 false
    final hasShownHelp = SpUtil.getBool(_hasShownHelpKey, defValue: false) ?? false;

    // 如果没有显示过帮助
    if (!hasShownHelp && mounted) {
      // 显示帮助界面
      await RemoteControlHelp.show(context);
      // 存储已经显示过帮助的状态
      await SpUtil.putBool(_hasShownHelpKey, true);
    }
  }

  // 更新图标状态的方法，控制播放、暂停、显示日期等图标的显隐
  void _updateIconState({
    bool? showPause,
    bool? showPlay,
    bool? showDatePosition,
  }) {
    // 避免在组件销毁后更新状态，提升代码安全性
    if (mounted) {
      _iconStateNotifier.value = _iconStateNotifier.value.copyWith(
        showPause: showPause,
        showPlay: showPlay,
        showDatePosition: showDatePosition,
      );
    }
  }

  // 启动暂停图标显示的定时器，在3秒后自动隐藏暂停图标
  void _startPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = Timer(_pauseIconDisplayDuration, () {
      if (mounted) {
        _updateIconState(showPause: false); // 隐藏暂停图标
      }
    });
  }

  void _clearPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null;
  }

  // 打开设置页面，并更新播放图标状态
  Future<bool?> _opensetting() async {
    try {
      final result = await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return const TvSettingPage();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, -1.0);
            const end = Offset.zero;
            const curve = Curves.ease;
            final tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        ),
      );
      return result;
    } catch (e, stackTrace) {
      LogUtil.logError('打开设置页面时发生错误', e, stackTrace);
      return null;
    }
  }

  // 处理返回按键，当抽屉打开时关闭抽屉；否则检测是否退出应用
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerOpenNotifier.value) {
      _toggleDrawer(false);
      return false;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return false;
    } else {
      // 检查播放器当前播放状态，如果在播放，则暂停
      bool wasPlaying = widget.controller?.isPlaying() ?? false;
      if (wasPlaying) {
        await widget.controller?.pause();
        _updateIconState(showPlay: true); // 显示播放图标
        widget.onUserPaused?.call(); // 通知 LiveHomePage 用户暂停
      }

      bool shouldExit = await ShowExitConfirm.ExitConfirm(context);

      if (!shouldExit && wasPlaying) {
        await widget.controller?.play();
        _updateIconState(showPlay: false); // 继续播放时隐藏播放图标
      }
      return shouldExit;
    }
  }

  // 构建控制图标的通用方法，可以传入不同的图标类型
  Widget _buildControlIcon({
    required IconData icon,
    Color backgroundColor = Colors.black,
    Color iconColor = Colors.white,
  }) {
    return Center(
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
  }

  // 构建暂停图标
  Widget _buildPauseIcon() {
    return _buildControlIcon(icon: Icons.pause);
  }

  // 构建播放图标
  Widget _buildPlayIcon() {
    return _buildControlIcon(icon: Icons.play_arrow);
  }

  // 处理选择键按下的逻辑，包括播放、暂停控制及图标状态更新
  Future<void> _handleSelectPress() async {
    if (_blockSelectKeyEvent) return;
    
    final controller = widget.controller;
    if (controller == null) return;

    final isActuallyPlaying = controller.isPlaying() ?? false; // 检查播放状态

    if (isActuallyPlaying) {
      if (!(_pauseIconTimer?.isActive ?? false)) {
        // 如果计时器未激活，则显示暂停图标
        _updateIconState(
          showPause: true,
          showPlay: false,
        );
        _startPauseIconTimer();
      } else {
        // 如果计时器已激活，则暂停播放并显示播放图标
        await controller.pause();
        _clearPauseIconTimer();
        _updateIconState(
          showPause: false,
          showPlay: true,
        );
        widget.onUserPaused?.call(); // 通知 LiveHomePage 用户暂停
      }
    } else {
      // 如果当前未播放，则启动播放并隐藏播放图标
      if (widget.isHls) {
        widget.onRetry?.call(); // HLS 流调用重试
      } else {
        await controller.play();
        _updateIconState(showPlay: false);
      }
    }

    // 切换时间和收藏图标的显示状态
    _updateIconState(
      showDatePosition: !_iconStateNotifier.value.showDatePosition,
    );
  }

  // 优化：简化键盘事件处理
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    if (e is! KeyUpEvent) return KeyEventResult.handled;

    // 当抽屉打开时，忽略方向键和选择键事件
    if (_drawerOpenNotifier.value &&
        (e.logicalKey == LogicalKeyboardKey.arrowUp ||
            e.logicalKey == LogicalKeyboardKey.arrowDown ||
            e.logicalKey == LogicalKeyboardKey.arrowLeft ||
            e.logicalKey == LogicalKeyboardKey.arrowRight ||
            e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter)) {
      return KeyEventResult.handled;
    }

    // 使用Map查找处理器，提升性能
    final handler = _keyHandlers[e.logicalKey];
    if (handler != null) {
      await handler();
    }
    
    return KeyEventResult.handled;
  }

  // 处理EPG节目点击事件，关闭选择键事件的拦截
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    _blockSelectKeyEvent = true;
    widget.onTapChannel?.call(selectedProgram);
    _toggleDrawer(false);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _blockSelectKeyEvent = false;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 屏幕尺寸或方向变化时更新广告管理器信息
    _updateAdManagerInfo();
  }

  // 资源释放，取消定时器和焦点管理
  @override
  void dispose() {
    _iconStateNotifier.dispose();
    _drawerOpenNotifier.dispose();

    _pauseIconTimer?.cancel();
    _blockSelectKeyEvent = false;

    if (_drawerNavigationState != null) {
      _drawerNavigationState!.deactivateFocusManagement();
      _drawerNavigationState = null;
    }
    
    // 移除广告管理器监听
    widget.adManager.removeListener(_onAdManagerUpdate);
    
    super.dispose();
  }

  // 构建收藏图标
  Widget _buildFavoriteIcon() {
    if (widget.currentChannelId == null || widget.isChannelFavorite == null) {
      return const SizedBox();
    }

    return Positioned(
      right: 28,
      bottom: 28,
      child: Icon(
        widget.isChannelFavorite!(widget.currentChannelId!)
            ? Icons.favorite
            : Icons.favorite_border,
        color: widget.isChannelFavorite!(widget.currentChannelId!) ? Colors.red : Colors.white,
        size: 38,
      ),
    );
  }
  
  // 优化：使用 ValueListenableBuilder 减少重建
  Widget _buildVideoPlayerCore() {
    return VideoPlayerWidget(
      controller: widget.controller,
      playModel: widget.playModel,
      toastString: widget.toastString,
      currentChannelLogo: widget.currentChannelLogo,
      currentChannelTitle: widget.currentChannelTitle,
      drawerIsOpen: _drawerOpenNotifier.value,
      isBuffering: widget.isBuffering,
      isError: _isError,
      isAudio: widget.isAudio,
    );
  }

  // 构建进度条和提示信息
  Widget _buildToastAndProgress() {
    // 计算进度条宽度，保持与 TableVideoWidget 一致的逻辑
    final progressBarWidth = widget.isLandscape
        ? MediaQuery.of(context).size.width * 0.3
        : MediaQuery.of(context).size.width * 0.5;
    
    if (widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString)) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 12,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GradientProgressBar(
                width: progressBarWidth,
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
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  // 优化：使用 ValueListenableBuilder 局部更新控制图标
  Widget _buildControlIcons() {
    return ValueListenableBuilder<IconState>(
      valueListenable: _iconStateNotifier,
      builder: (context, iconState, child) {
        return Stack(
          children: [
            // 显示暂停图标：优先使用从 LiveHomePage 传入的状态
            if (widget.showPauseIconFromListener || iconState.showPause) _buildPauseIcon(),
            // 显示播放图标：优先使用从 LiveHomePage 传入的状态
            if (widget.showPlayIcon || iconState.showPlay) _buildPlayIcon(),
            if (iconState.showDatePosition) const DatePositionWidget(),
            if (iconState.showDatePosition) 
              ValueListenableBuilder<bool>(
                valueListenable: _drawerOpenNotifier,
                builder: (context, isOpen, child) => 
                  isOpen ? const SizedBox.shrink() : _buildFavoriteIcon(),
              ),
          ],
        );
      },
    );
  }

  // 优化：使用 ValueListenableBuilder 局部更新频道抽屉
  Widget _buildChannelDrawer() {
    return ValueListenableBuilder<bool>(
      valueListenable: _drawerOpenNotifier,
      builder: (context, isOpen, child) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Offstage(
            offstage: !isOpen,
            child: ChannelDrawerPage(
              key: _drawerRefreshKey ?? const ValueKey('channel_drawer'),
              refreshKey: _drawerRefreshKey,
              videoMap: widget.videoMap,
              playModel: widget.playModel,
              isLandscape: true,
              onTapChannel: _handleEPGProgramTap,
              onCloseDrawer: () {
                _toggleDrawer(false);
              },
              onTvKeyNavigationStateCreated: (state) {
                _drawerNavigationState = state;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (isOpen) {
                    state.activateFocusManagement();
                  } else {
                    state.deactivateFocusManagement();
                  }
                });
              },
            ),
          ),
        );
      },
    );
  }
  
  // 构建文字广告层
  Widget _buildTextAdOverlay() {
    return widget.adManager.buildTextAdWidget();
  }
  
  // 构建图片广告层
  Widget _buildImageAdOverlay() {
    return widget.adManager.getShowImageAd() 
        ? widget.adManager.buildImageAdWidget() 
        : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _handleBackPress(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(builder: (context) {
          return KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e),
            child: Container(
              alignment: Alignment.center,
              color: Colors.black,
              child: Stack(
                children: [
                  // 优化：使用 ValueListenableBuilder 包装需要响应抽屉状态的组件
                  ValueListenableBuilder<bool>(
                    valueListenable: _drawerOpenNotifier,
                    builder: (context, isOpen, child) => _buildVideoPlayerCore(),
                  ),
                  
                  // 进度条和提示信息层
                  _buildToastAndProgress(),
                  
                  // 控制图标层
                  _buildControlIcons(),
                  
                  // 频道抽屉层
                  _buildChannelDrawer(),
                  
                  // 文字广告作为独立层
                  _buildTextAdOverlay(),
                  
                  // 图片广告作为最顶层
                  _buildImageAdOverlay(),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // 控制抽屉的显示和焦点管理
  void _toggleDrawer(bool isOpen) {
    if (_drawerOpenNotifier.value == isOpen) return;

    _drawerOpenNotifier.value = isOpen;

    if (_drawerNavigationState != null) {
      if (isOpen) {
        _drawerNavigationState!.activateFocusManagement();
      } else {
        _drawerNavigationState!.deactivateFocusManagement();
      }
    }
  }
}
