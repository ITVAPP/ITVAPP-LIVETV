import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
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

/// 主页面，负责视频播放和频道管理
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 传入的 M3U 播放列表数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

/// 常量配置类，集中管理重复使用的常量
class _Constants {
  static const int defaultMaxRetries = 1; // 默认最大重试次数
  static const int defaultTimeoutSeconds = 36; // 解析超时秒数
  static const int initialProgressDelaySeconds = 60; // 初始进度监听延迟秒数
  static const int bufferUpdateTimeoutSeconds = 6; // 缓冲区更新超时秒数
  static const int minRemainingBufferSeconds = 8; // 最小剩余缓冲秒数
  static const int bufferHistorySize = 6; // 缓冲历史记录大小
  static const int positionIncreaseThreshold = 5; // 播放位置连续增加次数阈值
  static const int lowBufferThresholdCount = 3; // 低缓冲次数阈值
  static const int networkRecoveryBufferSeconds = 7; // 网络恢复缓冲秒数
  static const int retryDelaySeconds = 2; // 重试延迟秒数
  static const int hlsSwitchThresholdSeconds = 3; // HLS 切换阈值秒数
  static const int nonHlsPreloadThresholdSeconds = 20; // 非 HLS 预加载阈值秒数
  static const int nonHlsSwitchThresholdSeconds = 3; // 非 HLS 切换阈值秒数
  static const double defaultAspectRatio = 1.78; // 默认视频宽高比 (16:9)
  static const int cleanupDelayMilliseconds = 500; // 清理控制器延迟毫秒数
  static const int snackBarDurationSeconds = 4; // 提示显示时长秒数
  static const int bufferingStartSeconds = 15; // 缓冲超时秒数
  static const int listenerThrottleSeconds = 1; // 监听器节流间隔秒数
}

class _LiveHomePageState extends State<LiveHomePage> {
  Queue<Map<String, dynamic>> _bufferedHistory = Queue(); // 缓冲历史记录，使用 Queue 提高效率
  String? _preCachedUrl; // 预缓存的视频 URL
  bool _isParsing = false; // 标记是否正在解析
  Duration? _lastBufferedPosition; // 上次缓冲到的位置
  int? _lastBufferedTime; // 上次缓冲时间戳（毫秒）
  bool _isRetrying = false; // 标记是否正在重试
  Timer? _retryTimer; // 重试操作的计时器
  String toastString = S.current.loading; // 当前显示的提示信息
  PlaylistModel? _videoMap; // 视频播放列表数据
  PlayModel? _currentChannel; // 当前播放的频道
  int _sourceIndex = 0; // 当前播放源的索引
  int _lastProgressTime = 0; // 上次进度更新的时间
  BetterPlayerController? _playerController; // 视频播放控制器
  bool isBuffering = false; // 标记是否正在缓冲
  bool isPlaying = false; // 标记是否正在播放
  double aspectRatio = _Constants.defaultAspectRatio; // 当前视频宽高比
  bool _drawerIsOpen = false; // 标记抽屉是否打开
  int _retryCount = 0; // 当前重试次数
  bool _timeoutActive = false; // 标记超时是否激活
  bool _isDisposing = false; // 标记是否正在释放资源
  bool _isSwitchingChannel = false; // 标记是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 标记是否需要更新宽高比
  StreamUrl? _streamUrl; // 当前视频流地址实例
  StreamUrl? _preCacheStreamUrl; // 预缓存视频流地址实例
  String? _currentPlayUrl; // 当前播放的 URL
  String? _originalUrl; // 解析前的原始 URL
  bool _progressEnabled = false; // 标记进度监听是否启用
  bool _isHls = false; // 标记是否为 HLS 流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  }; // 收藏列表，存储用户喜欢的频道
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键，用于触发更新
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析实例
  bool _isAudio = false; // 标记是否为音频流
  Timer? _playDurationTimer; // 播放持续时间计时器
  Timer? _timeoutTimer; // 缓冲超时计时器
  late AdManager _adManager; // 广告管理实例
  bool _isUserPaused = false; // 标记是否为用户主动暂停
  bool _showPlayIcon = false; // 标记是否显示播放图标
  bool _showPauseIconFromListener = false; // 标记是否显示非用户触发的暂停图标
  DateTime? _lastListenerUpdateTime; // 上次监听器处理时间

