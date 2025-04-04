import 'dart:io';
import 'dart:async';
import 'dart:convert';
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
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 定义媒体类型枚举，用于统一处理不同类型的媒体
enum MediaType {
 hls,    // HLS 流媒体
 video,  // 普通视频文件
 audio,  // 音频文件
 unknown // 未知类型
}

/// 主页面
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData;
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int defaultMaxRetries = 1; // 默认最大重试次数，控制播放失败后尝试重新播放的最大次数
  static const int defaultTimeoutSeconds = 36; // 解析超时秒数，若超过此时间仍未完成，则视为解析失败
  static const int initialProgressDelaySeconds = 60; // 播放开始后经过此时间才会启用进度事件监听（progress）
  static const int bufferUpdateTimeoutSeconds = 6; // 若缓冲区最后一次更新距现在超过此时间（秒），且其他条件满足，则触发重新解析
  static const int minRemainingBufferSeconds = 8; // 最小剩余缓冲秒数，HLS流中若缓冲区剩余时间低于此值，用于判断是否需要重新解析
  static const int bufferHistorySize = 6; // 缓冲历史记录大小，保存最近的缓冲记录条数，至少需此数量以支持重新解析条件检查
  static const int positionIncreaseThreshold = 5; // 播放位置需连续增加此次数，且满足其他条件才触发重新解析，表示播放正常但缓冲不足
  static const int lowBufferThresholdCount = 3; // 低缓冲次数阈值，剩余缓冲低于次数需达到此值，才触发重新解析，表示缓冲持续不足
  static const int networkRecoveryBufferSeconds = 7; // 重新解析后若缓冲区剩余时间超过此值（秒），认为网络已恢复，取消切换操作
  static const int retryDelaySeconds = 2; // 播放失败或切换源时，等待此时间（秒）后重新播放或加载新源，给予系统清理和准备的时间
  static const int hlsSwitchThresholdSeconds = 3; // 当HLS流剩余播放时间少于此值（秒）且有预缓存地址时，切换到预缓存地址
  static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS流剩余时间少于此值（秒）时，开始预加载下一源，提前准备切换
  static const int nonHlsSwitchThresholdSeconds = 3; // 非HLS流剩余时间少于此值（秒）且有预缓存地址时，切换到预缓存地址
  static const double defaultAspectRatio = 1.78; // 视频播放器的初始宽高比（16:9），若未从播放器获取新值则使用此值
  static const int cleanupDelayMilliseconds = 500; // 清理控制器前的延迟毫秒数，确保旧控制器完全暂停和清理
  static const int snackBarDurationSeconds = 4; // 操作提示的显示时长（秒）
  static const int bufferingStartSeconds = 15; // 缓冲超过计时器的时间就放弃加载，启用重试

  // 缓冲区检查相关变量
  List<Map<String, dynamic>> _bufferedHistory = [];
  String? _preCachedUrl; // 预缓存的URL
  bool _isParsing = false; // 是否正在解析
  Duration? _lastBufferedPosition; // 上次缓冲位置
  int? _lastBufferedTime; // 上次缓冲时间戳（毫秒）
  bool _isRetrying = false; // 是否正在重试
  Timer? _retryTimer; // 重试计时器
  String toastString = S.current.loading; // 提示信息
  PlaylistModel? _videoMap; // 视频映射
  PlayModel? _currentChannel; // 当前频道
  int _sourceIndex = 0; // 当前源索引
  int _lastProgressTime = 0; // 上次进度时间
  BetterPlayerController? _playerController; // 播放器控制器
  bool isBuffering = false; // 是否正在缓冲
  bool isPlaying = false; // 是否正在播放
  double aspectRatio = defaultAspectRatio; // 宽高比
  bool _drawerIsOpen = false; // 抽屉是否打开
  int _retryCount = 0; // 重试次数
  bool _timeoutActive = false; // 超时是否激活
  bool _isDisposing = false; // 是否正在释放资源
  bool _isSwitchingChannel = false; // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 是否应该更新宽高比
  StreamUrl? _streamUrl; // 流地址
  StreamUrl? _preCacheStreamUrl; // 预缓存的 StreamUrl 实例
  String? _currentPlayUrl; // 当前播放的URL（解析后的地址）
  String? _originalUrl; // 解析前的原始地址
  bool _progressEnabled = false; // 进度是否启用
  bool _isHls = false; // 是否是HLS流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  }; // 收藏列表
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析
  bool _isAudio = false; // 是否是音频流
  Timer? _playDurationTimer; // 播放持续时间计时器
  Timer? _timeoutTimer; // 缓冲超时的计时器
  late AdManager _adManager; // 广告管理实例
  bool _isUserPaused = false; // 是否为用户触发的暂停
  bool _showPlayIcon = false; // 控制播放图标显示
  bool _showPauseIconFromListener = false; // 控制非用户触发的暂停图标显示

  // 切换请求队列
  final List<Map<String, dynamic>> _pendingSwitches = []; // 使用列表存储所有切换请求
  bool _isProcessingSwitches = false; // 是否正在处理切换请求

  // 统一检查媒体类型的方法
  MediaType _checkMediaType(String? url) {
    if (url == null || url.isEmpty) return MediaType.unknown;
    
    final lowercaseUrl = url.toLowerCase();
    
    // 检查是否为HLS流
    if (lowercaseUrl.contains('.m3u8')) return MediaType.hls;
    
    // 检查音频格式
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    if (audioFormats.any(lowercaseUrl.contains)) return MediaType.audio;
    
    // 检查视频格式
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    if (videoFormats.any(lowercaseUrl.contains)) return MediaType.video;
    
    // 如果没有明确的文件扩展名，默认视为HLS
    return MediaType.hls;
  }

  bool _checkIsAudioStream(String? url) {
    return _checkMediaType(url) == MediaType.audio;
  }

  bool _isHlsStream(String? url) {
    return _checkMediaType(url) == MediaType.hls;
  }

  // 统一更新 _currentPlayUrl 和 _isHls 的方法
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  // 更新播放器状态的统一方法，避免状态不一致
  void _updatePlayerState({
    bool? buffering, 
    bool? playing, 
    String? toast,
    bool? retrying,
    bool? showPlayIcon,
    bool? showPauseIcon,
    bool? userPaused,
    bool? switchingChannel,
    bool? progressEnabled, 
  }) {
    if (!mounted) return;
    
    setState(() {
      if (buffering != null) isBuffering = buffering;
      if (playing != null) isPlaying = playing;
      if (toast != null) toastString = toast;
      if (retrying != null) _isRetrying = retrying;
      if (showPlayIcon != null) _showPlayIcon = showPlayIcon;
      if (showPauseIcon != null) _showPauseIconFromListener = showPauseIcon;
      if (userPaused != null) _isUserPaused = userPaused;
      if (switchingChannel != null) _isSwitchingChannel = switchingChannel;
      if (progressEnabled != null) _progressEnabled = progressEnabled;
    });
  }

  // 切换到预缓存地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
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

    LogUtil.i('$logDescription: 切换到预缓存地址: $_preCachedUrl');
    _updatePlayUrl(_preCachedUrl!); // 在播放前更新，确保 _isHls 正确
    final newSource = BetterPlayerConfig.createDataSource(url: _currentPlayUrl!, isHls: _isHls);

    try {
      await _playerController?.preCache(newSource);
      LogUtil.i('$logDescription: 预缓存新数据源完成: $_currentPlayUrl');
      await _playerController?.setupDataSource(newSource);
      if (isPlaying) {
        await _playerController?.play();
        LogUtil.i('$logDescription: 切换到预缓存地址并开始播放: $_currentPlayUrl');
        _progressEnabled = false;
        _startPlayDurationTimer();
      } else {
        LogUtil.i('$logDescription: 切换到预缓存地址但保持暂停状态: $_currentPlayUrl');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('$logDescription: 切换到预缓存地址失败', e, stackTrace);
      _retryPlayback();
      return;
    } finally {
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl();
    }
  }

  /// 播放视频，包含初始化和切换逻辑
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    // 添加空检查以防止 _currentChannel 为 null 时崩溃
    if (_currentChannel == null) return; // 避免空指针异常

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');

    _cleanupTimers(); // 清理计时器
    _adManager.reset(); // 重置广告状态
    
    // 使用统一方法更新状态
    _updatePlayerState(
      buffering: false,
      playing: false,
      toast: '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
      userPaused: false,
      showPlayIcon: false,
      showPauseIcon: false,
      switchingChannel: true
    );

    // 启动整个播放流程的超时计时
    _timeoutTimer?.cancel();
    _timeoutActive = true;
    _timeoutTimer = Timer(Duration(seconds: defaultTimeoutSeconds), () {
      if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
        _timeoutActive = false;
        return;
      }
      if (_playerController?.isPlaying() != true) { // 如果 36 秒后未播放成功
        LogUtil.e('播放流程超时（解析或缓冲失败），切换下一源');
        _handleSourceSwitching();
        _timeoutActive = false;
      }
    });

    try {
      // 仅在初次播放频道时检查并触发广告
      if (!isRetry && !isSourceSwitch && _adManager.shouldPlayVideoAd()) {
        await _adManager.playVideoAd(); // 等待广告播放完成
        LogUtil.i('视频广告播放完成，准备播放频道');
        _adManager.reset(); // 检查并可能显示文字广告
      }

      // 如果已有控制器，先暂停并重用，避免重复创建
      if (_playerController != null) {
        await _playerController!.pause();
        await _cleanupController(_playerController);
      }

      await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
      if (!mounted) {
        LogUtil.i('组件已卸载，停止播放流程');
        return;
      }

      // 解析URL并播放
      await _parseAndPlayUrl();
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrl(); // 播放失败时释放
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        _updatePlayerState(switchingChannel: false);
        
        // 如果播放器为空，确保重置其他状态
        if (_playerController == null) {
          _updatePlayerState(buffering: false, playing: false);
        }
        
        // 处理待处理的切换请求
        _processNextPendingSwitch();
      }
    }
  }

  // 新增：解析并播放URL的抽取方法，减少代码重复
  Future<void> _parseAndPlayUrl() async {
    String url = _currentChannel!.urls![_sourceIndex].toString();
    _originalUrl = url; // 设置解析前地址
    
    // 创建并保存StreamUrl实例
    _streamUrl = StreamUrl(url);
    String parsedUrl = await _streamUrl!.getStreamUrl();
    
    if (parsedUrl == 'ERROR') {
      LogUtil.e('地址解析失败: $url');
      _updatePlayerState(toast: S.current.vpnplayError, switchingChannel: false);
      await _disposeStreamUrl();
      return;
    }
    
    // 更新URL和媒体类型
    _updatePlayUrl(parsedUrl);
    
    // 检查是否为音频
    bool isDirectAudio = _checkIsAudioStream(parsedUrl);
    setState(() => _isAudio = isDirectAudio);
    
    LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $isDirectAudio, HLS: $_isHls');
    
    // 创建播放器数据源和配置
    final dataSource = BetterPlayerConfig.createDataSource(
      url: parsedUrl,
      isHls: _isHls,
    );
    
    final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
      eventListener: _videoListener,
      isHls: _isHls,
    );
    
    // 设置并播放
    BetterPlayerController? tempController;
    try {
      tempController = BetterPlayerController(betterPlayerConfiguration);
      await tempController.setupDataSource(dataSource);
      LogUtil.i('播放器数据源设置完成: $parsedUrl');
      setState(() {
        _playerController = tempController;
      });
      await _playerController?.play();
      LogUtil.i('开始播放: $parsedUrl');
      _timeoutActive = false; // 播放成功后取消超时
      _timeoutTimer?.cancel(); // 停止计时器
    } catch (e) {
      tempController?.dispose();
      throw e;
    }
  }

  // 改进切换队列管理，支持多请求排队
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) return;

    // 添加到请求队列
    _pendingSwitches.add({'channel': channel, 'sourceIndex': sourceIndex});
    LogUtil.i('添加切换请求: ${channel.title}, 源索引: $sourceIndex, 队列长度: ${_pendingSwitches.length}');
    
    // 如果不在切换中且未处理队列，则开始处理
    if (!_isSwitchingChannel && !_isProcessingSwitches) {
      _processNextPendingSwitch();
    }
  }

  // 处理下一个切换请求
  Future<void> _processNextPendingSwitch() async {
    // 如果正在切换或处理中，或队列为空，则退出
    if (_isSwitchingChannel || _isProcessingSwitches || _pendingSwitches.isEmpty) {
      return;
    }
    
    _isProcessingSwitches = true;
    
    try {
      // 获取最新请求（队列末尾）并移除其他请求
      final latestRequest = _pendingSwitches.last;
      _pendingSwitches.clear();
      
      // 更新当前频道和源
      _currentChannel = latestRequest['channel'] as PlayModel?;
      _sourceIndex = latestRequest['sourceIndex'] as int;
      _originalUrl = _currentChannel?.urls?[_sourceIndex];
      
      LogUtil.i('处理最新切换请求: ${_currentChannel?.title}, 源索引: $_sourceIndex');
      
      // 执行播放
      await _playVideo();
    } finally {
      _isProcessingSwitches = false;
      
      // 检查是否有新请求添加
      if (_pendingSwitches.isNotEmpty) {
        // 使用微任务避免递归调用引起的堆栈溢出
        Future.microtask(_processNextPendingSwitch);
      }
    }
  }

  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing) return;

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
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "Unknown error"}');
        if (_preCachedUrl != null) {
          await _switchToPreCachedUrl('异常触发');
        } else {
          _retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        _updatePlayerState(
          buffering: true,
          toast: S.current.loading
        );
        
        // 仅在视频已开始播放后启用缓冲超时
        if (isPlaying) {
          // 清理现有超时定时器，避免叠加
          _timeoutTimer?.cancel();
          _timeoutTimer = Timer(const Duration(seconds: bufferingStartSeconds), () {
            _handleBufferingTimeout();
          });
        } else {
          LogUtil.i('初始缓冲，不启用超时');
        }
        break;

      case BetterPlayerEventType.bufferingUpdate:
        _handleBufferingUpdate(event);
        break;

      case BetterPlayerEventType.bufferingEnd:
        _updatePlayerState(
          buffering: false,
          toast: 'HIDE_CONTAINER',
          showPauseIcon: _isUserPaused ? _showPauseIconFromListener : false
        );
        
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        _cleanupTimers();
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          _updatePlayerState(
            playing: true,
            toast: isBuffering ? toastString : 'HIDE_CONTAINER',
            progressEnabled: false,
            showPlayIcon: false,
            showPauseIcon: false,
            userPaused: false
          );
          
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          
          if (_playDurationTimer == null || !_playDurationTimer!.isActive) {
            _startPlayDurationTimer();
          }
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          _updatePlayerState(
            playing: false,
            toast: S.current.playpause,
            showPlayIcon: _isUserPaused,
            showPauseIcon: !_isUserPaused
          );
          
          LogUtil.i('播放暂停，用户触发: $_isUserPaused');
        }
        break;

      case BetterPlayerEventType.progress:
        _handleProgressEvent(event);
        break;

      case BetterPlayerEventType.finished:
        _handlePlaybackFinished();
        break;

      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.changedPlayerVisibility) {
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  // 新增：处理缓冲超时
  void _handleBufferingTimeout() {
    // 检查各种状态以避免不必要触发
    if (!mounted || !isBuffering || _isRetrying || _isSwitchingChannel || _isDisposing || 
        _isParsing || _pendingSwitches.isNotEmpty) {
      LogUtil.i('缓冲超时检查被阻止: mounted=$mounted, isBuffering=$isBuffering, '
          'isRetrying=$_isRetrying, isSwitchingChannel=$_isSwitchingChannel, '
          'isDisposing=$_isDisposing, isParsing=$_isParsing, pendingSwitches=${_pendingSwitches.length}');
      return;
    }
    
    // 检查播放器是否仍在缓冲且未播放
    if (_playerController?.isPlaying() != true) {
      LogUtil.e('播放中缓冲超过设定时间，触发重试');
      _retryPlayback(resetRetryCount: true); // 重置重试次数后重试
    }
  }

  // 新增：处理缓冲区更新
  void _handleBufferingUpdate(BetterPlayerEvent event) {
    if (!_progressEnabled || !isPlaying) return;
    
    final bufferedData = event.parameters?["buffered"];
    if (bufferedData == null) {
      LogUtil.i('缓冲区数据为空');
      _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    
    if (bufferedData is List<dynamic>) {
      if (bufferedData.isNotEmpty) {
        final lastBuffer = bufferedData.last;
        try {
          _lastBufferedPosition = lastBuffer.end as Duration;
          _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
          // LogUtil.i('缓冲区范围更新: $_lastBufferedPosition @ $_lastBufferedTime');
        } catch (e) {
          LogUtil.i('无法解析缓冲对象: $lastBuffer, 错误: $e');
          _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
        }
      } else {
        _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (bufferedData is Duration) {
      _lastBufferedPosition = bufferedData;
      _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('缓冲区更新: $_lastBufferedPosition @ $_lastBufferedTime');
    } else {
      LogUtil.i('未知的缓冲区数据类型: $bufferedData (类型: ${bufferedData.runtimeType})');
      _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  // 新增：处理进度事件
  void _handleProgressEvent(BetterPlayerEvent event) {
    if (!_progressEnabled || !isPlaying) return;
    
    final position = event.parameters?["progress"] as Duration?;
    final duration = event.parameters?["duration"] as Duration?;
    
    if (position == null || duration == null) {
      LogUtil.i('Progress 数据不完整: position=$position, duration=$duration');
      return;
    }
    
    if (_lastBufferedPosition == null || _lastBufferedTime == null) {
      // LogUtil.i('缓冲数据未准备好: _lastBufferedPosition=$_lastBufferedPosition, _lastBufferedTime=$_lastBufferedTime');
      return;
    }
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final timeSinceLastUpdate = (timestamp - _lastBufferedTime!) / 1000.0;
    final remainingBuffer = _lastBufferedPosition! - position;
    
    // 使用列表结构管理缓冲历史
    _addBufferHistoryRecord({
      'buffered': _lastBufferedPosition!,
      'position': position,
      'timestamp': timestamp,
      'remainingBuffer': remainingBuffer,
    });
    
    if (_isHls && !_isParsing) {
      _handleHlsProgress(position, duration, timeSinceLastUpdate);
    } else {
      _handleNonHlsProgress(position, duration);
    }
  }

  // 新增：添加缓冲历史记录并维护大小
  void _addBufferHistoryRecord(Map<String, dynamic> record) {
    _bufferedHistory.add(record);
    // 优化历史记录大小管理，只保留最新的bufferHistorySize条记录
    if (_bufferedHistory.length > bufferHistorySize) {
      _bufferedHistory.removeAt(0);
    }
  }

  // 新增：处理HLS流的进度逻辑
  void _handleHlsProgress(Duration position, Duration duration, double timeSinceLastUpdate) {
    final remainingTime = duration - position;
    // LogUtil.i('HLS 检查 - 当前位置: $position, 缓冲末尾: $_lastBufferedPosition, 时间差: $remainingTime');
    
    // 检查剩余时间是否低于阈值且有预缓存地址
    if (_preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
      _switchToPreCachedUrl('HLS 剩余时间少于 $hlsSwitchThresholdSeconds 秒');
      return;
    }
    
// 检查是否需要触发重新解析
   if (_bufferedHistory.length >= bufferHistorySize) {
     int positionIncreaseCount = 0;
     int remainingBufferLowCount = 0;
     
     // 检查连续的位置增加和缓冲不足情况
     for (int i = _bufferedHistory.length - positionIncreaseThreshold; i < _bufferedHistory.length; i++) {
       final prev = _bufferedHistory[i - 1];
       final curr = _bufferedHistory[i];
       
       if (curr['position'] > prev['position']) {
         positionIncreaseCount++;
       }
       
       if ((curr['remainingBuffer'] as Duration).inSeconds < minRemainingBufferSeconds) {
         remainingBufferLowCount++;
       }
     }
     
     // 如果满足所有条件，触发重新解析
     if (positionIncreaseCount == positionIncreaseThreshold &&
         remainingBufferLowCount >= lowBufferThresholdCount &&
         timeSinceLastUpdate > bufferUpdateTimeoutSeconds) {
       LogUtil.i('触发重新解析: 位置增加 $positionIncreaseThreshold 次，'
           '剩余缓冲 < $minRemainingBufferSeconds 至少 $lowBufferThresholdCount 次，'
           '最后缓冲更新距今 > $bufferUpdateTimeoutSeconds');
       _reparseAndSwitch();
     }
   }
 }

 // 新增：处理非HLS流的进度逻辑
 void _handleNonHlsProgress(Duration position, Duration duration) {
   final remainingTime = duration - position;
   
   // 检查是否需要预加载下一源
   if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
     final nextUrl = _getNextVideoUrl();
     if (nextUrl != null && nextUrl != _preCachedUrl) {
       LogUtil.i('非 HLS 剩余时间少于 $nonHlsPreloadThresholdSeconds 秒，预缓存下一源: $nextUrl');
       _preloadNextVideo(nextUrl);
     }
   }
   
   // 检查是否需要切换到预缓存地址
   if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
     _switchToPreCachedUrl('非 HLS 剩余时间少于 $nonHlsSwitchThresholdSeconds 秒');
   }
 }

 // 新增：处理播放结束事件
 void _handlePlaybackFinished() {
   if (!_isHls && _preCachedUrl != null) {
     _switchToPreCachedUrl('非 HLS 播放结束');
   } else if (_isHls) {
     LogUtil.i('HLS 流异常结束，重试播放');
     _retryPlayback();
   } else {
     LogUtil.i('无更多源可播放');
     _handleNoMoreSources();
   }
 }

 void _startPlayDurationTimer() {
   _playDurationTimer?.cancel();
   _playDurationTimer = Timer(const Duration(seconds: initialProgressDelaySeconds), () {
     if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
       // 检查是否满足启用 _progressEnabled 的条件
       bool shouldEnableProgress = false;

       if (_isHls) {
         if (_originalUrl == null) {
           LogUtil.i('HLS 流检查 - _originalUrl 为 null');
         } else {
           LogUtil.i('HLS 流检查 - 解析前地址: $_originalUrl');
           if (_originalUrl!.toLowerCase().contains('timelimit')) {
             shouldEnableProgress = true;
           }
         }
       } else {
         // 非 HLS 流：有下一个源地址时启用
         if (_getNextVideoUrl() != null) {
           shouldEnableProgress = true;
         }
       }

       if (shouldEnableProgress) {
         LogUtil.i('播放 $initialProgressDelaySeconds 秒，且满足条件，启用 progress 监听');
         _progressEnabled = true;
       } else {
         LogUtil.i('播放 $initialProgressDelaySeconds 秒，但未满足条件，不启用 progress 监听');
       }
       _retryCount = 0;
       _playDurationTimer = null;
     }
   });
 }

 Future<void> _preloadNextVideo(String url) async {
   if (_isDisposing || _isSwitchingChannel || _playerController == null) {
     LogUtil.i('预加载被阻止: _isDisposing=$_isDisposing, _isSwitchingChannel=$_isSwitchingChannel, controller=${_playerController != null}');
     return;
   }

   try {
     LogUtil.i('开始预加载: $url');
     await _disposePreCacheStreamUrl(); // 先释放旧的预缓存实例
     _preCacheStreamUrl = StreamUrl(url); // 保存预缓存实例
     String parsedUrl = await _preCacheStreamUrl!.getStreamUrl(); // 使用保存的实例
     if (parsedUrl == 'ERROR') {
       LogUtil.e('预加载解析失败: $url');
       await _disposePreCacheStreamUrl(); // 解析失败时释放
       return;
     }
     _preCachedUrl = parsedUrl; // 设置预缓存地址，不影响 _currentPlayUrl 和 _isHls
     LogUtil.i('预缓存地址: $_preCachedUrl, 当前 _isHls: $_isHls (保持不变)');

     final nextSource = BetterPlayerConfig.createDataSource(
       isHls: _isHlsStream(parsedUrl), // 仅用于预缓存，不影响当前 _isHls
       url: parsedUrl,
     );

     await _playerController!.preCache(nextSource);
     LogUtil.i('预缓存完成: $parsedUrl');
   } catch (e, stackTrace) {
     LogUtil.logError('预加载失败: $url', e, stackTrace);
     _preCachedUrl = null;
     await _disposePreCacheStreamUrl(); // 异常时释放
   }
 }

 void _startTimeoutCheck() {
   if (_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) return;

   _timeoutActive = true;
   Timer(Duration(seconds: defaultTimeoutSeconds), () {
     if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
       _timeoutActive = false;
       return;
     }
     if (_playerController?.videoPlayerController == null) {
       LogUtil.e('超时检查: 播放器控制器无效');
       _handleSourceSwitching();
       _timeoutActive = false;
       return;
     }
     if (isBuffering) {
       LogUtil.e('缓冲超时，切换下一源');
       _handleSourceSwitching();
     }
     _timeoutActive = false;
   });
 }

 void _retryPlayback({bool resetRetryCount = false}) {
   if (_isRetrying || _isSwitchingChannel || _isDisposing) return;

   _cleanupTimers();

   if (resetRetryCount) {
     setState(() {
       _retryCount = 0; // 用户触发时重置重试次数
     });
   }

   if (_retryCount < defaultMaxRetries) {
     _updatePlayerState(
       retrying: true,
       buffering: false,
       toast: S.current.retryplay,
       showPlayIcon: false,
       showPauseIcon: false
     );
     
     _retryCount++;
     LogUtil.i('重试播放: 第 $_retryCount 次');

     _retryTimer = Timer(const Duration(seconds: retryDelaySeconds), () async {
       if (!mounted || _isSwitchingChannel || _isDisposing) {
         LogUtil.i('重试中断: mounted=$mounted, isSwitchingChannel=$_isSwitchingChannel, isDisposing=$_isDisposing');
         setState(() => _isRetrying = false);
         return;
       }
       await _playVideo(isRetry: true); // 标记为重试
       if (mounted) {
         setState(() {
           _isRetrying = false;
         });
       }
     });
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
   if (_isRetrying || _isDisposing) return;

   _cleanupTimers();
   
   final nextUrl = _getNextVideoUrl();
   if (nextUrl == null) {
     LogUtil.i('无更多源可切换');
     _handleNoMoreSources();
     return;
   }

   _updatePlayerState(
     retrying: false,
     buffering: false,
     toast: S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '')
   );
   
   _sourceIndex++;
   _retryCount = 0;
   _preCachedUrl = null;

   LogUtil.i('切换到下一源: $nextUrl');
   _startNewSourceTimer();
 }

 Future<void> _handleNoMoreSources() async {
   _updatePlayerState(
     toast: S.current.playError,
     buffering: false,
     playing: false,
     retrying: false,
     showPlayIcon: false,
     showPauseIcon: false
   );
   
   _sourceIndex = 0;
   _retryCount = 0;
   
   await _cleanupController(_playerController);
   LogUtil.i('播放结束，无更多源');
 }

 void _startNewSourceTimer() {
   _cleanupTimers();
   _retryTimer = Timer(const Duration(seconds: retryDelaySeconds), () async {
     if (!mounted || _isSwitchingChannel) return;
     await _playVideo(isSourceSwitch: true); // 标记为切换源
   });
 }

 /// 清理播放器控制器，确保资源释放
 Future<void> _cleanupController(BetterPlayerController? controller) async {
   if (controller == null) return;

   _isDisposing = true;
   try {
     _cleanupTimers();
     controller.removeEventsListener(_videoListener);

     if (controller.isPlaying() ?? false) {
       await controller.pause();
       await controller.setVolume(0);
     }

     await _disposeStreamUrl();
     await _disposePreCacheStreamUrl(); // 清理预缓存实例
     controller.videoPlayerController?.dispose();
     controller.dispose();

     setState(() {
       _playerController = null;
       _progressEnabled = false;
       _isAudio = false;
       // 不重置 _isHls，保持与 _currentPlayUrl 一致
       _bufferedHistory.clear();
       _preCachedUrl = null;
       _lastBufferedPosition = null;
       _lastBufferedTime = null;
       _isParsing = false;
       _isUserPaused = false; // 重置用户暂停状态
       _showPlayIcon = false; // 重置播放图标状态
       _showPauseIconFromListener = false; // 重置暂停图标状态
     });
     LogUtil.i('播放器清理完成');
   } catch (e, stackTrace) {
     LogUtil.logError('清理播放器失败', e, stackTrace);
   } finally {
     _isDisposing = false;
   }
 }

 // 优化的资源释放方法，增加异常处理
 Future<void> _disposeStreamUrl() async {
   if (_streamUrl != null) {
     try {
       await _streamUrl!.dispose();
     } catch (e, stackTrace) {
       LogUtil.logError('释放StreamUrl实例失败', e, stackTrace);
     } finally {
       _streamUrl = null;
     }
   }
 }

 Future<void> _disposePreCacheStreamUrl() async {
   if (_preCacheStreamUrl != null) {
     try {
       await _preCacheStreamUrl!.dispose();
     } catch (e, stackTrace) {
       LogUtil.logError('释放预缓存StreamUrl实例失败', e, stackTrace);
     } finally {
       _preCacheStreamUrl = null;
     }
   }
 }

 void _cleanupTimers() {
   _retryTimer?.cancel();
   _retryTimer = null;
   _playDurationTimer?.cancel();
   _playDurationTimer = null;
   _timeoutTimer?.cancel(); // 清理超时计时器
   _timeoutTimer = null; // 重置为 null
   _timeoutActive = false;
 }

 Future<void> _reparseAndSwitch() async {
   if (_isRetrying || _isSwitchingChannel || _isDisposing || _isParsing) {
     LogUtil.i('重新解析被阻止: _isRetrying=$_isRetrying, _isSwitchingChannel=$_isSwitchingChannel, _isDisposing=$_isDisposing, _isParsing=$_isParsing');
     return;
   }

   _isParsing = true;
   setState(() => _isRetrying = true);

   try {
     String url = _currentChannel!.urls![_sourceIndex].toString();
     LogUtil.i('重新解析地址: $url');
     await _disposeStreamUrl(); // 先释放旧实例
     _streamUrl = StreamUrl(url); // 保存新实例
     String newParsedUrl = await _streamUrl!.getStreamUrl(); // 使用保存的实例
     if (newParsedUrl == 'ERROR') {
       LogUtil.e('重新解析失败: $url');
       await _disposeStreamUrl(); // 解析失败时释放
       _handleSourceSwitching();
       return;
     }
     if (newParsedUrl == _currentPlayUrl) {
       LogUtil.i('新地址与当前播放地址相同，无需切换');
       await _disposeStreamUrl(); // 无需切换时释放
       return;
     }

     // 检查当前缓冲区状态，若恢复则取消预加载
     final position = _playerController?.videoPlayerController?.value.position ?? Duration.zero;
     final bufferedPosition = _playerController?.videoPlayerController?.value.buffered?.isNotEmpty == true
         ? _playerController!.videoPlayerController!.value.buffered!.last.end
         : position;
     final remainingBuffer = bufferedPosition - position;
     if (remainingBuffer.inSeconds > networkRecoveryBufferSeconds) {
       LogUtil.i('网络恢复，剩余缓冲 > $networkRecoveryBufferSeconds 秒，取消预加载');
       _preCachedUrl = null;
       _isParsing = false;
       setState(() => _isRetrying = false);
       await _disposeStreamUrl(); // 网络恢复时释放
       return;
     }

     _preCachedUrl = newParsedUrl; // 只设置预缓存地址，不更新 _currentPlayUrl
     LogUtil.i('预缓存地址: $_preCachedUrl');

     final newSource = BetterPlayerConfig.createDataSource(
       isHls: _isHlsStream(newParsedUrl), // 使用新地址判断 HLS，不影响当前 _isHls
       url: newParsedUrl,
     );

     if (_playerController != null) {
       await _playerController!.preCache(newSource);
       _progressEnabled = false;
       _playDurationTimer?.cancel();
       _playDurationTimer = null;
     } else {
       LogUtil.i('播放器控制器为空，无法切换');
       _handleSourceSwitching();
     }
   } catch (e, stackTrace) {
     LogUtil.logError('重新解析失败', e, stackTrace);
     await _disposeStreamUrl(); // 异常时释放
     _handleSourceSwitching();
   } finally {
     _isParsing = false;
     if (mounted) setState(() => _isRetrying = false);
     LogUtil.i('重新解析结束');
   }
 }

 // 获取地理信息
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
     
     // 取前两个字符
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

 // 基于地理前缀排序，全部按原始顺序排列
 List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
   if (prefix == null || prefix.isEmpty) {
     LogUtil.i('地理前缀为空，返回原始顺序');
     return items; // 如果没有前缀，返回原始列表
   }

   List<String> matched = []; // 匹配前缀的项
   List<String> unmatched = []; // 未匹配前缀的项
   Map<String, int> originalOrder = {}; // 保存原始顺序的索引

   // 记录原始顺序并分离匹配与未匹配项
   for (int i = 0; i < items.length; i++) {
     String item = items[i];
     originalOrder[item] = i; // 记录原始索引
     if (item.startsWith(prefix)) {
       matched.add(item);
     } else {
       unmatched.add(item);
     }
   }

   // 按原始顺序对匹配项排序
   matched.sort((a, b) => originalOrder[a]!.compareTo(originalOrder[b]!));
   // 按原始顺序对未匹配项排序
   unmatched.sort((a, b) => originalOrder[a]!.compareTo(originalOrder[b]!));

   LogUtil.i('排序结果 - 匹配: $matched, 未匹配: $unmatched');
   return [...matched, ...unmatched];
 }

 // 对 videoMap 进行排序
 void _sortVideoMap(PlaylistModel videoMap, String? userInfo) {
   if (videoMap.playList == null || videoMap.playList!.isEmpty) {
     LogUtil.e('播放列表为空，无需排序');
     return;
   }

   final location = _getLocationInfo(userInfo);
   final String? regionPrefix = location['region'];
   final String? cityPrefix = location['city'];

   // 如果两者均为空则跳过排序
   if ((regionPrefix == null || regionPrefix.isEmpty) && (cityPrefix == null || cityPrefix.isEmpty)) {
     LogUtil.i('地理信息中未找到有效地区或城市前缀，跳过排序');
     return;
   }

   videoMap.playList!.forEach((category, groups) {
     final groupList = groups.keys.toList();
     final sortedGroups = _sortByGeoPrefix(groupList, regionPrefix);
     final newGroups = <String, Map<String, PlayModel>>{};
     
     for (var group in sortedGroups) {
       final channels = groups[group]!;
       final sortedChannels = _sortByGeoPrefix(channels.keys.toList(), cityPrefix);
       final newChannels = <String, PlayModel>{};
       
       for (var channel in sortedChannels) {
         newChannels[channel] = channels[channel]!;
       }
       
       newGroups[group] = newChannels;
     }
     
     videoMap.playList![category] = newGroups;
   });
   
   LogUtil.i('按地理位置排序完成');
 }

 Future<void> _onTapChannel(PlayModel? model) async {
   if (model == null) return;

   try {
     _updatePlayerState(
       buffering: false,
       toast: S.current.loading
     );
     
     _cleanupTimers();
     _currentChannel = model;
     _sourceIndex = 0;
     _isRetrying = false;
     _retryCount = 0;
     _shouldUpdateAspectRatio = true;

     await _queueSwitchChannel(_currentChannel, _sourceIndex);

     if (Config.Analytics) {
       await _sendTrafficAnalytics(context, _currentChannel!.title);
     }
   } catch (e, stackTrace) {
     LogUtil.logError('切换频道失败', e, stackTrace);
     _updatePlayerState(toast: S.current.playError);
     await _cleanupController(_playerController);
   }
 }

 // 允许当前源点击后重试
 Future<void> _changeChannelSources() async {
   List<String>? sources = _currentChannel?.urls;
   if (sources?.isEmpty ?? true) {
     LogUtil.e('未找到有效视频源');
     return;
   }

   final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
   if (selectedIndex != null) {
     setState(() {
       _sourceIndex = selectedIndex;
       _isRetrying = false;
       _retryCount = 0;
     });
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

 // 处理用户暂停的回调
 void _handleUserPaused() {
   setState(() {
     _isUserPaused = true;
   });
 }

 // HLS 重试的回调
 void _handleRetry() {
   _retryPlayback(resetRetryCount: true); // 用户触发重试，重置次数
 }

 @override
 void initState() {
   super.initState();
   _adManager = AdManager(); // 初始化 AdManager
   _adManager.loadAdData(); // 加载广告数据
   if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
   _loadData();
   _extractFavoriteList();
 }

 /// 清理所有资源
 @override
 void dispose() {
   _isDisposing = true;
   _cleanupController(_playerController); // 清理主播放器
   _disposeStreamUrl(); // 清理流地址
   _disposePreCacheStreamUrl(); // 清理预缓存 StreamUrl
   _pendingSwitches.clear(); // 清理切换队列
   _originalUrl = null; // 清理解析前地址
   _playDurationTimer?.cancel(); // 确保定时器被清理
   _playDurationTimer = null;
   _timeoutTimer?.cancel(); // 清理超时计时器
   _timeoutTimer = null; // 重置为 null
   _adManager.dispose(); // 清理广告资源
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
   setState(() {
     _isRetrying = false;
     _cleanupTimers();
     _retryCount = 0;
     _isAudio = false;
   });

   if (widget.m3uData.playList == null || widget.m3uData.playList!.isEmpty) {
     LogUtil.e('播放列表无效');
     setState(() => toastString = S.current.getDefaultError);
     return;
   }

   try {
     _videoMap = widget.m3uData;
     // 添加排序逻辑
     String? userInfo = SpUtil.getString('user_all_info');
     LogUtil.i('原始 user_all_info: $userInfo'); // 添加调试日志以检查实际数据
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

       setState(() {
         _retryCount = 0;
         _timeoutActive = false;
         _queueSwitchChannel(_currentChannel, _sourceIndex); // 使用优化后的队列机制
       });
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
       adManager: _adManager, // 传递 AdManager 给 TvPage
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
             adManager: _adManager, // 传递 AdManager 给 MobileVideoWidget
             showPlayIcon: _showPlayIcon, // 传递播放图标状态
             showPauseIconFromListener: _showPauseIconFromListener, // 传递暂停图标状态
             isHls: _isHls, // 传递 HLS 状态
             onUserPaused: _handleUserPaused, // 用户暂停回调
             onRetry: _handleRetry, // HLS 重试回调
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
                         showPlayIcon: _showPlayIcon, // 传递播放图标状态
                         showPauseIconFromListener: _showPauseIconFromListener, // 传递暂停图标状态
                         isHls: _isHls, // 传递 HLS 状态
                         onUserPaused: _handleUserPaused, // 用户暂停回调
                         onRetry: _handleRetry, // HLS 重试回调
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
