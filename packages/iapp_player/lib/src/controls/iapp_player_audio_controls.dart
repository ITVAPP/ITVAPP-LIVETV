import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/controls/iapp_player_material_progress_bar.dart';
import 'package:iapp_player/src/controls/iapp_player_progress_colors.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/video_player/video_player.dart';

/// 音频模式专用控制条
class IAppPlayerAudioControls extends StatefulWidget {
  final IAppPlayerController controller;
  final IAppPlayerControlsConfiguration controlsConfiguration;
  
  const IAppPlayerAudioControls({
    Key? key,
    required this.controller,
    required this.controlsConfiguration,
  }) : super(key: key);
  
  @override
  State<IAppPlayerAudioControls> createState() => _IAppPlayerAudioControlsState();
}

class _IAppPlayerAudioControlsState extends State<IAppPlayerAudioControls> {
  VideoPlayerController? get _videoController => widget.controller.videoPlayerController;
  IAppPlayerControlsConfiguration get _config => widget.controlsConfiguration;
  
  VideoPlayerValue? _latestValue;
  double? _latestVolume;
  late VoidCallback _listener;
  
  @override
  void initState() {
    super.initState();
    _listener = () {
      if (!mounted) return;
      setState(() {
        _latestValue = _videoController?.value;
      });
    };
    _videoController?.addListener(_listener);
    _latestValue = _videoController?.value;
  }
  
  @override
  void dispose() {
    _videoController?.removeListener(_listener);
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // 固定高度80px的音频控制条
    return Container(
      width: double.infinity,
      height: 80.0,
      color: _config.controlBarColor,
      child: Column(
        children: [
          // 进度条（如果启用且非直播）
          if (_config.enableProgressBar && !widget.controller.isLiveStream())
            Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: IAppPlayerMaterialVideoProgressBar(
                  _videoController,
                  widget.controller,
                  colors: IAppPlayerProgressColors(
                    playedColor: _config.progressBarPlayedColor,
                    handleColor: _config.progressBarHandleColor,
                    bufferedColor: _config.progressBarBufferedColor,
                    backgroundColor: _config.progressBarBackgroundColor,
                  ),
                ),
              ),
            ),
          
          // 控制按钮行
          Expanded(
            child: Row(
              children: [
                // 播放/暂停按钮
                if (_config.enablePlayPause)
                  IconButton(
                    icon: Icon(
                      _isVideoFinished() 
                          ? Icons.replay
                          : (_latestValue?.isPlaying ?? false) 
                              ? _config.pauseIcon 
                              : _config.playIcon,
                      color: _config.iconsColor,
                    ),
                    onPressed: _onPlayPause,
                  ),
                
                // 快退按钮
                if (_config.enableSkips && !widget.controller.isLiveStream())
                  IconButton(
                    icon: Icon(
                      _config.skipBackIcon,
                      color: _config.iconsColor,
                      size: 20,
                    ),
                    onPressed: _skipBack,
                  ),
                
                // 快进按钮  
                if (_config.enableSkips && !widget.controller.isLiveStream())
                  IconButton(
                    icon: Icon(
                      _config.skipForwardIcon,
                      color: _config.iconsColor,
                      size: 20,
                    ),
                    onPressed: _skipForward,
                  ),
                
                // 时间显示或直播标识
                if (widget.controller.isLiveStream())
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _config.liveTextColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.controller.translations.controlsLive,
                      style: TextStyle(
                        color: _config.liveTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (_config.enableProgressText)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${IAppPlayerUtils.formatDuration(_latestValue?.position ?? Duration.zero)} / '
                      '${IAppPlayerUtils.formatDuration(_latestValue?.duration ?? Duration.zero)}',
                      style: TextStyle(
                        color: _config.textColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                
                const Spacer(),
                
                // 静音按钮
                if (_config.enableMute)
                  IconButton(
                    icon: Icon(
                      (_latestValue?.volume ?? 1.0) == 0 
                          ? _config.unMuteIcon 
                          : _config.muteIcon,
                      color: _config.iconsColor,
                      size: 20,
                    ),
                    onPressed: _toggleMute,
                  ),
                
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _onPlayPause() {
    if (_isVideoFinished()) {
      widget.controller.seekTo(Duration.zero);
    }
    if (_latestValue?.isPlaying ?? false) {
      widget.controller.pause();
    } else {
      widget.controller.play();
    }
  }
  
  void _skipBack() {
    final currentPosition = _latestValue?.position ?? Duration.zero;
    final skipDuration = Duration(
      milliseconds: _config.backwardSkipTimeInMilliseconds,
    );
    final newPosition = currentPosition - skipDuration;
    widget.controller.seekTo(
      newPosition < Duration.zero ? Duration.zero : newPosition,
    );
  }
  
  void _skipForward() {
    final currentPosition = _latestValue?.position ?? Duration.zero;
    final duration = _latestValue?.duration ?? Duration.zero;
    final skipDuration = Duration(
      milliseconds: _config.forwardSkipTimeInMilliseconds,
    );
    final newPosition = currentPosition + skipDuration;
    widget.controller.seekTo(
      newPosition > duration ? duration : newPosition,
    );
  }
  
  void _toggleMute() {
    if ((_latestValue?.volume ?? 1.0) == 0) {
      widget.controller.setVolume(_latestVolume ?? 0.5);
    } else {
      _latestVolume = _latestValue?.volume;
      widget.controller.setVolume(0.0);
    }
  }
  
  bool _isVideoFinished() {
    return _latestValue?.position != null &&
        _latestValue?.duration != null &&
        _latestValue!.position >= _latestValue!.duration!;
  }
}
