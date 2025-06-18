/// 播放状态配置
enum BetterPlayerEventType {
  initialized,
  play,
  pause,
  seekTo,
  openFullscreen,
  hideFullscreen,
  setVolume,
  progress,
  finished,
  exception,
  controlsVisible,
  controlsHiddenStart,
  controlsHiddenEnd,
  setSpeed,
  changedSubtitles,
  changedTrack,
  changedPlayerVisibility,
  changedResolution,
  pipStart,
  pipStop,
  setupDataSource,
  bufferingStart,
  bufferingUpdate,
  bufferingEnd,
  changedPlaylistItem,
}

/// 解码器类型配置
enum BetterPlayerDecoderType {
  /// 自动选择（默认）
  auto,

  /// 硬件解码优先
  hardwareFirst,

  /// 软件解码优先
  softwareFirst,
}
