import 'dart:async';
import 'dart:math' as math;  // 添加缺失的导入
import 'package:iapp_player/src/configuration/iapp_player_controls_configuration.dart';
import 'package:iapp_player/src/controls/iapp_player_clickable_widget.dart';
import 'package:iapp_player/src/controls/iapp_player_material_progress_bar.dart';
import 'package:iapp_player/src/controls/iapp_player_multiple_gesture_detector.dart';
import 'package:iapp_player/src/controls/iapp_player_progress_colors.dart';
import 'package:iapp_player/src/controls/iapp_player_controls_state.dart';
import 'package:iapp_player/src/core/iapp_player_controller.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:flutter/material.dart';

/// 播放器控件 - 按照 TableVideoWidget 模式重构
class IAppPlayerMaterialControls extends StatefulWidget {
  final Function(bool visibility) onControlsVisibilityChanged;
  final IAppPlayerControlsConfiguration controlsConfiguration;
  final IAppPlayerUIState uiState;
  final Function({bool? controlsVisible, bool? isLoading, bool? hasError}) onUIStateChanged;

  const IAppPlayerMaterialControls({
    Key? key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
    required this.uiState,
    required this.onUIStateChanged,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _IAppPlayerMaterialControlsState();
  }
}

class _IAppPlayerMaterialControlsState extends State<IAppPlayerMaterialControls> {
  // 定义常量 - 参考 TableVideoWidget
  static const Color _iconColor = Colors.white;
  static const Color _backgroundColor = Colors.black45;
  static const double _iconSize = 42.0;
  static const double _controlIconSize = 24.0;
  static const double _buttonSize = 32.0;
  static const double _controlBarHeight = 48.0;
  static const EdgeInsets _controlPadding = EdgeInsets.all(10.0);
  
  // 预定义装饰
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

  // 状态管理
  VideoPlayerValue? _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  bool _displayTapped = false;
  VideoPlayerController? _controller;
  IAppPlayerController? _iappPlayerController;
  StreamSubscription? _controlsVisibilityStreamSubscription;

  // 本地控件可见性状态
  bool _controlsNotVisible = false;

  IAppPlayerControlsConfiguration get _controlsConfiguration =>
      widget.controlsConfiguration;

  @override
  void initState() {
    super.initState();
    _controlsNotVisible = !widget.uiState.controlsVisible;
  }

  @override
  void didChangeDependencies() {
    final _oldController = _iappPlayerController;
    _iappPlayerController = IAppPlayerController.of(context);
    _controller = _iappPlayerController!.videoPlayerController;
    _latestValue = _controller!.value;

    if (_oldController != _iappPlayerController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant IAppPlayerMaterialControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uiState.controlsVisible != oldWidget.uiState.controlsVisible) {
      _controlsNotVisible = !widget.uiState.controlsVisible;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildMainWidget();
  }

  Widget _buildMainWidget() {
    // 检查并更新加载状态
    final currentLoading = _isLoading(_latestValue);
    final wasLoading = widget.uiState.isLoading;
    if (currentLoading != wasLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onUIStateChanged(isLoading: currentLoading);
      });
    }
    
