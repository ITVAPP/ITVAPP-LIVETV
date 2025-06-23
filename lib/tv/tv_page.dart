import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sp_util/sp_util.dart';
import 'package:iapp_player/iapp_player.dart';
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

// TV页面UI状态管理类，统一管理所有UI相关状态
class TvUIState {
  final bool showPause; // 是否显示暂停图标
  final bool showPlay; // 是否显示播放图标
  final bool showDatePosition; // 是否显示日期位置
  final bool drawerIsOpen; // 抽屉是否打开
  final bool isShowingHelp; // 是否显示遥控帮助
  final bool isShowingSourceMenu; // 是否显示线路选择菜单
  final bool isFavorite; // 当前频道是否为收藏
  final bool showImageAd; // 是否显示图片广告
  final int drawerRefreshKey; // 抽屉刷新键
  final int adUpdateKey; // 广告更新键

  const TvUIState({
    this.showPause = false,
    this.showPlay = false,
    this.showDatePosition = false,
    this.drawerIsOpen = false,
    this.isShowingHelp = false,
    this.isShowingSourceMenu = false,
    this.isFavorite = false,
    this.showImageAd = false,
    this.drawerRefreshKey = 0,
    this.adUpdateKey = 0,
  });

  // 创建新状态实例，支持部分属性更新
  TvUIState copyWith({
    bool? showPause,
    bool? showPlay,
    bool? showDatePosition,
    bool? drawerIsOpen,
    bool? isShowingHelp,
    bool? isShowingSourceMenu,
    bool? isFavorite,
    bool? showImageAd,
    int? drawerRefreshKey,
    int? adUpdateKey,
  }) {
    return TvUIState(
      showPause: showPause ?? this.showPause,
      showPlay: showPlay ?? this.showPlay,
      showDatePosition: showDatePosition ?? this.showDatePosition,
      drawerIsOpen: drawerIsOpen ?? this.drawerIsOpen,
      isShowingHelp: isShowingHelp ?? this.isShowingHelp,
      isShowingSourceMenu: isShowingSourceMenu ?? this.isShowingSourceMenu,
      isFavorite: isFavorite ?? this.isFavorite,
      showImageAd: showImageAd ?? this.showImageAd,
      drawerRefreshKey: drawerRefreshKey ?? this.drawerRefreshKey,
      adUpdateKey: adUpdateKey ?? this.adUpdateKey,
    );
  }
}

// 电视播放页面，集成播放器、抽屉、广告及键盘事件处理
class TvPage extends StatefulWidget {
  final PlaylistModel? videoMap; // 视频播放列表
  final PlayModel? playModel; // 当前播放模型
  final Function(PlayModel? newModel)? onTapChannel; // 频道点击回调
  final IAppPlayerController? controller; // 视频播放控制器
  final Future<void> Function()? changeChannelSources; // 切换频道源回调
  final GestureTapCallback? onChangeSubSource; // 切换子源回调
  final String? toastString; // 提示信息
  final bool isLandscape; // 是否为横屏
  final bool isBuffering; // 是否在缓冲
  final bool isPlaying; // 是否在播放
  final double aspectRatio; // 视频宽高比
  final Function(String)? toggleFavorite; // 切换收藏状态回调
  final Function(String)? isChannelFavorite; // 判断频道是否收藏回调
  final String? currentChannelId; // 当前频道ID
  final String? currentChannelLogo; // 当前频道Logo
  final String? currentChannelTitle; // 当前频道标题
  final bool isAudio; // 是否为音频模式
  final AdManager adManager; // 广告管理器
  final bool showPlayIcon; // 是否显示播放图标
  final bool showPauseIconFromListener; // 是否显示暂停图标（来自监听器）
  final bool isHls; // 是否为HLS流
  final VoidCallback? onUserPaused; // 用户暂停回调
  final VoidCallback? onRetry; // 重试回调

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

// 电视播放页面状态类，管理UI状态及键盘事件
class _TvPageState extends State<TvPage> with TickerProviderStateMixin {
  // 常量定义
  static const Duration _pauseIconDisplayDuration = Duration(seconds: 3); // 暂停图标显示时长
  static const Duration _helpShowDelay = Duration(seconds: 10); // 帮助页面显示延迟
  static const Duration _helpRecheckDelay = Duration(seconds: 1); // 帮助页面重新检查延迟
  static const Duration _blockSelectDelay = Duration(milliseconds: 500); // 选择键拦截延迟
  static const Duration _sourceMenuCloseDelay = Duration(milliseconds: 500); // 线路菜单关闭延迟
  static const Duration _helpCloseDelay = Duration(milliseconds: 1000); // 帮助页面关闭延迟
  static const Duration _snackBarDuration = Duration(seconds: 4); // 提示条显示时长
  static const String _hasShownHelpKey = 'has_shown_remote_control_help'; // 帮助页面显示状态键
  static const double _aspectRatio = 16 / 9; // 默认视频宽高比
  static const double _iconSize = 78.0; // 控制图标尺寸
  static const double _iconPadding = 10.0; // 控制图标内边距
  static const double _favoriteIconSize = 38.0; // 收藏图标尺寸
  static const double _favoriteIconOffset = 28.0; // 收藏图标偏移量
  static const double _progressBarHeight = 5.0; // 进度条高度
  static const double _progressBarBottomOffset = 12.0; // 进度条底部偏移
  static const double _progressBarWidthRatioLandscape = 0.3; // 横屏进度条宽度比例
  static const double _progressBarWidthRatioPortrait = 0.5; // 竖屏进度条宽度比例
  
