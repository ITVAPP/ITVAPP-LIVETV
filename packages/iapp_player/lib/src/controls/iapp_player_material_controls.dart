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

  /// 按钮间距常量 - 参考 Chewie
  final marginSize = 5.0;

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
    /// 仅当加载状态变化时更新
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
        absorbing: controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden,
        child: Stack(
          children: [
            // 加载动画或点击区域 - 完全参考 Chewie 的互斥显示逻辑
            if (_wasLoading)
              _buildLoadingWidget()
            else
              _buildHitArea(),
            
            // 顶部控制栏 - 参考 Chewie，右上角定位
            Positioned(
              top: 0,
              right: 0,
              left: 0,  // 添加 left: 0 确保宽度正确
              child: _buildTopBar(),
            ),
            
            // 底部控制栏 - 修复：使用 Positioned 而不是 Column
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
              
            // 下一视频提示
            _buildNextVideoWidget(),
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

  /// 构建顶部控制栏 - 完全参考 Chewie 设计
  Widget _buildTopBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    return SafeArea(
      bottom: false,
      child: AnimatedOpacity(
        opacity: controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        child: Container(
          height: _controlsConfiguration.controlBarHeight,
          alignment: Alignment.topRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_controlsConfiguration.enablePip)
                _buildPipButtonWrapperWidget(controlsNotVisible, () {})
              else
                const SizedBox(),
              if (_controlsConfiguration.enableOverflowMenu)
                _buildMoreButton()
              else
                const SizedBox(),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建画中画按钮
  Widget _buildPipButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        iappPlayerController!.enablePictureInPicture(
            iappPlayerController!.iappPlayerGlobalKey!);
      },
      child: Padding(
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
          return AnimatedOpacity(
            opacity: hideStuff ? 0.0 : 1.0,
            duration: iappPlayerControlsConfiguration.controlsHideTime,
            child: Container(
              height: iappPlayerControlsConfiguration.controlBarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildPipButton(),
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
  Widget _buildMoreButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        onShowMoreClicked();
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  /// 构建底部控制栏 - 修复布局问题
  Widget _buildBottomBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
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
        child: SafeArea(
          top: false,
          bottom: _iappPlayerController!.isFullScreen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条 - 直接放在顶部，不使用 Expanded
if (!_iappPlayerController!.isLiveStream() && 
    _controlsConfiguration.enableProgressBar)
  Container(
    height: 48.0,  // 改为48px以提供足够的触摸区域
    margin: const EdgeInsets.symmetric(horizontal: 20),
    alignment: Alignment.center,
    child: Container(
      height: 4.0,  // 内部容器控制视觉高度
      child: _buildProgressBar(),
    ),
  ),
              
              // 控制按钮行
              Container(
                height: _controlsConfiguration.controlBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // 时间显示或直播标识
                    if (_iappPlayerController!.isLiveStream())
                      _buildLiveWidget()
                    else if (_controlsConfiguration.enableProgressText)
                      _buildPosition()
                    else
                      const SizedBox(),
                    
                    // 静音按钮
                    if (_controlsConfiguration.enableMute)
                      _buildMuteButton(_controller)
                    else
                      const SizedBox(),
                    
                    // 中间占位
                    const Spacer(),
                    
                    // 全屏按钮
                    if (_controlsConfiguration.enableFullscreen)
                      _buildExpandButton()
                    else
                      const SizedBox(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建直播标识
  Widget _buildLiveWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _iappPlayerController!.translations.controlsLive,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
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

  /// 构建点击区域 - 完全参考 Chewie 设计
  Widget _buildHitArea() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    final bool isFinished = isVideoFinished(_latestValue);
    final bool showPlayButton = !controlsNotVisible;

    return Container(
      color: Colors.transparent,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 后退按钮
            if (!isFinished && !_iappPlayerController!.isLiveStream() && 
                _controlsConfiguration.enableSkips)
              _buildCenterSeekButton(
                iconData: _controlsConfiguration.skipBackIcon,
                show: showPlayButton,
                onPressed: skipBack,
              ),
            // 播放/暂停按钮
            Container(
              margin: EdgeInsets.symmetric(horizontal: marginSize * 4),
              child: _buildCenterPlayButton(
                isFinished: isFinished,
                isPlaying: _controller?.value.isPlaying ?? false,
                show: showPlayButton,
                onPressed: _onPlayPause,
              ),
            ),
            // 前进按钮
            if (!isFinished && !_iappPlayerController!.isLiveStream() && 
                _controlsConfiguration.enableSkips)
              _buildCenterSeekButton(
                iconData: _controlsConfiguration.skipForwardIcon,
                show: showPlayButton,
                onPressed: skipForward,
              ),
          ],
        ),
      ),
    );
  }

  /// 构建中心播放按钮 - 参考 Chewie 的 CenterPlayButton
  Widget _buildCenterPlayButton({
    required bool isFinished,
    required bool isPlaying,
    required bool show,
    required VoidCallback onPressed,
  }) {
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: _controlsConfiguration.controlsHideTime,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(48),
        ),
        child: IAppPlayerMaterialClickableWidget(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              isFinished
                  ? Icons.replay
                  : (isPlaying 
                      ? _controlsConfiguration.pauseIcon 
                      : _controlsConfiguration.playIcon),
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建中心快进/快退按钮 - 参考 Chewie 的 CenterSeekButton
  Widget _buildCenterSeekButton({
    required IconData iconData,
    required bool show,
    required VoidCallback onPressed,
  }) {
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: _controlsConfiguration.controlsHideTime,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(48),
        ),
        child: IAppPlayerMaterialClickableWidget(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              iconData,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建下一视频提示
  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          return Positioned(
            bottom: _controlsConfiguration.controlBarHeight + 70,
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

  /// 构建时间显示
  Widget _buildPosition() {
    final position =
        _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null
        ? _latestValue!.duration!
        : Duration.zero;

    return RichText(
      text: TextSpan(
          text: IAppPlayerUtils.formatDuration(position),
          style: TextStyle(
            fontSize: 14.0,
            color: _controlsConfiguration.textColor,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
          ),
          children: <TextSpan>[
            TextSpan(
              text: ' / ${IAppPlayerUtils.formatDuration(duration)}',
              style: TextStyle(
                fontSize: 14.0,
                color: _controlsConfiguration.textColor.withOpacity(0.75),
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            )
          ]),
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

  /// 构建进度条 - 不使用 Expanded，让父容器控制宽度
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

  /// 控件隐藏回调
  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  /// 构建加载指示器 - 完全参考 Chewie 设计
  Widget _buildLoadingWidget() {
    if (_controlsConfiguration.loadingWidget != null) {
      return Center(
        child: _controlsConfiguration.loadingWidget!,
      );
    }

    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}
