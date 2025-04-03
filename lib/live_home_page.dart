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

// 主页面组件，显示直播内容并管理播放状态
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // M3U 播放列表数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

// 主页面状态管理类，处理播放逻辑和界面更新
class _LiveHomePageState extends State<LiveHomePage> {
  // 常量定义，控制播放逻辑和超时配置
  static const int defaultMaxRetries = 1; // 默认最大重试次数
  static const int defaultTimeoutSeconds = 36; // 默认超时时间（秒）
  static const int initialProgressDelaySeconds = 60; // 初始进度监听延迟（秒）
  static const int bufferUpdateTimeoutSeconds = 6; // 缓冲更新超时（秒）
  static const int minRemainingBufferSeconds = 8; // 最小剩余缓冲时间（秒）
  static const int bufferHistorySize = 6; // 缓冲历史记录大小
  static const int positionIncreaseThreshold = 5; // 位置增加阈值
  static const int lowBufferThresholdCount = 3; // 低缓冲阈值计数
  static const int networkRecoveryBufferSeconds = 7; // 网络恢复缓冲时间（秒）
  static const int retryDelaySeconds = 2; // 重试延迟（秒）
  static const int hlsSwitchThresholdSeconds = 3; // HLS 切换阈值（秒）
  static const int nonHlsPreloadThresholdSeconds = 20; // 非 HLS 预加载阈值（秒）
  static const int nonHlsSwitchThresholdSeconds = 3; // 非 HLS 切换阈值（秒）
  static const double defaultAspectRatio = 1.78; // 默认宽高比
  static const int cleanupDelayMilliseconds = 500; // 清理延迟（毫秒）
  static const int snackBarDurationSeconds = 5; // SnackBar 显示时长（秒）
  static const int bufferingStartSeconds = 15; // 缓冲开始超时（秒）

  Map<int, Map<String, dynamic>> _bufferedHistory = {}; // 缓冲历史记录
  String? _preCachedUrl; // 预缓存的播放地址
  bool _isParsing = false; // 是否正在解析地址
  Duration? _lastBufferedPosition; // 上次缓冲位置
  int? _lastBufferedTime; // 上次缓冲时间戳
  bool _isRetrying = false; // 是否正在重试

  final _timerManager = TimerManager(); // 定时器管理器

