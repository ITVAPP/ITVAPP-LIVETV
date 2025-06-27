import 'dart:async';
import 'dart:math' as math;
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

/// 播放器控件
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
    return buildLTRDirectionality(
      LayoutBuilder(
        builder: (context, constraints) {
          return _buildMainWidget(constraints.biggest);
        },
      ),
    );
  }

  /// 计算响应式缩放系数
  double _calculateScale(Size containerSize) {
    // 基准尺寸 - 基于常见的 16:9 视频播放器
    const baseWidth = 800.0;
    const baseHeight = 450.0;
    
    // 计算缩放比例
    final widthScale = containerSize.width / baseWidth;
    final heightScale = containerSize.height / baseHeight;
    
    // 使用较小的缩放比例，确保控件不会超出容器
    final scale = math.min(widthScale, heightScale);
    
    // 限制缩放范围
    // 最小 0.7 提高小屏幕文字可读性
    // 最大 2.0 防止在大屏幕上过大
    return scale.clamp(0.7, 2.0);
  }

  /// 获取响应式尺寸
  double _getResponsiveSize(double baseSize, double scale) {
    return baseSize * scale;
  }

  /// 确保最小触摸目标尺寸
  double _ensureMinTouchTarget(double size) {
    return math.max(size, 48.0);
  }

  /// 构建主控件
  Widget _buildMainWidget(Size containerSize) {
    // 计算缩放系数
    final scale = _calculateScale(containerSize);
    
    // 修复：直接使用当前加载状态，而不是依赖 _wasLoading
    final currentLoading = isLoading(_latestValue);
    _wasLoading = currentLoading;
    
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(scale),
      );
    }
    return GestureDetector(
      onTap: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onTap?.call();
        }
        controlsNotVisible
            ? cancelAndRestartTimer()
            : changePlayerControlsNotVisible(true);
      },
      onDoubleTap: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onDoubleTap?.call();
        }
        cancelAndRestartTimer();
      },
      onLongPress: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      child: AbsorbPointer(
        absorbing: controlsNotVisible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (currentLoading)  // 修复：直接使用 currentLoading
              Center(child: _buildLoadingWidget(scale))
            else
              _buildHitArea(scale),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(scale),
            ),
            Positioned(
              bottom: 0, 
              left: 0, 
              right: 0, 
              child: _buildBottomBar(scale),
            ),
            _buildNextVideoWidget(scale),
          ],
        ),
      ),
    );
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
  Widget _buildErrorWidget(double scale) {
    final errorBuilder =
        _iappPlayerController!.iappPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(
          context,
          _iappPlayerController!
              .videoPlayerController!.value.errorDescription);
    } else {
      // 错误界面图标和文字也需要响应式
      final iconSize = _getResponsiveSize(42, scale);
      final fontSize = _getResponsiveSize(14, scale);
      
      final textStyle = TextStyle(
        color: _controlsConfiguration.textColor,
        fontSize: fontSize,
      );
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning,
              color: _controlsConfiguration.iconsColor,
              size: iconSize,
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

  /// 构建顶部控制栏
  Widget _buildTopBar(double scale) {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    // 响应式控制栏高度
    final responsiveBarHeight = _getResponsiveSize(
      _controlsConfiguration.controlBarHeight, 
      scale
    );

    return Container(
      child: (_controlsConfiguration.enableOverflowMenu)
          ? AnimatedOpacity(
              opacity: controlsNotVisible ? 0.0 : 1.0,
              duration: _controlsConfiguration.controlsHideTime,
              onEnd: _onPlayerHide,
              child: Container(
                height: _ensureMinTouchTarget(responsiveBarHeight),
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_controlsConfiguration.enablePip)
                      _buildPipButtonWrapperWidget(
                          controlsNotVisible, _onPlayerHide, scale)
                    else
                      const SizedBox(),
                    _buildMoreButton(scale),
                  ],
                ),
              ),
            )
          : const SizedBox(),
    );
  }

  /// 构建画中画按钮
  Widget _buildPipButton(double scale) {
    final responsivePadding = _getResponsiveSize(8, scale);
    final responsiveIconSize = _getResponsiveSize(24, scale);

    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        iappPlayerController!.enablePictureInPicture(
            iappPlayerController!.iappPlayerGlobalKey!);
      },
      child: Padding(
        padding: EdgeInsets.all(responsivePadding),
        child: Icon(
          iappPlayerControlsConfiguration.pipMenuIcon,
          color: iappPlayerControlsConfiguration.iconsColor,
          size: responsiveIconSize,
        ),
      ),
    );
  }

  /// 构建画中画按钮包装器
  Widget _buildPipButtonWrapperWidget(
      bool hideStuff, void Function() onPlayerHide, double scale) {
    return FutureBuilder<bool>(
      future: iappPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final bool isPipSupported = snapshot.data ?? false;
        if (isPipSupported &&
            _iappPlayerController!.iappPlayerGlobalKey != null) {
          final responsiveBarHeight = _getResponsiveSize(
            iappPlayerControlsConfiguration.controlBarHeight, 
            scale
          );
          
          return AnimatedOpacity(
            opacity: hideStuff ? 0.0 : 1.0,
            duration: iappPlayerControlsConfiguration.controlsHideTime,
            onEnd: onPlayerHide,
            child: Container(
              height: _ensureMinTouchTarget(responsiveBarHeight),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildPipButton(scale),
                ],
              ),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  /// 构建更多按钮
  Widget _buildMoreButton(double scale) {
    final responsivePadding = _getResponsiveSize(8, scale);
    final responsiveIconSize = _getResponsiveSize(24, scale);

    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        onShowMoreClicked();
      },
      child: Padding(
        padding: EdgeInsets.all(responsivePadding),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
          size: responsiveIconSize,
        ),
      ),
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomBar(double scale) {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
    // 响应式控制栏高度和额外空间
    final responsiveBarHeight = _getResponsiveSize(
      _controlsConfiguration.controlBarHeight, 
      scale
    );
    final responsiveExtraSpace = _getResponsiveSize(20.0, scale);
    
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        height: _ensureMinTouchTarget(responsiveBarHeight) + responsiveExtraSpace,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              flex: 75,
              child: Row(
                children: [
                  if (_controlsConfiguration.enablePlayPause)
                    _buildPlayPause(_controller!, scale)
                  else
                    const SizedBox(),
                  if (_iappPlayerController!.isLiveStream())
                    _buildLiveWidget(scale)
                  else
                    _controlsConfiguration.enableProgressText
                        ? Expanded(child: _buildPosition(scale))
                        : const SizedBox(),
                  const Spacer(),
                  if (_controlsConfiguration.enableMute)
                    _buildMuteButton(_controller, scale)
                  else
                    const SizedBox(),
                  if (_controlsConfiguration.enableFullscreen)
                    _buildExpandButton(scale)
                  else
                    const SizedBox(),
                ],
              ),
            ),
            if (_iappPlayerController!.isLiveStream())
              const SizedBox()
            else
              _controlsConfiguration.enableProgressBar
                  ? _buildProgressBar(scale)
                  : const SizedBox(),
          ],
        ),
      ),
    );
  }

  /// 构建直播标识
  Widget _buildLiveWidget(double scale) {
    final responsiveFontSize = _getResponsiveSize(14, scale);
    
    return Text(
      _iappPlayerController!.translations.controlsLive,
      style: TextStyle(
          color: _controlsConfiguration.liveTextColor,
          fontWeight: FontWeight.bold,
          fontSize: responsiveFontSize),
    );
  }

  /// 构建全屏按钮
  Widget _buildExpandButton(double scale) {
    final responsivePadding = _getResponsiveSize(12.0, scale);
    final responsiveIconSize = _getResponsiveSize(24, scale);
    final responsiveBarHeight = _getResponsiveSize(
      _controlsConfiguration.controlBarHeight, 
      scale
    );

    return Padding(
      padding: EdgeInsets.only(right: responsivePadding),
      child: IAppPlayerMaterialClickableWidget(
        onTap: _onExpandCollapse,
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: Container(
            height: _ensureMinTouchTarget(responsiveBarHeight),
            padding: EdgeInsets.symmetric(horizontal: _getResponsiveSize(8.0, scale)),
            child: Center(
              child: Icon(
                _iappPlayerController!.isFullScreen
                    ? _controlsConfiguration.fullscreenDisableIcon
                    : _controlsConfiguration.fullscreenEnableIcon,
                color: _controlsConfiguration.iconsColor,
                size: responsiveIconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建点击区域
  Widget _buildHitArea(double scale) {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    return Container(
      child: Center(
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: _buildMiddleRow(scale),
        ),
      ),
    );
  }

  /// 构建中间控制行
  Widget _buildMiddleRow(double scale) {
    return Container(
      color: _controlsConfiguration.controlBarColor,
      width: double.infinity,
      height: double.infinity,
      child: _iappPlayerController?.isLiveStream() == true
          ? const SizedBox()
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_controlsConfiguration.enableSkips)
                  Expanded(child: _buildSkipButton(scale)),
                Expanded(child: _buildReplayButton(_controller!, scale)),
                if (_controlsConfiguration.enableSkips)
                  Expanded(child: _buildForwardButton(scale)),
              ],
            ),
    );
  }

  /// 构建点击区域按钮
  Widget _buildHitAreaClickableButton({
    Widget? icon, 
    required void Function() onClicked,
    required double scale,
  }) {
    final responsiveMaxSize = _getResponsiveSize(80.0, scale);
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: responsiveMaxSize, 
        maxWidth: responsiveMaxSize,
      ),
      child: IAppPlayerMaterialClickableWidget(
        onTap: onClicked,
        child: Align(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(48),
            ),
            child: Padding(
              padding: EdgeInsets.all(_getResponsiveSize(8, scale)),
              child: icon!,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建快退按钮
  Widget _buildSkipButton(double scale) {
    final responsiveIconSize = _getResponsiveSize(24, scale);
    
    return _buildHitAreaClickableButton(
      icon: Icon(
        _controlsConfiguration.skipBackIcon,
        size: responsiveIconSize,
        color: _controlsConfiguration.iconsColor,
      ),
      onClicked: skipBack,
      scale: scale,
    );
  }

  /// 构建快进按钮
  Widget _buildForwardButton(double scale) {
    final responsiveIconSize = _getResponsiveSize(24, scale);
    
    return _buildHitAreaClickableButton(
      icon: Icon(
        _controlsConfiguration.skipForwardIcon,
        size: responsiveIconSize,
        color: _controlsConfiguration.iconsColor,
      ),
      onClicked: skipForward,
      scale: scale,
    );
  }

  /// 构建播放/重播按钮
  Widget _buildReplayButton(VideoPlayerController controller, double scale) {
    final bool isFinished = isVideoFinished(_latestValue);
    final responsiveIconSize = _getResponsiveSize(42, scale);
    
    return _buildHitAreaClickableButton(
      icon: isFinished
          ? Icon(
              Icons.replay,
              size: responsiveIconSize,
              color: _controlsConfiguration.iconsColor,
            )
          : Icon(
              controller.value.isPlaying
                  ? _controlsConfiguration.pauseIcon
                  : _controlsConfiguration.playIcon,
              size: responsiveIconSize,
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
      scale: scale,
    );
  }

  /// 构建下一视频提示
  Widget _buildNextVideoWidget(double scale) {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          final responsiveBarHeight = _getResponsiveSize(
            _controlsConfiguration.controlBarHeight, 
            scale
          );
          final responsiveMargin = _getResponsiveSize(24, scale);
          final responsivePadding = _getResponsiveSize(12, scale);
          final responsiveFontSize = _getResponsiveSize(14, scale);
          
          return IAppPlayerMaterialClickableWidget(
            onTap: () {
              _iappPlayerController!.playNextVideo();
            },
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: EdgeInsets.only(
                    bottom: responsiveBarHeight + _getResponsiveSize(20, scale),
                    right: responsiveMargin),
                decoration: BoxDecoration(
                  color: _controlsConfiguration.controlBarColor,
                  borderRadius: BorderRadius.circular(_getResponsiveSize(16, scale)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(responsivePadding),
                  child: Text(
                    "${_iappPlayerController!.translations.controlsNextVideoIn} $time...",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: responsiveFontSize,
                    ),
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
    double scale,
  ) {
    final responsiveBarHeight = _getResponsiveSize(
      _controlsConfiguration.controlBarHeight, 
      scale
    );
    final responsivePadding = _getResponsiveSize(8, scale);
    final responsiveIconSize = _getResponsiveSize(24, scale);
    
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
      child: AnimatedOpacity(
        opacity: controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        child: ClipRect(
          child: Container(
            height: _ensureMinTouchTarget(responsiveBarHeight),
            padding: EdgeInsets.symmetric(horizontal: responsivePadding),
            child: Icon(
              (_latestValue != null && _latestValue!.volume > 0)
                  ? _controlsConfiguration.muteIcon
                  : _controlsConfiguration.unMuteIcon,
              color: _controlsConfiguration.iconsColor,
              size: responsiveIconSize,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建播放/暂停按钮
  Widget _buildPlayPause(VideoPlayerController controller, double scale) {
    final responsiveHorizontalMargin = _getResponsiveSize(4, scale);
    final responsiveHorizontalPadding = _getResponsiveSize(12, scale);
    final responsiveIconSize = _getResponsiveSize(24, scale);
    
    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        height: double.infinity,
        margin: EdgeInsets.symmetric(horizontal: responsiveHorizontalMargin),
        padding: EdgeInsets.symmetric(horizontal: responsiveHorizontalPadding),
        child: Icon(
          controller.value.isPlaying
              ? _controlsConfiguration.pauseIcon
              : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
          size: responsiveIconSize,
        ),
      ),
    );
  }

  /// 构建时间显示
  Widget _buildPosition(double scale) {
    final position =
        _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null
        ? _latestValue!.duration!
        : Duration.zero;

    final responsiveFontSize = _getResponsiveSize(10.0, scale);
    final responsivePadding = _controlsConfiguration.enablePlayPause
        ? EdgeInsets.only(right: _getResponsiveSize(24, scale))
        : EdgeInsets.symmetric(horizontal: _getResponsiveSize(22, scale));

    return Padding(
      padding: responsivePadding,
      child: RichText(
        text: TextSpan(
            text: IAppPlayerUtils.formatDuration(position),
            style: TextStyle(
              fontSize: responsiveFontSize,
              color: _controlsConfiguration.textColor,
              decoration: TextDecoration.none,
            ),
            children: <TextSpan>[
              TextSpan(
                text: ' / ${IAppPlayerUtils.formatDuration(duration)}',
                style: TextStyle(
                  fontSize: responsiveFontSize,
                  color: _controlsConfiguration.textColor,
                  decoration: TextDecoration.none,
                ),
              )
            ]),
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
  Widget _buildProgressBar(double scale) {
    final responsivePadding = _getResponsiveSize(12, scale);
    
    return Expanded(
      flex: 40,
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: EdgeInsets.symmetric(horizontal: responsivePadding),
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
            cancelAndRestartTimer();
          },
          colors: IAppPlayerProgressColors(
              playedColor: _controlsConfiguration.progressBarPlayedColor,
              handleColor: _controlsConfiguration.progressBarHandleColor,
              bufferedColor: _controlsConfiguration.progressBarBufferedColor,
              backgroundColor:
                  _controlsConfiguration.progressBarBackgroundColor),
        ),
      ),
    );
  }

  /// 控件隐藏回调
  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  /// 构建加载指示器
  Widget? _buildLoadingWidget(double scale) {
    if (_controlsConfiguration.loadingWidget != null) {
      return Container(
        color: _controlsConfiguration.controlBarColor,
        child: _controlsConfiguration.loadingWidget,
      );
    }

    // 加载指示器大小也需要响应式
    final responsiveIndicatorSize = _getResponsiveSize(40.0, scale);
    
    return SizedBox(
      width: responsiveIndicatorSize,
      height: responsiveIndicatorSize,
      child: CircularProgressIndicator(
        valueColor:
            AlwaysStoppedAnimation<Color>(_controlsConfiguration.loadingColor),
      ),
    );
  }
}
