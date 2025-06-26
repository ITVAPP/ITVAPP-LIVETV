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

  /// 按钮间距常量
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

  /// 构建主控件 - 使用 Column 布局，与 Cupertino 保持一致
  Widget _buildMainWidget() {
    _iappPlayerController = IAppPlayerController.of(context);
    _controller = _iappPlayerController!.videoPlayerController;
    
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }
    
    // 关键修复：更新加载状态
    _wasLoading = isLoading(_latestValue);
    final isFullScreen = _iappPlayerController?.isFullScreen == true;
    
    // 使用 Column 而不是 Stack
    final controlsColumn = Column(
      children: <Widget>[
        _buildTopBar(),
        if (_wasLoading)
          Expanded(child: Center(child: _buildLoadingWidget()))
        else
          _buildHitArea(),
        _buildNextVideoWidget(),
        _buildBottomBar(),
      ],
    );
    
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
        _onPlayPause();
      },
      onLongPress: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      child: AbsorbPointer(
        absorbing: controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden,
        child: isFullScreen 
            ? SafeArea(child: controlsColumn) 
            : controlsColumn,
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
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  @override
  void didChangeDependencies() {
    final _oldController = _iappPlayerController;
    _iappPlayerController = IAppPlayerController.of(context);
    _controller = _iappPlayerController!.videoPlayerController;

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

  /// 构建顶部控制栏
  Widget _buildTopBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    return Container(
      height: _controlsConfiguration.controlBarHeight,
      margin: EdgeInsets.only(
        top: marginSize,
        right: marginSize,
        left: marginSize,
      ),
      child: AnimatedOpacity(
        opacity: controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        child: Row(
          children: <Widget>[
            // 左侧占位
            const Spacer(),
            // 右侧按钮
            if (_controlsConfiguration.enablePip)
              _buildPipButtonWrapper()
            else
              const SizedBox(),
            const SizedBox(width: 8),
            if (_controlsConfiguration.enableOverflowMenu)
              _buildMoreButton()
            else
              const SizedBox(),
          ],
        ),
      ),
    );
  }

  /// 构建画中画按钮包装
  Widget _buildPipButtonWrapper() {
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

  /// 构建画中画按钮
  Widget _buildPipButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        iappPlayerController!.enablePictureInPicture(
            iappPlayerController!.iappPlayerGlobalKey!);
      },
      child: Container(
        decoration: BoxDecoration(
          color: _controlsConfiguration.controlBarColor,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(
          iappPlayerControlsConfiguration.pipMenuIcon,
          color: iappPlayerControlsConfiguration.iconsColor,
          size: 20,
        ),
      ),
    );
  }

  /// 构建更多按钮
  Widget _buildMoreButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        onShowMoreClicked();
      },
      child: Container(
        decoration: BoxDecoration(
          color: _controlsConfiguration.controlBarColor,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
          size: 20,
        ),
      ),
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        alignment: Alignment.bottomCenter,
        margin: EdgeInsets.all(marginSize),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            decoration: BoxDecoration(
              color: _controlsConfiguration.controlBarColor,
            ),
            child: _iappPlayerController!.isLiveStream()
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const SizedBox(width: 8),
                      if (_controlsConfiguration.enablePlayPause)
                        _buildPlayPause(_controller!)
                      else
                        const SizedBox(),
                      const SizedBox(width: 8),
                      _buildLiveWidget(),
                      if (_controlsConfiguration.enableMute)
                        _buildMuteButton(_controller)
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableFullscreen)
                        _buildExpandButton()
                      else
                        const SizedBox(),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      if (_controlsConfiguration.enableSkips)
                        _buildSkipBack()
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enablePlayPause)
                        _buildPlayPause(_controller!)
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableSkips)
                        _buildSkipForward()
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableProgressText)
                        _buildPosition()
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableProgressBar)
                        _buildProgressBar()
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableProgressText)
                        _buildRemaining()
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableMute)
                        _buildMuteButton(_controller)
                      else
                        const SizedBox(),
                      if (_controlsConfiguration.enableFullscreen)
                        _buildExpandButton()
                      else
                        const SizedBox(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// 构建播放/暂停按钮
  GestureDetector _buildPlayPause(VideoPlayerController controller) {
    return GestureDetector(
      onTap: _onPlayPause,
      child: Container(
        height: _controlsConfiguration.controlBarHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(
          controller.value.isPlaying
              ? _controlsConfiguration.pauseIcon
              : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
          size: _controlsConfiguration.controlBarHeight * 0.6,
        ),
      ),
    );
  }

  /// 构建后退按钮
  GestureDetector _buildSkipBack() {
    return GestureDetector(
      onTap: skipBack,
      child: Container(
        height: _controlsConfiguration.controlBarHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(left: 10.0),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          _controlsConfiguration.skipBackIcon,
          color: _controlsConfiguration.iconsColor,
          size: _controlsConfiguration.controlBarHeight * 0.4,
        ),
      ),
    );
  }

  /// 构建前进按钮
  GestureDetector _buildSkipForward() {
    return GestureDetector(
      onTap: skipForward,
      child: Container(
        height: _controlsConfiguration.controlBarHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        margin: const EdgeInsets.only(right: 8.0),
        child: Icon(
          _controlsConfiguration.skipForwardIcon,
          color: _controlsConfiguration.iconsColor,
          size: _controlsConfiguration.controlBarHeight * 0.4,
        ),
      ),
    );
  }

  /// 构建当前位置文本
  Widget _buildPosition() {
    final position =
        _latestValue != null ? _latestValue!.position : const Duration();

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text(
        IAppPlayerUtils.formatDuration(position),
        style: TextStyle(
          color: _controlsConfiguration.textColor,
          fontSize: 12.0,
        ),
      ),
    );
  }

  /// 构建剩余时间文本
  Widget _buildRemaining() {
    final position = _latestValue != null && _latestValue!.duration != null
        ? _latestValue!.duration! - _latestValue!.position
        : const Duration();

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text(
        '-${IAppPlayerUtils.formatDuration(position)}',
        style: TextStyle(
          color: _controlsConfiguration.textColor,
          fontSize: 12.0,
        ),
      ),
    );
  }

  /// 构建进度条
  Widget _buildProgressBar() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0),
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
            backgroundColor: _controlsConfiguration.progressBarBackgroundColor,
          ),
        ),
      ),
    );
  }

  /// 构建直播标识
  Widget _buildLiveWidget() {
    return Expanded(
      child: Text(
        _iappPlayerController!.translations.controlsLive,
        style: TextStyle(
          color: _controlsConfiguration.liveTextColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建全屏按钮
  GestureDetector _buildExpandButton() {
    return GestureDetector(
      onTap: _onExpandCollapse,
      child: Container(
        height: _controlsConfiguration.controlBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          _iappPlayerController!.isFullScreen
              ? _controlsConfiguration.fullscreenDisableIcon
              : _controlsConfiguration.fullscreenEnableIcon,
          color: _controlsConfiguration.iconsColor,
          size: 20,
        ),
      ),
    );
  }

  /// 构建静音按钮
  Widget _buildMuteButton(VideoPlayerController? controller) {
    return GestureDetector(
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
        height: _controlsConfiguration.controlBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          (_latestValue != null && _latestValue!.volume > 0)
              ? _controlsConfiguration.muteIcon
              : _controlsConfiguration.unMuteIcon,
          color: _controlsConfiguration.iconsColor,
          size: 20,
        ),
      ),
    );
  }

  /// 构建点击区域
  Expanded _buildHitArea() {
    return Expanded(
      child: GestureDetector(
        onTap: _latestValue != null && _latestValue!.isPlaying
            ? () {
                if (controlsNotVisible == true) {
                  cancelAndRestartTimer();
                } else {
                  _hideTimer?.cancel();
                  changePlayerControlsNotVisible(true);
                }
              }
            : () {
                _hideTimer?.cancel();
                changePlayerControlsNotVisible(false);
              },
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: _buildCenterButtons(),
          ),
        ),
      ),
    );
  }

  /// 构建中心按钮组
  Widget _buildCenterButtons() {
    if (!iappPlayerController!.controlsEnabled ||
        _iappPlayerController!.isLiveStream()) {
      return const SizedBox();
    }

    final bool isFinished = isVideoFinished(_latestValue);
    final bool isPlaying = _controller?.value.isPlaying ?? false;

    return AnimatedOpacity(
      opacity: !isPlaying || isFinished || !controlsNotVisible ? 1.0 : 0.0,
      duration: _controlsConfiguration.controlsHideTime,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isFinished && _controlsConfiguration.enableSkips)
            _buildCenterButton(
              iconData: _controlsConfiguration.skipBackIcon,
              onPressed: skipBack,
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildCenterButton(
              iconData: isFinished
                  ? Icons.replay
                  : (isPlaying
                      ? _controlsConfiguration.pauseIcon
                      : _controlsConfiguration.playIcon),
              onPressed: _onPlayPause,
              isMainButton: true,
            ),
          ),
          if (!isFinished && _controlsConfiguration.enableSkips)
            _buildCenterButton(
              iconData: _controlsConfiguration.skipForwardIcon,
              onPressed: skipForward,
            ),
        ],
      ),
    );
  }

  /// 构建中心按钮
  Widget _buildCenterButton({
    required IconData iconData,
    required VoidCallback onPressed,
    bool isMainButton = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(48),
      ),
      child: IAppPlayerMaterialClickableWidget(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(isMainButton ? 12.0 : 10.0),
          child: Icon(
            iconData,
            color: Colors.white,
            size: isMainButton ? 32 : 24,
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
          return InkWell(
            onTap: () {
              _iappPlayerController!.playNextVideo();
            },
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4, right: 8),
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

  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    changePlayerControlsNotVisible(false);
    _startHideTimer();
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
        if (_iappPlayerController!.iappPlayerDataSource?.liveStream == true) {
          _iappPlayerController!.play();
          _iappPlayerController!.cancelNextVideoTimer();
        }
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
    _hideTimer = Timer(const Duration(seconds: 3), () {
      changePlayerControlsNotVisible(true);
    });
  }

  /// 更新播放状态
  void _updateState() {
    if (!mounted) return;
    
    setState(() {
      _latestValue = _controller!.value;
      if (isVideoFinished(_latestValue) &&
          _iappPlayerController?.isLiveStream() == false) {
        changePlayerControlsNotVisible(false);
      }
    });
  }

  /// 控件隐藏回调
  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  /// 构建加载指示器
  Widget? _buildLoadingWidget() {
    if (_controlsConfiguration.loadingWidget != null) {
      return _controlsConfiguration.loadingWidget;
    }

    return CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(
        _controlsConfiguration.loadingColor,
      ),
    );
  }
}
