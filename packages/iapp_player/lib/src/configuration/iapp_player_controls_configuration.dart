import 'package:iapp_player/iapp_player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// IApp Player控件UI配置，定义颜色、图标及行为，仅用于应用内播放器
class IAppPlayerControlsConfiguration {
  /// 控件栏背景色，默认为黑色半透明
  final Color controlBarColor;

  /// 文本颜色，默认为白色
  final Color textColor;

  /// 图标颜色，默认为白色
  final Color iconsColor;

  /// 播放图标，默认为箭头图标
  final IconData playIcon;

  /// 暂停图标，默认为暂停图标
  final IconData pauseIcon;

  /// 静音图标，默认为音量开启图标
  final IconData muteIcon;

  /// 取消静音图标，默认为音量关闭图标
  final IconData unMuteIcon;

  /// 进入全屏图标，默认为全屏图标
  final IconData fullscreenEnableIcon;

  /// 退出全屏图标，默认为退出全屏图标
  final IconData fullscreenDisableIcon;

  /// Cupertino风格后退图标，默认为15秒后退
  final IconData skipBackIcon;

  /// Cupertino风格快进图标，默认为15秒快进
  final IconData skipForwardIcon;

  /// 是否启用全屏功能，默认为true
  final bool enableFullscreen;

  /// 是否启用静音功能，默认为true
  final bool enableMute;

  /// 是否显示进度文本，默认为true
  final bool enableProgressText;

  /// 是否显示进度条，默认为true
  final bool enableProgressBar;

  /// 是否允许拖动进度条，默认为true
  final bool enableProgressBarDrag;

  /// 是否启用播放/暂停按钮，默认为true
  final bool enablePlayPause;

  /// 是否启用快进/后退功能，默认为true
  final bool enableSkips;

  /// 进度条已播放部分颜色，默认为白色
  final Color progressBarPlayedColor;

  /// 进度条拖动点颜色，默认为白色
  final Color progressBarHandleColor;

  /// 进度条缓冲部分颜色，默认为白色半透明
  final Color progressBarBufferedColor;

  /// 进度条背景色，默认为白色稍透明
  final Color progressBarBackgroundColor;

  /// 控件自动隐藏时间，默认为300毫秒
  final Duration controlsHideTime;

  /// 自定义控件构造器，接收控制器及可见性变化回调
  final Widget Function(IAppPlayerController controller,
      Function(bool) onPlayerVisibilityChanged)? customControlsBuilder;

  /// 播放器主题配置
  final IAppPlayerTheme? playerTheme;

  /// 是否显示控件，默认为true
  final bool showControls;

  /// 初始化时是否显示控件，默认为true
  final bool showControlsOnInitialize;

  /// 控件栏高度，默认为48.0
  final double controlBarHeight;

  /// 直播文本颜色，默认为红色
  final Color liveTextColor;

  /// 是否启用溢出菜单（包含播放速度、字幕、画质等），默认为true
  final bool enableOverflowMenu;

  /// 是否启用播放速度选择，默认为true
  final bool enablePlaybackSpeed;

  /// 是否启用字幕功能，默认为true
  final bool enableSubtitles;

  /// 是否启用画质选择，默认为true
  final bool enableQualities;

  /// 是否启用画中画模式，默认为true
  final bool enablePip;

  /// 是否启用重试功能，默认为true
  final bool enableRetry;

  /// 是否启用音频轨道选择，默认为true
  final bool enableAudioTracks;

  /// 自定义溢出菜单项，默认为空
  final List<IAppPlayerOverflowMenuItem> overflowMenuCustomItems;

  /// 溢出菜单图标，默认为更多图标
  final IconData overflowMenuIcon;

  /// 画中画菜单图标，默认为画中画图标
  final IconData pipMenuIcon;

  /// 播放速度菜单项图标，默认为速度图标
  final IconData playbackSpeedIcon;

  /// 字幕菜单项图标，默认为字幕图标
  final IconData subtitlesIcon;

  /// 画质菜单项图标，默认为高清图标
  final IconData qualitiesIcon;

  /// 音频轨道菜单项图标，默认为音频图标
  final IconData audioTracksIcon;

  /// 溢出菜单图标颜色，默认为黑色
  final Color overflowMenuIconsColor;

  /// 快进时间（毫秒），默认为10000
  final int forwardSkipTimeInMilliseconds;

  /// 后退时间（毫秒），默认为10000
  final int backwardSkipTimeInMilliseconds;

  /// 加载指示器颜色，默认为白色
  final Color loadingColor;

  /// 自定义加载组件，默认为空
  final Widget? loadingWidget;

