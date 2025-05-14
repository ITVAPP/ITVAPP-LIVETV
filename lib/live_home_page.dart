// 修改代码开始
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

/// 主页面，负责展示直播内容
class LiveHomePage extends StatefulWidget { 
  final PlaylistModel m3uData; // 播放列表数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

/// 计时器类型枚举，用于区分不同计时任务
enum TimerType {
  retry,        // 重试计时器
  m3u8Check,    // m3u8 检查计时器
  playDuration, // 播放时长计时器
  timeout,      // 超时计时器
  bufferingCheck, // 缓冲检查计时器
}

/// 频道切换请求类，封装切换所需的频道和源索引
class SwitchRequest {
  final PlayModel? channel; // 目标频道
  final int sourceIndex;    // 源索引
  SwitchRequest(this.channel, this.sourceIndex);
}

/// 计时器管理类，统一管理所有计时任务
class TimerManager {
  final Map<TimerType, Timer?> _timers = {}; // 存储计时器实例

  /// 启动单次计时器
  void startTimer(TimerType type, Duration duration, Function() callback) {
    cancelTimer(type); // 先取消同类型计时器
    _timers[type] = Timer(duration, () {
      callback();
      _timers[type] = null; // 执行后清理
    });
  }
  
  /// 启动周期性计时器
  void startPeriodicTimer(TimerType type, Duration period, Function(Timer) callback) {
    cancelTimer(type);
    _timers[type] = Timer.periodic(period, callback);
  }
  
  /// 取消指定计时器
  void cancelTimer(TimerType type) {
    if (_timers[type]?.isActive == true) {
      _timers[type]?.cancel();
      _timers[type] = null;
    }
  }
  
  /// 取消所有计时器并清理映射
  void cancelAll() {
    TimerType.values.forEach(cancelTimer);
    _timers.clear();
  }
  
  /// 检查计时器是否活跃
  bool isActive(TimerType type) => _timers[type]?.isActive == true;
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int defaultMaxRetries = 1; // 默认最大重试次数
  static const int defaultTimeoutSeconds = 38; // 默认超时时间（秒）
  static const int initialProgressDelaySeconds = 60; // 初始进度检查延迟（秒）
  static const int retryDelaySeconds = 2; // 重试延迟（秒）
  static const int hlsSwitchThresholdSeconds = 3; // HLS 切换阈值（秒）
  static const int nonHlsPreloadThresholdSeconds = 20; // 非 HLS 预加载阈值（秒）
  static const int nonHlsSwitchThresholdSeconds = 3; // 非 HLS 切换阈值（秒）
  static const double defaultAspectRatio = 1.78; // 默认宽高比
  static const int cleanupDelayMilliseconds = 500; // 切换和清理延迟（毫秒）
  static const int snackBarDurationSeconds = 5; // 提示条显示时长（秒）
  static const int m3u8InvalidConfirmDelaySeconds = 1; // m3u8 失效确认延迟（秒）
  static const int m3u8CheckIntervalSeconds = 10; // m3u8 检查间隔（秒）
  static const int reparseMinIntervalMilliseconds = 10000; // m3u8 重新检查间隔（毫秒）
  static const int m3u8ConnectTimeoutSeconds = 5; // m3u8 连接超时（秒）
  static const int m3u8ReceiveTimeoutSeconds = 10; // m3u8 接收超时（秒）
  static const int maxSwitchAttempts = 3; // 最大切换尝试次数

  String? _preCachedUrl; // 预缓存的播放地址
  bool _isParsing = false; // 是否正在解析
  bool _isRetrying = false; // 是否正在重试
  int? _lastParseTime; // 上次解析时间戳
  String toastString = S.current.loading; // 当前提示信息
  PlaylistModel? _videoMap; // 视频播放列表数据
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
  bool _isHls = false; // 是否为 HLS 流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{}, // 收藏列表
  };
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析实例
  bool _isAudio = false; // 是否为音频流
  late AdManager _adManager; // 广告管理实例
  bool _isUserPaused = false; // 用户是否暂停
  bool _showPlayIcon = false; // 是否显示播放图标
  bool _showPauseIconFromListener = false; // 是否显示暂停图标（监听器触发）
  int _m3u8InvalidCount = 0; // m3u8 失效计数
  int _switchAttemptCount = 0; // 切换尝试计数
  
  // 添加中文转换器实例
  ZhConverter? _s2tConverter; // 简体转繁体转换器
  ZhConverter? _t2sConverter; // 繁体转简体转换器
  // 添加中文转换器初始化状态标志
  bool _zhConvertersInitializing = false; // 是否正在初始化中文转换器
  bool _zhConvertersInitialized = false; // 中文转换器是否已初始化完成

  final TimerManager _timerManager = TimerManager(); // 计时器管理实例
  SwitchRequest? _pendingSwitch; // 待处理的切换请求
  Timer? _debounceTimer; // 防抖定时器
  
  // 新增：添加广告管理器初始化状态和最后播放的频道ID
  bool _hasInitializedAdManager = false;
  String? _lastPlayedChannelId;