  String toastString = S.current.loading; // 当前提示信息
  PlaylistModel? _videoMap; // 播放列表数据
  PlayModel? _currentChannel; // 当前播放频道
  int _sourceIndex = 0; // 当前源索引
  int _lastProgressTime = 0; // 上次进度时间
  BetterPlayerController? _playerController; // 播放器控制器
  bool isBuffering = false; // 是否正在缓冲
  bool isPlaying = false; // 是否正在播放
  double aspectRatio = defaultAspectRatio; // 当前宽高比
  bool _drawerIsOpen = false; // 侧边栏是否打开
  int _retryCount = 0; // 重试计数
  bool _timeoutActive = false; // 超时是否激活
  bool _isDisposing = false; // 是否正在销毁
  bool _isSwitchingChannel = false; // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 是否需要更新宽高比
  StreamUrl? _streamUrl; // 当前流地址解析器
  StreamUrl? _preCacheStreamUrl; // 预缓存流地址解析器
  String? _currentPlayUrl; // 当前播放地址
  bool _isHlsCached = false; // HLS 类型是否已缓存
  bool _isAudioCached = false; // 音频类型是否已缓存
  String? _originalUrl; // 原始播放地址
  bool _progressEnabled = false; // 是否启用进度监听
  bool _isHls = false; // 是否为 HLS 流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{}, // 收藏列表
  };
  ValueKey<int>? _drawerRefreshKey; // 侧边栏刷新键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析工具
  bool _isAudio = false; // 是否为音频流
  late AdManager _adManager; // 广告管理器
  bool _isUserPaused = false; // 用户是否主动暂停
  bool _showPlayIcon = false; // 是否显示播放图标
  bool _showPauseIconFromListener = false; // 是否显示监听器触发的暂停图标

  final List<Map<String, dynamic>> _pendingSwitchQueue = []; // 待处理切换队列

  // 检查 URL 类型，判断是否为音频或 HLS 流
  Map<String, bool> _checkUrlType(String? url) {
    if (url == null || url.isEmpty) return {'isAudio': false, 'isHls': false};
    final lowercaseUrl = url.toLowerCase();
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    bool isAudio = !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
    bool isHls = lowercaseUrl.contains('.m3u8') || !([...videoFormats, ...audioFormats].any(lowercaseUrl.contains));
    return {'isAudio': isAudio, 'isHls': isHls};
  }

  // 更新当前播放地址并缓存类型
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    if (!_isHlsCached || !_isAudioCached) {
      final urlType = _checkUrlType(_currentPlayUrl);
      _isHls = urlType['isHls']!;
      _isAudio = urlType['isAudio']!;
      _isHlsCached = true;
      _isAudioCached = true;
    }
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
      await _disposeAllStreams();
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
      await _disposeAllStreams();
    }
  }

  // 播放视频，支持重试和源切换
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

      // 并行解析流地址，但不影响广告逻辑
      final parseFuture = _streamUrl!.getStreamUrl();
      String parsedUrl = await parseFuture; // 先解析地址以优化性能
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
        await _disposeAllStreams();
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
        
        // 确保视频广告播放完成才开始播放
        if (adFuture != null) {
          await adFuture;
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
      await _disposeAllStreams();
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

  // 更新播放开始时的状态
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

  // 启动播放超时定时器
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

  // 将频道切换请求加入队列
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

  // 处理待处理的切换队列
  void _processPendingSwitchQueue() {
    if (_pendingSwitchQueue.isNotEmpty) {
      final nextRequest = _pendingSwitchQueue.last;
      _pendingSwitchQueue.clear();
      _currentChannel = nextRequest['channel'] as PlayModel?;
      _sourceIndex = nextRequest['sourceIndex'] as int;
      LogUtil.i('处理最新切换请求: ${_currentChannel!.title}, 源索引: $_sourceIndex');
      Future.microtask(() => _playVideo());
    }
  }

  // 播放器事件监听器
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

  // 更新缓冲历史记录
  void _updateBufferedHistory(Map<String, dynamic> entry) {
    final timestamp = entry['timestamp'] as int;
    _bufferedHistory[timestamp] = entry;
    if (_bufferedHistory.length > bufferHistorySize) {
      final oldestKey = _bufferedHistory.keys.reduce((a, b) => a < b ? a : b);
      _bufferedHistory.remove(oldestKey);
    }
  }

  // 检查 HLS 流是否需要重新解析
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

  // 启动播放时长定时器
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

  // 预加载下一视频源
  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel || _playerController == null || url == _currentPlayUrl) {
      LogUtil.i('预加载被阻止: _isDisposing=$_isDisposing, _isSwitchingChannel=$_isSwitchingChannel, controller=${_playerController != null}, url=$url');
      return;
    }

    try {
      LogUtil.i('开始预加载: $url');
      await _disposeAllStreams();
      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposeAllStreams();
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
      await _disposeAllStreams();
    }
  }

  // 启动超时检查
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

  // 重试播放逻辑
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
  // 获取下一视频源地址
  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null) return null;
    final List<String> urls = _currentChannel!.urls!;
    if (urls.isEmpty) return null;
    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) return null;
    _cachedNextUrl = urls[nextSourceIndex];
    return _cachedNextUrl;
  }

  // 处理源切换逻辑
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

  // 处理无更多源的情况
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

  // 启动新源播放定时器
  void _startNewSourceTimer() {
    _timerManager.cancel('newSource');
    _timerManager.schedule('newSource', const Duration(seconds: retryDelaySeconds), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  // 清理播放器控制器
  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;

    _isDisposing = true;
    try {
      _timerManager.cancelAll();
      _timeoutActive = false;

      controller.removeEventsListener(_videoListener);

      if (controller.isPlaying() ?? false) {
        await controller.pause();
        await controller.setVolume(0);
      }

      await _disposeAllStreams();
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

  // 释放所有流资源
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

  // 重新解析并切换流地址
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
      await _disposeAllStreams();
      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeAllStreams();
        _handleSourceSwitching();
        return;
      }
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeAllStreams();
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
        await _disposeAllStreams();
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
      await _disposeAllStreams();
      _handleSourceSwitching();
    } finally {
      _isParsing = false;
      if (mounted) setState(() => _isRetrying = false);
      await _disposeAllStreams();
      LogUtil.i('重新解析结束');
    }
  }

  // 获取用户地理位置信息
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

  // 根据地理前缀排序列表
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

  // 根据地理位置排序播放列表
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

  // 点击切换频道
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

  // 切换频道源
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

  // 处理返回键逻辑
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

  // 处理用户暂停
  void _handleUserPaused() {
    if (mounted) {
      setState(() {
        _isUserPaused = true;
      });
    }
  }

  // 处理重试
  void _handleRetry() {
    _retryPlayback(resetRetryCount: true);
  }

  @override
  void initState() {
    super.initState();
    _adManager = AdManager(); // 初始化广告管理器
    _adManager.loadAdData(); // 加载广告数据
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden); // 非移动设备隐藏标题栏
    _loadData(); // 加载播放数据
    _extractFavoriteList(); // 提取收藏列表
  }

  @override
  void dispose() {
    _isDisposing = true;
    _cleanupController(_playerController); // 清理播放器
    _disposeAllStreams(); // 释放流资源
    _pendingSwitchQueue.clear(); // 清空切换队列
    _originalUrl = null;
    _adManager.dispose(); // 释放广告资源
    _timerManager.dispose(); // 释放定时器资源
    super.dispose();
  }

  // 发送流量统计数据
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

  // 加载播放数据
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
      _sortVideoMap(_videoMap!, userInfo); // 根据地理位置排序
      _sourceIndex = 0;
      await _handlePlaylist(); // 处理播放列表
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表失败', e, stackTrace);
      if (mounted) setState(() => toastString = S.current.parseError);
    }
  }

  // 处理播放列表并选择初始频道
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

  // 从播放列表中获取第一个有效频道
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

  // 提取收藏列表
  void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
    }
  }

  // 获取分组名称
  String getGroupName(String channelId) => _currentChannel?.group ?? '';
  // 获取频道名称
  String getChannelName(String channelId) => _currentChannel?.title ?? '';
  // 获取源显示名称
  String _getSourceDisplayName(String url, int index) {
    if (url.contains('\$')) return url.split('\$')[1].trim();
    return S.current.lineIndex(index + 1);
  }
  // 获取播放地址列表
  List<String> getPlayUrls(String channelId) => _currentChannel?.urls ?? [];
  // 检查频道是否已收藏
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

  // 解析播放数据
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
    bool isTV = context.watch<ThemeProvider>().isTV; // 判断是否为 TV 模式

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
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // 设置系统 UI 为边缘模式
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
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); // 设置系统 UI 为沉浸模式
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: Stack(
              children: [
                Scaffold(
                  body: toastString == 'UNKNOWN'
                      ? EmptyPage(onRefresh: _loadData) // 显示空页面
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

// 定时器管理类，统一管理定时任务
class TimerManager {
  final Map<String, Timer> _timers = {}; // 定时器存储

  // 调度定时器
  void schedule(String key, Duration duration, VoidCallback callback) {
    cancel(key);
    _timers[key] = Timer(duration, callback);
  }

  // 取消指定定时器
  void cancel(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  // 取消所有定时器
  void cancelAll() {
    _timers.values.forEach((timer) => timer.cancel());
    _timers.clear();
  }

  // 释放资源
  void dispose() {
    cancelAll();
  }
}
