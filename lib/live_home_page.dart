
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

// 播放器管理类，统一处理视频播放逻辑和状态
class PlayerManager {
  final String parsedUrl; // 解析后的视频地址
  final StreamUrl streamUrlInstance; // 流地址实例
  PlayerManager(this.parsedUrl, this.streamUrlInstance);
  
  static const int defaultMaxRetries = 1; // 最大重试次数
  static const int defaultTimeoutSeconds = 38; // 超时时间（秒）
  static const int retryDelaySeconds = 2; // 重试延迟（秒）
  static const int switchThresholdSeconds = 3; // 切换阈值（秒）
  static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS预加载阈值（秒）
  static const double defaultAspectRatio = 1.78; // 默认宽高比
  
  // 获取状态更新配置
  static Map<String, dynamic> getStateUpdate(String type, {int? retryCount}) {
    switch (type) {
      case 'playing':
        return {'playing': true, 'buffering': false, 'showPlay': false, 'showPause': false};
      case 'error':
        return {'playing': false, 'buffering': false, 'retrying': false, 'switching': false};
      case 'loading':
        return {'playing': false, 'buffering': false, 'showPlay': false, 'showPause': false, 'userPaused': false, 'switching': true};
      case 'resetOperations':
        return {'retrying': false, 'parsing': false, 'switching': false};
      case 'retrying':
        return {'retrying': true, 'retryCount': retryCount ?? 0, 'buffering': false, 'showPlay': false, 'showPause': false, 'userPaused': false};
      default:
        return {};
    }
  }

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