  /// 获取频道logo，如果没有则返回默认logo
  String _getChannelLogo() {
    if (_currentChannel?.logo == null || _currentChannel!.logo!.isEmpty) {
      return 'assets/images/logo-2.png'; // 默认logo路径
    }
    return _currentChannel!.logo!;
  }

  /// 检查 URL 是否符合指定格式
  bool _checkUrlFormat(String? url, List<String> formats) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return formats.any(lowercaseUrl.contains);
  }

  /// 判断是否为音频流
  bool _checkIsAudioStream(String? url) {
    // 根据Config中的videoPlayMode设置决定是否为音频流
    // true表示视频播放模式，false表示音频播放模式
    return !Config.videoPlayMode;
  }

  /// 判断是否为 HLS 流
  bool _isHlsStream(String? url) {
    if (_checkUrlFormat(url, ['.m3u8'])) return true;
    return !_checkUrlFormat(url, [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac', '.flv', 'rtmp:'
    ]);
  }

  /// 更新当前播放地址并判断流类型
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  /// 更新播放状态，批量设置界面状态
  void _updatePlayState({
    bool? playing, bool? buffering, String? message, bool? showPlay, bool? showPause,
    bool? userPaused, bool? switching, bool? retrying, bool? parsing, int? sourceIndex, int? retryCount,
  }) {
    if (!mounted) return;
    
    // 合并所有状态更新到一次setState调用，减少UI重建次数
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

  /// 检查是否可以执行操作，避免状态冲突
  bool _canPerformOperation(String operationName, {
    bool checkRetrying = true, bool checkSwitching = true, bool checkDisposing = true, bool checkParsing = true,
  }) {
    if (checkDisposing && _isDisposing) {
      LogUtil.i('$operationName 被阻止: 正在释放资源');
      return false;
    }
    
    final List<String> blockers = [];
    if (checkRetrying && _isRetrying) blockers.add('正在重试');
    if (checkSwitching && _isSwitchingChannel) blockers.add('正在切换频道');
    if (checkParsing && _isParsing) blockers.add('正在解析');
    
    if (blockers.isNotEmpty) {
      LogUtil.i('$operationName 被阻止: ${blockers.join(", ")}');
      return false;
    }
    return true;
  }

  /// 准备预缓存数据源
  Future<void> _preparePreCacheSource(String url) async {
    if (_playerController == null) {
      LogUtil.e('预缓存失败: 播放器控制器为null');
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

  /// 切换到预缓存地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
    if (_isDisposing) {
      LogUtil.i('$logDescription: 正在释放资源，跳过切换');
      return;
    }
    
    _timerManager.cancelAll();
    if (_preCachedUrl == null) {
      LogUtil.i('$logDescription: 预缓存地址为空，无法切换');
      return;
    }
    
    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址与当前地址相同，跳过切换，尝试重新解析');
      _preCachedUrl = null;
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
      await _reparseAndSwitch();
      return;
    }
    
    try {
      _updatePlayState(switching: true); // 设置切换标志位
      
      if (_playerController == null) {
        LogUtil.e('$logDescription: 切换失败，播放器控制器为null');
        _updatePlayState(switching: false);
        return;
      }
      
      await _preparePreCacheSource(_preCachedUrl!);
      LogUtil.i('$logDescription: 预缓存新数据源完成: $_preCachedUrl');
      
      final newSource = BetterPlayerConfig.createDataSource(
        url: _preCachedUrl!, 
        isHls: _isHlsStream(_preCachedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      
      await _playerController?.setupDataSource(newSource);
      await _playerController?.play();
      
      LogUtil.i('$logDescription: 切换到预缓存地址并开始播放');
      _startPlayDurationTimer();
      _updatePlayUrl(_preCachedUrl!);
      _updatePlayState(playing: true, switching: false);
      
      // 重置切换计数
      _switchAttemptCount = 0;
    } catch (e, stackTrace) {
      LogUtil.logError('$logDescription: 切换到预缓存地址失败', e, stackTrace);
      _updatePlayState(switching: false);
      _retryPlayback();
      return;
    } finally {
      _progressEnabled = false;
      _preCachedUrl = null;
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
    }
  }

  /// 执行视频播放流程
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null) {
      LogUtil.e('播放视频失败：_currentChannel 为 null');
      return;
    }
    
    if (!_isSourceIndexValid()) {
      LogUtil.e('播放视频失败：源索引无效');
      return;
    }
    
    // 判断是否为频道切换（而非仅源切换）
    bool isChannelChange = !isSourceSwitch || (_lastPlayedChannelId != _currentChannel!.id);
    String channelId = _currentChannel?.id ?? _currentChannel!.title ?? 'unknown_channel';
    _lastPlayedChannelId = channelId;
    
    // 只在真正的频道切换时通知广告管理器
    if (isChannelChange) {
      _adManager.onChannelChanged(channelId);
    }
    
    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');
    
    // 清理旧计时器并设置状态
    _timerManager.cancelAll();
    _updatePlayState(
      message: '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
      playing: false,
      buffering: false,
      showPlay: false,
      showPause: false,
      userPaused: false,
      switching: true,
    );
    
    // 启动超时检测
    _startPlaybackTimeout();
    
    try {
      // 只在新频道（非重试、非源切换）的情况下检查视频广告
      if (!isRetry && !isSourceSwitch && isChannelChange && _hasInitializedAdManager) {
        try {
          // 使用异步方法确保广告数据已加载
          bool shouldPlay = await _adManager.shouldPlayVideoAdAsync();
          if (shouldPlay) {
            await _adManager.playVideoAd();
            LogUtil.i('视频广告播放完成，准备播放内容');
          }
        } catch (e) {
          LogUtil.e('视频广告处理发生错误: $e，继续播放内容');
        }
      }
      
      // 在开始新播放前释放旧资源
      if (_playerController != null) {
        await _releaseAllResources(isDisposing: false);
      }
      
      // 准备播放URL，设置播放器，开始播放
      await _preparePlaybackUrl();
      await _setupPlayerController();
      await _startPlayback();
      
      // 重置切换尝试计数
      _switchAttemptCount = 0;
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      
      // 增加切换尝试计数并处理
      _switchAttemptCount++;
      if (_switchAttemptCount <= maxSwitchAttempts) {
        _handleSourceSwitching();
      } else {
        // 超过最大尝试次数，重置计数并显示错误
        _switchAttemptCount = 0;
        _updatePlayState(
          message: S.current.playError,
          playing: false,
          buffering: false,
          switching: false,
          retrying: false,
        );
      }
    } finally {
      if (mounted) {
        // 确保状态更新和处理待定切换
        _updatePlayState(switching: false);
        _processPendingSwitch();
      }
    }
  }

  /// 验证当前源索引是否有效
  bool _isSourceIndexValid() {
    if (_sourceIndex < 0 || _currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
      _sourceIndex = 0;
      if (_currentChannel?.urls == null || _currentChannel!.urls!.isEmpty) {
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

  /// 启动播放超时检测
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
      }
    );
  }

  /// 准备播放地址并解析流，优化错误处理
  Future<void> _preparePlaybackUrl() async {
    if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
      throw Exception('频道源索引无效');
    }
    
    String url = _currentChannel!.urls![_sourceIndex].toString();
    _originalUrl = url;
    
    // 清理旧的StreamUrl实例
    if (_streamUrl != null) {
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
    }
    
    // 创建新的StreamUrl实例并解析
    _streamUrl = StreamUrl(url);
    String parsedUrl = await _streamUrl!.getStreamUrl();
    
    if (parsedUrl == 'ERROR') {
      LogUtil.e('地址解析失败: $url');
      
      if (mounted) {
        setState(() {
          toastString = S.current.vpnplayError;
        });
      }
      
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      throw Exception('地址解析失败');
    }
    
    _updatePlayUrl(parsedUrl);
    
    // 根据Config配置设置音频模式
    bool isAudio = _checkIsAudioStream(null); // 参数不再使用
    setState(() => _isAudio = isAudio);
    
    // 日志记录播放信息
    LogUtil.i('播放信息 - URL: $parsedUrl, 音频模式: $isAudio, HLS: $_isHls, 视频播放模式: ${Config.videoPlayMode}');
  }

  /// 设置播放器控制器并初始化数据源，增强错误处理
  Future<void> _setupPlayerController() async {
    // 确保任何旧的控制器都已正确释放
    if (_playerController != null) {
      await _releaseAllResources(isDisposing: false);
    }
    
    if (_currentPlayUrl == null || _currentPlayUrl!.isEmpty) {
      throw Exception('播放地址为空');
    }
    
    try {
      final dataSource = BetterPlayerConfig.createDataSource(
        url: _currentPlayUrl!, 
        isHls: _isHls,
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener, 
        isHls: _isHls
      );
      
      _playerController = BetterPlayerController(betterPlayerConfiguration);
      await _playerController!.setupDataSource(dataSource);
      
      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      LogUtil.logError('设置播放器失败', e, stackTrace);
      await _releaseAllResources(isDisposing: false);
      throw e;
    }
  }

  /// 开始播放视频
  Future<void> _startPlayback() async {
    if (_playerController == null) {
      throw Exception('播放器控制器为空，无法开始播放');
    }
    
    await _playerController?.play();
    _timeoutActive = false;
    _timerManager.cancelTimer(TimerType.timeout);
  }

  /// 处理待执行的频道切换请求，优化防止切换冲突
  void _processPendingSwitch() {
    if (_pendingSwitch == null) {
      return;
    }
    
    if (_isParsing || _isRetrying || _isDisposing) {
      LogUtil.i('无法处理切换请求，因状态冲突: _isParsing=$_isParsing, _isRetrying=$_isRetrying, _isDisposing=$_isDisposing');
      return;
    }
    
    // 复制请求并立即清空队列，防止重复处理
    final nextRequest = _pendingSwitch!;
    _pendingSwitch = null;
    
    _currentChannel = nextRequest.channel;
    _sourceIndex = nextRequest.sourceIndex;
    
    // 使用microtask确保UI更新后再执行
    Future.microtask(() async {
      if (_playerController != null) {
        await _releaseAllResources(isDisposing: false);
      }
      await _playVideo();
    });
  }

  /// 队列化切换频道，增强防抖逻辑
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) {
      LogUtil.e('切换频道失败：channel 为 null');
      return;
    }
    
    final safeSourceIndex = _getSafeSourceIndex(channel, sourceIndex);

    // 取消任何待处理的定时器
    _debounceTimer?.cancel();
    
    // 创建新的防抖定时器
    _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
      if (!mounted) return;
      
      _pendingSwitch = SwitchRequest(channel, safeSourceIndex);
      LogUtil.i('防抖后更新最新切换请求: ${channel.title}, 源索引: $safeSourceIndex');
      
      if (!_isSwitchingChannel) {
        _processPendingSwitch();
      } else {
        // 添加超时保护
        _timerManager.startTimer(
          TimerType.timeout,
          Duration(seconds: m3u8ConnectTimeoutSeconds),
          () {
            if (mounted && _isSwitchingChannel) {
              LogUtil.e('切换操作超时(${m3u8ConnectTimeoutSeconds}秒)，强制处理队列');
              _updatePlayState(switching: false);
              _processPendingSwitch();
            }
          },
        );
      }
    });
  }

  /// 获取安全的源索引，避免越界
  int _getSafeSourceIndex(PlayModel channel, int requestedIndex) {
    if (channel.urls == null || channel.urls!.isEmpty) {
      LogUtil.e('频道没有可用源');
      return 0;
    }
    return channel.urls!.length > requestedIndex ? requestedIndex : 0;
  }

  /// 视频播放事件监听器，优化事件处理逻辑
  void _videoListener(BetterPlayerEvent event) async {
    // 跳过不需要处理的事件类型
    if (!mounted || _playerController == null || _isDisposing || 
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
          }
        }
        break;
        
      case BetterPlayerEventType.exception:
        // 如果正在解析和已在切换中则停止处理
        if (_isParsing || _isSwitchingChannel) {
          return;
        }
        
        final error = event.parameters?["error"] as String? ?? "Unknown error";
        LogUtil.e('播放器异常: $error');
        
        if (_preCachedUrl != null) {
          LogUtil.i('异常触发，预缓存地址已准备，立即切换');
          await _switchToPreCachedUrl('异常触发');
        } else {
          LogUtil.i('异常触发，预缓存地址未准备，启动重试');
          _retryPlayback();
        }
        break;
        
      case BetterPlayerEventType.bufferingStart:
        _updatePlayState(buffering: true, message: S.current.loading);
        break;
        
      case BetterPlayerEventType.bufferingEnd:
        _updatePlayState(
          buffering: false,
          message: 'HIDE_CONTAINER',
          showPause: _isUserPaused ? false : _showPauseIconFromListener,
        );
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
          if (!_timerManager.isActive(TimerType.playDuration)) {
            _startPlayDurationTimer();
          }
        }
        // 通知广告管理器视频已开始播放
        _adManager.onVideoStartPlaying();
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
        // 如果正在解析和已在切换中则停止处理
        if (_isParsing || _isSwitchingChannel) {
          return;
        }
        
        if (_progressEnabled && isPlaying) {
          final position = event.parameters?["progress"] as Duration?;
          final duration = event.parameters?["duration"] as Duration?;
          
          if (position != null && duration != null) {
            final remainingTime = duration - position;
            
            if (_isHls && _preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
              LogUtil.i('HLS 剩余时间少于 $hlsSwitchThresholdSeconds 秒，切换到预缓存地址');
              await _switchToPreCachedUrl('HLS 剩余时间触发切换');
            } else if (!_isHls) {
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
        LogUtil.i('播放结束，preCachedUrl: $_preCachedUrl');
        break;
        
      default:
        break;
    }
  }

  /// 异步检查 m3u8 文件有效性，避免阻塞UI线程
  Future<bool> _checkM3u8Validity() async {
    if (_currentPlayUrl == null || !_isHls) return true;
    
    try {
      // 使用隔离的Future实现异步检查
      final completer = Completer<bool>();
      
      Future(() async {
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
            completer.complete(false);
            return;
          }
          
          bool hasSegments = content.contains('.ts');
          bool hasValidDirectives = content.contains('#EXTINF') || content.contains('#EXT-X-STREAM-INF');
          bool isValid = hasSegments || hasValidDirectives;
          
          if (!isValid) {
            LogUtil.e('m3u8 内容无效，不包含有效标记或片段');
            completer.complete(false);
            return;
          }
          
          completer.complete(true);
        } catch (e, stackTrace) {
          LogUtil.logError('m3u8 有效性检查出错', e, stackTrace);
          completer.complete(false);
        }
      });
      
      return await completer.future;
    } catch (e, stackTrace) {
      LogUtil.logError('m3u8 有效性检查异常', e, stackTrace);
      return false;
    }
  }

  /// 启动 m3u8 检查定时器，优化异常处理
  void _startM3u8CheckTimer() {
    _timerManager.cancelTimer(TimerType.m3u8Check);
    if (!_isHls) return;
    
    _timerManager.startPeriodicTimer(
      TimerType.m3u8Check,
      const Duration(seconds: m3u8CheckIntervalSeconds),
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
                
                final secondCheck = await _checkM3u8Validity();
                if (!secondCheck) {
                  LogUtil.i('连续两次检查确认 m3u8 失效，触发重新解析');
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

  /// 启动播放时长检查定时器
  void _startPlayDurationTimer() {
    _timerManager.cancelTimer(TimerType.playDuration);
    _timerManager.startTimer(
      TimerType.playDuration,
      const Duration(seconds: initialProgressDelaySeconds),
      () {
        if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
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
  
  /// 预加载下一个视频源，优化错误处理
  Future<void> _preloadNextVideo(String url) async {
    if (!_canPerformOperation('预加载下一个视频', checkDisposing: true, checkSwitching: true, checkRetrying: false, checkParsing: false)) return;
    
    if (_playerController == null || _preCachedUrl != null) {
      LogUtil.i('预加载被阻止: controller=${_playerController != null}, _preCachedUrl=${_preCachedUrl != null}');
      return;
    }
    
    try {
      LogUtil.i('开始预加载: $url');
      
      // 清理旧的预缓存实例
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
      
      // 创建新的预缓存实例并解析
      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();
      
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposeStreamUrlInstance(_preCacheStreamUrl);
        _preCacheStreamUrl = null;
        return;
      }
      
      // 更新预缓存URL并设置缓存
      _preCachedUrl = parsedUrl;
      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl), 
        url: parsedUrl,
        channelTitle: _currentChannel?.title,
        channelLogo: _getChannelLogo(),
      );
      
      if (_playerController != null) {
        await _playerController!.preCache(nextSource);
        LogUtil.i('预缓存完成: $parsedUrl');
      } else {
        LogUtil.e('预缓存失败: 播放器控制器已为null');
        _preCachedUrl = null;
        await _disposeStreamUrlInstance(_preCacheStreamUrl);
        _preCacheStreamUrl = null;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
      
      if (_playerController != null) {
        try {
          await _playerController!.clearCache();
        } catch (clearError) {
          LogUtil.e('清除缓存失败: $clearError');
        }
      }
    }
  }

  /// 初始化中文转换器，优化初始化逻辑
  Future<void> _initializeZhConverters() async {
    // 如果已初始化或正在初始化，则不重复执行
    if (_zhConvertersInitialized || _zhConvertersInitializing) {
      return;
    }
    
    _zhConvertersInitializing = true;
    
    try {
      // 并行初始化两个转换器
      final futures = <Future>[];
      
      // 初始化简体转繁体转换器
      if (_s2tConverter == null) {
        _s2tConverter = ZhConverter('s2t'); // 简体转繁体
        futures.add(_s2tConverter!.initialize());
      }
      
      // 初始化繁体转简体转换器
      if (_t2sConverter == null) {
        _t2sConverter = ZhConverter('t2s'); // 繁体转简体
        futures.add(_t2sConverter!.initialize());
      }
      
      // 等待所有初始化完成
      await Future.wait(futures);
      
      _zhConvertersInitialized = true;
      LogUtil.i('中文转换器初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化中文转换器失败', e, stackTrace);
    } finally {
      _zhConvertersInitializing = false;
    }
  }

  /// 重试播放逻辑，增加防止无限循环的保护机制
  void _retryPlayback({bool resetRetryCount = false}) {
    if (!_canPerformOperation('重试播放')) return;
    
    if (_isParsing) {
      LogUtil.i('正在重新解析中，跳过重试，等待解析完成切换');
      return;
    }
    
    _timerManager.cancelAll();
    
    if (resetRetryCount) {
      _updatePlayState(retryCount: 0);
    }
    
    // 确保重试次数不超过限制
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
        const Duration(seconds: retryDelaySeconds),
        () async {
          if (!mounted || _isDisposing) {
            _updatePlayState(retrying: false);
            return;
          }
          
          // 再次检查状态，防止并发问题
          if (_isSwitchingChannel || _isParsing) {
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

  /// 获取下一个视频源地址
  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null) return null;
    
    final List<String> urls = _currentChannel!.urls!;
    if (urls.isEmpty) return null;
    
    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) return null;
    
    return urls[nextSourceIndex];
  }

  /// 处理源切换逻辑，增强错误处理
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;
    
    _timerManager.cancelAll();
    
    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      LogUtil.i('无更多源可切换');
      _handleNoMoreSources();
      return;
    }
    
    // 增加切换尝试计数
    _switchAttemptCount++;
    
    // 如果切换尝试次数超过限制，显示错误并重置
    if (_switchAttemptCount > maxSwitchAttempts) {
      LogUtil.e('切换尝试次数超过限制 ($maxSwitchAttempts)，停止切换');
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
    LogUtil.i('切换到下一源: $nextUrl (尝试次数: $_switchAttemptCount/${maxSwitchAttempts})');
    _startNewSourceTimer();
  }

  /// 处理无更多源的情况
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
    
    // 重置切换尝试计数
    _switchAttemptCount = 0;
  }

  /// 启动新源播放定时器
  void _startNewSourceTimer() {
    _timerManager.cancelAll();
    _timerManager.startTimer(
      TimerType.retry,
      const Duration(seconds: retryDelaySeconds),
      () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) return;
        await _playVideo(isSourceSwitch: true);
      }
    );
  }

  /// 释放所有资源，优化资源释放流程
  Future<void> _releaseAllResources({bool isDisposing = false}) async {
    // 防止重复释放
    if (_isDisposing) return;
    _isDisposing = true;
    
    try {
      LogUtil.i('开始释放所有资源');
      
      // 首先取消所有计时器
      _timerManager.cancelAll();
      
      // 释放播放器控制器
      if (_playerController != null) {
        try {
          // 移除事件监听器
          _playerController!.removeEventsListener(_videoListener);
          
          // 如果正在播放，先暂停并降低音量
          if (_playerController!.isPlaying() ?? false) {
            try {
              await _playerController!.pause();
              await _playerController!.setVolume(0);
              await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
            } catch (e) {
              LogUtil.e('暂停播放器失败: $e');
            }
          }
          
          // 释放视频播放器控制器
          if (_playerController!.videoPlayerController != null) {
            try {
              await _playerController!.videoPlayerController!.dispose();
            } catch (e) {
              LogUtil.e('释放视频播放器控制器失败: $e');
            }
          }
          
          // 释放播放器控制器
          try {
            _playerController!.dispose();
          } catch (e) {
            LogUtil.e('释放播放器控制器失败: $e');
          } finally {
            _playerController = null;
          }
        } catch (e, stackTrace) {
          LogUtil.logError('释放播放器资源失败', e, stackTrace);
        } finally {
          _playerController = null;
        }
      }
      
      // 释放流URL实例
      await Future.wait([
        _disposeStreamUrlInstance(_streamUrl),
        _disposeStreamUrlInstance(_preCacheStreamUrl),
      ]);
      
      _streamUrl = null;
      _preCacheStreamUrl = null;
      
      // 处理广告管理器
      if (isDisposing) {
        // 完全销毁时释放广告管理器
        _adManager.dispose();
      } else {
        // 否则只是重置状态，保留计时器
        _adManager.reset(rescheduleAds: false, preserveTimers: true);
      }
      
      // 更新状态
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
      
      // 延迟短暂时间确保资源完全释放
      await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
    } catch (e, stackTrace) {
      LogUtil.logError('释放资源过程中发生错误', e, stackTrace);
    } finally {
      // 只有在完全销毁时才保持_isDisposing为true
      _isDisposing = isDisposing;
    }
  }

  /// 释放 StreamUrl 实例，增强错误处理
  Future<void> _disposeStreamUrlInstance(StreamUrl? instance) async {
    if (instance == null) return;
    
    try {
      await instance.dispose();
    } catch (e, stackTrace) {
      LogUtil.logError('释放StreamUrl实例失败', e, stackTrace);
    }
  }

  /// 重新解析并切换播放地址，增强错误处理和频率限制
  Future<void> _reparseAndSwitch({bool force = false}) async {
    if (!_canPerformOperation('重新解析')) return;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 频率限制检查
    if (!force && _lastParseTime != null) {
      final timeSinceLastParse = now - _lastParseTime!;
      if (timeSinceLastParse < reparseMinIntervalMilliseconds) {
        final remainingWaitTime = reparseMinIntervalMilliseconds - timeSinceLastParse;
        LogUtil.i('解析频率过高，延迟 ${remainingWaitTime}ms 后解析');
        
        // 使用计时器延迟解析
        _timerManager.startTimer(
          TimerType.retry, 
          Duration(milliseconds: remainingWaitTime.toInt()), 
          () {
            if (mounted) _reparseAndSwitch(force: true);
          }
        );
        return;
      }
    }
    
    // 取消所有计时器并更新状态
    _timerManager.cancelAll();
    _updatePlayState(parsing: true, retrying: true);
    
    try {
      // 验证频道信息
      if (_currentChannel == null || _currentChannel!.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
        LogUtil.e('重新解析时频道信息无效');
        throw Exception('无效的频道信息');
      }
      
      _updatePlayState(switching: true);
      
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      
      // 清理旧的StreamUrl实例
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      
      // 创建新的StreamUrl实例并解析
      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();
      
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeStreamUrlInstance(_streamUrl);
        _streamUrl = null;
        throw Exception('解析失败');
      }
      
      // 检查新解析的URL是否与当前相同
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeStreamUrlInstance(_streamUrl);
        _streamUrl = null;
        _updatePlayState(parsing: false, retrying: false, switching: false);
        return;
      }
      
      _preCachedUrl = newParsedUrl;
      LogUtil.i('预缓存地址已准备: $_preCachedUrl');
      
      // 检查播放器控制器状态
      if (_playerController != null) {
        if (_isDisposing) {
          LogUtil.i('预加载前检测到中断，退出重新解析');
          _preCachedUrl = null;
          await _disposeStreamUrlInstance(_streamUrl);
          _streamUrl = null;
          _updatePlayState(parsing: false, retrying: false, switching: false);
          return;
        }
        
        // 预缓存新源
        await _preparePreCacheSource(newParsedUrl);
        
        if (_isDisposing) {
          LogUtil.i('预加载完成后检测到中断，退出重新解析');
          _preCachedUrl = null;
          await _disposeStreamUrlInstance(_streamUrl);
          _streamUrl = null;
          _updatePlayState(parsing: false, retrying: false, switching: false);
          return;
        }
        
        _progressEnabled = true;
        _lastParseTime = now;
        LogUtil.i('预缓存完成，等待剩余时间或异常触发切换');
      } else {
        LogUtil.i('播放器控制器为空，无法切换');
        _handleSourceSwitching();
      }
      
      _updatePlayState(switching: false);
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = null;
      _preCachedUrl = null;
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        _updatePlayState(parsing: false, retrying: false);
      }
    }
  }
  
  /// 从用户信息中提取地理位置信息并根据语言环境进行简繁转换
  Future<Map<String, String?>> _getLocationInfo(String? userInfo) async {
    if (userInfo == null || userInfo.isEmpty) {
      LogUtil.i('用户地理信息为空，使用默认顺序');
      return {'region': null, 'city': null};
    }
    
    try {
      final Map<String, dynamic> userData = jsonDecode(userInfo);
      final Map<String, dynamic>? locationData = userData['info']?['location'];
      
      if (locationData == null) {
        LogUtil.i('用户信息中无location字段');
        return {'region': null, 'city': null};
      }
      
      // 获取原始地理信息
      String? region = locationData['region'] as String?;
      String? city = locationData['city'] as String?;
      
      // 如果地理信息为空则提前返回
      if ((region == null || region.isEmpty) && (city == null || city.isEmpty)) {
        return {'region': null, 'city': null};
      }
      
      // 获取当前语言环境
      if (!mounted) return {'region': null, 'city': null};
      final currentLocale = Localizations.localeOf(context).toString();
      LogUtil.i('当前语言环境: $currentLocale');
      
      // 如果是中文环境，需要进行简繁转换
      if (currentLocale.startsWith('zh')) {
        // 确保转换器已初始化，但避免重复初始化
        if (!_zhConvertersInitialized) {
          await _initializeZhConverters();
        }
        
        // 如果转换器初始化失败，返回原始值
        if (!_zhConvertersInitialized) {
          LogUtil.e('中文转换器初始化失败，使用原始值');
          final String? regionPrefix = region != null && region.isNotEmpty
              ? (region.length >= 2 ? region.substring(0, 2) : region)
              : null;
          final String? cityPrefix = city != null && city.isNotEmpty
              ? (city.length >= 2 ? city.substring(0, 2) : city)
              : null;
          return {'region': regionPrefix, 'city': cityPrefix};
        }
        
        // 判断是简体还是繁体环境
        bool isTraditional = currentLocale.contains('TW') || 
                           currentLocale.contains('HK') || 
                           currentLocale.contains('MO');
        
        // 使用对应的转换器
        ZhConverter? converter = isTraditional ? _s2tConverter : _t2sConverter;
        String targetType = isTraditional ? '繁体' : '简体';
        
        if (converter != null) {
          // 转换 region
          if (region != null && region.isNotEmpty) {
            String oldRegion = region;
            region = converter.convertSync(region);
            LogUtil.i('region转换为$targetType: $oldRegion -> $region');
          }
          
          // 转换 city
          if (city != null && city.isNotEmpty) {
            String oldCity = city;
            city = converter.convertSync(city);
            LogUtil.i('city转换为$targetType: $oldCity -> $city');
          }
        }
      }
      
      // 提取前缀（保持原有逻辑）
      final String? regionPrefix = region != null && region.isNotEmpty
          ? (region.length >= 2 ? region.substring(0, 2) : region)
          : null;
      final String? cityPrefix = city != null && city.isNotEmpty
          ? (city.length >= 2 ? city.substring(0, 2) : city)
          : null;
          
      LogUtil.i('获取地理信息 - 地区: $region (前缀: $regionPrefix), 城市: $city (前缀: $cityPrefix)');
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e, stackTrace) {
      LogUtil.logError('解析地理信息失败', e, stackTrace);
      return {'region': null, 'city': null};
    }
  }

  /// 根据地理前缀排序列表 - 只将匹配前缀的项目提到前面，其余保持原顺序
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix == null || prefix.isEmpty) {
      LogUtil.i('地理前缀为空，返回原始顺序: $items');
      return items;
    }
    if (items.isEmpty) {
      LogUtil.i('待排序列表为空，返回空列表');
      return items;
    }
    
    // 分离匹配和不匹配的项目，保持原始顺序
    final List<String> matchingItems = [];
    final List<String> nonMatchingItems = [];
    
    for (var item in items) {
      if (item.startsWith(prefix)) {
        matchingItems.add(item);
      } else {
        nonMatchingItems.add(item);
      }
    }
    
    // 合并结果 - 匹配项在前，非匹配项保持原始顺序
    final result = [...matchingItems, ...nonMatchingItems];
    LogUtil.i('排序结果: $result');
    return result;
  }

  /// 根据地理信息排序视频播放列表
  Future<void> _sortVideoMap(PlaylistModel videoMap, String? userInfo) async {
    if (videoMap.playList == null || videoMap.playList!.isEmpty) {
      return;
    }
    
    final location = await _getLocationInfo(userInfo);
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
      if (!categoryNeedsSort) return;
      
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
          for (var channel in sortedChannels) newChannels[channel] = channels[channel]!;
        } else {
          for (var channel in channelList) newChannels[channel] = channels[channel]!;
        }
        
        newGroups[group] = newChannels;
      }
      
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成: ${newGroups.keys.toList()}');
    });
  }

  /// 处理频道点击事件
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
      
      // 重置切换尝试计数
      _switchAttemptCount = 0;
      
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
      
      if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      _updatePlayState(message: S.current.playError);
      await _releaseAllResources(isDisposing: false);
    }
  }

  /// 切换频道源
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) {
      LogUtil.e('未找到有效视频源');
      return;
    }
    
    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null) {
      _updatePlayState(sourceIndex: selectedIndex, retrying: false, retryCount: 0);
      
      // 重置切换尝试计数
      _switchAttemptCount = 0;
      
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
    }
  }

  /// 处理返回键事件
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

  /// 处理用户暂停事件
  void _handleUserPaused() => _updatePlayState(userPaused: true);

  /// 处理重试事件
  void _handleRetry() => _retryPlayback(resetRetryCount: true);

  @override
  void initState() {
    super.initState();
    
    // 初始化广告管理器
    _adManager = AdManager();
    
    // 在后台线程中加载广告数据，避免阻塞UI
    Future.microtask(() async {
      await _adManager.loadAdData();
      _hasInitializedAdManager = true;
    });
    
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden); // 非移动端隐藏标题栏
    _loadData(); // 加载播放数据
    _extractFavoriteList(); // 提取收藏列表
    
    // 记录当前播放模式配置
    LogUtil.i('当前播放模式配置: ${Config.videoPlayMode ? "视频播放模式" : "音频播放模式"}');
    
    // 预初始化中文转换器
    Future.microtask(() => _initializeZhConverters());
  }

  @override
  void dispose() {
    _releaseAllResources(isDisposing: true); // 释放所有资源
    favoriteList.clear(); 
    _videoMap = null;
    _s2tConverter = null; // 释放中文转换器资源
    _t2sConverter = null; // 释放中文转换器资源
    _debounceTimer?.cancel(); // 取消防抖定时器
    super.dispose();
  }

  /// 发送流量统计数据
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
  
  /// 加载播放数据并排序
  Future<void> _loadData() async {
    _updatePlayState(retrying: false, retryCount: 0);
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
      
      // 确保中文转换器已初始化
      await _initializeZhConverters();
      await _sortVideoMap(_videoMap!, userInfo);
      
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表失败', e, stackTrace);
      setState(() => toastString = S.current.parseError);
    }
  }

  /// 处理播放列表并选择首个可用频道
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);
      
      if (_currentChannel != null) {
        if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
        
        _updatePlayState(retryCount: 0);
        _timeoutActive = false;
        
        // 重置切换尝试计数
        _switchAttemptCount = 0;
        
        _queueSwitchChannel(_currentChannel, _sourceIndex);
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

  /// 从播放列表中提取首个可用频道
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    try {
      for (final categoryEntry in playList.entries) {
        final categoryData = categoryEntry.value;
        if (categoryData is Map<String, Map<String, PlayModel>>) {
          for (final groupEntry in categoryData.entries) {
            final channelMap = groupEntry.value;
            for (final channel in channelMap.values) {
              if (channel?.urls != null && channel!.urls!.isNotEmpty) return channel;
            }
          }
        } else if (categoryData is Map<String, PlayModel>) {
          for (final channel in categoryData.values) {
            if (channel?.urls != null && channel!.urls!.isNotEmpty) return channel;
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('提取频道失败', e, stackTrace);
    }
    return null;
  }

  /// 提取收藏列表数据
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

  /// 切换频道的收藏状态
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

  /// 解析播放数据
  Future<void> _parseData() async {
    try {
      if (_videoMap == null || _videoMap!.playList == null || _videoMap!.playList!.isEmpty) {
        LogUtil.e('播放列表无效');
        setState(() => toastString = S.current.getDefaultError);
        return;
      }
      
      _sourceIndex = 0;
      // 重置切换尝试计数
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
      return TvPage( // TV 模式界面
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
        portrait: (context) { // 竖屏布局
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
        landscape: (context) { // 横屏布局
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
// 修改代码结束
