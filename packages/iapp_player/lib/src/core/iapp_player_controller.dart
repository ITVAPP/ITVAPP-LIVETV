import 'dart:async';
import 'dart:io';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/configuration/iapp_player_controller_event.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/subtitles/iapp_player_subtitle.dart';
import 'package:iapp_player/src/subtitles/iapp_player_subtitles_factory.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:iapp_player/src/video_player/video_player_platform_interface.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

///Class used to control overall Better Player behavior. Main class to change
///state of Better Player.
class IAppPlayerController {
  static const String _durationParameter = "duration";
  static const String _progressParameter = "progress";
  static const String _bufferedParameter = "buffered";
  static const String _volumeParameter = "volume";
  static const String _speedParameter = "speed";
  static const String _dataSourceParameter = "dataSource";
  static const String _authorizationHeader = "Authorization";

  ///General configuration used in controller instance.
  final IAppPlayerConfiguration iappPlayerConfiguration;

  ///Playlist configuration used in controller instance.
  final IAppPlayerPlaylistConfiguration? iappPlayerPlaylistConfiguration;

  ///List of event listeners, which listen to events.
  final List<Function(IAppPlayerEvent)?> _eventListeners = [];

  ///List of files to delete once player disposes.
  final List<File> _tempFiles = [];

  ///Stream controller which emits stream when control visibility changes.
  final StreamController<bool> _controlsVisibilityStreamController =
      StreamController.broadcast();

  ///Instance of video player controller which is adapter used to communicate
  ///between flutter high level code and lower level native code.
  VideoPlayerController? videoPlayerController;

  ///Controls configuration
  late IAppPlayerControlsConfiguration _iappPlayerControlsConfiguration;

  ///Controls configuration
  IAppPlayerControlsConfiguration get iappPlayerControlsConfiguration =>
      _iappPlayerControlsConfiguration;

  ///Expose all active eventListeners
  List<Function(IAppPlayerEvent)?> get eventListeners =>
      _eventListeners.sublist(1);

  /// Defines a event listener where video player events will be send.
  Function(IAppPlayerEvent)? get eventListener =>
      iappPlayerConfiguration.eventListener;

  ///Flag used to store full screen mode state.
  bool _isFullScreen = false;

  ///Flag used to store full screen mode state.
  bool get isFullScreen => _isFullScreen;

  ///Time when last progress event was sent
  int _lastPositionSelection = 0;

  ///Currently used data source in player.
  IAppPlayerDataSource? _iappPlayerDataSource;

  ///Currently used data source in player.
  IAppPlayerDataSource? get iappPlayerDataSource => _iappPlayerDataSource;

  ///List of IAppPlayerSubtitlesSources.
  final List<IAppPlayerSubtitlesSource> _iappPlayerSubtitlesSourceList = [];

  ///List of IAppPlayerSubtitlesSources.
  List<IAppPlayerSubtitlesSource> get iappPlayerSubtitlesSourceList =>
      _iappPlayerSubtitlesSourceList;
  IAppPlayerSubtitlesSource? _iappPlayerSubtitlesSource;

  ///Currently used subtitles source.
  IAppPlayerSubtitlesSource? get iappPlayerSubtitlesSource =>
      _iappPlayerSubtitlesSource;

  ///Subtitles lines for current data source.
  List<IAppPlayerSubtitle> subtitlesLines = [];

  ///List of tracks available for current data source. Used only for HLS / DASH.
  List<IAppPlayerAsmsTrack> _iappPlayerAsmsTracks = [];

  ///List of tracks available for current data source. Used only for HLS / DASH.
  List<IAppPlayerAsmsTrack> get iappPlayerAsmsTracks =>
      _iappPlayerAsmsTracks;

  ///Currently selected player track. Used only for HLS / DASH.
  IAppPlayerAsmsTrack? _iappPlayerAsmsTrack;

  ///Currently selected player track. Used only for HLS / DASH.
  IAppPlayerAsmsTrack? get iappPlayerAsmsTrack => _iappPlayerAsmsTrack;

  ///Timer for next video. Used in playlist.
  Timer? _nextVideoTimer;

  ///Time for next video.
  int? _nextVideoTime;

  ///Stream controller which emits next video time.
  final StreamController<int?> _nextVideoTimeStreamController =
      StreamController.broadcast();

  Stream<int?> get nextVideoTimeStream => _nextVideoTimeStreamController.stream;

  ///Has player been disposed.
  bool _disposed = false;

  ///Was player playing before automatic pause.
  bool? _wasPlayingBeforePause;

  ///Currently used translations
  IAppPlayerTranslations translations = IAppPlayerTranslations();

  ///Has current data source started
  bool _hasCurrentDataSourceStarted = false;

  ///Has current data source initialized
  bool _hasCurrentDataSourceInitialized = false;

  ///Stream which sends flag whenever visibility of controls changes
  Stream<bool> get controlsVisibilityStream =>
      _controlsVisibilityStreamController.stream;

  ///Current app lifecycle state.
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  ///Flag which determines if controls (UI interface) is shown. When false,
  ///UI won't be shown (show only player surface).
  bool _controlsEnabled = true;

  ///Flag which determines if controls (UI interface) is shown. When false,
  ///UI won't be shown (show only player surface).
  bool get controlsEnabled => _controlsEnabled;

  ///Overridden aspect ratio which will be used instead of aspect ratio passed
  ///in configuration.
  double? _overriddenAspectRatio;

  ///Overridden fit which will be used instead of fit passed in configuration.
  BoxFit? _overriddenFit;

  ///Was Picture in Picture opened.
  bool _wasInPipMode = false;

  ///Was player in fullscreen before Picture in Picture opened.
  bool _wasInFullScreenBeforePiP = false;

  ///Was controls enabled before Picture in Picture opened.
  bool _wasControlsEnabledBeforePiP = false;

