import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sp_util/sp_util.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/tv/tv_setting_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
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

// 图标状态管理类，控制播放、暂停、日期图标显示状态
class IconState {
  final bool showPause;
  final bool showPlay;
  final bool showDatePosition;

  const IconState({
    required this.showPause,
    required this.showPlay,
    required this.showDatePosition,
  });

  // 创建新状态实例，支持部分属性更新
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

// 电视播放页面，集成播放器、抽屉、广告及键盘事件处理
class TvPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final Function(PlayModel? newModel)? onTapChannel;
  final BetterPlayerController? controller;
  final Future<void> Function()? changeChannelSources;
  final GestureTapCallback? onChangeSubSource;
  final String? toastString;
  final bool isLandscape;
  final bool isBuffering;
  final bool isPlaying;
  final double aspectRatio;
  final Function(String)? toggleFavorite;
  final Function(String)? isChannelFavorite;
  final String? currentChannelId;
  final String? currentChannelLogo;
  final String? currentChannelTitle;
  final bool isAudio;
  final AdManager adManager;
  final bool showPlayIcon;
  final bool showPauseIconFromListener;
  final bool isHls;
  final VoidCallback? onUserPaused;
  final VoidCallback? onRetry;

  const TvPage({
    super.key,
    this.videoMap,
    this.onTapChannel,
    this.controller,
    this.playModel,
    this.changeChannelSources,
    this.onChangeSubSource,
    this.toastString,
    this.isLandscape = false,
    this.isBuffering = false,
    this.isPlaying = false,
    this.aspectRatio = 16 / 9,
    this.toggleFavorite,
    this.isChannelFavorite,
    this.currentChannelId,
    this.currentChannelLogo,
    this.currentChannelTitle,
    this.isAudio = false,
    required this.adManager,
    this.showPlayIcon = false,
    this.showPauseIconFromListener = false,
    this.isHls = false,
    this.onUserPaused,
    this.onRetry,
  });

  @override
  State<TvPage> createState() => _TvPageState();
}

// 电视播放页面状态类，管理图标、抽屉、广告及键盘事件
class _TvPageState extends State<TvPage> with TickerProviderStateMixin {
  static const Duration _pauseIconDisplayDuration = Duration(seconds: 3);
  static const String _hasShownHelpKey = 'has_shown_remote_control_help';
  static const double _aspectRatio = 16.0 / 9.0; // 固定宽高比
  
