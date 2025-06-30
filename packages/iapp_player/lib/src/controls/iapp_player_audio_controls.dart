import 'dart:async';
import 'package:iapp_player/src/configuration/iapp_player_controls_configuration.dart';
import 'package:iapp_player/src/controls/iapp_player_clickable_widget.dart';
import 'package:iapp_player/src/controls/iapp_player_controls_state.dart';
import 'package:iapp_player/src/controls/iapp_player_material_progress_bar.dart';
import 'package:iapp_player/src/controls/iapp_player_progress_colors.dart';
import 'package:iapp_player/src/core/iapp_player_controller.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:flutter/material.dart';

// 音频播放控件，复用Material Controls风格
class IAppPlayerAudioControls extends StatefulWidget {
  // 控件可见性变化回调
  final Function(bool visbility) onControlsVisibilityChanged;
  // 控件配置
  final IAppPlayerControlsConfiguration controlsConfiguration;

  const IAppPlayerAudioControls({
    Key? key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _IAppPlayerAudioControlsState();
}

class _IAppPlayerAudioControlsState extends IAppPlayerControlsState<IAppPlayerAudioControls> {
  // 基础间距系统 - 统一的设计语言
  static const double kSpacingUnit = 8.0;         // 基础间距单位 (8的倍数设计系统)
  static const double kSpacingHalf = 4.0;         // 半间距 (kSpacingUnit / 2)
  static const double kSpacingDouble = 16.0;      // 双倍间距 (kSpacingUnit * 2)
  
  // 组件尺寸 - 保持独立，不与间距混淆
  static const double kProgressBarHeight = 12.0;
  static const double kAudioControlBarHeight = 40.0;
  static const double kIconSizeBase = 24.0;       // 保持独立：用于响应式计算
  static const double kTextSizeBase = 13.0;       // 保持独立：文本基础尺寸
  static const double kErrorIconSize = 42.0;
  
  // 阴影效果
  static const double kIconShadowBlurRadius = 3.0;
  static const double kTextShadowBlurRadius = 2.0;
  static const double kShadowOffsetY = 1.0;
  static const double kShadowOffsetX = 0.0;
  
  // 播放列表模态框 - 相关常量组合
  static const double kModalBorderRadius = 24.0;
  static const double kModalPadding = 16.0;           // 使用 kSpacingDouble
  static const double kModalItemPaddingHorizontal = 16.0;  // 使用 kSpacingDouble
  static const double kModalItemPaddingVertical = 12.0;
  static const double kModalItemSpacing = 16.0;       // 使用 kSpacingDouble
  static const double kModalTitleFontSize = 18.0;     // 保持独立：字体大小
  static const double kModalItemFontSize = 16.0;      // 保持独立：字体大小
  static const double kPlayIndicatorIconSize = 20.0;
  static const double kPlayIndicatorWidth = 24.0;
  
  // 功能性常量
  static const double kDisabledButtonOpacity = 0.3;
  static const double kDefaultVolume = 0.5;
  static const double kMutedVolume = 0.0;
  static const double kEmptyPlaylistHeight = 200.0;
  static const double kPlaylistMaxHeightRatio = 0.6;
  
  // 特定用途间距 - 保持语义清晰
  static const double kTimeTextSizeDecrease = 1.0;
  static const double kTimeDisplayBottomPadding = 6.0;
  static const double kProgressToTimeSpacing = 3.0;
  static const double kZeroPadding = 0.0;

  // 最新播放值
  VideoPlayerValue? _latestValue;
  // 最新音量，用于静音恢复
  double? _latestVolume;
  // 视频播放控制器
  VideoPlayerController? _controller;
  // 播放器控制器
  IAppPlayerController? _iappPlayerController;

  // 获取控件配置
  IAppPlayerControlsConfiguration get _controlsConfiguration => widget.controlsConfiguration;

  @override
  VideoPlayerValue? get latestValue => _latestValue;

  @override
  IAppPlayerController? get iappPlayerController => _iappPlayerController;

  @override
  IAppPlayerControlsConfiguration get iappPlayerControlsConfiguration => _controlsConfiguration;

  // 响应式尺寸缓存
  double? _cachedScaleFactor;
  // 屏幕尺寸缓存
  Size? _cachedScreenSize;
  // 缓存的响应式尺寸
  late double _responsiveIconSize;
  late double _responsiveTextSize;
  late double _responsiveErrorIconSize;

  // 计算响应式尺寸
  double _getResponsiveSize(BuildContext context, double baseSize) {
    final currentScreenSize = MediaQuery.of(context).size;

    if (_cachedScreenSize == currentScreenSize && _cachedScaleFactor != null) {
      return baseSize * _cachedScaleFactor!;
    }

    _cachedScreenSize = currentScreenSize;
    final screenWidth = currentScreenSize.width;
    final screenHeight = currentScreenSize.height;
    final screenSize = screenWidth < screenHeight ? screenWidth : screenHeight;

    final scaleFactor = screenSize / 360.0;
    _cachedScaleFactor = scaleFactor.clamp(0.8, 1.5);

    return baseSize * _cachedScaleFactor!;
  }

  // 预计算所有响应式尺寸
  void _precalculateResponsiveSizes(BuildContext context) {
    _responsiveIconSize = _getResponsiveSize(context, kIconSizeBase);
    _responsiveTextSize = _getResponsiveSize(context, kTextSizeBase);
    _responsiveErrorIconSize = _getResponsiveSize(context, kErrorIconSize);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 预计算所有响应式尺寸，避免重复计算
    _precalculateResponsiveSizes(context);
    return buildLTRDirectionality(_buildMainWidget());
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  // 清理控制器监听
  void _dispose() {
    _controller?.removeListener(_updateState);
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

  // 构建主控件布局
  Widget _buildMainWidget() {
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }

    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressSection(),
          _buildControlsSection(),
        ],
      ),
    );
  }