  ///GlobalKey of the IAppPlayer widget
  GlobalKey? _iappPlayerGlobalKey;

  ///Getter of the GlobalKey
  GlobalKey? get iappPlayerGlobalKey => _iappPlayerGlobalKey;

  ///StreamSubscription for VideoEvent listener
  StreamSubscription<VideoEvent>? _videoEventStreamSubscription;

  ///Are controls always visible
  bool _controlsAlwaysVisible = false;

  ///Are controls always visible
  bool get controlsAlwaysVisible => _controlsAlwaysVisible;

  ///List of all possible audio tracks returned from ASMS stream
  List<IAppPlayerAsmsAudioTrack>? _iappPlayerAsmsAudioTracks;

  ///List of all possible audio tracks returned from ASMS stream
  List<IAppPlayerAsmsAudioTrack>? get iappPlayerAsmsAudioTracks =>
      _iappPlayerAsmsAudioTracks;

  ///Selected ASMS audio track
  IAppPlayerAsmsAudioTrack? _iappPlayerAsmsAudioTrack;

  ///Selected ASMS audio track
  IAppPlayerAsmsAudioTrack? get iappPlayerAsmsAudioTrack =>
      _iappPlayerAsmsAudioTrack;

  ///Selected videoPlayerValue when error occurred.
  VideoPlayerValue? _videoPlayerValueOnError;

  ///Flag which holds information about player visibility
  bool _isPlayerVisible = true;

  final StreamController<IAppPlayerControllerEvent>
      _controllerEventStreamController = StreamController.broadcast();

  ///Stream of internal controller events. Shouldn't be used inside app. For
  ///normal events, use eventListener.
  Stream<IAppPlayerControllerEvent> get controllerEventStream =>
      _controllerEventStreamController.stream;

  ///Flag which determines whether are ASMS segments loading
  bool _asmsSegmentsLoading = false;

  ///List of loaded ASMS segments
  final List<String> _asmsSegmentsLoaded = [];

  ///Currently displayed [IAppPlayerSubtitle].
  IAppPlayerSubtitle? renderedSubtitle;

  IAppPlayerController(
    this.iappPlayerConfiguration, {
    this.iappPlayerPlaylistConfiguration,
    IAppPlayerDataSource? iappPlayerDataSource,
  }) {
    this._iappPlayerControlsConfiguration =
        iappPlayerConfiguration.controlsConfiguration;
    _eventListeners.add(eventListener);
    if (iappPlayerDataSource != null) {
      setupDataSource(iappPlayerDataSource);
    }
  }

  ///Get IAppPlayerController from context. Used in InheritedWidget.
  static IAppPlayerController of(BuildContext context) {
    final betterPLayerControllerProvider = context
        .dependOnInheritedWidgetOfExactType<IAppPlayerControllerProvider>()!;

    return betterPLayerControllerProvider.controller;
  }

  ///Setup new data source in Better Player.
  Future setupDataSource(IAppPlayerDataSource iappPlayerDataSource) async {
    postEvent(IAppPlayerEvent(IAppPlayerEventType.setupDataSource,
        parameters: <String, dynamic>{
          _dataSourceParameter: iappPlayerDataSource,
        }));
    _postControllerEvent(IAppPlayerControllerEvent.setupDataSource);
    _hasCurrentDataSourceStarted = false;
    _hasCurrentDataSourceInitialized = false;
    _iappPlayerDataSource = iappPlayerDataSource;
    _iappPlayerSubtitlesSourceList.clear();

    ///Build videoPlayerController if null
    if (videoPlayerController == null) {
      videoPlayerController = VideoPlayerController(
          bufferingConfiguration:
              iappPlayerDataSource.bufferingConfiguration);
      videoPlayerController?.addListener(_onVideoPlayerChanged);
    }

    ///Clear asms tracks
    iappPlayerAsmsTracks.clear();

    ///Setup subtitles
    final List<IAppPlayerSubtitlesSource>? iappPlayerSubtitlesSourceList =
        iappPlayerDataSource.subtitles;
    if (iappPlayerSubtitlesSourceList != null) {
      _iappPlayerSubtitlesSourceList
          .addAll(iappPlayerDataSource.subtitles!);
    }

    if (_isDataSourceAsms(iappPlayerDataSource)) {
      _setupAsmsDataSource(iappPlayerDataSource).then((dynamic value) {
        _setupSubtitles();
      });
    } else {
      _setupSubtitles();
    }

    ///Process data source
    await _setupDataSource(iappPlayerDataSource);
    setTrack(IAppPlayerAsmsTrack.defaultTrack());
  }

  ///Configure subtitles based on subtitles source.
  void _setupSubtitles() {
    _iappPlayerSubtitlesSourceList.add(
      IAppPlayerSubtitlesSource(type: IAppPlayerSubtitlesSourceType.none),
    );
    final defaultSubtitle = _iappPlayerSubtitlesSourceList
        .firstWhereOrNull((element) => element.selectedByDefault == true);

    ///Setup subtitles (none is default)
    setupSubtitleSource(
        defaultSubtitle ?? _iappPlayerSubtitlesSourceList.last,
        sourceInitialize: true);
  }

  ///Check if given [iappPlayerDataSource] is HLS / DASH-type data source.
  bool _isDataSourceAsms(IAppPlayerDataSource iappPlayerDataSource) =>
      (IAppPlayerAsmsUtils.isDataSourceHls(iappPlayerDataSource.url) ||
          iappPlayerDataSource.videoFormat == IAppPlayerVideoFormat.hls) ||
      (IAppPlayerAsmsUtils.isDataSourceDash(iappPlayerDataSource.url) ||
          iappPlayerDataSource.videoFormat == IAppPlayerVideoFormat.dash);