  // 控制图标装饰样式
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

  // UI状态管理器
  late final ValueNotifier<TvUIState> _uiStateNotifier;
  // 获取当前UI状态
  TvUIState get _currentState => _uiStateNotifier.value;

  bool _isError = false; // 播放错误状态
  Timer? _pauseIconTimer; // 暂停图标定时器
  bool _blockSelectKeyEvent = false; // 拦截选择键事件
  TvKeyNavigationState? _drawerNavigationState; // 抽屉导航状态
  
  // 键盘焦点节点
  late final FocusNode _keyboardFocusNode;

  // 更新UI状态
  void _updateUIState({
    bool? showPause,
    bool? showPlay,
    bool? showDatePosition,
    bool? drawerIsOpen,
    bool? isShowingHelp,
    bool? isShowingSourceMenu,
    bool? isFavorite,
    bool? showImageAd,
    int? drawerRefreshKey,
    int? adUpdateKey,
  }) {
    if (mounted) {
      _uiStateNotifier.value = _currentState.copyWith(
        showPause: showPause,
        showPlay: showPlay,
        showDatePosition: showDatePosition,
        drawerIsOpen: drawerIsOpen,
        isShowingHelp: isShowingHelp,
        isShowingSourceMenu: isShowingSourceMenu,
        isFavorite: isFavorite,
        showImageAd: showImageAd,
        drawerRefreshKey: drawerRefreshKey,
        adUpdateKey: adUpdateKey,
      );
    }
  }