  // 构建错误提示界面
  Widget _buildErrorWidget() {
    final errorBuilder = _iappPlayerController!.iappPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(context, _iappPlayerController!.videoPlayerController!.value.errorDescription);
    } else {
      final textStyle = TextStyle(
        color: _controlsConfiguration.textColor,
        fontSize: _responsiveTextSize,
      );
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_rounded,
              color: _controlsConfiguration.iconsColor,
              size: _responsiveErrorIconSize,
            ),
            SizedBox(height: kSpacingDouble), // 使用统一间距
            Text(
              _iappPlayerController!.translations.generalDefaultError,
              style: textStyle,
            ),
            if (_controlsConfiguration.enableRetry)
              SizedBox(height: kSpacingDouble), // 使用统一间距
            if (_controlsConfiguration.enableRetry)
              TextButton(
                onPressed: () => _iappPlayerController!.retryDataSource(),
                child: Text(
                  _iappPlayerController!.translations.generalRetry,
                  style: textStyle.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      );
    }
  }

  // 为图标添加阴影效果
  Widget _wrapIconWithStroke(Widget icon) {
    if (icon is Icon) {
      return Icon(
        icon.icon,
        color: icon.color,
        size: icon.size,
        shadows: const [
          Shadow(
            blurRadius: kIconShadowBlurRadius,
            color: Colors.black45,
            offset: Offset(kShadowOffsetX, kShadowOffsetY),
          ),
        ],
      );
    }
    return icon;
  }

  // 文本阴影效果
  static const List<Shadow> _textShadows = [
    Shadow(
      blurRadius: kTextShadowBlurRadius,
      color: Colors.black54,
      offset: Offset(kShadowOffsetX, kShadowOffsetY),
    ),
  ];

  // 进度条容器阴影
  static const List<BoxShadow> _progressBarShadows = [
    BoxShadow(
      blurRadius: kIconShadowBlurRadius,
      color: Colors.black45,
      offset: Offset(kShadowOffsetX, kShadowOffsetY),
    ),
  ];

  // 构建进度条区域
  Widget _buildProgressSection() {
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;

    return Container(
      padding: EdgeInsets.only(
        left: kSpacingDouble,    // 使用统一间距
        right: kSpacingDouble,   // 使用统一间距
        top: isLive ? kZeroPadding : kSpacingUnit,
        bottom: isLive ? kZeroPadding : kSpacingUnit,
      ),
      child: Column(
        children: [
          if (_controlsConfiguration.enableProgressBar)
            Container(
              height: kProgressBarHeight,
              decoration: const BoxDecoration(boxShadow: _progressBarShadows),
              child: _buildProgressBar(),
            ),
          if (_controlsConfiguration.enableProgressText && !isLive) ...[
            const SizedBox(height: kProgressToTimeSpacing),
            _buildPosition(),
          ],
        ],
      ),
    );
  }

  // 构建时间显示
  Widget _buildPosition() {
    final position = _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null ? _latestValue!.duration! : Duration.zero;

    final textStyle = TextStyle(
      fontSize: _responsiveTextSize - kTimeTextSizeDecrease,
      color: _controlsConfiguration.textColor,
      shadows: _textShadows,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: kTimeDisplayBottomPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(IAppPlayerUtils.formatDuration(position), style: textStyle),
          Text(IAppPlayerUtils.formatDuration(duration), style: textStyle),
        ],
      ),
    );
  }

  // 构建控制按钮区域
  Widget _buildControlsSection() {
    final bool isPlaylist = _iappPlayerController!.isPlaylistMode;
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;

    return Container(
      height: kAudioControlBarHeight,
      padding: EdgeInsets.symmetric(horizontal: kSpacingUnit), // 使用统一间距
      child: Row(
        children: [
          if (isPlaylist) ...[
            _buildShuffleButton(),
            if (_controlsConfiguration.enableMute) _buildMuteButton(),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPreviousButton(),
                  _buildPlayPauseButton(),
                  _buildNextButton(),
                ],
              ),
            ),
            _buildPlaylistMenuButton(),
          ] else ...[
            if (_controlsConfiguration.enableMute) _buildMuteButton(),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isLive) _buildSkipBackButton(),
                  _buildPlayPauseButton(),
                  if (!isLive) _buildSkipForwardButton(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 构建静音按钮
  Widget _buildMuteButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        if (_latestValue == null || _controller == null) return;
        if (_latestValue!.volume == kMutedVolume) {
          _iappPlayerController!.setVolume(_latestVolume ?? kDefaultVolume);
        } else {
          _latestVolume = _controller!.value.volume;
          _iappPlayerController!.setVolume(kMutedVolume);
        }
      },
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            (_latestValue?.volume ?? kMutedVolume) > kMutedVolume ? _controlsConfiguration.muteIcon : _controlsConfiguration.unMuteIcon,
            color: _controlsConfiguration.iconsColor,
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建随机/顺序播放按钮
  Widget _buildShuffleButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        _iappPlayerController!.togglePlaylistShuffle();
        setState(() {});
      },
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            _iappPlayerController!.playlistShuffleMode ? Icons.shuffle : Icons.repeat,
            color: _controlsConfiguration.iconsColor,
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建上一曲按钮
  Widget _buildPreviousButton() {
    final bool hasPrevious = _iappPlayerController!.playlistController?.hasPrevious ?? false;
    final bool isEnabled = hasPrevious;

    return IAppPlayerMaterialClickableWidget(
      onTap: isEnabled ? _playPrevious : null,
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            Icons.skip_previous,
            color: isEnabled ? _controlsConfiguration.iconsColor : _controlsConfiguration.iconsColor.withOpacity(kDisabledButtonOpacity),
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建下一曲按钮
  Widget _buildNextButton() {
    final bool hasNext = _iappPlayerController!.playlistController?.hasNext ?? false;
    final bool isEnabled = hasNext;

    return IAppPlayerMaterialClickableWidget(
      onTap: isEnabled ? _playNext : null,
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            Icons.skip_next,
            color: isEnabled ? _controlsConfiguration.iconsColor : _controlsConfiguration.iconsColor.withOpacity(kDisabledButtonOpacity),
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建播放/暂停按钮
  Widget _buildPlayPauseButton() {
    final bool isFinished = isVideoFinished(_latestValue);
    final bool isPlaying = _controller?.value.isPlaying ?? false;

    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_audio_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            isFinished ? Icons.replay : isPlaying ? _controlsConfiguration.pauseIcon : _controlsConfiguration.playIcon,
            color: _controlsConfiguration.iconsColor,
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建快退按钮
  Widget _buildSkipBackButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: skipBack,
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            _controlsConfiguration.skipBackIcon,
            color: _controlsConfiguration.iconsColor,
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建快进按钮
  Widget _buildSkipForwardButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: skipForward,
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            _controlsConfiguration.skipForwardIcon,
            color: _controlsConfiguration.iconsColor,
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 构建播放列表菜单按钮
  Widget _buildPlaylistMenuButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: _showPlaylistMenu,
      child: Container(
        padding: EdgeInsets.all(kSpacingHalf), // 使用统一间距
        child: _wrapIconWithStroke(
          Icon(
            Icons.queue_music,
            color: _controlsConfiguration.iconsColor,
            size: _responsiveIconSize,
          ),
        ),
      ),
    );
  }

  // 显示播放列表菜单
  void _showPlaylistMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: _controlsConfiguration.overflowModalColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(kModalBorderRadius),
              topRight: Radius.circular(kModalBorderRadius),
            ),
          ),
          child: _buildPlaylistMenuContent(),
        ),
      ),
    );
  }

  // 构建播放列表菜单内容
  Widget _buildPlaylistMenuContent() {
    final playlistController = _iappPlayerController!.playlistController;
    final translations = _iappPlayerController!.translations;

    if (playlistController == null) {
      return SizedBox(
        height: kEmptyPlaylistHeight,
        child: Center(
          child: Text(
            translations.playlistUnavailable,
            style: TextStyle(color: _controlsConfiguration.overflowModalTextColor),
          ),
        ),
      );
    }

    final dataSourceList = playlistController.dataSourceList;
    final currentIndex = playlistController.currentDataSourceIndex;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * kPlaylistMaxHeightRatio),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(kModalPadding), // 独立的模态框内边距
            child: Row(
              children: [
                Text(
                  translations.playlistTitle,
                  style: TextStyle(
                    color: _controlsConfiguration.overflowModalTextColor,
                    fontSize: kModalTitleFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: _controlsConfiguration.overflowModalTextColor),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: kModalPadding), // 独立的模态框内边距
              itemCount: dataSourceList.length,
              itemBuilder: (context, index) {
                final dataSource = dataSourceList[index];
                final isCurrentItem = index == currentIndex;
                final title = dataSource.notificationConfiguration?.title ?? translations.trackItem.replaceAll('{index}', '${index + 1}');

                return IAppPlayerMaterialClickableWidget(
                  onTap: () {
                    _playAtIndex(index);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: kModalItemPaddingHorizontal, // 独立的列表项内边距
                      vertical: kModalItemPaddingVertical
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: kPlayIndicatorWidth,
                          child: isCurrentItem ? Icon(Icons.play_arrow, color: _controlsConfiguration.overflowModalTextColor, size: kPlayIndicatorIconSize) : null,
                        ),
                        SizedBox(width: kModalItemSpacing), // 独立的列表项间距
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: _controlsConfiguration.overflowModalTextColor,
                              fontSize: kModalItemFontSize,
                              fontWeight: isCurrentItem ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 播放上一曲
  void _playPrevious() {
    final playlistController = _iappPlayerController!.playlistController;
    if (playlistController != null) {
      playlistController.playPrevious();
    }
  }

  // 播放下一曲
  void _playNext() {
    final playlistController = _iappPlayerController!.playlistController;
    if (playlistController != null) {
      playlistController.playNext();
    }
  }

  // 播放指定索引曲目
  void _playAtIndex(int index) {
    final playlistController = _iappPlayerController!.playlistController;
    if (playlistController != null) {
      playlistController.setupDataSource(index);
    }
  }

  // 播放/暂停切换
  void _onPlayPause() {
    bool isFinished = false;

    if (_latestValue?.position != null && _latestValue?.duration != null) {
      isFinished = _latestValue!.position >= _latestValue!.duration!;
    }

    if (_controller!.value.isPlaying) {
      _iappPlayerController!.pause();
    } else {
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

  // 初始化控制器
  Future<void> _initialize() async {
    _controller!.addListener(_updateState);
    _updateState();
  }

  // 更新播放状态 - 优化：减少不必要的setState
  void _updateState() {
    if (!mounted) return;
    
    final newValue = _controller!.value;
    // 只在关键状态变化时更新
    if (_latestValue?.isPlaying != newValue.isPlaying ||
        _latestValue?.position != newValue.position ||
        _latestValue?.duration != newValue.duration ||
        _latestValue?.hasError != newValue.hasError ||
        _latestValue?.volume != newValue.volume) {
      setState(() {
        _latestValue = newValue;
      });
    }
  }

  // 构建进度条
  Widget _buildProgressBar() {
    return IAppPlayerMaterialVideoProgressBar(
      _controller,
      _iappPlayerController,
      onDragStart: () {},
      onDragEnd: () {},
      onTapDown: () {},
      colors: IAppPlayerProgressColors(
        playedColor: _controlsConfiguration.progressBarPlayedColor,
        handleColor: _controlsConfiguration.progressBarHandleColor,
        bufferedColor: _controlsConfiguration.progressBarBufferedColor,
        backgroundColor: _controlsConfiguration.progressBarBackgroundColor,
      ),
    );
  }

  @override
  void cancelAndRestartTimer() {
    // 音频控件保持始终可见
  }
}