  /// 无视频帧时的背景色，默认为黑色
  final Color backgroundColor;

  /// 溢出菜单底部模态框颜色，默认为白色
  final Color overflowModalColor;

  /// 溢出菜单底部模态框文本颜色，默认为黑色
  final Color overflowModalTextColor;

  /// 白色主题静态配置，缓存以提升性能
  static const _whiteConfig = IAppPlayerControlsConfiguration(
      controlBarColor: Colors.white,
      textColor: Colors.black,
      iconsColor: Colors.black,
      progressBarPlayedColor: Colors.black,
      progressBarHandleColor: Colors.black,
      progressBarBufferedColor: Colors.black54,
      progressBarBackgroundColor: Colors.white70);

  /// Cupertino风格静态配置，缓存以提升性能
  static const _cupertinoConfig = IAppPlayerControlsConfiguration(
    fullscreenEnableIcon: CupertinoIcons.arrow_up_left_arrow_down_right,
    fullscreenDisableIcon: CupertinoIcons.arrow_down_right_arrow_up_left,
    playIcon: CupertinoIcons.play_arrow_solid,
    pauseIcon: CupertinoIcons.pause_solid,
    skipBackIcon: CupertinoIcons.gobackward_15,
    skipForwardIcon: CupertinoIcons.goforward_15,
  );

  const IAppPlayerControlsConfiguration({
    this.controlBarColor = Colors.black87,
    this.textColor = Colors.white,
    this.iconsColor = Colors.white,
    this.playIcon = Icons.play_arrow_outlined,
    this.pauseIcon = Icons.pause_outlined,
    this.muteIcon = Icons.volume_up_outlined,
    this.unMuteIcon = Icons.volume_off_outlined,
    this.fullscreenEnableIcon = Icons.fullscreen_outlined,
    this.fullscreenDisableIcon = Icons.fullscreen_exit_outlined,
    this.skipBackIcon = Icons.replay_10_outlined,
    this.skipForwardIcon = Icons.forward_10_outlined,
    this.enableFullscreen = true,
    this.enableMute = true,
    this.enableProgressText = true,
    this.enableProgressBar = true,
    this.enableProgressBarDrag = true,
    this.enablePlayPause = true,
    this.enableSkips = true,
    this.enableAudioTracks = true,
    this.progressBarPlayedColor = Colors.white,
    this.progressBarHandleColor = Colors.white,
    this.progressBarBufferedColor = Colors.white70,
    this.progressBarBackgroundColor = Colors.white60,
    this.controlsHideTime = const Duration(milliseconds: 300),
    this.customControlsBuilder,
    this.playerTheme,
    this.showControls = true,
    this.showControlsOnInitialize = true,
    this.controlBarHeight = 48.0,
    this.liveTextColor = Colors.red,
    this.enableOverflowMenu = true,
    this.enablePlaybackSpeed = true,
    this.enableSubtitles = true,
    this.enableQualities = true,
    this.enablePip = true,
    this.enableRetry = true,
    this.overflowMenuCustomItems = const [],
    this.overflowMenuIcon = Icons.more_vert_outlined,
    this.pipMenuIcon = Icons.picture_in_picture_outlined,
    this.playbackSpeedIcon = Icons.shutter_speed_outlined,
    this.qualitiesIcon = Icons.hd_outlined,
    this.subtitlesIcon = Icons.closed_caption_outlined,
    this.audioTracksIcon = Icons.audiotrack_outlined,
    this.overflowMenuIconsColor = Colors.black,
    this.forwardSkipTimeInMilliseconds = 10000,
    this.backwardSkipTimeInMilliseconds = 10000,
    this.loadingColor = Colors.white,
    this.loadingWidget,
    this.backgroundColor = Colors.black,
    this.overflowModalColor = Colors.white,
    this.overflowModalTextColor = Colors.black,
  });

  /// 返回白色主题的缓存静态配置，提升性能
  factory IAppPlayerControlsConfiguration.white() {
    return _whiteConfig;
  }

  /// 返回Cupertino风格的缓存静态配置，提升性能
  factory IAppPlayerControlsConfiguration.cupertino() {
    return _cupertinoConfig;
  }

  /// 根据主题动态生成控件配置，不可缓存
  factory IAppPlayerControlsConfiguration.theme(ThemeData theme) {
    return IAppPlayerControlsConfiguration(
      textColor: theme.textTheme.bodySmall?.color ?? Colors.white,
      iconsColor: theme.buttonTheme.colorScheme?.primary ?? Colors.white,
    );
  }
}