  Map<String, dynamic>? _pendingSwitch; // 切换请求队列，存储待处理的频道和源索引

  /// 检查是否为音频流，根据 URL 后缀判断
  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    final lowercaseUrl = url.toLowerCase();
    return !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
  }

  /// 检查是否为 HLS 流，主要基于 URL 是否含 .m3u8
  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    if (lowercaseUrl.contains('.m3u8')) return true;
    const formats = [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'
    ];
    return !formats.any(lowercaseUrl.contains);
  }

  /// 更新当前播放 URL 并同步 HLS 状态
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  /// 切换到预缓存地址，处理播放失败或结束时的无缝衔接
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
    _updatePlayUrl(_preCachedUrl!);
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

  /// 播放视频，包含初始化和切换逻辑，支持重试和源切换
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null) return; // 检查空值，避免崩溃
    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');

    _cleanupTimers();
    setState(() {
      toastString = '${_currentChannel!.title} - $sourceName  ${S.current.loading}';
      isPlaying = false;
      isBuffering = false;
      _progressEnabled = false;
      _isSwitchingChannel = true;
      _isUserPaused = false;
      _showPlayIcon = false;
      _showPauseIconFromListener = false;
    });

    _timeoutTimer?.cancel();
    _timeoutActive = true;
    _timeoutTimer = Timer(Duration(seconds: _Constants.defaultTimeoutSeconds), () {
      if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
        _timeoutActive = false;
        return;
      }
      if (_playerController?.isPlaying() != true) {
        LogUtil.e('播放流程超时（解析或缓冲失败），切换下一源');
        _handleSourceSwitching();
        _timeoutActive = false;
      }
    });

    try {
      if (!isRetry && !isSourceSwitch && _adManager.shouldPlayVideoAd()) {
        await _adManager.playVideoAd();
        LogUtil.i('视频广告播放完成，准备播放频道');
        _adManager.reset();
      }

      if (_playerController != null) {
        await _playerController!.pause();
        await _cleanupController(_playerController);
      }

      await Future.delayed(const Duration(milliseconds: _Constants.cleanupDelayMilliseconds));
      if (!mounted) {
        LogUtil.i('组件已卸载，停止播放流程');
        return;
      }

      String url = _currentChannel!.urls![_sourceIndex].toString();
      _originalUrl = url;
      _streamUrl = StreamUrl(url);
      String parsedUrl = await _streamUrl!.getStreamUrl();
      _updatePlayUrl(parsedUrl);

      if (parsedUrl == 'ERROR') {
        LogUtil.e('地址解析失败: $url');
        setState(() {
          toastString = S.current.vpnplayError;
          _isSwitchingChannel = false;
        });
        await _disposeStreamUrl();
        return;
      }

      bool isDirectAudio = _checkIsAudioStream(parsedUrl);
      setState(() => _isAudio = isDirectAudio);

      LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $isDirectAudio, HLS: $_isHls');

      final dataSource = BetterPlayerConfig.createDataSource(url: parsedUrl, isHls: _isHls);
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(eventListener: _videoListener, isHls: _isHls);

      BetterPlayerController? tempController;
      try {
        tempController = BetterPlayerController(betterPlayerConfiguration);
        await tempController.setupDataSource(dataSource);
        LogUtil.i('播放器数据源设置完成: $parsedUrl');
        setState(() => _playerController = tempController);
        await _playerController?.play();
        LogUtil.i('开始播放: $parsedUrl');
        _timeoutActive = false;
        _timeoutTimer?.cancel();
      } catch (e) {
        tempController?.dispose();
        throw e;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrl();
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingChannel = false;
          if (_playerController == null) {
            isBuffering = false;
            isPlaying = false;
          }
        });
        if (_pendingSwitch != null) {
          final nextRequest = _pendingSwitch!;
          _currentChannel = nextRequest['channel'] as PlayModel?;
          _sourceIndex = nextRequest['sourceIndex'] as int;
          _pendingSwitch = null; // 清理切换请求，避免重复处理
          LogUtil.i('处理最新切换请求: ${_currentChannel!.title}, 源索引: $_sourceIndex');
          Future.microtask(() => _playVideo());
        }
      }
    }
  }

  /// 将频道切换请求加入队列，处理并发切换
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) return;
    if (_isSwitchingChannel) {
      _pendingSwitch = {'channel': channel, 'sourceIndex': sourceIndex};
      LogUtil.i('更新最新切换请求: ${channel.title}, 源索引: $sourceIndex');
    } else {
      _currentChannel = channel;
      _sourceIndex = sourceIndex;
      _originalUrl = _currentChannel!.urls![_sourceIndex];
      LogUtil.i('切换频道/源 - 解析前地址: $_originalUrl');
      await _playVideo();
    }
  }

  /// 视频事件监听器，处理播放过程中的各种状态变化
  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing) return;

    final now = DateTime.now();
    if (_lastListenerUpdateTime != null && now.difference(_lastListenerUpdateTime!).inSeconds < _Constants.listenerThrottleSeconds) {
      return;
    }
    _lastListenerUpdateTime = now;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (_shouldUpdateAspectRatio) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? _Constants.defaultAspectRatio;
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
        if (!_isRetrying && !_isSwitchingChannel) { // 避免重复触发重试
          if (_preCachedUrl != null) await _switchToPreCachedUrl('异常触发');
          else _retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        setState(() {
          isBuffering = true;
          toastString = S.current.loading;
        });
        if (isPlaying) {
          _timeoutTimer?.cancel();
          _timeoutTimer = Timer(const Duration(seconds: _Constants.bufferingStartSeconds), () {
            if (!mounted || !isBuffering || _isRetrying || _isSwitchingChannel || _isDisposing || _isParsing || _pendingSwitch != null) return;
            if (_playerController?.isPlaying() != true) {
              LogUtil.e('播放中缓冲超过10秒，提出重试');
              _retryPlayback(resetRetryCount: true);
            }
          });
        }
        break;

      case BetterPlayerEventType.bufferingUpdate:
        if (_progressEnabled && isPlaying) {
          final bufferedData = event.parameters?["buffered"];
          if (bufferedData != null) {
            if (bufferedData is List<dynamic> && bufferedData.isNotEmpty) {
              final lastBuffer = bufferedData.last;
              try {
                _lastBufferedPosition = lastBuffer.end as Duration;
                _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
              } catch (e) {
                LogUtil.i('无法解析缓冲对象: $lastBuffer, 错误: $e');
                _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
              }
            } else if (bufferedData is Duration) {
              _lastBufferedPosition = bufferedData;
              _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
            } else {
              _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
            }
          } else {
            _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
          }
        }
        break;

      case BetterPlayerEventType.bufferingEnd:
        setState(() {
          isBuffering = false;
          toastString = 'HIDE_CONTAINER';
          if (!_isUserPaused) _showPauseIconFromListener = false;
        });
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        _cleanupTimers();
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          setState(() {
            isPlaying = true;
            if (!isBuffering) toastString = 'HIDE_CONTAINER';
            _progressEnabled = false;
            _showPlayIcon = false;
            _showPauseIconFromListener = false;
            _isUserPaused = false;
          });
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          if (_playDurationTimer == null || !_playDurationTimer!.isActive) _startPlayDurationTimer();
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          setState(() {
            isPlaying = false;
            toastString = S.current.playpause;
            if (_isUserPaused) _showPlayIcon = true;
            else _showPauseIconFromListener = true;
          });
          LogUtil.i('播放暂停，用户触发: $_isUserPaused');
        }
        break;

      case BetterPlayerEventType.progress:
        if (_progressEnabled && isPlaying) {
          final position = event.parameters?["progress"] as Duration?;
          final duration = event.parameters?["duration"] as Duration?;
          if (position != null && duration != null && _lastBufferedPosition != null && _lastBufferedTime != null) {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final timeSinceLastUpdate = (timestamp - _lastBufferedTime!) / 1000.0;
            final remainingBuffer = _lastBufferedPosition! - position;

            _bufferedHistory.add({
              'buffered': _lastBufferedPosition!,
              'position': position,
              'timestamp': timestamp,
              'remainingBuffer': remainingBuffer,
            });
            if (_bufferedHistory.length > _Constants.bufferHistorySize) _bufferedHistory.removeFirst(); // 高效移除最早记录

            if (_isHls && !_isParsing) {
              final remainingTime = duration - position;
              if (_preCachedUrl != null && remainingTime.inSeconds <= _Constants.hlsSwitchThresholdSeconds) {
                await _switchToPreCachedUrl('HLS 剩余时间少于 ${_Constants.hlsSwitchThresholdSeconds} 秒');
              } else if (_bufferedHistory.length >= _Constants.bufferHistorySize) {
                int positionIncreaseCount = 0;
                int remainingBufferLowCount = 0;
                for (int i = _bufferedHistory.length - _Constants.positionIncreaseThreshold; i < _bufferedHistory.length; i++) {
                  final prev = _bufferedHistory.elementAt(i - 1);
                  final curr = _bufferedHistory.elementAt(i);
                  if (curr['position'] > prev['position']) positionIncreaseCount++;
                  if ((curr['remainingBuffer'] as Duration).inSeconds < _Constants.minRemainingBufferSeconds) remainingBufferLowCount++;
                }
                if (positionIncreaseCount == _Constants.positionIncreaseThreshold &&
                    remainingBufferLowCount >= _Constants.lowBufferThresholdCount &&
                    timeSinceLastUpdate > _Constants.bufferUpdateTimeoutSeconds) {
                  LogUtil.i('触发重新解析: 位置增加 ${_Constants.positionIncreaseThreshold} 次，缓冲不足');
                  _reparseAndSwitch();
                }
              }
            } else {
              final remainingTime = duration - position;
              if (remainingTime.inSeconds <= _Constants.nonHlsPreloadThresholdSeconds) {
                final nextUrl = _getNextVideoUrl();
                if (nextUrl != null && nextUrl != _preCachedUrl) _preloadNextVideo(nextUrl);
              }
              if (remainingTime.inSeconds <= _Constants.nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
                await _switchToPreCachedUrl('非 HLS 剩余时间少于 ${_Constants.nonHlsSwitchThresholdSeconds} 秒');
              }
            }
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!_isHls && _preCachedUrl != null) await _switchToPreCachedUrl('非 HLS 播放结束');
        else if (_isHls) _retryPlayback();
        else _handleNoMoreSources();
        break;

      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.changedPlayerVisibility) {
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  /// 启动播放持续时间计时器，延迟启用进度监听
  void _startPlayDurationTimer() {
    _playDurationTimer?.cancel();
    _playDurationTimer = Timer(const Duration(seconds: _Constants.initialProgressDelaySeconds), () {
      if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
        bool shouldEnableProgress = _isHls && _originalUrl?.toLowerCase().contains('timelimit') == true || !_isHls && _getNextVideoUrl() != null;
        if (shouldEnableProgress) {
          LogUtil.i('播放 ${_Constants.initialProgressDelaySeconds} 秒，启用 progress 监听');
          _progressEnabled = true;
        }
        _retryCount = 0;
        _playDurationTimer = null;
      }
    });
  }

  /// 预加载下一个视频源，提升切换流畅性
  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel || _playerController == null) return;
    try {
      LogUtil.i('开始预加载: $url');
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposeStreamUrlInstance(_preCacheStreamUrl);
        return;
      }
      _preCachedUrl = parsedUrl;
      final nextSource = BetterPlayerConfig.createDataSource(isHls: _isHlsStream(parsedUrl), url: parsedUrl);
      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
    }
  }

  /// 启动超时检查，处理长时间未响应的播放
  void _startTimeoutCheck() {
    if (_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) return;
    _timeoutActive = true;
    Timer(Duration(seconds: _Constants.defaultTimeoutSeconds), () {
      if (!mounted || !_timeoutActive || _playerController?.videoPlayerController == null) {
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

  /// 重试播放逻辑，管理重试次数并重置状态
  void _retryPlayback({bool resetRetryCount = false}) {
    if (_isRetrying || _isSwitchingChannel || _isDisposing) return;
    _cleanupTimers();
    if (resetRetryCount) setState(() => _retryCount = 0);
    if (_retryCount < _Constants.defaultMaxRetries) {
      setState(() {
        _isRetrying = true;
        _retryCount++;
        isBuffering = false;
        toastString = S.current.retryplay;
        _showPlayIcon = false;
        _showPauseIconFromListener = false;
      });
      LogUtil.i('重试播放: 第 $_retryCount 次');
      _retryTimer = Timer(const Duration(seconds: _Constants.retryDelaySeconds), () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) {
          setState(() => _isRetrying = false);
          return;
        }
        await _playVideo(isRetry: true);
        if (mounted) setState(() => _isRetrying = false);
      });
    } else {
      LogUtil.i('重试次数达上限，切换下一源');
      _handleSourceSwitching();
    }
  }

  /// 获取下一个视频源 URL，用于预加载或切换
  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null || _sourceIndex + 1 >= _currentChannel!.urls!.length) return null;
    return _currentChannel!.urls![_sourceIndex + 1];
  }

  /// 处理源切换，更新索引并触发新源播放
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;
    _cleanupTimers();
    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      _handleNoMoreSources();
      return;
    }
    setState(() {
      _sourceIndex++;
      _isRetrying = false;
      _retryCount = 0;
      isBuffering = false;
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
      _preCachedUrl = null;
    });
    LogUtil.i('切换到下一源: $nextUrl');
    _startNewSourceTimer();
  }

  /// 处理无更多源的情况，清理状态并提示用户
  Future<void> _handleNoMoreSources() async {
    setState(() {
      toastString = S.current.playError;
      _sourceIndex = 0;
      isBuffering = false;
      isPlaying = false;
      _isRetrying = false;
      _retryCount = 0;
      _showPlayIcon = false;
      _showPauseIconFromListener = false;
    });
    await _cleanupController(_playerController);
    LogUtil.i('播放结束，无更多源');
  }

  /// 启动新源加载计时器，延迟执行播放
  void _startNewSourceTimer() {
    _cleanupTimers();
    _retryTimer = Timer(const Duration(seconds: _Constants.retryDelaySeconds), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  /// 清理播放器控制器，确保资源正确释放
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
      await _disposeStreamUrlInstance(_streamUrl);
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      controller.videoPlayerController?.dispose();
      controller.dispose();
      setState(() {
        _playerController = null; // 置空引用，避免内存泄漏
        _progressEnabled = false;
        _isAudio = false;
        _bufferedHistory.clear();
        _preCachedUrl = null;
        _lastBufferedPosition = null;
        _lastBufferedTime = null;
        _isParsing = false;
        _isUserPaused = false;
        _showPlayIcon = false;
        _showPauseIconFromListener = false;
      });
      LogUtil.i('播放器清理完成');
    } catch (e, stackTrace) {
      LogUtil.logError('清理播放器失败', e, stackTrace);
    } finally {
      _isDisposing = false;
    }
  }

  /// 释放流地址资源的通用方法，保持实例同步
  Future<void> _disposeStreamUrlInstance(StreamUrl? streamUrl) async {
    if (streamUrl != null) {
      await streamUrl.dispose();
      if (streamUrl == _streamUrl) _streamUrl = null; // 更新当前流实例
      if (streamUrl == _preCacheStreamUrl) _preCacheStreamUrl = null; // 更新预缓存流实例
    }
  }

  /// 清理所有计时器，确保资源释放完整
  void _cleanupTimers() {
    if (_retryTimer != null) {
      _retryTimer!.cancel();
      _retryTimer = null;
    }
    if (_playDurationTimer != null) {
      _playDurationTimer!.cancel();
      _playDurationTimer = null;
    }
    if (_timeoutTimer != null) {
      _timeoutTimer!.cancel();
      _timeoutTimer = null;
    }
    _timeoutActive = false;
  }

  /// 重新解析并切换视频源，优化网络恢复逻辑
  Future<void> _reparseAndSwitch() async {
    if (_isRetrying || _isSwitchingChannel || _isDisposing || _isParsing) return;
    _isParsing = true;
    setState(() => _isRetrying = true);
    try {
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      await _disposeStreamUrlInstance(_streamUrl);
      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeStreamUrlInstance(_streamUrl);
        _handleSourceSwitching();
        return;
      }
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeStreamUrlInstance(_streamUrl);
        return;
      }
      final position = _playerController?.videoPlayerController?.value.position ?? Duration.zero;
      final bufferedPosition = _playerController?.videoPlayerController?.value.buffered?.isNotEmpty == true
          ? _playerController!.videoPlayerController!.value.buffered!.last.end
          : position;
      final remainingBuffer = bufferedPosition - position;
      if (remainingBuffer.inSeconds > _Constants.networkRecoveryBufferSeconds) {
        LogUtil.i('网络恢复，剩余缓冲 > ${_Constants.networkRecoveryBufferSeconds} 秒，取消预加载');
        _preCachedUrl = null;
        _isParsing = false;
        setState(() => _isRetrying = false);
        await _disposeStreamUrlInstance(_streamUrl);
        return;
      }
      _preCachedUrl = newParsedUrl;
      final newSource = BetterPlayerConfig.createDataSource(isHls: _isHlsStream(newParsedUrl), url: newParsedUrl);
      if (_playerController != null) {
        await _playerController!.preCache(newSource);
        _progressEnabled = false;
        _playDurationTimer?.cancel();
        _playDurationTimer = null;
      } else {
        _handleSourceSwitching();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      await _disposeStreamUrlInstance(_streamUrl);
      _handleSourceSwitching();
    } finally {
      _isParsing = false;
      if (mounted) setState(() => _isRetrying = false);
      LogUtil.i('重新解析结束');
    }
  }

  /// 获取用户地理信息，从 JSON 数据中提取地区和城市
  Map<String, String?> _getLocationInfo(String? userInfo) {
    if (userInfo == null || userInfo.isEmpty) return {'region': null, 'city': null};
    try {
      final userData = jsonDecode(userInfo);
      final locationData = userData['info']?['location'];
      final region = locationData?['region'] as String?;
      final city = locationData?['city'] as String?;
      final regionPrefix = _extractPrefix(region); // 提取地区前缀
      final cityPrefix = _extractPrefix(city); // 提取城市前缀
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e) {
      LogUtil.e('解析地理信息失败: $e');
      return {'region': null, 'city': null};
    }
  }

  /// 提取字符串前缀的工具函数，取前两个字符
  String? _extractPrefix(String? value) {
    return value != null && value.length >= 2 ? value.substring(0, 2) : value;
  }

  /// 根据地理前缀排序列表，优先匹配前缀项
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix == null || prefix.isEmpty) return items;
    List<String> matched = [];
    List<String> unmatched = [];
    Map<String, int> originalOrder = {};
    for (int i = 0; i < items.length; i++) {
      String item = items[i];
      originalOrder[item] = i;
      if (item.startsWith(prefix)) matched.add(item);
      else unmatched.add(item);
    }
    matched.sort((a, b) => originalOrder[a]!.compareTo(originalOrder[b]!));
    unmatched.sort((a, b) => originalOrder[a]!.compareTo(originalOrder[b]!));
    return [...matched, ...unmatched];
  }

  /// 对播放列表按地理位置排序，优化用户体验
  void _sortVideoMap(PlaylistModel videoMap, String? userInfo) {
    if (videoMap.playList == null || videoMap.playList!.isEmpty) return;
    final location = _getLocationInfo(userInfo);
    if ((location['region'] == null || location['region']!.isEmpty) && (location['city'] == null || location['city']!.isEmpty)) return;
    videoMap.playList!.forEach((category, groups) {
      final groupList = groups.keys.toList();
      final sortedGroups = _sortByGeoPrefix(groupList, location['region']);
      final newGroups = <String, Map<String, PlayModel>>{};
      for (var group in sortedGroups) {
        final channels = groups[group]!;
        final sortedChannels = _sortByGeoPrefix(channels.keys.toList(), location['city']);
        final newChannels = <String, PlayModel>{};
        for (var channel in sortedChannels) newChannels[channel] = channels[channel]!;
        newGroups[group] = newChannels;
      }
      videoMap.playList![category] = newGroups;
    });
    LogUtil.i('按地理位置排序完成');
  }

  /// 处理频道点击事件，触发播放并更新状态
  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;
    setState(() {
      isBuffering = false;
      toastString = S.current.loading;
      _cleanupTimers();
      _currentChannel = model;
      _sourceIndex = 0;
      _isRetrying = false;
      _retryCount = 0;
      _shouldUpdateAspectRatio = true;
    });
    await _queueSwitchChannel(_currentChannel, _sourceIndex);
    if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
  }

  /// 切换频道源，弹出选择对话框并更新播放
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) return;
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

  /// 处理返回键逻辑，支持抽屉关闭和退出确认
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

  /// 处理用户主动暂停，更新状态
  void _handleUserPaused() => setState(() => _isUserPaused = true);

  /// 处理 HLS 重试，重置计数并重新播放
  void _handleRetry() => _retryPlayback(resetRetryCount: true);

  @override
  void initState() {
    super.initState();
    _adManager = AdManager(); // 初始化广告管理
    _adManager.loadAdData(); // 加载广告数据
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden); // 非移动端隐藏标题栏
    _loadData(); // 加载初始数据
    _extractFavoriteList(); // 提取收藏列表
  }

  @override
  void dispose() {
    _isDisposing = true;
    _cleanupController(_playerController); // 清理播放器资源
    _disposeStreamUrlInstance(_streamUrl); // 释放当前流资源
    _disposeStreamUrlInstance(_preCacheStreamUrl); // 释放预缓存流资源
    _pendingSwitch = null; // 清理切换请求
    _originalUrl = null; // 清理原始 URL
    _playDurationTimer?.cancel(); // 取消播放计时器
    _playDurationTimer = null;
    _timeoutTimer?.cancel(); // 取消超时计时器
    _timeoutTimer = null;
    _lastListenerUpdateTime = null; // 清理监听时间
    _adManager.dispose(); // 释放广告管理资源
    super.dispose();
  }

  /// 发送流量统计数据，记录页面访问和频道信息
  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName == null || channelName.isEmpty) return;
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

  /// 加载初始数据，初始化播放列表和状态
  Future<void> _loadData() async {
    setState(() {
      _isRetrying = false;
      _cleanupTimers();
      _retryCount = 0;
      _isAudio = false;
    });
    if (widget.m3uData.playList == null || widget.m3uData.playList!.isEmpty) {
      setState(() => toastString = S.current.getDefaultError);
      return;
    }
    try {
      _videoMap = widget.m3uData;
      String? userInfo = SpUtil.getString('user_all_info');
      _sortVideoMap(_videoMap!, userInfo); // 根据地理位置排序播放列表
      _sourceIndex = 0;
      await _handlePlaylist(); // 处理播放列表
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表失败', e, stackTrace);
      setState(() => toastString = S.current.parseError);
    }
  }

  /// 处理播放列表，初始化首个有效频道
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);
      if (_currentChannel != null) {
        if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
        setState(() => _queueSwitchChannel(_currentChannel, _sourceIndex));
      } else {
        setState(() => toastString = 'UNKNOWN');
      }
    } else {
      setState(() {
        _currentChannel = null;
        toastString = 'UNKNOWN';
        _isRetrying = false;
      });
    }
  }

  /// 从播放列表中获取首个有效频道
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

  /// 提取收藏列表，从播放列表中分离收藏数据
  void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
    }
  }

  String getGroupName(String channelId) => _currentChannel?.group ?? ''; // 获取当前频道组名
  String getChannelName(String channelId) => _currentChannel?.title ?? ''; // 获取当前频道名称
  String _getSourceDisplayName(String url, int index) => url.contains('\$') ? url.split('\$')[1].trim() : S.current.lineIndex(index + 1); // 获取源显示名称
  List<String> getPlayUrls(String channelId) => _currentChannel?.urls ?? []; // 获取当前频道播放 URL 列表
  bool isChannelFavorite(String channelId) => favoriteList[Config.myFavoriteKey]?[getGroupName(channelId)]?.containsKey(getChannelName(channelId)) ?? false; // 判断频道是否已收藏

  /// 切换收藏状态，添加或移除频道到收藏列表
  void toggleFavorite(String channelId) async {
    bool isFavoriteChanged = false;
    String actualChannelId = _currentChannel?.id ?? channelId;
    String groupName = getGroupName(actualChannelId);
    String channelName = getChannelName(actualChannelId);

    if (groupName.isEmpty || channelName.isEmpty) {
      CustomSnackBar.showSnackBar(context, S.current.channelnofavorite, duration: Duration(seconds: _Constants.snackBarDurationSeconds));
      return;
    }

    if (isChannelFavorite(actualChannelId)) {
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) favoriteList[Config.myFavoriteKey]!.remove(groupName);
      CustomSnackBar.showSnackBar(context, S.current.removefavorite, duration: Duration(seconds: _Constants.snackBarDurationSeconds));
      isFavoriteChanged = true;
    } else {
      if (favoriteList[Config.myFavoriteKey]![groupName] == null) favoriteList[Config.myFavoriteKey]![groupName] = {};
      PlayModel newFavorite = PlayModel(
        id: actualChannelId,
        group: groupName,
        logo: _currentChannel?.logo,
        title: channelName,
        urls: getPlayUrls(actualChannelId),
      );
      favoriteList[Config.myFavoriteKey]![groupName]![channelName] = newFavorite;
      CustomSnackBar.showSnackBar(context, S.current.newfavorite, duration: Duration(seconds: _Constants.snackBarDurationSeconds));
      isFavoriteChanged = true;
    }

    if (isFavoriteChanged) {
      try {
        await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
        _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
        if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: _Constants.snackBarDurationSeconds));
        LogUtil.logError('保存收藏失败', error);
      }
    }
  }

  /// 重新解析播放列表，恢复初始状态并重新加载
  Future<void> _parseData() async {
    try {
      if (_videoMap == null || _videoMap!.playList == null || _videoMap!.playList!.isEmpty) {
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
    bool isTV = context.watch<ThemeProvider>().isTV; // 判断是否为 TV 模式

    if (isTV) {
      return TvPage( // TV 模式下渲染专用页面
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
      child: OrientationLayoutBuilder( // 根据屏幕方向渲染不同布局
        portrait: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // 设置竖屏 UI 模式
          return WillPopScope(
            onWillPop: () => _handleBackPress(context), // 处理返回键逻辑
            child: MobileVideoWidget( // 竖屏视频播放组件
              toastString: toastString,
              controller: _playerController,
              changeChannelSources: _changeChannelSources,
              isLandscape: false,
              isBuffering: isBuffering,
              isPlaying: isPlaying,
              aspectRatio: aspectRatio,
              onChangeSubSource: _parseData,
              drawChild: ChannelDrawerPage( // 频道抽屉组件
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
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); // 设置横屏沉浸式模式
          return WillPopScope(
            onWillPop: () => _handleBackPress(context), // 处理返回键逻辑
            child: Stack(
              children: [
                Scaffold(
                  body: toastString == 'UNKNOWN'
                      ? EmptyPage(onRefresh: _loadData) // 显示空页面并支持刷新
                      : TableVideoWidget( // 横屏视频播放组件
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
                  offstage: !_drawerIsOpen, // 控制抽屉显示状态
                  child: GestureDetector(
                    onTap: () => setState(() => _drawerIsOpen = false), // 点击关闭抽屉
                    child: ChannelDrawerPage( // 横屏频道抽屉组件
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
