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

// 播放器管理器，统一处理播放逻辑和状态
class PlayerManager {
  // 播放配置常量
  static const int defaultMaxRetries = 1; // 最大重试次数
  static const int defaultTimeoutSeconds = 38; // 默认超时时间（秒）
  static const int retryDelaySeconds = 2; // 重试延迟时间（秒）
  static const int hlsSwitchThresholdSeconds = 3; // HLS切换阈值（秒）
  static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS预加载阈值（秒）
  static const int nonHlsSwitchThresholdSeconds = 3; // 非HLS切换阈值（秒）
  static const double defaultAspectRatio = 1.78; // 默认宽高比

  // 预定义播放状态
  static const Map<String, dynamic> playing = {
    'playing': true,
    'buffering': false,
    'showPlay': false,
    'showPause': false,
  }; // 播放中状态

  static const Map<String, dynamic> error = {
    'playing': false,
    'buffering': false,
    'retrying': false,
    'switching': false,
  }; // 错误状态

  static const Map<String, dynamic> loading = {
    'playing': false,
    'buffering': false,
    'showPlay': false,
    'showPause': false,
    'userPaused': false,
    'switching': true,
  }; // 加载中状态

  static const Map<String, dynamic> resetOperations = {
    'retrying': false,
    'parsing': false,
    'switching': false,
  }; // 重置操作状态

  // 创建重试状态
  static Map<String, dynamic> retrying(int count) => {
        'retrying': true,
        'retryCount': count,
        'buffering': false,
        'showPlay': false,
        'showPause': false,
        'userPaused': false,
      }; // 重试状态

  // 创建播放器控制器
  static BetterPlayerController? createController({
    required Function(BetterPlayerEvent) eventListener,
    required bool isHls,
  }) {
    final configuration = BetterPlayerConfig.createPlayerConfig(
      eventListener: eventListener,
      isHls: isHls,
    );
    return BetterPlayerController(configuration); // 初始化播放器控制器
  }

  // 播放视频源
  static Future<void> playSource({
    required BetterPlayerController controller,
    required String url,
    required bool isHls,
    String? channelTitle,
    String? channelLogo,
    bool preloadOnly = false,
  }) async {
    final dataSource = BetterPlayerConfig.createDataSource(
      url: url,
      isHls: isHls,
      channelTitle: channelTitle,
      channelLogo: channelLogo,
    );
    if (preloadOnly) {
      await controller.preCache(dataSource);
      LogUtil.i('预缓存完成: $url');
    } else {
      await controller.setupDataSource(dataSource);
      await controller.play();
      LogUtil.i('播放源: $url');
    }
  }

  // 执行播放任务并解析地址
  static Future<String> executePlayback({
    required String originalUrl,
    required CancelToken cancelToken,
    String? channelTitle,
  }) async {
    StreamUrl? streamUrl;
    try {
      LogUtil.i('开始播放任务: $originalUrl');
      streamUrl = StreamUrl(originalUrl, cancelToken: cancelToken);
      String parsedUrl = await streamUrl.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        throw Exception('地址解析失败: $originalUrl');
      }
      LogUtil.i('解析成功: $parsedUrl');
      return parsedUrl;
    } catch (e, stackTrace) {
      LogUtil.e('播放失败: $e\n$stackTrace');
      await safeDisposeResource(streamUrl);
      rethrow;
    }
  }

  // 释放资源
  static Future<void> safeDisposeResource(dynamic resource) async {
    if (resource == null) return;
    try {
      if (resource is BetterPlayerController) {
        if (resource.isPlaying() ?? false) {
          await resource.pause();
          await resource.setVolume(0);
        }
        if (resource.videoPlayerController != null) {
          await resource.videoPlayerController!.dispose();
        }
        resource.dispose();
        LogUtil.i('播放器控制器释放完成');
      } else if (resource is StreamUrl) {
        await resource.dispose();
        LogUtil.i('StreamUrl释放完成');
      }
    } catch (e) {
      LogUtil.e('资源释放失败: $e');
    }
  }

  // 判断是否为HLS流
  static bool isHlsStream(String? url) {
    if (url?.isEmpty ?? true) return false;
    final lowercaseUrl = url!.toLowerCase();
    if (lowercaseUrl.contains('.m3u8')) return true;
    final nonHlsFormats = [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac', '.flv', 'rtmp:'
    ];
    return !nonHlsFormats.any(lowercaseUrl.contains);
  }
}

// 主页面，管理播放和频道切换
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 播放列表数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

// 计时器类型枚举
enum TimerType {
  retry, // 重试计时
  m3u8Check, // m3u8检查
  playDuration, // 播放时长
  timeout, // 超时检测
  bufferingCheck, // 缓冲检查
  switchTimeout, // 切换超时
  stateCheck, // 状态检查
}

// 频道切换请求
class SwitchRequest {
  final PlayModel? channel; // 目标频道
  final int sourceIndex; // 源索引
  SwitchRequest(this.channel, this.sourceIndex);
}

