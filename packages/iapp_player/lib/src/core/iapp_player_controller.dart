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

// 视频播放控制器，管理播放状态、数据源、字幕和事件监听
class IAppPlayerController {
  static const String _durationParameter = "duration";
  static const String _progressParameter = "progress";
  static const String _bufferedParameter = "buffered";
  static const String _volumeParameter = "volume";
  static const String _speedParameter = "speed";
  static const String _dataSourceParameter = "dataSource";
  static const String _authorizationHeader = "Authorization";

  // 通用播放器配置
  final IAppPlayerConfiguration iappPlayerConfiguration;

  // 播放列表配置
  final IAppPlayerPlaylistConfiguration? iappPlayerPlaylistConfiguration;
  
  // 播放列表控制器引用（内部使用）
  IAppPlayerPlaylistController? _playlistController;

  // 事件监听器列表
  final List<Function(IAppPlayerEvent)?> _eventListeners = [];

  // 待删除的临时文件列表
  final List<File> _tempFiles = [];

  // 控件显示状态流控制器
  final StreamController<bool> _controlsVisibilityStreamController =
      StreamController.broadcast();

  // 视频播放器控制器，桥接 Flutter 和原生代码
  VideoPlayerController? videoPlayerController;

  // 控件配置
  late IAppPlayerControlsConfiguration _iappPlayerControlsConfiguration;

  // 获取控件配置
  IAppPlayerControlsConfiguration get iappPlayerControlsConfiguration =>
      _iappPlayerControlsConfiguration;

  // 获取活动的事件监听器
  List<Function(IAppPlayerEvent)?> get eventListeners =>
      _eventListeners.sublist(1);

  // 全局事件监听器
  Function(IAppPlayerEvent)? get eventListener =>
      iappPlayerConfiguration.eventListener;

  // 全屏模式状态
  bool _isFullScreen = false;

  // 获取全屏模式状态
  bool get isFullScreen => _isFullScreen;

  // 上次进度事件触发时间
  int _lastPositionSelection = 0;

  // 当前数据源
  IAppPlayerDataSource? _iappPlayerDataSource;

  // 获取当前数据源
  IAppPlayerDataSource? get iappPlayerDataSource => _iappPlayerDataSource;

  // 字幕源列表
  final List<IAppPlayerSubtitlesSource> _iappPlayerSubtitlesSourceList = [];

  // 获取字幕源列表
  List<IAppPlayerSubtitlesSource> get iappPlayerSubtitlesSourceList =>
      _iappPlayerSubtitlesSourceList;
  IAppPlayerSubtitlesSource? _iappPlayerSubtitlesSource;

  // 当前字幕源
  IAppPlayerSubtitlesSource? get iappPlayerSubtitlesSource =>
      _iappPlayerSubtitlesSource;

  // 当前数据源的字幕行
  List<IAppPlayerSubtitle> subtitlesLines = [];

  // HLS/DASH 轨道列表
  List<IAppPlayerAsmsTrack> _iappPlayerAsmsTracks = [];

  // 获取 HLS/DASH 轨道列表
  List<IAppPlayerAsmsTrack> get iappPlayerAsmsTracks =>
      _iappPlayerAsmsTracks;

  // 当前选择的 HLS/DASH 轨道
  IAppPlayerAsmsTrack? _iappPlayerAsmsTrack;

  // 获取当前选择的 HLS/DASH 轨道
  IAppPlayerAsmsTrack? get iappPlayerAsmsTrack => _iappPlayerAsmsTrack;

  // 播放列表下一视频定时器
  Timer? _nextVideoTimer;
  
  /// 获取播放列表控制器
  IAppPlayerPlaylistController? get playlistController => _playlistController;

  // 下一视频剩余时间
  int? _nextVideoTime;

  // 下一视频时间流控制器
  final StreamController<int?> _nextVideoTimeStreamController =
      StreamController.broadcast();

  // 下一视频时间流
  Stream<int?> get nextVideoTimeStream => _nextVideoTimeStreamController.stream;

  // 播放器是否已销毁
  bool _disposed = false;

  // 获取是否已销毁状态
  bool get isDisposed => _disposed;

  // 暂停前是否在播放
  bool? _wasPlayingBeforePause;

  // 当前翻译配置
  IAppPlayerTranslations translations = IAppPlayerTranslations();

  // 当前数据源是否已开始
  bool _hasCurrentDataSourceStarted = false;

  // 当前数据源是否已初始化
  bool _hasCurrentDataSourceInitialized = false;

  // 控件显示状态流
  Stream<bool> get controlsVisibilityStream =>
      _controlsVisibilityStreamController.stream;

