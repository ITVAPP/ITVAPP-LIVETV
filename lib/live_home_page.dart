import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider/theme_provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:better_player/better_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:itvapp_live_tv/config.dart';
import 'package:itvapp_live_tv/channel_drawer_page.dart';
import 'package:itvapp_live_tv/mobile_video_widget.dart';
import 'package:itvapp_live_tv/table_video_widget.dart';
import 'package:itvapp_live_tv/tv/tv_page.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart';
import 'package:itvapp_live_tv/util/stream_url.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/util/channel_util.dart';
import 'package:itvapp_live_tv/util/traffic_analytics.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 主页面
class LiveHomePage extends StatefulWidget { 
  final PlaylistModel m3uData;
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

/// 计时器类型枚举
enum TimerType {
  retry,
  m3u8Check,
  playDuration,
  timeout,
  bufferingCheck,
}

/// 切换请求类
class SwitchRequest {
  final PlayModel? channel;
  final int sourceIndex;
  
  SwitchRequest(this.channel, this.sourceIndex);
}

/// 修改点1：计时器管理类优化，使用单一 Timer.periodic
class TimerManager {
  Timer? _timer;
  final Map<TimerType, Tuple2<Duration, Function>> _tasks = {};

  /// 启动统一计时器
  void startUnifiedTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      _tasks.forEach((type, task) {
        if (timer.tick % (task.item1.inMilliseconds / 1000) == 0) {
          task.item2();
        }
      });
    });
  }

  /// 添加任务（替代 startTimer 和 startPeriodicTimer）
  void addTask(TimerType type, Duration duration, Function callback) {
    cancelTask(type); // 先取消同类型任务
    _tasks[type] = Tuple2(duration, callback);
    if (_timer == null) startUnifiedTimer();
  }

  /// 取消任务（替代 cancelTimer）
  void cancelTask(TimerType type) {
    _tasks.remove(type);
    if (_tasks.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// 取消所有任务（替代 cancelAll）
  void cancelAll() {
    _tasks.clear();
    _timer?.cancel();
    _timer = null;
  }

  /// 检查任务是否活跃（替代 isActive）
  bool isActive(TimerType type) {
    return _tasks.containsKey(type);
  }
}

/// 用于计时器任务的元组类
class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int defaultMaxRetries = 1;
  static const int defaultTimeoutSeconds = 36;
  static const int initialProgressDelaySeconds = 60;
  static const int retryDelaySeconds = 2;
  static const int m3u8InvalidConfirmDelaySeconds = 1;
  static const int hlsSwitchThresholdSeconds = 3;
  static const int nonHlsPreloadThresholdSeconds = 20;
  static const int nonHlsSwitchThresholdSeconds = 3;
  static const double defaultAspectRatio = 1.78;
  static const int cleanupDelayMilliseconds = 500;
  static const int snackBarDurationSeconds = 4;
  static const int bufferingStartSeconds = 10;
  static const int m3u8CheckIntervalSeconds = 10;
  static const int reparseMinIntervalMilliseconds = 10000;
  static const int m3u8ConnectTimeoutSeconds = 5;
  static const int m3u8ReceiveTimeoutSeconds = 10;
  static const int m3u8CheckCacheIntervalMs = 5000;
  static const bool enableM3u8SecondCheck = true;
  static const bool enableNonHlsPreload = true;

  String? _preCachedUrl;
  bool _isParsing = false;
  bool _isRetrying = false;
  int? _lastParseTime;
  String toastString = S.current.loading;
  PlaylistModel? _videoMap;
  PlayModel? _currentChannel;
  int _sourceIndex = 0;
  BetterPlayerController? _playerController;
  bool isBuffering = false;
  bool isPlaying = false;
  double aspectRatio = defaultAspectRatio;
  bool _drawerIsOpen = false;
  int _retryCount = 0;
  bool _timeoutActive = false;
  bool _isDisposing = false;
  bool _isSwitchingChannel = false;
  bool _shouldUpdateAspectRatio = true;
  StreamUrl? _streamUrl;
  StreamUrl? _preCacheStreamUrl;
  String? _currentPlayUrl;
  String? _originalUrl;
  bool _progressEnabled = false;
  bool _isHls = false;
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  ValueKey<int>? _drawerRefreshKey;
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();
  bool _isAudio = false;
  late AdManager _adManager;
  bool _isUserPaused = false;
  bool _showPlayIcon = false;
  bool _showPauseIconFromListener = false;
  int _m3u8InvalidCount = 0;

  final TimerManager _timerManager = TimerManager();
  SwitchRequest? _pendingSwitch;

  // 修改点2：添加状态缓存
  bool _cachedIsRetrying = false;
  bool _cachedIsSwitchingChannel = false;
  bool _cachedIsDisposing = false;
  bool _cachedIsParsing = false;

  bool _checkUrlFormat(String? url, List<String> formats) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return formats.any(lowercaseUrl.contains);
  }

  bool _checkIsAudioStream(String? url) {
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    return _checkUrlFormat(url, audioFormats) && !_checkUrlFormat(url, videoFormats);
  }

  bool _isHlsStream(String? url) {
    if (_checkUrlFormat(url, ['.m3u8'])) return true;
    return !_checkUrlFormat(url, [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'
    ]);
  }

  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  /// 修改点3：统一状态更新，同步缓存
  void _updatePlayState({
    bool? playing,
    bool? buffering,
    String? message,
    bool? showPlay,
    bool? showPause,
    bool? userPaused,
    bool? switching,
    bool? retrying,
    bool? parsing,
    int? sourceIndex,
    int? retryCount,
  }) {
    if (!mounted) return;

    setState(() {
      if (playing != null) isPlaying = playing;
      if (buffering != null) isBuffering = buffering;
      if (message != null) toastString = message;
      if (showPlay != null) _showPlayIcon = showPlay;
      if (showPause != null) _showPauseIconFromListener = showPause;
      if (userPaused != null) _isUserPaused = userPaused;
      if (switching != null) {
        _isSwitchingChannel = switching;
        _cachedIsSwitchingChannel = switching; // 同步缓存
      }
      if (retrying != null) {
        _isRetrying = retrying;
        _cachedIsRetrying = retrying; // 同步缓存
      }
      if (parsing != null) {
        _isParsing = parsing;
        _cachedIsParsing = parsing; // 同步缓存
      }
      if (sourceIndex != null) _sourceIndex = sourceIndex;
      if (retryCount != null) _retryCount = retryCount;
    });
  }

  bool _canPerformOperation(String operationName, {
    bool checkRetrying = true,
    bool checkSwitching = true,
    bool checkDisposing = true,
    bool checkParsing = true,
  }) {
    final List<String> blockers = [];
    
    if (checkRetrying && _cachedIsRetrying) blockers.add('正在重试');
    if (checkSwitching && _cachedIsSwitchingChannel) blockers.add('正在切换频道');
    if (checkDisposing && _isDisposing) blockers.add('正在释放资源');
    if (checkParsing && _cachedIsParsing) blockers.add('正在解析');
    
    if (blockers.isNotEmpty) {
      LogUtil.i('$operationName 被阻止: ${blockers.join(", ")}');
      return false;
    }
    return true;
  }

  Future<void> _preparePreCacheSource(String url) async {
    final newSource = BetterPlayerConfig.createDataSource(
      isHls: _isHlsStream(url),
      url: url,
    );
    await _playerController!.preCache(newSource);
  }

  Future<void> _switchToPreCachedUrl(String logDescription) async {
    _timerManager.cancelAll();

    if (_preCachedUrl == null) {
      LogUtil.i('$logDescription: 预缓存地址为空，无法切换');
      return;
    }

    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址与当前地址相同，跳过切换，尝试重新解析');
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl();
      await _reparseAndSwitch();
      return;
    }

    try {
      await _preparePreCacheSource(_preCachedUrl!);
      LogUtil.i('$logDescription: 预缓存新数据源完成: $_preCachedUrl');
      final newSource = BetterPlayerConfig.createDataSource(url: _preCachedUrl!, isHls: _isHlsStream(_preCachedUrl));
      await _playerController?.setupDataSource(newSource);

      if (isPlaying) {
        await _playerController?.play();
        LogUtil.i('$logDescription: 切换到预缓存地址并开始播放');
        _startPlayDurationTimer();
      } else {
        LogUtil.i('$logDescription: 切换到预缓存地址但保持暂停状态');
      }

      _updatePlayUrl(_preCachedUrl!);
    } catch (e, stackTrace) {
      LogUtil.logError('$logDescription: 切换到预缓存地址失败', e, stackTrace);
      _retryPlayback();
      return;
    } finally {
      _progressEnabled = false;
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl();
    }
  }

  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null) {
      LogUtil.e('播放视频失败：_currentChannel 为 null');
      return;
    }

    if (!_isSourceIndexValid()) {
      LogUtil.e('播放视频失败：源索引无效');
      return;
    }

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');

    _timerManager.cancelAll();
    _adManager.reset();

    _updatePlayState(
      message: '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
      playing: false,
      buffering: false,
      showPlay: false,
      showPause: false,
      userPaused: false,
      switching: true,
    );

    _startPlaybackTimeout();

    try {
      if (!isRetry && !isSourceSwitch && _adManager.shouldPlayVideoAd()) {
        await _adManager.playVideoAd();
        LogUtil.i('视频广告播放完成，准备播放频道');
        _adManager.reset();
      }

      await _cleanupCurrentPlayer();
      await _preparePlaybackUrl();
      await _setupPlayerController();
      await _startPlayback();
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrl();
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        _updatePlayState(switching: false);
        _processPendingSwitch();
      }
    }
  }

  bool _isSourceIndexValid() {
    if (_sourceIndex < 0 || _currentChannel!.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
      _sourceIndex = 0;
      if (_currentChannel!.urls == null || _currentChannel!.urls!.isEmpty) {
        LogUtil.e('频道没有可用源');
        _updatePlayState(
          message: S.current.playError,
          playing: false,
          buffering: false,
          showPlay: false,
          showPause: false,
        );
        return false;
      }
    }
    return true;
  }

  void _startPlaybackTimeout() {
    _timeoutActive = true;
    _timerManager.addTask(
      TimerType.timeout,
      Duration(seconds: defaultTimeoutSeconds),
      () {
        if (!mounted || !_timeoutActive || _cachedIsRetrying || _cachedIsSwitchingChannel || _isDisposing) {
          _timeoutActive = false;
          return;
        }
        if (_playerController?.isPlaying() != true) {
          LogUtil.e('播放流程超时，切换下一源');
          _handleSourceSwitching();
          _timeoutActive = false;
        }
      }
    );
  }

  Future<void> _cleanupCurrentPlayer() async {
    if (_playerController != null) {
      await _playerController!.pause();
      await _releaseAllResources(); // 修改点4：直接调用 _releaseAllResources
      await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
    }

    if (!mounted) {
      LogUtil.i('组件已卸载，停止播放流程');
      throw Exception('组件已卸载');
    }
  }

  Future<void> _preparePlaybackUrl() async {
    String url = _currentChannel!.urls![_sourceIndex].toString();
    _originalUrl = url;

    await _disposeStreamUrl();

    _streamUrl = StreamUrl(url);
    String parsedUrl = await _streamUrl!.getStreamUrl();

    if (parsedUrl == 'ERROR') {
      LogUtil.e('地址解析失败: $url');
      _updatePlayState(
        message: S.current.vpnplayError,
        switching: false,
      );
      await _disposeStreamUrl();
      throw Exception('地址解析失败');
    }

    _updatePlayUrl(parsedUrl);
    bool isDirectAudio = _checkIsAudioStream(parsedUrl);
    _updatePlayState(parsing: false); // 修改点5：使用 _updatePlayState 更新 _isAudio
    _isAudio = isDirectAudio;

    LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $isDirectAudio, HLS: $_isHls');
  }

  /// 修改点6：添加 try-finally 确保资源释放
  Future<void> _setupPlayerController() async {
    final dataSource = BetterPlayerConfig.createDataSource(
      url: _currentPlayUrl!,
      isHls: _isHls,
    );
    final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
      eventListener: _videoListener,
      isHls: _isHls,
    );

    BetterPlayerController? tempController;
    try {
      tempController = BetterPlayerController(betterPlayerConfiguration);
      await tempController.setupDataSource(dataSource);
      LogUtil.i('播放器数据源设置完成');
      setState(() {
        _playerController = tempController;
      });
    } catch (e) {
      rethrow;
    } finally {
      if (_playerController != tempController) {
        tempController?.dispose();
      }
    }
  }

  Future<void> _startPlayback() async {
    await _playerController?.play();
    LogUtil.i('开始播放: $_currentPlayUrl');
    _timeoutActive = false;
    _timerManager.cancelTask(TimerType.timeout);
  }

  void _processPendingSwitch() {
    if (_pendingSwitch != null && !_cachedIsParsing && !_cachedIsRetrying) {
      final nextRequest = _pendingSwitch!;
      _currentChannel = nextRequest.channel;
      _sourceIndex = nextRequest.sourceIndex;
      _pendingSwitch = null;
      LogUtil.i('处理最新切换请求: ${_currentChannel?.title ?? "未知频道"}, 源索引: $_sourceIndex');
      Future.microtask(() => _playVideo());
    } else if (_pendingSwitch != null) {
      LogUtil.i('无法处理切换请求，因状态冲突: _isParsing=$_cachedIsParsing, _isRetrying=$_cachedIsRetrying');
    }
  }

  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) {
      LogUtil.e('切换频道失败：channel 为 null');
      return;
    }

    final safeSourceIndex = _getSafeSourceIndex(channel, sourceIndex);

    if (_cachedIsSwitchingChannel) {
      _pendingSwitch = SwitchRequest(channel, safeSourceIndex);
      LogUtil.i('更新最新切换请求: ${channel.title}, 源索引: $safeSourceIndex');

      _timerManager.addTask(
        TimerType.timeout,
        Duration(seconds: m3u8ConnectTimeoutSeconds),
        () {
          if (mounted && _cachedIsSwitchingChannel) {
            LogUtil.e('切换操作超时(${m3u8ConnectTimeoutSeconds}秒)，强制重置状态');
            _updatePlayState(switching: false);
            _processPendingSwitch();
          }
        }
      );
    } else {
      if (_playerController != null) {
        await _releaseAllResources();
        await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
      }
      _currentChannel = channel;
      _sourceIndex = safeSourceIndex;

      if (_currentChannel?.urls != null &&
          _sourceIndex >= 0 &&
          _sourceIndex < _currentChannel!.urls!.length) {
        _originalUrl = _currentChannel!.urls![_sourceIndex];
        LogUtil.i('切换频道/源 - 解析前地址: $_originalUrl');
        await _playVideo();
      } else {
        LogUtil.e('切换频道/源失败 - 无效的URL索引: $_sourceIndex');
        _updatePlayState(
          message: S.current.playError,
          playing: false,
          buffering: false,
        );
      }
    }
  }

  int _getSafeSourceIndex(PlayModel channel, int requestedIndex) {
    if (channel.urls == null || channel.urls!.isEmpty) {
      LogUtil.e('频道没有可用源');
      return 0;
    }
    return channel.urls!.length > requestedIndex ? requestedIndex : 0;
  }

  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted ||
        _playerController == null ||
        _isDisposing ||
        event.betterPlayerEventType == BetterPlayerEventType.changedPlayerVisibility ||
        event.betterPlayerEventType == BetterPlayerEventType.bufferingUpdate ||
        event.betterPlayerEventType == BetterPlayerEventType.changedTrack ||
        event.betterPlayerEventType == BetterPlayerEventType.setupDataSource ||
        event.betterPlayerEventType == BetterPlayerEventType.changedSubtitles) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (_shouldUpdateAspectRatio) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? defaultAspectRatio;
          if (aspectRatio != newAspectRatio) {
            setState(() {
              aspectRatio = newAspectRatio;
              _shouldUpdateAspectRatio = false;
            });
            LogUtil.i('初始化完成，更新宽高比: $newAspectRatio');
          }
        }
        break;

      case BetterPlayerEventType.exception:
        final error = event.parameters?["error"] as String? ?? "Unknown error";
        LogUtil.e('播放器异常: $error');

        if (_cachedIsParsing) {
          LogUtil.i('正在重新解析中，忽略本次异常，等待解析完成切换');
          return;
        }

        if (_isHls) {
          if (_preCachedUrl != null) {
            LogUtil.i('异常触发，预缓存地址已准备，立即切换');
            await _switchToPreCachedUrl('异常触发');
          } else {
            LogUtil.i('异常触发，预缓存地址未准备，等待解析');
            await _reparseAndSwitch();
          }
        } else {
          _retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        _updatePlayState(
          buffering: true,
          message: S.current.loading,
        );

        if (isPlaying) {
          _timerManager.cancelTask(TimerType.timeout);
          _timerManager.addTask(
            TimerType.bufferingCheck,
            const Duration(seconds: bufferingStartSeconds),
            () {
              if (!mounted || !isBuffering || _cachedIsRetrying || _cachedIsSwitchingChannel || _isDisposing || _cachedIsParsing || _pendingSwitch != null) {
                LogUtil.i('缓冲超时检查被阻止');
                return;
              }
              if (_playerController?.isPlaying() != true) {
                LogUtil.e('播放中缓冲超过15秒，触发重试');
                _retryPlayback(resetRetryCount: true);
              }
            }
          );
        }
        break;

      case BetterPlayerEventType.bufferingEnd:
        _updatePlayState(
          buffering: false,
          message: 'HIDE_CONTAINER',
          showPause: _isUserPaused ? false : _showPauseIconFromListener,
        );

        _timerManager.cancelTask(TimerType.bufferingCheck);
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          _updatePlayState(
            playing: true,
            message: isBuffering ? toastString : 'HIDE_CONTAINER',
            showPlay: false,
            showPause: false,
            userPaused: false,
          );

          _timerManager.cancelTask(TimerType.bufferingCheck);

          if (!_timerManager.isActive(TimerType.playDuration)) {
            _startPlayDurationTimer();
          }
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          _updatePlayState(
            playing: false,
            message: S.current.playpause,
            showPlay: _isUserPaused,
            showPause: !_isUserPaused,
          );

          LogUtil.i('播放暂停，用户触发: $_isUserPaused');
        }
        break;

      case BetterPlayerEventType.progress:
        if (_progressEnabled && isPlaying) {
          final position = event.parameters?["progress"] as Duration?;
          final duration = event.parameters?["duration"] as Duration?;

          if (position != null && duration != null) {
            final remainingTime = duration - position;

            if (_isHls && _preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
              LogUtil.i('HLS 剩余时间少于 $hlsSwitchThresholdSeconds 秒，切换到预缓存地址');
              await _switchToPreCachedUrl('HLS 剩余时间触发切换');
            }
            else if (!_isHls) {
              if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
                final nextUrl = _getNextVideoUrl();
                if (nextUrl != null && nextUrl != _preCachedUrl) {
                  LogUtil.i('非 HLS 剩余时间少于 $nonHlsPreloadThresholdSeconds 秒，预缓存下一源');
                  _preloadNextVideo(nextUrl);
                }
              }

              if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
                await _switchToPreCachedUrl('非 HLS 剩余时间少于 $nonHlsSwitchThresholdSeconds 秒');
              }
            }
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!_isHls && _preCachedUrl != null) {
          await _switchToPreCachedUrl('非 HLS 播放结束');
        } else if (_isHls) {
          LogUtil.i('HLS 流异常结束，重试播放');
          _retryPlayback();
        } else {
          LogUtil.i('无更多源可播放');
          _handleNoMoreSources();
        }
        break;

      default:
        break;
    }
  }

  Future<bool> _checkM3u8Validity() async {
    if (_currentPlayUrl == null || !_isHls) {
      return true;
    }

    try {
      final String? content = await HttpUtil().getRequest<String>(
        _currentPlayUrl!,
        options: Options(
          extra: {
            'connectTimeout': const Duration(seconds: m3u8ConnectTimeoutSeconds),
            'receiveTimeout': const Duration(seconds: m3u8ReceiveTimeoutSeconds),
          },
        ),
        retryCount: 1,
      );

      if (content == null || content.isEmpty) {
        LogUtil.e('m3u8 内容为空或获取失败：$_currentPlayUrl');
        return false;
      }

      bool hasSegments = content.contains('.ts');
      bool hasValidDirectives = content.contains('#EXTINF') || content.contains('#EXT-X-STREAM-INF');

      bool isValid = hasSegments || hasValidDirectives;

      if (!isValid) {
        LogUtil.e('m3u8 内容无效，不包含有效标记或片段');
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('m3u8 有效性检查出错', e, stackTrace);
      return false;
    }
  }

  void _startM3u8CheckTimer() {
    _timerManager.cancelTask(TimerType.m3u8Check);

    if (!_isHls) return;

    _timerManager.addTask(
      TimerType.m3u8Check,
      const Duration(seconds: m3u8CheckIntervalSeconds),
      () async {
        if (!mounted || !_isHls || !isPlaying || _isDisposing || _cachedIsParsing) return;

        final isValid = await _checkM3u8Validity();
        if (!isValid) {
          _m3u8InvalidCount++;
          LogUtil.i('m3u8 检查失效，次数: $_m3u8InvalidCount');

          if (_m3u8InvalidCount == 1) {
            LogUtil.i('第一次检测到 m3u8 失效，等待 $m3u8InvalidConfirmDelaySeconds 秒后再次检查');
            _timerManager.addTask(
              TimerType.retry,
              Duration(seconds: m3u8InvalidConfirmDelaySeconds),
              () async {
                if (!mounted || !_isHls || !isPlaying || _isDisposing || _cachedIsParsing) {
                  _m3u8InvalidCount = 0;
                  return;
                }
                final secondCheck = await _checkM3u8Validity();
                if (!secondCheck) {
                  LogUtil.i('第二次检查确认 m3u8 失效，触发重新解析');
                  await _reparseAndSwitch();
                } else {
                  _m3u8InvalidCount = 0;
                }
              },
            );
          } else if (_m3u8InvalidCount >= 2) {
            LogUtil.i('连续两次检查到 m3u8 失效，触发重新解析');
            await _reparseAndSwitch();
            _m3u8InvalidCount = 0;
          }
        } else {
          _m3u8InvalidCount = 0;
        }
      },
    );
  }

  void _startPlayDurationTimer() {
    _timerManager.cancelTask(TimerType.playDuration);
    _timerManager.addTask(
      TimerType.playDuration,
      const Duration(seconds: initialProgressDelaySeconds),
      () {
        if (mounted && !_cachedIsRetrying && !_cachedIsSwitchingChannel && !_isDisposing) {
          LogUtil.i('播放 $initialProgressDelaySeconds 秒，开始检查逻辑');

          if (_isHls) {
            if (_originalUrl != null && _originalUrl!.toLowerCase().contains('timelimit')) {
              _startM3u8CheckTimer();
              LogUtil.i('HLS 流包含 timelimit，启用 m3u8 检查定时器');
            }
          } else {
            if (_getNextVideoUrl() != null) {
              _progressEnabled = true;
              LogUtil.i('非 HLS 流，启用 progress 监听');
            }
          }

          _retryCount = 0;
        }
      },
    );
  }

  Future<void> _preloadNextVideo(String url) async {
    if (!enableNonHlsPreload) return;

    if (!_canPerformOperation('预加载下一个视频', 
        checkDisposing: true, 
        checkSwitching: true, 
        checkRetrying: false, 
        checkParsing: false)) {
      return;
    }
    
    if (_playerController == null || _preCachedUrl != null) {
      LogUtil.i('预加载被阻止: controller=${_playerController != null}, _preCachedUrl=${_preCachedUrl != null}');
      return;
    }

    try {
      LogUtil.i('开始预加载: $url');

      await _disposePreCacheStreamUrl();

      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();

      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposePreCacheStreamUrl();
        return;
      }

      _preCachedUrl = parsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl');

      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl),
        url: parsedUrl,
      );

      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl();
    }
  }

  void _retryPlayback({bool resetRetryCount = false}) {
    if (!_canPerformOperation('重试播放')) {
      return;
    }

    if (_cachedIsParsing) {
      LogUtil.i('正在重新解析中，跳过重试，等待解析完成切换');
      return;
    }

    _timerManager.cancelAll();

    if (resetRetryCount) {
      _updatePlayState(retryCount: 0);
    }

    if (_retryCount < defaultMaxRetries) {
      _updatePlayState(
        buffering: false,
        message: S.current.retryplay,
        showPlay: false,
        showPause: false,
        retrying: true,
        retryCount: _retryCount + 1,
      );

      LogUtil.i('重试播放: 第 $_retryCount 次');

      _timerManager.addTask(
        TimerType.retry,
        const Duration(seconds: retryDelaySeconds),
        () async {
          if (!mounted || _cachedIsSwitchingChannel || _isDisposing || _cachedIsParsing) {
            _updatePlayState(retrying: false);
            return;
          }

          await _playVideo(isRetry: true);

          if (mounted) {
            _updatePlayState(retrying: false);
          }
        }
      );
    } else {
      LogUtil.i('重试次数达上限，切换下一源');
      _handleSourceSwitching();
    }
  }

  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null) return null;

    final List<String> urls = _currentChannel!.urls!;
    if (urls.isEmpty) return null;

    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) return null;

    return urls[nextSourceIndex];
  }

  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_cachedIsRetrying || _isDisposing) return;

    _timerManager.cancelAll();

    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      LogUtil.i('无更多源可切换');
      _handleNoMoreSources();
      return;
    }

    _updatePlayState(
      sourceIndex: _sourceIndex + 1,
      retrying: false,
      retryCount: 0,
      buffering: false,
      message: S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? ''),
    );
    _preCachedUrl = null;

    LogUtil.i('切换到下一源: $nextUrl');
    _startNewSourceTimer();
  }

  Future<void> _handleNoMoreSources() async {
    _updatePlayState(
      message: S.current.playError,
      playing: false,
      buffering: false,
      showPlay: false,
      showPause: false,
      sourceIndex: 0,
      retrying: false,
      retryCount: 0,
    );

    await _releaseAllResources();
    LogUtil.i('播放结束，无更多源');
  }

  void _startNewSourceTimer() {
    _timerManager.cancelAll();
    _timerManager.addTask(
      TimerType.retry,
      const Duration(seconds: retryDelaySeconds),
      () async {
        if (!mounted || _cachedIsSwitchingChannel) return;
        await _playVideo(isSourceSwitch: true);
      }
    );
  }

  Future<void> _releaseAllResources({bool isDisposing = false}) async {
    if (_isDisposing) return;
    _isDisposing = true;
    
    try {
      LogUtil.i('开始释放所有资源');
      
      _timerManager.cancelAll();
      
      if (_playerController != null) {
        try {
          _playerController!.removeEventsListener(_videoListener);
          
          if (_playerController!.isPlaying() ?? false) {
            await _playerController!.pause();
            await _playerController!.setVolume(0);
          }
          
          if (_playerController!.videoPlayerController != null) {
            await _playerController!.videoPlayerController!.dispose();
          }
          
          _playerController!.dispose(); 
          _playerController = null;
        } catch (e, stackTrace) {
          LogUtil.logError('释放播放器资源失败', e, stackTrace);
        }
      }
      
      await _disposeStreamUrl();
      await _disposePreCacheStreamUrl();
      
      if (mounted && !isDisposing) {
        _updatePlayState(
          playing: false,
          buffering: false,
          retrying: false,
          parsing: false,
          switching: false,
          showPlay: false,
          showPause: false,
          userPaused: false,
        );
        
        _progressEnabled = false;
        _preCachedUrl = null;
        _lastParseTime = null;
        _currentPlayUrl = null;
        _originalUrl = null;
        _m3u8InvalidCount = 0;
      }
      
      LogUtil.i('所有资源已释放');
    } catch (e, stackTrace) {
      LogUtil.logError('释放资源过程中发生错误', e, stackTrace);
    } finally {
      _isDisposing = isDisposing;
    }
  }

  /// 修改点7：移除 _cleanupController，改为直接调用 _releaseAllResources
  // Future<void> _cleanupController(BetterPlayerController? controller) async {
  //   if (controller == null) return;
  //   await _releaseAllResources();
  // }

  Future<void> _disposeStreamUrlInstance(StreamUrl? instance) async {
    if (instance != null) {
      await instance.dispose();
      LogUtil.i('StreamUrl 实例已释放');
    }
  }

  Future<void> _disposeStreamUrl() async {
    await _disposeStreamUrlInstance(_streamUrl);
    _streamUrl = null;
  }

  Future<void> _disposePreCacheStreamUrl() async {
    await _disposeStreamUrlInstance(_preCacheStreamUrl);
    _preCacheStreamUrl = null;
  }

  Future<void> _reparseAndSwitch({bool force = false}) async {
    if (!_canPerformOperation('重新解析')) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastParseTime != null) {
      final timeSinceLastParse = now - _lastParseTime!;
      
      if (timeSinceLastParse < reparseMinIntervalMilliseconds) {
        final remainingWaitTime = reparseMinIntervalMilliseconds - timeSinceLastParse;
        LogUtil.i('解析频率过高，延迟 ${remainingWaitTime}ms 后解析');
        
        _timerManager.addTask(
          TimerType.retry, 
          Duration(milliseconds: remainingWaitTime.toInt()), 
          () {
            if (mounted) _reparseAndSwitch(force: true);
          }
        );
        return;
      }
    }

    _timerManager.cancelAll();
    _updatePlayState(
      parsing: true,
      retrying: true
    );

    try {
      if (_currentChannel == null || _currentChannel!.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
        LogUtil.e('重新解析时频道信息无效');
        throw Exception('无效的频道信息');
      }

      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');

      await _disposeStreamUrl();

      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();

      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeStreamUrl();
        throw Exception('解析失败');
      }

      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeStreamUrl();
        return;
      }

      _preCachedUrl = newParsedUrl;
      LogUtil.i('预缓存地址已准备: $_preCachedUrl');

      if (_playerController != null) {
        if (_isDisposing || _cachedIsSwitchingChannel) {
          LogUtil.i('预加载前检测到中断，退出重新解析');
          _preCachedUrl = null;
          await _disposeStreamUrl();
          return;
        }

        await _preparePreCacheSource(newParsedUrl);

        if (_isDisposing || _cachedIsSwitchingChannel) {
          LogUtil.i('预加载完成后检测到中断，退出重新解析');
          _preCachedUrl = null;
          await _disposeStreamUrl();
          return;
        }

        _progressEnabled = true;
        _lastParseTime = now;
        LogUtil.i('预缓存完成，等待剩余时间或异常触发切换');
      } else {
        LogUtil.i('播放器控制器为空，无法切换');
        _handleSourceSwitching();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      await _disposeStreamUrl();
      _handleSourceSwitching();
    } finally {
      _updatePlayState(
        parsing: false,
        retrying: false
      );
      LogUtil.i('重新解析结束');
    }
  }

  Map<String, String?> _getLocationInfo(String? userInfo) {
    if (userInfo == null || userInfo.isEmpty) {
      LogUtil.i('用户地理信息为空，使用默认顺序');
      return {'region': null, 'city': null};
    }
    try {
      final Map<String, dynamic> userData = jsonDecode(userInfo);
      final Map<String, dynamic>? locationData = userData['info']?['location'];
      final String? region = locationData?['region'] as String?;
      final String? city = locationData?['city'] as String?;

      final String? regionPrefix = region != null && region.isNotEmpty
          ? (region.length >= 2 ? region.substring(0, 2) : region)
          : null;
      final String? cityPrefix = city != null && city.isNotEmpty
          ? (city.length >= 2 ? city.substring(0, 2) : city)
          : null;

      LogUtil.i('获取地理信息 - 地区: $region (前缀: $regionPrefix), 城市: $city (前缀: $cityPrefix)');
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e) {
      LogUtil.e('解析地理信息失败: $e');
      return {'region': null, 'city': null};
    }
  }

  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix == null || prefix.isEmpty) {
      LogUtil.i('地理前缀为空，返回原始顺序: $items');
      return items;
    }
    if (items.isEmpty) {
      LogUtil.i('待排序列表为空，返回空列表');
      return items;
    }

    items.sort((a, b) {
      final aMatches = a.startsWith(prefix);
      final bMatches = b.startsWith(prefix);
      if (aMatches && !bMatches) return -1;
      if (!aMatches && bMatches) return 1;
      return a.compareTo(b);
    });

    LogUtil.i('排序结果: $items');
    return items;
  }

  void _sortVideoMap(PlaylistModel videoMap, String? userInfo) {
    if (videoMap.playList == null || videoMap.playList!.isEmpty) {
      LogUtil.e('播放列表为空，无需排序');
      return;
    }

    final location = _getLocationInfo(userInfo);
    final String? regionPrefix = location['region'];
    final String? cityPrefix = location['city'];

    if (regionPrefix == null || regionPrefix.isEmpty) {
      LogUtil.i('地区前缀为空，跳过排序');
      return;
    }

    videoMap.playList!.forEach((category, groups) {
      if (groups is! Map<String, Map<String, PlayModel>>) {
        LogUtil.e('分类 $category 的 groups 类型无效: ${groups.runtimeType}');
        return;
      }

      final groupList = groups.keys.toList();
      bool categoryNeedsSort = groupList.any((group) => group.contains(regionPrefix));
      if (!categoryNeedsSort) {
        return;
      }

      final sortedGroups = _sortByGeoPrefix(groupList, regionPrefix);
      final newGroups = <String, Map<String, PlayModel>>{};

      for (var group in sortedGroups) {
        final channels = groups[group];
        if (channels is! Map<String, PlayModel>) {
          LogUtil.e('组 $group 的 channels 类型无效: ${channels.runtimeType}');
          continue;
        }

        final channelList = channels.keys.toList();
        final newChannels = <String, PlayModel>{};

        if (group.contains(regionPrefix) && (cityPrefix != null && cityPrefix.isNotEmpty)) {
          final sortedChannels = _sortByGeoPrefix(channelList, cityPrefix);
          for (var channel in sortedChannels) {
            newChannels[channel] = channels[channel]!;
          }
        } else {
          for (var channel in channelList) {
            newChannels[channel] = channels[channel]!;
          }
        }
        newGroups[group] = newChannels;
      }
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成: ${newGroups.keys.toList()}');
    });
  }

  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;

    try {
      _updatePlayState(
        buffering: false,
        message: S.current.loading,
        retrying: false,
        retryCount: 0,
      );
      _timerManager.cancelAll();
      _currentChannel = model;
      _sourceIndex = 0;
      _shouldUpdateAspectRatio = true;

      await _queueSwitchChannel(_currentChannel, _sourceIndex);

      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      _updatePlayState(message: S.current.playError);
      await _releaseAllResources();
    }
  }

  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) {
      LogUtil.e('未找到有效视频源');
      return;
    }

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null) {
      _updatePlayState(
        sourceIndex: selectedIndex,
        retrying: false,
        retryCount: 0,
      );
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
    }
  }

  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      setState(() => _drawerIsOpen = false);
      return false;
    }

    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) await _playerController?.pause();

    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    if (!shouldExit && wasPlaying && mounted) await _playerController?.play();
    return shouldExit;
  }

  void _handleUserPaused() {
    _updatePlayState(userPaused: true);
  }

  void _handleRetry() {
    _retryPlayback(resetRetryCount: true);
  }

  @override
  void initState() {
    super.initState();
    _adManager = AdManager();
    _adManager.loadAdData();
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    _loadData();
    _extractFavoriteList();
  }

  @override
  void dispose() {
    _releaseAllResources(isDisposing: true);
    _adManager.dispose();
    super.dispose();
  }

  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        bool? isFirstInstall = SpUtil.getBool('is_first_install');
        bool isTV = context.watch<ThemeProvider>().isTV;

        String deviceType = isTV ? "TV" : "Other";

        if (isFirstInstall == null) {
          await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: deviceType);
          await SpUtil.putBool('is_first_install', true);
        } else {
          await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: channelName);
        }
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计失败', e, stackTrace);
      }
    }
  }

  Future<void> _loadData() async {
    _updatePlayState(
      retrying: false,
      retryCount: 0,
    );
    _timerManager.cancelAll();
    setState(() => _isAudio = false);

    if (widget.m3uData.playList == null || widget.m3uData.playList!.isEmpty) {
      LogUtil.e('播放列表无效');
      setState(() => toastString = S.current.getDefaultError);
      return;
    }

    try {
      _videoMap = widget.m3uData;
      String? userInfo = SpUtil.getString('user_all_info');
      LogUtil.i('原始 user_all_info: $userInfo');
      _sortVideoMap(_videoMap!, userInfo);
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表失败', e, stackTrace);
      setState(() => toastString = S.current.parseError);
    }
  }

  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
        if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);

        _updatePlayState(
          retryCount: 0,
        );
        _timeoutActive = false;
        _queueSwitchChannel(_currentChannel, _sourceIndex);
      } else {
        _updatePlayState(
          message: 'UNKNOWN',
          retrying: false,
        );
      }
    } else {
      _updatePlayState(
        message: 'UNKNOWN',
        retrying: false,
      );
      _currentChannel = null;
    }
  }

  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    try {
      for (final categoryEntry in playList.entries) {
        final categoryData = categoryEntry.value;
        if (categoryData is Map<String, Map<String, PlayModel>>) {
          for (final groupEntry in categoryData.entries) {
            final channelMap = groupEntry.value;
            for (final channel in channelMap.values) {
              if (channel?.urls != null && channel!.urls!.isNotEmpty) {
                return channel;
              }
            }
          }
        } else if (categoryData is Map<String, PlayModel>) {
          for (final channel in categoryData.values) {
            if (channel?.urls != null && channel!.urls!.isNotEmpty) {
              return channel;
            }
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取频道失败', e, stackTrace);
    }
    return null;
  }

  void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
    }
  }

  String getGroupName(String channelId) => _currentChannel?.group ?? '';
  String getChannelName(String channelId) => _currentChannel?.title ?? '';
  String _getSourceDisplayName(String url, int index) {
    if (url.contains('\$')) return url.split('\$')[1].trim();
    return S.current.lineIndex(index + 1);
  }
  List<String> getPlayUrls(String channelId) => _currentChannel?.urls ?? [];
  bool isChannelFavorite(String channelId) {
    String groupName = getGroupName(channelId);
    String channelName = getChannelName(channelId);
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
  }

  void toggleFavorite(String channelId) async {
    bool isFavoriteChanged = false;
    String actualChannelId = _currentChannel?.id ?? channelId;
    String groupName = getGroupName(actualChannelId);
    String channelName = getChannelName(actualChannelId);

    if (groupName.isEmpty || channelName.isEmpty) {
      CustomSnackBar.showSnackBar(context, S.current.channelnofavorite, duration: Duration(seconds: snackBarDurationSeconds));
      return;
    }

    if (isChannelFavorite(actualChannelId)) {
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
      CustomSnackBar.showSnackBar(context, S.current.removefavorite, duration: Duration(seconds: snackBarDurationSeconds));
      isFavoriteChanged = true;
    } else {
      if (favoriteList[Config.myFavoriteKey]![groupName] == null) {
        favoriteList[Config.myFavoriteKey]![groupName] = {};
      }
      PlayModel newFavorite = PlayModel(
        id: actualChannelId,
        group: groupName,
        logo: _currentChannel?.logo,
        title: channelName,
        urls: getPlayUrls(actualChannelId),
      );
      favoriteList[Config.myFavoriteKey]![groupName]![channelName] = newFavorite;
      CustomSnackBar.showSnackBar(context, S.current.newfavorite, duration: Duration(seconds: snackBarDurationSeconds));
      isFavoriteChanged = true;
    }

    if (isFavoriteChanged) {
      try {
        await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
        _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
        LogUtil.i('更新收藏列表: $_videoMap');
        if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: snackBarDurationSeconds));
        LogUtil.logError('保存收藏失败', error);
      }
    }
  }

  Future<void> _parseData() async {
    try {
      if (_videoMap == null || _videoMap!.playList == null || _videoMap!.playList!.isEmpty) {
        LogUtil.e('播放列表无效');
        setState(() => toastString = S.current.getDefaultError);
        return;
      }
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('处理播放列表失败', e, stackTrace);
      setState(() => toastString = S.current.parseError);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;

    if (isTV) {
      return TvPage(
        videoMap: _videoMap,
        playModel: _currentChannel,
        onTapChannel: _onTapChannel,
        toastString: toastString,
        controller: _playerController,
        isBuffering: isBuffering,
        isPlaying: isPlaying,
        aspectRatio: aspectRatio,
        onChangeSubSource: _parseData,
        changeChannelSources: _changeChannelSources,
        toggleFavorite: toggleFavorite,
        isChannelFavorite: isChannelFavorite,
        currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
        currentChannelLogo: _currentChannel?.logo ?? '',
        currentChannelTitle: _currentChannel?.title ?? _currentChannel?.id ?? '',
        isAudio: _isAudio,
        adManager: _adManager,
      );
    }

    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: MobileVideoWidget(
              toastString: toastString,
              controller: _playerController,
              changeChannelSources: _changeChannelSources,
              isLandscape: false,
              isBuffering: isBuffering,
              isPlaying: isPlaying,
              aspectRatio: aspectRatio,
              onChangeSubSource: _parseData,
              drawChild: ChannelDrawerPage(
                key: _drawerRefreshKey,
                refreshKey: _drawerRefreshKey,
                videoMap: _videoMap,
                playModel: _currentChannel,
                onTapChannel: _onTapChannel,
                isLandscape: false,
                onCloseDrawer: () => setState(() => _drawerIsOpen = false),
              ),
              toggleFavorite: toggleFavorite,
              currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
              currentChannelLogo: _currentChannel?.logo ?? '',
              currentChannelTitle: _currentChannel?.title ?? _currentChannel?.id ?? '',
              isChannelFavorite: isChannelFavorite,
              isAudio: _isAudio,
              adManager: _adManager,
              showPlayIcon: _showPlayIcon,
              showPauseIconFromListener: _showPauseIconFromListener,
              isHls: _isHls,
              onUserPaused: _handleUserPaused,
              onRetry: _handleRetry,
            ),
          );
        },
        landscape: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: Stack(
              children: [
                Scaffold(
                  body: toastString == 'UNKNOWN'
                      ? EmptyPage(onRefresh: _loadData)
                      : TableVideoWidget(
                          toastString: toastString,
                          controller: _playerController,
                          isBuffering: isBuffering,
                          isPlaying: isPlaying,
                          aspectRatio: aspectRatio,
                          drawerIsOpen: _drawerIsOpen,
                          changeChannelSources: _changeChannelSources,
                          isChannelFavorite: isChannelFavorite,
                          currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
                          currentChannelLogo: _currentChannel?.logo ?? '',
                          currentChannelTitle: _currentChannel?.title ?? _currentChannel?.id ?? '',
                          toggleFavorite: toggleFavorite,
                          isLandscape: true,
                          isAudio: _isAudio,
                          onToggleDrawer: () => setState(() => _drawerIsOpen = !_drawerIsOpen),
                          adManager: _adManager,
                          showPlayIcon: _showPlayIcon,
                          showPauseIconFromListener: _showPauseIconFromListener,
                          isHls: _isHls,
                          onUserPaused: _handleUserPaused,
                          onRetry: _handleRetry,
                        ),
                ),
                Offstage(
                  offstage: !_drawerIsOpen,
                  child: GestureDetector(
                    onTap: () => setState(() => _drawerIsOpen = false),
                    child: ChannelDrawerPage(
                      key: _drawerRefreshKey,
                      refreshKey: _drawerRefreshKey,
                      videoMap: _videoMap,
                      playModel: _currentChannel,
                      onTapChannel: _onTapChannel,
                      isLandscape: true,
                      onCloseDrawer: () => setState(() => _drawerIsOpen = false),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
