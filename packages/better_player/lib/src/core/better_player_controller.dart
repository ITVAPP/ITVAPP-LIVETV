import 'dart:async';
import 'dart:io';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/configuration/better_player_controller_event.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/subtitles/better_player_subtitle.dart';
import 'package:better_player/src/subtitles/better_player_subtitles_factory.dart';
import 'package:better_player/src/video_player/video_player.dart';
import 'package:better_player/src/video_player/video_player_platform_interface.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// 视频播放控制器，管理播放状态、数据源、字幕和事件监听
class BetterPlayerController {
  // 通用播放器配置
  final BetterPlayerConfiguration betterPlayerConfiguration;

  // 播放列表配置
  final BetterPlayerPlaylistConfiguration? betterPlayerPlaylistConfiguration;

  // 事件监听器列表
  // 注意：_eventListeners[0] 始终是全局监听器，不应被移除
  final List<Function(BetterPlayerEvent)?> _eventListeners = [];

  // 待删除的临时文件列表
  final List<File> _tempFiles = [];

  // 控件显示状态流控制器
  final StreamController<bool> _controlsVisibilityStreamController =
      StreamController.broadcast();

  // 视频播放器控制器，桥接 Flutter 和原生代码
  VideoPlayerController? videoPlayerController;

  // 控件配置
  late BetterPlayerControlsConfiguration _betterPlayerControlsConfiguration;

  // 获取控件配置
  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration =>
      _betterPlayerControlsConfiguration;

  // 获取活动的事件监听器
  List<Function(BetterPlayerEvent)?> get eventListeners =>
      _eventListeners.sublist(1);

  // 全局事件监听器
  Function(BetterPlayerEvent)? get eventListener =>
      betterPlayerConfiguration.eventListener;

  // 全屏模式状态
  bool _isFullScreen = false;

  // 获取全屏模式状态
  bool get isFullScreen => _isFullScreen;

  // 上次进度事件触发时间
  int _lastPositionSelection = 0;

  // 当前数据源
  BetterPlayerDataSource? _betterPlayerDataSource;

  // 获取当前数据源
  BetterPlayerDataSource? get betterPlayerDataSource => _betterPlayerDataSource;

  // 字幕源列表
  final List<BetterPlayerSubtitlesSource> _betterPlayerSubtitlesSourceList = [];

  // 获取字幕源列表
  List<BetterPlayerSubtitlesSource> get betterPlayerSubtitlesSourceList =>
      _betterPlayerSubtitlesSourceList;
  BetterPlayerSubtitlesSource? _betterPlayerSubtitlesSource;

  // 当前字幕源
  BetterPlayerSubtitlesSource? get betterPlayerSubtitlesSource =>
      _betterPlayerSubtitlesSource;

  // 当前数据源的字幕行
  List<BetterPlayerSubtitle> subtitlesLines = [];

  // HLS/DASH 轨道列表
  List<BetterPlayerAsmsTrack> _betterPlayerAsmsTracks = [];

  // 获取 HLS/DASH 轨道列表
  List<BetterPlayerAsmsTrack> get betterPlayerAsmsTracks =>
      _betterPlayerAsmsTracks;

  // 当前选择的 HLS/DASH 轨道
  BetterPlayerAsmsTrack? _betterPlayerAsmsTrack;

  // 获取当前选择的 HLS/DASH 轨道
  BetterPlayerAsmsTrack? get betterPlayerAsmsTrack => _betterPlayerAsmsTrack;

  // 播放列表下一视频定时器
  Timer? _nextVideoTimer;

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
  BetterPlayerTranslations translations = BetterPlayerTranslations();

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

  // BetterPlayer 组件全局键
  GlobalKey? _betterPlayerGlobalKey;

  // 获取全局键
  GlobalKey? get betterPlayerGlobalKey => _betterPlayerGlobalKey;

  // 视频事件流订阅
  StreamSubscription<VideoEvent>? _videoEventStreamSubscription;

  // 控件是否始终可见
  bool _controlsAlwaysVisible = false;

  // 获取控件始终可见状态
  bool get controlsAlwaysVisible => _controlsAlwaysVisible;

  // ASMS 音频轨道列表
  List<BetterPlayerAsmsAudioTrack>? _betterPlayerAsmsAudioTracks;

  // 获取 ASMS 音频轨道列表
  List<BetterPlayerAsmsAudioTrack>? get betterPlayerAsmsAudioTracks =>
      _betterPlayerAsmsAudioTracks;