  // 当前应用生命周期状态
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  // 控件是否启用
  bool _controlsEnabled = true;

  // 获取控件启用状态
  bool get controlsEnabled => _controlsEnabled;

  // 覆盖的宽高比
  double? _overriddenAspectRatio;

  // 覆盖的适配模式
  BoxFit? _overriddenFit;

  // 是否处于画中画模式
  bool _wasInPipMode = false;

  // 画中画模式前是否全屏
  bool _wasInFullScreenBeforePiP = false;

  // 画中画模式前控件是否启用
  bool _wasControlsEnabledBeforePiP = false;

  // IAppPlayer 组件全局键
  GlobalKey? _iappPlayerGlobalKey;

  // 获取全局键
  GlobalKey? get iappPlayerGlobalKey => _iappPlayerGlobalKey;

  // 视频事件流订阅
  StreamSubscription<VideoEvent>? _videoEventStreamSubscription;

  // 控件是否始终可见
  bool _controlsAlwaysVisible = false;

  // 获取控件始终可见状态
  bool get controlsAlwaysVisible => _controlsAlwaysVisible;

  // ASMS 音频轨道列表
  List<IAppPlayerAsmsAudioTrack>? _iappPlayerAsmsAudioTracks;

  // 获取 ASMS 音频轨道列表
  List<IAppPlayerAsmsAudioTrack>? get iappPlayerAsmsAudioTracks =>
      _iappPlayerAsmsAudioTracks;

  // 当前选择的 ASMS 音频轨道
  IAppPlayerAsmsAudioTrack? _iappPlayerAsmsAudioTrack;

  // 获取当前选择的 ASMS 音频轨道
  IAppPlayerAsmsAudioTrack? get iappPlayerAsmsAudioTrack =>
      _iappPlayerAsmsAudioTrack;

  // 错误时的视频播放器值
  VideoPlayerValue? _videoPlayerValueOnError;

  // 播放器是否可见
  bool _isPlayerVisible = true;

  // 内部事件流控制器
  final StreamController<IAppPlayerControllerEvent>
      _controllerEventStreamController = StreamController.broadcast();

  // 内部事件流
  Stream<IAppPlayerControllerEvent> get controllerEventStream =>
      _controllerEventStreamController.stream;

  // ASMS 字幕段是否正在加载
  bool _asmsSegmentsLoading = false;

  // 已加载的 ASMS 字幕段 - 优化：使用 Set 替代 List
  final Set<String> _asmsSegmentsLoaded = {};

  // 当前显示的字幕
  IAppPlayerSubtitle? renderedSubtitle;

  // 缓存视频播放器值，减少重复访问
  VideoPlayerValue? _lastVideoPlayerValue;
  
  // 缓冲防抖定时器 - 优化：统一管理
  Timer? _bufferingDebounceTimer;
  // 当前是否在缓冲
  bool _isCurrentlyBuffering = false;
  // 上次缓冲状态变更时间
  DateTime? _lastBufferingChangeTime;
  
  // 缓冲防抖时间（毫秒）
  int _bufferingDebounceMs = 500;
  
  /// 播放列表随机模式状态
  bool _playlistShuffleMode = false;
  
  /// 获取播放列表随机模式状态
  bool get playlistShuffleMode => _playlistShuffleMode;

  // 性能优化：缓存直播流检测结果
  bool? _cachedIsLiveStream;
  
  // 性能优化：待加载字幕段缓存
  List<IAppPlayerAsmsSubtitleSegment>? _pendingSubtitleSegments;
  Duration? _lastSubtitleCheckPosition;

  // 构造函数，初始化配置和数据源
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

  // 从上下文中获取控制器实例
  static IAppPlayerController of(BuildContext context) {
    final betterPLayerControllerProvider = context
        .dependOnInheritedWidgetOfExactType<IAppPlayerControllerProvider>()!;

    return betterPLayerControllerProvider.controller;
  }

  // 设置视频数据源，初始化播放器和字幕
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
    
    // 重置缓冲状态 - 优化：统一清理
    _clearBufferingState();
    
    // 性能优化：清理缓存
    _cachedIsLiveStream = null;
    _pendingSubtitleSegments = null;
    _lastSubtitleCheckPosition = null;

    // 初始化视频播放器控制器
    if (videoPlayerController == null) {
      videoPlayerController = VideoPlayerController(
          bufferingConfiguration:
              iappPlayerDataSource.bufferingConfiguration);
      videoPlayerController?.addListener(_onVideoPlayerChanged);
    }