  ///Configure HLS / DASH data source based on provided data source and configuration.
  ///This method configures tracks, subtitles and audio tracks from given
  ///master playlist.
  Future _setupAsmsDataSource(IAppPlayerDataSource source) async {
    final String? data = await IAppPlayerAsmsUtils.getDataFromUrl(
      iappPlayerDataSource!.url,
      _getHeaders(),
    );
    if (data != null) {
      final IAppPlayerAsmsDataHolder _response =
          await IAppPlayerAsmsUtils.parse(data, iappPlayerDataSource!.url);

      /// Load tracks
      if (_iappPlayerDataSource?.useAsmsTracks == true) {
        _iappPlayerAsmsTracks = _response.tracks ?? [];
      }

      /// Load subtitles
      if (iappPlayerDataSource?.useAsmsSubtitles == true) {
        final List<IAppPlayerAsmsSubtitle> asmsSubtitles =
            _response.subtitles ?? [];
        asmsSubtitles.forEach((IAppPlayerAsmsSubtitle asmsSubtitle) {
          _iappPlayerSubtitlesSourceList.add(
            IAppPlayerSubtitlesSource(
              type: IAppPlayerSubtitlesSourceType.network,
              name: asmsSubtitle.name,
              urls: asmsSubtitle.realUrls,
              asmsIsSegmented: asmsSubtitle.isSegmented,
              asmsSegmentsTime: asmsSubtitle.segmentsTime,
              asmsSegments: asmsSubtitle.segments,
              selectedByDefault: asmsSubtitle.isDefault,
            ),
          );
        });
      }

      ///Load audio tracks
      if (iappPlayerDataSource?.useAsmsAudioTracks == true &&
          _isDataSourceAsms(iappPlayerDataSource!)) {
        _iappPlayerAsmsAudioTracks = _response.audios ?? [];
        if (_iappPlayerAsmsAudioTracks?.isNotEmpty == true) {
          setAudioTrack(_iappPlayerAsmsAudioTracks!.first);
        }
      }
    }
  }

  ///Setup subtitles to be displayed from given subtitle source.
  ///If subtitles source is segmented then don't load videos at start. Videos
  ///will load with just in time policy.
  Future<void> setupSubtitleSource(IAppPlayerSubtitlesSource subtitlesSource,
      {bool sourceInitialize = false}) async {
    _iappPlayerSubtitlesSource = subtitlesSource;
    subtitlesLines.clear();
    _asmsSegmentsLoaded.clear();
    _asmsSegmentsLoading = false;

    if (subtitlesSource.type != IAppPlayerSubtitlesSourceType.none) {
      if (subtitlesSource.asmsIsSegmented == true) {
        return;
      }
      final subtitlesParsed =
          await IAppPlayerSubtitlesFactory.parseSubtitles(subtitlesSource);
      subtitlesLines.addAll(subtitlesParsed);
    }

    _postEvent(IAppPlayerEvent(IAppPlayerEventType.changedSubtitles));
    if (!_disposed && !sourceInitialize) {
      _postControllerEvent(IAppPlayerControllerEvent.changeSubtitles);
    }
  }

  ///Load ASMS subtitles segments for given [position].
  ///Segments are being loaded within range (current video position;endPosition)
  ///where endPosition is based on time segment detected in HLS playlist. If
  ///time segment is not present then 5000 ms will be used. Also time segment
  ///is multiplied by 5 to increase window of duration.
  ///Segments are also cached, so same segment won't load twice. Only one
  ///pack of segments can be load at given time.
  Future _loadAsmsSubtitlesSegments(Duration position) async {
    try {
      if (_asmsSegmentsLoading) {
        return;
      }
      _asmsSegmentsLoading = true;
      final IAppPlayerSubtitlesSource? source = _iappPlayerSubtitlesSource;
      final Duration loadDurationEnd = Duration(
          milliseconds: position.inMilliseconds +
              5 * (_iappPlayerSubtitlesSource?.asmsSegmentsTime ?? 5000));

      final segmentsToLoad = _iappPlayerSubtitlesSource?.asmsSegments
          ?.where((segment) {
            return segment.startTime > position &&
                segment.endTime < loadDurationEnd &&
                !_asmsSegmentsLoaded.contains(segment.realUrl);
          })
          .map((segment) => segment.realUrl)
          .toList();

      if (segmentsToLoad != null && segmentsToLoad.isNotEmpty) {
        final subtitlesParsed =
            await IAppPlayerSubtitlesFactory.parseSubtitles(
                IAppPlayerSubtitlesSource(
          type: _iappPlayerSubtitlesSource!.type,
          headers: _iappPlayerSubtitlesSource!.headers,
          urls: segmentsToLoad,
        ));

        ///Additional check if current source of subtitles is same as source
        ///used to start loading subtitles. It can be different when user
        ///changes subtitles and there was already pending load.
        if (source == _iappPlayerSubtitlesSource) {
          subtitlesLines.addAll(subtitlesParsed);
          _asmsSegmentsLoaded.addAll(segmentsToLoad);
        }
      }
      _asmsSegmentsLoading = false;
    } catch (exception) {
      IAppPlayerUtils.log("Load ASMS subtitle segments failed: $exception");
    }
  }

  ///Get VideoFormat from IAppPlayerVideoFormat (adapter method which translates
  ///to video_player supported format).
  VideoFormat? _getVideoFormat(
      IAppPlayerVideoFormat? iappPlayerVideoFormat) {
    if (iappPlayerVideoFormat == null) {
      return null;
    }
    switch (iappPlayerVideoFormat) {
      case IAppPlayerVideoFormat.dash:
        return VideoFormat.dash;
      case IAppPlayerVideoFormat.hls:
        return VideoFormat.hls;
      case IAppPlayerVideoFormat.ss:
        return VideoFormat.ss;
      case IAppPlayerVideoFormat.other:
        return VideoFormat.other;
    }
  }

