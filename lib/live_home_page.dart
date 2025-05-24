import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider/theme_provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:better_player_plus/better_player_plus.dart';
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
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/util/channel_util.dart';
import 'package:itvapp_live_tv/util/traffic_analytics.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/zhConverter.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 主页面，展示直播内容
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 直播播放列表数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

// 计时器类型，管理不同计时任务
enum TimerType {
  retry,        // 重试任务
  m3u8Check,    // m3u8有效性检查
  playDuration, // 播放时长监测
  timeout,      // 超时检测
  bufferingCheck, // 缓冲状态检查
  switchTimeout,  // 频道切换超时
}

// 频道切换请求，封装目标频道与源索引
class SwitchRequest {
  final PlayModel? channel; // 目标频道
  final int sourceIndex;    // 源索引
  SwitchRequest(this.channel, this.sourceIndex);
}

// 计时器管理，统一控制计时任务
class TimerManager {
  final Map<TimerType, Timer?> _timers = {}; // 计时器映射

  // 启动单次计时器
  void startTimer(TimerType type, Duration duration, Function() callback) {
    cancelTimer(type);
    _timers[type] = Timer(duration, () {
      callback();
      _timers[type] = null;
    });
  }

  // 启动周期性计时器
  void startPeriodicTimer(TimerType type, Duration period, Function(Timer) callback) {
    cancelTimer(type);
    _timers[type] = Timer.periodic(period, callback);
  }

  // 取消指定计时器
  void cancelTimer(TimerType type) => _timers[type]?.cancel();

  // 取消所有计时器
  void cancelAll() {
    _timers.forEach((_, timer) => timer?.cancel());
    _timers.clear();
  }

  // 检查计时器是否活跃
  bool isActive(TimerType type) => _timers[type]?.isActive == true;
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int defaultMaxRetries = 1; // 最大重试次数
  static const int defaultTimeoutSeconds = 58; // 超时时间（秒）
  static const int initialProgressDelaySeconds = 60; // 初始进度检查延迟（秒）
  static const int retryDelaySeconds = 2; // 重试延迟（秒）
  static const int hlsSwitchThresholdSeconds = 3; // HLS切换阈值（秒）
  static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS预加载阈值（秒）
  static const int nonHlsSwitchThresholdSeconds = 3; // 非HLS切换阈值（秒）
  static const double defaultAspectRatio = 1.78; // 默认宽高比
  static const int cleanupDelayMilliseconds = 500; // 切换清理延迟（毫秒）
  static const int snackBarDurationSeconds = 5; // 提示条显示时长（秒）
  static const int m3u8InvalidConfirmDelaySeconds = 1; // m3u8失效确认延迟（秒）
  static const int m3u8CheckIntervalSeconds = 10; // m3u8检查间隔（秒）
  static const int reparseMinIntervalMilliseconds = 10000; // m3u8重新解析间隔（毫秒）
  static const int m3u8ConnectTimeoutSeconds = 5; // m3u8连接超时（秒）
  static const int m3u8ReceiveTimeoutSeconds = 10; // m3u8接收超时（秒）
  static const int maxSwitchAttempts = 3; // 最大切换尝试次数

