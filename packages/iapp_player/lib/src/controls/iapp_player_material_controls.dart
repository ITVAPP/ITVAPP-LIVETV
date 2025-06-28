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
  /// 常量定义 - 避免魔法数字
  static const double kBottomBarPadding = 5.0;
  static const double kProgressBarHeight = 12.0;
  static const double kButtonPadding = 4.0;
  static const double kHorizontalPadding = 8.0;
  static const double kTopBarVerticalPadding = 4.0;
  static const double kIconSizeBase = 24.0;
  static const double kTextSizeBase = 13.0;
  static const double kErrorIconSize = 42.0;
  static const double kNextVideoMarginRight = 24.0;
  static const double kNextVideoPadding = 12.0;

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
  /// 是否正在加载
  bool _wasLoading = false;
  /// 视频播放控制器
  VideoPlayerController? _controller;
  /// 播放器控制器
  IAppPlayerController? _iappPlayerController;
  /// 控件可见性流订阅
  StreamSubscription? _controlsVisibilityStreamSubscription;

  /// 响应式尺寸缓存 - 避免重复计算
  double? _cachedScaleFactor;
  Size? _cachedScreenSize;

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

  /// 计算响应式尺寸 - 优化版本，缓存计算结果
  double _getResponsiveSize(BuildContext context, double baseSize) {
    final currentScreenSize = MediaQuery.of(context).size;
    
    // 如果屏幕尺寸没变，使用缓存的缩放因子
    if (_cachedScreenSize == currentScreenSize && _cachedScaleFactor != null) {
      return baseSize * _cachedScaleFactor!;
    }
    
    // 更新缓存
    _cachedScreenSize = currentScreenSize;
    final screenWidth = currentScreenSize.width;
    final screenHeight = currentScreenSize.height;
    final screenSize = screenWidth < screenHeight ? screenWidth : screenHeight;
    
    // 基于屏幕最小边计算缩放因子
    // 360是标准手机宽度，用作基准
    final scaleFactor = screenSize / 360.0;
    
    // 限制缩放范围在0.8到1.5之间
    _cachedScaleFactor = scaleFactor.clamp(0.8, 1.5);
    
    return baseSize * _cachedScaleFactor!;
  }

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
    
    // 构建主要内容
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (_wasLoading)
          Center(child: _buildLoadingWidget())
        else
          _buildHitArea(),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(),
        ),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
        _buildNextVideoWidget(),
      ],
    );
    
    // 根据配置决定手势处理策略
    if (!_controlsConfiguration.handleAllGestures) {
      // handleAllGestures = false: 只处理单击，但使用 Listener 让事件继续传递
      return Listener(
        behavior: HitTestBehavior.translucent, // 允许事件传递
        onPointerUp: (event) {
          // 处理单击逻辑
          if (IAppPlayerMultipleGestureDetector.of(context) != null) {
            IAppPlayerMultipleGestureDetector.of(context)!.onTap?.call();
          }
          controlsNotVisible
              ? cancelAndRestartTimer()
              : changePlayerControlsNotVisible(true);
        },
        child: content,
      );
    } else {
      // handleAllGestures = true: 处理所有手势，阻止事件传递
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
        child: content,
      );
    }
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
      final textStyle = TextStyle(
        color: _controlsConfiguration.textColor,
        fontSize: _getResponsiveSize(context, kTextSizeBase),
      );
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_rounded,
              color: _controlsConfiguration.iconsColor,
              size: _getResponsiveSize(context, kErrorIconSize),
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

  /// 为图标添加阴影效果包装 - 使用阴影替代边框
  Widget _wrapIconWithStroke(Widget icon) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            blurRadius: 3.0, // 阴影模糊半径
            color: Colors.black54, // 阴影颜色
            offset: Offset(0, 1), // 阴影偏移
          ),
        ],
      ),
      child: icon,
    );
  }

  /// 构建顶部控制栏
  Widget _buildTopBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }

    final responsiveControlBarHeight = _getResponsiveSize(
      context, 
      _controlsConfiguration.controlBarHeight
    );

    return (_controlsConfiguration.enableOverflowMenu)
        ? AnimatedOpacity(
            opacity: controlsNotVisible ? 0.0 : 1.0,
            duration: _controlsConfiguration.controlsHideTime,
            onEnd: _onPlayerHide,
            child: Container(
              height: responsiveControlBarHeight + kTopBarVerticalPadding * 2,
              padding: EdgeInsets.symmetric(
                horizontal: kHorizontalPadding / 2, 
                vertical: kTopBarVerticalPadding
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_controlsConfiguration.enablePip)
                    _buildPipButtonWrapperWidget()
                  else
                    const SizedBox(),
                  _buildMoreButton(),
                ],
              ),
            ),
          )
        : const SizedBox();
  }

  /// 构建画中画按钮
  Widget _buildPipButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        iappPlayerController!.enablePictureInPicture(
            iappPlayerController!.iappPlayerGlobalKey!);
      },
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            iappPlayerControlsConfiguration.pipMenuIcon,
            color: iappPlayerControlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建画中画按钮包装器
  Widget _buildPipButtonWrapperWidget() {
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
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            _controlsConfiguration.overflowMenuIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建底部控制栏 - YouTube风格布局
  /// 修改：添加快进快退按钮到底部栏，减少高度
  Widget _buildBottomBar() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;
    final responsiveControlBarHeight = _getResponsiveSize(
      context, 
      _controlsConfiguration.controlBarHeight 
    );
    
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        padding: EdgeInsets.only(bottom: kBottomBarPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 进度条区域 - 始终显示以保持布局稳定
            Container(
              height: kProgressBarHeight,
              padding: EdgeInsets.symmetric(horizontal: kHorizontalPadding * 2),
              child: _controlsConfiguration.enableProgressBar
                  ? _buildProgressBar()
                  : const SizedBox(),
            ),
            
            // 控制按钮行
            Container(
              height: responsiveControlBarHeight,
              padding: EdgeInsets.symmetric(horizontal: kHorizontalPadding),
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
                  
                  // 直播标识或时间显示（位于静音按钮右侧）- 添加左右边距
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: kButtonPadding),
                      child: isLive
                          ? _buildLiveWidget()
                          : _controlsConfiguration.enableProgressText
                              ? _buildPosition()
                              : const SizedBox(),
                    ),
                  ),
                  
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
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            _controlsConfiguration.skipBackIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建底部快进按钮
  Widget _buildBottomForwardButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: skipForward,
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            _controlsConfiguration.skipForwardIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建直播标识
  Widget _buildLiveWidget() {
    return Text(
      _iappPlayerController!.translations.controlsLive,
      style: TextStyle(
          color: _controlsConfiguration.liveTextColor,
          fontWeight: FontWeight.bold),
    );
  }
  
  /// 构建全屏按钮
  Widget _buildExpandButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: _onExpandCollapse,
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            _iappPlayerController!.isFullScreen
                ? _controlsConfiguration.fullscreenDisableIcon
                : _controlsConfiguration.fullscreenEnableIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建点击区域
  /// 修改：返回透明容器以响应点击事件
  Widget _buildHitArea() {
    if (!iappPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    
    // 返回透明容器占满整个区域，让整个播放器都能响应点击
    return Container(
      color: Colors.transparent,
      width: double.infinity,
      height: double.infinity,
    );
  }

  /// 构建下一视频提示
  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _iappPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          final responsiveControlBarHeight = _getResponsiveSize(
            context, 
            _controlsConfiguration.controlBarHeight
          );
          
          return IAppPlayerMaterialClickableWidget(
            onTap: () {
              _iappPlayerController!.playNextVideo();
            },
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: EdgeInsets.only(
                    bottom: responsiveControlBarHeight + kProgressBarHeight + kBottomBarPadding + 20,
                    right: kNextVideoMarginRight),
                decoration: BoxDecoration(
                  color: _controlsConfiguration.controlBarColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: EdgeInsets.all(kNextVideoPadding),
                  child: Text(
                    "${_iappPlayerController!.translations.controlsNextVideoIn} $time...",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _getResponsiveSize(context, kTextSizeBase),
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
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            (_latestValue != null && _latestValue!.volume > 0)
                ? _controlsConfiguration.muteIcon
                : _controlsConfiguration.unMuteIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建播放/暂停/重播按钮
  Widget _buildPlayPause(VideoPlayerController controller) {
    // 判断视频是否播放完成
    final bool isFinished = isVideoFinished(_latestValue);
    
    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            isFinished
                ? Icons.replay  // 视频播放完成时显示重播图标
                : controller.value.isPlaying
                    ? _controlsConfiguration.pauseIcon
                    : _controlsConfiguration.playIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
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
        fontSize: _getResponsiveSize(context, kTextSizeBase),
        color: _controlsConfiguration.textColor,
      ),
    );
  }

  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    changePlayerControlsNotVisible(false);
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
    _hideTimer = Timer(const Duration(milliseconds: 5000), () {
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

  /// 构建加载指示器 - 使用Flutter内置的CircularProgressIndicator
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
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            _controlsConfiguration.loadingColor ?? Colors.white,
          ),
          strokeWidth: 3.0,
        ),
      ),
    );
  }
}
