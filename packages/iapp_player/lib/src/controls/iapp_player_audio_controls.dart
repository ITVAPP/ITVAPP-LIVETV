import 'package:flutter/material.dart';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/controls/iapp_player_material_progress_bar.dart';
import 'package:iapp_player/src/controls/iapp_player_progress_colors.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/video_player/video_player.dart';

/// 简化版音频控制条 - 复用视频模式逻辑
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
    // 调试日志
    debugPrint('音频控制条构建 - 进度条启用: ${_config.enableProgressBar}, 是直播: ${widget.controller.isLiveStream()}');
    
    // 复用视频模式的布局，但始终显示（无透明度动画）
    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 底部控制栏
          Container(
            // 使用白色背景确保可见性（调试用）
            color: _config.controlBarColor.withOpacity(0.9),
            height: _config.controlBarHeight + 20.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // 控制按钮行
                Expanded(
                  flex: 75,
                  child: Row(
                    children: [
                      // 播放/暂停按钮
                      if (_config.enablePlayPause)
                        _buildPlayPause(),
                      
                      // 时间显示或直播标识
                      if (widget.controller.isLiveStream())
                        _buildLiveWidget()
                      else if (_config.enableProgressText)
                        Expanded(child: _buildPosition()),
                      
                      const Spacer(),
                      
                      // 静音按钮
                      if (_config.enableMute)
                        _buildMuteButton(),
                      
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                
                // 进度条 - 简化条件，音频模式始终显示（除非是直播）
                if (_config.enableProgressBar && !widget.controller.isLiveStream())
                  Expanded(
                    flex: 40,
                    child: Container(
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 构建播放/暂停按钮
  Widget _buildPlayPause() {
    return GestureDetector(
      onTap: _onPlayPause,
      child: Container(
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          _isVideoFinished()
              ? Icons.replay
              : (_latestValue?.isPlaying ?? false)
                  ? _config.pauseIcon
                  : _config.playIcon,
          color: _config.iconsColor,
        ),
      ),
    );
  }
  
  // 构建时间显示
  Widget _buildPosition() {
    final position = _latestValue?.position ?? Duration.zero;
    final duration = _latestValue?.duration ?? Duration.zero;
    
    return Padding(
      padding: _config.enablePlayPause
          ? const EdgeInsets.only(right: 24)
          : const EdgeInsets.symmetric(horizontal: 22),
      child: RichText(
        text: TextSpan(
          text: IAppPlayerUtils.formatDuration(position),
          style: TextStyle(
            fontSize: 10.0,
            color: _config.textColor,
            decoration: TextDecoration.none,
          ),
          children: <TextSpan>[
            TextSpan(
              text: ' / ${IAppPlayerUtils.formatDuration(duration)}',
              style: TextStyle(
                fontSize: 10.0,
                color: _config.textColor,
                decoration: TextDecoration.none,
              ),
            )
          ],
        ),
      ),
    );
  }
  
  // 构建直播标识
  Widget _buildLiveWidget() {
    return Text(
      widget.controller.translations.controlsLive,
      style: TextStyle(
        color: _config.liveTextColor,
        fontWeight: FontWeight.bold,
      ),
    );
  }
  
  // 构建静音按钮
  Widget _buildMuteButton() {
    return GestureDetector(
      onTap: () {
        if ((_latestValue?.volume ?? 1.0) == 0) {
          widget.controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = _latestValue?.volume;
          widget.controller.setVolume(0.0);
        }
      },
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          (_latestValue != null && _latestValue!.volume > 0)
              ? _config.muteIcon
              : _config.unMuteIcon,
          color: _config.iconsColor,
        ),
      ),
    );
  }
  
  // 播放/暂停
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
  
  // 检查视频是否结束
  bool _isVideoFinished() {
    return _latestValue?.position != null &&
        _latestValue?.duration != null &&
        _latestValue!.position >= _latestValue!.duration!;
  }
}
