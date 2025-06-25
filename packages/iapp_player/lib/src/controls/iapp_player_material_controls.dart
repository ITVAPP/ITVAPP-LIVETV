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
        _onPlayPause();
      },
      onLongPress: () {
        if (IAppPlayerMultipleGestureDetector.of(context) != null) {
          IAppPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      child: AbsorbPointer(
        absorbing: controlsNotVisible && _controlsConfiguration.absorbTouchWhenControlsHidden,
        child: Stack(
          fit: StackFit.expand,  // 修改：添加 expand 确保 Stack 填充可用空间，使 Positioned 子组件能正确定位
          children: [
            // 背景层（点击区域）
            Positioned.fill(
              child: Container(
                color: Colors.transparent,
              ),
            ),
            // 加载指示器层 - 现代化设计
            if (_wasLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLoadingWidget() ?? const SizedBox(),
                        const SizedBox(height: 16),
                        Text(
                          '加载中...',
                          style: TextStyle(
                            color: _controlsConfiguration.textColor.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // 中间控制按钮层 - 重新设计
            if (!_wasLoading && iappPlayerController!.controlsEnabled)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: controlsNotVisible ? 0.0 : 1.0,
                  duration: _controlsConfiguration.controlsHideTime,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.transparent,
                        ],
                        radius: 0.8,
                      ),
                    ),
                    child: Center(
                      child: _buildCenterControls(),
                    ),
                  ),
                ),
              ),
            // 顶部控制栏 - 渐变背景
            AnimatedPositioned(
              duration: _controlsConfiguration.controlsHideTime,
              top: controlsNotVisible ? -60 : 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            // 底部控制栏 - 现代化设计
            AnimatedPositioned(
              duration: _controlsConfiguration.controlsHideTime,
              bottom: controlsNotVisible ? -100 : 0,
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

  /// 构建中间控制按钮 - 全新设计
  Widget _buildCenterControls() {
    if (_iappPlayerController?.isLiveStream() == true) {
      return const SizedBox();
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 快退按钮
        if (_controlsConfiguration.enableSkips)
          _buildCircularButton(
            icon: _controlsConfiguration.skipBackIcon,
            size: 56,
            iconSize: 28,
            onTap: skipBack,
          ),
        const SizedBox(width: 24),
        // 播放/暂停按钮 - 主按钮更大
        _buildPlayPauseButton(),
        const SizedBox(width: 24),
        // 快进按钮
        if (_controlsConfiguration.enableSkips)
          _buildCircularButton(
            icon: _controlsConfiguration.skipForwardIcon,
            size: 56,
            iconSize: 28,
            onTap: skipForward,
          ),
      ],
    );
  }

  /// 构建圆形按钮 - 统一风格
  Widget _buildCircularButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? iconColor,
  }) {
    return Material(
      color: backgroundColor ?? Colors.black.withOpacity(0.6),
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor ?? _controlsConfiguration.iconsColor,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建播放/暂停按钮 - 主按钮
  Widget _buildPlayPauseButton() {
    final bool isFinished = isVideoFinished(_latestValue);
    final bool isPlaying = _controller?.value.isPlaying ?? false;
    
    return _buildCircularButton(
      icon: isFinished
          ? Icons.replay_rounded
          : isPlaying
              ? _controlsConfiguration.pauseIcon
              : _controlsConfiguration.playIcon,
      size: 72,
      iconSize: 42,
      backgroundColor: Colors.white.withOpacity(0.9),
      iconColor: Colors.black87,
      onTap: () {
        if (isFinished) {
          _iappPlayerController!.seekTo(const Duration());
          _iappPlayerController!.play();
        } else {
          _onPlayPause();
        }
      },
    );
  }

  /// 构建顶部控制栏 - 渐变背景
  Widget _buildTopBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    return Container(
      height: 80,
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
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // 左侧按钮组
              if (_controlsConfiguration.enablePip)
                _buildTopBarButton(
                  icon: _controlsConfiguration.pipMenuIcon,
                  onTap: () {
                    iappPlayerController!.enablePictureInPicture(
                        iappPlayerController!.iappPlayerGlobalKey!);
                  },
                ),
              // 中间标题区域（可扩展）
              Expanded(
                child: Container(),
              ),
              // 右侧按钮组
              if (_controlsConfiguration.enableOverflowMenu)
                _buildTopBarButton(
                  icon: _controlsConfiguration.overflowMenuIcon,
                  onTap: onShowMoreClicked,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建顶部栏按钮
  Widget _buildTopBarButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: _controlsConfiguration.iconsColor,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// 构建底部控制栏 - 现代化设计
  Widget _buildBottomBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.black.withOpacity(0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条 - 独立一行，更容易操作
            if (!_iappPlayerController!.isLiveStream() && 
                _controlsConfiguration.enableProgressBar)
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // 当前时间
                    if (_controlsConfiguration.enableProgressText)
                      Text(
                        IAppPlayerUtils.formatDuration(
                          _latestValue?.position ?? Duration.zero,
                        ),
                        style: TextStyle(
                          color: _controlsConfiguration.textColor,
                          fontSize: 12,
                        ),
                      ),
                    // 进度条
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildProgressBar(),
                      ),
                    ),
                    // 总时长
                    if (_controlsConfiguration.enableProgressText)
                      Text(
                        IAppPlayerUtils.formatDuration(
                          _latestValue?.duration ?? Duration.zero,
                        ),
                        style: TextStyle(
                          color: _controlsConfiguration.textColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            // 控制按钮行
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // 播放/暂停按钮（小版本）
                  if (_controlsConfiguration.enablePlayPause)
                    _buildBottomBarButton(
                      icon: _controller?.value.isPlaying ?? false
                          ? _controlsConfiguration.pauseIcon
                          : _controlsConfiguration.playIcon,
                      onTap: _onPlayPause,
                    ),
                  // 下一个视频按钮（如果有播放列表）
                  if (_iappPlayerController?.iappPlayerPlaylistConfiguration != null)
                    _buildBottomBarButton(
                      icon: Icons.skip_next_rounded,
                      onTap: () {
                        _iappPlayerController!.playNextVideo();
                      },
                    ),
                  // 直播标识
                  if (_iappPlayerController!.isLiveStream())
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _controlsConfiguration.liveTextColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // 音量按钮
                  if (_controlsConfiguration.enableMute)
                    _buildBottomBarButton(
                      icon: (_latestValue?.volume ?? 1.0) > 0
                          ? _controlsConfiguration.muteIcon
                          : _controlsConfiguration.unMuteIcon,
                      onTap: () {
                        if (_latestValue!.volume == 0) {
                          _iappPlayerController!.setVolume(_latestVolume ?? 0.5);
                        } else {
                          _latestVolume = _controller!.value.volume;
                          _iappPlayerController!.setVolume(0.0);
                        }
                      },
                    ),
                  // 全屏按钮
                  if (_controlsConfiguration.enableFullscreen)
                    _buildBottomBarButton(
                      icon: _iappPlayerController!.isFullScreen
                          ? _controlsConfiguration.fullscreenDisableIcon
                          : _controlsConfiguration.fullscreenEnableIcon,
                      onTap: _onExpandCollapse,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部栏按钮
  Widget _buildBottomBarButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: _controlsConfiguration.iconsColor,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// 构建进度条 - 改进的样式
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
        backgroundColor: _controlsConfiguration.progressBarBackgroundColor.withOpacity(0.3),
      ),
    );
  }

  /// 构建下一视频提示 - 现代化设计
  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          return Positioned(
            right: 16,
            bottom: 120,
            child: Material(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () {
                  _iappPlayerController!.playNextVideo();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${_iappPlayerController!.translations.controlsNextVideoIn} $time",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
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

  /// 构建错误提示 - 现代化设计
  Widget _buildErrorWidget() {
    final errorBuilder =
        _iappPlayerController!.iappPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(
          context,
          _iappPlayerController!
              .videoPlayerController!.value.errorDescription);
    } else {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: _controlsConfiguration.iconsColor.withOpacity(0.8),
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _iappPlayerController!.translations.generalDefaultError,
                style: TextStyle(
                  color: _controlsConfiguration.textColor,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              if (_controlsConfiguration.enableRetry) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    _iappPlayerController!.retryDataSource();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    _iappPlayerController!.translations.generalRetry,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
  }

  /// 构建加载指示器
  Widget? _buildLoadingWidget() {
    if (_controlsConfiguration.loadingWidget != null) {
      return _controlsConfiguration.loadingWidget;
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(
          _controlsConfiguration.loadingColor,
        ),
        strokeWidth: 3,
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

  /// 控件隐藏回调
  void _onPlayerHide() {
    _iappPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }
}