  // 初始化状态
  @override
  void initState() {
    super.initState();
    
    // 设置全屏模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
    // 初始化键盘焦点
    _keyboardFocusNode = FocusNode();
    
    // 初始化UI状态
    _uiStateNotifier = ValueNotifier(TvUIState(
      showPlay: widget.showPlayIcon,
      showPause: widget.showPauseIconFromListener,
      isFavorite: widget.isChannelFavorite?.call(widget.currentChannelId ?? '') ?? false,
      showImageAd: widget.adManager.getShowImageAd(),
    ));
    
    // 添加广告管理器监听
    widget.adManager.addListener(_onAdManagerUpdate);
    
    // 延迟执行初始化任务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAdManagerInfo();
      // 检查是否需要显示帮助
      final hasShownHelp = SpUtil.getBool(_hasShownHelpKey, defValue: false) ?? false;
      if (!hasShownHelp) {
        Future.delayed(_helpShowDelay, () {
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
  
  // 响应广告管理器更新
  void _onAdManagerUpdate() {
    if (mounted) {
      _updateUIState(
        showImageAd: widget.adManager.getShowImageAd(),
        adUpdateKey: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  // 检查并显示遥控帮助
  Future<void> _checkAndShowHelp() async {
    final hasShownHelp = SpUtil.getBool(_hasShownHelpKey, defValue: false) ?? false;
    if (hasShownHelp || !mounted) return;
    
    // 抽屉打开时延迟检查
    if (_currentState.drawerIsOpen) {
      Future.delayed(_helpRecheckDelay, () {
        if (mounted) {
          _checkAndShowHelp();
        }
      });
      return;
    }
    
    // 显示帮助页面
    _updateUIState(isShowingHelp: true);
    await RemoteControlHelp.show(context);
    await SpUtil.putBool(_hasShownHelpKey, true);
    if (mounted) {
      // 延迟关闭帮助状态
      Future.delayed(_helpCloseDelay, () {
        if (mounted) {
          _updateUIState(isShowingHelp: false);
        }
      });
    }
  }

  // 启动暂停图标定时器
  void _startPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = Timer(_pauseIconDisplayDuration, () {
      if (mounted) {
        _updateUIState(showPause: false);
      }
    });
  }

  // 清除暂停图标定时器
  void _clearPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null;
  }

  // 打开设置页面
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

  // 处理返回键
  Future<bool> _handleBackPress(BuildContext context) async {
    // 处理帮助页面或线路菜单
    if (_currentState.isShowingHelp || _currentState.isShowingSourceMenu) {
      _updateUIState(isShowingHelp: false, isShowingSourceMenu: false);
      return false;
    }
    
    // 关闭抽屉
    if (_currentState.drawerIsOpen) {
      _toggleDrawer(false);
      return false;
    }
    
    // 处理页面导航
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return false;
    } else {
      bool wasPlaying = widget.controller?.isPlaying() ?? false;
      if (wasPlaying) {
        await widget.controller?.pause();
        _updateUIState(showPlay: true);
        widget.onUserPaused?.call();
      }
      bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
      if (!shouldExit && wasPlaying) {
        await widget.controller?.play();
        _updateUIState(showPlay: false);
      }
      return shouldExit;
    }
  }

  // 构建控制图标
  Widget _buildControlIcon({
    required IconData icon,
  }) {
    return Center(
      child: Container(
        decoration: _controlIconDecoration,
        padding: const EdgeInsets.all(_iconPadding),
        child: Icon(
          icon,
          size: _iconSize,
          color: Colors.white.withOpacity(0.85),
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

  // 处理选择键
  Future<void> _handleSelectPress() async {
    final controller = widget.controller;
    if (controller == null) return;
    final isActuallyPlaying = controller.isPlaying() ?? false;
    if (isActuallyPlaying) {
      // 显示暂停图标
      if (!(_pauseIconTimer?.isActive ?? false)) {
        _updateUIState(showPause: true, showPlay: false);
        _startPauseIconTimer();
      } else {
        // 暂停播放
        await controller.pause();
        _clearPauseIconTimer();
        _updateUIState(showPause: false, showPlay: true);
        widget.onUserPaused?.call();
      }
    } else {
      // 恢复播放或重试
      if (widget.isHls) {
        widget.onRetry?.call();
      } else {
        await controller.play();
        _updateUIState(showPlay: false);
      }
    }
    // 切换日期位置显示
    _updateUIState(showDatePosition: !_currentState.showDatePosition);
  }

  // 处理左方向键 - 切换收藏
  void _handleLeftArrowKey() {
    if (widget.toggleFavorite != null &&
        widget.isChannelFavorite != null &&
        widget.currentChannelId != null) {
      widget.toggleFavorite!(widget.currentChannelId!);
      final newFavoriteState = widget.isChannelFavorite!(widget.currentChannelId!);
      _updateUIState(
        isFavorite: newFavoriteState,
        drawerRefreshKey: DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) {
        CustomSnackBar.showSnackBar(
          context,
          newFavoriteState ? S.of(context).newfavorite : S.of(context).removefavorite,
          duration: _snackBarDuration,
        );
      }
    }
  }

  // 处理右方向键 - 切换抽屉
  void _handleRightArrowKey() {
    _toggleDrawer(!_currentState.drawerIsOpen);
  }

  // 处理上方向键 - 切换频道源
  Future<void> _handleUpArrowKey() async {
    if (widget.changeChannelSources != null) {
      _updateUIState(isShowingSourceMenu: true);
      try {
        await widget.changeChannelSources!();
      } finally {
        if (mounted) {
          Future.delayed(_sourceMenuCloseDelay, () {
            if (mounted) {
              _updateUIState(isShowingSourceMenu: false);
            }
          });
        }
      }
    }
  }

  // 处理下方向键 - 打开设置
  void _handleDownArrowKey() {
    _opensetting();
  }

  // 处理键盘事件
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    if (e is! KeyUpEvent) return KeyEventResult.handled;
    
    // 拦截抽屉、帮助或线路菜单中的方向键及选择键
    if ((_currentState.drawerIsOpen || _currentState.isShowingHelp || _currentState.isShowingSourceMenu) &&
        (e.logicalKey == LogicalKeyboardKey.arrowUp ||
            e.logicalKey == LogicalKeyboardKey.arrowDown ||
            e.logicalKey == LogicalKeyboardKey.arrowLeft ||
            e.logicalKey == LogicalKeyboardKey.arrowRight ||
            e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter)) {
      return KeyEventResult.handled;
    }
    
    // 处理键盘事件
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _handleLeftArrowKey();
        break;
      case LogicalKeyboardKey.arrowRight:
        _handleRightArrowKey();
        break;
      case LogicalKeyboardKey.arrowUp:
        await _handleUpArrowKey();
        break;
      case LogicalKeyboardKey.arrowDown:
        _handleDownArrowKey();
        break;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        if (!_blockSelectKeyEvent) {
          await _handleSelectPress();
        }
        break;
      case LogicalKeyboardKey.f5:
        break;
      default:
        break;
    }
    return KeyEventResult.handled;
  }

  // 处理EPG节目点击
  void _handleEPGProgramTap(PlayModel? selectedProgram) {
    _blockSelectKeyEvent = true;
    widget.onTapChannel?.call(selectedProgram);
    _toggleDrawer(false);
    Future.delayed(_blockSelectDelay, () {
      if (mounted) {
        _blockSelectKeyEvent = false;
      }
    });
  }

  // 处理屏幕尺寸或方向变化
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAdManagerInfo();
  }

  // 处理组件更新
  @override
  void didUpdateWidget(covariant TvPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 更新收藏状态
    if (widget.currentChannelId != oldWidget.currentChannelId) {
      _updateUIState(
        isFavorite: widget.isChannelFavorite?.call(widget.currentChannelId ?? '') ?? false
      );
    }
  }

  // 清理资源
  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _uiStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    _blockSelectKeyEvent = false;
    _drawerNavigationState?.deactivateFocusManagement();
    _drawerNavigationState = null;
    widget.adManager.removeListener(_onAdManagerUpdate);
    super.dispose();
  }

  // 构建收藏图标
  Widget _buildFavoriteIcon(bool drawerIsOpen, bool isFavorite) {
    if (widget.currentChannelId == null || 
        widget.isChannelFavorite == null || 
        !isFavorite || 
        drawerIsOpen) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      right: _favoriteIconOffset,
      bottom: _favoriteIconOffset,
      child: const Icon(
        Icons.favorite,
        color: Colors.red,
        size: _favoriteIconSize,
      ),
    );
  }
  
  // 构建视频播放器
  Widget _buildVideoPlayerCore() {
    if (widget.controller == null ||
        !(widget.controller!.isVideoInitialized() ?? false) ||
        widget.isAudio) {
      return VideoHoldBg(
        currentChannelLogo: widget.currentChannelLogo,
        currentChannelTitle: widget.currentChannelTitle,
        toastString: _currentState.drawerIsOpen ? '' : widget.toastString,
        showBingBackground: widget.isAudio,
      );
    }
    
    // 构建视频播放界面
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: IAppPlayer(controller: widget.controller!),
        ),
      ),
    );
  }

