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

/// 播放器控件 - YouTube风格改进版
class IAppPlayerMaterialControls extends StatefulWidget {
  /// 控件可见性变化回调
  final Function(bool visbility) onControlsVisibilityChanged;

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
  /// 最新播放值
  VideoPlayerValue? _latestValue;
  /// 最新音量
  double? _latestVolume;
  /// 隐藏定时器
  Timer? _hideTimer;
  /// 初始化定时器
  Timer? _initTimer;
  /// 全屏切换后显示定时器
  Timer? _showAfterExpandCollapseTimer;
  /// 是否点击显示
  bool _displayTapped = false;
  /// 是否正在加载
  bool _wasLoading = false;
  /// 视频播放控制器
  VideoPlayerController? _controller;
  /// 播放器控制器
  IAppPlayerController? _iappPlayerController;
  /// 控件可见性流订阅
  StreamSubscription? _controlsVisibilityStreamSubscription;

  /// 获取控件配置
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
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return buildLTRDirectionality(_buildMainWidget());
  }

  /// 构建主控件
  Widget _buildMainWidget() {
    final currentLoading = isLoading(_latestValue);
    if (currentLoading != _wasLoading) {
      _wasLoading = currentLoading;
    }
    
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }
    
    return GestureDetector(
      onTap: () {
        // 修复：当控件隐藏且absorbTouchWhenControlsHidden为true时，不响应点击
        if (controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden) {
          return;
        }
        
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onTap?.call();
        }
        controlsNotVisible
            ? cancelAndRestartTimer()
            : changePlayerControlsNotVisible(true);
      },
      onDoubleTap: () {
        // 修复：当控件隐藏且absorbTouchWhenControlsHidden为true时，不响应双击
        if (controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden) {
          return;
        }
        
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onDoubleTap?.call();
        }
        cancelAndRestartTimer();
      },
      onLongPress: () {
        // 修复：当控件隐藏且absorbTouchWhenControlsHidden为true时，不响应长按
        if (controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden) {
          return;
        }
        
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      child: AbsorbPointer(
        absorbing: controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_wasLoading)
              Center(child: _buildLoadingWidget())
            else
              _buildHitArea(),
            // 修改：移除遮罩层
            // _buildGradientOverlay(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
            _buildNextVideoWidget(),
          ],
        ),
      ),
    );
  }

  /// 构建渐变遮罩 - YouTube风格
  /// 修改：移除遮罩层，返回空组件
  Widget _buildGradientOverlay() {
    return const SizedBox();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  /// 清理资源
  void _dispose() {
    _controller?.removeListener(_updateState);
    _cancelAllTimers();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  /// 取消所有定时器
  void _cancelAllTimers() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _initTimer?.cancel();
    _initTimer = null;
    _showAfterExpandCollapseTimer?.cancel();
    _showAfterExpandCollapseTimer = null;
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

  /// 构建错误提示
  Widget _buildErrorWidget() {
    final errorBuilder =
        _iappPlayerController!.iappPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(
          context,
          _iappPlayerController!
              .videoPlayerController!.value.errorDescription);
    } else {
      final textStyle = TextStyle(color: _controlsConfiguration.textColor);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_rounded,
              color: _controlsConfiguration.iconsColor,
              size: 42,
            ),
            const SizedBox(height: 16),
            Text(
              _iappPlayerController!.translations.generalDefaultError,
              style: textStyle,
            ),
            if (_controlsConfiguration.enableRetry)
              const SizedBox(height: 16),
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

  /// 构建顶部控制栏
  Widget _buildTopBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    return Container(
      child: (_controlsConfiguration.enableOverflowMenu)
          ? AnimatedOpacity(
              opacity: controlsNotVisible ? 0.0 : 1.0,
              duration: _controlsConfiguration.controlsHideTime,
              onEnd: _onPlayerHide,
              child: Container(
                height: _controlsConfiguration.controlBarHeight + 8.0,
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_controlsConfiguration.enablePip)
                      _buildPipButtonWrapperWidget(
                          controlsNotVisible, _onPlayerHide)
                    else
                      const SizedBox(),
                    _buildMoreButton(),
                  ],
                ),
              ),
            )
          : const SizedBox(),
    );
  }

  /// 构建画中画按钮
  Widget _buildPipButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        iappPlayerController!.enablePictureInPicture(
            iappPlayerController!.iappPlayerGlobalKey!);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          iappPlayerControlsConfiguration.pipMenuIcon,
          color: iappPlayerControlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建画中画按钮包装器
  Widget _buildPipButtonWrapperWidget(
      bool hideStuff, void Function() onPlayerHide) {
    return FutureBuilder<bool>(
      future: iappPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final bool isPipSupported = snapshot.data ?? false;
        if (isPipSupported &&
            _iappPlayerController!.iappPlayerGlobalKey != null) {
          return _buildPipButton();
        } else {
          return const SizedBox();
        }
      },
    );
  }

  /// 构建更多按钮
  Widget _buildMoreButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        onShowMoreClicked();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建底部控制栏 - YouTube风格布局
  /// 修改：添加快进快退按钮到底部栏
  Widget _buildBottomBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;
    
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        padding: const EdgeInsets.only(bottom: 4),  // 修改：从8减少到4，使布局更紧凑
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 进度条区域 - 始终显示以保持布局稳定
            Container(
              height: 24,  // 修改：从40减少到24，使底部栏更紧凑
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _controlsConfiguration.enableProgressBar
                  ? _buildProgressBar()
                  : const SizedBox(),
            ),
            
            // 控制按钮行
            Container(
              height: _controlsConfiguration.controlBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // 快退按钮（非直播时显示）
                  if (!isLive && _controlsConfiguration.enableSkips)
                    _buildBottomSkipButton(),
                    
                  // 播放/暂停按钮
                  if (_controlsConfiguration.enablePlayPause)
                    _buildPlayPause(_controller!),
                    
                  // 快进按钮（非直播时显示）
                  if (!isLive && _controlsConfiguration.enableSkips)
                    _buildBottomForwardButton(),
                  
                  // 音量按钮
                  if (_controlsConfiguration.enableMute)
                    _buildMuteButton(_controller),
                  
                  const SizedBox(width: 8),
                  
                  // 时间显示（直播时不显示）
                  if (!isLive && _controlsConfiguration.enableProgressText)
                    _buildPosition(),
                    
                  const Spacer(),
                  
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

  /// 构建底部快退按钮
  Widget _buildBottomSkipButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: skipBack,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.skipBackIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建底部快进按钮
  Widget _buildBottomForwardButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: skipForward,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.skipForwardIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建全屏按钮
  Widget _buildExpandButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: _onExpandCollapse,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _iappPlayerController!.isFullScreen
              ? _controlsConfiguration.fullscreenDisableIcon
              : _controlsConfiguration.fullscreenEnableIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建点击区域
  /// 修改：移除中间的控制按钮
  Widget _buildHitArea() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
    // 返回空组件，不显示中间按钮
    return const SizedBox();
  }

  /// 构建中间控制行
  Widget _buildMiddleRow() {
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;
    
    return Container(
      color: _controlsConfiguration.controlBarColor,
      width: double.infinity,
      height: double.infinity,
      child: isLive
          ? _buildReplayButton(_controller!) // 直播时只显示播放/暂停按钮
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_controlsConfiguration.enableSkips)
                  Expanded(child: _buildSkipButton()),
                Expanded(child: _buildReplayButton(_controller!)),
                if (_controlsConfiguration.enableSkips)
                  Expanded(child: _buildForwardButton()),
              ],
            ),
    );
  }

  /// 构建点击区域按钮
  Widget _buildHitAreaClickableButton(
      {Widget? icon, required void Function() onClicked}) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 80.0, maxWidth: 80.0),
      child: IAppPlayerMaterialClickableWidget(
        onTap: onClicked,
        child: Align(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(48),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 添加背景圆形以提升视觉效果
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  icon!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建快退按钮
  Widget _buildSkipButton() {
    return _buildHitAreaClickableButton(
      icon: Icon(
        _controlsConfiguration.skipBackIcon,
        size: 24,
        color: _controlsConfiguration.iconsColor,
      ),
      onClicked: skipBack,
    );
  }

  /// 构建快进按钮
  Widget _buildForwardButton() {
    return _buildHitAreaClickableButton(
      icon: Icon(
        _controlsConfiguration.skipForwardIcon,
        size: 24,
        color: _controlsConfiguration.iconsColor,
      ),
      onClicked: skipForward,
    );
  }

  /// 构建播放/重播按钮
  Widget _buildReplayButton(VideoPlayerController controller) {
    final bool isFinished = isVideoFinished(_latestValue);
    return _buildHitAreaClickableButton(
      icon: isFinished
          ? Icon(
              Icons.replay,
              size: 42,
              color: _controlsConfiguration.iconsColor,
            )
          : Icon(
              controller.value.isPlaying
                  ? _controlsConfiguration.pauseIcon
                  : _controlsConfiguration.playIcon,
              size: 42,
              color: _controlsConfiguration.iconsColor,
            ),
      onClicked: () {
        if (isFinished) {
          if (_latestValue != null && _latestValue!.isPlaying) {
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
    );
  }

  /// 构建下一视频提示
  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          return IAppPlayerMaterialClickableWidget(
            onTap: () {
              _iappPlayerController!.playNextVideo();
            },
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: EdgeInsets.only(
                    bottom: _controlsConfiguration.controlBarHeight + 68, // 修改：根据新的底部padding调整
                    right: 24),
                decoration: BoxDecoration(
                  color: _controlsConfiguration.controlBarColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "${_iappPlayerController!.translations.controlsNextVideoIn} $time...",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  /// 构建静音按钮
  Widget _buildMuteButton(
    VideoPlayerController? controller,
  ) {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        cancelAndRestartTimer();
        if (_latestValue!.volume == 0) {
          _iappPlayerController!.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller!.value.volume;
          _iappPlayerController!.setVolume(0.0);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          (_latestValue != null && _latestValue!.volume > 0)
              ? _controlsConfiguration.muteIcon
              : _controlsConfiguration.unMuteIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建播放/暂停按钮
  Widget _buildPlayPause(VideoPlayerController controller) {
    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          controller.value.isPlaying
              ? _controlsConfiguration.pauseIcon
              : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建时间显示 - YouTube风格
  Widget _buildPosition() {
    final position =
        _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null
        ? _latestValue!.duration!
        : Duration.zero;

    return Text(
      '${IAppPlayerUtils.formatDuration(position)} / ${IAppPlayerUtils.formatDuration(duration)}',
      style: TextStyle(
        fontSize: 13.0,
        color: _controlsConfiguration.textColor,
      ),
    );
  }

  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    changePlayerControlsNotVisible(false);
    _displayTapped = true;
  }

  /// 初始化控制器
  Future<void> _initialize() async {
    _controller!.addListener(_updateState);

    _updateState();

    if ((_controller!.value.isPlaying) ||
        _iappPlayerController!.iappPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }

    if (_controlsConfiguration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        changePlayerControlsNotVisible(false);
      });
    }

    _controlsVisibilityStreamSubscription =
        _iappPlayerController!.controlsVisibilityStream.listen((state) {
      changePlayerControlsNotVisible(!state);
      if (!controlsNotVisible) {
        cancelAndRestartTimer();
      }
    });
  }

  /// 切换全屏状态
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

  /// 播放/暂停切换
  void _onPlayPause() {
    bool isFinished = false;

    if (_latestValue?.position != null && _latestValue?.duration != null) {
      isFinished = _latestValue!.position >= _latestValue!.duration!;
    }

    if (_controller!.value.isPlaying) {
      changePlayerControlsNotVisible(false);
      _hideTimer?.cancel();
      _iappPlayerController!.pause();
    } else {
      cancelAndRestartTimer();

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

  /// 启动隐藏定时器
  void _startHideTimer() {
    if (_iappPlayerController!.controlsAlwaysVisible) {
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      changePlayerControlsNotVisible(true);
    });
  }

  /// 更新播放状态
  void _updateState() {
    if (mounted) {
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
          backgroundColor:
              _controlsConfiguration.progressBarBackgroundColor),
    );
  }

  /// 控件隐藏回调
  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  /// 构建加载指示器 - YouTube风格三点动画
  Widget? _buildLoadingWidget() {
    if (_controlsConfiguration.loadingWidget != null) {
      return Container(
        color: _controlsConfiguration.controlBarColor,
        child: _controlsConfiguration.loadingWidget,
      );
    }

    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: _ThreeDotsLoadingIndicator(
          color: _controlsConfiguration.loadingColor,
        ),
      ),
    );
  }
}

/// YouTube风格三点加载动画
class _ThreeDotsLoadingIndicator extends StatefulWidget {
  final Color color;
  
  const _ThreeDotsLoadingIndicator({
    Key? key,
    required this.color,
  }) : super(key: key);
  
  @override
  _ThreeDotsLoadingIndicatorState createState() =>
      _ThreeDotsLoadingIndicatorState();
}

class _ThreeDotsLoadingIndicatorState
    extends State<_ThreeDotsLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    
    _animations = List.generate(3, (index) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            index * 0.2,
            0.6 + index * 0.2,
            curve: Curves.easeInOut,
          ),
        ),
      );
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(
                  0.3 + 0.7 * _animations[index].value,
                ),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
