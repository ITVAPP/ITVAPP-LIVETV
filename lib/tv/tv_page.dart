import 'dart:async';
import 'package:itvapp_live_tv/tv/tv_setting_page.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/widget/date_position_widget.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/video_hold_bg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart'; // 修改: 导入 VLC 播放器

import '../channel_drawer_page.dart';
import '../gradient_progress_bar.dart';
import '../entity/playlist_model.dart';
import '../util/log_util.dart';
import '../util/custom_snackbar.dart';
import '../generated/l10n.dart';

// 播放器组件
class VideoPlayerWidget extends StatelessWidget {
  final VlcPlayerController? controller; // 修改: 改为 VLC 控制器
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

  // 播放器构建方法 - 修改为使用 VLC 播放器
  Widget _buildPlayer(VlcPlayerValue value) {
    // 获取安全的宽高比
    double safeAspectRatio;
    final size = value.size;
    if (size.width > 0 && size.height > 0) {
      safeAspectRatio = size.width / size.height;
    } else {
      safeAspectRatio = 16/9;
    }

    return Center(
      child: AspectRatio(
        aspectRatio: safeAspectRatio,
        child: SizedBox(
          width: double.infinity,
          child: VlcPlayer(
            controller: controller!,
            aspectRatio: safeAspectRatio,
            placeholder: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
          ValueListenableBuilder<VlcPlayerValue>(
            valueListenable: controller!,
            builder: (context, value, _) {
              if (controller != null && value.playingState != PlayingState.stopped && !isAudio) {
                return _buildPlayer(value);
              }
              return VideoHoldBg(
                toastString: drawerIsOpen ? '' : toastString,
                showBingBackground: isAudio,
              );
            },
          ),
        
        if (controller != null && 
            controller!.value.playingState != PlayingState.stopped && 
            (isBuffering || isError) && 
            !drawerIsOpen)
          _buildBufferingIndicator(context),
      ],
    );
  }
}

// IconState 类保持不变,因为它是一个纯数据类
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

// TvPage 组件
class TvPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final Function(PlayModel? newModel)? onTapChannel;
  final VlcPlayerController? controller; // 修改: VideoPlayerController 替换为 VlcPlayerController
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
  
  // 使用 ValueNotifier 替换原有状态
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
  VlcPlayerController? get _controller => widget.controller; // 修改: 类型替换为 VlcPlayerController
  bool get _hasValidController => _controller != null;

  // 图标状态更新方法
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

  // 定时器管理方法
  void _startPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = Timer(_pauseIconDisplayDuration, () {
      if (mounted) {
        _updateIconState(showPause: false);
      }
    });
  }

  void _clearPauseIconTimer() {
    _pauseIconTimer?.cancel();
    _pauseIconTimer = null;
  }

// 设置页面打开方法
Future<bool?> _opensetting() async {
    try {
      _updateIconState(showPlay: true);
      
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

// 返回按键处理方法 - 修改为使用 VLC 播放状态
Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      _toggleDrawer(false);
      return false;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return false;
    }

    if (_hasValidController) {
      final bool wasPlaying = _controller!.value.playingState == PlayingState.playing;
      if (wasPlaying) {
        await _controller!.pause();
        _updateIconState(showPlay: true);
      }
      
      final bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
      
      if (!shouldExit && wasPlaying && mounted) {
        await _controller!.play();
        _updateIconState(showPlay: false);
      }
      
      return shouldExit;
    }
    
    return true;
  }
  
// 控制图标构建方法
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

  Widget _buildPauseIcon() {
    return _buildControlIcon(icon: Icons.pause);
  }

  Widget _buildPlayIcon() {
    return _buildControlIcon(icon: Icons.play_arrow);
  }
  
  // 选择键处理逻辑，使用 VLC 播放状态
  Future<void> _handleSelectPress() async {
    if (!_hasValidController) return;	
    
    final controller = _controller!;
    final isActuallyPlaying = controller.value.playingState == PlayingState.playing;
    
    if (isActuallyPlaying) {
      if (!(_pauseIconTimer?.isActive ?? false)) {
        _updateIconState(
          showPause: true,
          showPlay: false,
        );
        _startPauseIconTimer();
      } else {
        await controller.pause();
        _clearPauseIconTimer();
        _updateIconState(
          showPause: false,
          showPlay: true,
        );
      }
    } else {
      await controller.play();
      _updateIconState(showPlay: false);
    }

    // 切换时间和收藏图标的显示状态
    _updateIconState(
      showDatePosition: !_iconStateNotifier.value.showDatePosition
    );
  }
  
  // 键盘事件处理，使用 VLC API
  Future<KeyEventResult> _focusEventHandle(BuildContext context, KeyEvent e) async {
    if (e is! KeyUpEvent) return KeyEventResult.handled;

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
        break;
      case LogicalKeyboardKey.arrowRight:
        _toggleDrawer(!_drawerIsOpen);
        break;
      case LogicalKeyboardKey.arrowUp:
        await widget.changeChannelSources?.call();
        break;
      case LogicalKeyboardKey.arrowDown:
        if (_hasValidController) {
          await _controller!.pause();
          _updateIconState(showPlay: true);
          await _opensetting();
        }
        break;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        if (!_blockSelectKeyEvent) {
          await _handleSelectPress();
        }
        break;  
      case LogicalKeyboardKey.audioVolumeUp:
        if (_hasValidController) {
          final currentVolume = await _controller!.getVolume() ?? 0;
          await _controller!.setVolume((currentVolume + 10).clamp(0, 100));
        }
        break;
      case LogicalKeyboardKey.audioVolumeDown:
        if (_hasValidController) {
          final currentVolume = await _controller!.getVolume() ?? 0;
          await _controller!.setVolume((currentVolume - 10).clamp(0, 100));
        }
        break;
      default:
        break;
    }
    return KeyEventResult.handled;
  }
  
  // EPGList 节目点击事件处理
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
  void dispose() {
    _iconStateNotifier.dispose();
    _pauseIconTimer?.cancel();
    _blockSelectKeyEvent = false;
    
    if (_drawerNavigationState != null) {
      _drawerNavigationState!.deactivateFocusManagement();
      _drawerNavigationState = null;
    }
    super.dispose();
  }
  
  // 收藏图标构建方法
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
                
                ValueListenableBuilder<IconState>(
                  valueListenable: _iconStateNotifier,
                  builder: (context, iconState, child) {
                    return Stack(
                      children: [
                        if (iconState.showPause) 
                          _buildPauseIcon(),
                          
                        if (_hasValidController && 
                            _controller!.value.playingState != PlayingState.playing && 
                            _controller!.value.playingState != PlayingState.stopped && 
                            !_drawerIsOpen || 
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

  // 抽屉显示/隐藏和焦点管理的方法
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
