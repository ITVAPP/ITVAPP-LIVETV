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
  static const int defaultMaxRetries = 1; // 默认最大重试次数，控制播放失败后尝试重新播放的最大次数
  static const int defaultTimeoutSeconds = 36; // 解析超时秒数，若超过此时间仍未完成，则视为解析失败
  static const int initialProgressDelaySeconds = 60; // 播放开始后经过此时间才会启用进度事件监听（progress）
  static const int bufferUpdateTimeoutSeconds = 6; // 若缓冲区最后一次更新距现在超过此时间（秒），且其他条件满足，则(trigger)重新解析
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
  // 修改：使用 Map 替代 List，以时间戳为键优化查询和更新
  Map<int, Map<String, dynamic>> _bufferedHistory = {};
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
  bool _isHlsCached = false; // _isHls 的缓存标志
  bool _isAudioCached = false; // _isAudio 的缓存标志
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

  // 修改：将 _pendingSwitch 改为队列结构
  final List<Map<String, dynamic>> _pendingSwitchQueue = [];

  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    final lowercaseUrl = url.toLowerCase();
    return !videoFormats.any(lowV(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
  }

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

  // 修改：统一更新 _currentPlayUrl 并缓存 _isHls 和 _isAudio
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    if (!_isHlsCached || !_isAudioCached) {
      _isHls = _isHlsStream(_currentPlayUrl);
      _isAudio = _checkIsAudioStream(_currentPlayUrl);
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

  /// 播放视频，包含初始化和切换逻辑
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    if (_currentChannel == null || _currentChannel!.urls == null || _currentChannel!.urls!.isEmpty) {
      LogUtil.e('当前频道无效或无可用源');
      setState(() => toastString = S.current.playError);
      return;
    }

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');

    _adManager.reset();
    _updateStateOnPlayStart(sourceName);
    _startTimeoutTimer();

    try {
      // 修改：并行执行广告加载和控制器初始化
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
      String parsedUrl = await _streamUrl!.getStreamUrl();
      _isHlsCached = false; // 重置缓存标志
      _isAudioCached = false;
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

      setState(() => _isAudio = _isAudio);

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
        setState(() {
          _playerController = tempController;
        });
        await _playerController?.play();
        LogUtil.i('开始播放: $parsedUrl');
        _timeoutActive = false;
      } catch (e) {
        tempController?.dispose();
        throw e;
      }

      if (adFuture != null) await adFuture; // 等待广告完成
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
        _processPendingSwitchQueue();
      }
    }
  }

  // 修改：合并状态更新逻辑
  void _updateStateOnPlayStart(String sourceName) {
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
    _timeoutTimer = Timer(Duration(seconds: defaultTimeoutSeconds), () {
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

  // 修改：处理切换请求队列
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

  // 修改：处理队列中的最新请求
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
        setState(() {
          isBuffering = true;
          toastString = S.current.loading;
        });
        
        if (isPlaying) {
          _timeoutTimer?.cancel();
          _timeoutTimer = Timer(const Duration(seconds: bufferingStartSeconds), () {
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
        setState(() {
          isBuffering = false;
          toastString = 'HIDE_CONTAINER';
          if (!_isUserPaused) _showPauseIconFromListener = false;
        });
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
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
          if (_playDurationTimer == null || !_playDurationTimer!.isActive) {
            _startPlayDurationTimer();
          }
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
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

  // 修改：优化缓冲历史记录管理，使用 Map
  void _updateBufferedHistory(Map<String, dynamic> entry) {
    final timestamp = entry['timestamp'] as int;
    _bufferedHistory[timestamp] = entry;
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
    _playDurationTimer = Timer(const Duration(seconds: initialProgressDelaySeconds), () {
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
        _playDurationTimer = null;
      }
    });
  }

  // 修改：提前检查条件优化
  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel || _playerController == null || url == _currentPlayUrl) {
      LogUtil.i('预加载被阻止: _isDisposing=$_isDisposing, _isSwitchingChannel=$_isSwitchingChannel, controller=${_playerController != null}, url=$url');
      return;
    }

    try {
      LogUtil.i('开始预加载: $url');
      await _disposePreCacheStreamUrl();
      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposePreCacheStreamUrl();
        return;
      }
      _preCachedUrl = parsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl, 当前 _isHls: $_isHls (保持不变)');

      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl),
        url: parsedUrl,
      );

      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl();
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

    if (resetRetryCount) {
      setState(() => _retryCount = 0);
    }

    if (_retryCount < defaultMaxRetries) {
      setState(() {
        _isRetrying = true;
        _retryCount++;
        isBuffering = false;
        toastString = S.current.retryplay;
        _showPlayIcon = false;
        _showPauseIconFromListener = false;
      });
      LogUtil.i('重试播放: 第 $_retryCount 次');

      _retryTimer = Timer(const Duration(seconds: retryDelaySeconds), () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) {
          LogUtil.i('重试中断: mounted=$mounted, isSwitchingChannel=$_isSwitchingChannel, isDisposing=$_isDisposing');
          setState(() => _isRetrying = false);
          return;
        }
        await _playVideo(isRetry: true);
        if (mounted) {
          setState(() => _isRetrying = false);
        }
      });
    } else {
      LogUtil.i('重试次数达上限，切换下一源');
      _handleSourceSwitching();
    }
  }

  // 修改：缓存 _getNextVideoUrl 结果
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

  void _startNewSourceTimer() {
    _retryTimer = Timer(const Duration(seconds: retryDelaySeconds), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  /// 清理播放器控制器，确保资源释放
  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;

    _isDisposing = true;
    try {
      // 修改：集成 _cleanupTimers 逻辑
      _retryTimer?.cancel();
      _retryTimer = null;
      _playDurationTimer?.cancel();
      _playDurationTimer = null;
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _timeoutActive = false;

      controller.removeEventsListener(_videoListener);

      if (controller.isPlaying() ?? false) {
        await controller.pause();
        await controller.setVolume(0);
      }

      await _disposeStreamUrl();
      await _disposePreCacheStreamUrl();
      controller.videoPlayerController?.dispose();
      controller.dispose();

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
      LogUtil.i('播放器清理完成');
    } catch (e, stackTrace) {
      LogUtil.logError('清理播放器失败', e, stackTrace);
    } finally {
      _isDisposing = false;
    }
  }

  Future<void> _disposeStreamUrl() async {
    if (_streamUrl != null) {
      await _streamUrl!.dispose();
      _streamUrl = null;
    }
  }

  Future<void> _disposePreCacheStreamUrl() async {
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
    setState(() => _isRetrying = true);

    try {
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      await _disposeStreamUrl();
      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeStreamUrl();
        _handleSourceSwitching();
        return;
      }
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeStreamUrl();
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
        setState(() => _isRetrying = false);
        await _disposeStreamUrl();
        return;
      }

      _preCachedUrl = newParsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl');

      final newSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(newParsedUrl),
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
      await _disposeStreamUrl();
      _handleSourceSwitching();
    } finally {
      _isParsing = false;
      if (mounted) setState(() => _isRetrying = false);
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

  // 修改：使用原地排序，保证逻辑一致
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix == null || prefix.isEmpty) {
      LogUtil.i('地理前缀为空，返回原始顺序');
      return items;
    }

    items.sort((a, b) {
      final aMatches = a.startsWith(prefix);
      final bMatches = b.startsWith(prefix);
      if (aMatches && !bMatches) return -1;
      if (!aMatches && bMatches) return 1;
      return items.indexOf(a).compareTo(items.indexOf(b));
    });

    LogUtil.i('排序结果: $items');
    return items;
  }

  // 修改：优化为单次遍历，保证效果一致
  void _sortVideoMap(PlaylistModel videoMap, String? userInfo) {
    if (videoMap.playList == null || videoMap.playList!.isEmpty) {
      LogUtil.e('播放列表为空，无需排序');
      return;
    }

    final location = _getLocationInfo(userInfo);
    final String? regionPrefix = location['region'];
    final String? cityPrefix = location['city'];

    if ((regionPrefix == null || regionPrefix.isEmpty) && (cityPrefix == null || cityPrefix.isEmpty)) {
      LogUtil.i('地理信息中未找到有效地区或城市前缀，跳过排序');
      return;
    }

    final sortedPlayList = <String, Map<String, Map<String, PlayModel>>>{};
    videoMap.playList!.forEach((category, groups) {
      final groupList = groups.keys.toList();
      final sortedGroups = _sortByGeoPrefix(groupList, regionPrefix);
      final newGroups = <String, Map<String, PlayModel>>{};

      for (var group in sortedGroups) {
        final channels = groups[group]!;
        final channelList = channels.keys.toList();
        final sortedChannels = _sortByGeoPrefix(channelList, cityPrefix);
        final newChannels = <String, PlayModel>{};

        for (var channel in sortedChannels) {
          newChannels[channel] = channels[channel]!;
        }
        newGroups[group] = newChannels;
      }
      sortedPlayList[category] = newGroups;
    });

    videoMap.playList = sortedPlayList;
    LogUtil.i('按地理位置排序完成');
  }

  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;

    try {
      setState(() {
        isBuffering = false;
        toastString = S.current.loading;
        _currentChannel = model;
        _sourceIndex = 0;
        _isRetrying = false;
        _retryCount = 0;
        _shouldUpdateAspectRatio = true;
      });

      await _queueSwitchChannel(_currentChannel, _sourceIndex);

      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      setState(() => toastString = S.current.playError);
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

  void _handleUserPaused() {
    setState(() {
      _isUserPaused = true;
    });
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
    _disposeStreamUrl();
    _disposePreCacheStreamUrl();
    _pendingSwitchQueue.clear();
    _originalUrl = null;
    _adManager.dispose();
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
      String? userInfo = SpUtil.getString('user_all_info');
      LogUtil.i('原始 user_all_info: $userInfo');
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
          _queueSwitchChannel(_currentChannel, _sourceIndex);
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
                     多元key: _drawerRefreshKey,
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
