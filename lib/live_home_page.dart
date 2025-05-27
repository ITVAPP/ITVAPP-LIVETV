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

  // 播放模式枚举，用于区分不同播放场景和策略
  enum PlayMode {
    normal,           // 正常播放模式
    retry,           // 失败重试模式
    sourceSwitch,    // 多源切换模式
    preload,         // 预加载缓存模式
    reparse,         // 地址重新解析模式
  }

  // 定时器类型枚举，统一管理各种超时和检查机制
  enum TimerType {
    playbackTimeout(38),     // 播放启动超时检测
    retry(2),               // 重试操作延迟等待
    playDuration(60),       // 播放时长达标检查
    m3u8Check(10),          // HLS流有效性检查
    ;

    const TimerType(this.seconds);
    final int seconds;
  }

// 播放器核心管理类，封装视频播放的通用逻辑和配置
class PlayerManager {
  final String parsedUrl; // 解析后的最终播放地址
  final StreamUrl streamUrlInstance; // 流地址处理实例
  PlayerManager(this.parsedUrl, this.streamUrlInstance);
  
  static const int defaultMaxRetries = 1; // 单源最大重试次数限制
  static const int switchThresholdSeconds = 3; // 进度监听中剩余时间，切换预缓存视频源
  static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS流预加载时机秒数
  static const int maxSwitchAttempts = 3; // 多源切换最大尝试次数
  static const double defaultAspectRatio = 1.78; // 默认视频宽高比16:9

  // 执行视频源播放或预缓存操作
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

  // 安全释放各类播放资源，避免内存泄漏
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

  // 检测URL是否为HLS直播流格式
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

// 直播主页面Widget，管理播放列表和频道切换
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // M3U格式的播放列表数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int cleanupDelayMilliseconds = 500; // 资源清理延迟毫秒数
  static const int snackBarDurationSeconds = 5; // 提示消息显示持续时间
  static const int reparseMinIntervalMilliseconds = 10000; // 重新解析最小间隔毫秒数

  // 统一状态存储 - 所有状态都在这里
  final Map<String, dynamic> _states = {
    'playing': false,
    'buffering': false,
    'switching': false,
    'retrying': false,
    'disposing': false,
    'audio': false,
    'userPaused': false,
    'showPlay': false,
    'showPause': false,
    'progressEnabled': false,
    'timeoutActive': false,
    'shouldUpdateAspectRatio': true,
    'drawerIsOpen': false,
    'sourceIndex': 0,
    'retryCount': 0,
    'aspectRatioValue': PlayerManager.defaultAspectRatio,
    'message': '', // 会在 initState 中设置
    'drawerRefreshKey': null,
    'switchRequestId': null, // 频道切换请求ID，用于防重入保护
  };