    // 检查错误状态
    if (_latestValue?.hasError == true) {
      if (!widget.uiState.hasError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onUIStateChanged(hasError: true);
        });
      }
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    } else if (widget.uiState.hasError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onUIStateChanged(hasError: false);
      });
    }
    
    // 使用 Stack 构建控件层 - 参考 TableVideoWidget
    return GestureDetector(
      onTap: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onTap?.call();
        }
        _controlsNotVisible
            ? _cancelAndRestartTimer()
            : _changePlayerControlsNotVisible(true);
      },
      onDoubleTap: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onDoubleTap?.call();
        }
        _cancelAndRestartTimer();
      },
      onLongPress: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: AbsorbPointer(
        absorbing: _controlsNotVisible && 
            _controlsConfiguration.absorbTouchWhenControlsHidden,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 透明背景层 - 用于捕获点击
            Container(color: Colors.transparent),
            
            // 中心控制按钮层 - 使用固定大小的容器
            if (!currentLoading)
              _buildCenterControls(),
            
            // 加载指示器层 - 使用固定大小
            if (currentLoading)
              _buildLoadingIndicator(),
            
            // 顶部控制栏 - 使用 Positioned 定位
            _buildTopBar(),
            
            // 底部控制栏 - 使用 Positioned 定位
            _buildBottomBar(),
            
            // 下一视频提示 - 使用 Positioned 定位
            _buildNextVideoWidget(),
          ],
        ),
      ),
    );
  }

  // 构建中心控制按钮 - 参考 TableVideoWidget 的 _buildControlIcon
  Widget _buildCenterControls() {
    if (_iappPlayerController?.isLiveStream() == true) {
      return const SizedBox.shrink();
    }
    
    return AnimatedOpacity(
      opacity: _controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      child: Center(
        child: Container(
          decoration: _controlIconDecoration,
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_controlsConfiguration.enableSkips) ...[
                _buildIconButton(
                  icon: _controlsConfiguration.skipBackIcon,
                  size: _controlIconSize,
                  onTap: _skipBack,
                ),
                const SizedBox(width: 24),
              ],
              _buildPlayPauseButton(),
              if (_controlsConfiguration.enableSkips) ...[
                const SizedBox(width: 24),
                _buildIconButton(
                  icon: _controlsConfiguration.skipForwardIcon,
                  size: _controlIconSize,
                  onTap: _skipForward,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 构建加载指示器 - 使用固定大小
  Widget _buildLoadingIndicator() {
    return Center(
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: _controlsConfiguration.controlBarColor,
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.all(10),
        child: _controlsConfiguration.loadingWidget ??
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                _controlsConfiguration.loadingColor,
              ),
              strokeWidth: 3,
            ),
      ),
    );
  }

  // 构建顶部控制栏 - 使用 Positioned
  Widget _buildTopBar() {
    if (!_iappPlayerController!.controlsEnabled || 
        !_controlsConfiguration.enableOverflowMenu) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        onEnd: _onPlayerHide,
        child: Container(
          height: _controlBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_controlsConfiguration.enablePip)
                _buildPipButton(),
              _buildMoreButton(),
            ],
          ),
        ),
      ),
    );
  }

  // 构建底部控制栏 - 使用 Positioned
  Widget _buildBottomBar() {
    if (!_iappPlayerController!.controlsEnabled) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        onEnd: _onPlayerHide,
        child: Container(
          height: _controlBarHeight + 20,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 控制按钮行
              Container(
                height: _controlBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (_controlsConfiguration.enablePlayPause)
                      _buildBottomPlayPause(),
                    if (_iappPlayerController!.isLiveStream())
                      _buildLiveWidget()
                    else if (_controlsConfiguration.enableProgressText)
                      Expanded(child: _buildPosition()),
                    const Spacer(),
                    if (_controlsConfiguration.enableMute)
                      _buildMuteButton(),
                    if (_controlsConfiguration.enableFullscreen)
                      _buildExpandButton(),
                  ],
                ),
              ),
              // 进度条
              if (!_iappPlayerController!.isLiveStream() && 
                  _controlsConfiguration.enableProgressBar)
                _buildProgressBar(),
            ],
          ),
        ),
      ),
    );
  }

  // 构建下一视频提示 - 使用 Positioned
  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time == null || time <= 0) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          bottom: _controlBarHeight + 40,
          right: 24,
          child: IAppPlayerMaterialClickableWidget(
            onTap: () {
              _iappPlayerController!.playNextVideo();
            },
            child: Container(
              decoration: BoxDecoration(
                color: _controlsConfiguration.controlBarColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(12),
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

  // 构建图标按钮 - 统一样式
  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 24,
  }) {
    return IAppPlayerMaterialClickableWidget(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  // 构建播放/暂停按钮
  Widget _buildPlayPauseButton() {
    final bool isFinished = _isVideoFinished(_latestValue);
    final isPlaying = _controller?.value.isPlaying ?? false;
    
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        if (isFinished) {
          if (_latestValue != null && _latestValue!.isPlaying) {
            if (_displayTapped) {
              _changePlayerControlsNotVisible(true);
            } else {
              _cancelAndRestartTimer();
            }
          } else {
            _onPlayPause();
            _changePlayerControlsNotVisible(true);
          }
        } else {
          _onPlayPause();
        }
      },
      child: Icon(
        isFinished
            ? Icons.replay
            : isPlaying
                ? _controlsConfiguration.pauseIcon
                : _controlsConfiguration.playIcon,
        size: _iconSize,
        color: _controlsConfiguration.iconsColor,
      ),
    );
  }

  // 构建底部播放/暂停按钮
  Widget _buildBottomPlayPause() {
    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        height: double.infinity,
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

  // 构建画中画按钮
  Widget _buildPipButton() {
    return FutureBuilder<bool>(
      future: _iappPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final bool isPipSupported = snapshot.data ?? false;
        if (!isPipSupported || 
            _iappPlayerController!.iappPlayerGlobalKey == null) {
          return const SizedBox.shrink();
        }
        
        return _buildIconButton(
          icon: _iappPlayerControlsConfiguration.pipMenuIcon,
          onTap: () {
            _iappPlayerController!.enablePictureInPicture(
              _iappPlayerController!.iappPlayerGlobalKey!,
            );
          },
        );
      },
    );
  }

  // 构建更多按钮
  Widget _buildMoreButton() {
    return _buildIconButton(
      icon: _controlsConfiguration.overflowMenuIcon,
      onTap: _onShowMoreClicked,
    );
  }

  // 构建静音按钮
  Widget _buildMuteButton() {
    return _buildIconButton(
      icon: (_latestValue != null && _latestValue!.volume > 0)
          ? _controlsConfiguration.muteIcon
          : _controlsConfiguration.unMuteIcon,
      onTap: () {
        _cancelAndRestartTimer();
        if (_latestValue!.volume == 0) {
          _iappPlayerController!.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = _controller!.value.volume;
          _iappPlayerController!.setVolume(0.0);
        }
      },
    );
  }

  // 构建全屏按钮
  Widget _buildExpandButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _buildIconButton(
        icon: _iappPlayerController!.isFullScreen
            ? _controlsConfiguration.fullscreenDisableIcon
            : _controlsConfiguration.fullscreenEnableIcon,
        onTap: _onExpandCollapse,
      ),
    );
  }

  // 构建直播标识
  Widget _buildLiveWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        _iappPlayerController!.translations.controlsLive,
        style: TextStyle(
          color: _controlsConfiguration.liveTextColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // 构建时间显示
  Widget _buildPosition() {
    final position =
        _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null
        ? _latestValue!.duration!
        : Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        '${IAppPlayerUtils.formatDuration(position)} / ${IAppPlayerUtils.formatDuration(duration)}',
        style: TextStyle(
          fontSize: 10.0,
          color: _controlsConfiguration.textColor,
        ),
      ),
    );
  }

  // 构建进度条
  Widget _buildProgressBar() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IAppPlayerMaterialVideoProgressBar(
        _controller,
        _iappPlayerController,
        onDragStart: () {
          _hideTimer?.cancel();
        },
        onDragEnd: () {
          _startHideTimer();
        },
        onTapDown: () {
          _cancelAndRestartTimer();
        },
        colors: IAppPlayerProgressColors(
          playedColor: _controlsConfiguration.progressBarPlayedColor,
          handleColor: _controlsConfiguration.progressBarHandleColor,
          bufferedColor: _controlsConfiguration.progressBarBufferedColor,
          backgroundColor: _controlsConfiguration.progressBarBackgroundColor,
        ),
      ),
    );
  }

  // 构建错误提示
  Widget _buildErrorWidget() {
    final errorBuilder =
        _iappPlayerController!.iappPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(
        context,
        _iappPlayerController!
            .videoPlayerController!.value.errorDescription,
      );
    } else {
      final textStyle = TextStyle(color: _controlsConfiguration.textColor);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning,
              color: _controlsConfiguration.iconsColor,
              size: 42,
            ),
            Text(
              _iappPlayerController!.translations.generalDefaultError,
              style: textStyle,
            ),
            if (_controlsConfiguration.enableRetry)
              TextButton(
                onPressed: () {
                  _iappPlayerController!.retryDataSource();
                },
                child: Text(
                  _iappPlayerController!.translations.generalRetry,
                  style: textStyle.copyWith(fontWeight: FontWeight.bold),
                ),
              )
          ],
        ),
      );
    }
  }

  // 辅助方法
  bool _isLoading(VideoPlayerValue? latestValue) {
    if (latestValue == null) return false;
    if (!latestValue.initialized) return true;  // 修复：isInitialized → initialized
    if (latestValue.isBuffering == true) return true;
    
    final Duration position = latestValue.position;
    final Duration bufferedEndPosition = latestValue.buffered.isNotEmpty
        ? latestValue.buffered.last.end
        : const Duration();
    
    return position > bufferedEndPosition;
  }

  bool _isVideoFinished(VideoPlayerValue? videoPlayerValue) {
    if (videoPlayerValue == null) return false;
    final Duration? duration = videoPlayerValue.duration;
    if (duration == null) return false;
    
    final Duration position = videoPlayerValue.position;
    return position >= duration;
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    _changePlayerControlsNotVisible(false);
    _displayTapped = true;
  }

  void _initialize() async {
    _controller!.addListener(_updateState);

    _updateState();

    if ((_controller!.value.isPlaying) ||
        _iappPlayerController!.iappPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }

    if (_controlsConfiguration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        _changePlayerControlsNotVisible(false);
      });
    }

    _controlsVisibilityStreamSubscription =
        _iappPlayerController!.controlsVisibilityStream.listen((state) {
      _changePlayerControlsNotVisible(!state);
      if (!_controlsNotVisible) {
        _cancelAndRestartTimer();
      }
    });
  }

  void _onExpandCollapse() {
    _changePlayerControlsNotVisible(true);
    _iappPlayerController!.toggleFullScreen();
    _showAfterExpandCollapseTimer =
        Timer(_controlsConfiguration.controlsHideTime, () {
      setState(() {
        _cancelAndRestartTimer();
      });
    });
  }

  void _onPlayPause() {
    bool isFinished = false;

    if (_latestValue?.position != null && _latestValue?.duration != null) {
      isFinished = _latestValue!.position >= _latestValue!.duration!;
    }

    if (_controller!.value.isPlaying) {
      _changePlayerControlsNotVisible(false);
      _hideTimer?.cancel();
      _iappPlayerController!.pause();
    } else {
      _cancelAndRestartTimer();

      if (!_controller!.value.initialized) {
      } else {
        if (isFinished) {
          _iappPlayerController!.seekTo(const Duration());
        }
        _iappPlayerController!.play();
        _iappPlayerController!.cancelNextVideoTimer();
      }
    }
  }

  void _startHideTimer() {
    if (_iappPlayerController!.controlsAlwaysVisible) {
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      _changePlayerControlsNotVisible(true);
    });
  }

  void _updateState() {
    if (mounted) {
      if (!_controlsNotVisible ||
          _isVideoFinished(_controller!.value) ||
          widget.uiState.isLoading ||
          _isLoading(_controller!.value)) {
        setState(() {
          _latestValue = _controller!.value;
          if (_isVideoFinished(_latestValue) &&
              _iappPlayerController?.isLiveStream() == false) {
            _changePlayerControlsNotVisible(false);
          }
        });
      }
    }
  }

  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!_controlsNotVisible);
    widget.onControlsVisibilityChanged(!_controlsNotVisible);
  }

  void _skipBack() {
    _cancelAndRestartTimer();
    final beginning = const Duration().inMilliseconds;
    final skip = (_latestValue!.position -
            Duration(milliseconds: _controlsConfiguration.backwardSkipTimeInMilliseconds))  // 修复：使用正确的属性名
        .inMilliseconds;
    _iappPlayerController!.seekTo(Duration(milliseconds: math.max(skip, beginning)));
  }

  void _skipForward() {
    _cancelAndRestartTimer();
    final end = _latestValue!.duration!.inMilliseconds;
    final skip = (_latestValue!.position +
            Duration(milliseconds: _controlsConfiguration.forwardSkipTimeInMilliseconds))  // 修复：使用正确的属性名
        .inMilliseconds;
    _iappPlayerController!.seekTo(Duration(milliseconds: math.min(skip, end)));
  }

  void _onShowMoreClicked() {
    _showModalBottomSheet([
      if (_controlsConfiguration.enablePlaybackSpeed)  // 修复：使用正确的属性名
        _buildBottomSheetRow(
          _controlsConfiguration.playbackSpeedIcon,  // 修复：使用正确的属性名
          _iappPlayerController!.translations.overflowMenuPlaybackSpeed,  // 修复：使用正确的属性名
          () {
            Navigator.of(context).pop();
            _showSpeedChooser();
          },
        ),
      if (_controlsConfiguration.enableSubtitles &&
          _iappPlayerController!.iappPlayerSubtitlesSourceList.isNotEmpty)
        _buildBottomSheetRow(
          _controlsConfiguration.subtitlesIcon,
          _iappPlayerController!.translations.overflowMenuSubtitles,  // 修复：使用正确的属性名
          () {
            Navigator.of(context).pop();
            _showSubtitlesSelectionWidget();
          },
        ),
      if (_controlsConfiguration.enableQualities &&
          _iappPlayerController!.iappPlayerDataSource != null &&
          _iappPlayerController!.iappPlayerDataSource!.videoFormat != null)
        _buildBottomSheetRow(
          _controlsConfiguration.qualitiesIcon,
          _iappPlayerController!.translations.overflowMenuQuality,  // 修复：使用正确的属性名
          () {
            Navigator.of(context).pop();
            _showQualitiesSelectionWidget();
          },
        ),
      if (_controlsConfiguration.enableAudioTracks &&
          _iappPlayerController!.iappPlayerAsmsAudioTracks?.isNotEmpty == true)  // 修复：使用正确的属性名
        _buildBottomSheetRow(
          _controlsConfiguration.audioTracksIcon,
          _iappPlayerController!.translations.overflowMenuAudioTracks,  // 修复：使用正确的属性名
          () {
            Navigator.of(context).pop();
            _showAudioTracksSelectionWidget();
          },
        ),
    ]);
  }

  Widget _buildBottomSheetRow(
    IconData icon,
    String name,
    void Function() onTap,
  ) {
    return IAppPlayerMaterialClickableWidget(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
        child: Row(
          children: [
            Icon(icon, color: _controlsConfiguration.overflowMenuIconsColor),
            const SizedBox(width: 16),
            Text(
              name,
              style: TextStyle(  // 修复：不使用不存在的 overflowMenuTextStyle
                color: _controlsConfiguration.overflowModalTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showModalBottomSheet(List<Widget> children) {
    showModalBottomSheet<void>(
      backgroundColor: _controlsConfiguration.overflowModalColor,
      context: context,
      builder: (context) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSpeedChooser() {
    // 使用固定的速度列表
    const speedLevels = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    _showModalBottomSheet(
      speedLevels
          .map(
            (speed) => _buildBottomSheetRow(
              _controller!.value.speed == speed  // 修复：使用 controller 而不是 iappPlayerController
                  ? Icons.check
                  : Icons.speed,
              "$speed x",
              () {
                Navigator.of(context).pop();
                _iappPlayerController!.setSpeed(speed);
              },
            ),
          )
          .toList(),
    );
  }

  void _showSubtitlesSelectionWidget() {
    // 实现字幕选择器
  }

  void _showQualitiesSelectionWidget() {
    // 实现质量选择器
  }

  void _showAudioTracksSelectionWidget() {
    // 实现音轨选择器
  }

  void _changePlayerControlsNotVisible(bool notVisible) {
    setState(() {
      _controlsNotVisible = notVisible;
    });
    widget.onUIStateChanged(controlsVisible: !notVisible);
  }

  void _dispose() {
    _controller?.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  // 获取配置
  IAppPlayerControlsConfiguration get _iappPlayerControlsConfiguration =>
      _controlsConfiguration;
}
