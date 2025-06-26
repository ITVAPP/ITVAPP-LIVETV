import 'dart:async';
import 'package:iapp_player/src/configuration/iapp_player_controls_configuration.dart';
import 'package:iapp_player/src/controls/iapp_player_clickable_widget.dart';
import 'package:iapp_player/src/controls/iapp_player_controls_state.dart';
import 'package:iapp_player/src/controls/iapp_player_material_progress_bar.dart';
import 'package:iapp_player/src/controls/iapp_player_multiple_gesture_detector.dart';
import 'package:iapp_player/src/controls/iapp_player_progress_colors.dart';
import 'package:iapp_player/src/core/iapp_player_controller.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:flutter/material.dart';

/// Material 风格播放器控件 - 重构版本
class IAppPlayerMaterialControls extends StatefulWidget {
  /// 控件可见性变化回调
  final Function(bool visibility) onControlsVisibilityChanged;

  /// 控件配置
  final IAppPlayerControlsConfiguration controlsConfiguration;

  const IAppPlayerMaterialControls({
    Key? key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _IAppPlayerMaterialControlsState();
  }
}

class _IAppPlayerMaterialControlsState
    extends IAppPlayerControlsState<IAppPlayerMaterialControls> {
  // 核心状态
  VideoPlayerValue? _latestValue;
  double? _latestVolume;
  bool _wasLoading = false;
  bool _displayTapped = false;
  
  // 控制器
  VideoPlayerController? _controller;
  IAppPlayerController? _iappPlayerController;
  
  // 定时器
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  
  // 订阅
  StreamSubscription? _controlsVisibilityStreamSubscription;

  // Getters
  IAppPlayerControlsConfiguration get _controlsConfiguration =>
      widget.controlsConfiguration;

  @override
  VideoPlayerValue? get latestValue => _latestValue;

  @override
  IAppPlayerController? get iappPlayerController => _iappPlayerController;

  @override
  IAppPlayerControlsConfiguration get iappPlayerControlsConfiguration =>
      _controlsConfiguration;

  @override
  void didChangeDependencies() {
    final oldController = _iappPlayerController;
    _iappPlayerController = IAppPlayerController.of(context);
    _controller = _iappPlayerController!.videoPlayerController;
    _latestValue = _controller!.value;

    if (oldController != _iappPlayerController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    _controller?.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return buildLTRDirectionality(_buildMainWidget());
  }

  /// 构建主控件布局
  Widget _buildMainWidget() {
    // 检查错误状态
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }

    // 更新加载状态
    final isCurrentlyLoading = isLoading(_latestValue);
    if (_wasLoading != isCurrentlyLoading) {
      _wasLoading = isCurrentlyLoading;
    }

    // 主布局 - 使用 Stack 直接组织所有元素
    return Stack(
      children: [
        // 底层：手势检测层（覆盖整个区域）
        Positioned.fill(
          child: GestureDetector(
            // 根据控件可见性调整行为
            behavior: controlsNotVisible 
                ? HitTestBehavior.opaque  // 控件隐藏时，确保能接收点击
                : HitTestBehavior.translucent,  // 控件显示时，允许事件穿透
            onTap: _handleTap,
            onDoubleTap: _handleDoubleTap,
            onLongPress: _handleLongPress,
            child: Container(
              color: Colors.transparent, // 透明背景，仅用于接收手势
            ),
          ),
        ),
        
        // 中层：加载指示器（居中显示）
        if (_wasLoading)
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _controlsConfiguration.controlBarColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: _buildLoadingWidget(),
              ),
            ),
          ),
        
        // 中间控制按钮（播放/暂停/快进快退）
        if (!_wasLoading && iappPlayerController!.controlsEnabled)
          Center(
            child: AnimatedOpacity(
              opacity: controlsNotVisible ? 0.0 : 1.0,
              duration: _controlsConfiguration.controlsHideTime,
              child: _buildCenterControls(),
            ),
          ),
        
        // 顶部控制栏
        if (iappPlayerController!.controlsEnabled)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),
        
        // 底部控制栏  
        if (iappPlayerController!.controlsEnabled)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        
        // 下一视频提示
        _buildNextVideoWidget(),
        