  // 非状态变量保持不变
  String? _preCachedUrl; // 预缓存的下一个播放地址
  int? _lastParseTime; // 上次地址解析的时间戳
  PlaylistModel? _videoMap; // 完整的视频播放列表数据
  PlayModel? _currentChannel; // 当前选中的频道信息
  BetterPlayerController? _playerController; // 视频播放器控制器实例
  StreamUrl? _streamUrl; // 当前播放的流地址处理器
  StreamUrl? _preCacheStreamUrl; // 预缓存的流地址处理器
  String? _currentPlayUrl; // 当前实际播放的解析后地址
  String? _originalUrl; // 当前频道的原始播放地址
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  }; // 用户收藏的频道列表数据
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 用户行为统计分析实例
  late AdManager _adManager; // 广告播放管理器
  int _m3u8InvalidCount = 0; // HLS流失效检查计数器
  int _switchAttemptCount = 0; // 当前频道的源切换尝试计数
  ZhConverter? _s2tConverter; // 简体转繁体中文转换器
  ZhConverter? _t2sConverter; // 繁体转简体中文转换器
  bool _zhConvertersInitializing = false; // 中文转换器是否正在初始化
  bool _zhConvertersInitialized = false; // 中文转换器初始化完成标识
  
  final Map<String, Timer?> _timers = {}; // 统一管理的定时器映射表
  Timer? _debounceTimer; // 防抖动延迟定时器
  bool _hasInitializedAdManager = false; // 广告管理器初始化完成标识
  String? _lastPlayedChannelId; // 最后播放频道的唯一标识
  late CancelToken _cancelToken; // 网络请求统一取消令牌

  // 更新当前播放地址并自动检测流类型
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    LogUtil.i('更新播放地址: $newUrl, HLS: ${PlayerManager.isHlsStream(_currentPlayUrl)}');
  }

  // 极简的状态更新方法 - 零映射表，零switch！
  void _updateState(Map<String, dynamic> updates) {
    if (!mounted) return;
    
    final actualChanges = updates.entries
        .where((entry) => _states[entry.key] != entry.value)
        .fold<Map<String, dynamic>>({}, (map, entry) {
      map[entry.key] = entry.value;
      return map;
    });
    
    if (actualChanges.isEmpty) return;
    
    LogUtil.i('状态更新: $actualChanges');
    
    setState(() {
      _states.addAll(actualChanges); // 一行搞定所有赋值！
    });
  }

  // 启动指定类型的单次定时器
  void _startTimer(TimerType type, {Duration? customDuration, required Function() callback}) {
    _timers[type.name]?.cancel();
    final duration = customDuration ?? Duration(seconds: type.seconds);
    LogUtil.i('启动定时器: ${type.name}, 延迟: ${duration.inSeconds}秒');
    _timers[type.name] = Timer(duration, () {
      LogUtil.i('定时器触发: ${type.name}');
      callback();
      _timers[type.name] = null;
    });
  }

  // 启动指定类型的周期性定时器
  void _startPeriodicTimer(TimerType type, {Duration? customPeriod, required Function(Timer) callback}) {
    _timers[type.name]?.cancel();
    final period = customPeriod ?? Duration(seconds: type.seconds);
    LogUtil.i('启动周期性定时器: ${type.name}, 周期: ${period.inSeconds}秒');
    _timers[type.name] = Timer.periodic(period, callback);
  }

  // 取消指定类型的定时器
  void _cancelTimer(TimerType type) {
    if (_timers[type.name]?.isActive == true) {
      LogUtil.i('取消定时器: ${type.name}');
    }
    _timers[type.name]?.cancel();
  }

  // 批量取消多个定时器
  void _cancelTimers(List<TimerType> types) {
    for (final type in types) {
      _cancelTimer(type);
    }
  }

  // 取消所有正在运行的定时器
  void _cancelAllTimers() {
    LogUtil.i('取消所有定时器');
    _timers.forEach((_, timer) => timer?.cancel());
    _timers.clear();
  }

  // 检查指定定时器是否处于活跃状态
  bool _isTimerActive(TimerType type) => _timers[type.name]?.isActive == true;

  // 检查当前是否可以执行指定操作，避免状态冲突
  bool _canPerformOperation(String operationName, {
    bool checkRetrying = true,
    bool checkSwitching = true,
    bool checkDisposing = true,
    bool? customCondition,
    VoidCallback? onFailed,
  }) {
    if (!mounted) {
      LogUtil.i('$operationName被阻止: 组件未挂载');
      onFailed?.call();
      return false;
    }
    List<String> blockers = [];
    if (checkDisposing && _states['disposing']) blockers.add('正在释放资源');
    if (checkRetrying && _states['retrying']) blockers.add('正在重试');
    if (checkSwitching && _states['switching']) blockers.add('正在切换操作');
    if (customCondition == false) blockers.add('自定义条件不满足');
    if (blockers.isNotEmpty) {
      LogUtil.i('$operationName被阻止: ${blockers.join(", ")}');
      onFailed?.call();
      return false;
    }
    return true;
  }

  // 重置所有操作状态标志位
  void _resetOperationStates() {
    LogUtil.i('重置操作状态');
    _updateState({'retrying': false, 'switching': false});
    _cancelTimers([TimerType.retry, TimerType.m3u8Check]);
  }

  // 初始化首个可播放频道并开始播放
  Future<void> _initializeChannel() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getFirstChannel(_videoMap!.playList!);
      if (_currentChannel != null) {
        _updateState({'retryCount': 0, 'timeoutActive': false});
        _switchAttemptCount = 0;
        if (!_states['switching'] && !_states['retrying']) {
          await _playVideo();
        } else {
          LogUtil.i('用户操作中，跳过切换');
        }
      } else {
        LogUtil.e('未找到可播放频道');
        _updateState({'message': 'UNKNOWN', 'retrying': false});
      }
    } else {
      LogUtil.e('播放列表为空');
      _currentChannel = null;
      _updateState({'message': 'UNKNOWN', 'retrying': false});
    }
  }
  
  // 清理预缓存资源和相关状态
  Future<void> _cleanupPreCache() async {
    LogUtil.i('清理预缓存资源');
    _preCachedUrl = null;
    if (_preCacheStreamUrl != null) {
      await PlayerManager.safeDisposeResource(_preCacheStreamUrl);
      _preCacheStreamUrl = null;
      LogUtil.i('预缓存清理完成');
    }
  }

  // 切换到已预缓存的播放地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
    LogUtil.i('$logDescription: 尝试切换预缓存');
    if (_states['disposing'] || _preCachedUrl == null) {
      LogUtil.i('$logDescription: ${_states['disposing'] ? "正在释放资源" : "无预缓存地址"}');
      return;
    }
    _cancelTimers([TimerType.playbackTimeout, TimerType.retry]);
    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址相同，重新解析');
      await _cleanupPreCache();
      await _playVideo(isReparse: true);
      return;
    }
    try {
      _updateState({'playing': false, 'buffering': false, 'showPlay': false, 'showPause': false, 'userPaused': false, 'switching': true});
      await PlayerManager.playSource(
        controller: _playerController!,
        url: _preCachedUrl!,
        isHls: PlayerManager.isHlsStream(_preCachedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png',
        preloadOnly: true,
      );
      await PlayerManager.playSource(
        controller: _playerController!,
        url: _preCachedUrl!,
        isHls: PlayerManager.isHlsStream(_preCachedUrl),
        channelTitle: _currentChannel?.title,
        channelLogo: _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png',
      );
      _startPlayDurationTimer();
      _updatePlayUrl(_preCachedUrl!);
      _updateState({'playing': true, 'buffering': false, 'showPlay': false, 'showPause': false, 'switching': false});
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

  // 统一播放方法，支持播放、重试、切换源、预加载、重新解析
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
    LogUtil.i('开始$operationName, 重试: $isRetry, 切换源: $isSourceSwitch');
    
    if (!_canPerformOperation(operationName, 
        checkRetrying: !isPreload && !isReparse,
        checkSwitching: !isPreload && !isReparse)) {
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
      url = _currentChannel!.urls![_states['sourceIndex']].toString();
    }
    if (!isPreload && !isReparse) {
      bool isChannelChange = !isSourceSwitch || (_lastPlayedChannelId != _currentChannel!.id);
      String channelId = _currentChannel?.id ?? _currentChannel!.title ?? 'unknown_channel';
      _lastPlayedChannelId = channelId;
      if (isChannelChange) {
        LogUtil.i('频道变更，通知广告管理器: $channelId');
        _adManager.onChannelChanged(channelId);
      }
      String sourceName = _currentChannel!.urls![_states['sourceIndex']].contains('\$') 
          ? _currentChannel!.urls![_states['sourceIndex']].split('\$')[1].trim()
          : S.current.lineIndex(_states['sourceIndex'] + 1);
      LogUtil.i('播放: ${_currentChannel!.title}, 源: $sourceName');
      _updateState({
        'playing': false, 
        'buffering': false, 
        'showPlay': false, 
        'showPause': false, 
        'userPaused': false, 
        'switching': true,
        'timeoutActive': false, // 重置超时状态
        'message': '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
      });
      await _releaseAllResources(isDisposing: false);
      _startPlaybackTimeout();
      if (!isRetry && !isSourceSwitch && isChannelChange && _hasInitializedAdManager) {
        LogUtil.i('检查是否需要播放广告');
        bool shouldPlay = await _adManager.shouldPlayVideoAdAsync();
        if (shouldPlay) {
          LogUtil.i('开始播放广告');
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
          _startTimer(TimerType.retry, 
            customDuration: Duration(milliseconds: (reparseMinIntervalMilliseconds - timeSinceLastParse).toInt()),
            callback: () {
              if (mounted) _playVideo(isReparse: true, force: true);
            });
          return;
        }
      }
      _cancelTimers([TimerType.retry, TimerType.m3u8Check]);
      _updateState({'switching': true});
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
      _cancelToken.cancel();
      _cancelToken = CancelToken();
      streamUrlInstance = StreamUrl(url, cancelToken: _cancelToken);
      parsedUrl = await streamUrlInstance.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        throw Exception('地址解析失败: $url');
      }
      LogUtil.i('地址解析成功: $parsedUrl');
      
      if (!isPreload && !isReparse) {
        await PlayerManager.safeDisposeResource(_streamUrl);
        _streamUrl = streamUrlInstance;
        _updatePlayUrl(parsedUrl);
        bool isAudio = !Config.videoPlayMode;
        _updateState({'audio': isAudio});
        LogUtil.i('播放信息: URL=$parsedUrl, 音频=$isAudio, HLS=${PlayerManager.isHlsStream(parsedUrl)}');
        final configuration = BetterPlayerConfig.createPlayerConfig(
          eventListener: _videoListener,
          isHls: PlayerManager.isHlsStream(parsedUrl),
        );
        _playerController = BetterPlayerController(configuration);
        
        await PlayerManager.playSource(
          controller: _playerController!,
          url: _currentPlayUrl!,
          isHls: PlayerManager.isHlsStream(parsedUrl),
          channelTitle: _currentChannel?.title,
          channelLogo: _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png',
        );
        if (mounted) setState(() {});
        await _playerController?.play();
        _updateState({'timeoutActive': false, 'switching': false});
        _cancelTimer(TimerType.playbackTimeout);
        _switchAttemptCount = 0;
      } else {
        if (isReparse && _states['disposing']) {
          LogUtil.i('重新解析中断: 正在释放资源');
          _updateState({'switching': false});
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
          channelLogo: _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png',
          preloadOnly: true,
        );
        if (isReparse && _states['disposing']) {
          LogUtil.i('重新解析中断: 预缓存后检查');
          _updateState({'switching': false});
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
            'switching': false
          });
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('$operationName失败: $url', e, stackTrace);
      if (!isPreload && !isReparse) {
        await PlayerManager.safeDisposeResource(_streamUrl);
        _streamUrl = null;
        _switchAttemptCount++;
        if (_switchAttemptCount <= PlayerManager.maxSwitchAttempts) {
          LogUtil.i('切换下一源，尝试次数: $_switchAttemptCount');
          _handleSourceSwitching();
        } else {
          LogUtil.e('切换尝试超限，停止播放');
          _switchAttemptCount = 0;
          _updateState({
            'playing': false, 
            'buffering': false, 
            'retrying': false, 
            'switching': false,
            'message': S.current.playError,
          });
        }
      } else if (isReparse) {
        LogUtil.e('重新解析失败，切换下一源');
        _preCachedUrl = null;
        _handleSourceSwitching();
      } else {
        LogUtil.e('预加载失败，清理缓存');
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
        }
      }
    }
  }

  // 验证播放源索引有效性并自动修正
  bool _isSourceIndexValid({PlayModel? channel, int? sourceIndex, bool updateState = true}) {
    final targetChannel = channel ?? _currentChannel;
    final targetIndex = sourceIndex ?? _states['sourceIndex'];
    if (targetChannel?.urls?.isEmpty ?? true) {
      LogUtil.e('无可用源');
      if (updateState) {
        _updateState({
          'playing': false, 
          'buffering': false, 
          'retrying': false, 
          'switching': false,
          'message': S.current.playError,
        });
      }
      return false;
    }
    final safeIndex = (targetIndex < 0 || targetIndex >= targetChannel!.urls!.length) ? 0 : targetIndex;
    if (safeIndex != targetIndex) {
      LogUtil.i('源索引修正: $targetIndex -> $safeIndex');
    }
    if (updateState) {
      _updateState({'sourceIndex': safeIndex});
    }
    return true;
  }

  // 启动播放超时检测机制
  void _startPlaybackTimeout() {
    LogUtil.i('启动播放超时检测');
    _updateState({'timeoutActive': true});
    _startTimer(TimerType.playbackTimeout, callback: () {
      LogUtil.i('播放超时检测触发');
      
      if (!_canPerformOperation('超时检查', customCondition: _states['timeoutActive'])) {
        _updateState({'timeoutActive': false});
        return;
      }
      
      // 检查播放器状态
      bool isActuallyPlaying = _playerController?.isPlaying() ?? false;
      bool isStillBuffering = _states['buffering'];
      
      LogUtil.i('超时检查 - 播放中: $isActuallyPlaying, 缓冲中: $isStillBuffering');
      
      // 如果还在缓冲或者没有真正开始播放，则认为超时
      if (!isActuallyPlaying || isStillBuffering) {
        LogUtil.e('播放超时，执行重试逻辑');
        _updateState({'timeoutActive': false});
        _retryPlayback();
      } else {
        LogUtil.i('播放正常，取消超时状态');
        _updateState({'timeoutActive': false});
      }
    });
  }

  // 频道切换方法，支持立即执行+防抖合并
  Future<void> _switchChannel(Map<String, dynamic> request) async {
    final channel = request['channel'] as PlayModel?;
    final sourceIndex = request['sourceIndex'] as int;
    
    LogUtil.i('切换频道请求: ${channel?.title}, 源索引: $sourceIndex');
    
    if (channel == null) {
      LogUtil.e('切换频道失败: 无频道');
      return;
    }
    
    if (!_isSourceIndexValid(channel: channel, sourceIndex: sourceIndex, updateState: false)) {
      return;
    }
    
    // 生成请求ID用于重入防护
    String requestId = DateTime.now().millisecondsSinceEpoch.toString();
    _updateState({'switchRequestId': requestId});
    
    // 检查是否为相同频道重复点击
    if (_currentChannel?.id == channel.id && 
        _states['sourceIndex'] == sourceIndex && 
        _states['playing'] && 
        !_states['retrying']) {
      LogUtil.i('相同频道重复点击，忽略请求');
      return;
    }
    
    // 取消之前的防抖定时器
    _debounceTimer?.cancel();
    
    if (!_states['switching']) {
      // 没有在切换，立即执行
      LogUtil.i('立即执行频道切换: ${channel.title}');
      await _executeSwitchChannel(request, requestId);
    } else {
      // 正在切换，使用防抖等待
      LogUtil.i('切换中，设置防抖等待: ${channel.title}');
      
      _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () async {
        if (!mounted) return;
        
        // 检查请求是否还有效
        if (_states['switchRequestId'] == requestId) {
          LogUtil.i('防抖执行频道切换: ${channel.title}');
          await _executeSwitchChannel(request, requestId);
        } else {
          LogUtil.i('防抖请求已过期，跳过执行');
        }
      });
    }
  }
  
  // 执行频道切换的核心方法
  Future<void> _executeSwitchChannel(Map<String, dynamic> request, String requestId) async {
    // 检查请求有效性
    if (_states['switchRequestId'] != requestId || !mounted) {
      LogUtil.i('请求已过期或组件已销毁，取消执行');
      return;
    }
    
    final channel = request['channel'] as PlayModel;
    final sourceIndex = request['sourceIndex'] as int;
    
    try {
      // 再次检查相同频道
      if (_currentChannel?.id == channel.id && 
          _states['sourceIndex'] == sourceIndex && 
          _states['playing'] && 
          !_states['retrying']) {
        LogUtil.i('执行时发现相同频道，跳过切换');
        return;
      }
      
      // 重置操作状态
      _resetOperationStates();
      
      // 更新频道信息
      _currentChannel = channel;
      final safeIndex = (sourceIndex < 0 || sourceIndex >= channel.urls!.length) ? 0 : sourceIndex;
      _updateState({
        'sourceIndex': safeIndex, 
        'shouldUpdateAspectRatio': true,
        'retryCount': 0,
      });
      _switchAttemptCount = 0;
      
      // 最后检查请求有效性
      if (_states['switchRequestId'] != requestId) {
        LogUtil.i('切换过程中请求已过期');
        return;
      }
      
      // 执行播放
      await _playVideo();
      
      LogUtil.i('频道切换完成: ${channel.title}');
      
    } catch (e) {
      LogUtil.e('频道切换失败: $e');
      _updateState({'message': S.current.playError});
      await _releaseAllResources(isDisposing: false);
    } finally {
      // 清理请求ID（如果是当前请求）
      if (_states['switchRequestId'] == requestId) {
        _updateState({'switchRequestId': null});
      }
    }
  }

  // 处理播放源切换逻辑，支持多源轮换
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    LogUtil.i('处理源切换，来源: ${isFromFinished ? "播放结束" : "失败"}');
    if (_states['retrying'] || _states['disposing']) {
      LogUtil.i('跳过源切换: ${_states['retrying'] ? "正在重试" : "正在释放"}');
      return;
    }
    _cancelTimers([TimerType.retry, TimerType.playbackTimeout]);
    String? nextUrl;
    if (_currentChannel?.urls?.isNotEmpty ?? false) {
      final List<String> urls = _currentChannel!.urls!;
      final nextSourceIndex = _states['sourceIndex'] + 1;
      nextUrl = nextSourceIndex < urls.length ? urls[nextSourceIndex] : null;
    }
    
    if (nextUrl == null) {
      LogUtil.i('无更多源');
      _handleNoMoreSources();
      return;
    }
    _switchAttemptCount++;
    if (_switchAttemptCount > PlayerManager.maxSwitchAttempts) {
      LogUtil.e('切换尝试超限: $_switchAttemptCount');
      _handleNoMoreSources();
      _switchAttemptCount = 0;
      return;
    }
    _updateState({
      'sourceIndex': _states['sourceIndex'] + 1,
      'buffering': false,
      'message': S.current.lineToast(_states['sourceIndex'] + 1, _currentChannel?.title ?? ''),
    });
    _resetOperationStates();
    _preCachedUrl = null;
    LogUtil.i('切换下一源: $nextUrl');
    _cancelTimer(TimerType.retry);
    _startTimer(TimerType.retry, callback: () async {
      if (!_canPerformOperation('启动新源')) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  // 视频播放器事件监听处理器
  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _states['disposing']) return;
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
        LogUtil.i('播放器初始化完成');
        if (_states['shouldUpdateAspectRatio']) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? PlayerManager.defaultAspectRatio;
          if (_states['aspectRatioValue'] != newAspectRatio) {
            _updateState({'aspectRatioValue': newAspectRatio, 'shouldUpdateAspectRatio': false});
          }
        }
        break;
      case BetterPlayerEventType.exception:
        if (_states['switching']) return;
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "未知错误"}');
        
        // 取消超时检测，避免重复触发
        _cancelTimer(TimerType.playbackTimeout);
        
        if (_preCachedUrl != null) {
          LogUtil.i('使用预缓存地址处理异常');
          await _switchToPreCachedUrl('异常触发');
        } else {
          LogUtil.i('无预缓存，执行重试');
          _retryPlayback();
        }
        break;
      case BetterPlayerEventType.bufferingStart:
        _updateState({'buffering': true, 'message': S.current.loading});
        // 关键修改：启动播放超时检测，防止无限缓冲
        if (!_isTimerActive(TimerType.playbackTimeout)) {
          _startPlaybackTimeout();
          LogUtil.i('缓冲时启动超时检测');
        }
        break;
      case BetterPlayerEventType.bufferingEnd:
        _updateState({
          'buffering': false,
          'message': 'HIDE_CONTAINER',
          'showPause': _states['userPaused'] ? false : _states['showPause'],
        });
        _cancelTimer(TimerType.playbackTimeout);
        LogUtil.i('缓冲结束，取消超时检测');
        break;
      case BetterPlayerEventType.play:
        if (!_states['playing']) {
          _updateState({'playing': true, 'buffering': false, 'showPlay': false, 'showPause': false});
          _updateState({'message': _states['buffering'] ? _states['message'] : 'HIDE_CONTAINER', 'userPaused': false});
          
          // 播放开始时取消超时检测
          _cancelTimer(TimerType.playbackTimeout);
          
          if (!_isTimerActive(TimerType.playDuration)) {
            _startPlayDurationTimer();
          }
        }
        _adManager.onVideoStartPlaying();
        break;
      case BetterPlayerEventType.pause:
        if (_states['playing']) {
          LogUtil.i('暂停播放，用户触发: ${_states['userPaused']}');
          _updateState({
            'playing': false,
            'message': S.current.playpause,
            'showPlay': _states['userPaused'],
            'showPause': !_states['userPaused'],
          });
        }
        break;
      case BetterPlayerEventType.progress:
        if (_states['switching'] || !_states['progressEnabled'] || !_states['playing']) return;
        final position = event.parameters?["progress"] as Duration?;
        final duration = event.parameters?["duration"] as Duration?;
        if (position != null && duration != null) {
          final remainingTime = duration - position;
          bool isHls = PlayerManager.isHlsStream(_currentPlayUrl);
          if (isHls) {
            if (_preCachedUrl != null && remainingTime.inSeconds <= PlayerManager.switchThresholdSeconds) {
              LogUtil.i('HLS剩余时间不足，切换预缓存: ${remainingTime.inSeconds}秒');
              await _switchToPreCachedUrl('HLS剩余时间触发');
            }
          } else {
            if (remainingTime.inSeconds <= PlayerManager.nonHlsPreloadThresholdSeconds) {
              String? nextUrl;
              if (_currentChannel?.urls?.isNotEmpty ?? false) {
                final List<String> urls = _currentChannel!.urls!;
                final nextSourceIndex = _states['sourceIndex'] + 1;
                nextUrl = nextSourceIndex < urls.length ? urls[nextSourceIndex] : null;
              }
              if (nextUrl != null && nextUrl != _preCachedUrl) {
                LogUtil.i('非HLS预加载下一源: $nextUrl');
                await _playVideo(isPreload: true, specificUrl: nextUrl);
              }
            }
            if (remainingTime.inSeconds <= PlayerManager.switchThresholdSeconds && _preCachedUrl != null) {
              LogUtil.i('非HLS切换预缓存: ${remainingTime.inSeconds}秒');
              await _switchToPreCachedUrl('非HLS切换触发');
            }
          }
        }
        break;
      case BetterPlayerEventType.finished:
        if (_states['switching']) return;
        LogUtil.i('播放结束');
        
        // 播放结束时取消超时检测
        _cancelTimer(TimerType.playbackTimeout);
        
        bool isHls = PlayerManager.isHlsStream(_currentPlayUrl);
        if (!isHls && _preCachedUrl != null) {
          LogUtil.i('非HLS播放结束，切换预缓存');
          await _switchToPreCachedUrl('非HLS播放结束');
        } else if (isHls) {
          LogUtil.i('HLS流异常结束，重试');
          _retryPlayback();
        } else {
          LogUtil.i('播放完成，无更多源');
          _handleNoMoreSources();
        }
        break;
      default:
        break;
    }
  }

  // 启动HLS流有效性监控机制
  void _startM3u8Monitor() {
    bool isHls = PlayerManager.isHlsStream(_currentPlayUrl);
    if (!isHls) return;
    LogUtil.i('启动m3u8监控');
    _cancelTimer(TimerType.m3u8Check);
    _startPeriodicTimer(
      TimerType.m3u8Check,
      callback: (_) async {
        if (!mounted || !PlayerManager.isHlsStream(_currentPlayUrl) || !_states['playing'] || _states['disposing'] || _states['switching']) return;
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

  // 启动播放时长达标检查机制
  void _startPlayDurationTimer() {
    _cancelTimer(TimerType.playDuration);
    _startTimer(TimerType.playDuration, callback: () {
      if (!_canPerformOperation('播放时长检查', checkSwitching: false)) return;
      bool isHls = PlayerManager.isHlsStream(_currentPlayUrl);
      if (isHls) {
        if (_originalUrl?.toLowerCase().contains('timelimit') ?? false) {
          LogUtil.i('时间限制HLS源，启动m3u8监控');
          _startM3u8Monitor();
        }
      } else {
        String? nextUrl;
        if (_currentChannel?.urls?.isNotEmpty ?? false) {
          final List<String> urls = _currentChannel!.urls!;
          final nextSourceIndex = _states['sourceIndex'] + 1;
          nextUrl = nextSourceIndex < urls.length ? urls[nextSourceIndex] : null;
        }
        if (nextUrl != null) {
          LogUtil.i('非HLS启用progress监听');
          _updateState({'progressEnabled': true});
        }
      }
      LogUtil.i('稳定播放重置重试次数');
      _updateState({'retryCount': 0});
    });
  }

  // 执行播放重试逻辑，支持重试次数控制
  void _retryPlayback({bool resetRetryCount = false}) {
    LogUtil.i('执行播放重试，重置计数: $resetRetryCount');
    if (!_canPerformOperation('重试播放') || _states['switching']) {
      LogUtil.i('重试阻止: ${_states['switching'] ? "正在切换操作" : "状态冲突"}');
      return;
    }
    
    // 取消可能的超时检测
    _cancelTimers([TimerType.retry, TimerType.playbackTimeout]);
    
    if (resetRetryCount) {
      _updateState({'retryCount': 0});
    }
    if (_states['retryCount'] < PlayerManager.defaultMaxRetries) {
      _updateState({
        'retrying': true, 
        'retryCount': _states['retryCount'] + 1, 
        'buffering': false, 
        'showPlay': false, 
        'showPause': false, 
        'userPaused': false,
        'timeoutActive': false, // 重置超时状态
        'message': S.current.retryplay,
      });
      LogUtil.i('重试播放: 第${_states['retryCount']}次');
      _startTimer(TimerType.retry, callback: () async {
        if (!_canPerformOperation('执行重试', checkRetrying: false)) return;
        _updateState({'retrying': false});
        await _playVideo(isRetry: true);
      });
    } else {
      LogUtil.i('重试超限，切换下一源');
      _handleSourceSwitching();
    }
  }

  // 处理所有播放源都无法播放的情况
  Future<void> _handleNoMoreSources() async {
    LogUtil.i('处理无更多源情况');
    
    // 更新UI状态
    _updateState({
      'playing': false, 
      'buffering': false, 
      'retrying': false, 
      'switching': false,
      'message': S.current.playError,
      'sourceIndex': 0,
    });
    
    // 关键修改：确保播放器在释放前彻底停止
    if (_playerController != null) {
      try {
        // 移除事件监听器，防止继续触发缓冲事件
        _playerController!.removeEventsListener(_videoListener);
        LogUtil.i('移除播放器事件监听器');
        
        // 如果还在播放，先暂停
        if (_playerController!.isPlaying() ?? false) {
          await _playerController!.pause();
          LogUtil.i('强制暂停播放器');
        }
        
        // 清除缓存，确保不会继续尝试播放
        await _playerController!.clearCache();
        LogUtil.i('清除播放器缓存');
        
      } catch (e) {
        LogUtil.e('停止播放器失败: $e');
      }
    }
    
    // 使用现有的资源释放方法
    await _releaseAllResources(isDisposing: false);
    
    LogUtil.i('播放结束，无更多源');
    _switchAttemptCount = 0;
  }

  // 处理用户点击频道的事件
  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;
    try {
      _updateState({
        'buffering': false,
        'message': S.current.loading,
      });
      _resetOperationStates();
      _currentChannel = model;
      _updateState({'sourceIndex': 0, 'shouldUpdateAspectRatio': true});
      _switchAttemptCount = 0;
      await _switchChannel({'channel': _currentChannel, 'sourceIndex': _states['sourceIndex']});
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e) {
      LogUtil.e('切换频道失败: $e');
      _updateState({'message': S.current.playError});
      await _releaseAllResources(isDisposing: false);
    }
  }

  // 显示频道播放源选择对话框
  Future<void> _changeChannelSources() async {
    LogUtil.i('显示播放源选择对话框');
    final sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) {
      LogUtil.e('无有效源');
      return;
    }
    final selectedIndex = await changeChannelSources(context, sources, _states['sourceIndex']);
    if (selectedIndex != null) {
      LogUtil.i('用户选择源索引: $selectedIndex');
      _updateState({'sourceIndex': selectedIndex});
      _resetOperationStates();
      _switchAttemptCount = 0;
      await _switchChannel({'channel': _currentChannel, 'sourceIndex': _states['sourceIndex']});
    }
  }

  // 处理用户主动暂停播放
  void _handleUserPaused() {
    LogUtil.i('用户主动暂停播放');
    _updateState({'userPaused': true});
  }

  // 处理用户点击重试按钮
  void _handleRetry() {
    LogUtil.i('用户点击重试按钮');
    _retryPlayback(resetRetryCount: true);
  }

  // 释放所有播放相关资源
  Future<void> _releaseAllResources({bool isDisposing = false}) async {
    if (_states['disposing'] && !isDisposing) {
      LogUtil.i('资源释放中，跳过');
      return;
    }
    _updateState({'disposing': true});
    _cancelAllTimers();
    _cancelToken.cancel();
    
    // 清理防抖定时器
    _debounceTimer?.cancel();
    
    // 重置切换状态
    _updateState({'switchRequestId': null});
    
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
        LogUtil.i('释放广告管理器');
        _adManager.dispose();
      } else {
        LogUtil.i('重置广告管理器');
        _adManager.reset(rescheduleAds: false, preserveTimers: true);
      }
      if (mounted && !isDisposing) {
        _updateState({
          'retrying': false, 
          'switching': false,
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
    }
  }

  // 初始化繁简体中文转换器
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

  // 根据用户地理位置信息对播放列表进行智能排序
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

  // 处理Android返回键，支持退出确认
  Future<bool> _handleBackPress(BuildContext context) async {
    LogUtil.i('处理返回键按压');
    if (_states['drawerIsOpen']) {
      LogUtil.i('关闭抽屉菜单');
      _updateState({'drawerIsOpen': false});
      return false;
    }
    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) {
      LogUtil.i('暂停播放以显示退出确认');
      await _playerController?.pause();
    }
    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    LogUtil.i('退出确认结果: $shouldExit');
    if (!shouldExit && wasPlaying && mounted) {
      LogUtil.i('取消退出，恢复播放');
      await _playerController?.play();
    }
    return shouldExit;
  }

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    _adManager = AdManager();
    _states['message'] = S.current.loading; // 初始化消息
    Future.microtask(() async {
      await _adManager.loadAdData();
      _hasInitializedAdManager = true;
      LogUtil.i('广告管理器初始化完成');
    });
    if (!EnvUtil.isMobile) {
      LogUtil.i('桌面环境，隐藏标题栏');
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
      LogUtil.i('初始化空收藏列表');
    }
    _loadData();
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
    LogUtil.i('LiveHomePage销毁完成');
    super.dispose();
  }

  // 发送用户行为统计数据
Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
  if (channelName?.isNotEmpty ?? false) {
    try {
      bool hasInitialized = SpUtil.getBool('app_initialized', defValue: false) ?? false;
      bool isTV = context.watch<ThemeProvider>().isTV;
      String deviceType = isTV ? "TV" : "Other";
      
      if (!hasInitialized) {
        LogUtil.i('首次安装，发送设备类型统计: $deviceType');
        await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: deviceType);
        await SpUtil.putBool('app_initialized', true);
      } else {
        LogUtil.i('发送频道统计: $channelName');
        await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: channelName!);
      }
    } catch (e) {
      LogUtil.e('流量统计失败: $e');
    }
  }
}

  // 加载并解析M3U播放列表数据
  Future<void> _loadData() async {
    _updateState({'retrying': false, 'switching': false, 'audio': false});
    _cancelAllTimers();
    if (widget.m3uData.playList?.isEmpty ?? true) {
      LogUtil.e('播放列表无效');
      _updateState({'message': S.current.getDefaultError});
      return;
    }
    try {
      _videoMap = widget.m3uData;
      String? userInfo = SpUtil.getString('user_all_info');
      await _initializeZhConverters();
      await _sortVideoMap(_videoMap!, userInfo);
      _updateState({'sourceIndex': 0});
      await _initializeChannel();
    } catch (e) {
      LogUtil.e('加载播放列表失败: $e');
      _updateState({'message': S.current.parseError});
    }
  }

  // 从播放列表中提取第一个有效的频道
  PlayModel? _getFirstChannel(Map<String, dynamic> playList) {
    try {
      for (final categoryEntry in playList.entries) {
        final categoryData = categoryEntry.value;
        if (categoryData is Map<String, Map<String, PlayModel>>) {
          for (final groupEntry in categoryData.entries) {
            final channelMap = groupEntry.value;
            for (final channel in channelMap.values) {
              if (channel.urls?.isNotEmpty ?? false) {
                return channel;
              }
            }
          }
        } else if (categoryData is Map<String, PlayModel>) {
          for (final channel in categoryData.values) {
            if (channel.urls?.isNotEmpty ?? false) {
              LogUtil.i('找到首个频道: ${channel.title}');
              return channel;
            }
          }
        }
      }
    } catch (e) {
      LogUtil.e('提取频道失败: $e');
    }
    LogUtil.e('未找到有效频道');
    return null;
  }

  // 检查指定频道是否已收藏
  bool isChannelFavorite(String channelId) {
    String groupName = _currentChannel?.group ?? '';
    String channelName = _currentChannel?.title ?? '';
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
  }

  // 切换频道收藏状态并同步到存储
  void toggleFavorite(String channelId) async {
    LogUtil.i('切换收藏状态: $channelId');
    bool isFavoriteChanged = false;
    String actualChannelId = _currentChannel?.id ?? channelId;
    String groupName = _currentChannel?.group ?? '';
    String channelName = _currentChannel?.title ?? '';
    if (groupName.isEmpty || channelName.isEmpty) {
      LogUtil.e('频道信息不完整，无法收藏');
      CustomSnackBar.showSnackBar(context, S.current.channelnofavorite, duration: Duration(seconds: snackBarDurationSeconds));
      return;
    }
    if (isChannelFavorite(actualChannelId)) {
      LogUtil.i('移除收藏: $channelName');
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
      CustomSnackBar.showSnackBar(context, S.current.removefavorite, duration: Duration(seconds: snackBarDurationSeconds));
      isFavoriteChanged = true;
    } else {
      LogUtil.i('添加收藏: $channelName');
      favoriteList[Config.myFavoriteKey]![groupName] ??= {};
      PlayModel newFavorite = PlayModel(
        id: actualChannelId,
        group: groupName,
        logo: _currentChannel?.logo,
        title: channelName,
        urls: _currentChannel?.urls ?? [],
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

  // 重新解析播放列表数据
  Future<void> _parseData() async {
    LogUtil.i('重新解析播放列表数据');
    try {
      if (_videoMap?.playList?.isEmpty ?? true) {
        LogUtil.e('播放列表无效');
        _updateState({'message': S.current.getDefaultError});
        return;
      }
      _updateState({'sourceIndex': 0});
      await _initializeChannel();
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
        toastString: _states['message'],
        controller: _playerController,
        isBuffering: _states['buffering'],
        isPlaying: _states['playing'],
        aspectRatio: _states['aspectRatioValue'],
        onChangeSubSource: _parseData,
        changeChannelSources: _changeChannelSources,
        toggleFavorite: toggleFavorite,
        isChannelFavorite: isChannelFavorite,
        currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
        currentChannelLogo: _currentChannel?.logo ?? '',
        currentChannelTitle: _currentChannel?.title ?? _currentChannel?.id ?? '',
        isAudio: _states['audio'],
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
              toastString: _states['message'],
              controller: _playerController,
              changeChannelSources: _changeChannelSources,
              isLandscape: false,
              isBuffering: _states['buffering'],
              isPlaying: _states['playing'],
              aspectRatio: _states['aspectRatioValue'],
              onChangeSubSource: _parseData,
              drawChild: ChannelDrawerPage(
                key: _states['drawerRefreshKey'],
                refreshKey: _states['drawerRefreshKey'],
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
              isAudio: _states['audio'],
              adManager: _adManager,
              showPlayIcon: _states['showPlay'],
              showPauseIconFromListener: _states['showPause'],
              isHls: PlayerManager.isHlsStream(_currentPlayUrl),
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
                  body: _states['message'] == 'UNKNOWN'
                      ? EmptyPage(onRefresh: _loadData)
                      : TableVideoWidget(
                          toastString: _states['message'],
                          controller: _playerController,
                          isBuffering: _states['buffering'],
                          isPlaying: _states['playing'],
                          aspectRatio: _states['aspectRatioValue'],
                          drawerIsOpen: _states['drawerIsOpen'],
                          changeChannelSources: _changeChannelSources,
                          isChannelFavorite: isChannelFavorite,
                          currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
                          currentChannelLogo: _currentChannel?.logo ?? '',
                          currentChannelTitle: _currentChannel?.title ?? _currentChannel?.id ?? '',
                          toggleFavorite: toggleFavorite,
                          isLandscape: true,
                          isAudio: _states['audio'],
                          onToggleDrawer: () => _updateState({'drawerIsOpen': !_states['drawerIsOpen']}),
                          adManager: _adManager,
                          showPlayIcon: _states['showPlay'],
                          showPauseIconFromListener: _states['showPause'],
                          isHls: PlayerManager.isHlsStream(_currentPlayUrl),
                          onUserPaused: _handleUserPaused,
                          onRetry: _handleRetry,
                        ),
                ),
                Offstage(
                  offstage: !_states['drawerIsOpen'],
                  child: GestureDetector(
                    onTap: () => _updateState({'drawerIsOpen': false}),
                    child: ChannelDrawerPage(
                      key: _states['drawerRefreshKey'],
                      refreshKey: _states['drawerRefreshKey'],
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