  // 构建进度条及提示信息
  Widget _buildToastAndProgress() {
    if (widget.toastString == null || 
        widget.toastString == "HIDE_CONTAINER" || 
        widget.toastString!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final progressBarWidth = MediaQuery.of(context).size.width * 
        (widget.isLandscape ? _progressBarWidthRatioLandscape : _progressBarWidthRatioPortrait);
    
    return Positioned(
      left: 0,
      right: 0,
      bottom: _progressBarBottomOffset,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientProgressBar(
              width: progressBarWidth,
              height: _progressBarHeight,
            ),
            const SizedBox(height: _progressBarHeight),
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

  // 构建控制图标层
  Widget _buildControlIcons(TvUIState uiState) {
    return Stack(
      children: [
        if (widget.showPauseIconFromListener || uiState.showPause) _buildPauseIcon(),
        if (widget.showPlayIcon || uiState.showPlay) _buildPlayIcon(),
        if (uiState.showDatePosition) const DatePositionWidget(),
        _buildFavoriteIcon(uiState.drawerIsOpen, uiState.isFavorite),
      ],
    );
  }

  // 构建频道抽屉
  Widget _buildChannelDrawerContent(int refreshKey) {
    return ChannelDrawerPage(
      key: ValueKey('channel_drawer_$refreshKey'),
      refreshKey: ValueKey(refreshKey),
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
          if (_currentState.drawerIsOpen) {
            state.activateFocusManagement();
          } else {
            state.deactivateFocusManagement();
          }
        });
      },
    );
  }
  
