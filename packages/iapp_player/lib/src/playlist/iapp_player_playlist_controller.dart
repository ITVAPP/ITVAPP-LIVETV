import 'dart:async';
import 'package:iapp_player/iapp_player.dart';

///Controller used to manage playlist player.
class IAppPlayerPlaylistController {
  ///List of data sources set for playlist.
  final List<IAppPlayerDataSource> _iappPlayerDataSourceList;

  //General configuration of Better Player
  final IAppPlayerConfiguration iappPlayerConfiguration;

  ///Playlist configuration of Better Player
  final IAppPlayerPlaylistConfiguration iappPlayerPlaylistConfiguration;

  ///IAppPlayerController instance
  IAppPlayerController? _iappPlayerController;

  ///Currently playing data source index
  int _currentDataSourceIndex = 0;

  ///Next video change listener subscription
  StreamSubscription? _nextVideoTimeStreamSubscription;

  ///Flag that determines whenever player is changing video
  bool _changingToNextVideo = false;

  IAppPlayerPlaylistController(
    this._iappPlayerDataSourceList, {
    this.iappPlayerConfiguration = const IAppPlayerConfiguration(),
    this.iappPlayerPlaylistConfiguration =
        const IAppPlayerPlaylistConfiguration(),
  }) : assert(_iappPlayerDataSourceList.isNotEmpty,
            "Better Player data source list can't be empty") {
    _setup();
  }

  ///Initialize controller and listeners.
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

  /// Setup new data source list. Pauses currently played video and init new data
  /// source list. Previous data source list will be removed.
  void setupDataSourceList(List<IAppPlayerDataSource> dataSourceList) {
    _iappPlayerController?.pause();
    _iappPlayerDataSourceList.clear();
    _iappPlayerDataSourceList.addAll(dataSourceList);
    _setup();
  }

  ///Handle video change signal from IAppPlayerController. Setup new data
  ///source based on configuration.
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

  ///Handle IAppPlayerEvent from IAppPlayerController. Used to control
  ///startup of next video timer.
  void _handleEvent(IAppPlayerEvent iappPlayerEvent) {
    if (iappPlayerEvent.iappPlayerEventType ==
        IAppPlayerEventType.finished) {
      if (_getNextDataSourceIndex() != -1) {
        _iappPlayerController!.startNextVideoTimer();
      }
    }
  }

  ///Setup data source with index based on [_iappPlayerDataSourceList] provided
  ///in constructor. Index must
  void setupDataSource(int index) {
    assert(
        index >= 0 && index < _iappPlayerDataSourceList.length,
        "Index must be greater than 0 and less than size of data source "
        "list - 1");
    if (index <= _dataSourceLength) {
      _currentDataSourceIndex = index;
      _iappPlayerController!
          .setupDataSource(_iappPlayerDataSourceList[index]);
    }
  }

  ///Get index of next data source. If current index is less than
  ///[_iappPlayerDataSourceList] size then next element will be picked, otherwise
  ///if loops is enabled then first element of [_iappPlayerDataSourceList] will
  ///be picked, otherwise -1 will be returned, indicating that player should
  ///stop changing videos.
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

  ///Get index of currently played source, based on [_iappPlayerDataSourceList]
  int get currentDataSourceIndex => _currentDataSourceIndex;

  ///Get size of [_iappPlayerDataSourceList]
  int get _dataSourceLength => _iappPlayerDataSourceList.length;

  ///Get IAppPlayerController instance
  IAppPlayerController? get iappPlayerController => _iappPlayerController;

  ///Cleanup IAppPlayerPlaylistController
  void dispose() {
    _nextVideoTimeStreamSubscription?.cancel();
  }
}