  ///Internal method which invokes videoPlayerController source setup.
  Future _setupDataSource(IAppPlayerDataSource iappPlayerDataSource) async {
    switch (iappPlayerDataSource.type) {
      case IAppPlayerDataSourceType.network:
        await videoPlayerController?.setNetworkDataSource(
          iappPlayerDataSource.url,
          headers: _getHeaders(),
          useCache:
              _iappPlayerDataSource!.cacheConfiguration?.useCache ?? false,
          maxCacheSize:
              _iappPlayerDataSource!.cacheConfiguration?.maxCacheSize ?? 0,
          maxCacheFileSize:
              _iappPlayerDataSource!.cacheConfiguration?.maxCacheFileSize ??
                  0,
          cacheKey: _iappPlayerDataSource?.cacheConfiguration?.key,
          showNotification: _iappPlayerDataSource
              ?.notificationConfiguration?.showNotification,
          title: _iappPlayerDataSource?.notificationConfiguration?.title,
          author: _iappPlayerDataSource?.notificationConfiguration?.author,
          imageUrl:
              _iappPlayerDataSource?.notificationConfiguration?.imageUrl,
          notificationChannelName: _iappPlayerDataSource
              ?.notificationConfiguration?.notificationChannelName,
          overriddenDuration: _iappPlayerDataSource!.overriddenDuration,
          formatHint: _getVideoFormat(_iappPlayerDataSource!.videoFormat),
          licenseUrl: _iappPlayerDataSource?.drmConfiguration?.licenseUrl,
          certificateUrl:
              _iappPlayerDataSource?.drmConfiguration?.certificateUrl,
          drmHeaders: _iappPlayerDataSource?.drmConfiguration?.headers,
          activityName:
              _iappPlayerDataSource?.notificationConfiguration?.activityName,
          clearKey: _iappPlayerDataSource?.drmConfiguration?.clearKey,
          videoExtension: _iappPlayerDataSource!.videoExtension,
        );

        break;
      case IAppPlayerDataSourceType.file:
        final file = File(iappPlayerDataSource.url);
        if (!file.existsSync()) {
          IAppPlayerUtils.log(
              "File ${file.path} doesn't exists. This may be because "
              "you're acessing file from native path and Flutter doesn't "
              "recognize this path.");
        }

        await videoPlayerController?.setFileDataSource(
            File(iappPlayerDataSource.url),
            showNotification: _iappPlayerDataSource
                ?.notificationConfiguration?.showNotification,
            title: _iappPlayerDataSource?.notificationConfiguration?.title,
            author: _iappPlayerDataSource?.notificationConfiguration?.author,
            imageUrl:
                _iappPlayerDataSource?.notificationConfiguration?.imageUrl,
            notificationChannelName: _iappPlayerDataSource
                ?.notificationConfiguration?.notificationChannelName,
            overriddenDuration: _iappPlayerDataSource!.overriddenDuration,
            activityName: _iappPlayerDataSource
                ?.notificationConfiguration?.activityName,
            clearKey: _iappPlayerDataSource?.drmConfiguration?.clearKey);
        break;
      case IAppPlayerDataSourceType.memory:
        final file = await _createFile(_iappPlayerDataSource!.bytes!,
            extension: _iappPlayerDataSource!.videoExtension);

        if (file.existsSync()) {
          await videoPlayerController?.setFileDataSource(file,
              showNotification: _iappPlayerDataSource
                  ?.notificationConfiguration?.showNotification,
              title: _iappPlayerDataSource?.notificationConfiguration?.title,
              author:
                  _iappPlayerDataSource?.notificationConfiguration?.author,
              imageUrl:
                  _iappPlayerDataSource?.notificationConfiguration?.imageUrl,
              notificationChannelName: _iappPlayerDataSource
                  ?.notificationConfiguration?.notificationChannelName,
              overriddenDuration: _iappPlayerDataSource!.overriddenDuration,
              activityName: _iappPlayerDataSource
                  ?.notificationConfiguration?.activityName,
              clearKey: _iappPlayerDataSource?.drmConfiguration?.clearKey);
          _tempFiles.add(file);
        } else {
          throw ArgumentError("Couldn't create file from memory.");
        }
        break;

      default:
        throw UnimplementedError(
            "${iappPlayerDataSource.type} is not implemented");
    }
    await _initializeVideo();
  }

