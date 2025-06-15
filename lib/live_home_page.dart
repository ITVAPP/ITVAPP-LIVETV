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

  // 检测URL是否为HLS直播流格式 - 优化版本，减少字符串操作
  static bool isHlsStream(String? url) {
    if (url?.isEmpty ?? true) return false;
    
    // 优化：先检查最常见的情况
    if (url!.contains('.m3u8')) return true;
    
    // 优化：使用单次遍历检查所有非HLS格式
    final lowercaseUrl = url.toLowerCase();
    const nonHlsFormats = [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac', '.flv', 'rtmp:'
    ];
    
    for (final format in nonHlsFormats) {
      if (lowercaseUrl.contains(format)) return false;
    }
    
    return true;
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

  // 缓冲循环检测相关常量和变量
  static const int maxBufferingStarts = 5;        // 频繁缓冲检测阈值：连续缓冲次数
  static const int maxTimeGapSeconds = 5;         // 频繁缓冲异常时间差阈值
  static const int maxSingleBufferingSeconds = 10; // 单次缓冲超时阈值（与m3u8Check同步）
  static const int maxBufferingRecords = 10;      // 缓冲记录最大保存数量
  
  // 优化：使用固定大小的循环缓冲区替代动态List
  final List<DateTime?> _bufferingStartTimes = List.filled(maxBufferingRecords, null);
  int _bufferingStartIndex = 0;  // 循环缓冲区的当前索引
  int _bufferingCount = 0;        // 实际记录数量
  Timer? _bufferingTimeoutTimer;  // 单次缓冲超时检测定时器

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
    // 'shouldUpdateAspectRatio': true,  // 移除此状态，不再动态更新视频比例
    'drawerIsOpen': false,
    'sourceIndex': 0,
    'retryCount': 0,
    'aspectRatioValue': PlayerManager.defaultAspectRatio,  // 固定使用16:9比例
    'message': '', // 会在 initState 中设置
    'drawerRefreshKey': null,
  };

  // 防抖相关状态变量
  String? _currentPlayingKey; // 当前正在播放的频道+线路键
  
  // 新增：保存 isTV 值
  late final bool _isTV;

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
  Map<String, dynamic>? _pendingSwitch; // 待处理的频道切换请求
  Timer? _debounceTimer; // 防抖动延迟定时器
  bool _hasInitializedAdManager = false; // 广告管理器初始化完成标识
  String? _lastPlayedChannelId; // 最后播放频道的唯一标识
  late CancelToken _cancelToken; // 网络请求统一取消令牌

  // 检测频繁缓冲循环异常的方法 - 优化版本，使用循环缓冲区
  void _checkFrequentBufferingLoop() {
    final now = DateTime.now();
    
    // 添加新记录到循环缓冲区
    _bufferingStartTimes[_bufferingStartIndex] = now;
    _bufferingStartIndex = (_bufferingStartIndex + 1) % maxBufferingRecords;
    if (_bufferingCount < maxBufferingRecords) {
      _bufferingCount++;
    }
    
    // 当达到阈值时进行检测
    if (_bufferingCount >= maxBufferingStarts) {
      // 找出有效记录中的最早和最晚时间
      DateTime? firstTime;
      DateTime? lastTime;
      int validCount = 0;
      
      for (int i = 0; i < maxBufferingRecords; i++) {
        final time = _bufferingStartTimes[i];
        if (time != null && now.difference(time).inSeconds <= maxTimeGapSeconds) {
          firstTime ??= time;
          lastTime = time;
          validCount++;
        }
      }
      
      if (validCount >= maxBufferingStarts && firstTime != null && lastTime != null) {
        final timeGap = lastTime.difference(firstTime).inSeconds;
        if (timeGap <= maxTimeGapSeconds) {
          LogUtil.e('检测到频繁缓冲循环异常: ${validCount}次/${timeGap}秒，触发失败处理');
          _cleanupBufferingDetection();
          _handleBufferingAnomaly('频繁缓冲循环');
          return;
        }
      }
    }
    
    // 启动单次缓冲超时检测
    _startBufferingTimeoutDetection();
  }

  // 启动单次缓冲超时检测
  void _startBufferingTimeoutDetection() {
    _bufferingTimeoutTimer?.cancel();
    
    _bufferingTimeoutTimer = Timer(
      Duration(seconds: maxSingleBufferingSeconds),
      () {
        if (!mounted || !_states['buffering'] || _states['disposing']) {
          LogUtil.i('缓冲超时检测取消: ${!mounted ? "组件未挂载" : (!_states['buffering'] ? "非缓冲状态" : "正在释放资源")}');
          return;
        }
        
        // 定时器触发即表示超时，无需重复计算时间
        LogUtil.e('检测到单次缓冲超时: ${maxSingleBufferingSeconds}秒，触发失败处理');
        _handleBufferingAnomaly('单次缓冲超时');
      },
    );
    LogUtil.i('启动缓冲超时检测: ${maxSingleBufferingSeconds}秒');
  }

  // 停止单次缓冲超时检测
  void _stopBufferingTimeoutDetection() {
    if (_bufferingTimeoutTimer?.isActive == true) {
      LogUtil.i('停止缓冲超时检测');
      _bufferingTimeoutTimer?.cancel();
      _bufferingTimeoutTimer = null;
    }
  }

  // 统一处理缓冲异常的方法
  void _handleBufferingAnomaly(String anomalyType) {
    if (!_canPerformOperation('处理缓冲异常[$anomalyType]', 
        checkRetrying: false,  // 不检查retrying状态
        checkSwitching: false,  // 缓冲异常不被switching阻塞
        checkDisposing: true)) {
      return;
    }
    
    // 如果正在重试，需要中断当前重试
    if (_states['retrying']) {
      LogUtil.i('缓冲异常中断当前重试');
      _cancelTimer(TimerType.retry);
      _updateState({'retrying': false});
    }
    
    // 清空播放键，允许重试
    _currentPlayingKey = null;
    
    // 清理缓冲检测状态
    _cleanupBufferingDetection();
    
    // 触发重试逻辑
    _retryPlayback(resetRetryCount: true);
  }

  // 清理所有缓冲检测相关状态 - 优化版本
  void _cleanupBufferingDetection() {
    // 清空循环缓冲区
    for (int i = 0; i < maxBufferingRecords; i++) {
      _bufferingStartTimes[i] = null;
    }
    _bufferingStartIndex = 0;
    _bufferingCount = 0;
    _stopBufferingTimeoutDetection();
    LogUtil.i('清理缓冲检测状态');
  }

  // 生成频道+线路的唯一标识
  String _generateChannelKey(PlayModel? channel, int sourceIndex) {
    if (channel == null) return '';
    String channelName = channel.title ?? channel.id ?? '';
    return '${channelName}_$sourceIndex';
  }

  // 状态更新方法 - 优化版本，分离UI状态和逻辑状态
  void _updateState(Map<String, dynamic> updates) {
    if (!mounted) return;
    
    // 定义需要触发UI更新的状态键
    final uiStateKeys = {
      'playing', 'buffering', 'showPlay', 'showPause', 'message', 
      'drawerIsOpen', 'aspectRatioValue', 'audio', 'drawerRefreshKey'
    };
    
    // 分离UI状态和逻辑状态更新
    final uiUpdates = <String, dynamic>{};
    final logicUpdates = <String, dynamic>{};
    
    updates.forEach((key, value) {
      if (uiStateKeys.contains(key)) {
        uiUpdates[key] = value;
      } else {
        logicUpdates[key] = value;
      }
    });
    
    // 处理UI状态更新（需要setState）
    if (uiUpdates.isNotEmpty) {
      final actualUIChanges = uiUpdates.entries
          .where((entry) => _states[entry.key] != entry.value)
          .fold<Map<String, dynamic>>({}, (map, entry) {
        map[entry.key] = entry.value;
        return map;
      });
      
      if (actualUIChanges.isNotEmpty) {
        LogUtil.i('UI状态更新: $actualUIChanges');
        setState(() {
          _states.addAll(actualUIChanges);
        });
      }
    }
    
    // 处理逻辑状态更新（不需要setState）
    if (logicUpdates.isNotEmpty) {
      final actualLogicChanges = logicUpdates.entries
          .where((entry) => _states[entry.key] != entry.value)
          .fold<Map<String, dynamic>>({}, (map, entry) {
        map[entry.key] = entry.value;
        return map;
      });
      
      if (actualLogicChanges.isNotEmpty) {
        LogUtil.i('逻辑状态更新: $actualLogicChanges');
        _states.addAll(actualLogicChanges);
      }
    }
  }

  // 启动指定类型的单次定时器
  void _startTimer(TimerType type, {Duration? customDuration, required Function() callback}) {
    _timers[type.name]?.cancel();
    final duration = customDuration ?? Duration(seconds: type.seconds);
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
          await _switchChannel({'channel': _currentChannel, 'sourceIndex': _states['sourceIndex']});
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
    _preCachedUrl = null;
    if (_preCacheStreamUrl != null) {
      await _cleanupStreamUrls();
      LogUtil.i('预缓存清理完成');
    }
  }

  // 切换到已预缓存的播放地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
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
      _updateState({'switching': true});
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
      _currentPlayUrl = _preCachedUrl!;
      _updateState({'playing': true, 'buffering': false, 'showPlay': false, 'showPause': false});
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
        _adManager.onChannelChanged(channelId);
      }
      String sourceName = _currentChannel!.urls![_states['sourceIndex']].contains('\$') 
          ? _currentChannel!.urls![_states['sourceIndex']].split('\$')[1].trim()
          : S.current.lineIndex(_states['sourceIndex'] + 1);
      await _releaseAllResources(resetAd: false, resetSwitchCount: !isSourceSwitch);
    
      // 创建新的 CancelToken
      _cancelToken = CancelToken();
    
      _updateState({
        'switching': true, 
        'timeoutActive': false, 
        'message': '${_currentChannel!.title} - $sourceName  ${S.current.loading}',  // 设置加载消息
      });
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
         LogUtil.e('地址解析失败: $url');
      }
      
      if (!isPreload && !isReparse) {
        _streamUrl = streamUrlInstance;
        _currentPlayUrl = parsedUrl;
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
        streamUrlInstance = null; // 标记已使用，防止finally清理
      } else {
        if (isReparse && _states['disposing']) {
          _updateState({'switching': false});
          try {
            await streamUrlInstance.dispose();
          } catch (e) {
            LogUtil.e('清理重新解析StreamUrl失败: $e');
          }
          return;
        }
        await _cleanupStreamUrls();
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
        streamUrlInstance = null; // 标记已使用，防止finally清理
      }
    } catch (e, stackTrace) {
      LogUtil.logError('$operationName失败: $parsedUrl', e, stackTrace);
      if (!isPreload && !isReparse) {
        _switchAttemptCount++;
        if (_switchAttemptCount <= PlayerManager.maxSwitchAttempts) {
          LogUtil.i('切换下一源，尝试次数: $_switchAttemptCount');
          _handleSourceSwitching();
        } else {
          LogUtil.e('切换尝试超限，停止播放');
          _switchAttemptCount = 0;
          await _handleNoMoreSources();
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
    } finally {
      // 如果streamUrlInstance还存在，说明创建了但没有成功使用，需要清理
      if (streamUrlInstance != null) {
        try {
          await streamUrlInstance.dispose();
        } catch (e) {
          LogUtil.e('清理未使用StreamUrl失败: $e');
        }
      }
      if (mounted) {
        if (!isPreload && !isReparse) {
          _checkPendingSwitch();
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
    _updateState({'timeoutActive': true});
    _startTimer(TimerType.playbackTimeout, callback: () {
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

  // 处理频道切换请求，支持防抖动
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
    
    // 简化为一层检查，合并playing和switching状态
    String requestKey = _generateChannelKey(channel, sourceIndex);
    LogUtil.i('切换频道请求: ${channel.title}, 源索引: $sourceIndex, 键: $requestKey');
    
    // 如果是相同频道+线路且正在播放或切换中，直接忽略
    if (requestKey == _currentPlayingKey && (_states['playing'] || _states['switching'])) {
      LogUtil.i('相同频道+线路正在播放或切换中，忽略: $requestKey');
      return;
    }
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
      if (!mounted) return;
      final safeIndex = (sourceIndex < 0 || sourceIndex >= channel.urls!.length) ? 0 : sourceIndex;
      _pendingSwitch = {'channel': channel, 'sourceIndex': safeIndex};
      if (!_states['switching']) {
        _checkPendingSwitch();
      }
    });
  }

  // 检查并处理待执行的频道切换请求
  void _checkPendingSwitch() {
    if (_pendingSwitch == null || !_canPerformOperation('处理待切换')) {
      return;
    }
    final nextRequest = _pendingSwitch!;
    _pendingSwitch = null;
    _currentChannel = nextRequest['channel'] as PlayModel?;
    _updateState({'sourceIndex': nextRequest['sourceIndex'] as int});
    
    // 在开始播放前就设置播放键，提供更早的防护
    if (_currentChannel != null) {
      _currentPlayingKey = _generateChannelKey(_currentChannel, _states['sourceIndex']);
    }
    
    Future.microtask(() => _playVideo());
  }

  // 处理播放源切换逻辑，支持多源轮换 - 修改此方法支持循环播放
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    LogUtil.i('处理源切换，来源: ${isFromFinished ? "播放结束" : "失败"}');
    if (_states['retrying'] || _states['disposing']) {
      LogUtil.i('跳过源切换: ${_states['retrying'] ? "正在重试" : "正在释放"}');
      return;
    }
    _cancelTimers([TimerType.retry, TimerType.playbackTimeout]);
    String? nextUrl;
    int nextSourceIndex = _states['sourceIndex'] + 1;
    
    if (_currentChannel?.urls?.isNotEmpty ?? false) {
      final List<String> urls = _currentChannel!.urls!;
      
      if (nextSourceIndex < urls.length) {
        // 有下一个源
        nextUrl = urls[nextSourceIndex];
      } else if (isFromFinished && urls.length > 0) {
        // 播放结束且没有下一个源时，循环到第一个源
        nextUrl = urls[0];
        nextSourceIndex = 0;
        LogUtil.i('播放结束，循环到第一个源');
      }
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
      'sourceIndex': nextSourceIndex,
      'message': S.current.lineToast(nextSourceIndex + 1, _currentChannel?.title ?? ''),
    });
    _resetOperationStates();
    _preCachedUrl = null;
    LogUtil.i('切换到源索引: $nextSourceIndex, URL: $nextUrl');
    _cancelTimer(TimerType.retry);
    _startTimer(TimerType.retry, callback: () async {
      if (!_canPerformOperation('启动新源')) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  // 视频播放器事件监听处理器 - 修改此方法支持非HLS循环预加载
  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _states['disposing'] || _states['switching']) return;
    
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
        // 注释掉动态视频比例计算逻辑，统一使用16:9
        /*
        if (_states['shouldUpdateAspectRatio']) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? PlayerManager.defaultAspectRatio;
          if (_states['aspectRatioValue'] != newAspectRatio) {
            _updateState({'aspectRatioValue': newAspectRatio, 'shouldUpdateAspectRatio': false});
          }
        }
        */
        break;
      case BetterPlayerEventType.exception:
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "未知错误"}');
        
        // 播放异常时清空播放键，允许重试
        _currentPlayingKey = null;
        
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
        
        // 检测频繁缓冲循环异常
        _checkFrequentBufferingLoop();
        break;
      case BetterPlayerEventType.bufferingEnd:
        // 停止缓冲超时检测
        _stopBufferingTimeoutDetection();
        
        _updateState({
          'buffering': false,
          'message': 'HIDE_CONTAINER',
          'showPause': _states['userPaused'] ? false : _states['showPause'],
        });
        break;
      case BetterPlayerEventType.play:
        if (!_states['playing']) {
          _updateState({
            'playing': true, 
            'buffering': false, 
            'showPlay': false, 
            'showPause': false,
            'message': _states['buffering'] ? _states['message'] : 'HIDE_CONTAINER', 
            'userPaused': false
          });
          
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
        
        // 修复：添加数据有效性验证
        if (position == null || duration == null || duration.inMilliseconds <= 0) {
          return;
        }
        
        // 修复：处理异常的播放位置
        if (position > duration) {
          LogUtil.w('播放位置超过总时长: position=${position.inSeconds}s, duration=${duration.inSeconds}s');
          // 如果有预缓存，尝试切换
          if (_preCachedUrl != null) {
            LogUtil.i('检测到异常播放位置，切换预缓存');
            await _switchToPreCachedUrl('异常位置触发');
          }
          return;
        }
        
        final remainingTime = duration - position;
        bool isHls = PlayerManager.isHlsStream(_currentPlayUrl);
        
        if (isHls) {
          if (_preCachedUrl != null && remainingTime.inSeconds <= PlayerManager.switchThresholdSeconds) {
            LogUtil.i('HLS剩余时间不足，切换预缓存: ${remainingTime.inSeconds}秒');
            await _switchToPreCachedUrl('HLS剩余时间触发');
          }
        } else {
          // 非HLS流处理逻辑 - 添加循环预加载支持
          if (remainingTime.inSeconds <= PlayerManager.nonHlsPreloadThresholdSeconds) {
            String? nextUrl;
            int preloadSourceIndex = -1;
            
            if (_currentChannel?.urls?.isNotEmpty ?? false) {
              final List<String> urls = _currentChannel!.urls!;
              final nextSourceIndex = _states['sourceIndex'] + 1;
              
              if (nextSourceIndex < urls.length) {
                // 有下一个源
                nextUrl = urls[nextSourceIndex];
                preloadSourceIndex = nextSourceIndex;
              } else if (urls.length > 0) {
                // 没有下一个源，循环到第一个源
                nextUrl = urls[0];
                preloadSourceIndex = 0;
                LogUtil.i('非HLS无下一源，预加载第一个源（循环播放）');
              }
            }
            
            if (nextUrl != null && nextUrl != _preCachedUrl) {
              LogUtil.i('非HLS预加载源索引: $preloadSourceIndex, URL: $nextUrl');
              await _playVideo(isPreload: true, specificUrl: nextUrl);
            }
          }
          
          if (remainingTime.inSeconds <= PlayerManager.switchThresholdSeconds && _preCachedUrl != null) {
            LogUtil.i('非HLS切换预缓存: ${remainingTime.inSeconds}秒');
            await _switchToPreCachedUrl('非HLS切换触发');
          }
        }
        break;
      case BetterPlayerEventType.finished:
        if (_states['switching']) return;
        LogUtil.i('播放结束');
        
        // 播放结束时清空播放键
        _currentPlayingKey = null;
        
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
          // 非HLS且无预缓存，尝试源切换（包括循环）
          LogUtil.i('播放完成，尝试下一源或循环');
          _handleSourceSwitching(isFromFinished: true);
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
                    content.contains('#EXTINF'));
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
    
    // 避免重复触发
    if (_states['retrying']) {
      LogUtil.i('已在重试中，忽略重复请求');
      return;
    }
    
    if (!_canPerformOperation('重试播放')) {
      LogUtil.i('重试阻止: 状态冲突');
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
    // 清空播放键，允许用户重试
    _currentPlayingKey = null;
    
    LogUtil.i('播放结束，无更多源');
    _switchAttemptCount = 0;
    
    // 先调用统一资源清理
    await _releaseAllResources();
    
    // 再设置特有状态，避免被覆盖
    _updateState({
      'message': S.current.playError,
      'sourceIndex': 0,
    });
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
      _updateState({
        'sourceIndex': 0, 
        // 'shouldUpdateAspectRatio': true  // 移除此行，不再动态更新视频比例
      });
      _switchAttemptCount = 0;
      await _switchChannel({'channel': _currentChannel, 'sourceIndex': _states['sourceIndex']});
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e) {
      LogUtil.e('切换频道失败: $e');
      _updateState({'message': S.current.playError});
      await _releaseAllResources();
    }
  }

  // 显示频道播放源选择对话框
  Future<void> _changeChannelSources() async {
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

  // 清理StreamUrl - 优化版本，更好的错误处理
  Future<void> _cleanupStreamUrls() async {
    try {
      final cleanupTasks = <Future<void>>[];
      
      if (_streamUrl != null) {
        final streamUrl = _streamUrl!;
        _streamUrl = null; // 先置空，防止重复清理
        cleanupTasks.add(streamUrl.dispose());
      }
      
      if (_preCacheStreamUrl != null) {
        final preCacheStreamUrl = _preCacheStreamUrl!;
        _preCacheStreamUrl = null; // 先置空，防止重复清理
        cleanupTasks.add(preCacheStreamUrl.dispose());
      }
      
      if (cleanupTasks.isNotEmpty) {
        await Future.wait(cleanupTasks);
        LogUtil.i('StreamUrl资源清理完成');
      }
    } catch (e) {
      LogUtil.e('StreamUrl清理失败: $e');
      // 即使清理失败，也要置空引用避免内存泄漏
      _streamUrl = null;
      _preCacheStreamUrl = null;
    }
  }

  // 释放所有资源的方法 - 优化版本，减少重复代码
  Future<void> _releaseAllResources({bool resetAd = true, bool resetSwitchCount = true}) async {
    _updateState({'disposing': true});
    
    try {
      // 1. 取消所有定时器（包括防抖定时器）
      _cancelAllTimers();
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _cancelToken.cancel();
      
      // 2. 清理缓冲循环检测记录
      _cleanupBufferingDetection();
      
      // 3. 清理播放器
      if (_playerController != null) {
        try {
          _playerController!.removeEventsListener(_videoListener);
          if (_playerController!.isPlaying() ?? false) {
            await _playerController!.pause();
            await _playerController!.setVolume(0);
          }
          _playerController!.dispose(forceDispose: true);
          _playerController = null;
        } catch (e) {
          LogUtil.e('播放器清理失败: $e');
          _playerController = null;
        }
      }
      
      // 4. 清理StreamUrl资源
      await _cleanupStreamUrls();
      
      // 5. 根据参数决定是否重置广告管理器
      if (resetAd) {
        LogUtil.i('重置广告管理器');
        _adManager.reset(rescheduleAds: false, preserveTimers: true);
      } 
      
      // 6. 重置状态变量和关键标识
      if (mounted) {
        _updateState({
          'retrying': false, 
          'switching': false,
          'playing': false,
          'buffering': false,
          'showPlay': false,
          'showPause': false,
          'userPaused': false,
          'progressEnabled': false,
          'timeoutActive': false,  // 重置超时检测状态
        });
        _preCachedUrl = null;
        _lastParseTime = null;
        _currentPlayUrl = null;
        _originalUrl = null;
        _m3u8InvalidCount = 0;
        if (resetSwitchCount) {
          _switchAttemptCount = 0;      // 重置源切换计数
        }
        _currentPlayingKey = null;    // 重置防重复播放标识
      }
    } catch (e) {
      LogUtil.e('资源释放失败: $e');
    } finally {
      LogUtil.i('资源释放完成');
      if (mounted) {
        _updateState({'disposing': false});
        
        // 处理待切换请求
        if (_pendingSwitch != null) {
          LogUtil.i('处理待切换请求: ${(_pendingSwitch!['channel'] as PlayModel?)?.title}');
          Future.microtask(() {
            if (mounted && !_states['disposing']) {
              _checkPendingSwitch();
            }
          });
        }
      }
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
    
    // 解析用户地理信息
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
      
      // 先检查是否需要排序
      final groupList = groups.keys.toList();
      bool categoryNeedsSort = groupList.any((group) => group.contains(regionPrefix!));
      if (!categoryNeedsSort) return;
      
      final List<String> matchedGroups = [];
      final List<String> otherGroups = [];
      
      for (var group in groupList) {
        if (group.startsWith(regionPrefix!)) {
          matchedGroups.add(group);
        } else {
          otherGroups.add(group);
        }
      }
      
      // 如果没有匹配的组，跳过
      if (matchedGroups.isEmpty) return;
      
      // 重建groups - 匹配的组排在前面
      final newGroups = <String, Map<String, PlayModel>>{};
      
      // 先添加匹配的组
      for (var group in matchedGroups) {
        final channels = groups[group];
        if (channels is! Map<String, PlayModel>) {
          LogUtil.e('组 $group 类型无效');
          continue;
        }
        
        // 城市级别排序（仅在需要时）
        if (cityPrefix?.isNotEmpty ?? false) {
          final channelList = channels.keys.toList();
          final List<String> matchedChannels = [];
          final List<String> otherChannels = [];
          
          for (var channel in channelList) {
            if (channel.startsWith(cityPrefix!)) {
              matchedChannels.add(channel);
            } else {
              otherChannels.add(channel);
            }
          }
          
          if (matchedChannels.isNotEmpty) {
            final sortedChannels = <String, PlayModel>{};
            // 添加匹配的频道
            for (var channel in matchedChannels) {
              sortedChannels[channel] = channels[channel]!;
            }
            // 添加其他频道
            for (var channel in otherChannels) {
              sortedChannels[channel] = channels[channel]!;
            }
            newGroups[group] = sortedChannels;
          } else {
            newGroups[group] = channels;
          }
        } else {
          newGroups[group] = channels;
        }
      }
      
      // 再添加其他组
      for (var group in otherGroups) {
        newGroups[group] = groups[group]!;
      }
      
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成');
    });
  }

  // 处理Android返回键，支持退出确认
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_states['drawerIsOpen']) {
      _updateState({'drawerIsOpen': false});
      return false;
    }
    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) {
      await _playerController?.pause();
    }
    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    if (!shouldExit && wasPlaying && mounted) {
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
    
    // 一次性读取 isTV 值
    _isTV = context.read<ThemeProvider>().isTV;
    
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
    _debounceTimer?.cancel();
    _currentPlayingKey = null;
    
    // 先清理所有常规资源
    _releaseAllResources();
    
    // 然后处理销毁特有逻辑
    _adManager.dispose();
    favoriteList.clear();
    _videoMap = null;
    _s2tConverter = null;
    _t2sConverter = null;
    super.dispose();
  }

  // 发送用户行为统计数据
  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName?.isNotEmpty ?? false) {
      try {
        bool hasInitialized = SpUtil.getBool('app_initialized', defValue: false) ?? false;
        String deviceType = _isTV ? "TV" : "Other";  // 使用成员变量
        
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

  // 从播放列表中提取第一个有效的频道 - 优化版本，添加早期返回
  PlayModel? _getFirstChannel(Map<String, dynamic> playList) {
    try {
      for (final categoryEntry in playList.entries) {
        final categoryData = categoryEntry.value;
        
        if (categoryData is Map<String, Map<String, PlayModel>>) {
          for (final groupEntry in categoryData.entries) {
            final channelMap = groupEntry.value;
            for (final channel in channelMap.values) {
              if (channel.urls?.isNotEmpty ?? false) {
                return channel; // 找到第一个有效频道立即返回
              }
            }
          }
        } else if (categoryData is Map<String, PlayModel>) {
          for (final channel in categoryData.values) {
            if (channel.urls?.isNotEmpty ?? false) {
              return channel; // 找到第一个有效频道立即返回
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
    if (_isTV) {  // 直接使用成员变量
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
        isLandscape: true,  // TV端始终是横屏
        showPlayIcon: _states['showPlay'],
        showPauseIconFromListener: _states['showPause'],
        isHls: PlayerManager.isHlsStream(_currentPlayUrl),
        onUserPaused: () {_updateState({'userPaused': true});},
        onRetry: () {_retryPlayback(resetRetryCount: true);},
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
              onUserPaused: () {_updateState({'userPaused': true});},
              onRetry: () {_retryPlayback(resetRetryCount: true);},
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
                          onUserPaused: () {_updateState({'userPaused': true});},
                          onRetry: () {_retryPlayback(resetRetryCount: true);},
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
