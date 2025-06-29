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

/// 音频播放控件 - 复用Material Controls风格
class IAppPlayerAudioControls extends StatefulWidget {
  /// 控件可见性变化回调
  final Function(bool visbility) onControlsVisibilityChanged;

  /// 控件配置
  final IAppPlayerControlsConfiguration controlsConfiguration;

  const IAppPlayerAudioControls({
    Key? key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _IAppPlayerAudioControlsState();
  }
}

class _IAppPlayerAudioControlsState
    extends IAppPlayerControlsState<IAppPlayerAudioControls> {
  /// 复用Material Controls的常量定义
  static const double kProgressBarHeight = 12.0;
  static const double kButtonPadding = 4.0;
  static const double kHorizontalPadding = 8.0;
  static const double kIconSizeBase = 24.0;
  static const double kTextSizeBase = 13.0;
  
  /// 音频控件特有常量
  static const double kAudioControlBarHeight = 60.0;
  static const double kProgressSectionPadding = 16.0;

  /// 最新播放值
  VideoPlayerValue? _latestValue;
  /// 视频播放控制器
  VideoPlayerController? _controller;
  /// 播放器控制器
  IAppPlayerController? _iappPlayerController;

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

  /// 响应式尺寸缓存 - 复用Material Controls的逻辑
  double? _cachedScaleFactor;
  Size? _cachedScreenSize;

  /// 计算响应式尺寸 - 复用Material Controls的实现
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

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return buildLTRDirectionality(_buildMainWidget());
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

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

  Widget _buildMainWidget() {
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }

    // 音频模式简化布局：只有进度条和控制按钮
    return Container(
      color: Colors.transparent, // 保持透明背景，与Material Controls一致
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条区域
          _buildProgressSection(),
          // 控制按钮区域
          _buildControlsSection(),
        ],
      ),
    );
  }

  /// 构建错误提示 - 复用Material Controls的样式
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
              size: _getResponsiveSize(context, 42),
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

  /// 为图标添加阴影效果 - 复用Material Controls的实现
  Widget _wrapIconWithStroke(Widget icon) {
    if (icon is Icon) {
      return Icon(
        icon.icon,
        color: icon.color,
        size: icon.size,
        shadows: const [
          Shadow(
            blurRadius: 3.0,
            color: Colors.black45,
            offset: Offset(0, 1),
          ),
        ],
      );
    }
    return icon;
  }

  /// 为文字添加阴影 - 复用Material Controls
  static const List<Shadow> _textShadows = [
    Shadow(
      blurRadius: 2.0,
      color: Colors.black54,
      offset: Offset(0, 1),
    ),
  ];

  /// 构建进度条区域 - 复用Material Controls的样式
  Widget _buildProgressSection() {
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: kProgressSectionPadding,
        vertical: kHorizontalPadding,
      ),
      child: Column(
        children: [
          // 进度条
          if (_controlsConfiguration.enableProgressBar)
            Container(
              height: kProgressBarHeight,
              child: _buildProgressBar(),
            ),
          // 时间显示
          if (_controlsConfiguration.enableProgressText && !isLive)
            const SizedBox(height: 8),
          if (_controlsConfiguration.enableProgressText && !isLive)
            _buildPosition(),
        ],
      ),
    );
  }

  /// 构建时间显示 - 复用Material Controls的样式
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
        shadows: _textShadows,
      ),
    );
  }

  /// 构建控制按钮区域
  Widget _buildControlsSection() {
    final bool isPlaylist = _iappPlayerController!.isPlaylistMode;
    final bool isLive = _iappPlayerController?.isLiveStream() ?? false;
    
    return Container(
      height: kAudioControlBarHeight,
      padding: EdgeInsets.symmetric(horizontal: kHorizontalPadding),
      child: Row(
        children: [
          // 播放列表模式
          if (isPlaylist) ...[
            // 随机/顺序按钮
            _buildShuffleButton(),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 上一曲
                  _buildPreviousButton(),
                  // 播放/暂停
                  _buildPlayPauseButton(),
                  // 下一曲
                  _buildNextButton(),
                ],
              ),
            ),
            // 播放列表菜单
            _buildPlaylistMenuButton(),
          ] else ...[
            // 单曲模式
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isLive)
                    // 快退10秒
                    _buildSkipBackButton(),
                  // 播放/暂停
                  _buildPlayPauseButton(),
                  if (!isLive)
                    // 快进10秒
                    _buildSkipForwardButton(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建随机/顺序播放按钮 - 使用Material Controls风格
  Widget _buildShuffleButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        _iappPlayerController!.togglePlaylistShuffle();
        setState(() {});
      },
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            _iappPlayerController!.playlistShuffleMode
                ? Icons.shuffle
                : Icons.repeat,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 构建上一曲按钮
  Widget _buildPreviousButton() {
    final bool hasPrevious = _iappPlayerController!.playlistController?.hasPrevious ?? false;
    final bool isEnabled = hasPrevious;
    
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        if (isEnabled) {
          _playPrevious();
        }
      },
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            Icons.skip_previous,
            color: isEnabled 
                ? _controlsConfiguration.iconsColor 
                : _controlsConfiguration.iconsColor.withOpacity(0.3),
            size: _getResponsiveSize(context, kIconSizeBase + 8), // 稍大一点
          ),
        ),
      ),
    );
  }

  /// 构建下一曲按钮
  Widget _buildNextButton() {
    final bool hasNext = _iappPlayerController!.playlistController?.hasNext ?? false;
    final bool isEnabled = hasNext;
    
    return IAppPlayerMaterialClickableWidget(
      onTap: () {
        if (isEnabled) {
          _playNext();
        }
      },
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            Icons.skip_next,
            color: isEnabled 
                ? _controlsConfiguration.iconsColor 
                : _controlsConfiguration.iconsColor.withOpacity(0.3),
            size: _getResponsiveSize(context, kIconSizeBase + 8), // 稍大一点
          ),
        ),
      ),
    );
  }

  /// 构建播放/暂停按钮 - 复用Material Controls的逻辑
  Widget _buildPlayPauseButton() {
    final bool isFinished = isVideoFinished(_latestValue);
    final bool isPlaying = _controller?.value.isPlaying ?? false;
    
    return IAppPlayerMaterialClickableWidget(
      key: const Key("iapp_player_audio_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        padding: EdgeInsets.all(kButtonPadding + 4), // 稍大的padding
        child: _wrapIconWithStroke(
          Icon(
            isFinished
                ? Icons.replay
                : isPlaying
                    ? _controlsConfiguration.pauseIcon
                    : _controlsConfiguration.playIcon,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase + 12), // 更大的播放按钮
          ),
        ),
      ),
    );
  }

  /// 构建快退按钮 - 复用Material Controls风格
  Widget _buildSkipBackButton() {
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

  /// 构建快进按钮 - 复用Material Controls风格
  Widget _buildSkipForwardButton() {
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

  /// 构建播放列表菜单按钮 - 使用Material Controls风格
  Widget _buildPlaylistMenuButton() {
    return IAppPlayerMaterialClickableWidget(
      onTap: _showPlaylistMenu,
      child: Container(
        padding: EdgeInsets.all(kButtonPadding),
        child: _wrapIconWithStroke(
          Icon(
            Icons.queue_music,
            color: _controlsConfiguration.iconsColor,
            size: _getResponsiveSize(context, kIconSizeBase),
          ),
        ),
      ),
    );
  }

  /// 显示播放列表菜单 - 使用Material Controls的模态框风格
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
              topLeft: Radius.circular(24.0),
              topRight: Radius.circular(24.0),
            ),
          ),
          child: _buildPlaylistMenuContent(),
        ),
      ),
    );
  }

  /// 构建播放列表菜单内容 - 使用Material Controls的样式
  Widget _buildPlaylistMenuContent() {
    final playlistController = _iappPlayerController!.playlistController;
    final translations = _iappPlayerController!.translations;
    
    if (playlistController == null) {
      return Container(
        height: 200,
        child: Center(
          child: Text(
            translations.playlistUnavailable,
            style: TextStyle(
              color: _controlsConfiguration.overflowModalTextColor,
            ),
          ),
        ),
      );
    }
    
    final dataSourceList = playlistController.dataSourceList;
    final currentIndex = playlistController.currentDataSourceIndex;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  translations.playlistTitle,
                  style: TextStyle(
                    color: _controlsConfiguration.overflowModalTextColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: _controlsConfiguration.overflowModalTextColor,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 播放列表
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: 16),
              itemCount: dataSourceList.length,
              itemBuilder: (context, index) {
                final dataSource = dataSourceList[index];
                final isCurrentItem = index == currentIndex;
                final title = dataSource.notificationConfiguration?.title ?? 
                              translations.trackItem.replaceAll('{index}', '${index + 1}');
                
                return IAppPlayerMaterialClickableWidget(
                  onTap: () {
                    _playAtIndex(index);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // 播放指示器
                        SizedBox(
                          width: 24,
                          child: isCurrentItem
                              ? Icon(
                                  Icons.play_arrow,
                                  color: _controlsConfiguration.overflowModalTextColor,
                                  size: 20,
                                )
                              : null,
                        ),
                        SizedBox(width: 16),
                        // 曲目标题
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: _controlsConfiguration.overflowModalTextColor,
                              fontSize: 16,
                              fontWeight: isCurrentItem 
                                  ? FontWeight.bold
                                  : FontWeight.normal,
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

  /// 播放上一曲
  void _playPrevious() {
    final playlistController = _iappPlayerController!.playlistController;
    if (playlistController != null) {
      playlistController.playPrevious();
    }
  }

  /// 播放下一曲
  void _playNext() {
    final playlistController = _iappPlayerController!.playlistController;
    if (playlistController != null) {
      playlistController.playNext();
    }
  }

  /// 播放指定索引的曲目
  void _playAtIndex(int index) {
    final playlistController = _iappPlayerController!.playlistController;
    if (playlistController != null) {
      playlistController.setupDataSource(index);
    }
  }

  /// 播放/暂停切换 - 复用Material Controls的逻辑
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

  /// 初始化控制器
  Future<void> _initialize() async {
    _controller!.addListener(_updateState);
    _updateState();
  }

  /// 更新播放状态
  void _updateState() {
    if (mounted) {
      setState(() {
        _latestValue = _controller!.value;
      });
    }
  }

  /// 构建进度条 - 完全复用Material Controls的样式
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
    // 音频控件不需要自动隐藏，保持控件始终可见
  }
}