  ///Create file from provided list of bytes. File will be created in temporary
  ///directory.
  Future<File> _createFile(List<int> bytes,
      {String? extension = "temp"}) async {
    final String dir = (await getTemporaryDirectory()).path;
    final File temp = File(
        '$dir/iapp_player_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await temp.writeAsBytes(bytes);
    return temp;
  }

  ///Initializes video based on configuration. Invoke actions which need to be
  ///run on player start.
  Future _initializeVideo() async {
    setLooping(iappPlayerConfiguration.looping);
    _videoEventStreamSubscription?.cancel();
    _videoEventStreamSubscription = null;

    _videoEventStreamSubscription = videoPlayerController
        ?.videoEventStreamController.stream
        .listen(_handleVideoEvent);

    final fullScreenByDefault = iappPlayerConfiguration.fullScreenByDefault;
    if (iappPlayerConfiguration.autoPlay) {
      if (fullScreenByDefault && !isFullScreen) {
        enterFullScreen();
      }
      if (_isAutomaticPlayPauseHandled()) {
        if (_appLifecycleState == AppLifecycleState.resumed &&
            _isPlayerVisible) {
          await play();
        } else {
          _wasPlayingBeforePause = true;
        }
      } else {
        await play();
      }
    } else {
      if (fullScreenByDefault) {
        enterFullScreen();
      }
    }

    final startAt = iappPlayerConfiguration.startAt;
    if (startAt != null) {
      seekTo(startAt);
    }
  }

  ///Method which is invoked when full screen changes.
  Future<void> _onFullScreenStateChanged() async {
    if (videoPlayerController?.value.isPlaying == true && !_isFullScreen) {
      enterFullScreen();
      videoPlayerController?.removeListener(_onFullScreenStateChanged);
    }
  }

  ///Enables full screen mode in player. This will trigger route change.
  void enterFullScreen() {
    _isFullScreen = true;
    _postControllerEvent(IAppPlayerControllerEvent.openFullscreen);
  }

  ///Disables full screen mode in player. This will trigger route change.
  void exitFullScreen() {
    _isFullScreen = false;
    _postControllerEvent(IAppPlayerControllerEvent.hideFullscreen);
  }

  ///Enables/disables full screen mode based on current fullscreen state.
  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      _postControllerEvent(IAppPlayerControllerEvent.openFullscreen);
    } else {
      _postControllerEvent(IAppPlayerControllerEvent.hideFullscreen);
    }
  }

  ///Start video playback. Play will be triggered only if current lifecycle state
  ///is resumed.
  Future<void> play() async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    if (_appLifecycleState == AppLifecycleState.resumed) {
      await videoPlayerController!.play();
      _hasCurrentDataSourceStarted = true;
      _wasPlayingBeforePause = null;
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.play));
      _postControllerEvent(IAppPlayerControllerEvent.play);
    }
  }

  ///Enables/disables looping (infinity playback) mode.
  Future<void> setLooping(bool looping) async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    await videoPlayerController!.setLooping(looping);
  }

  ///Stop video playback.
  Future<void> pause() async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    await videoPlayerController!.pause();
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.pause));
  }

  ///Move player to specific position/moment of the video.
  Future<void> seekTo(Duration moment) async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }
    if (videoPlayerController?.value.duration == null) {
      throw StateError("The video has not been initialized yet.");
    }

    await videoPlayerController!.seekTo(moment);

    _postEvent(IAppPlayerEvent(IAppPlayerEventType.seekTo,
        parameters: <String, dynamic>{_durationParameter: moment}));

    final Duration? currentDuration = videoPlayerController!.value.duration;
    if (currentDuration == null) {
      return;
    }
    if (moment > currentDuration) {
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.finished));
    } else {
      cancelNextVideoTimer();
    }
  }

  ///Set volume of player. Allows values from 0.0 to 1.0.
  Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) {
      IAppPlayerUtils.log("Volume must be between 0.0 and 1.0");
      throw ArgumentError("Volume must be between 0.0 and 1.0");
    }
    if (videoPlayerController == null) {
      IAppPlayerUtils.log("The data source has not been initialized");
      throw StateError("The data source has not been initialized");
    }
    await videoPlayerController!.setVolume(volume);
    _postEvent(IAppPlayerEvent(
      IAppPlayerEventType.setVolume,
      parameters: <String, dynamic>{_volumeParameter: volume},
    ));
  }

  ///Set playback speed of video. Allows to set speed value between 0 and 2.
  Future<void> setSpeed(double speed) async {
    if (speed <= 0 || speed > 2) {
      IAppPlayerUtils.log("Speed must be between 0 and 2");
      throw ArgumentError("Speed must be between 0 and 2");
    }
    if (videoPlayerController == null) {
      IAppPlayerUtils.log("The data source has not been initialized");
      throw StateError("The data source has not been initialized");
    }
    await videoPlayerController?.setSpeed(speed);
    _postEvent(
      IAppPlayerEvent(
        IAppPlayerEventType.setSpeed,
        parameters: <String, dynamic>{
          _speedParameter: speed,
        },
      ),
    );
  }

  ///Flag which determines whenever player is playing or not.
  bool? isPlaying() {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }
    return videoPlayerController!.value.isPlaying;
  }

  ///Flag which determines whenever player is loading video data or not.
  bool? isBuffering() {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }
    return videoPlayerController!.value.isBuffering;
  }

  ///Show or hide controls manually
  void setControlsVisibility(bool isVisible) {
    _controlsVisibilityStreamController.add(isVisible);
  }

  ///Enable/disable controls (when enabled = false, controls will be always hidden)
  void setControlsEnabled(bool enabled) {
    if (!enabled) {
      _controlsVisibilityStreamController.add(false);
    }
    _controlsEnabled = enabled;
  }

  ///Internal method, used to trigger CONTROLS_VISIBLE or CONTROLS_HIDDEN event
  ///once controls state changed.
  void toggleControlsVisibility(bool isVisible) {
    _postEvent(isVisible
        ? IAppPlayerEvent(IAppPlayerEventType.controlsVisible)
        : IAppPlayerEvent(IAppPlayerEventType.controlsHiddenEnd));
  }

  ///Send player event. Shouldn't be used manually.
  void postEvent(IAppPlayerEvent iappPlayerEvent) {
    _postEvent(iappPlayerEvent);
  }

  ///Send player event to all listeners.
  void _postEvent(IAppPlayerEvent iappPlayerEvent) {
    for (final Function(IAppPlayerEvent)? eventListener in _eventListeners) {
      if (eventListener != null) {
        eventListener(iappPlayerEvent);
      }
    }
  }

  ///Listener used to handle video player changes.
  void _onVideoPlayerChanged() async {
    final VideoPlayerValue currentVideoPlayerValue =
        videoPlayerController?.value ??
            VideoPlayerValue(duration: const Duration());

    if (currentVideoPlayerValue.hasError) {
      _videoPlayerValueOnError ??= currentVideoPlayerValue;
      _postEvent(
        IAppPlayerEvent(
          IAppPlayerEventType.exception,
          parameters: <String, dynamic>{
            "exception": currentVideoPlayerValue.errorDescription
          },
        ),
      );
    }
    if (currentVideoPlayerValue.initialized &&
        !_hasCurrentDataSourceInitialized) {
      _hasCurrentDataSourceInitialized = true;
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.initialized));
    }
    if (currentVideoPlayerValue.isPip) {
      _wasInPipMode = true;
    } else if (_wasInPipMode) {
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.pipStop));
      _wasInPipMode = false;
      if (!_wasInFullScreenBeforePiP) {
        exitFullScreen();
      }
      if (_wasControlsEnabledBeforePiP) {
        setControlsEnabled(true);
      }
      videoPlayerController?.refresh();
    }

    if (_iappPlayerSubtitlesSource?.asmsIsSegmented == true) {
      _loadAsmsSubtitlesSegments(currentVideoPlayerValue.position);
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPositionSelection > 500) {
      _lastPositionSelection = now;
      _postEvent(
        IAppPlayerEvent(
          IAppPlayerEventType.progress,
          parameters: <String, dynamic>{
            _progressParameter: currentVideoPlayerValue.position,
            _durationParameter: currentVideoPlayerValue.duration
          },
        ),
      );
    }
  }

  ///Add event listener which listens to player events.
  void addEventsListener(Function(IAppPlayerEvent) eventListener) {
    _eventListeners.add(eventListener);
  }

  ///Remove event listener. This method should be called once you're disposing
  ///Better Player.
  void removeEventsListener(Function(IAppPlayerEvent) eventListener) {
    _eventListeners.remove(eventListener);
  }

  ///Flag which determines whenever player is playing live data source.
  bool isLiveStream() {
    if (_iappPlayerDataSource == null) {
      IAppPlayerUtils.log("The data source has not been initialized");
      throw StateError("The data source has not been initialized");
    }
    return _iappPlayerDataSource!.liveStream == true;
  }

  ///Flag which determines whenever player data source has been initialized.
  bool? isVideoInitialized() {
    if (videoPlayerController == null) {
      IAppPlayerUtils.log("The data source has not been initialized");
      throw StateError("The data source has not been initialized");
    }
    return videoPlayerController?.value.initialized;
  }

  ///Start timer which will trigger next video. Used in playlist. Do not use
  ///manually.
  void startNextVideoTimer() {
    if (_nextVideoTimer == null) {
      if (iappPlayerPlaylistConfiguration == null) {
        IAppPlayerUtils.log(
            "BettterPlayerPlaylistConifugration has not been set!");
        throw StateError(
            "BettterPlayerPlaylistConifugration has not been set!");
      }

      _nextVideoTime =
          iappPlayerPlaylistConfiguration!.nextVideoDelay.inSeconds;
      _nextVideoTimeStreamController.add(_nextVideoTime);
      if (_nextVideoTime == 0) {
        return;
      }

      _nextVideoTimer =
          Timer.periodic(const Duration(milliseconds: 1000), (_timer) async {
        if (_nextVideoTime == 1) {
          _timer.cancel();
          _nextVideoTimer = null;
        }
        if (_nextVideoTime != null) {
          _nextVideoTime = _nextVideoTime! - 1;
        }
        _nextVideoTimeStreamController.add(_nextVideoTime);
      });
    }
  }

  ///Cancel next video timer. Used in playlist. Do not use manually.
  void cancelNextVideoTimer() {
    _nextVideoTime = null;
    _nextVideoTimeStreamController.add(_nextVideoTime);
    _nextVideoTimer?.cancel();
    _nextVideoTimer = null;
  }

  ///Play next video form playlist. Do not use manually.
  void playNextVideo() {
    _nextVideoTime = 0;
    _nextVideoTimeStreamController.add(_nextVideoTime);
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.changedPlaylistItem));
    cancelNextVideoTimer();
  }

  ///Setup track parameters for currently played video. Can be only used for HLS or DASH
  ///data source.
  void setTrack(IAppPlayerAsmsTrack track) {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.changedTrack,
        parameters: <String, dynamic>{
          "id": track.id,
          "width": track.width,
          "height": track.height,
          "bitrate": track.bitrate,
          "frameRate": track.frameRate,
          "codecs": track.codecs,
          "mimeType": track.mimeType,
        }));

    videoPlayerController!
        .setTrackParameters(track.width, track.height, track.bitrate);
    _iappPlayerAsmsTrack = track;
  }

  ///Check if player can be played/paused automatically
  bool _isAutomaticPlayPauseHandled() {
    return !(_iappPlayerDataSource
                ?.notificationConfiguration?.showNotification ==
            true) &&
        iappPlayerConfiguration.handleLifecycle;
  }

  ///Listener which handles state of player visibility. If player visibility is
  ///below 0.0 then video will be paused. When value is greater than 0, video
  ///will play again. If there's different handler of visibility then it will be
  ///used. If showNotification is set in data source or handleLifecycle is false
  /// then this logic will be ignored.
  void onPlayerVisibilityChanged(double visibilityFraction) async {
    _isPlayerVisible = visibilityFraction > 0;
    if (_disposed) {
      return;
    }
    _postEvent(
        IAppPlayerEvent(IAppPlayerEventType.changedPlayerVisibility));

    if (_isAutomaticPlayPauseHandled()) {
      if (iappPlayerConfiguration.playerVisibilityChangedBehavior != null) {
        iappPlayerConfiguration
            .playerVisibilityChangedBehavior!(visibilityFraction);
      } else {
        if (visibilityFraction == 0) {
          _wasPlayingBeforePause ??= isPlaying();
          pause();
        } else {
          if (_wasPlayingBeforePause == true && !isPlaying()!) {
            play();
          }
        }
      }
    }
  }

  ///Set different resolution (quality) for video
  void setResolution(String url) async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }
    final position = await videoPlayerController!.position;
    final wasPlayingBeforeChange = isPlaying()!;
    pause();
    await setupDataSource(iappPlayerDataSource!.copyWith(url: url));
    seekTo(position!);
    if (wasPlayingBeforeChange) {
      play();
    }
    _postEvent(IAppPlayerEvent(
      IAppPlayerEventType.changedResolution,
      parameters: <String, dynamic>{"url": url},
    ));
  }

  ///Setup translations for given locale. In normal use cases it shouldn't be
  ///called manually.
  void setupTranslations(Locale locale) {
    // ignore: unnecessary_null_comparison
    if (locale != null) {
      final String languageCode = locale.languageCode;
      translations = iappPlayerConfiguration.translations?.firstWhereOrNull(
              (translations) => translations.languageCode == languageCode) ??
          _getDefaultTranslations(locale);
    } else {
      IAppPlayerUtils.log("Locale is null. Couldn't setup translations.");
    }
  }

  ///Setup default translations for selected user locale. These translations
  ///are pre-build in.
  IAppPlayerTranslations _getDefaultTranslations(Locale locale) {
    final String languageCode = locale.languageCode;
    switch (languageCode) {
      case "pl":
        return IAppPlayerTranslations.polish();
      case "zh":
        return IAppPlayerTranslations.chinese();
      case "hi":
        return IAppPlayerTranslations.hindi();
      case "tr":
        return IAppPlayerTranslations.turkish();
      case "vi":
        return IAppPlayerTranslations.vietnamese();
      case "es":
        return IAppPlayerTranslations.spanish();
      default:
        return IAppPlayerTranslations();
    }
  }

  ///Flag which determines whenever current data source has started.
  bool get hasCurrentDataSourceStarted => _hasCurrentDataSourceStarted;

  ///Set current lifecycle state. If state is [AppLifecycleState.resumed] then
  ///player starts playing again. if lifecycle is in [AppLifecycleState.paused]
  ///state, then video playback will stop. If showNotification is set in data
  ///source or handleLifecycle is false then this logic will be ignored.
  void setAppLifecycleState(AppLifecycleState appLifecycleState) {
    if (_isAutomaticPlayPauseHandled()) {
      _appLifecycleState = appLifecycleState;
      if (appLifecycleState == AppLifecycleState.resumed) {
        if (_wasPlayingBeforePause == true && _isPlayerVisible) {
          play();
        }
      }
      if (appLifecycleState == AppLifecycleState.paused) {
        _wasPlayingBeforePause ??= isPlaying();
        pause();
      }
    }
  }

  // ignore: use_setters_to_change_properties
  ///Setup overridden aspect ratio.
  void setOverriddenAspectRatio(double aspectRatio) {
    _overriddenAspectRatio = aspectRatio;
  }

  ///Get aspect ratio used in current video. If aspect ratio is null, then
  ///aspect ratio from IAppPlayerConfiguration will be used. Otherwise
  ///[_overriddenAspectRatio] will be used.
  double? getAspectRatio() {
    return _overriddenAspectRatio ?? iappPlayerConfiguration.aspectRatio;
  }

  // ignore: use_setters_to_change_properties
  ///Setup overridden fit.
  void setOverriddenFit(BoxFit fit) {
    _overriddenFit = fit;
  }

  ///Get fit used in current video. If fit is null, then fit from
  ///IAppPlayerConfiguration will be used. Otherwise [_overriddenFit] will be
  ///used.
  BoxFit getFit() {
    return _overriddenFit ?? iappPlayerConfiguration.fit;
  }

  ///Enable Picture in Picture (PiP) mode. [iappPlayerGlobalKey] is required
  ///to open PiP mode in iOS. When device is not supported, PiP mode won't be
  ///open.
  Future<void>? enablePictureInPicture(GlobalKey iappPlayerGlobalKey) async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    final bool isPipSupported =
        (await videoPlayerController!.isPictureInPictureSupported()) ?? false;

    if (isPipSupported) {
      _wasInFullScreenBeforePiP = _isFullScreen;
      _wasControlsEnabledBeforePiP = _controlsEnabled;
      setControlsEnabled(false);
      if (Platform.isAndroid) {
        _wasInFullScreenBeforePiP = _isFullScreen;
        await videoPlayerController?.enablePictureInPicture(
            left: 0, top: 0, width: 0, height: 0);
        enterFullScreen();
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.pipStart));
        return;
      }
      if (Platform.isIOS) {
        final RenderBox? renderBox = iappPlayerGlobalKey.currentContext!
            .findRenderObject() as RenderBox?;
        if (renderBox == null) {
          IAppPlayerUtils.log(
              "Can't show PiP. RenderBox is null. Did you provide valid global"
              " key?");
          return;
        }
        final Offset position = renderBox.localToGlobal(Offset.zero);
        return videoPlayerController?.enablePictureInPicture(
          left: position.dx,
          top: position.dy,
          width: renderBox.size.width,
          height: renderBox.size.height,
        );
      } else {
        IAppPlayerUtils.log("Unsupported PiP in current platform.");
      }
    } else {
      IAppPlayerUtils.log(
          "Picture in picture is not supported in this device. If you're "
          "using Android, please check if you're using activity v2 "
          "embedding.");
    }
  }

  ///Disable Picture in Picture mode if it's enabled.
  Future<void>? disablePictureInPicture() {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }
    return videoPlayerController!.disablePictureInPicture();
  }

  // ignore: use_setters_to_change_properties
  ///Set GlobalKey of IAppPlayer. Used in PiP methods called from controls.
  void setIAppPlayerGlobalKey(GlobalKey iappPlayerGlobalKey) {
    _iappPlayerGlobalKey = iappPlayerGlobalKey;
  }

  ///Check if picture in picture mode is supported in this device.
  Future<bool> isPictureInPictureSupported() async {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    final bool isPipSupported =
        (await videoPlayerController!.isPictureInPictureSupported()) ?? false;

    return isPipSupported && !_isFullScreen;
  }

  ///Handle VideoEvent when remote controls notification / PiP is shown
  void _handleVideoEvent(VideoEvent event) async {
    switch (event.eventType) {
      case VideoEventType.play:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.play));
        break;
      case VideoEventType.pause:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.pause));
        break;
      case VideoEventType.seek:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.seekTo));
        break;
      case VideoEventType.completed:
        final VideoPlayerValue? videoValue = videoPlayerController?.value;
        _postEvent(
          IAppPlayerEvent(
            IAppPlayerEventType.finished,
            parameters: <String, dynamic>{
              _progressParameter: videoValue?.position,
              _durationParameter: videoValue?.duration
            },
          ),
        );
        break;
      case VideoEventType.bufferingStart:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingStart));
        break;
      case VideoEventType.bufferingUpdate:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingUpdate,
            parameters: <String, dynamic>{
              _bufferedParameter: event.buffered,
            }));
        break;
      case VideoEventType.bufferingEnd:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingEnd));
        break;
      default:

        ///TODO: Handle when needed
        break;
    }
  }

  ///Setup controls always visible mode
  void setControlsAlwaysVisible(bool controlsAlwaysVisible) {
    _controlsAlwaysVisible = controlsAlwaysVisible;
    _controlsVisibilityStreamController.add(controlsAlwaysVisible);
  }

  ///Retry data source if playback failed.
  Future retryDataSource() async {
    await _setupDataSource(_iappPlayerDataSource!);
    if (_videoPlayerValueOnError != null) {
      final position = _videoPlayerValueOnError!.position;
      await seekTo(position);
      await play();
      _videoPlayerValueOnError = null;
    }
  }

  ///Set [audioTrack] in player. Works only for HLS or DASH streams.
  void setAudioTrack(IAppPlayerAsmsAudioTrack audioTrack) {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    if (audioTrack.language == null) {
      _iappPlayerAsmsAudioTrack = null;
      return;
    }

    _iappPlayerAsmsAudioTrack = audioTrack;
    videoPlayerController!.setAudioTrack(audioTrack.label, audioTrack.id);
  }

  ///Enable or disable audio mixing with other sound within device.
  void setMixWithOthers(bool mixWithOthers) {
    if (videoPlayerController == null) {
      throw StateError("The data source has not been initialized");
    }

    videoPlayerController!.setMixWithOthers(mixWithOthers);
  }

  ///Clear all cached data. Video player controller must be initialized to
  ///clear the cache.
  Future<void> clearCache() async {
    return VideoPlayerController.clearCache();
  }

  ///Build headers map that will be used to setup video player controller. Apply
  ///DRM headers if available.
  Map<String, String?> _getHeaders() {
    final headers = iappPlayerDataSource!.headers ?? {};
    if (iappPlayerDataSource?.drmConfiguration?.drmType ==
            IAppPlayerDrmType.token &&
        iappPlayerDataSource?.drmConfiguration?.token != null) {
      headers[_authorizationHeader] =
          iappPlayerDataSource!.drmConfiguration!.token!;
    }
    return headers;
  }

  ///PreCache a video. On Android, the future succeeds when
  ///the requested size, specified in
  ///[IAppPlayerCacheConfiguration.preCacheSize], is downloaded or when the
  ///complete file is downloaded if the file is smaller than the requested size.
  ///On iOS, the whole file will be downloaded, since [maxCacheFileSize] is
  ///currently not supported on iOS. On iOS, the video format must be in this
  ///list: https://github.com/sendyhalim/Swime/blob/master/Sources/MimeType.swift
  Future<void> preCache(IAppPlayerDataSource iappPlayerDataSource) async {
    final cacheConfig = iappPlayerDataSource.cacheConfiguration ??
        const IAppPlayerCacheConfiguration(useCache: true);

    final dataSource = DataSource(
      sourceType: DataSourceType.network,
      uri: iappPlayerDataSource.url,
      useCache: true,
      headers: iappPlayerDataSource.headers,
      maxCacheSize: cacheConfig.maxCacheSize,
      maxCacheFileSize: cacheConfig.maxCacheFileSize,
      cacheKey: cacheConfig.key,
      videoExtension: iappPlayerDataSource.videoExtension,
    );

    return VideoPlayerController.preCache(dataSource, cacheConfig.preCacheSize);
  }

  ///Stop pre cache for given [iappPlayerDataSource]. If there was no pre
  ///cache started for given [iappPlayerDataSource] then it will be ignored.
  Future<void> stopPreCache(
      IAppPlayerDataSource iappPlayerDataSource) async {
    return VideoPlayerController?.stopPreCache(iappPlayerDataSource.url,
        iappPlayerDataSource.cacheConfiguration?.key);
  }

  /// Sets the new [iappPlayerControlsConfiguration] instance in the
  /// controller.
  void setIAppPlayerControlsConfiguration(
      IAppPlayerControlsConfiguration iappPlayerControlsConfiguration) {
    this._iappPlayerControlsConfiguration = iappPlayerControlsConfiguration;
  }

  /// Add controller internal event.
  void _postControllerEvent(IAppPlayerControllerEvent event) {
    if (!_controllerEventStreamController.isClosed) {
      _controllerEventStreamController.add(event);
    }
  }

  ///Dispose IAppPlayerController. When [forceDispose] parameter is true, then
  ///autoDispose parameter will be overridden and controller will be disposed
  ///(if it wasn't disposed before).
  void dispose({bool forceDispose = false}) {
    if (!iappPlayerConfiguration.autoDispose && !forceDispose) {
      return;
    }
    if (!_disposed) {
      if (videoPlayerController != null) {
        pause();
        videoPlayerController!.removeListener(_onFullScreenStateChanged);
        videoPlayerController!.removeListener(_onVideoPlayerChanged);
        videoPlayerController!.dispose();
      }
      _eventListeners.clear();
      _nextVideoTimer?.cancel();
      _nextVideoTimeStreamController.close();
      _controlsVisibilityStreamController.close();
      _videoEventStreamSubscription?.cancel();
      _disposed = true;
      _controllerEventStreamController.close();

      ///Delete files async
      _tempFiles.forEach((file) => file.delete());
    }
  }
}