  static final _controlIconDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.black.withOpacity(0.5),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.7),
        spreadRadius: 2,
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );

  final _iconStateNotifier = ValueNotifier<IconState>(
    const IconState(
      showPause: false,
      showPlay: false,
      showDatePosition: false,
    )
  );

  bool _drawerIsOpen = false;
  bool _isError = false;
  Timer? _pauseIconTimer;
  bool _blockSelectKeyEvent = false;
  TvKeyNavigationState? _drawerNavigationState;
  ValueKey<int>? _drawerRefreshKey;
  bool _isShowingHelp = false;
  bool _isShowingSourceMenu = false;
  
  // 添加持久的FocusNode
  late final FocusNode _keyboardFocusNode;

  // 初始化状态，设置延迟帮助显示、广告监听及图标状态
  @override
  void initState() {
    super.initState();
    // 创建持久的FocusNode
    _keyboardFocusNode = FocusNode();
    
    widget.adManager.addListener(_onAdManagerUpdate);
    _updateIconState(
      showPlay: widget.showPlayIcon,
      showPause: widget.showPauseIconFromListener,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 确保焦点被正确设置
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
      _updateAdManagerInfo();
      // 先检查是否需要显示帮助
      final hasShownHelp = SpUtil.getBool(_hasShownHelpKey, defValue: false) ?? false;
      if (!hasShownHelp) {
        // 只有首次使用才延迟10秒显示帮助页面
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) {
            _checkAndShowHelp();
          }
        });
      }
    });
  }
  
  // 更新广告管理器屏幕信息
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
  
  // 响应广告管理器状态变化，触发界面重绘
  void _onAdManagerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  // 检查并显示遥控帮助页面
  Future<void> _checkAndShowHelp() async {
    final hasShownHelp = SpUtil.getBool(_hasShownHelpKey, defValue: false) ?? false;
    if (hasShownHelp || !mounted) return;
    
    // 如果抽屉正在打开，1秒后重新检查
    if (_drawerIsOpen) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _checkAndShowHelp();
        }
      });
      return;
    }
    
    // 抽屉已关闭，显示帮助页面
    setState(() {
      _isShowingHelp = true;
    });
    await RemoteControlHelp.show(context);
    await SpUtil.putBool(_hasShownHelpKey, true);
    if (mounted) {
      // 延迟关闭帮助状态，防止按键冲突
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _isShowingHelp = false;
          });
        }
      });
    }
  }

  // 更新播放、暂停、日期图标显示状态
  void _updateIconState({
    bool? showPause,
    bool? showPlay,
    bool? showDatePosition,
  }) {
    if (mounted) {
      _iconStateNotifier.value = _iconStateNotifier.value.copyWith(
        showPause: showPause,
        showPlay: showPlay,
        showDatePosition: showDatePosition,
      );
    }
  }

  // 启动暂停图标显示定时器
  void _startPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = Timer(_pauseIconDisplayDuration, () {
      if (mounted) {
        _updateIconState(showPause: false);
      }
    });
  }

  // 清除暂停图标定时器
  void _clearPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null;
  }

  // 打开设置页面并处理导航结果
  Future<bool?> _opensetting() async {
    try {
      final result = await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return const TvSettingPage();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            var begin = const Offset(0.0, -1.0);
            var end = Offset.zero;
            var curve = Curves.ease;
            var tween = Tween(begin: begin, end: end).chain(
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
      LogUtil.logError('打开设置页面失败', e, stackTrace);
      return null;
    }
  }

  // 处理返回键，控制抽屉关闭或应用退出
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      _toggleDrawer(false);
      return false;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return false;
    } else {
      bool wasPlaying = widget.controller?.isPlaying() ?? false;
      if (wasPlaying) {
        await widget.controller?.pause();
        _updateIconState(showPlay: true);
        widget.onUserPaused?.call();
      }
      bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
      if (!shouldExit && wasPlaying) {
        await widget.controller?.play();
        _updateIconState(showPlay: false);
      }
      return shouldExit;
    }
  }

  // 构建控制图标，设置图标样式及背景
  Widget _buildControlIcon({
    required IconData icon,
  }) {
    return Center(
      child: Container(
        decoration: _controlIconDecoration,
        padding: const EdgeInsets.all(10.0),
        child: Icon(
          icon,
          size: 78,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    );
  }

  // 处理选择键，控制播放/暂停及图标状态切换
  Future<void> _handleSelectPress() async {
    final controller = widget.controller;
    if (controller == null) return;
    final isActuallyPlaying = controller.isPlaying() ?? false;
    if (isActuallyPlaying) {
      if (!(_pauseIconTimer?.isActive ?? false)) {
        _updateIconState(showPause: true, showPlay: false);
        _startPauseIconTimer();
      } else {
        await controller.pause();
        _clearPauseIconTimer();
        _updateIconState(showPause: false, showPlay: true);
        widget.onUserPaused?.call();
      }
    } else {
      if (widget.isHls) {
        widget.onRetry?.call();
      } else {
        await controller.play();
        _updateIconState(showPlay: false);
      }
    }
    _updateIconState(showDatePosition: !_iconStateNotifier.value.showDatePosition);
  }

  // 处理键盘事件，响应方向键及选择键 - 修复事件传递问题
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    // 只处理 KeyUpEvent，其他事件让它继续传递
    if (e is! KeyUpEvent) return KeyEventResult.ignored;
    
    // 当处于特殊界面时，阻止方向键和选择键
    if ((_drawerIsOpen || _isShowingHelp || _isShowingSourceMenu) &&
        (e.logicalKey == LogicalKeyboardKey.arrowUp ||
            e.logicalKey == LogicalKeyboardKey.arrowDown ||
            e.logicalKey == LogicalKeyboardKey.arrowLeft ||
            e.logicalKey == LogicalKeyboardKey.arrowRight ||
            e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter)) {
      return KeyEventResult.handled;
    }
    
    // 处理特定按键
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        // 切换频道收藏状态并刷新抽屉
        if (widget.toggleFavorite != null &&
            widget.isChannelFavorite != null &&
            widget.currentChannelId != null) {
          final bool isFavorite = widget.isChannelFavorite!(widget.currentChannelId!);
          widget.toggleFavorite!(widget.currentChannelId!);
          setState(() {
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
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        // 切换频道抽屉显示状态
        _toggleDrawer(!_drawerIsOpen);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        // 显示并切换频道源
        if (widget.changeChannelSources != null) {
          setState(() {
            _isShowingSourceMenu = true;
          });
          try {
            await widget.changeChannelSources!();
          } finally {
            // 延迟关闭源菜单状态，防止按键冲突
            if (mounted) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  setState(() {
                    _isShowingSourceMenu = false;
                  });
                }
              });
            }
          }
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        // 打开设置页面
        _opensetting();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        // 处理播放/暂停逻辑
        if (!_blockSelectKeyEvent) {
          await _handleSelectPress();
        }
        return KeyEventResult.handled;
      default:
        // 其他按键不处理，让事件继续传递
        return KeyEventResult.ignored;
    }
  }

  // 处理EPG节目点击，更新频道并拦截选择键
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    _blockSelectKeyEvent = true;
    widget.onTapChannel?.call(selectedProgram);
    _toggleDrawer(false);
    // 延迟解除选择键拦截
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _blockSelectKeyEvent = false;
        });
      }
    });
  }

  // 屏幕尺寸或方向变化时更新广告信息
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAdManagerInfo();
  }

  // 清理资源，释放定时器及焦点管理
  @override
  void dispose() {
    _iconStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    _blockSelectKeyEvent = false;
    _drawerNavigationState?.deactivateFocusManagement();
    _drawerNavigationState = null;
    widget.adManager.removeListener(_onAdManagerUpdate);
    // 释放FocusNode
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // 构建收藏图标，仅显示已收藏频道
  Widget _buildFavoriteIcon() {
    if (widget.currentChannelId == null || widget.isChannelFavorite == null) {
      return const SizedBox.shrink();
    }
    if (!widget.isChannelFavorite!(widget.currentChannelId!)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      right: 28,
      bottom: 28,
      child: const Icon(
        Icons.favorite,
        color: Colors.red,
        size: 38,
      ),
    );
  }
  
  // 构建视频播放器 - 采用与移动端相似的结构
  Widget _buildVideoPlayer(double containerHeight) {
    if (widget.controller == null ||
        !(widget.controller!.isVideoInitialized() ?? false) ||
        widget.isAudio) {
      return VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      );
    }

    // 使用与移动端相似的布局结构
    return SizedBox(
      width: double.infinity,
      height: containerHeight,
      child: ColoredBox(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 16,
              height: 9,
              child: BetterPlayer(controller: widget.controller!),
            ),
          ),
        ),
      ),
    );
  }

  // 构建进度条及提示信息
  Widget _buildToastAndProgress() {
    if (widget.toastString == null || widget.toastString == "HIDE_CONTAINER" || widget.toastString!.isEmpty) {
      return const SizedBox.shrink();
    }
    final progressBarWidth = MediaQuery.of(context).size.width * 0.3;
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
  }

  // 构建播放器容器和核心控件 - 采用与移动端相似的结构
  Widget _buildPlayerContainer() {
    final mediaQuery = MediaQuery.of(context);
    final playerHeight = mediaQuery.size.width / _aspectRatio;
    
    return Container(
      alignment: Alignment.center,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildVideoPlayer(playerHeight),
          if (widget.showPlayIcon || _iconStateNotifier.value.showPlay) 
            _buildControlIcon(icon: Icons.play_arrow),
          if (_iconStateNotifier.value.showPause || widget.showPauseIconFromListener) 
            _buildControlIcon(icon: Icons.pause),
          if (_buildToastAndProgress() is! SizedBox) _buildToastAndProgress(),
        ],
      ),
    );
  }

  // 构建频道抽屉
  Widget _buildChannelDrawer() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Offstage(
        offstage: !_drawerIsOpen,
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
            setState(() {
              _drawerNavigationState = state;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_drawerIsOpen) {
                state.activateFocusManagement();
              } else {
                state.deactivateFocusManagement();
              }
            });
          },
        ),
      ),
    );
  }
  
  // 构建文字广告层
  Widget _buildTextAdOverlay() {
    return widget.adManager.buildTextAdWidget(context);
  }
  
  // 构建图片广告层
  Widget _buildImageAdOverlay() {
    return widget.adManager.getShowImageAd() 
        ? widget.adManager.buildImageAdWidget() 
        : const SizedBox.shrink();
  }

  // 构建页面主视图，集成键盘监听及UI组件
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _handleBackPress(context),
      child: Scaffold(
        body: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: KeyboardListener(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e),
            child: Stack(
              children: [
                // 播放器层 - 采用与移动端相似的手势处理
                GestureDetector(
                  onTap: !_drawerIsOpen && !_blockSelectKeyEvent ? _handleSelectPress : null,
                  child: _buildPlayerContainer(),
                ),
                // 控制图标层
                ValueListenableBuilder<IconState>(
                  valueListenable: _iconStateNotifier,
                  builder: (context, iconState, child) {
                    return Stack(
                      children: [
                        if (iconState.showDatePosition) const DatePositionWidget(),
                        if (!_drawerIsOpen) _buildFavoriteIcon(),
                      ],
                    );
                  },
                ),
                // 抽屉层
                _buildChannelDrawer(),
                // 广告层
                _buildTextAdOverlay(),
                _buildImageAdOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 控制抽屉显示及焦点管理
  void _toggleDrawer(bool isOpen) {
    if (_drawerIsOpen == isOpen) return;
    setState(() {
      _drawerIsOpen = isOpen;
    });
    if (_drawerNavigationState != null) {
      if (isOpen) {
        _drawerNavigationState!.activateFocusManagement();
      } else {
        _drawerNavigationState!.deactivateFocusManagement();
        // 抽屉关闭时，确保焦点回到主界面
        if (mounted) {
          _keyboardFocusNode.requestFocus();
        }
      }
    }
  }
}