  String? _preCachedUrl; // 预缓存播放地址
  bool _isParsing = false; // 是否正在解析
  bool _isRetrying = false; // 是否正在重试
  int? _lastParseTime; // 上次解析时间戳
  String toastString = S.current.loading; // 当前提示信息
  PlaylistModel? _videoMap; // 视频播放列表
  PlayModel? _currentChannel; // 当前播放频道
  int _sourceIndex = 0; // 当前源索引
  BetterPlayerController? _playerController; // 播放器控制器
  bool isBuffering = false; // 是否正在缓冲
  bool isPlaying = false; // 是否正在播放
  double aspectRatio = defaultAspectRatio; // 当前宽高比
  bool _drawerIsOpen = false; // 抽屉菜单是否打开
  int _retryCount = 0; // 当前重试次数
  bool _timeoutActive = false; // 超时检测是否激活
  bool _isDisposing = false; // 是否正在释放资源
  bool _isSwitchingChannel = false; // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 是否需要更新宽高比
  StreamUrl? _streamUrl; // 当前流地址实例
  StreamUrl? _preCacheStreamUrl; // 预缓存流地址实例
  String? _currentPlayUrl; // 当前播放地址
  String? _originalUrl; // 原始播放地址
  bool _progressEnabled = false; // 是否启用进度检查
  bool _isHls = false; // 是否为HLS流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{}, // 收藏列表
  };
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析实例
  bool _isAudio = false; // 是否为音频流
  late AdManager _adManager; // 广告管理实例
  bool _isUserPaused = false; // 用户是否暂停
  bool _showPlayIcon = false; // 是否显示播放图标
  bool _showPauseIconFromListener = false; // 是否显示暂停图标（监听触发）
  int _m3u8InvalidCount = 0; // m3u8失效计数
  int _switchAttemptCount = 0; // 切换尝试计数
  ZhConverter? _s2tConverter; // 简体转繁体转换器
  ZhConverter? _t2sConverter; // 繁体转简体转换器
  bool _zhConvertersInitializing = false; // 是否正在初始化中文转换器
  bool _zhConvertersInitialized = false; // 中文转换器是否初始化完成
  final TimerManager _timerManager = TimerManager(); // 计时器管理实例
  SwitchRequest? _pendingSwitch; // 待处理切换请求
  Timer? _debounceTimer; // 防抖定时器
  bool _hasInitializedAdManager = false; // 广告管理器初始化状态
  String? _lastPlayedChannelId; // 最后播放频道ID
  late CancelToken _currentCancelToken; // 当前解析任务的CancelToken
  late CancelToken _preloadCancelToken; // 预加载任务的CancelToken

  // 获取频道logo，默认返回预设logo
  String _getChannelLogo() => 
      _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png';

  // 验证URL格式是否符合指定类型
  bool _checkUrlFormat(String? url, List<String> formats) {
    if (url?.isEmpty ?? true) return false;
    return formats.any(url!.toLowerCase().contains);
  }

  // 判断是否为音频流
  bool _checkIsAudioStream(String? url) => !Config.videoPlayMode;

  // 判断是否为HLS流
  bool _isHlsStream(String? url) {
    if (_checkUrlFormat(url, ['.m3u8'])) return true;
    return !_checkUrlFormat(url, [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac', '.flv', 'rtmp:'
    ]);
  }

  // 更新播放地址并检测流类型
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  // 批量更新播放状态，优化UI渲染
  void _updatePlayState({
    bool? playing, bool? buffering, String? message, bool? showPlay, bool? showPause,
    bool? userPaused, bool? switching, bool? retrying, bool? parsing, int? sourceIndex, int? retryCount,
  }) {
    if (!mounted) return;
    setState(() {
      if (playing != null) isPlaying = playing;
      if (buffering != null) isBuffering = buffering;
      if (message != null) toastString = message;
      if (showPlay != null) _showPlayIcon = showPlay;
      if (showPause != null) _showPauseIconFromListener = showPause;
      if (userPaused != null) _isUserPaused = userPaused;
      if (switching != null) _isSwitchingChannel = switching;
      if (retrying != null) _isRetrying = retrying;
      if (parsing != null) _isParsing = parsing;
      if (sourceIndex != null) _sourceIndex = sourceIndex;
      if (retryCount != null) _retryCount = retryCount;
    });
  }

  // 检查操作可执行性，防止状态冲突
  bool _canPerformOperation(String operationName, {
    bool checkRetrying = true, bool checkSwitching = true, bool checkDisposing = true, bool checkParsing = true,
  }) {
    if (checkDisposing && _isDisposing) {
      LogUtil.i('$operationName 阻止: 资源释放中');
      return false;
    }
    List<String> blockers = [];
    if (checkRetrying && _isRetrying) blockers.add('重试中');
    if (checkSwitching && _isSwitchingChannel) blockers.add('频道切换中');
    if (checkParsing && _isParsing) blockers.add('解析中');
    if (blockers.isNotEmpty) {
      LogUtil.i('$operationName 阻止: ${blockers.join(", ")}');
      return false;
    }
    return true;
  }

  // 取消当前解析任务
  void _cancelCurrentTask() {
    try {
      if (!_currentCancelToken.isCancelled) {
        _currentCancelToken.cancel('频道切换或超时');
        LogUtil.i('取消当前解析任务');
      }
    } catch (e) {
      LogUtil.i('当前任务CancelToken未初始化或已取消');
    }
  }

  // 取消预加载任务
  void _cancelPreloadTask() {
    try {
      if (!_preloadCancelToken.isCancelled) {
        _preloadCancelToken.cancel('频道切换或新预加载');
        LogUtil.i('取消预加载任务');
      }
    } catch (e) {
      LogUtil.i('预加载任务CancelToken未初始化或已取消');
    }
  }

  // 准备预缓存数据源
  Future<void> _preparePreCacheSource(String url) async {
    if (_playerController == null) {
      LogUtil.e('预缓存失败: 播放器控制器为空');
      return;
    }
    final newSource = BetterPlayerConfig.createDataSource(
      isHls: _isHlsStream(url),
      url: url,
      channelTitle: _currentChannel?.title,
      channelLogo: _getChannelLogo(),
    );
    await _playerController!.preCache(newSource);
  }

  // 清理预缓存资源
  Future<void> _cleanupPreCacheResources() async {
    _preCachedUrl = null;
    if (_preCacheStreamUrl != null) {
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
    }
  }

  // 切换到预缓存地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
    if (_isDisposing || _preCachedUrl == null) {
      LogUtil.i('$logDescription: ${_isDisposing ? "资源释放中" : "预缓存地址为空"}，跳过切换');
      return;
    }
    _timerManager.cancelTimer(TimerType.timeout);
    _timerManager.cancelTimer(TimerType.retry);
    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址与当前地址相同，重新解析');
      await _cleanupPreCacheResources();
      await _reparseAndSwitch();
      return;
    }
    try {
      _updatePlayState(switching: true);
      if (_playerController == null) {
        LogUtil.e('$logDescription: 播放器控制器为空');
        return;
      }
      await _preparePreCacheSource(_preCachedUrl!);
      LogUtil.i('$logDescription: 预缓存新数据源: $_preCachedUrl');
      final newSource = BetterPlayerConfig.createDataSource(
        url: _preCachedUrl!,
        isHls: _isHlsStream(_preCachedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      await _playerController?.setupDataSource(newSource);
      await _playerController?.play();
      LogUtil.i('$logDescription: 切换到预缓存地址并播放');
      _startPlayDurationTimer();
      _updatePlayUrl(_preCachedUrl!);
      _updatePlayState(playing: true, switching: false);
      _switchAttemptCount = 0;
    } catch (e, stackTrace) {
      LogUtil.logError('$logDescription: 切换预缓存地址失败', e, stackTrace);
      _retryPlayback();
    } finally {
      _updatePlayState(switching: false);
      _progressEnabled = false;
      await _cleanupPreCacheResources();
    }
  }

  // 执行视频播放流程
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null || !_isSourceIndexValid()) {
      LogUtil.e('播放失败: ${_currentChannel == null ? "频道为空" : "源索引无效"}');
      return;
    }
    bool isChannelChange = !isSourceSwitch || (_lastPlayedChannelId != _currentChannel!.id);
    String channelId = _currentChannel?.id ?? _currentChannel!.title ?? 'unknown_channel';
    _lastPlayedChannelId = channelId;
    if (isChannelChange) _adManager.onChannelChanged(channelId);
    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('播放频道: ${_currentChannel!.title}, 源: $sourceName');
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.timeout);
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
      if (!isRetry && !isSourceSwitch && isChannelChange && _hasInitializedAdManager) {
        try {
          bool shouldPlay = await _adManager.shouldPlayVideoAdAsync();
          if (shouldPlay) {
            await _adManager.playVideoAd();
            LogUtil.i('视频广告播放完成');
          }
        } catch (e) {
          LogUtil.e('视频广告处理错误: $e');
        }
      }
      if (_playerController != null) await _releaseAllResources(isDisposing: false);
      await _preparePlaybackUrl();
      await _setupPlayerController();
      await _startPlayback();
      _switchAttemptCount = 0;
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      _switchAttemptCount++;
      if (_switchAttemptCount <= maxSwitchAttempts) {
        _handleSourceSwitching();
      } else {
        _switchAttemptCount = 0;
        _updatePlayState(message: S.current.playError, playing: false, buffering: false, retrying: false, switching: false);
      }
    } finally {
      if (mounted) {
        _updatePlayState(switching: false);
        _timerManager.cancelTimer(TimerType.switchTimeout);
        _processPendingSwitch();
      }
    }
  }

  // 验证源索引有效性
  bool _isSourceIndexValid() {
    if (_sourceIndex < 0 || _currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
      _sourceIndex = 0;
      if (_currentChannel?.urls?.isEmpty ?? true) {
        LogUtil.e('频道无可用源');
        _updatePlayState(message: S.current.playError, playing: false, buffering: false, showPlay: false, showPause: false);
        return false;
      }
    }
    return true;
  }

  // 启动播放超时检测
  void _startPlaybackTimeout() {
    _timeoutActive = true;
    _timerManager.startTimer(
      TimerType.timeout,
      Duration(seconds: defaultTimeoutSeconds),
      () {
        if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
          _timeoutActive = false;
          return;
        }
        if (_playerController?.isPlaying() != true) {
          _handleSourceSwitching();
          _timeoutActive = false;
        }
      },
    );
  }

  // 准备播放地址并解析流
  Future<void> _preparePlaybackUrl() async {
    if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
      throw Exception('频道源索引无效');
    }
    String url = _currentChannel!.urls![_sourceIndex].toString();
    _originalUrl = url;
    await _disposeStreamUrlInstance(_streamUrl);
    _currentCancelToken = CancelToken();
    _streamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
    String parsedUrl = await _streamUrl!.getStreamUrl();
    if (parsedUrl == 'ERROR') {
      LogUtil.e('地址解析失败: $url');
      if (mounted) setState(() => toastString = S.current.vpnplayError);
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      throw Exception('地址解析失败');
    }
    _updatePlayUrl(parsedUrl);
    setState(() => _isAudio = _checkIsAudioStream(null));
    LogUtil.i('播放信息: URL=$parsedUrl, 音频模式=$_isAudio, HLS=$_isHls');
  }

  // 设置播放器控制器并初始化数据源
  Future<void> _setupPlayerController() async {
    if (_playerController != null) await _releaseAllResources(isDisposing: false);
    if (_currentPlayUrl?.isEmpty ?? true) throw Exception('播放地址为空');
    try {
      final dataSource = BetterPlayerConfig.createDataSource(
        url: _currentPlayUrl!,
        isHls: _isHls,
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener,
        isHls: _isHls,
      );
      _playerController = BetterPlayerController(betterPlayerConfiguration);
      await _playerController!.setupDataSource(dataSource);
      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      LogUtil.logError('设置播放器失败', e, stackTrace);
      await _releaseAllResources(isDisposing: false);
      throw e;
    }
  }

  // 开始播放视频
  Future<void> _startPlayback() async {
    if (_playerController == null) throw Exception('播放器控制器为空');
    await _playerController?.play();
    _timeoutActive = false;
    _timerManager.cancelTimer(TimerType.timeout);
  }

  // 处理待执行的频道切换请求
  void _processPendingSwitch() {
    if (_pendingSwitch == null || _isParsing || _isRetrying || _isDisposing) {
      if (_pendingSwitch != null) LogUtil.i('切换请求冲突: 解析=$_isParsing, 重试=$_isRetrying, 释放=$_isDisposing');
      return;
    }
    final nextRequest = _pendingSwitch!;
    _pendingSwitch = null;
    _currentChannel = nextRequest.channel;
    _sourceIndex = nextRequest.sourceIndex;
    Future.microtask(() async => await _playVideo());
  }

  // 队列化频道切换，防抖处理
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) {
      LogUtil.e('切换频道失败: 频道为空');
      return;
    }
    final safeSourceIndex = _getSafeSourceIndex(channel, sourceIndex);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
      if (!mounted) return;
      _pendingSwitch = SwitchRequest(channel, safeSourceIndex);
      LogUtil.i('防抖切换: ${channel.title}, 源索引: $safeSourceIndex');
      if (!_isSwitchingChannel) {
        _processPendingSwitch();
      } else {
        _timerManager.startTimer(
          TimerType.switchTimeout,
          Duration(seconds: m3u8ConnectTimeoutSeconds),
          () {
            if (mounted) {
              LogUtil.e('强制处理切换频道');
              _updatePlayState(switching: false);
              _processPendingSwitch();
            }
          },
        );
      }
    });
  }

  // 获取安全的源索引
  int _getSafeSourceIndex(PlayModel channel, int requestedIndex) {
    if (channel.urls?.isEmpty ?? true) {
      LogUtil.e('频道无可用源');
      return 0;
    }
    return channel.urls!.length > requestedIndex ? requestedIndex : 0;
  }

  // 视频播放事件监听
  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing) return;
    final ignoredEvents = {
      BetterPlayerEventType.changedPlayerVisibility,
      BetterPlayerEventType.bufferingUpdate,
      BetterPlayerEventType.changedTrack,
      BetterPlayerEventType.setupDataSource,
      BetterPlayerEventType.changedSubtitles,
    };
    if (ignoredEvents.contains(event.betterPlayerEventType)) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (_shouldUpdateAspectRatio) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? defaultAspectRatio;
          if (aspectRatio != newAspectRatio) {
            setState(() {
              aspectRatio = newAspectRatio;
              _shouldUpdateAspectRatio = false;
            });
          }
        }
        break;
      case BetterPlayerEventType.exception:
        if (_isParsing || _isSwitchingChannel) return;
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "Unknown"}');
        if (_preCachedUrl != null) {
          await _switchToPreCachedUrl('异常触发');
        } else {
          _retryPlayback();
        }
        break;
      case BetterPlayerEventType.bufferingStart:
        _updatePlayState(buffering: true, message: S.current.loading);
        break;
      case BetterPlayerEventType.bufferingEnd:
        _updatePlayState(buffering: false, message: 'HIDE_CONTAINER', showPause: _isUserPaused ? false : _showPauseIconFromListener);
        _timerManager.cancelTimer(TimerType.bufferingCheck);
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
          _timerManager.cancelTimer(TimerType.bufferingCheck);
          if (!_timerManager.isActive(TimerType.playDuration)) _startPlayDurationTimer();
        }
        _adManager.onVideoStartPlaying();
        break;
      case BetterPlayerEventType.pause:
        if (isPlaying) {
          _updatePlayState(playing: false, message: S.current.playpause, showPlay: _isUserPaused, showPause: !_isUserPaused);
          LogUtil.i('播放暂停, 用户触发: $_isUserPaused');
        }
        break;
      case BetterPlayerEventType.progress:
        if (_isParsing || _isSwitchingChannel || !_progressEnabled || !isPlaying) return;
        final position = event.parameters?["progress"] as Duration?;
        final duration = event.parameters?["duration"] as Duration?;
        if (position != null && duration != null) {
          final remainingTime = duration - position;
          if (_isHls) {
            if (_preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
              LogUtil.i('HLS剩余时间少于 $hlsSwitchThresholdSeconds 秒，切换预缓存');
              await _switchToPreCachedUrl('HLS剩余时间触发');
            }
          } else {
            if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
              final nextUrl = _getNextVideoUrl();
              if (nextUrl != null && nextUrl != _preCachedUrl) {
                LogUtil.i('非HLS剩余时间少于 $nonHlsPreloadThresholdSeconds 秒，预缓存下一源');
                _preloadNextVideo(nextUrl);
              }
            }
            if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
              await _switchToPreCachedUrl('非HLS剩余时间触发');
            }
          }
        }
        break;
      case BetterPlayerEventType.finished:
        if (_isParsing || _isSwitchingChannel) return;
        if (!_isHls && _preCachedUrl != null) {
          await _switchToPreCachedUrl('非HLS播放结束');
        } else if (_isHls) {
          LogUtil.i('HLS流异常结束，重试');
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

  // 检查m3u8文件有效性
  Future<bool> _checkM3u8Validity() async {
    if (_currentPlayUrl == null || !_isHls) return true;
    try {
      final content = await HttpUtil().getRequest<String>(
        _currentPlayUrl!,
        options: Options(
          extra: {
            'connectTimeout': Duration(seconds: m3u8ConnectTimeoutSeconds),
            'receiveTimeout': Duration(seconds: m3u8ReceiveTimeoutSeconds),
          },
        ),
        retryCount: 1,
      );
      if (content?.isEmpty ?? true) {
        LogUtil.e('m3u8内容为空: $_currentPlayUrl');
        return false;
      }
      bool isValid = content!.contains('.ts') || content.contains('#EXTINF') || content.contains('#EXT-X-STREAM-INF');
      if (!isValid) LogUtil.e('m3u8内容无效');
      return isValid;
    } catch (e, stackTrace) {
      LogUtil.logError('m3u8检查失败', e, stackTrace);
      return false;
    }
  }

  // 启动m3u8有效性检查定时器
  void _startM3u8CheckTimer() {
    if (!_isHls) return;
    _timerManager.cancelTimer(TimerType.m3u8Check);
    _timerManager.startPeriodicTimer(
      TimerType.m3u8Check,
      Duration(seconds: m3u8CheckIntervalSeconds),
      (_) async {
        if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) return;
        final isValid = await _checkM3u8Validity();
        if (!isValid) {
          _m3u8InvalidCount++;
          if (_m3u8InvalidCount == 1) {
            _timerManager.startTimer(
              TimerType.retry,
              Duration(seconds: m3u8InvalidConfirmDelaySeconds),
              () async {
                if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) {
                  _m3u8InvalidCount = 0;
                  return;
                }
                if (!await _checkM3u8Validity()) {
                  LogUtil.i('连续两次确认m3u8失效，重新解析');
                  await _reparseAndSwitch();
                } else {
                  _m3u8InvalidCount = 0;
                }
              },
            );
          } else if (_m3u8InvalidCount >= 2) {
            LogUtil.i('连续两次m3u8失效，重新解析');
            await _reparseAndSwitch();
            _m3u8InvalidCount = 0;
          }
        } else {
          _m3u8InvalidCount = 0;
        }
      },
    );
  }

  // 启动播放时长检查定时器
  void _startPlayDurationTimer() {
    _timerManager.cancelTimer(TimerType.playDuration);
    _timerManager.startTimer(
      TimerType.playDuration,
      Duration(seconds: initialProgressDelaySeconds),
      () {
        if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
          LogUtil.i('播放 $initialProgressDelaySeconds 秒，开始检查逻辑');
          if (_isHls && (_originalUrl?.toLowerCase().contains('timelimit') ?? false)) {
            _startM3u8CheckTimer();
            LogUtil.i('HLS流含timelimit，启用检查定时器');
          } else if (!_isHls && _getNextVideoUrl() != null) {
            _progressEnabled = true;
            LogUtil.i('非HLS流，启用progress监听');
          }
          _retryCount = 0;
        }
      },
    );
  }

  // 预加载下一视频源
  Future<void> _preloadNextVideo(String url) async {
    if (!_canPerformOperation('预加载视频', checkRetrying: false, checkParsing: false)) return;
    if (_playerController == null) {
      LogUtil.e('预加载失败: 播放器控制器为空');
      return;
    }
    if (_preCachedUrl == url) {
      LogUtil.i('URL已预缓存: $url');
      return;
    }
    if (_preCachedUrl != null) {
      LogUtil.i('替换预缓存URL: $_preCachedUrl -> $url');
      await _cleanupPreCacheResources();
    }
    StreamUrl? tempStreamUrl;
    try {
      LogUtil.i('开始预加载: $url');
      _preloadCancelToken = CancelToken();
      tempStreamUrl = StreamUrl(url, cancelToken: _preloadCancelToken);
      String parsedUrl = await tempStreamUrl.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        return;
      }
      if (_playerController == null) {
        LogUtil.e('预缓存失败: 播放器控制器已释放');
        return;
      }
      _preCacheStreamUrl = tempStreamUrl;
      tempStreamUrl = null;
      _preCachedUrl = parsedUrl;
      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl),
        url: parsedUrl,
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      if (_playerController != null) await _playerController!.clearCache();
    } finally {
      if (tempStreamUrl != null) await _disposeStreamUrlInstance(tempStreamUrl);
    }
  }

  // 初始化中文转换器
  Future<void> _initializeZhConverters() async {
    if (_zhConvertersInitialized || _zhConvertersInitializing) return;
    _zhConvertersInitializing = true;
    try {
      await Future.wait([
        if (_s2tConverter == null) (_s2tConverter = ZhConverter('s2t')).initialize(),
        if (_t2sConverter == null) (_t2sConverter = ZhConverter('t2s')).initialize(),
      ]);
      _zhConvertersInitialized = true;
      LogUtil.i('中文转换器初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('中文转换器初始化失败', e, stackTrace);
    } finally {
      _zhConvertersInitializing = false;
    }
  }

  // 重试播放
  void _retryPlayback({bool resetRetryCount = false}) {
    if (!_canPerformOperation('重试播放') || _isParsing) return;
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.timeout);
    if (resetRetryCount) _updatePlayState(retryCount: 0);
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
      _timerManager.startTimer(
        TimerType.retry,
        Duration(seconds: retryDelaySeconds),
        () async {
          if (!mounted || _isDisposing || _isSwitchingChannel || _isParsing) {
            _updatePlayState(retrying: false);
            return;
          }
          await _playVideo(isRetry: true);
          if (mounted) _updatePlayState(retrying: false);
        },
      );
    } else {
      LogUtil.i('重试次数达上限，切换下一源');
      _handleSourceSwitching();
    }
  }

  // 获取下一视频源地址
  String? _getNextVideoUrl() {
    if (_currentChannel?.urls?.isEmpty ?? true) return null;
    final nextSourceIndex = _sourceIndex + 1;
    return nextSourceIndex < _currentChannel!.urls!.length ? _currentChannel!.urls![nextSourceIndex] : null;
  }

  // 处理源切换
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.timeout);
    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      LogUtil.i('无更多源可切换');
      _handleNoMoreSources();
      return;
    }
    _switchAttemptCount++;
    if (_switchAttemptCount > maxSwitchAttempts) {
      LogUtil.e('切换尝试超限 ($maxSwitchAttempts)');
      _handleNoMoreSources();
      _switchAttemptCount = 0;
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

  // 处理无更多源的情况
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
    await _releaseAllResources(isDisposing: false);
    LogUtil.i('播放结束，无更多源');
    _switchAttemptCount = 0;
  }

  // 启动新源播放定时器
  void _startNewSourceTimer() {
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.startTimer(
      TimerType.retry,
      Duration(seconds: retryDelaySeconds),
      () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) return;
        await _playVideo(isSourceSwitch: true);
      },
    );
  }

  // 释放所有资源
  Future<void> _releaseAllResources({bool isDisposing = false}) async {
    if (_isDisposing) return;
    _isDisposing = true;
    LogUtil.i('释放所有资源');
    _timerManager.cancelAll();
    try {
      if (_playerController != null) {
        final controller = _playerController!;
        _playerController = null;
        controller.removeEventsListener(_videoListener);
        if (controller.isPlaying() ?? false) {
          await controller.pause();
          await controller.setVolume(0);
        }
        if (controller.videoPlayerController != null) await controller.videoPlayerController!.dispose();
        controller.dispose();
      }
      final currentStreamUrl = _streamUrl;
      final preStreamUrl = _preCacheStreamUrl;
      _streamUrl = null;
      _preCacheStreamUrl = null;
      if (currentStreamUrl != null) await _disposeStreamUrlInstance(currentStreamUrl);
      if (preStreamUrl != null && preStreamUrl != currentStreamUrl) await _disposeStreamUrlInstance(preStreamUrl);
      if (isDisposing) {
        _adManager.dispose();
      } else {
        _adManager.reset(rescheduleAds: false, preserveTimers: true);
      }
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
      await Future.delayed(Duration(milliseconds: cleanupDelayMilliseconds));
    } catch (e, stackTrace) {
      LogUtil.logError('释放资源失败', e, stackTrace);
    } finally {
      _isDisposing = isDisposing;
    }
  }

  // 释放StreamUrl实例
  Future<void> _disposeStreamUrlInstance(StreamUrl? instance) async {
    if (instance == null) return;
    try {
      await instance.dispose();
    } catch (e, stackTrace) {
      LogUtil.logError('释放StreamUrl失败', e, stackTrace);
    }
  }

  // 重新解析并切换播放地址
  Future<void> _reparseAndSwitch({bool force = false}) async {
    if (!_canPerformOperation('重新解析')) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastParseTime != null && (now - _lastParseTime!) < reparseMinIntervalMilliseconds) {
      final remainingWaitTime = reparseMinIntervalMilliseconds - (now - _lastParseTime!);
      LogUtil.i('解析频率过高，延迟 ${remainingWaitTime}ms');
      _timerManager.startTimer(
        TimerType.retry,
        Duration(milliseconds: remainingWaitTime.toInt()),
        () {
          if (mounted) _reparseAndSwitch(force: true);
        },
      );
      return;
    }
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.m3u8Check);
    _updatePlayState(parsing: true, retrying: true);
    StreamUrl? tempStreamUrl;
    try {
      if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
        LogUtil.e('频道信息无效');
        throw Exception('无效的频道信息');
      }
      _updatePlayState(switching: true);
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      _currentCancelToken = CancelToken();
      tempStreamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
      String newParsedUrl = await tempStreamUrl.getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        return;
      }
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前地址相同，无需切换');
        _updatePlayState(parsing: false, retrying: false, switching: false);
        return;
      }
      _streamUrl = tempStreamUrl;
      tempStreamUrl = null;
      _preCachedUrl = newParsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl');
      if (_playerController != null) {
        if (_isDisposing) {
          LogUtil.i('中断，退出重新解析');
          _preCachedUrl = null;
          _updatePlayState(parsing: false, retrying: false, switching: false);
          return;
        }
        await _preparePreCacheSource(newParsedUrl);
        if (_isDisposing) {
          LogUtil.i('预加载中断，退出重新解析');
          _preCachedUrl = null;
          _updatePlayState(parsing: false, retrying: false, switching: false);
          return;
        }
        _progressEnabled = true;
        _lastParseTime = now;
        LogUtil.i('预缓存完成，等待切换');
      } else {
        LogUtil.i('播放器控制器为空，切换下一源');
        _handleSourceSwitching();
      }
      _updatePlayState(switching: false);
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      _preCachedUrl = null;
      _handleSourceSwitching();
    } finally {
      if (tempStreamUrl != null) await _disposeStreamUrlInstance(tempStreamUrl);
      if (_streamUrl != null && _preCachedUrl == null) await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      if (mounted) _updatePlayState(parsing: false, retrying: false);
    }
  }

  // 提取并转换地理信息
  Future<Map<String, String?>> _getLocationInfo(String? userInfo) async {
    if (userInfo?.isEmpty ?? true) {
      LogUtil.i('地理信息为空');
      return {'region': null, 'city': null};
    }
    try {
      final userData = jsonDecode(userInfo!);
      final locationData = userData['info']?['location'];
      if (locationData == null) {
        LogUtil.i('无location字段');
        return {'region': null, 'city': null};
      }
      String? region = locationData['region'] as String?;
      String? city = locationData['city'] as String?;
      if ((region?.isEmpty ?? true) && (city?.isEmpty ?? true)) return {'region': null, 'city': null};
      if (!mounted) return {'region': null, 'city': null};
      final currentLocale = Localizations.localeOf(context).toString();
      if (currentLocale.startsWith('zh')) {
        if (!_zhConvertersInitialized) await _initializeZhConverters();
        if (_zhConvertersInitialized) {
          bool isTraditional = currentLocale.contains('TW') || currentLocale.contains('HK') || currentLocale.contains('MO');
          ZhConverter? converter = isTraditional ? _s2tConverter : _t2sConverter;
          if (converter != null) {
            if (region?.isNotEmpty ?? false) region = converter.convertSync(region!);
            if (city?.isNotEmpty ?? false) city = converter.convertSync(city!);
          }
        }
      }
      final regionPrefix = (region?.length ?? 0) >= 2 ? region!.substring(0, 2) : region;
      final cityPrefix = (city?.length ?? 0) >= 2 ? city!.substring(0, 2) : city;
      LogUtil.i('地理信息: 地区=$regionPrefix, 城市=$cityPrefix');
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e, stackTrace) {
      LogUtil.logError('解析地理信息失败', e, stackTrace);
      return {'region': null, 'city': null};
    }
  }

  // 根据地理前缀排序列表
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix?.isEmpty ?? true) return items;
    if (items.isEmpty) return items;
    final matchingItems = items.where((item) => item.startsWith(prefix!)).toList();
    final nonMatchingItems = items.where((item) => !item.startsWith(prefix!)).toList();
    final result = [...matchingItems, ...nonMatchingItems];
    LogUtil.i('排序结果: $result');
    return result;
  }

  // 根据地理信息排序播放列表
  Future<void> _sortVideoMap(PlaylistModel videoMap, String? userInfo) async {
    if (videoMap.playList?.isEmpty ?? true) return;
    final location = await _getLocationInfo(userInfo);
    final regionPrefix = location['region'];
    if (regionPrefix?.isEmpty ?? true) {
      LogUtil.i('地区前缀为空，跳过排序');
      return;
    }
    videoMap.playList!.forEach((category, groups) {
      if (groups is! Map<String, Map<String, PlayModel>>) {
        LogUtil.e('分类 $category 类型无效');
        return;
      }
      final groupList = groups.keys.toList();
      if (!groupList.any((group) => group.contains(regionPrefix!))) return;
      final sortedGroups = _sortByGeoPrefix(groupList, regionPrefix);
      final newGroups = <String, Map<String, PlayModel>>{};
      for (var group in sortedGroups) {
        final channels = groups[group];
        if (channels is! Map<String, PlayModel>) {
          LogUtil.e('组 $group 类型无效');
          continue;
        }
        final channelList = channels.keys.toList();
        final newChannels = <String, PlayModel>{};
        if (regionPrefix != null && group.contains(regionPrefix) && (location['city']?.isNotEmpty ?? false)) {
          final sortedChannels = _sortByGeoPrefix(channelList, location['city']);
          for (var channel in sortedChannels) newChannels[channel] = channels[channel]!;
        } else {
          for (var channel in channelList) newChannels[channel] = channels[channel]!;
        }
        newGroups[group] = newChannels;
      }
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成');
    });
  }

  // 处理频道点击事件
  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;
    try {
      _updatePlayState(buffering: false, message: S.current.loading, retrying: false, retryCount: 0);
      _timerManager.cancelTimer(TimerType.retry);
      _timerManager.cancelTimer(TimerType.m3u8Check);
      _currentChannel = model;
      _sourceIndex = 0;
      _shouldUpdateAspectRatio = true;
      _switchAttemptCount = 0;
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
      if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      _updatePlayState(message: S.current.playError);
      await _releaseAllResources(isDisposing: false);
    }
  }

  // 切换频道源
  Future<void> _changeChannelSources() async {
    final sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) {
      LogUtil.e('无有效视频源');
      return;
    }
    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null) {
      _updatePlayState(sourceIndex: selectedIndex, retrying: false, retryCount: 0);
      _switchAttemptCount = 0;
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
    }
  }

  // 处理返回键事件
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

  // 处理用户暂停事件
  void _handleUserPaused() => _updatePlayState(userPaused: true);

  // 处理重试事件
  void _handleRetry() => _retryPlayback(resetRetryCount: true);

  @override
  void initState() {
    super.initState();
    _adManager = AdManager();
    Future.microtask(() async {
      await _adManager.loadAdData();
      _hasInitializedAdManager = true;
    });
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    _loadData();
    _extractFavoriteList();
    LogUtil.i('播放模式: ${Config.videoPlayMode ? "视频" : "音频"}');
    Future.microtask(() => _initializeZhConverters());
  }

  @override
  void dispose() {
    _releaseAllResources(isDisposing: true);
    favoriteList.clear();
    _videoMap = null;
    _s2tConverter = null;
    _t2sConverter = null;
    _debounceTimer?.cancel();
    super.dispose();
  }

  // 发送流量统计数据
  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName?.isNotEmpty ?? false) {
      try {
        bool? isFirstInstall = SpUtil.getBool('is_first_install');
        bool isTV = context.watch<ThemeProvider>().isTV;
        String deviceType = isTV ? "TV" : "Other";
        if (isFirstInstall == null) {
          await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: deviceType);
          await SpUtil.putBool('is_first_install', true);
        } else {
          await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: channelName!);
        }
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计失败', e, stackTrace);
      }
    }
  }

  // 加载并排序播放数据
  Future<void> _loadData() async {
    _updatePlayState(retrying: false, retryCount: 0);
    _timerManager.cancelAll();
    setState(() => _isAudio = false);
    if (widget.m3uData.playList?.isEmpty ?? true) {
      LogUtil.e('播放列表无效');
      setState(() => toastString = S.current.getDefaultError);
      return;
    }
    try {
      _videoMap = widget.m3uData;
      String? userInfo = SpUtil.getString('user_all_info');
      await _initializeZhConverters();
      await _sortVideoMap(_videoMap!, userInfo);
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表失败', e, stackTrace);
      setState(() => toastString = S.current.parseError);
    }
  }

  // 处理播放列表并选择首个频道
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);
      if (_currentChannel != null) {
        if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
        _updatePlayState(retryCount: 0);
        _timeoutActive = false;
        _switchAttemptCount = 0;
        if (!_isSwitchingChannel && !_isRetrying && !_isParsing) {
          await _queueSwitchChannel(_currentChannel, _sourceIndex);
        } else {
          LogUtil.i('用户操作中，跳过初始化切换');
        }
      } else {
        setState(() {
          toastString = 'UNKNOWN';
          _isRetrying = false;
        });
      }
    } else {
      setState(() {
        _currentChannel = null;
        toastString = 'UNKNOWN';
        _isRetrying = false;
      });
    }
  }

  // 从播放列表提取首个可用频道
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    try {
      for (final categoryEntry in playList.entries) {
        final categoryData = categoryEntry.value;
        if (categoryData is Map<String, Map<String, PlayModel>>) {
          for (final groupEntry in categoryData.entries) {
            final channelMap = groupEntry.value;
            for (final channel in channelMap.values) {
              if (channel.urls?.isNotEmpty ?? false) return channel;
            }
          }
        } else if (categoryData is Map<String, PlayModel>) {
          for (final channel in categoryData.values) {
            if (channel.urls?.isNotEmpty ?? false) return channel;
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取频道失败', e, stackTrace);
    }
    return null;
  }

  // 提取收藏列表
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

  // 切换频道收藏状态
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
      favoriteList[Config.myFavoriteKey]![groupName] ??= {};
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
        LogUtil.i('更新收藏列表');
        if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: snackBarDurationSeconds));
        LogUtil.logError('保存收藏失败', error);
      }
    }
  }

  // 解析播放数据
  Future<void> _parseData() async {
    try {
      if (_videoMap?.playList?.isEmpty ?? true) {
        LogUtil.e('播放列表无效');
        setState(() => toastString = S.current.getDefaultError);
        return;
      }
      _sourceIndex = 0;
      _switchAttemptCount = 0;
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