// 计时器管理
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
  static const int initialProgressDelaySeconds = 60; // 初始进度延迟
  static const int cleanupDelayMilliseconds = 500; // 清理延迟
  static const int snackBarDurationSeconds = 5; // 提示显示时长
  static const int m3u8InvalidConfirmDelaySeconds = 1; // m3u8失效确认延迟
  static const int m3u8CheckIntervalSeconds = 10; // m3u8检查间隔
  static const int reparseMinIntervalMilliseconds = 10000; // 重新解析间隔
  static const int maxSwitchAttempts = 3; // 最大切换尝试次数

  String? _preCachedUrl; // 预缓存地址
  bool _isParsing = false; // 是否正在解析
  bool _isRetrying = false; // 是否正在重试
  bool isBuffering = false; // 是否正在缓冲
  bool isPlaying = false; // 是否正在播放
  bool _isUserPaused = false; // 用户是否暂停
  bool _isDisposing = false; // 是否正在释放资源
  bool _isSwitchingChannel = false; // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 是否更新宽高比
  bool _progressEnabled = false; // 是否启用进度检查
  bool _isHls = false; // 是否为HLS流
  bool _isAudio = false; // 是否为音频流
  bool _showPlayIcon = false; // 是否显示播放图标
  int? _lastParseTime; // 上次解析时间
  String toastString = S.current.loading; // 当前提示信息
  PlaylistModel? _videoMap; // 视频播放列表
  PlayModel? _currentChannel; // 当前频道
  int _sourceIndex = 0; // 当前源索引
  BetterPlayerController? _playerController; // 播放器控制器
  double aspectRatio = PlayerManager.defaultAspectRatio; // 当前宽高比
  bool _drawerIsOpen = false; // 抽屉菜单是否打开
  int _retryCount = 0; // 重试次数
  bool _timeoutActive = false; // 超时检测是否激活
  StreamUrl? _streamUrl; // 当前流地址
  StreamUrl? _preCacheStreamUrl; // 预缓存流地址
  String? _currentPlayUrl; // 当前播放地址
  String? _originalUrl; // 原始播放地址
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  }; // 收藏列表
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析
  late AdManager _adManager; // 广告管理
  bool _showPauseIconFromListener = false; // 是否显示暂停图标
  int _m3u8InvalidCount = 0; // m3u8失效计数
  int _switchAttemptCount = 0; // 切换尝试计数
  ZhConverter? _s2tConverter; // 简转繁
  ZhConverter? _t2sConverter; // 繁转简
  bool _zhConvertersInitializing = false; // 是否正在初始化转换器
  bool _zhConvertersInitialized = false; // 转换器初始化状态
  final TimerManager _timerManager = TimerManager(); // 计时器管理
  SwitchRequest? _pendingSwitch; // 待处理切换请求
  Timer? _debounceTimer; // 防抖定时器
  bool _hasInitializedAdManager = false; // 广告管理器初始化状态
  String? _lastPlayedChannelId; // 最后播放频道ID
  late CancelToken _currentCancelToken; // 当前解析CancelToken
  late CancelToken _preloadCancelToken; // 预加载CancelToken

  // 获取频道logo
  String _getChannelLogo() =>
      _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png';

  // 判断是否为音频流
  bool _checkIsAudioStream(String? url) => !Config.videoPlayMode;

  // 更新播放地址并判断流类型
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = PlayerManager.isHlsStream(_currentPlayUrl);
  }

  // 统一状态更新
  void _updateState({
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
    bool? disposing,
    bool? audio,
    double? aspectRatioValue,
    bool? shouldUpdateAspectRatio,
    bool? drawerIsOpen,
    bool? progressEnabled,
    bool? timeoutActive,
    ValueKey<int>? drawerRefreshKey,
    Map<String, dynamic>? stateMap,
  }) {
    if (!mounted) return;
    setState(() {
      if (stateMap != null) {
        if (stateMap.containsKey('playing')) isPlaying = stateMap['playing'];
        if (stateMap.containsKey('buffering')) isBuffering = stateMap['buffering'];
        if (stateMap.containsKey('message')) toastString = stateMap['message'];
        if (stateMap.containsKey('showPlay')) _showPlayIcon = stateMap['showPlay'];
        if (stateMap.containsKey('showPause')) _showPauseIconFromListener = stateMap['showPause'];
        if (stateMap.containsKey('userPaused')) _isUserPaused = stateMap['userPaused'];
        if (stateMap.containsKey('switching')) _isSwitchingChannel = stateMap['switching'];
        if (stateMap.containsKey('retrying')) _isRetrying = stateMap['retrying'];
        if (stateMap.containsKey('parsing')) _isParsing = stateMap['parsing'];
        if (stateMap.containsKey('sourceIndex')) _sourceIndex = stateMap['sourceIndex'];
        if (stateMap.containsKey('retryCount')) _retryCount = stateMap['retryCount'];
        if (stateMap.containsKey('disposing')) _isDisposing = stateMap['disposing'];
        if (stateMap.containsKey('audio')) _isAudio = stateMap['audio'];
        if (stateMap.containsKey('aspectRatio')) aspectRatio = stateMap['aspectRatio'];
        if (stateMap.containsKey('shouldUpdateAspectRatio')) _shouldUpdateAspectRatio = stateMap['shouldUpdateAspectRatio'];
        if (stateMap.containsKey('drawerIsOpen')) _drawerIsOpen = stateMap['drawerIsOpen'];
        if (stateMap.containsKey('progressEnabled')) _progressEnabled = stateMap['progressEnabled'];
        if (stateMap.containsKey('timeoutActive')) _timeoutActive = stateMap['timeoutActive'];
        if (stateMap.containsKey('drawerRefreshKey')) _drawerRefreshKey = stateMap['drawerRefreshKey'];
      } else {
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
        if (disposing != null) _isDisposing = disposing;
        if (audio != null) _isAudio = audio;
        if (aspectRatioValue != null) aspectRatio = aspectRatioValue;
        if (shouldUpdateAspectRatio != null) _shouldUpdateAspectRatio = shouldUpdateAspectRatio;
        if (drawerIsOpen != null) _drawerIsOpen = drawerIsOpen;
        if (progressEnabled != null) _progressEnabled = progressEnabled;
        if (timeoutActive != null) _timeoutActive = timeoutActive;
        if (drawerRefreshKey != null) _drawerRefreshKey = drawerRefreshKey;
      }
    });
  }

  // 检查操作可行性
  bool _canPerformOperation(String operationName, {
    bool checkRetrying = true,
    bool checkSwitching = true,
    bool checkDisposing = true,
    bool checkParsing = true,
    bool? customCondition,
    VoidCallback? onFailed,
  }) {
    if (!mounted) {
      onFailed?.call();
      return false;
    }
    List<String> blockers = [];
    if (checkDisposing && _isDisposing) blockers.add('正在释放资源');
    if (checkRetrying && _isRetrying) blockers.add('正在重试');
    if (checkSwitching && _isSwitchingChannel) blockers.add('正在切换频道');
    if (checkParsing && _isParsing) blockers.add('正在解析');
    if (customCondition == false) blockers.add('自定义条件不满足');
    if (blockers.isNotEmpty) {
      LogUtil.i('$operationName 被阻止: ${blockers.join(", ")}');
      onFailed?.call();
      return false;
    }
    return true;
  }

  // 启动状态检查定时器
  void _startStateCheckTimer() {
    LogUtil.i('启动状态检查定时器');
    _timerManager.startTimer(TimerType.stateCheck, Duration(seconds: 3), () {
      if (!_canPerformOperation('状态检查', checkSwitching: false, checkParsing: false)) return;
      _checkAndFixStuckStates();
    });
  }

  // 检查并修复卡住状态
  void _checkAndFixStuckStates() {
    List<String> stuckStates = [];
    if (_isDisposing) stuckStates.add('disposing');
    if (_isParsing) stuckStates.add('parsing');
    if (_isRetrying && _retryCount > 0) stuckStates.add('retrying');
    if (_isSwitchingChannel) stuckStates.add('switching');
    if (stuckStates.isEmpty) {
      LogUtil.i('状态正常');
      return;
    }
    LogUtil.e('检测到状态异常: ${stuckStates.join(", ")}');
    _updateState(stateMap: {
      'parsing': false,
      'retrying': false,
      'switching': false,
      'retryCount': 0,
      'disposing': false,
    });
    _timerManager.cancelTimer(TimerType.timeout);
    _timerManager.cancelTimer(TimerType.switchTimeout);
    if (_pendingSwitch != null) {
      LogUtil.i('处理待切换请求');
      _processPendingSwitch();
    } else if (_currentChannel != null) {
      LogUtil.i('重新播放当前频道');
      Future.microtask(() => _playVideo());
    }
  }

  // 清理预缓存资源
  Future<void> _cleanupPreCache() async {
    _preCachedUrl = null;
    if (_preCacheStreamUrl != null) {
      await PlayerManager.safeDisposeResource(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
      LogUtil.i('预缓存清理完成');
    }
  }

  // 切换到预缓存地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
    if (_isDisposing || _preCachedUrl == null) {
      LogUtil.i('$logDescription: ${_isDisposing ? "正在释放资源" : "无预缓存地址"}');
      return;
    }
    _timerManager.cancelTimer(TimerType.timeout);
    _timerManager.cancelTimer(TimerType.retry);
    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址相同，重新解析');
      await _cleanupPreCache();
      await _reparseAndSwitch();
      return;
    }
    try {
      _updateState(stateMap: PlayerManager.loading);
      await PlayerManager.playSource(
        controller: _playerController!,
        url: _preCachedUrl!,
        isHls: PlayerManager.isHlsStream(_preCachedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
        preloadOnly: true,
      );
      await PlayerManager.playSource(
        controller: _playerController!,
        url: _preCachedUrl!,
        isHls: PlayerManager.isHlsStream(_preCachedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      _startPlayDurationTimer();
      _updatePlayUrl(_preCachedUrl!);
      _updateState(stateMap: {...PlayerManager.playing, 'switching': false});
      _switchAttemptCount = 0;
      LogUtil.i('$logDescription: 切换预缓存成功: $_preCachedUrl');
    } catch (e) {
      LogUtil.e('$logDescription: 切换预缓存失败: $e');
      _retryPlayback();
    } finally {
      _updateState(switching: false, progressEnabled: false);
      await _cleanupPreCache();
    }
  }

  // 播放视频
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null || !_isSourceIndexValid()) {
      LogUtil.e('播放失败: ${_currentChannel == null ? "无频道" : "源索引无效"}');
      return;
    }
    bool isChannelChange = !isSourceSwitch || (_lastPlayedChannelId != _currentChannel!.id);
    String channelId = _currentChannel?.id ?? _currentChannel!.title ?? 'unknown_channel';
    _lastPlayedChannelId = channelId;
    if (isChannelChange) {
      _adManager.onChannelChanged(channelId);
    }
    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('播放: ${_currentChannel!.title}, 源: $sourceName');
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.timeout);
    _updateState(stateMap: {
      ...PlayerManager.loading,
      'message': '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
    });
    _startPlaybackTimeout();
    try {
      if (!isRetry && !isSourceSwitch && isChannelChange && _hasInitializedAdManager) {
        bool shouldPlay = await _adManager.shouldPlayVideoAdAsync();
        if (shouldPlay) {
          await _adManager.playVideoAd();
          LogUtil.i('广告播放完成');
        }
      }
      if (_playerController != null) {
        await _releaseAllResources(isDisposing: false);
      }
      String url = _currentChannel!.urls![_sourceIndex].toString();
      _originalUrl = url;
      await PlayerManager.safeDisposeResource(_streamUrl);
      _currentCancelToken.cancel();
      _currentCancelToken = CancelToken();
      String parsedUrl = await PlayerManager.executePlayback(
        originalUrl: url,
        cancelToken: _currentCancelToken,
        channelTitle: _currentChannel?.title,
      );
      _streamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
      _updatePlayUrl(parsedUrl);
      bool isAudio = _checkIsAudioStream(null);
      _updateState(audio: isAudio);
      LogUtil.i('播放信息: URL=$parsedUrl, 音频=$isAudio, HLS=$_isHls');
      _playerController = PlayerManager.createController(
        eventListener: _videoListener,
        isHls: _isHls,
      );
      await PlayerManager.playSource(
        controller: _playerController!,
        url: _currentPlayUrl!,
        isHls: _isHls,
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      if (mounted) setState(() {});
      await _playerController?.play();
      _updateState(timeoutActive: false);
      _timerManager.cancelTimer(TimerType.timeout);
      _switchAttemptCount = 0;
    } catch (e) {
      LogUtil.e('播放失败: $e');
      await PlayerManager.safeDisposeResource(_streamUrl);
      _streamUrl = null;
      _switchAttemptCount++;
      if (_switchAttemptCount <= maxSwitchAttempts) {
        _handleSourceSwitching();
      } else {
        _switchAttemptCount = 0;
        _updateState(stateMap: {
          ...PlayerManager.error,
          'message': S.current.playError,
        });
      }
    } finally {
      if (mounted) {
        _updateState(switching: false);
        _timerManager.cancelTimer(TimerType.switchTimeout);
        _processPendingSwitch();
      }
    }
  }

  // 修正源索引
  ({int safeIndex, bool hasValidSources}) _fixSourceIndex(PlayModel? channel, int currentIndex) {
    if (channel?.urls?.isEmpty ?? true) {
      LogUtil.e('无可用源');
      return (safeIndex: 0, hasValidSources: false);
    }
    final safeIndex = (currentIndex < 0 || currentIndex >= channel!.urls!.length) ? 0 : currentIndex;
    return (safeIndex: safeIndex, hasValidSources: true);
  }

  // 验证源索引
  bool _isSourceIndexValid() {
    final result = _fixSourceIndex(_currentChannel, _sourceIndex);
    _updateState(sourceIndex: result.safeIndex);
    if (!result.hasValidSources) {
      _updateState(stateMap: {
        ...PlayerManager.error,
        'message': S.current.playError,
      });
      return false;
    }
    return true;
  }

  // 启动播放超时检测
  void _startPlaybackTimeout() {
    _updateState(timeoutActive: true);
    _timerManager.startTimer(TimerType.timeout, Duration(seconds: PlayerManager.defaultTimeoutSeconds), () {
      if (!_canPerformOperation('超时检查', customCondition: _timeoutActive)) {
        _updateState(timeoutActive: false);
        return;
      }
      if (_playerController?.isPlaying() != true) {
        _handleSourceSwitching();
        _updateState(timeoutActive: false);
      }
    });
  }

  // 处理待切换请求
  void _processPendingSwitch() {
    if (_pendingSwitch == null || !_canPerformOperation('处理待切换')) {
      if (_pendingSwitch != null) {
        LogUtil.i('切换请求冲突');
        _checkAndFixStuckStates();
      }
      return;
    }
    final nextRequest = _pendingSwitch!;
    _pendingSwitch = null;
    _currentChannel = nextRequest.channel;
    _updateState(sourceIndex: nextRequest.sourceIndex);
    Future.microtask(() => _playVideo());
  }

  // 队列化频道切换
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) {
      LogUtil.e('切换频道失败: 无频道');
      return;
    }
    final result = _fixSourceIndex(channel, sourceIndex);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
      if (!mounted) return;
      _pendingSwitch = SwitchRequest(channel, result.safeIndex);
      if (!_isSwitchingChannel) {
        _processPendingSwitch();
      } else {
        _timerManager.startTimer(TimerType.switchTimeout, Duration(seconds: PlayerManager.hlsSwitchThresholdSeconds), () {
          if (mounted) {
            LogUtil.e('强制切换频道');
            _updateState(switching: false);
            _processPendingSwitch();
          }
        });
      }
    });
  }

  // 视频事件监听
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
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? PlayerManager.defaultAspectRatio;
          if (aspectRatio != newAspectRatio) {
            _updateState(aspectRatioValue: newAspectRatio, shouldUpdateAspectRatio: false);
          }
        }
        break;
      case BetterPlayerEventType.exception:
        if (_isParsing || _isSwitchingChannel) return;
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "未知错误"}');
        if (_preCachedUrl != null) {
          await _switchToPreCachedUrl('异常触发');
        } else {
          _retryPlayback();
        }
        break;
      case BetterPlayerEventType.bufferingStart:
        _updateState(buffering: true, message: S.current.loading);
        break;
      case BetterPlayerEventType.bufferingEnd:
        _updateState(
          buffering: false,
          message: 'HIDE_CONTAINER',
          showPause: _isUserPaused ? false : _showPauseIconFromListener,
        );
        _timerManager.cancelTimer(TimerType.bufferingCheck);
        break;
      case BetterPlayerEventType.play:
        if (!isPlaying) {
          _updateState(stateMap: PlayerManager.playing);
          _updateState(message: isBuffering ? toastString : 'HIDE_CONTAINER', userPaused: false);
          _timerManager.cancelTimer(TimerType.bufferingCheck);
          if (!_timerManager.isActive(TimerType.playDuration)) {
            _startPlayDurationTimer();
          }
        }
        _adManager.onVideoStartPlaying();
        break;
      case BetterPlayerEventType.pause:
        if (isPlaying) {
          _updateState(
            playing: false,
            message: S.current.playpause,
            showPlay: _isUserPaused,
            showPause: !_isUserPaused,
          );
          LogUtil.i('暂停播放，用户触发: $_isUserPaused');
        }
        break;
      case BetterPlayerEventType.progress:
        if (_isParsing || _isSwitchingChannel || !_progressEnabled || !isPlaying) return;
        final position = event.parameters?["progress"] as Duration?;
        final duration = event.parameters?["duration"] as Duration?;
        if (position != null && duration != null) {
          final remainingTime = duration - position;
          if (_isHls) {
            if (_preCachedUrl != null && remainingTime.inSeconds <= PlayerManager.hlsSwitchThresholdSeconds) {
              await _switchToPreCachedUrl('HLS剩余时间触发');
            }
          } else {
            if (remainingTime.inSeconds <= PlayerManager.nonHlsPreloadThresholdSeconds) {
              final nextUrl = _getNextVideoUrl();
              if (nextUrl != null && nextUrl != _preCachedUrl) {
                LogUtil.i('非HLS预加载: $nextUrl');
                _preloadNextVideo(nextUrl);
              }
            }
            if (remainingTime.inSeconds <= PlayerManager.nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
              await _switchToPreCachedUrl('非HLS切换触发');
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
          _handleNoMoreSources();
        }
        break;
      default:
        break;
    }
  }

  // 启动m3u8检查
  void _startM3u8Monitor() {
    if (!_isHls) return;
    _timerManager.cancelTimer(TimerType.m3u8Check);
    _timerManager.startPeriodicTimer(
      TimerType.m3u8Check,
      const Duration(seconds: m3u8CheckIntervalSeconds),
      (_) async {
        if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) return;
        if (_currentPlayUrl?.isNotEmpty == true) {
          try {
            final content = await HttpUtil().getRequest<String>(
              _currentPlayUrl!,
              retryCount: 1,
              cancelToken: _currentCancelToken,
            );
            bool isValid = content?.isNotEmpty == true &&
                (content!.contains('.ts') ||
                    content.contains('#EXTINF') ||
                    content.contains('#EXT-X-STREAM-INF'));
            if (!isValid) {
              _m3u8InvalidCount++;
              LogUtil.i('m3u8失效，次数: $_m3u8InvalidCount');
              if (_m3u8InvalidCount >= 2) {
                LogUtil.i('m3u8连续失效，重新解析');
                _m3u8InvalidCount = 0;
                await _reparseAndSwitch();
              }
            } else {
              _m3u8InvalidCount = 0;
            }
          } catch (e) {
            LogUtil.e('m3u8检查失败: $e');
            _m3u8InvalidCount++;
            if (_m3u8InvalidCount >= 3) {
              LogUtil.i('m3u8检查异常过多，重新解析');
              _m3u8InvalidCount = 0;
              await _reparseAndSwitch();
            }
          }
        }
      },
    );
  }

  // 启动播放时长检查
  void _startPlayDurationTimer() {
    _timerManager.cancelTimer(TimerType.playDuration);
    _timerManager.startTimer(TimerType.playDuration, const Duration(seconds: initialProgressDelaySeconds), () {
      if (!_canPerformOperation('播放时长检查', checkParsing: false)) return;
      LogUtil.i('播放时长检查启动');
      if (_isHls) {
        if (_originalUrl?.toLowerCase().contains('timelimit') ?? false) {
          _startM3u8Monitor();
        }
      } else {
        if (_getNextVideoUrl() != null) {
          _updateState(progressEnabled: true);
          LogUtil.i('非HLS启用progress监听');
        }
      }
      _updateState(retryCount: 0);
    });
  }

  // 预加载下一视频
  Future<void> _preloadNextVideo(String url) async {
    if (!_canPerformOperation('预加载视频')) return;
    if (_playerController == null) {
      LogUtil.e('预加载失败: 无播放器控制器');
      return;
    }
    if (_preCachedUrl == url) {
      LogUtil.i('URL已预缓存: $url');
      return;
    }
    await _cleanupPreCache();
    try {
      LogUtil.i('开始预加载: $url');
      _preloadCancelToken.cancel();
      _preloadCancelToken = CancelToken();
      String parsedUrl = await PlayerManager.executePlayback(
        originalUrl: url,
        cancelToken: _preloadCancelToken,
        channelTitle: _currentChannel?.title,
      );
      if (_playerController == null) {
        LogUtil.e('预缓存失败: 播放器已释放');
        return;
      }
      _preCacheStreamUrl = StreamUrl(url, cancelToken: _preloadCancelToken);
      _preCachedUrl = parsedUrl;
      await PlayerManager.playSource(
        controller: _playerController!,
        url: parsedUrl,
        isHls: PlayerManager.isHlsStream(parsedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
        preloadOnly: true,
      );
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e) {
      LogUtil.e('预加载失败: $e');
      _preCachedUrl = null;
      await _cleanupPreCache();
      if (_playerController != null) {
        try {
          await _playerController!.clearCache();
        } catch (clearError) {
          LogUtil.e('清除缓存失败: $clearError');
        }
      }
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
    } catch (e) {
      LogUtil.e('中文转换器初始化失败: $e');
    } finally {
      _zhConvertersInitializing = false;
    }
  }

  // 重试播放
  void _retryPlayback({bool resetRetryCount = false}) {
    if (!_canPerformOperation('重试播放') || _isParsing) {
      LogUtil.i('重试阻止: ${_isParsing ? "正在解析" : "状态冲突"}');
      return;
    }
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.timeout);
    if (resetRetryCount) {
      _updateState(retryCount: 0);
    }
    if (_retryCount < PlayerManager.defaultMaxRetries) {
      _updateState(stateMap: {
        ...PlayerManager.retrying(_retryCount + 1),
        'message': S.current.retryplay,
      });
      LogUtil.i('重试播放: 第$_retryCount次');
      _timerManager.startTimer(TimerType.retry, const Duration(seconds: PlayerManager.retryDelaySeconds), () async {
        if (!_canPerformOperation('执行重试')) return;
        await _playVideo(isRetry: true);
        if (mounted) _updateState(retrying: false);
      });
    } else {
      LogUtil.i('重试超限，切换下一源');
      _handleSourceSwitching();
    }
  }

  // 获取下一视频源
  String? _getNextVideoUrl() {
    if (_currentChannel?.urls?.isEmpty ?? true) return null;
    final List<String> urls = _currentChannel!.urls!;
    final nextSourceIndex = _sourceIndex + 1;
    return nextSourceIndex < urls.length ? urls[nextSourceIndex] : null;
  }

  // 处理源切换
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.timeout);
    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      LogUtil.i('无更多源');
      _handleNoMoreSources();
      return;
    }
    _switchAttemptCount++;
    if (_switchAttemptCount > maxSwitchAttempts) {
      LogUtil.e('切换尝试超限: $_switchAttemptCount');
      _handleNoMoreSources();
      _switchAttemptCount = 0;
      return;
    }
    _updateState(
      sourceIndex: _sourceIndex + 1,
      buffering: false,
      message: S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? ''),
    );
    _updateState(stateMap: PlayerManager.resetOperations);
    _preCachedUrl = null;
    LogUtil.i('切换下一源: $nextUrl');
    _startNewSourceTimer();
  }

  // 处理无更多源
  Future<void> _handleNoMoreSources() async {
    _updateState(stateMap: {
      ...PlayerManager.error,
      'message': S.current.playError,
      'sourceIndex': 0,
    });
    await _releaseAllResources(isDisposing: false);
    LogUtil.i('播放结束，无更多源');
    _switchAttemptCount = 0;
  }

  // 启动新源播放
  void _startNewSourceTimer() {
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.startTimer(TimerType.retry, const Duration(seconds: PlayerManager.retryDelaySeconds), () async {
      if (!_canPerformOperation('启动新源', checkParsing: false)) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  // 释放所有资源
  Future<void> _releaseAllResources({bool isDisposing = false}) async {
    if (_isDisposing && !isDisposing) {
      LogUtil.i('资源释放中，跳过');
      return;
    }
    _updateState(disposing: true);
    _timerManager.cancelAll();
    _currentCancelToken.cancel();
    _preloadCancelToken.cancel();
    try {
      if (_playerController != null) {
        final controller = _playerController!;
        _playerController = null;
        controller.removeEventsListener(_videoListener);
        await PlayerManager.safeDisposeResource(controller);
      }
      final currentStreamUrl = _streamUrl;
      final preStreamUrl = _preCacheStreamUrl;
      _streamUrl = null;
      _preCacheStreamUrl = null;
      if (currentStreamUrl != null) {
        await PlayerManager.safeDisposeResource(currentStreamUrl);
      }
      if (preStreamUrl != null && preStreamUrl != currentStreamUrl) {
        await PlayerManager.safeDisposeResource(preStreamUrl);
      }
      if (isDisposing) {
        _adManager.dispose();
      } else {
        _adManager.reset(rescheduleAds: false, preserveTimers: true);
      }
      if (mounted && !isDisposing) {
        _updateState(stateMap: {
          ...PlayerManager.resetOperations,
          'playing': false,
          'buffering': false,
          'showPlay': false,
          'showPause': false,
          'userPaused': false,
          'progressEnabled': false,
        });
        _preCachedUrl = null;
        _lastParseTime = null;
        _currentPlayUrl = null;
        _originalUrl = null;
        _m3u8InvalidCount = 0;
      }
      await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
      LogUtil.i('资源释放完成');
    } catch (e) {
      LogUtil.e('资源释放失败: $e');
    } finally {
      _updateState(disposing: false);
      if (_pendingSwitch != null && mounted) {
        LogUtil.i('处理待切换请求: ${_pendingSwitch!.channel?.title}');
        Future.microtask(() {
          if (mounted && !_isDisposing) {
            _processPendingSwitch();
          }
        });
      }
    }
  }

  // 重新解析并切换
  Future<void> _reparseAndSwitch({bool force = false}) async {
    if (!_canPerformOperation('重新解析')) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastParseTime != null) {
      final timeSinceLastParse = now - _lastParseTime!;
      if (timeSinceLastParse < reparseMinIntervalMilliseconds) {
        LogUtil.i('解析频率过高，延迟${reparseMinIntervalMilliseconds - timeSinceLastParse}ms');
        _timerManager.startTimer(TimerType.retry, Duration(milliseconds: (reparseMinIntervalMilliseconds - timeSinceLastParse).toInt()), () {
          if (mounted) _reparseAndSwitch(force: true);
        });
        return;
      }
    }
    _timerManager.cancelTimer(TimerType.retry);
    _timerManager.cancelTimer(TimerType.m3u8Check);
    _updateState(parsing: true);
    try {
      if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
        LogUtil.e('频道信息无效');
        throw Exception('无效频道');
      }
      _updateState(switching: true);
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析: $url');
      await PlayerManager.safeDisposeResource(_streamUrl);
      _streamUrl = null;
      _currentCancelToken.cancel();
      _currentCancelToken = CancelToken();
      String parsedUrl = await PlayerManager.executePlayback(
        originalUrl: url,
        cancelToken: _currentCancelToken,
        channelTitle: _currentChannel?.title,
      );
      _streamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
      _preCachedUrl = parsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl');
      if (_playerController != null) {
        if (_isDisposing) {
          LogUtil.i('解析中断');
          _preCachedUrl = null;
          _updateState(parsing: false, switching: false);
          return;
        }
        await PlayerManager.playSource(
          controller: _playerController!,
          url: parsedUrl,
          isHls: PlayerManager.isHlsStream(parsedUrl),
          channelTitle: _currentChannel?.title,
          channelLogo: _getChannelLogo(),
          preloadOnly: true,
        );
        if (_isDisposing) {
          LogUtil.i('预加载中断');
          _preCachedUrl = null;
          _updateState(parsing: false, switching: false);
          return;
        }
        _updateState(progressEnabled: true);
        _lastParseTime = now;
        LogUtil.i('预缓存完成');
      } else {
        LogUtil.i('无播放器，切换下一源');
        _handleSourceSwitching();
      }
      _updateState(switching: false);
    } catch (e) {
      LogUtil.e('重新解析失败: $e');
      _preCachedUrl = null;
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        _updateState(parsing: false);
      }
    }
  }

  // 提取地理信息
  Future<Map<String, String?>> _getLocationInfo(String? userInfo) async {
    if (userInfo?.isEmpty ?? true) {
      LogUtil.i('无地理信息');
      return {'region': null, 'city': null};
    }
    try {
      final Map<String, dynamic> userData = jsonDecode(userInfo!);
      final Map<String, dynamic>? locationData = userData['info']?['location'];
      if (locationData == null) {
        LogUtil.i('无location字段');
        return {'region': null, 'city': null};
      }
      String? region = locationData['region'] as String?;
      String? city = locationData['city'] as String?;
      if ((region?.isEmpty ?? true) && (city?.isEmpty ?? true)) {
        return {'region': null, 'city': null};
      }
      if (!mounted) return {'region': null, 'city': null};
      final currentLocale = Localizations.localeOf(context).toString();
      LogUtil.i('语言环境: $currentLocale');
      if (currentLocale.startsWith('zh')) {
        if (!_zhConvertersInitialized) {
          await _initializeZhConverters();
        }
        if (_zhConvertersInitialized) {
          bool isTraditional = currentLocale.contains('TW') ||
              currentLocale.contains('HK') ||
              currentLocale.contains('MO');
          ZhConverter? converter = isTraditional ? _s2tConverter : _t2sConverter;
          String targetType = isTraditional ? '繁体' : '简体';
          if (converter != null) {
            if (region?.isNotEmpty ?? false) {
              String oldRegion = region!;
              region = converter.convertSync(region);
              LogUtil.i('region转换$targetType: $oldRegion -> $region');
            }
            if (city?.isNotEmpty ?? false) {
              String oldCity = city!;
              city = converter.convertSync(city);
              LogUtil.i('city转换$targetType: $oldCity -> $city');
            }
          }
        } else {
          LogUtil.e('转换器初始化失败');
        }
      }
      final String? regionPrefix = (region?.length ?? 0) >= 2 ? region!.substring(0, 2) : region;
      final String? cityPrefix = (city?.length ?? 0) >= 2 ? city!.substring(0, 2) : city;
      LogUtil.i('地理信息: 地区=$regionPrefix, 城市=$cityPrefix');
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e) {
      LogUtil.e('解析地理信息失败: $e');
      return {'region': null, 'city': null};
    }
  }

  // 按地理前缀排序
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix?.isEmpty ?? true) {
      LogUtil.i('无地理前缀，保持原序');
      return items;
    }
    if (items.isEmpty) {
      LogUtil.i('列表为空');
      return items;
    }
    final matchingItems = <String>[];
    final nonMatchingItems = <String>[];
    for (var item in items) {
      if (item.startsWith(prefix!)) {
        matchingItems.add(item);
      } else {
        nonMatchingItems.add(item);
      }
    }
    final result = [...matchingItems, ...nonMatchingItems];
    LogUtil.i('排序结果: $result');
    return result;
  }

  // 按地理信息排序播放列表
  Future<void> _sortVideoMap(PlaylistModel videoMap, String? userInfo) async {
    if (videoMap.playList?.isEmpty ?? true) return;
    final location = await _getLocationInfo(userInfo);
    final String? regionPrefix = location['region'];
    final String? cityPrefix = location['city'];
    if (regionPrefix?.isEmpty ?? true) {
      LogUtil.i('无地区前缀，跳过排序');
      return;
    }
    videoMap.playList!.forEach((category, groups) {
      if (groups is! Map<String, Map<String, PlayModel>>) {
        LogUtil.e('分类 $category 类型无效');
        return;
      }
      final groupList = groups.keys.toList();
      bool categoryNeedsSort = groupList.any((group) => group.contains(regionPrefix!));
      if (!categoryNeedsSort) return;
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
        if (regionPrefix != null && group.contains(regionPrefix) && (cityPrefix?.isNotEmpty ?? false)) {
          final sortedChannels = _sortByGeoPrefix(channelList, cityPrefix);
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

  // 处理频道点击
  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;
    try {
      _updateState(
        buffering: false,
        message: S.current.loading,
      );
      _updateState(stateMap: PlayerManager.resetOperations);
      _timerManager.cancelTimer(TimerType.retry);
      _timerManager.cancelTimer(TimerType.m3u8Check);
      _currentChannel = model;
      _updateState(sourceIndex: 0, shouldUpdateAspectRatio: true);
      _switchAttemptCount = 0;
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e) {
      LogUtil.e('切换频道失败: $e');
      _updateState(message: S.current.playError);
      await _releaseAllResources(isDisposing: false);
    }
  }

  // 切换频道源
  Future<void> _changeChannelSources() async {
    final sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) {
      LogUtil.e('无有效源');
      return;
    }
    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null) {
      _updateState(sourceIndex: selectedIndex);
      _updateState(stateMap: PlayerManager.resetOperations);
      _switchAttemptCount = 0;
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
    }
  }

  // 处理返回键
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      _updateState(drawerIsOpen: false);
      return false;
    }
    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) await _playerController?.pause();
    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    if (!shouldExit && wasPlaying && mounted) await _playerController?.play();
    return shouldExit;
  }

  // 处理用户暂停
  void _handleUserPaused() => _updateState(userPaused: true);

  // 处理重试
  void _handleRetry() => _retryPlayback(resetRetryCount: true);

  @override
  void initState() {
    super.initState();
    _currentCancelToken = CancelToken();
    _preloadCancelToken = CancelToken();
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

  // 发送流量统计
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
      } catch (e) {
        LogUtil.e('流量统计失败: $e');
      }
    }
  }

  // 加载播放数据
  Future<void> _loadData() async {
    _updateState(stateMap: PlayerManager.resetOperations);
    _timerManager.cancelAll();
    _updateState(audio: false);
    if (widget.m3uData.playList?.isEmpty ?? true) {
      LogUtil.e('播放列表无效');
      _updateState(message: S.current.getDefaultError);
      return;
    }
    try {
      _videoMap = widget.m3uData;
      String? userInfo = SpUtil.getString('user_all_info');
      LogUtil.i('加载用户地理信息');
      await _initializeZhConverters();
      await _sortVideoMap(_videoMap!, userInfo);
      _updateState(sourceIndex: 0);
      await _handlePlaylist();
    } catch (e) {
      LogUtil.e('加载播放列表失败: $e');
      _updateState(message: S.current.parseError);
    }
  }

  // 处理播放列表
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getFirstChannel(_videoMap!.playList!);
      if (_currentChannel != null) {
        if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
        _updateState(retryCount: 0, timeoutActive: false);
        _switchAttemptCount = 0;
        if (!_isSwitchingChannel && !_isRetrying && !_isParsing) {
          await _queueSwitchChannel(_currentChannel, _sourceIndex);
        } else {
          LogUtil.i('用户操作中，跳过切换');
        }
      } else {
        _updateState(message: 'UNKNOWN', retrying: false);
      }
    } else {
      _currentChannel = null;
      _updateState(message: 'UNKNOWN', retrying: false);
    }
  }

  // 获取首个频道
  PlayModel? _getFirstChannel(Map<String, dynamic> playList) {
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
    } catch (e) {
      LogUtil.e('提取频道失败: $e');
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

  // 切换收藏状态
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
        if (mounted) _updateState(drawerRefreshKey: ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: snackBarDurationSeconds));
        LogUtil.e('保存收藏失败: $error');
      }
    }
  }

  // 解析播放数据
  Future<void> _parseData() async {
    try {
      if (_videoMap?.playList?.isEmpty ?? true) {
        LogUtil.e('播放列表无效');
        _updateState(message: S.current.getDefaultError);
        return;
      }
      _updateState(sourceIndex: 0);
      _switchAttemptCount = 0;
      await _handlePlaylist();
    } catch (e) {
      LogUtil.e('处理播放列表失败: $e');
      _updateState(message: S.current.parseError);
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
                onCloseDrawer: () => _updateState(drawerIsOpen: false),
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
                          onToggleDrawer: () => _updateState(drawerIsOpen: !_drawerIsOpen),
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
                    onTap: () => _updateState(drawerIsOpen: false),
                    child: ChannelDrawerPage(
                      key: _drawerRefreshKey,
                      refreshKey: _drawerRefreshKey,
                      videoMap: _videoMap,
                      playModel: _currentChannel,
                      onTapChannel: _onTapChannel,
                      isLandscape: true,
                      onCloseDrawer: () => _updateState(drawerIsOpen: false),
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
