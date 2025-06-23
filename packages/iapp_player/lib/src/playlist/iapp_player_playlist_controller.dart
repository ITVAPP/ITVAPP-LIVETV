import 'dart:async';
import 'package:iapp_player/iapp_player.dart';

/// 播放列表控制器，管理播放器播放列表
class IAppPlayerPlaylistController {
  /// 播放列表数据源
  final List<IAppPlayerDataSource> _iappPlayerDataSourceList;

  /// 播放器通用配置
  final IAppPlayerConfiguration iappPlayerConfiguration;

  /// 播放列表配置
  final IAppPlayerPlaylistConfiguration iappPlayerPlaylistConfiguration;

  /// 播放器控制器实例
  IAppPlayerController? _iappPlayerController;

  /// 当前播放数据源索引
  int _currentDataSourceIndex = 0;

  /// 下一视频切换监听订阅
  StreamSubscription? _nextVideoTimeStreamSubscription;

  /// 是否正在切换下一视频
  bool _changingToNextVideo = false;

  /// 构造函数，初始化播放列表数据源及配置
  IAppPlayerPlaylistController(
    this._iappPlayerDataSourceList, {
    this.iappPlayerConfiguration = const IAppPlayerConfiguration(),
    this.iappPlayerPlaylistConfiguration =
        const IAppPlayerPlaylistConfiguration(),
  }) : assert(_iappPlayerDataSourceList.isNotEmpty,
            "播放列表数据源不能为空") {
    _setup();
  }

  /// 初始化控制器及监听器
  void _setup() {
    _iappPlayerController ??= IAppPlayerController(
      iappPlayerConfiguration,
      iappPlayerPlaylistConfiguration: iappPlayerPlaylistConfiguration,
    );

    var initialStartIndex = iappPlayerPlaylistConfiguration.initialStartIndex;
    if (initialStartIndex >= _iappPlayerDataSourceList.length) {
      initialStartIndex = 0;
    }

    _currentDataSourceIndex = initialStartIndex;
    setupDataSource(_currentDataSourceIndex);
    _iappPlayerController!.addEventsListener(_handleEvent);
    _nextVideoTimeStreamSubscription =
        _iappPlayerController!.nextVideoTimeStream.listen((time) {
      if (time != null && time == 0) {
        _onVideoChange();
      }
    });
  }

  /// 设置新数据源列表，暂停当前视频并初始化新列表
  void setupDataSourceList(List<IAppPlayerDataSource> dataSourceList) {
    assert(dataSourceList.isNotEmpty, "播放列表数据源不能为空");
    _iappPlayerController?.pause();
    _iappPlayerDataSourceList.clear();
    _iappPlayerDataSourceList.addAll(dataSourceList);
    _setup();
  }

  /// 处理播放器发出的视频切换信号，设置新数据源
  void _onVideoChange() {
    if (_changingToNextVideo) {
      return;
    }
    final int nextDataSourceId = _getNextDataSourceIndex();
    if (nextDataSourceId == -1) {
      return;
    }
    if (_iappPlayerController!.isFullScreen) {
      _iappPlayerController!.exitFullScreen();
    }
    _changingToNextVideo = true;
    setupDataSource(nextDataSourceId);

    _changingToNextVideo = false;
  }

  /// 处理播放器事件，控制下一视频计时器启动
  void _handleEvent(IAppPlayerEvent iappPlayerEvent) {
    if (iappPlayerEvent.iappPlayerEventType ==
        IAppPlayerEventType.finished) {
      if (_getNextDataSourceIndex() != -1) {
        _iappPlayerController!.startNextVideoTimer();
      }
    }
  }

  /// 根据索引设置数据源，索引需合法
  void setupDataSource(int index) {
    assert(
        index >= 0 && index < _iappPlayerDataSourceList.length,
        "索引需大于等于0且小于数据源列表长度");
    if (index < _dataSourceLength) {
      _currentDataSourceIndex = index;
      _iappPlayerController!
          .setupDataSource(_iappPlayerDataSourceList[index]);
    }
  }

  /// 获取下一数据源索引，支持循环播放
  int _getNextDataSourceIndex() {
    final currentIndex = _currentDataSourceIndex;
    if (currentIndex + 1 < _dataSourceLength) {
      return currentIndex + 1;
    } else {
      if (iappPlayerPlaylistConfiguration.loopVideos) {
        return 0;
      } else {
        return -1;
      }
    }
  }

  /// 获取当前播放数据源索引
  int get currentDataSourceIndex => _currentDataSourceIndex;

  /// 获取数据源列表长度
  int get _dataSourceLength => _iappPlayerDataSourceList.length;

  /// 获取播放器控制器实例
  IAppPlayerController? get iappPlayerController => _iappPlayerController;

  /// 清理控制器资源
  void dispose() {
    _nextVideoTimeStreamSubscription?.cancel();
  }
}
