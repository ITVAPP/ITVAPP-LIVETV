/// 播放列表播放器附加配置
class IAppPlayerPlaylistConfiguration {
  /// 下一视频播放延迟
  final Duration nextVideoDelay;

  /// 是否循环播放视频
  final bool loopVideos;

  /// 播放列表启动时的初始视频索引
  final int initialStartIndex;

  /// 构造函数，初始化播放列表配置
  const IAppPlayerPlaylistConfiguration({
    this.nextVideoDelay = const Duration(milliseconds: 3000),
    this.loopVideos = true,
    this.initialStartIndex = 0,
  });
}
