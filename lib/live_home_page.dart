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

/// 主页面
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData;
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  static const int defaultMaxRetries = 1;
  static const int defaultTimeoutSeconds = 36;
  static const int initialProgressDelaySeconds = 60;
  static const int bufferUpdateTimeoutSeconds = 6;
  static const int minRemainingBufferSeconds = 8;
  static const int bufferHistorySize = 6;
  static const int positionIncreaseThreshold = 5;
  static const int lowBufferThresholdCount = 3;
  static const int networkRecoveryBufferSeconds = 7;
  static const int retryDelaySeconds = 2;
  static const int hlsSwitchThresholdSeconds = 3;
  static const int nonHlsPreloadThresholdSeconds = 20;
  static const int nonHlsSwitchThresholdSeconds = 3;
  static const double defaultAspectRatio = 1.78;
  static const int cleanupDelayMilliseconds = 500;
  static const int snackBarDurationSeconds = 4;
  static const int bufferingStartSeconds = 15;

  Map<int, Map<String, dynamic>> _bufferedHistory = {};
  String? _preCachedUrl;
  bool _isParsing = false;
  Duration? _lastBufferedPosition;
  int? _lastBufferedTime;
  bool _isRetrying = false;
  
  final _timerManager = TimerManager();
  
  String toastString = S.current.loading;
  PlaylistModel? _videoMap;
  PlayModel? _currentChannel;
  int _sourceIndex = 0;
  int _lastProgressTime = 0;
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
  bool _isHlsCached = false;
  bool _isAudioCached = false;
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

  final List<Map<String, dynamic>> _pendingSwitchQueue = [];

  Map<String, bool> _checkUrlType(String? url) {
    if (url == null || url.isEmpty) return {'isAudio': false, 'isHls': false};
    final lowercaseUrl = url.toLowerCase();
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    bool isAudio = !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
    bool isHls = lowercaseUrl.contains('.m3u8') || !([...videoFormats, ...audioFormats].any(lowercaseUrl.contains));
    return {'isAudio': isAudio, 'isHls': isHls};
  }

  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    // 修改 1: 提前检查缓存状态，避免重复调用 _checkUrlType
    if (!_isHlsCached || !_isAudioCached) {
      final urlType = _checkUrlType(_currentPlayUrl);
      _isHls = urlType['isHls']!;
      _isAudio = urlType['isAudio']!;
      _isHlsCached = true;
      _isAudioCached = true;
    }
  }

  Future<void> _switchToPreCachedUrl(String logDescription) async {
    if (_preCachedUrl == null) {
      LogUtil.i('$logDescription: 预缓存地址为空，无法切换');
      return;
    }

    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址与当前地址相同，跳过切换，尝试重新解析');
      _preCachedUrl = null;
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
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
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
    }
  }

  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null || _currentChannel!.urls == null || _currentChannel!.urls!.isEmpty) {
      LogUtil.e('当前频道无效或无可用源');
      if (mounted) setState(() => toastString = S.current.playError);
      return;
    }

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');

    _adManager.reset();
    _updateStateOnPlayStart(sourceName);
    _startTimeoutTimer();

    try {
      Future<void>? adFuture;
      if (!isRetry && !isSourceSwitch && _adManager.shouldPlayVideoAd()) {
        adFuture = _adManager.playVideoAd().then((_) {
          LogUtil.i('视频广告播放完成，准备播放频道');
          _adManager.reset();
        });
      }

      BetterPlayerController? tempController;
      if (_playerController != null) {
        await _playerController!.pause();
        await _cleanupController(_playerController);
      }

      await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
      if (!mounted) {
        LogUtil.i('组件已卸载，停止播放流程');
        return;
      }

      String url = _currentChannel!.urls![_sourceIndex].toString();
      _originalUrl = url;
      _streamUrl = StreamUrl(url);
      
      // 修改 3: 并行执行广告加载和流地址解析
      final parseFuture = _streamUrl!.getStreamUrl();
      if (adFuture != null) {
        await Future.wait([parseFuture, adFuture]); // 并行等待
      } else {
        await parseFuture;
      }
      final parsedUrl = await parseFuture;
      _isHlsCached = false;
      _isAudioCached = false;
      _updatePlayUrl(parsedUrl);

      if (parsedUrl == 'ERROR') {
        LogUtil.e('地址解析失败: $url');
        if (mounted) {
          setState(() {
            toastString = S.current.vpnplayError;
            _isSwitchingChannel = false;
          });
        }
        await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
        return;
      }

      if (mounted) setState(() => _isAudio = _isAudio);

      LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $_isAudio, HLS: $_isHls');

      final dataSource = BetterPlayerConfig.createDataSource(
        url: parsedUrl,
        isHls: _isHls,
      );
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener,
        isHls: _isHls,
      );

      try {
        tempController = BetterPlayerController(betterPlayerConfiguration);
        await tempController.setupDataSource(dataSource);
        LogUtil.i('播放器数据源设置完成: $parsedUrl');
        if (mounted) {
          setState(() {
            _playerController = tempController;
          });
        }
        await _playerController?.play();
        LogUtil.i('开始播放: $parsedUrl');
        _timeoutActive = false;
      } catch (e) {
        tempController?.dispose();
        throw e;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
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
        _processPendingSwitchQueue();
      }
    }
  }

  void _updateStateOnPlayStart(String sourceName) {
    if (!mounted) return;
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
  }

  void _startTimeoutTimer() {
    _timeoutActive = true;
    _timerManager.cancel('timeout');
    _timerManager.schedule('timeout', Duration(seconds: defaultTimeoutSeconds), () {
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
  }

  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) return;

    if (_isSwitchingChannel) {
      _pendingSwitchQueue.add({'channel': channel, 'sourceIndex': sourceIndex});
      LogUtil.i('加入切换队列: ${channel.title}, 源索引: $sourceIndex, 队列长度: ${_pendingSwitchQueue.length}');
    } else {
      _currentChannel = channel;
      _sourceIndex = sourceIndex;
      _originalUrl = _currentChannel!.urls![_sourceIndex];
      LogUtil.i('切换频道/源 - 解析前地址: $_originalUrl');
      await _playVideo();
    }
  }

  void _processPendingSwitchQueue() {
    if (_pendingSwitchQueue.isNotEmpty) {
      final nextRequest = _pendingSwitchQueue.last;
      _pendingSwitchQueue.clear(); // 修改 4: 确保队列在处理后清空
      _currentChannel = nextRequest['channel'] as PlayModel?;
      _sourceIndex = nextRequest['sourceIndex'] as int;
      LogUtil.i('处理最新切换请求: ${_currentChannel!.title}, 源索引: $_sourceIndex');
      Future.microtask(() => _playVideo());
    }
  }

  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (_shouldUpdateAspectRatio) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? defaultAspectRatio;
          if (aspectRatio != newAspectRatio) {
            if (mounted) {
              setState(() {
                aspectRatio = newAspectRatio;
                _shouldUpdateAspectRatio = false;
              });
            }
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
        if (mounted) {
          setState(() {
            isBuffering = true;
            toastString = S.current.loading;
          });
        }

        if (isPlaying) {
          _timerManager.cancel('buffering');
          _timerManager.schedule('buffering', const Duration(seconds: bufferingStartSeconds), () {
            if (!mounted || !isBuffering || _isRetrying || _isSwitchingChannel || _isDisposing || _isParsing || _pendingSwitchQueue.isNotEmpty) {
              LogUtil.i('缓冲超时检查被阻止: mounted=$mounted, isBuffering=$isBuffering, '
                  'isRetrying=$_isRetrying, isSwitchingChannel=$_isSwitchingChannel, '
                  'isDisposing=$_isDisposing, isParsing=$_isParsing, pendingSwitchQueue=${_pendingSwitchQueue.length}');
              return;
            }

            if (_playerController?.isPlaying() != true) {
              LogUtil.e('播放中缓冲超过10秒，触发重试');
              _retryPlayback(resetRetryCount: true);
            }
          });
        } else {
          LogUtil.i('初始缓冲，不启用10秒超时');
        }
        break;

      case BetterPlayerEventType.bufferingUpdate:
        if (_progressEnabled && isPlaying) {
          final bufferedData = event.parameters?["buffered"];
          if (bufferedData != null) {
            if (bufferedData is List<dynamic>) {
              if (bufferedData.isNotEmpty) {
                final lastBuffer = bufferedData.last;
                try {
                  _lastBufferedPosition = lastBuffer.end as Duration;
                  _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
                  _updateBufferedHistory({
                    'buffered': _lastBufferedPosition!,
                    'position': _playerController!.videoPlayerController!.value.position,
                    'timestamp': _lastBufferedTime!,
                    'remainingBuffer': _lastBufferedPosition! - _playerController!.videoPlayerController!.value.position,
                  });
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
              _updateBufferedHistory({
                'buffered': _lastBufferedPosition!,
                'position': _playerController!.videoPlayerController!.value.position,
                'timestamp': _lastBufferedTime!,
                'remainingBuffer': _lastBufferedPosition! - _playerController!.videoPlayerController!.value.position,
              });
            } else {
              LogUtil.i('未知的缓冲区数据类型: $bufferedData (类型: ${bufferedData.runtimeType})');
              _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
            }
          } else {
            LogUtil.i('缓冲区数据为空');
            _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
          }
        }
        break;

      case BetterPlayerEventType.bufferingEnd:
        if (mounted) {
          setState(() {
            isBuffering = false;
            toastString = 'HIDE_CONTAINER';
            if (!_isUserPaused) _showPauseIconFromListener = false;
          });
        }
        _timerManager.cancel('buffering');
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          if (mounted) {
            setState(() {
              isPlaying = true;
              if (!isBuffering) toastString = 'HIDE_CONTAINER';
              _progressEnabled = false;
              _showPlayIcon = false;
              _showPauseIconFromListener = false;
              _isUserPaused = false;
            });
          }
          _timerManager.cancel('timeout');
          _startPlayDurationTimer();
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          if (mounted) {
            setState(() {
              isPlaying = false;
              toastString = S.current.playpause;
              if (_isUserPaused) {
                _showPlayIcon = true;
                _showPauseIconFromListener = false;
              } else {
                _showPlayIcon = false;
                _showPauseIconFromListener = true;
              }
            });
          }
          LogUtil.i('播放暂停，用户触发: $_isUserPaused');
        }
        break;

      case BetterPlayerEventType.progress:
        if (_progressEnabled && isPlaying) {
          final position = event.parameters?["progress"] as Duration?;
          final duration = event.parameters?["duration"] as Duration?;
          if (position != null && duration != null) {
            if (_lastBufferedPosition != null && _lastBufferedTime != null) {
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final timeSinceLastUpdate = (timestamp - _lastBufferedTime!) / 1000.0;
              final remainingBuffer = _lastBufferedPosition! - position;

              if (_isHls && !_isParsing) {
                final remainingTime = duration - position;
                if (_preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
                  await _switchToPreCachedUrl('HLS 剩余时间少于 $hlsSwitchThresholdSeconds 秒');
                } else {
                  _checkHlsReparseCondition(position, duration, timeSinceLastUpdate);
                }
              } else {
                final remainingTime = duration - position;
                if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
                  final nextUrl = _getNextVideoUrl();
                  if (nextUrl != null && nextUrl != _preCachedUrl) {
                    LogUtil.i('非 HLS 剩余时间少于 $nonHlsPreloadThresholdSeconds 秒，预缓存下一源: $nextUrl');
                    _preloadNextVideo(nextUrl);
                  }
                }
                if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
                  await _switchToPreCachedUrl('非 HLS 剩余时间少于 $nonHlsSwitchThresholdSeconds 秒');
                }
              }
            }
          } else {
            LogUtil.i('Progress 数据不完整: position=$position, duration=$duration');
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
        if (event.betterPlayerEventType != BetterPlayerEventType.changedPlayerVisibility) {
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  void _updateBufferedHistory(Map<String, dynamic> entry) {
    final timestamp = entry['timestamp'] as int;
    _bufferedHistory[timestamp] = entry;
    // 修改 5: 添加历史记录大小限制
    if (_bufferedHistory.length > bufferHistorySize) {
      final oldestKey = _bufferedHistory.keys.reduce((a, b) => a < b ? a : b);
      _bufferedHistory.remove(oldestKey);
    }
  }

  void _checkHlsReparseCondition(Duration position, Duration duration, double timeSinceLastUpdate) {
    if (_bufferedHistory.length < bufferHistorySize) return;

    int positionIncreaseCount = 0;
    int remainingBufferLowCount = 0;

    final sortedKeys = _bufferedHistory.keys.toList()..sort();
    for (int i = 0; i < sortedKeys.length - 1; i++) {
      final prev = _bufferedHistory[sortedKeys[i]]!;
      final curr = _bufferedHistory[sortedKeys[i + 1]]!;
      if (curr['position'] > prev['position']) {
        positionIncreaseCount++;
      }
      if ((curr['remainingBuffer'] as Duration).inSeconds < minRemainingBufferSeconds) {
        remainingBufferLowCount++;
      }
    }

    if (positionIncreaseCount >= positionIncreaseThreshold &&
        remainingBufferLowCount >= lowBufferThresholdCount &&
        timeSinceLastUpdate > bufferUpdateTimeoutSeconds) {
      LogUtil.i('触发重新解析: 位置增加 $positionIncreaseThreshold 次，剩余缓冲 < $minRemainingBufferSeconds 至少 $lowBufferThresholdCount 次，最后缓冲更新距今 > $bufferUpdateTimeoutSeconds');
      _reparseAndSwitch();
    }
  }

  void _startPlayDurationTimer() {
    _timerManager.cancel('playDuration');
    _timerManager.schedule('playDuration', const Duration(seconds: initialProgressDelaySeconds), () {
      if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
        bool shouldEnableProgress = _isHls && _originalUrl?.toLowerCase().contains('timelimit') == true ||
            (!_isHls && _getNextVideoUrl() != null);

        if (shouldEnableProgress) {
          LogUtil.i('播放 $initialProgressDelaySeconds 秒，启用 progress 监听');
          _progressEnabled = true;
        } else {
          LogUtil.i('播放 $initialProgressDelaySeconds 秒，但未满足条件，不启用 progress 监听');
        }
        _retryCount = 0;
      }
    });
  }

  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel || _playerController == null || url == _currentPlayUrl) {
      LogUtil.i('预加载被阻止: _isDisposing=$_isDisposing, _isSwitchingChannel=$_isSwitchingChannel, controller=${_playerController != null}, url=$url');
      return;
    }

    try {
      LogUtil.i('开始预加载: $url');
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
        return;
      }
      _preCachedUrl = parsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl, 当前 _isHls: $_isHls (保持不变)');

      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _checkUrlType(parsedUrl)['isHls']!,
        url: parsedUrl,
      );

      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
    }
  }

  void _startTimeoutCheck() {
    if (_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) return;

    _timeoutActive = true;
    _timerManager.schedule('timeoutCheck', Duration(seconds: defaultTimeoutSeconds), () {
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

    if (resetRetryCount) {
      if (mounted) setState(() => _retryCount = 0);
    }

    if (_retryCount < defaultMaxRetries) {
      if (mounted) {
        setState(() {
          _isRetrying = true;
          _retryCount++;
          isBuffering = false;
          toastString = S.current.retryplay;
          _showPlayIcon = false;
          _showPauseIconFromListener = false;
        });
      }
      LogUtil.i('重试播放: 第 $_retryCount 次');

      _timerManager.cancel('retry');
      _timerManager.schedule('retry', const Duration(seconds: retryDelaySeconds), () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) {
          LogUtil.i('重试中断: mounted=$mounted, isSwitchingChannel=$_isSwitchingChannel, isDisposing=$_isDisposing');
          if (mounted) setState(() => _isRetrying = false);
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

  String? _cachedNextUrl;
  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null) return null;
    final List<String> urls = _currentChannel!.urls!;
    if (urls.isEmpty) return null;
    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) return null;
    _cachedNextUrl = urls[nextSourceIndex];
    return _cachedNextUrl;
  }

  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;

    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      LogUtil.i('无更多源可切换');
      _handleNoMoreSources();
      return;
    }

    if (mounted) {
      setState(() {
        _sourceIndex++;
        _isRetrying = false;
        _retryCount = 0;
        isBuffering = false;
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
        _preCachedUrl = null;
      });
    }

    LogUtil.i('切换到下一源: $nextUrl');
    _startNewSourceTimer();
  }

  Future<void> _handleNoMoreSources() async {
    if (mounted) {
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
    }
    await _cleanupController(_playerController);
    LogUtil.i('播放结束，无更多源');
  }

  void _startNewSourceTimer() {
    _timerManager.cancel('newSource');
    _timerManager.schedule('newSource', const Duration(seconds: retryDelaySeconds), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;

    _isDisposing = true;
    try {
      _timerManager.cancelAll(); // 修改 6: 清理所有定时器
      _timeoutActive = false;

      controller.removeEventsListener(_videoListener);

      if (controller.isPlaying() ?? false) {
        await controller.pause();
        await controller.setVolume(0);
      }

      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
      controller.videoPlayerController?.dispose();
      controller.dispose();

      if (mounted) {
        setState(() {
          _playerController = null;
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
      }
      LogUtil.i('播放器清理完成');
    } catch (e, stackTrace) {
      LogUtil.logError('清理播放器失败', e, stackTrace);
    } finally {
      _isDisposing = false;
    }
  }

  // 修改 2: 合并 StreamUrl 清理逻辑
  Future<void> _disposeAllStreams() async {
    if (_streamUrl != null) {
      await _streamUrl!.dispose();
      _streamUrl = null;
    }
    if (_preCacheStreamUrl != null) {
      await _preCacheStreamUrl!.dispose();
      _preCacheStreamUrl = null;
    }
  }

  Future<void> _reparseAndSwitch() async {
    if (_isRetrying || _isSwitchingChannel || _isDisposing || _isParsing) {
      LogUtil.i('重新解析被阻止: _isRetrying=$_isRetrying, _isSwitchingChannel=$_isSwitchingChannel, _isDisposing=$_isDisposing, _isParsing=$_isParsing');
      return;
    }

    _isParsing = true;
    if (mounted) setState(() => _isRetrying = true);

    try {
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
        _handleSourceSwitching();
        return;
      }
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
        return;
      }

      final position = _playerController?.videoPlayerController?.value.position ?? Duration.zero;
      final bufferedPosition = _playerController?.videoPlayerController?.value.buffered?.isNotEmpty == true
          ? _playerController!.videoPlayerController!.value.buffered!.last.end
          : position;
      final remainingBuffer = bufferedPosition - position;
      if (remainingBuffer.inSeconds > networkRecoveryBufferSeconds) {
        LogUtil.i('网络恢复，剩余缓冲 > $networkRecoveryBufferSeconds 秒，取消预加载');
        _preCachedUrl = null;
        _isParsing = false;
        if (mounted) setState(() => _isRetrying = false);
        await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
        return;
      }

      _preCachedUrl = newParsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl');

      final newSource = BetterPlayerConfig.createDataSource(
        isHls: _checkUrlType(newParsedUrl)['isHls']!,
        url: newParsedUrl,
      );

      if (_playerController != null) {
        await _playerController!.preCache(newSource);
        _progressEnabled = false;
        _timerManager.cancel('playDuration');
      } else {
        LogUtil.i('播放器控制器为空，无法切换');
        _handleSourceSwitching();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      await _disposeAllStreams(); // 修改 2: 使用合并的清理方法
      _handleSourceSwitching();
    } finally {
      _isParsing = false;
      if (mounted) setState(() => _isRetrying = false);
      await _disposeAllStreams(); // 修改 7: 在 finally 中确保资源释放
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
        LogUtil.i('分类 $category 不包含 $regionPrefix，跳过排序');
        return;
      }

      LogUtil.i('排序前 groupList for $category: $groupList');
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
          LogUtil.i('排序前 channelList for $group: $channelList');
          final sortedChannels = _sortByGeoPrefix(channelList, cityPrefix);
          for (var channel in sortedChannels) {
            newChannels[channel] = channels[channel]!;
          }
        } else {
          LogUtil.i('组 $group 不包含 $regionPrefix，跳过 channel 排序');
          for (var channel in channelList) {
            newChannels[channel] = channels[channel]!;
          }
        }
        newGroups[group] = newChannels;
      }
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成: ${newGroups.keys.toList()}');
    });

    LogUtil.i('按地理位置排序完成');
  }

  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;

    try {
      if (mounted) {
        setState(() {
          isBuffering = false;
          toastString = S.current.loading;
          _currentChannel = model;
          _sourceIndex = 0;
          _isRetrying = false;
          _retryCount = 0;
          _shouldUpdateAspectRatio = true;
        });
      }

      await _queueSwitchChannel(_currentChannel, _sourceIndex);

      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      if (mounted) setState(() => toastString = S.current.playError);
      await _cleanupController(_playerController);
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
      if (mounted) {
        setState(() {
          _sourceIndex = selectedIndex;
          _isRetrying = false;
          _retryCount = 0;
        });
      }
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
    }
  }

  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      if (mounted) setState(() => _drawerIsOpen = false);
      return false;
    }

    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) await _playerController?.pause();

    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    if (!shouldExit && wasPlaying && mounted) await _playerController?.play();
    return shouldExit;
  }

  void _handleUserPaused() {
    if (mounted) {
      setState(() {
        _isUserPaused = true;
      });
    }
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
    _isDisposing = true;
    _cleanupController(_playerController);
    _disposeAllStreams(); // 修改 2: 使用合并的清理方法
    _pendingSwitchQueue.clear(); // 修改 4: 确保队列在 dispose 时清空
    _originalUrl = null;
    _adManager.dispose();
    _timerManager.dispose();
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
    if (mounted) {
      setState(() {
        _isRetrying = false;
        _retryCount = 0;
        _isAudio = false;
      });
    }

    if (widget.m3uData.playList == null || widget.m3uData.playList!.isEmpty) {
      LogUtil.e('播放列表无效');
      if (mounted) setState(() => toastString = S.current.getDefaultError);
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
      if (mounted) setState(() => toastString = S.current.parseError);
    }
  }

  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
        if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);

        if (mounted) {
          setState(() {
            _retryCount = 0;
            _timeoutActive = false;
            _queueSwitchChannel(_currentChannel, _sourceIndex);
          });
        }
      } else {
        if (mounted) {
          setState(() {
            toastString = 'UNKNOWN';
            _isRetrying = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _currentChannel = null;
          toastString = 'UNKNOWN';
          _isRetrying = false;
        });
      }
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
        if (mounted) setState(() => toastString = S.current.getDefaultError);
        return;
      }
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('处理播放列表失败', e, stackTrace);
      if (mounted) setState(() => toastString = S.current.parseError);
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

class TimerManager {
  final Map<String, Timer> _timers = {};

  void schedule(String key, Duration duration, VoidCallback callback) {
    cancel(key);
    _timers[key] = Timer(duration, callback);
  }

  void cancel(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  void cancelAll() {
    _timers.values.forEach((timer) => timer.cancel());
    _timers.clear();
  }

  void dispose() {
    cancelAll();
  }
}