  // 播放或预缓存视频源
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
      LogUtil.i('播放视频: $url');
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
      streamUrl = StreamUrl(originalUrl, cancelToken: cancelToken);
      String parsedUrl = await streamUrl.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        throw Exception('地址解析失败: $originalUrl');
      }
      LogUtil.i('地址解析成功: $parsedUrl');
      return parsedUrl;
    } catch (e, stackTrace) {
      LogUtil.e('播放失败: $e\n$stackTrace');
      await safeDisposeResource(streamUrl);
      rethrow;
    }
  }

  // 释放指定资源
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
        LogUtil.i('播放器控制器已释放');
      } else if (resource is StreamUrl) {
        await resource.dispose();
        LogUtil.i('StreamUrl已释放');
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

class _LiveHomePageState extends State<LiveHomePage> {
  static const int initialProgressDelaySeconds = 60; // 初始进度检查延迟
  static const int cleanupDelayMilliseconds = 500; // 资源清理延迟
  static const int snackBarDurationSeconds = 5; // 提示显示时长
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
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析实例
  late AdManager _adManager; // 广告管理器
  bool _showPauseIconFromListener = false; // 是否显示暂停图标
  int _m3u8InvalidCount = 0; // m3u8失效计数
  int _switchAttemptCount = 0; // 切换尝试计数
  ZhConverter? _s2tConverter; // 简转繁转换器
  ZhConverter? _t2sConverter; // 繁转简转换器
  bool _zhConvertersInitializing = false; // 是否正在初始化转换器
  bool _zhConvertersInitialized = false; // 转换器初始化状态
  
  final Map<String, Timer?> _timers = {}; // 计时器映射
  Map<String, dynamic>? _pendingSwitch; // 待处理切换请求
  Timer? _debounceTimer; // 防抖定时器
  bool _hasInitializedAdManager = false; // 广告管理器初始化状态
  String? _lastPlayedChannelId; // 最后播放频道ID
  late CancelToken _cancelToken; // 统一取消令牌

  // 获取频道logo
  String _getChannelLogo() =>
      _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png';

  // 更新播放地址并判断流类型
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = PlayerManager.isHlsStream(_currentPlayUrl);
  }

  // 更新状态
  void _updateState(Map<String, dynamic> updates) {
    if (!mounted) return;
    setState(() {
      updates.forEach((key, value) {
        switch (key) {
          case 'playing': isPlaying = value; break;
          case 'buffering': isBuffering = value; break;
          case 'message': toastString = value; break;
          case 'showPlay': _showPlayIcon = value; break;
          case 'showPause': _showPauseIconFromListener = value; break;
          case 'userPaused': _isUserPaused = value; break;
          case 'switching': _isSwitchingChannel = value; break;
          case 'retrying': _isRetrying = value; break;
          case 'parsing': _isParsing = value; break;
          case 'sourceIndex': _sourceIndex = value; break;
          case 'retryCount': _retryCount = value; break;
          case 'disposing': _isDisposing = value; break;
          case 'audio': _isAudio = value; break;
          case 'aspectRatioValue': aspectRatio = value; break;
          case 'shouldUpdateAspectRatio': _shouldUpdateAspectRatio = value; break;
          case 'drawerIsOpen': _drawerIsOpen = value; break;
          case 'progressEnabled': _progressEnabled = value; break;
          case 'timeoutActive': _timeoutActive = value; break;
          case 'drawerRefreshKey': _drawerRefreshKey = value; break;
        }
      });
    });
  }

  // 启动定时器
  void _startTimer(String type, Duration duration, Function() callback) {
    _cancelTimer(type);
    _timers[type] = Timer(duration, () {
      callback();
      _timers[type] = null;
    });
  }

  // 启动周期性定时器
  void _startPeriodicTimer(String type, Duration period, Function(Timer) callback) {
    _cancelTimer(type);
    _timers[type] = Timer.periodic(period, callback);
  }

  // 取消指定定时器
  void _cancelTimer(String type) => _timers[type]?.cancel();

  // 取消多个定时器
  void _cancelTimers(List<String> types) {
    for (final type in types) {
      _cancelTimer(type);
    }
  }

  // 取消所有定时器
  void _cancelAllTimers() {
    _timers.forEach((_, timer) => timer?.cancel());
    _timers.clear();
  }

  // 检查定时器是否活跃
  bool _isTimerActive(String type) => _timers[type]?.isActive == true;

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
      LogUtil.i('$operationName被阻止: ${blockers.join(", ")}');
      onFailed?.call();
      return false;
    }
    return true;
  }

  // 启动状态检查定时器
  void _startStateCheckTimer() {
    _cancelTimer('stateCheck');
    LogUtil.i('启动状态检查定时器');
    _startTimer('stateCheck', Duration(seconds: 3), () {
      if (!mounted) return;
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
    _updateState({
      'parsing': false,
      'retrying': false,
      'switching': false,
      'retryCount': 0,
      'disposing': false,
    });
    _cancelTimers(['timeout', 'switchTimeout']);
    if (_pendingSwitch != null) {
      LogUtil.i('处理待切换请求');
      _checkPendingSwitch();
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
    _cancelTimers(['timeout', 'retry']);
    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址相同，重新解析');
      await _cleanupPreCache();
      await _playVideo(isReparse: true);
      return;
    }
    try {
      _updateState(PlayerManager.getStateUpdate('loading'));
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
      _updateState({...PlayerManager.getStateUpdate('playing'), 'switching': false});
      _switchAttemptCount = 0;
      LogUtil.i('$logDescription: 切换预缓存成功: $_preCachedUrl');
    } catch (e) {
      LogUtil.e('$logDescription: 切换预缓存失败: $e');
      _retryPlayback();
    } finally {
      _updateState({'switching': false, 'progressEnabled': false});
      await _cleanupPreCache();
    }
  }

  // 统一播放方法，支持播放、预加载、重新解析
  Future<void> _playVideo({
    bool isRetry = false,
    bool isSourceSwitch = false,
    bool isPreload = false,
    bool isReparse = false,
    String? specificUrl,
    bool setAsPreCache = true,
    bool force = false,
  }) async {
    if ((isPreload && isReparse) || (isPreload && (isRetry || isSourceSwitch)) || (isReparse && (isRetry || isSourceSwitch))) {
      LogUtil.e('播放参数冲突');
      return;
    }
    String operationName = isReparse ? '重新解析' : (isPreload ? '预加载' : '播放');
    if (!_canPerformOperation(operationName, 
        checkRetrying: !isPreload && !isReparse,
        checkSwitching: !isPreload && !isReparse,
        checkParsing: !isReparse)) {
      return;
    }
    if ((isPreload || isReparse) && _playerController == null) {
      LogUtil.e('$operationName失败: 无播放器控制器');
      if (isReparse) {
        LogUtil.i('无播放器，切换下一源');
        _handleSourceSwitching();
      }
      return;
    }
    String url;
    if (specificUrl != null) {
      url = specificUrl;
    } else {
      if (_currentChannel == null || !_isSourceIndexValid()) {
        LogUtil.e('$operationName失败: ${_currentChannel == null ? "无频道" : "源索引无效"}');
        return;
      }
      url = _currentChannel!.urls![_sourceIndex].toString();
    }
    if (!isPreload && !isReparse) {
      _startStateCheckTimer();
      bool isChannelChange = !isSourceSwitch || (_lastPlayedChannelId != _currentChannel!.id);
      String channelId = _currentChannel?.id ?? _currentChannel!.title ?? 'unknown_channel';
      _lastPlayedChannelId = channelId;
      if (isChannelChange) {
        _adManager.onChannelChanged(channelId);
      }
      String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
      LogUtil.i('播放: ${_currentChannel!.title}, 源: $sourceName');
      _cancelAllTimers();
      _updateState({
        ...PlayerManager.getStateUpdate('loading'),
        'message': '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
      });
      await _releaseAllResources(isDisposing: false);
      _startPlaybackTimeout();
      if (!isRetry && !isSourceSwitch && isChannelChange && _hasInitializedAdManager) {
        bool shouldPlay = await _adManager.shouldPlayVideoAdAsync();
        if (shouldPlay) {
          await _adManager.playVideoAd();
          LogUtil.i('广告播放完成');
        }
      }
    } else if (isReparse) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && _lastParseTime != null) {
        final timeSinceLastParse = now - _lastParseTime!;
        if (timeSinceLastParse < reparseMinIntervalMilliseconds) {
          LogUtil.i('解析频率过高，延迟${reparseMinIntervalMilliseconds - timeSinceLastParse}ms');
          _startTimer('retry', Duration(milliseconds: (reparseMinIntervalMilliseconds - timeSinceLastParse).toInt()), () {
            if (mounted) _playVideo(isReparse: true, force: true);
          });
          return;
        }
      }
      _cancelTimers(['retry', 'm3u8Check']);
      _updateState({'parsing': true});
    } else {
      if (_preCachedUrl == url) {
        LogUtil.i('URL已预缓存: $url');
        return;
      }
      await _cleanupPreCache();
    }
    StreamUrl? streamUrlInstance;
    String? parsedUrl;
    try {
      LogUtil.i('$operationName: $url');
      _cancelToken.cancel();
      _cancelToken = CancelToken();
      parsedUrl = await PlayerManager.executePlayback(
        originalUrl: url,
        cancelToken: _cancelToken,
        channelTitle: _currentChannel?.title,
      );
      streamUrlInstance = StreamUrl(url, cancelToken: _cancelToken);
      if (!isPreload && !isReparse) {
        await PlayerManager.safeDisposeResource(_streamUrl);
        _streamUrl = streamUrlInstance;
        _updatePlayUrl(parsedUrl);
        bool isAudio = !Config.videoPlayMode;
        _updateState({'audio': isAudio});
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
        _updateState({'timeoutActive': false});
        _cancelTimer('timeout');
        _switchAttemptCount = 0;
      } else {
        if (isReparse && _isDisposing) {
          LogUtil.i('重新解析中断: 正在释放资源');
          _updateState({'parsing': false, 'switching': false});
          await PlayerManager.safeDisposeResource(streamUrlInstance);
          return;
        }
        await PlayerManager.safeDisposeResource(_preCacheStreamUrl);
        _preCacheStreamUrl = streamUrlInstance;
        await PlayerManager.playSource(
          controller: _playerController!,
          url: parsedUrl,
          isHls: PlayerManager.isHlsStream(parsedUrl),
          channelTitle: _currentChannel?.title,
          channelLogo: _getChannelLogo(),
          preloadOnly: true,
        );
        if (isReparse && _isDisposing) {
          LogUtil.i('重新解析中断: 预缓存后检查');
          _updateState({'parsing': false, 'switching': false});
          return;
        }
        if (setAsPreCache) {
          _preCachedUrl = parsedUrl;
        }
        LogUtil.i('$operationName完成: $parsedUrl');
        if (isReparse) {
          _lastParseTime = DateTime.now().millisecondsSinceEpoch;
          _updateState({
            'progressEnabled': true,
            'switching': false,
            'parsing': false
          });
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('$operationName失败: $url', e, stackTrace);
      if (!isPreload && !isReparse) {
        await PlayerManager.safeDisposeResource(_streamUrl);
        _streamUrl = null;
        _switchAttemptCount++;
        if (_switchAttemptCount <= maxSwitchAttempts) {
          _handleSourceSwitching();
        } else {
          _switchAttemptCount = 0;
          _updateState({
            ...PlayerManager.getStateUpdate('error'),
            'message': S.current.playError,
          });
        }
      } else if (isReparse) {
        _preCachedUrl = null;
        _handleSourceSwitching();
      } else {
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
      if (streamUrlInstance != null) {
        await PlayerManager.safeDisposeResource(streamUrlInstance);
      }
    } finally {
      if (streamUrlInstance != null) {
        bool needsCleanup = false;
        if (!isPreload && !isReparse) {
          needsCleanup = (_streamUrl != streamUrlInstance);
        } else {
          needsCleanup = (_preCacheStreamUrl != streamUrlInstance);
        }
        if (needsCleanup) {
          await PlayerManager.safeDisposeResource(streamUrlInstance);
        }
      }
      if (mounted) {
        if (!isPreload && !isReparse) {
          _updateState({'switching': false});
          _cancelTimer('switchTimeout');
          _checkPendingSwitch();
        } else if (isReparse) {
          _updateState({'parsing': false});
        }
      }
    }
  }

  // 验证和修正源索引
  bool _isSourceIndexValid({PlayModel? channel, int? sourceIndex, bool updateState = true}) {
    final targetChannel = channel ?? _currentChannel;
    final targetIndex = sourceIndex ?? _sourceIndex;
    if (targetChannel?.urls?.isEmpty ?? true) {
      LogUtil.e('无可用源');
      if (updateState) {
        _updateState({
          ...PlayerManager.getStateUpdate('error'),
          'message': S.current.playError,
        });
      }
      return false;
    }
    final safeIndex = (targetIndex < 0 || targetIndex >= targetChannel!.urls!.length) ? 0 : targetIndex;
    if (updateState) {
      _updateState({'sourceIndex': safeIndex});
    }
    return true;
  }

  // 启动播放超时检测
  void _startPlaybackTimeout() {
    _updateState({'timeoutActive': true});
    _startTimer('timeout', Duration(seconds: PlayerManager.defaultTimeoutSeconds), () {
      if (!_canPerformOperation('超时检查', customCondition: _timeoutActive)) {
        _updateState({'timeoutActive': false});
        return;
      }
      if (_playerController?.isPlaying() != true) {
        _handleSourceSwitching();
        _updateState({'timeoutActive': false});
      }
    });
  }

  // 切换频道
  Future<void> _switchChannel(Map<String, dynamic> request) async {
    final channel = request['channel'] as PlayModel?;
    final sourceIndex = request['sourceIndex'] as int;
    if (channel == null) {
      LogUtil.e('切换频道失败: 无频道');
      return;
    }
    if (!_isSourceIndexValid(channel: channel, sourceIndex: sourceIndex, updateState: false)) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
      if (!mounted) return;
      final safeIndex = (sourceIndex < 0 || sourceIndex >= channel.urls!.length) ? 0 : sourceIndex;
      _pendingSwitch = {'channel': channel, 'sourceIndex': safeIndex};
      if (!_isSwitchingChannel) {
        _checkPendingSwitch();
      } else {
        _startTimer('switchTimeout', Duration(seconds: PlayerManager.switchThresholdSeconds), () {
          if (mounted) {
            LogUtil.e('强制切换频道');
            _updateState({'switching': false});
            _checkPendingSwitch();
          }
        });
      }
    });
  }

  // 处理待切换请求
  void _checkPendingSwitch() {
    if (_pendingSwitch == null || !_canPerformOperation('处理待切换')) {
      if (_pendingSwitch != null) {
        LogUtil.i('切换请求冲突');
        _checkAndFixStuckStates();
      }
      return;
    }
    final nextRequest = _pendingSwitch!;
    _pendingSwitch = null;
    _currentChannel = nextRequest['channel'] as PlayModel?;
    _updateState({'sourceIndex': nextRequest['sourceIndex'] as int});
    Future.microtask(() => _playVideo());
  }

  // 处理源切换
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;
    _cancelTimers(['retry', 'timeout']);
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
    _updateState({
      'sourceIndex': _sourceIndex + 1,
      'buffering': false,
      'message': S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? ''),
    });
    _updateState(PlayerManager.getStateUpdate('resetOperations'));
    _preCachedUrl = null;
    LogUtil.i('切换下一源: $nextUrl');
    _cancelTimer('retry');
    _startTimer('retry', const Duration(seconds: PlayerManager.retryDelaySeconds), () async {
      if (!_canPerformOperation('启动新源', checkParsing: false)) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  // 监听视频事件
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
            _updateState({'aspectRatioValue': newAspectRatio, 'shouldUpdateAspectRatio': false});
          }
        }
        break;
      case BetterPlayerEventType.exception:
        if (_isParsing || _isSwitchingChannel) return;
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "未知错误"}');
        _startStateCheckTimer();
        if (_preCachedUrl != null) {
          await _switchToPreCachedUrl('异常触发');
        } else {
          _retryPlayback();
        }
        break;
      case BetterPlayerEventType.bufferingStart:
        _updateState({'buffering': true, 'message': S.current.loading});
        break;
      case BetterPlayerEventType.bufferingEnd:
        _updateState({
          'buffering': false,
          'message': 'HIDE_CONTAINER',
          'showPause': _isUserPaused ? false : _showPauseIconFromListener,
        });
        _cancelTimer('bufferingCheck');
        break;
      case BetterPlayerEventType.play:
        if (!isPlaying) {
          _updateState(PlayerManager.getStateUpdate('playing'));
          _updateState({'message': isBuffering ? toastString : 'HIDE_CONTAINER', 'userPaused': false});
          _cancelTimer('bufferingCheck');
          if (!_isTimerActive('playDuration')) {
            _startPlayDurationTimer();
          }
        }
        _cancelTimer('stateCheck');
        _adManager.onVideoStartPlaying();
        break;
      case BetterPlayerEventType.pause:
        if (isPlaying) {
          _updateState({
            'playing': false,
            'message': S.current.playpause,
            'showPlay': _isUserPaused,
            'showPause': !_isUserPaused,
          });
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
            if (_preCachedUrl != null && remainingTime.inSeconds <= PlayerManager.switchThresholdSeconds) {
              await _switchToPreCachedUrl('HLS剩余时间触发');
            }
          } else {
            if (remainingTime.inSeconds <= PlayerManager.nonHlsPreloadThresholdSeconds) {
              final nextUrl = _getNextVideoUrl();
              if (nextUrl != null && nextUrl != _preCachedUrl) {
                LogUtil.i('非HLS预加载: $nextUrl');
                await _playVideo(isPreload: true, specificUrl: nextUrl);
              }
            }
            if (remainingTime.inSeconds <= PlayerManager.switchThresholdSeconds && _preCachedUrl != null) {
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

  // 启动m3u8流检查
  void _startM3u8Monitor() {
    if (!_isHls) return;
    _cancelTimer('m3u8Check');
    _startPeriodicTimer(
      'm3u8Check',
      const Duration(seconds: m3u8CheckIntervalSeconds),
      (_) async {
        if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) return;
        if (_currentPlayUrl?.isNotEmpty == true) {
          try {
            final content = await HttpUtil().getRequest<String>(
              _currentPlayUrl!,
              retryCount: 1,
              cancelToken: _cancelToken,
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
                await _playVideo(isReparse: true);
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
              await _playVideo(isReparse: true);
            }
          }
        }
      },
    );
  }

  // 启动播放时长检查
  void _startPlayDurationTimer() {
    _cancelTimer('playDuration');
    _startTimer('playDuration', const Duration(seconds: initialProgressDelaySeconds), () {
      if (!_canPerformOperation('播放时长检查', checkParsing: false)) return;
      LogUtil.i('播放时长检查启动');
      if (_isHls) {
        if (_originalUrl?.toLowerCase().contains('timelimit') ?? false) {
          _startM3u8Monitor();
        }
      } else {
        if (_getNextVideoUrl() != null) {
          _updateState({'progressEnabled': true});
          LogUtil.i('非HLS启用progress监听');
        }
      }
      _updateState({'retryCount': 0});
    });
  }

  // 重试播放
  void _retryPlayback({bool resetRetryCount = false}) {
    if (!_canPerformOperation('重试播放') || _isParsing) {
      LogUtil.i('重试阻止: ${_isParsing ? "正在解析" : "状态冲突"}');
      return;
    }
    _cancelTimers(['retry', 'timeout']);
    if (resetRetryCount) {
      _updateState({'retryCount': 0});
    }
    if (_retryCount < PlayerManager.defaultMaxRetries) {
      _startStateCheckTimer();
      _updateState({
        ...PlayerManager.getStateUpdate('retrying', retryCount: _retryCount + 1),
        'message': S.current.retryplay,
      });
      LogUtil.i('重试播放: 第$_retryCount次');
      _startTimer('retry', const Duration(seconds: PlayerManager.retryDelaySeconds), () async {
        if (!_canPerformOperation('执行重试', checkRetrying: false)) return;
        await _playVideo(isRetry: true);
        if (mounted) _updateState({'retrying': false});
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

  // 处理无更多源
  Future<void> _handleNoMoreSources() async {
    _updateState({
      ...PlayerManager.getStateUpdate('error'),
      'message': S.current.playError,
      'sourceIndex': 0,
    });
    await _releaseAllResources(isDisposing: false);
    LogUtil.i('播放结束，无更多源');
    _switchAttemptCount = 0;
  }

  // 处理频道点击
  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;
    try {
      _updateState({
        'buffering': false,
        'message': S.current.loading,
      });
      _updateState(PlayerManager.getStateUpdate('resetOperations'));
      _cancelTimers(['retry', 'm3u8Check']);
      _currentChannel = model;
      _updateState({'sourceIndex': 0, 'shouldUpdateAspectRatio': true});
      _switchAttemptCount = 0;
      await _switchChannel({'channel': _currentChannel, 'sourceIndex': _sourceIndex});
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e) {
      LogUtil.e('切换频道失败: $e');
      _updateState({'message': S.current.playError});
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
      _updateState({'sourceIndex': selectedIndex});
      _updateState(PlayerManager.getStateUpdate('resetOperations'));
      _switchAttemptCount = 0;
      await _switchChannel({'channel': _currentChannel, 'sourceIndex': _sourceIndex});
    }
  }

  // 处理用户暂停
  void _handleUserPaused() => _updateState({'userPaused': true});

  // 处理重试
  void _handleRetry() => _retryPlayback(resetRetryCount: true);

  // 释放所有资源
  Future<void> _releaseAllResources({bool isDisposing = false}) async {
    if (_isDisposing && !isDisposing) {
      LogUtil.i('资源释放中，跳过');
      return;
    }
    _updateState({'disposing': true});
    _cancelAllTimers();
    _cancelToken.cancel();
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
        _updateState({
          ...PlayerManager.getStateUpdate('resetOperations'),
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
      _updateState({'disposing': false});
      if (_pendingSwitch != null && mounted) {
        LogUtil.i('处理待切换请求: ${(_pendingSwitch!['channel'] as PlayModel?)?.title}');
        Future.microtask(() {
          if (mounted && !_isDisposing) {
            _checkPendingSwitch();
          }
        });
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

  // 按地理信息排序播放列表
  Future<void> _sortVideoMap(PlaylistModel videoMap, String? userInfo) async {
    if (videoMap.playList?.isEmpty ?? true) return;
    String? regionPrefix;
    String? cityPrefix;
    if (userInfo?.isNotEmpty ?? false) {
      try {
        final Map<String, dynamic> userData = jsonDecode(userInfo!);
        final Map<String, dynamic>? locationData = userData['info']?['location'];
        if (locationData != null) {
          String? region = locationData['region'] as String?;
          String? city = locationData['city'] as String?;
          if ((region?.isNotEmpty ?? false) || (city?.isNotEmpty ?? false)) {
            if (mounted) {
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
              regionPrefix = (region?.length ?? 0) >= 2 ? region!.substring(0, 2) : region;
              cityPrefix = (city?.length ?? 0) >= 2 ? city!.substring(0, 2) : city;
              LogUtil.i('地理信息: 地区=$regionPrefix, 城市=$cityPrefix');
            }
          }
        } else {
          LogUtil.i('无location字段');
        }
      } catch (e) {
        LogUtil.e('解析地理信息失败: $e');
      }
    } else {
      LogUtil.i('无地理信息');
    }
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
      final matchingGroups = <String>[];
      final nonMatchingGroups = <String>[];
      for (var group in groupList) {
        if (group.startsWith(regionPrefix!)) {
          matchingGroups.add(group);
        } else {
          nonMatchingGroups.add(group);
        }
      }
      final sortedGroups = [...matchingGroups, ...nonMatchingGroups];
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
          final matchingChannels = <String>[];
          final nonMatchingChannels = <String>[];
          for (var channel in channelList) {
            if (channel.startsWith(cityPrefix!)) {
              matchingChannels.add(channel);
            } else {
              nonMatchingChannels.add(channel);
            }
          }
          final sortedChannels = [...matchingChannels, ...nonMatchingChannels];
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

  // 处理返回键
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      _updateState({'drawerIsOpen': false});
      return false;
    }
    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) await _playerController?.pause();
    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    if (!shouldExit && wasPlaying && mounted) await _playerController?.play();
    return shouldExit;
  }

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    _adManager = AdManager();
    Future.microtask(() async {
      await _adManager.loadAdData();
      _hasInitializedAdManager = true;
    });
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
    }
    _loadData();
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

  // 加载播放列表数据
  Future<void> _loadData() async {
    _updateState(PlayerManager.getStateUpdate('resetOperations'));
    _cancelAllTimers();
    _updateState({'audio': false});
    if (widget.m3uData.playList?.isEmpty ?? true) {
      LogUtil.e('播放列表无效');
      _updateState({'message': S.current.getDefaultError});
      return;
    }
    try {
      _videoMap = widget.m3uData;
      String? userInfo = SpUtil.getString('user_all_info');
      LogUtil.i('加载用户地理信息');
      await _initializeZhConverters();
      await _sortVideoMap(_videoMap!, userInfo);
      _updateState({'sourceIndex': 0});
      _switchAttemptCount = 0;
      if (_videoMap?.playList?.isNotEmpty ?? false) {
        _currentChannel = _getFirstChannel(_videoMap!.playList!);
        if (_currentChannel != null) {
          if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
          _updateState({'retryCount': 0, 'timeoutActive': false});
          if (!_isSwitchingChannel && !_isRetrying && !_isParsing) {
            await _switchChannel({'channel': _currentChannel, 'sourceIndex': _sourceIndex});
          } else {
            LogUtil.i('用户操作中，跳过切换');
          }
        } else {
          _updateState({'message': 'UNKNOWN', 'retrying': false});
        }
      } else {
        _currentChannel = null;
        _updateState({'message': 'UNKNOWN', 'retrying': false});
      }
    } catch (e) {
      LogUtil.e('加载播放列表失败: $e');
      _updateState({'message': S.current.parseError});
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
        if (mounted) _updateState({'drawerRefreshKey': ValueKey(DateTime.now().millisecondsSinceEpoch)});
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
        _updateState({'message': S.current.getDefaultError});
        return;
      }
      _updateState({'sourceIndex': 0});
      _switchAttemptCount = 0;
      if (_videoMap?.playList?.isNotEmpty ?? false) {
        _currentChannel = _getFirstChannel(_videoMap!.playList!);
        if (_currentChannel != null) {
          if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
          _updateState({'retryCount': 0, 'timeoutActive': false});
          _switchAttemptCount = 0;
          if (!_isSwitchingChannel && !_isRetrying && !_isParsing) {
            await _switchChannel({'channel': _currentChannel, 'sourceIndex': _sourceIndex});
          } else {
            LogUtil.i('用户操作中，跳过切换');
          }
        } else {
          _updateState({'message': 'UNKNOWN', 'retrying': false});
        }
      } else {
        _currentChannel = null;
        _updateState({'message': 'UNKNOWN', 'retrying': false});
      }
    } catch (e) {
      LogUtil.e('处理播放列表失败: $e');
      _updateState({'message': S.current.parseError});
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
                onCloseDrawer: () => _updateState({'drawerIsOpen': false}),
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
                          onToggleDrawer: () => _updateState({'drawerIsOpen': !_drawerIsOpen}),
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
                    onTap: () => _updateState({'drawerIsOpen': false}),
                    child: ChannelDrawerPage(
                      key: _drawerRefreshKey,
                      refreshKey: _drawerRefreshKey,
                      videoMap: _videoMap,
                      playModel: _currentChannel,
                      onTapChannel: _onTapChannel,
                      isLandscape: true,
                      onCloseDrawer: () => _updateState({'drawerIsOpen': false}),
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