        // 触摸吸收层（在控件隐藏时阻止子控件接收触摸事件）
        if (controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(),
            ),
          ),
      ],
    );
  }

  /// 处理单击事件
  void _handleTap() {
    if (IAppPlayerMultipleGestureDetector.of(context) != null) {
      IAppPlayerMultipleGestureDetector.of(context)!.onTap?.call();
    }
    
    if (controlsNotVisible) {
      cancelAndRestartTimer();
    } else {
      changePlayerControlsNotVisible(true);
    }
  }

  /// 处理双击事件
  void _handleDoubleTap() {
    if (IAppPlayerMultipleGestureDetector.of(context) != null) {
      IAppPlayerMultipleGestureDetector.of(context)!.onDoubleTap?.call();
    }
    cancelAndRestartTimer();
  }

  /// 处理长按事件
  void _handleLongPress() {
    if (IAppPlayerMultipleGestureDetector.of(context) != null) {
      IAppPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
    }
  }

  /// 构建中间控制按钮组
  Widget _buildCenterControls() {
    if (_iappPlayerController?.isLiveStream() == true) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: _controlsConfiguration.controlBarColor,
        borderRadius: BorderRadius.circular(48),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_controlsConfiguration.enableSkips) ...[
            _buildControlButton(
              icon: _controlsConfiguration.skipBackIcon,
              onTap: skipBack,
              size: 32,
            ),
            const SizedBox(width: 20),
          ],
          _buildPlayPauseButton(),
          if (_controlsConfiguration.enableSkips) ...[
            const SizedBox(width: 20),
            _buildControlButton(
              icon: _controlsConfiguration.skipForwardIcon,
              onTap: skipForward,
              size: 32,
            ),
          ],
        ],
      ),
    );
  }

  /// 构建播放/暂停按钮
  Widget _buildPlayPauseButton() {
    final isFinished = isVideoFinished(_latestValue);
    final isPlaying = _controller?.value.isPlaying ?? false;
    
    IconData icon;
    if (isFinished) {
      icon = Icons.replay;
    } else {
      icon = isPlaying 
          ? _controlsConfiguration.pauseIcon 
          : _controlsConfiguration.playIcon;
    }

    return _buildControlButton(
      icon: icon,
      onTap: () {
        if (isFinished) {
          if (_latestValue?.isPlaying ?? false) {
            if (_displayTapped) {
              changePlayerControlsNotVisible(true);
            } else {
              cancelAndRestartTimer();
            }
          } else {
            _onPlayPause();
            changePlayerControlsNotVisible(true);
          }
        } else {
          _onPlayPause();
        }
      },
      size: 48,
    );
  }

  /// 构建控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 24,
  }) {
    return IAppPlayerMaterialClickableWidget(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建顶部控制栏
  Widget _buildTopBar() {
    if (!_controlsConfiguration.enableOverflowMenu) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        height: _controlsConfiguration.controlBarHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_controlsConfiguration.enablePip)
              _buildPipButton(),
            _buildMoreButton(),
          ],
        ),
      ),
    );
  }

  /// 构建画中画按钮
  Widget _buildPipButton() {
    return FutureBuilder<bool>(
      future: iappPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final isPipSupported = snapshot.data ?? false;
        if (!isPipSupported || _iappPlayerController!.iappPlayerGlobalKey == null) {
          return const SizedBox.shrink();
        }

        return IAppPlayerMaterialClickableWidget(
          onTap: () {
            iappPlayerController!.enablePictureInPicture(
              iappPlayerController!.iappPlayerGlobalKey!,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              _controlsConfiguration.pipMenuIcon,
              color: _controlsConfiguration.iconsColor,
            ),
          ),
        );
      },
    );
  }

  /// 构建更多按钮
  Widget _buildMoreButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: onShowMoreClicked,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomBar() {
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            if (!_iappPlayerController!.isLiveStream() && 
                _controlsConfiguration.enableProgressBar)
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildProgressBar(),
              ),
            
            // 控制按钮行
            Container(
              height: _controlsConfiguration.controlBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // 播放/暂停按钮
                  if (_controlsConfiguration.enablePlayPause)
                    _buildBottomPlayPause(),
                  
                  // 时间显示或直播标识
                  if (_iappPlayerController!.isLiveStream())
                    _buildLiveWidget()
                  else if (_controlsConfiguration.enableProgressText)
                    _buildPosition(),
                  
                  const Spacer(),
                  
                  // 静音按钮
                  if (_controlsConfiguration.enableMute)
                    _buildMuteButton(),
                  
                  // 全屏按钮
                  if (_controlsConfiguration.enableFullscreen)
                    _buildExpandButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部播放/暂停按钮
  Widget _buildBottomPlayPause() {
    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          _controller!.value.isPlaying
              ? _controlsConfiguration.pauseIcon
              : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建时间显示
  Widget _buildPosition() {
    final position = _latestValue?.position ?? Duration.zero;
    final duration = _latestValue?.duration ?? Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        '${IAppPlayerUtils.formatDuration(position)} / ${IAppPlayerUtils.formatDuration(duration)}',
        style: TextStyle(
          fontSize: 12,
          color: _controlsConfiguration.textColor,
        ),
      ),
    );
  }

  /// 构建直播标识
  Widget _buildLiveWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        _iappPlayerController!.translations.controlsLive,
        style: TextStyle(
          color: _controlsConfiguration.liveTextColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// 构建静音按钮
  Widget _buildMuteButton() {
    final isMuted = (_latestValue?.volume ?? 0) == 0;
    
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        cancelAndRestartTimer();
        if (isMuted) {
          _iappPlayerController!.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = _controller!.value.volume;
          _iappPlayerController!.setVolume(0.0);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          isMuted 
              ? _controlsConfiguration.unMuteIcon
              : _controlsConfiguration.muteIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建全屏按钮
  Widget _buildExpandButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: _onExpandCollapse,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          _iappPlayerController!.isFullScreen
              ? _controlsConfiguration.fullscreenDisableIcon
              : _controlsConfiguration.fullscreenEnableIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建进度条
  Widget _buildProgressBar() {
    return IAppPlayerMaterialVideoProgressBar(
      _controller,
      _iappPlayerController,
      onDragStart: () {
        _hideTimer?.cancel();
      },
      onDragEnd: () {
        _startHideTimer();
      },
      onTapDown: () {
        cancelAndRestartTimer();
      },
      colors: IAppPlayerProgressColors(
        playedColor: _controlsConfiguration.progressBarPlayedColor,
        handleColor: _controlsConfiguration.progressBarHandleColor,
        bufferedColor: _controlsConfiguration.progressBarBufferedColor,
        backgroundColor: _controlsConfiguration.progressBarBackgroundColor,
      ),
    );
  }

  /// 构建下一视频提示
  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time == null || time <= 0) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: _controlsConfiguration.controlBarHeight + 60,
          right: 24,
          child: IAppPlayerMaterialClickableWidget(
            onTap: () {
              _iappPlayerController!.playNextVideo();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _controlsConfiguration.controlBarColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "${_iappPlayerController!.translations.controlsNextVideoIn} $time...",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建错误提示
  Widget _buildErrorWidget() {
    final errorBuilder = _iappPlayerController!.iappPlayerConfiguration.errorBuilder;
    
    if (errorBuilder != null) {
      return errorBuilder(
        context,
        _iappPlayerController!.videoPlayerController!.value.errorDescription,
      );
    }

    final textStyle = TextStyle(color: _controlsConfiguration.textColor);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_rounded,
            color: _controlsConfiguration.iconsColor,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _iappPlayerController!.translations.generalDefaultError,
            style: textStyle,
          ),
          if (_controlsConfiguration.enableRetry) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _iappPlayerController!.retryDataSource();
              },
              child: Text(
                _iappPlayerController!.translations.generalRetry,
                style: textStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建加载指示器
  Widget _buildLoadingWidget() {
    return _controlsConfiguration.loadingWidget ??
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            _controlsConfiguration.loadingColor,
          ),
        );
  }

  /// 初始化控制器
  Future<void> _initialize() async {
    _controller!.addListener(_updateState);
    _updateState();

    if (_controller!.value.isPlaying || 
        _iappPlayerController!.iappPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }

    if (_controlsConfiguration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        changePlayerControlsNotVisible(false);
      });
    }

    _controlsVisibilityStreamSubscription = 
        _iappPlayerController!.controlsVisibilityStream.listen((visible) {
      changePlayerControlsNotVisible(!visible);
      if (!controlsNotVisible) {
        cancelAndRestartTimer();
      }
    });
  }

  /// 更新播放状态
  void _updateState() {
    if (!mounted) return;

    if (!controlsNotVisible ||
        isVideoFinished(_controller!.value) ||
        _wasLoading ||
        isLoading(_controller!.value)) {
      setState(() {
        _latestValue = _controller!.value;
        if (isVideoFinished(_latestValue) &&
            _iappPlayerController?.isLiveStream() == false) {
          changePlayerControlsNotVisible(false);
        }
      });
    }
  }

  /// 播放/暂停切换
  void _onPlayPause() {
    final isFinished = isVideoFinished(_latestValue);

    if (_controller!.value.isPlaying) {
      changePlayerControlsNotVisible(false);
      _hideTimer?.cancel();
      _iappPlayerController!.pause();
    } else {
      cancelAndRestartTimer();

      if (!_controller!.value.initialized) {
        // 未初始化
      } else {
        if (isFinished) {
          _iappPlayerController!.seekTo(const Duration());
        }
        _iappPlayerController!.play();
        _iappPlayerController!.cancelNextVideoTimer();
      }
    }
  }

  /// 切换全屏
  void _onExpandCollapse() {
    changePlayerControlsNotVisible(true);
    _iappPlayerController!.toggleFullScreen();
    _showAfterExpandCollapseTimer = 
        Timer(_controlsConfiguration.controlsHideTime, () {
      setState(() {
        cancelAndRestartTimer();
      });
    });
  }

  /// 启动隐藏定时器
  void _startHideTimer() {
    if (_iappPlayerController!.controlsAlwaysVisible) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      changePlayerControlsNotVisible(true);
    });
  }

  /// 取消并重启定时器
  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();
    changePlayerControlsNotVisible(false);
    _displayTapped = true;
  }

  /// 控件隐藏回调
  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }
}