  // 当前选择的 ASMS 音频轨道
  BetterPlayerAsmsAudioTrack? _betterPlayerAsmsAudioTrack;

  // 获取当前选择的 ASMS 音频轨道
  BetterPlayerAsmsAudioTrack? get betterPlayerAsmsAudioTrack =>
      _betterPlayerAsmsAudioTrack;

  // 错误时的视频播放器值
  VideoPlayerValue? _videoPlayerValueOnError;

  // 播放器是否可见
  bool _isPlayerVisible = true;

  // 内部事件流控制器
  final StreamController<BetterPlayerControllerEvent>
      _controllerEventStreamController = StreamController.broadcast();

  // 内部事件流
  Stream<BetterPlayerControllerEvent> get controllerEventStream =>
      _controllerEventStreamController.stream;

  // ASMS 字幕段是否正在加载
  bool _asmsSegmentsLoading = false;

  // 已加载的 ASMS 字幕段 - 优化：使用 Set 替代 List
  final Set<String> _asmsSegmentsLoaded = {};

  // 当前显示的字幕
  BetterPlayerSubtitle? renderedSubtitle;

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

  // 性能优化：缓存直播流检测结果
  bool? _cachedIsLiveStream;
  
  // 性能优化：待加载字幕段缓存
  List<BetterPlayerAsmsSubtitleSegment>? _pendingSubtitleSegments;
  Duration? _lastSubtitleCheckPosition;

  // 构造函数，初始化配置和数据源
  BetterPlayerController(
    this.betterPlayerConfiguration, {
    this.betterPlayerPlaylistConfiguration,
    BetterPlayerDataSource? betterPlayerDataSource,
  }) {
    this._betterPlayerControlsConfiguration =
        betterPlayerConfiguration.controlsConfiguration;
    _eventListeners.add(eventListener);
    if (betterPlayerDataSource != null) {
      setupDataSource(betterPlayerDataSource);
    }
  }

  // 从上下文中获取控制器实例
  static BetterPlayerController of(BuildContext context) {
    final betterPLayerControllerProvider = context
        .dependOnInheritedWidgetOfExactType<BetterPlayerControllerProvider>()!;

    return betterPLayerControllerProvider.controller;
  }