  // 构建文字广告层
  Widget _buildTextAdOverlay() {
    return widget.adManager.buildTextAdWidget(context);
  }
  
  // 构建图片广告层
  Widget _buildImageAdOverlay(bool showImageAd) {
    return showImageAd
        ? widget.adManager.buildImageAdWidget() 
        : const SizedBox.shrink();
  }

  // 构建页面主视图
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _handleBackPress(context),
      child: Scaffold(
        body: Builder(builder: (context) {
          return KeyboardListener(
            focusNode: _keyboardFocusNode,
            onKeyEvent: (KeyEvent e) => _focusEventHandle(context, e),
            child: Container(
              alignment: Alignment.center,
              color: Colors.black,
              child: Stack(
                children: [
                  // 视频播放器层
                  Container(
                    color: Colors.black,
                    child: _buildVideoPlayerCore(),
                  ),
                  
                  // 进度条层
                  _buildToastAndProgress(),
                  
                  // 控制图标层
                  ValueListenableBuilder<TvUIState>(
                    valueListenable: _uiStateNotifier,
                    builder: (context, uiState, child) {
                      return _buildControlIcons(uiState);
                    },
                  ),
                  
                  // 抽屉层
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<TvUIState>(
                      valueListenable: _uiStateNotifier,
                      builder: (context, uiState, child) {
                        return Offstage(
                          offstage: !uiState.drawerIsOpen,
                          child: _buildChannelDrawerContent(uiState.drawerRefreshKey),
                        );
                      },
                    ),
                  ),
                  
                  // 文字广告层
                  ValueListenableBuilder<TvUIState>(
                    valueListenable: _uiStateNotifier,
                    builder: (context, uiState, child) {
                      return _buildTextAdOverlay();
                    },
                  ),
                  
                  // 图片广告层
                  ValueListenableBuilder<TvUIState>(
                    valueListenable: _uiStateNotifier,
                    builder: (context, uiState, child) {
                      return _buildImageAdOverlay(uiState.showImageAd);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // 控制抽屉显示
  void _toggleDrawer(bool isOpen) {
    if (_currentState.drawerIsOpen == isOpen) return;
    _updateUIState(drawerIsOpen: isOpen);
    if (_drawerNavigationState != null) {
      if (isOpen) {
        _drawerNavigationState!.activateFocusManagement();
      } else {
        _drawerNavigationState!.deactivateFocusManagement();
      }
    }
  }
}