    // 清空 ASMS 轨道
    iappPlayerAsmsTracks.clear();

    // 设置字幕
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

    // 处理数据源
    await _setupDataSource(iappPlayerDataSource);
    setTrack(IAppPlayerAsmsTrack.defaultTrack());
  }

  // 配置字幕源，设置默认或无字幕
  void _setupSubtitles() {
    _iappPlayerSubtitlesSourceList.add(
      IAppPlayerSubtitlesSource(type: IAppPlayerSubtitlesSourceType.none),
    );
    final defaultSubtitle = _iappPlayerSubtitlesSourceList
        .firstWhereOrNull((element) => element.selectedByDefault == true);

    // 设置默认字幕或无字幕
    setupSubtitleSource(
        defaultSubtitle ?? _iappPlayerSubtitlesSourceList.last,
        sourceInitialize: true);
  }

  // 检查数据源是否为 HLS/DASH 格式
  bool _isDataSourceAsms(IAppPlayerDataSource iappPlayerDataSource) =>
      (IAppPlayerAsmsUtils.isDataSourceHls(iappPlayerDataSource.url) ||
          iappPlayerDataSource.videoFormat == IAppPlayerVideoFormat.hls) ||
      (IAppPlayerAsmsUtils.isDataSourceDash(iappPlayerDataSource.url) ||
          iappPlayerDataSource.videoFormat == IAppPlayerVideoFormat.dash);

  // 配置 HLS/DASH 数据源，加载轨道、字幕和音频
  Future _setupAsmsDataSource(IAppPlayerDataSource source) async {
    final String? data = await IAppPlayerAsmsUtils.getDataFromUrl(
      iappPlayerDataSource!.url,
      _getHeaders(),
    );
    if (data != null) {
      final IAppPlayerAsmsDataHolder _response =
          await IAppPlayerAsmsUtils.parse(data, iappPlayerDataSource!.url);

      // 加载轨道
      if (_iappPlayerDataSource?.useAsmsTracks == true) {
        _iappPlayerAsmsTracks = _response.tracks ?? [];
      }

      // 加载字幕
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

      // 加载音频轨道
      if (iappPlayerDataSource?.useAsmsAudioTracks == true &&
          _isDataSourceAsms(iappPlayerDataSource!)) {
        _iappPlayerAsmsAudioTracks = _response.audios ?? [];
        if (_iappPlayerAsmsAudioTracks?.isNotEmpty == true) {
          setAudioTrack(_iappPlayerAsmsAudioTracks!.first);
        }
      }
    }
  }

  // 设置字幕源，加载字幕行
  Future<void> setupSubtitleSource(IAppPlayerSubtitlesSource subtitlesSource,
      {bool sourceInitialize = false}) async {
    _iappPlayerSubtitlesSource = subtitlesSource;
    subtitlesLines.clear();
    _asmsSegmentsLoaded.clear();
    _asmsSegmentsLoading = false;
    // 性能优化：清理字幕缓存
    _pendingSubtitleSegments = null;
    _lastSubtitleCheckPosition = null;

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

  // 加载 ASMS 字幕段，基于当前位置和时间窗口 - 性能优化：减少遍历次数
  Future _loadAsmsSubtitlesSegments(Duration position) async {
    try {
      if (_asmsSegmentsLoading) {
        return;
      }
      
      // 性能优化：避免频繁检查相同位置
      if (_lastSubtitleCheckPosition != null) {
        final positionDiff = (position.inMilliseconds - _lastSubtitleCheckPosition!.inMilliseconds).abs();
        if (positionDiff < 1000) { // 1秒内的位置变化不重新检查
          return;
        }
      }
      _lastSubtitleCheckPosition = position;
      
      _asmsSegmentsLoading = true;
      final IAppPlayerSubtitlesSource? source = _iappPlayerSubtitlesSource;
      final Duration loadDurationEnd = Duration(
          milliseconds: position.inMilliseconds +
              5 * (_iappPlayerSubtitlesSource?.asmsSegmentsTime ?? 5000));

      // 性能优化：使用缓存的待加载段列表
      if (_pendingSubtitleSegments == null) {
        _pendingSubtitleSegments = _iappPlayerSubtitlesSource?.asmsSegments
            ?.where((segment) => !_asmsSegmentsLoaded.contains(segment.realUrl))
            .toList() ?? [];
      }
      
      // 过滤出需要加载的段
      final segmentsToLoad = <String>[];
      final segmentsToRemove = <IAppPlayerAsmsSubtitleSegment>[];
      
      for (final segment in _pendingSubtitleSegments!) {
        if (segment.startTime > position && segment.endTime < loadDurationEnd) {
          segmentsToLoad.add(segment.realUrl);
          segmentsToRemove.add(segment);
        }
      }
      
      // 从待加载列表中移除已处理的段
      _pendingSubtitleSegments!.removeWhere((s) => segmentsToRemove.contains(s));

      if (segmentsToLoad.isNotEmpty) {
        final subtitlesParsed =
            await IAppPlayerSubtitlesFactory.parseSubtitles(
                IAppPlayerSubtitlesSource(
          type: _iappPlayerSubtitlesSource!.type,
          headers: _iappPlayerSubtitlesSource!.headers,
          urls: segmentsToLoad,
        ));

        // 验证字幕源一致性
        if (source == _iappPlayerSubtitlesSource) {
          subtitlesLines.addAll(subtitlesParsed);
          _asmsSegmentsLoaded.addAll(segmentsToLoad);
        }
      }
      _asmsSegmentsLoading = false;
    } catch (exception) {
      IAppPlayerUtils.log("加载 ASMS 字幕段失败: $exception");
    }
  }

  // 获取视频格式，适配 video_player 格式
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

  // 设置视频数据源，处理网络、文件或内存数据
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
          preferredDecoderType: _iappPlayerDataSource?.preferredDecoderType,
        );

        break;
      case IAppPlayerDataSourceType.file:
        final file = File(iappPlayerDataSource.url);
        if (!file.existsSync()) {
          IAppPlayerUtils.log(
              "文件 ${file.path} 不存在，可能是使用了原生路径");
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
          throw ArgumentError("无法从内存创建文件");
        }
        break;

      default:
        throw UnimplementedError(
            "${iappPlayerDataSource.type} 未实现");
    }
    await _initializeVideo();
  }

  // 从字节数组创建临时文件
  Future<File> _createFile(List<int> bytes,
      {String? extension = "temp"}) async {
    final String dir = (await getTemporaryDirectory()).path;
    final File temp = File(
        '$dir/iapp_player_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await temp.writeAsBytes(bytes);
    return temp;
  }

  // 初始化视频，设置循环和自动播放
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

  // 处理全屏状态变化
  Future<void> _onFullScreenStateChanged() async {
    if (videoPlayerController?.value.isPlaying == true && !_isFullScreen) {
      enterFullScreen();
      videoPlayerController?.removeListener(_onFullScreenStateChanged);
    }
  }

  // 进入全屏模式
  void enterFullScreen() {
    _isFullScreen = true;
    _postControllerEvent(IAppPlayerControllerEvent.openFullscreen);
  }

  // 退出全屏模式
  void exitFullScreen() {
    _isFullScreen = false;
    _postControllerEvent(IAppPlayerControllerEvent.hideFullscreen);
  }

  // 切换全屏模式
  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      _postControllerEvent(IAppPlayerControllerEvent.openFullscreen);
    } else {
      _postControllerEvent(IAppPlayerControllerEvent.hideFullscreen);
    }
  }

  // 开始播放视频，仅在生命周期恢复时生效
  Future<void> play() async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    if (_appLifecycleState == AppLifecycleState.resumed) {
      await videoPlayerController!.play();
      _hasCurrentDataSourceStarted = true;
      _wasPlayingBeforePause = null;
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.play));
      _postControllerEvent(IAppPlayerControllerEvent.play);
    }
  }

  // 设置视频循环播放
  Future<void> setLooping(bool looping) async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    await videoPlayerController!.setLooping(looping);
  }

  // 暂停视频播放
  Future<void> pause() async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    await videoPlayerController!.pause();
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.pause));
  }

  // 跳转到视频指定位置
  Future<void> seekTo(Duration moment) async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    if (videoPlayerController?.value.duration == null) {
      throw StateError("视频未初始化");
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

  // 设置音量，范围 0.0 到 1.0
  Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) {
      IAppPlayerUtils.log("音量必须在 0.0 到 1.0 之间");
      throw ArgumentError("音量必须在 0.0 到 1.0 之间");
    }
    if (videoPlayerController == null) {
      IAppPlayerUtils.log("数据源未初始化");
      throw StateError("数据源未初始化");
    }
    await videoPlayerController!.setVolume(volume);
    _postEvent(IAppPlayerEvent(
      IAppPlayerEventType.setVolume,
      parameters: <String, dynamic>{_volumeParameter: volume},
    ));
  }

  // 设置播放速度，范围 0 到 2
  Future<void> setSpeed(double speed) async {
    if (speed <= 0 || speed > 2) {
      IAppPlayerUtils.log("速度必须在 0 到 2 之间");
      throw ArgumentError("速度必须在 0 到 2 之间");
    }
    if (videoPlayerController == null) {
      IAppPlayerUtils.log("数据源未初始化");
      throw StateError("数据源未初始化");
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

  // 检查是否正在播放
  bool? isPlaying() {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    return videoPlayerController!.value.isPlaying;
  }

  // 检查是否正在缓冲
  bool? isBuffering() {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    return videoPlayerController!.value.isBuffering;
  }

  // 手动设置控件显示状态
  void setControlsVisibility(bool isVisible) {
    _controlsVisibilityStreamController.add(isVisible);
  }

  // 启用或禁用控件
  void setControlsEnabled(bool enabled) {
    if (!enabled) {
      _controlsVisibilityStreamController.add(false);
    }
    _controlsEnabled = enabled;
  }

  // 触发控件显示或隐藏事件
  void toggleControlsVisibility(bool isVisible) {
    _postEvent(isVisible
        ? IAppPlayerEvent(IAppPlayerEventType.controlsVisible)
        : IAppPlayerEvent(IAppPlayerEventType.controlsHiddenEnd));
  }

  // 发送播放器事件
  void postEvent(IAppPlayerEvent iappPlayerEvent) {
    _postEvent(iappPlayerEvent);
  }

  // 向所有监听器发送事件 - 关键修改：添加 dispose 检查
  void _postEvent(IAppPlayerEvent iappPlayerEvent) {
    // 新增：检查是否已释放，阻止后续事件处理
    if (_disposed) {
      return;
    }
    
    // 处理播放列表随机模式变化事件
    if (iappPlayerEvent.iappPlayerEventType == 
        IAppPlayerEventType.changedPlaylistShuffle) {
      _playlistShuffleMode = iappPlayerEvent.parameters?['shuffleMode'] ?? false;
      // 触发UI更新
      _postControllerEvent(IAppPlayerControllerEvent.changeSubtitles);
    }
    
    for (final Function(IAppPlayerEvent)? eventListener in _eventListeners) {
      if (eventListener != null) {
        eventListener(iappPlayerEvent);
      }
    }
  }
  
  /// 是否在播放列表模式
  bool get isPlaylistMode => iappPlayerPlaylistConfiguration != null;
  
  /// 切换播放列表随机模式
  void togglePlaylistShuffle() {
    if (isPlaylistMode) {
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.togglePlaylistShuffle));
    }
  }

  // 处理视频播放器状态变化 - 优化：添加缓存检查，减少重复处理
  void _onVideoPlayerChanged() async {
    // 新增：检查是否已释放
    if (_disposed) {
      return;
    }
    
    // 缓存当前值，减少重复访问
    final currentValue = videoPlayerController?.value;
    if (currentValue == null) {
      return;
    }

    // 提前返回，避免重复处理相同的状态
    if (_lastVideoPlayerValue != null &&
        currentValue.position == _lastVideoPlayerValue!.position &&
        currentValue.isPlaying == _lastVideoPlayerValue!.isPlaying &&
        currentValue.isBuffering == _lastVideoPlayerValue!.isBuffering &&
        currentValue.hasError == _lastVideoPlayerValue!.hasError) {
      return;
    }

    // 处理错误
    if (currentValue.hasError && _videoPlayerValueOnError == null) {
      _videoPlayerValueOnError = currentValue;
      _postEvent(
        IAppPlayerEvent(
          IAppPlayerEventType.exception,
          parameters: <String, dynamic>{
            "exception": currentValue.errorDescription
          },
        ),
      );
    }

    // 处理初始化事件
    if (currentValue.initialized && !_hasCurrentDataSourceInitialized) {
      _hasCurrentDataSourceInitialized = true;
      _postEvent(IAppPlayerEvent(IAppPlayerEventType.initialized));
    }

    // 处理画中画模式
    if (currentValue.isPip) {
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

    // 加载字幕段
    if (_iappPlayerSubtitlesSource?.asmsIsSegmented == true) {
      _loadAsmsSubtitlesSegments(currentValue.position);
    }

    // 节流进度事件
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPositionSelection > 500) {
      _lastPositionSelection = now;
      _postEvent(
        IAppPlayerEvent(
          IAppPlayerEventType.progress,
          parameters: <String, dynamic>{
            _progressParameter: currentValue.position,
            _durationParameter: currentValue.duration
          },
        ),
      );
    }

    // 更新缓存值
    _lastVideoPlayerValue = currentValue;
  }

  // 添加事件监听器
  void addEventsListener(Function(IAppPlayerEvent) eventListener) {
    _eventListeners.add(eventListener);
  }

  // 移除事件监听器
  void removeEventsListener(Function(IAppPlayerEvent) eventListener) {
    _eventListeners.remove(eventListener);
  }

  // 检查是否为直播数据源 - 性能优化：缓存结果
  bool isLiveStream() {
    if (_iappPlayerDataSource == null) {
      IAppPlayerUtils.log("数据源未初始化");
      throw StateError("数据源未初始化");
    }
    
    // 性能优化：使用缓存结果
    if (_cachedIsLiveStream != null) {
      return _cachedIsLiveStream!;
    }
    
    // 如果已经手动设置了 liveStream，直接返回
    if (_iappPlayerDataSource!.liveStream == true) {
      _cachedIsLiveStream = true;
      return true;
    }
    
    // 自动检测直播流格式
    final url = _iappPlayerDataSource!.url.toLowerCase();
    
    // RTMP 流
    if (url.contains('rtmp://')) {
      _cachedIsLiveStream = true;
      return true;
    }
    
    // M3U8 流（HLS直播）
    if (url.contains('.m3u8')) {
      _cachedIsLiveStream = true;
      return true;
    }
    
    // FLV 流
    if (url.contains('.flv')) {
      _cachedIsLiveStream = true;
      return true;
    }
    
    // 其他直播流协议
    if (url.contains('rtsp://') || 
        url.contains('mms://') || 
        url.contains('rtmps://')) {
      _cachedIsLiveStream = true;
      return true;
    }

    _cachedIsLiveStream = false;
    return false;
  }

  // 检查视频是否已初始化
  bool? isVideoInitialized() {
    if (videoPlayerController == null) {
      IAppPlayerUtils.log("数据源未初始化");
      throw StateError("数据源未初始化");
    }
    return videoPlayerController?.value.initialized;
  }

  // 启动播放列表下一视频定时器
  void startNextVideoTimer() {
    if (_nextVideoTimer == null) {
      if (iappPlayerPlaylistConfiguration == null) {
        IAppPlayerUtils.log("播放列表配置未设置");
        throw StateError("播放列表配置未设置");
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

  // 取消播放列表下一视频定时器
  void cancelNextVideoTimer() {
    _nextVideoTime = null;
    _nextVideoTimeStreamController.add(_nextVideoTime);
    _nextVideoTimer?.cancel();
    _nextVideoTimer = null;
  }

  // 播放播放列表下一视频
  void playNextVideo() {
    _nextVideoTime = 0;
    _nextVideoTimeStreamController.add(_nextVideoTime);
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.changedPlaylistItem));
    cancelNextVideoTimer();
  }

  // 选择 HLS/DASH 轨道，设置分辨率参数
  void setTrack(IAppPlayerAsmsTrack track) {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
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

  // 检查是否支持自动播放/暂停
  bool _isAutomaticPlayPauseHandled() {
    return !(_iappPlayerDataSource
                ?.notificationConfiguration?.showNotification ==
            true) &&
        iappPlayerConfiguration.handleLifecycle;
  }

  // 处理播放器可见性变化，控制自动播放/暂停 - 关键修改：添加 dispose 检查
  void onPlayerVisibilityChanged(double visibilityFraction) async {
    _isPlayerVisible = visibilityFraction > 0;
    // 新增：检查是否已释放
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

  // 设置视频分辨率
  void setResolution(String url) async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
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

  // 设置指定语言的翻译
  void setupTranslations(Locale locale) {
    // ignore: unnecessary_null_comparison
    if (locale != null) {
      final String languageCode = locale.languageCode;
      translations = iappPlayerConfiguration.translations?.firstWhereOrNull(
              (translations) => translations.languageCode == languageCode) ??
          _getDefaultTranslations(locale);
    } else {
      IAppPlayerUtils.log("语言环境为空，无法设置翻译");
    }
  }

  // 获取默认翻译配置
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

  // 获取当前数据源是否已开始
  bool get hasCurrentDataSourceStarted => _hasCurrentDataSourceStarted;

  // 设置应用生命周期状态，控制播放/暂停
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
  // 设置覆盖的宽高比
  void setOverriddenAspectRatio(double aspectRatio) {
    _overriddenAspectRatio = aspectRatio;
  }

  // 获取当前宽高比
  double? getAspectRatio() {
    return _overriddenAspectRatio ?? iappPlayerConfiguration.aspectRatio;
  }

  // ignore: use_setters_to_change_properties
  // 设置覆盖的适配模式
  void setOverriddenFit(BoxFit fit) {
    _overriddenFit = fit;
  }

  // 获取当前适配模式
  BoxFit getFit() {
    return _overriddenFit ?? iappPlayerConfiguration.fit;
  }

  // 启用画中画模式
  Future<void>? enablePictureInPicture(GlobalKey iappPlayerGlobalKey) async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
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
              "无法显示画中画，RenderBox 为空，请提供有效的全局键");
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
        IAppPlayerUtils.log("当前平台不支持画中画");
      }
    } else {
      IAppPlayerUtils.log(
          "设备不支持画中画，Android 请检查是否使用活动 v2 嵌入");
    }
  }

  // 禁用画中画模式
  Future<void>? disablePictureInPicture() {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    return videoPlayerController!.disablePictureInPicture();
  }

  // ignore: use_setters_to_change_properties
  // 设置 IAppPlayer 全局键
  void setIAppPlayerGlobalKey(GlobalKey iappPlayerGlobalKey) {
    _iappPlayerGlobalKey = iappPlayerGlobalKey;
  }

  // 检查是否支持画中画模式
  Future<bool> isPictureInPictureSupported() async {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    final bool isPipSupported =
        (await videoPlayerController!.isPictureInPictureSupported()) ?? false;

    return isPipSupported && !_isFullScreen;
  }

  // 处理视频事件
  void _handleVideoEvent(VideoEvent event) async {
    // 检查是否已释放
    if (_disposed) {
      return;
    }
    
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
        _handleBufferingStart();
        break;
      case VideoEventType.bufferingUpdate:
        _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingUpdate,
            parameters: <String, dynamic>{
              _bufferedParameter: event.buffered,
            }));
        break;
      case VideoEventType.bufferingEnd:
        _handleBufferingEnd();
        break;
      default:
        break;
    }
  }
  
  // 处理缓冲开始事件，防抖优化 - 优化：统一定时器管理
  void _handleBufferingStart() {
    // 新增：检查是否已释放
    if (_disposed) {
      return;
    }
    
    final now = DateTime.now();
    
    // 如果已经在缓冲中，忽略
    if (_isCurrentlyBuffering) {
      return;
    }
    
    // 取消待处理的定时器
    _bufferingDebounceTimer?.cancel();
    
    // 检查是否刚刚结束缓冲
    if (_lastBufferingChangeTime != null) {
      final timeSinceLastChange = now.difference(_lastBufferingChangeTime!).inMilliseconds;
      if (timeSinceLastChange < _bufferingDebounceMs) {
        // 设置延迟处理
        _bufferingDebounceTimer = Timer(
          Duration(milliseconds: _bufferingDebounceMs - timeSinceLastChange),
          () {
            if (!_disposed && !_isCurrentlyBuffering) {
              _isCurrentlyBuffering = true;
              _lastBufferingChangeTime = DateTime.now();
              _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingStart));
            }
          }
        );
        return;
      }
    }
    
    // 立即开始缓冲
    _isCurrentlyBuffering = true;
    _lastBufferingChangeTime = now;
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingStart));
  }
  
  // 处理缓冲结束事件，防抖优化 - 优化：统一定时器管理
  void _handleBufferingEnd() {
    // 新增：检查是否已释放
    if (_disposed) {
      return;
    }
    
    final now = DateTime.now();
    
    // 如果不在缓冲中，忽略
    if (!_isCurrentlyBuffering) {
      return;
    }
    
    // 取消待处理的定时器
    _bufferingDebounceTimer?.cancel();
    
    // 检查是否刚刚开始缓冲
    if (_lastBufferingChangeTime != null) {
      final timeSinceLastChange = now.difference(_lastBufferingChangeTime!).inMilliseconds;
      if (timeSinceLastChange < _bufferingDebounceMs) {
        // 设置延迟处理
        _bufferingDebounceTimer = Timer(
          Duration(milliseconds: _bufferingDebounceMs - timeSinceLastChange),
          () {
            if (!_disposed && _isCurrentlyBuffering) {
              _isCurrentlyBuffering = false;
              _lastBufferingChangeTime = DateTime.now();
              _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingEnd));
            }
          }
        );
        return;
      }
    }
    
    // 立即结束缓冲
    _isCurrentlyBuffering = false;
    _lastBufferingChangeTime = now;
    _postEvent(IAppPlayerEvent(IAppPlayerEventType.bufferingEnd));
  }

  // 设置控件始终可见模式
  void setControlsAlwaysVisible(bool controlsAlwaysVisible) {
    _controlsAlwaysVisible = controlsAlwaysVisible;
    _controlsVisibilityStreamController.add(controlsAlwaysVisible);
  }

  // 重试数据源加载
  Future retryDataSource() async {
    await _setupDataSource(_iappPlayerDataSource!);
    if (_videoPlayerValueOnError != null) {
      final position = _videoPlayerValueOnError!.position;
      await seekTo(position);
      await play();
      _videoPlayerValueOnError = null;
    }
  }

  // 选择 HLS/DASH 音频轨道
  void setAudioTrack(IAppPlayerAsmsAudioTrack audioTrack) {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    if (audioTrack.language == null) {
      _iappPlayerAsmsAudioTrack = null;
      return;
    }

    _iappPlayerAsmsAudioTrack = audioTrack;
    videoPlayerController!.setAudioTrack(audioTrack.label, audioTrack.id);
  }

  // 设置是否与其他音频混音
  void setMixWithOthers(bool mixWithOthers) {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    videoPlayerController!.setMixWithOthers(mixWithOthers);
  }

  // 清除缓存
  Future<void> clearCache() async {
    return VideoPlayerController.clearCache();
  }

  // 构建请求头，包含 DRM 授权
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

  // 预缓存视频数据
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

  // 停止预缓存
  Future<void> stopPreCache(
      IAppPlayerDataSource iappPlayerDataSource) async {
    return VideoPlayerController?.stopPreCache(iappPlayerDataSource.url,
        iappPlayerDataSource.cacheConfiguration?.key);
  }

  // 设置控件配置
  void setIAppPlayerControlsConfiguration(
      IAppPlayerControlsConfiguration iappPlayerControlsConfiguration) {
    this._iappPlayerControlsConfiguration = iappPlayerControlsConfiguration;
  }

  // 发送内部事件 - 关键修改：添加 dispose 检查
  void _postControllerEvent(IAppPlayerControllerEvent event) {
    // 新增：检查是否已释放和流控制器状态
    if (_disposed || _controllerEventStreamController.isClosed) {
      return;
    }
    _controllerEventStreamController.add(event);
  }
  
  // 设置缓冲防抖时间（毫秒）
  void setBufferingDebounceTime(int milliseconds) {
    if (milliseconds < 0) {
      IAppPlayerUtils.log("缓冲防抖时间必须非负");
      return;
    }
    _bufferingDebounceMs = milliseconds;
  }
  
  // 清理缓冲状态 - 新增：统一管理缓冲状态
  void _clearBufferingState() {
    _bufferingDebounceTimer?.cancel();
    _bufferingDebounceTimer = null;
    _isCurrentlyBuffering = false;
    _lastBufferingChangeTime = null;
  }

  // 销毁控制器，清理资源 - 优化：修正释放顺序
  void dispose({bool forceDispose = false}) {
    if (!iappPlayerConfiguration.autoDispose && !forceDispose) {
      return;
    }
    if (!_disposed) {
      // 优化：立即设置标志，阻止后续所有事件和回调
      _disposed = true;
      
      // 立即取消所有异步操作
      _nextVideoTimer?.cancel();
      _nextVideoTimer = null;
      _bufferingDebounceTimer?.cancel();
      _bufferingDebounceTimer = null;
      _videoEventStreamSubscription?.cancel();
      _videoEventStreamSubscription = null;
      
      // 立即清空事件监听器，防止后续回调
      _eventListeners.clear();
      
      // 移除视频播放器监听器
      if (videoPlayerController != null) {
        videoPlayerController!.removeListener(_onFullScreenStateChanged);
        videoPlayerController!.removeListener(_onVideoPlayerChanged);
      }
      
      // 关闭流控制器（先检查状态）
      if (!_controllerEventStreamController.isClosed) {
        _controllerEventStreamController.close();
      }
      if (!_nextVideoTimeStreamController.isClosed) {
        _nextVideoTimeStreamController.close();
      }
      if (!_controlsVisibilityStreamController.isClosed) {
        _controlsVisibilityStreamController.close();
      }
      
      // 暂停并释放视频播放器
      videoPlayerController?.pause();
      videoPlayerController?.dispose();
      videoPlayerController = null;
      
      // 清理缓冲状态
      _clearBufferingState();
      
      // 清理性能优化相关的缓存
      _cachedIsLiveStream = null;
      _pendingSubtitleSegments = null;
      _lastSubtitleCheckPosition = null;

      // 异步删除临时文件（不阻塞）
      for (final file in _tempFiles) {
        file.delete().catchError((error) {
          // 忽略删除错误
        });
      }
      _tempFiles.clear();
    }
  }
}
