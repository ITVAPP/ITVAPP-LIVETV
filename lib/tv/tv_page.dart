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
import '../channel_drawer_page.dart';
import '../gradient_progress_bar.dart';
import '../entity/playlist_model.dart';
import '../util/log_util.dart';
import '../util/custom_snackbar.dart';
import '../generated/l10n.dart';

// 播放器组件，用于视频播放的核心组件
class VideoPlayerWidget extends StatelessWidget {
  final BetterPlayerController? controller;
  final String? toastString;
  final bool drawerIsOpen;
  final bool isBuffering;
  final bool isError;
  final bool isAudio;

  const VideoPlayerWidget({
    Key? key,
    required this.controller,
    this.toastString,
    this.drawerIsOpen = false,
    this.isBuffering = false,
    this.isError = false,
    this.isAudio = false,
  }) : super(key: key);

  // 构建缓冲加载指示器
  Widget _buildBufferingIndicator(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientProgressBar(
              width: MediaQuery.of(context).size.width * 0.3,
              height: 5,
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).loading,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (controller != null && 
            (controller!.isVideoInitialized() ?? false) && // Fixed nullable bool
            !isAudio)
          // 如果控制器已初始化并且不是音频模式，则显示视频
          Center(
            child: AspectRatio(
              aspectRatio: controller!.videoPlayerController?.value.aspectRatio ?? 16/9,
              child: BetterPlayer(controller: controller!),
            ),
          )
        else
          // 如果控制器未初始化或是音频模式，则显示背景
          VideoHoldBg(
            toastString: drawerIsOpen ? '' : toastString,
            showBingBackground: isAudio,
          ),
        
        // 如果正在缓冲或出错且抽屉未打开，则显示缓冲指示器
        if (controller != null &&
            (controller!.isVideoInitialized() ?? false) && // Fixed nullable bool
            (isBuffering || isError) &&
            !drawerIsOpen)
          _buildBufferingIndicator(context),
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
  final GestureTapCallback? onChangeSubSource;
  final String? toastString;
  final bool isLandscape;
  final bool isBuffering;
  final bool isPlaying;
  final double aspectRatio;
  final Function(String)? toggleFavorite;
  final Function(String)? isChannelFavorite;
  final String? currentChannelId;
  final bool isAudio;

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
    this.isAudio = false,
  });

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> with TickerProviderStateMixin {
  static const Duration _pauseIconDisplayDuration = Duration(seconds: 3);
  
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

  // 更新图标状态的方法，控制播放、暂停、显示日期等图标的显隐
  void _updateIconState({
    bool? showPause,
    bool? showPlay,
    bool? showDatePosition,
  }) {
    _iconStateNotifier.value = _iconStateNotifier.value.copyWith(
      showPause: showPause,
      showPlay: showPlay,
      showDatePosition: showDatePosition,
    );
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
      _updateIconState(showPlay: true); // 显示播放图标
      
      return Navigator.push<bool>(
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
    } catch (e, stackTrace) {
      LogUtil.logError('打开添加源设置页面时发生错误', e, stackTrace);
      return null;
    }
  }
  
  // 处理返回按键，当抽屉打开时关闭抽屉；否则检测是否退出应用
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
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
      }
      
      bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
      
      if (!shouldExit && wasPlaying) {
        // 如果用户选择不退出且之前在播放，则恢复播放
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
    final controller = widget.controller;
    if (controller == null) return;	
    
    final isActuallyPlaying = controller.isPlaying() ?? false;  // 检查播放状态
    
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
      }
    } else {
      // 如果当前未播放，则启动播放并隐藏播放图标
      await controller.play();
      _updateIconState(showPlay: false);
    }

    // 切换时间和收藏图标的显示状态
    _updateIconState(
      showDatePosition: !_iconStateNotifier.value.showDatePosition
    );
  }
  