  // 设置视频数据源，初始化播放器和字幕
  Future setupDataSource(BetterPlayerDataSource betterPlayerDataSource) async {
    postEvent(BetterPlayerEvent(BetterPlayerEventType.setupDataSource,
        parameters: <String, dynamic>{
          "dataSource": betterPlayerDataSource,
        }));
    _postControllerEvent(BetterPlayerControllerEvent.setupDataSource);
    _hasCurrentDataSourceStarted = false;
    _hasCurrentDataSourceInitialized = false;
    _betterPlayerDataSource = betterPlayerDataSource;
    _betterPlayerSubtitlesSourceList.clear();
    
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
              betterPlayerDataSource.bufferingConfiguration);
      videoPlayerController?.addListener(_onVideoPlayerChanged);
    }

    // 清空 ASMS 轨道
    betterPlayerAsmsTracks.clear();

    // 设置字幕
    final List<BetterPlayerSubtitlesSource>? betterPlayerSubtitlesSourceList =
        betterPlayerDataSource.subtitles;
    if (betterPlayerSubtitlesSourceList != null) {
      _betterPlayerSubtitlesSourceList
          .addAll(betterPlayerDataSource.subtitles!);
    }

    if (_isDataSourceAsms(betterPlayerDataSource)) {
      _setupAsmsDataSource(betterPlayerDataSource).then((dynamic value) {
        _setupSubtitles();
      });
    } else {
      _setupSubtitles();
    }

    // 处理数据源
    await _setupDataSource(betterPlayerDataSource);
    setTrack(BetterPlayerAsmsTrack.defaultTrack());
  }

  // 配置字幕源，设置默认或无字幕
  void _setupSubtitles() {
    _betterPlayerSubtitlesSourceList.add(
      BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none),
    );
    final defaultSubtitle = _betterPlayerSubtitlesSourceList
        .firstWhereOrNull((element) => element.selectedByDefault == true);

    // 设置默认字幕或无字幕
    setupSubtitleSource(
        defaultSubtitle ?? _betterPlayerSubtitlesSourceList.last,
        sourceInitialize: true);
  }

  // 检查数据源是否为 HLS/DASH 格式
  bool _isDataSourceAsms(BetterPlayerDataSource betterPlayerDataSource) =>
      (BetterPlayerAsmsUtils.isDataSourceHls(betterPlayerDataSource.url) ||
          betterPlayerDataSource.videoFormat == BetterPlayerVideoFormat.hls) ||
      (BetterPlayerAsmsUtils.isDataSourceDash(betterPlayerDataSource.url) ||
          betterPlayerDataSource.videoFormat == BetterPlayerVideoFormat.dash);

  // 配置 HLS/DASH 数据源，加载轨道、字幕和音频
  Future _setupAsmsDataSource(BetterPlayerDataSource source) async {
    final String? data = await BetterPlayerAsmsUtils.getDataFromUrl(
      betterPlayerDataSource!.url,
      _getHeaders(),
    );
    if (data != null) {
      final BetterPlayerAsmsDataHolder _response =
          await BetterPlayerAsmsUtils.parse(data, betterPlayerDataSource!.url);

      // 加载轨道
      if (_betterPlayerDataSource?.useAsmsTracks == true) {
        _betterPlayerAsmsTracks = _response.tracks ?? [];
      }

      // 加载字幕
      if (betterPlayerDataSource?.useAsmsSubtitles == true) {
        final List<BetterPlayerAsmsSubtitle> asmsSubtitles =
            _response.subtitles ?? [];
        asmsSubtitles.forEach((BetterPlayerAsmsSubtitle asmsSubtitle) {
          _betterPlayerSubtitlesSourceList.add(
            BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.network,
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
      if (betterPlayerDataSource?.useAsmsAudioTracks == true &&
          _isDataSourceAsms(betterPlayerDataSource!)) {
        _betterPlayerAsmsAudioTracks = _response.audios ?? [];
        if (_betterPlayerAsmsAudioTracks?.isNotEmpty == true) {
          setAudioTrack(_betterPlayerAsmsAudioTracks!.first);
        }
      }
    }
  }

  // 设置字幕源，加载字幕行
  Future<void> setupSubtitleSource(BetterPlayerSubtitlesSource subtitlesSource,
      {bool sourceInitialize = false}) async {
    _betterPlayerSubtitlesSource = subtitlesSource;
    subtitlesLines.clear();
    _asmsSegmentsLoaded.clear();
    _asmsSegmentsLoading = false;
    // 性能优化：清理字幕缓存
    _pendingSubtitleSegments = null;
    _lastSubtitleCheckPosition = null;

    if (subtitlesSource.type != BetterPlayerSubtitlesSourceType.none) {
      if (subtitlesSource.asmsIsSegmented == true) {
        return;
      }
      final subtitlesParsed =
          await BetterPlayerSubtitlesFactory.parseSubtitles(subtitlesSource);
      subtitlesLines.addAll(subtitlesParsed);
    }

    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedSubtitles));
    if (!_disposed && !sourceInitialize) {
      _postControllerEvent(BetterPlayerControllerEvent.changeSubtitles);
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
      final BetterPlayerSubtitlesSource? source = _betterPlayerSubtitlesSource;
      final Duration loadDurationEnd = Duration(
          milliseconds: position.inMilliseconds +
              5 * (_betterPlayerSubtitlesSource?.asmsSegmentsTime ?? 5000));

      // 性能优化：使用缓存的待加载段列表
      if (_pendingSubtitleSegments == null) {
        _pendingSubtitleSegments = _betterPlayerSubtitlesSource?.asmsSegments
            ?.where((segment) => !_asmsSegmentsLoaded.contains(segment.realUrl))
            .toList() ?? [];
      }
      
      // 过滤出需要加载的段
      final segmentsToLoad = <String>[];
      final segmentsToRemove = <BetterPlayerAsmsSubtitleSegment>[];
      
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
            await BetterPlayerSubtitlesFactory.parseSubtitles(
                BetterPlayerSubtitlesSource(
          type: _betterPlayerSubtitlesSource!.type,
          headers: _betterPlayerSubtitlesSource!.headers,
          urls: segmentsToLoad,
        ));

        // 验证字幕源一致性
        if (source == _betterPlayerSubtitlesSource) {
          subtitlesLines.addAll(subtitlesParsed);
          _asmsSegmentsLoaded.addAll(segmentsToLoad);
        }
      }
      _asmsSegmentsLoading = false;
    } catch (exception) {
      // 静默处理异常
    }
  }

  // 获取视频格式，适配 video_player 格式
  VideoFormat? _getVideoFormat(
      BetterPlayerVideoFormat? betterPlayerVideoFormat) {
    if (betterPlayerVideoFormat == null) {
      return null;
    }
    switch (betterPlayerVideoFormat) {
      case BetterPlayerVideoFormat.dash:
        return VideoFormat.dash;
      case BetterPlayerVideoFormat.hls:
        return VideoFormat.hls;
      case BetterPlayerVideoFormat.ss:
        return VideoFormat.ss;
      case BetterPlayerVideoFormat.other:
        return VideoFormat.other;
    }
  }

  // 设置视频数据源，处理网络、文件或内存数据
  Future _setupDataSource(BetterPlayerDataSource betterPlayerDataSource) async {
    switch (betterPlayerDataSource.type) {
      case BetterPlayerDataSourceType.network:
        await videoPlayerController?.setNetworkDataSource(
          betterPlayerDataSource.url,
          headers: _getHeaders(),
          useCache:
              _betterPlayerDataSource!.cacheConfiguration?.useCache ?? false,
          maxCacheSize:
              _betterPlayerDataSource!.cacheConfiguration?.maxCacheSize ?? 0,
          maxCacheFileSize:
              _betterPlayerDataSource!.cacheConfiguration?.maxCacheFileSize ??
                  0,
          cacheKey: _betterPlayerDataSource?.cacheConfiguration?.key,
          showNotification: _betterPlayerDataSource
              ?.notificationConfiguration?.showNotification,
          title: _betterPlayerDataSource?.notificationConfiguration?.title,
          author: _betterPlayerDataSource?.notificationConfiguration?.author,
          imageUrl:
              _betterPlayerDataSource?.notificationConfiguration?.imageUrl,
          notificationChannelName: _betterPlayerDataSource
              ?.notificationConfiguration?.notificationChannelName,
          overriddenDuration: _betterPlayerDataSource!.overriddenDuration,
          formatHint: _getVideoFormat(_betterPlayerDataSource!.videoFormat),
          licenseUrl: _betterPlayerDataSource?.drmConfiguration?.licenseUrl,
          certificateUrl:
              _betterPlayerDataSource?.drmConfiguration?.certificateUrl,
          drmHeaders: _betterPlayerDataSource?.drmConfiguration?.headers,
          activityName:
              _betterPlayerDataSource?.notificationConfiguration?.activityName,
          clearKey: _betterPlayerDataSource?.drmConfiguration?.clearKey,
          videoExtension: _betterPlayerDataSource!.videoExtension,
        );

        break;
      case BetterPlayerDataSourceType.file:
        await videoPlayerController?.setFileDataSource(
            File(betterPlayerDataSource.url),
            showNotification: _betterPlayerDataSource
                ?.notificationConfiguration?.showNotification,
            title: _betterPlayerDataSource?.notificationConfiguration?.title,
            author: _betterPlayerDataSource?.notificationConfiguration?.author,
            imageUrl:
                _betterPlayerDataSource?.notificationConfiguration?.imageUrl,
            notificationChannelName: _betterPlayerDataSource
                ?.notificationConfiguration?.notificationChannelName,
            overriddenDuration: _betterPlayerDataSource!.overriddenDuration,
            activityName: _betterPlayerDataSource
                ?.notificationConfiguration?.activityName,
            clearKey: _betterPlayerDataSource?.drmConfiguration?.clearKey);
        break;
      case BetterPlayerDataSourceType.memory:
        final file = await _createFile(_betterPlayerDataSource!.bytes!,
            extension: _betterPlayerDataSource!.videoExtension);

        if (file.existsSync()) {
          await videoPlayerController?.setFileDataSource(file,
              showNotification: _betterPlayerDataSource
                  ?.notificationConfiguration?.showNotification,
              title: _betterPlayerDataSource?.notificationConfiguration?.title,
              author:
                  _betterPlayerDataSource?.notificationConfiguration?.author,
              imageUrl:
                  _betterPlayerDataSource?.notificationConfiguration?.imageUrl,
              notificationChannelName: _betterPlayerDataSource
                  ?.notificationConfiguration?.notificationChannelName,
              overriddenDuration: _betterPlayerDataSource!.overriddenDuration,
              activityName: _betterPlayerDataSource
                  ?.notificationConfiguration?.activityName,
              clearKey: _betterPlayerDataSource?.drmConfiguration?.clearKey);
          _tempFiles.add(file);
        } else {
          throw ArgumentError("无法从内存创建文件");
        }
        break;

      default:
        throw UnimplementedError(
            "${betterPlayerDataSource.type} 未实现");
    }
    await _initializeVideo();
  }

  // 从字节数组创建临时文件
  Future<File> _createFile(List<int> bytes,
      {String? extension = "temp"}) async {
    final String dir = (await getTemporaryDirectory()).path;
    final File temp = File(
        '$dir/better_player_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await temp.writeAsBytes(bytes);
    return temp;
  }

  // 初始化视频，设置循环和自动播放
  Future _initializeVideo() async {
    setLooping(betterPlayerConfiguration.looping);
    _videoEventStreamSubscription?.cancel();
    _videoEventStreamSubscription = null;

    _videoEventStreamSubscription = videoPlayerController
        ?.videoEventStreamController.stream
        .listen(_handleVideoEvent);

    final fullScreenByDefault = betterPlayerConfiguration.fullScreenByDefault;
    if (betterPlayerConfiguration.autoPlay) {
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

    final startAt = betterPlayerConfiguration.startAt;
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
    _postControllerEvent(BetterPlayerControllerEvent.openFullscreen);
  }

  // 退出全屏模式
  void exitFullScreen() {
    _isFullScreen = false;
    _postControllerEvent(BetterPlayerControllerEvent.hideFullscreen);
  }

  // 切换全屏模式
  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      _postControllerEvent(BetterPlayerControllerEvent.openFullscreen);
    } else {
      _postControllerEvent(BetterPlayerControllerEvent.hideFullscreen);
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
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.play));
      _postControllerEvent(BetterPlayerControllerEvent.play);
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
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.pause));
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

    _postEvent(BetterPlayerEvent(BetterPlayerEventType.seekTo,
        parameters: <String, dynamic>{"duration": moment}));

    final Duration? currentDuration = videoPlayerController!.value.duration;
    if (currentDuration == null) {
      return;
    }
    if (moment > currentDuration) {
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    } else {
      cancelNextVideoTimer();
    }
  }

  // 设置音量，范围 0.0 到 1.0
  Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) {
      throw ArgumentError("音量必须在 0.0 到 1.0 之间");
    }
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    await videoPlayerController!.setVolume(volume);
    _postEvent(BetterPlayerEvent(
      BetterPlayerEventType.setVolume,
      parameters: <String, dynamic>{"volume": volume},
    ));
  }

  // 设置播放速度，范围 0 到 2
  Future<void> setSpeed(double speed) async {
    if (speed <= 0 || speed > 2) {
      throw ArgumentError("速度必须在 0 到 2 之间");
    }
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    await videoPlayerController?.setSpeed(speed);
    _postEvent(
      BetterPlayerEvent(
        BetterPlayerEventType.setSpeed,
        parameters: <String, dynamic>{
          "speed": speed,
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
        ? BetterPlayerEvent(BetterPlayerEventType.controlsVisible)
        : BetterPlayerEvent(BetterPlayerEventType.controlsHiddenEnd));
  }

  // 发送播放器事件
  void postEvent(BetterPlayerEvent betterPlayerEvent) {
    _postEvent(betterPlayerEvent);
  }

  // 向所有监听器发送事件
  void _postEvent(BetterPlayerEvent betterPlayerEvent) {
    // 检查是否已释放，阻止后续事件处理
    if (_disposed) {
      return;
    }
    
    for (final Function(BetterPlayerEvent)? eventListener in _eventListeners) {
      if (eventListener != null) {
        eventListener(betterPlayerEvent);
      }
    }
  }

  // 处理来自原生端的视频事件
  void _handleVideoEvent(VideoEvent event) {
    // 检查是否已释放
    if (_disposed) {
      return;
    }
    
    switch (event.eventType) {
      case VideoEventType.play:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.play));
        break;
        
      case VideoEventType.pause:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.pause));
        break;
        
      case VideoEventType.seek:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.seekTo));
        break;
        
      case VideoEventType.completed:
        final VideoPlayerValue? videoValue = videoPlayerController?.value;
        _postEvent(
          BetterPlayerEvent(
            BetterPlayerEventType.finished,
            parameters: <String, dynamic>{
              "progress": videoValue?.position,
              "duration": videoValue?.duration
            },
          ),
        );
        break;
        
      case VideoEventType.bufferingStart:
        _handleBufferingStart();
        break;
        
      case VideoEventType.bufferingUpdate:
        // 增强：处理缓冲更新事件
        if (event.buffered != null && event.buffered!.isNotEmpty) {
          _postEvent(BetterPlayerEvent(
            BetterPlayerEventType.bufferingUpdate,
            parameters: <String, dynamic>{
              "buffered": event.buffered,
            }
          ));
        }
        break;
        
      case VideoEventType.bufferingEnd:
        _handleBufferingEnd();
        break;
        
      case VideoEventType.initialized:
        // 处理初始化完成事件
        if (!_hasCurrentDataSourceInitialized) {
          _hasCurrentDataSourceInitialized = true;
          _postEvent(BetterPlayerEvent(BetterPlayerEventType.initialized));
        }
        break;
        
      default:
        // 忽略未知事件类型
        break;
    }
  }

  // 优化后的缓冲开始处理方法
  void _handleBufferingStart() {
    // 检查是否已释放
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
              _postEvent(BetterPlayerEvent(BetterPlayerEventType.bufferingStart));
            }
          }
        );
        return;
      }
    }
    
    // 立即开始缓冲
    _isCurrentlyBuffering = true;
    _lastBufferingChangeTime = now;
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.bufferingStart));
  }

  // 优化后的缓冲结束处理方法  
  void _handleBufferingEnd() {
    // 检查是否已释放
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
              _postEvent(BetterPlayerEvent(BetterPlayerEventType.bufferingEnd));
            }
          }
        );
        return;
      }
    }
    
    // 立即结束缓冲
    _isCurrentlyBuffering = false;
    _lastBufferingChangeTime = now;
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.bufferingEnd));
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
        BetterPlayerEvent(
          BetterPlayerEventType.exception,
          parameters: <String, dynamic>{
            "exception": currentValue.errorDescription
          },
        ),
      );
    }

    // 处理初始化事件
    if (currentValue.initialized && !_hasCurrentDataSourceInitialized) {
      _hasCurrentDataSourceInitialized = true;
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.initialized));
    }

    // 处理画中画模式
    if (currentValue.isPip) {
      _wasInPipMode = true;
    } else if (_wasInPipMode) {
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.pipStop));
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
    if (_betterPlayerSubtitlesSource?.asmsIsSegmented == true) {
      _loadAsmsSubtitlesSegments(currentValue.position);
    }

    // 节流进度事件
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPositionSelection > 500) {
      _lastPositionSelection = now;
      _postEvent(
        BetterPlayerEvent(
          BetterPlayerEventType.progress,
          parameters: <String, dynamic>{
            "progress": currentValue.position,
            "duration": currentValue.duration
          },
        ),
      );
    }

    // 更新缓存值
    _lastVideoPlayerValue = currentValue;
  }

  // 添加事件监听器
  void addEventsListener(Function(BetterPlayerEvent) eventListener) {
    if (!_eventListeners.contains(eventListener)) {
      _eventListeners.add(eventListener);
    }
  }

  // 移除事件监听器
  void removeEventsListener(Function(BetterPlayerEvent) eventListener) {
    // 确保不会移除全局监听器（索引0）
    final index = _eventListeners.indexOf(eventListener);
    if (index > 0) {
      _eventListeners.removeAt(index);
    }
  }

  // 检查是否为直播数据源 - 性能优化：缓存结果
  bool isLiveStream() {
    if (_betterPlayerDataSource == null) {
      throw StateError("数据源未初始化");
    }
    
    // 性能优化：使用缓存结果
    if (_cachedIsLiveStream != null) {
      return _cachedIsLiveStream!;
    }
    
    // 如果已经手动设置了 liveStream，直接返回
    if (_betterPlayerDataSource!.liveStream == true) {
      _cachedIsLiveStream = true;
      return true;
    }
    
    // 自动检测直播流格式
    final url = _betterPlayerDataSource!.url.toLowerCase();
    
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
      throw StateError("数据源未初始化");
    }
    return videoPlayerController?.value.initialized;
  }

  // 启动播放列表下一视频定时器
  void startNextVideoTimer() {
    if (_nextVideoTimer == null) {
      if (betterPlayerPlaylistConfiguration == null) {
        throw StateError("播放列表配置未设置");
      }

      _nextVideoTime =
          betterPlayerPlaylistConfiguration!.nextVideoDelay.inSeconds;
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
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedPlaylistItem));
    cancelNextVideoTimer();
  }

  // 选择 HLS/DASH 轨道，设置分辨率参数
  void setTrack(BetterPlayerAsmsTrack track) {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedTrack,
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
    _betterPlayerAsmsTrack = track;
  }

  // 检查是否支持自动播放/暂停
  bool _isAutomaticPlayPauseHandled() {
    return !(_betterPlayerDataSource
                ?.notificationConfiguration?.showNotification ==
            true) &&
        betterPlayerConfiguration.handleLifecycle;
  }

  // 处理播放器可见性变化，控制自动播放/暂停
  void onPlayerVisibilityChanged(double visibilityFraction) async {
    _isPlayerVisible = visibilityFraction > 0;
    // 检查是否已释放
    if (_disposed) {
      return;
    }
    _postEvent(
        BetterPlayerEvent(BetterPlayerEventType.changedPlayerVisibility));

    if (_isAutomaticPlayPauseHandled()) {
      if (betterPlayerConfiguration.playerVisibilityChangedBehavior != null) {
        betterPlayerConfiguration
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
    await setupDataSource(betterPlayerDataSource!.copyWith(url: url));
    seekTo(position!);
    if (wasPlayingBeforeChange) {
      play();
    }
    _postEvent(BetterPlayerEvent(
      BetterPlayerEventType.changedResolution,
      parameters: <String, dynamic>{"url": url},
    ));
  }

  // 设置指定语言的翻译
  void setupTranslations(Locale locale) {
    // ignore: unnecessary_null_comparison
    if (locale != null) {
      final String languageCode = locale.languageCode;
      translations = betterPlayerConfiguration.translations?.firstWhereOrNull(
              (translations) => translations.languageCode == languageCode) ??
          _getDefaultTranslations(locale);
    }
  }

  // 获取默认翻译配置
  BetterPlayerTranslations _getDefaultTranslations(Locale locale) {
    final String languageCode = locale.languageCode;
    switch (languageCode) {
      case "pl":
        return BetterPlayerTranslations.polish();
      case "zh":
        return BetterPlayerTranslations.chinese();
      case "hi":
        return BetterPlayerTranslations.hindi();
      case "tr":
        return BetterPlayerTranslations.turkish();
      case "vi":
        return BetterPlayerTranslations.vietnamese();
      case "es":
        return BetterPlayerTranslations.spanish();
      default:
        return BetterPlayerTranslations();
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
    return _overriddenAspectRatio ?? betterPlayerConfiguration.aspectRatio;
  }

  // ignore: use_setters_to_change_properties
  // 设置覆盖的适配模式
  void setOverriddenFit(BoxFit fit) {
    _overriddenFit = fit;
  }

  // 获取当前适配模式
  BoxFit getFit() {
    return _overriddenFit ?? betterPlayerConfiguration.fit;
  }

  // 启用画中画模式
  Future<void>? enablePictureInPicture(GlobalKey betterPlayerGlobalKey) async {
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
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.pipStart));
        return;
      }
      if (Platform.isIOS) {
        final RenderBox? renderBox = betterPlayerGlobalKey.currentContext!
            .findRenderObject() as RenderBox?;
        if (renderBox == null) {
          return;
        }
        final Offset position = renderBox.localToGlobal(Offset.zero);
        return videoPlayerController?.enablePictureInPicture(
          left: position.dx,
          top: position.dy,
          width: renderBox.size.width,
          height: renderBox.size.height,
        );
      }
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
  // 设置 BetterPlayer 全局键
  void setBetterPlayerGlobalKey(GlobalKey betterPlayerGlobalKey) {
    _betterPlayerGlobalKey = betterPlayerGlobalKey;
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

  // 设置控件始终可见模式
  void setControlsAlwaysVisible(bool controlsAlwaysVisible) {
    _controlsAlwaysVisible = controlsAlwaysVisible;
    _controlsVisibilityStreamController.add(controlsAlwaysVisible);
  }

  // 重试数据源加载
  Future retryDataSource() async {
    await _setupDataSource(_betterPlayerDataSource!);
    if (_videoPlayerValueOnError != null) {
      final position = _videoPlayerValueOnError!.position;
      await seekTo(position);
      await play();
      _videoPlayerValueOnError = null;
    }
  }

  // 选择 HLS/DASH 音频轨道
  void setAudioTrack(BetterPlayerAsmsAudioTrack audioTrack) {
    if (videoPlayerController == null) {
      throw StateError("数据源未初始化");
    }

    if (audioTrack.language == null) {
      _betterPlayerAsmsAudioTrack = null;
      return;
    }

    _betterPlayerAsmsAudioTrack = audioTrack;
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
    final headers = betterPlayerDataSource!.headers ?? {};
    if (betterPlayerDataSource?.drmConfiguration?.drmType ==
            BetterPlayerDrmType.token &&
        betterPlayerDataSource?.drmConfiguration?.token != null) {
      headers["Authorization"] =
          betterPlayerDataSource!.drmConfiguration!.token!;
    }
    return headers;
  }

  // 预缓存视频数据
  Future<void> preCache(BetterPlayerDataSource betterPlayerDataSource) async {
    final cacheConfig = betterPlayerDataSource.cacheConfiguration ??
        const BetterPlayerCacheConfiguration(useCache: true);

    final dataSource = DataSource(
      sourceType: DataSourceType.network,
      uri: betterPlayerDataSource.url,
      useCache: true,
      headers: betterPlayerDataSource.headers,
      maxCacheSize: cacheConfig.maxCacheSize,
      maxCacheFileSize: cacheConfig.maxCacheFileSize,
      cacheKey: cacheConfig.key,
      videoExtension: betterPlayerDataSource.videoExtension,
    );

    return VideoPlayerController.preCache(dataSource, cacheConfig.preCacheSize);
  }

  // 停止预缓存
  Future<void> stopPreCache(
      BetterPlayerDataSource betterPlayerDataSource) async {
    return VideoPlayerController?.stopPreCache(betterPlayerDataSource.url,
        betterPlayerDataSource.cacheConfiguration?.key);
  }

  // 设置控件配置
  void setBetterPlayerControlsConfiguration(
      BetterPlayerControlsConfiguration betterPlayerControlsConfiguration) {
    this._betterPlayerControlsConfiguration = betterPlayerControlsConfiguration;
  }

  // 发送内部事件
  void _postControllerEvent(BetterPlayerControllerEvent event) {
    // 检查是否已释放和流控制器状态
    if (_disposed || _controllerEventStreamController.isClosed) {
      return;
    }
    _controllerEventStreamController.add(event);
  }
  
  // 设置缓冲防抖时间（毫秒）
  void setBufferingDebounceTime(int milliseconds) {
    if (milliseconds < 0) {
      return;
    }
    _bufferingDebounceMs = milliseconds;
  }
  
  // 清理缓冲状态
  void _clearBufferingState() {
    _bufferingDebounceTimer?.cancel();
    _bufferingDebounceTimer = null;
    _isCurrentlyBuffering = false;
    _lastBufferingChangeTime = null;
  }
  
  // 添加获取当前缓冲状态的方法
  bool get isCurrentlyBuffering => _isCurrentlyBuffering;

  // 添加获取缓冲百分比的方法
  double get bufferingProgress {
    if (videoPlayerController == null || !isVideoInitialized()!) {
      return 0.0;
    }
    
    final duration = videoPlayerController!.value.duration;
    final bufferedRanges = videoPlayerController!.value.buffered;
    
    if (duration == null || duration.inMilliseconds == 0) {
      return 0.0;
    }
    
    // 如果没有缓冲范围，返回0
    if (bufferedRanges.isEmpty) {
      return 0.0;
    }
    
    // 获取最后一个缓冲范围的结束时间作为缓冲位置
    // 这是最远的缓冲点
    final lastBufferedRange = bufferedRanges.last;
    final bufferedPosition = lastBufferedRange.end;
    
    return (bufferedPosition.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  // 添加手动触发缓冲检查的方法（用于调试）
  void checkBufferingState() {
    if (_disposed || videoPlayerController == null) {
      return;
    }
    
    final isBuffering = videoPlayerController!.value.isBuffering;
    
    if (isBuffering && !_isCurrentlyBuffering) {
      _handleBufferingStart();
    } else if (!isBuffering && _isCurrentlyBuffering) {
      _handleBufferingEnd();
    }
  }

  // 销毁控制器，清理资源
  void dispose({bool forceDispose = false}) {
    if (!betterPlayerConfiguration.autoDispose && !forceDispose) {
      return;
    }
    if (!_disposed) {
      // 立即设置标志，阻止后续所有事件和回调
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