// 处理键盘事件，包括方向键和选择键的逻辑处理
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    if (e is! KeyUpEvent) return KeyEventResult.handled;

    // 当抽屉打开时，忽略方向键和选择键事件
    if (_drawerIsOpen && (e.logicalKey == LogicalKeyboardKey.arrowUp ||
                          e.logicalKey == LogicalKeyboardKey.arrowDown ||
                          e.logicalKey == LogicalKeyboardKey.arrowLeft ||
                          e.logicalKey == LogicalKeyboardKey.arrowRight ||
                          e.logicalKey == LogicalKeyboardKey.select ||
                          e.logicalKey == LogicalKeyboardKey.enter)) {
      return KeyEventResult.handled;
    }

    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
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
        break;
      case LogicalKeyboardKey.arrowRight:
        // 右箭头用于打开或关闭抽屉
        _toggleDrawer(!_drawerIsOpen);
        break;
      case LogicalKeyboardKey.arrowUp:
        // 上箭头用于切换频道源
        await widget.changeChannelSources?.call();
        break;
      case LogicalKeyboardKey.arrowDown:
        // 下箭头用于暂停播放并打开设置页面
        await widget.controller?.pause();
        _updateIconState(showPlay: true);
        _opensetting();
        break;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        // 选择键用于控制播放/暂停
        if (!_blockSelectKeyEvent) {
          await _handleSelectPress();
        }
        break;  
      case LogicalKeyboardKey.audioVolumeUp:
        // 音量控制可以通过 BetterPlayer 的方法实现，但这里保持原样
        break;
      case LogicalKeyboardKey.audioVolumeDown:
        break;
      case LogicalKeyboardKey.f5:
        break;
      default:
        break;
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
  
  // 资源释放，取消定时器和焦点管理
  @override
  void dispose() {
    _iconStateNotifier.dispose();
    
    try {
      _pauseIconTimer?.cancel();
    } catch (e) {
      LogUtil.logError('释放 _pauseIconTimer 失败', e);
    }
    
    _blockSelectKeyEvent = false;
    
    if (_drawerNavigationState != null) {
      _drawerNavigationState!.deactivateFocusManagement();
      _drawerNavigationState = null;
    }
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
        color: widget.isChannelFavorite!(widget.currentChannelId!) 
            ? Colors.red 
            : Colors.white,
        size: 38,
      ),
    );
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
                  VideoPlayerWidget(
                    controller: widget.controller,
                    toastString: widget.toastString,
                    drawerIsOpen: _drawerIsOpen,
                    isBuffering: widget.isBuffering,
                    isError: _isError,
                    isAudio: widget.isAudio,
                  ),
                  
                  // 使用 ValueListenableBuilder 监听图标状态
                  ValueListenableBuilder<IconState>(
                    valueListenable: _iconStateNotifier,
                    builder: (context, iconState, child) {
                      return Stack(
                        children: [
                          if (iconState.showPause) 
                            _buildPauseIcon(),
                              
                          // Fixed: 正确处理视频初始化和播放状态的检查
                          if ((widget.controller != null && 
                              (widget.controller!.isVideoInitialized() ?? false) && 
                              !(widget.controller!.isPlaying() ?? false) && 
                              !_drawerIsOpen) || 
                              iconState.showPlay)    
                            _buildPlayIcon(),

                          if (iconState.showDatePosition) 
                            const DatePositionWidget(),
                          
                          if (iconState.showDatePosition && !_drawerIsOpen) 
                            _buildFavoriteIcon(),
                        ],
                      );
                    },
                  ),

                  // 频道抽屉显示
                  Align(
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
                  ),
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
    if (_drawerIsOpen == isOpen) return;

    setState(() {
      _drawerIsOpen = isOpen;
    });

    if (_drawerNavigationState != null) {
      if (isOpen) {
        _drawerNavigationState!.activateFocusManagement();
      } else {
        _drawerNavigationState!.deactivateFocusManagement();
      }
    }
  }
}
