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

/// 主页面，负责视频播放和频道管理
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // M3U 播放列表数据
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
}

class _LiveHomePageState extends State<LiveHomePage> {
  late List<Map<String, dynamic>> _bufferedHistory; // 缓冲历史记录数组
  int _bufferedHistoryIndex = 0; // 当前写入索引
  String? _preCachedUrl; // 预缓存的视频 URL
  bool _isParsing = false; // 是否正在解析视频地址
  Duration? _lastBufferedPosition; // 上次缓冲的播放位置
  int? _lastBufferedTime; // 上次缓冲时间戳（毫秒）
  bool _isRetrying = false; // 是否正在重试播放
  Timer? _retryTimer; // 重试操作的计时器
  String toastString = S.current.loading; // 当前显示的提示信息
  PlaylistModel? _videoMap; // 视频播放列表数据
  PlayModel? _currentChannel; // 当前播放的频道
  int _sourceIndex = 0; // 当前播放源的索引
  int _lastProgressTime = 0; // 上次播放进度时间（未使用，已标记移除）
  BetterPlayerController? _playerController; // 视频播放器控制器
  bool isBuffering = false; // 是否正在缓冲
  bool isPlaying = false; // 是否正在播放
  double aspectRatio = _Constants.defaultAspectRatio; // 当前视频宽高比
  bool _drawerIsOpen = false; // 频道抽屉是否打开
  int _retryCount = 0; // 重试次数计数器
  bool _timeoutActive = false; // 超时检测是否激活
  bool _isDisposing = false; // 是否正在释放资源
  bool _isSwitchingChannel = false; // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 是否需要更新宽高比
  StreamUrl? _streamUrl; // 当前视频流地址实例
  StreamUrl? _preCacheStreamUrl; // 预缓存视频流地址实例
  String? _currentPlayUrl; // 当前播放的视频 URL
  String? _originalUrl; // 解析前的原始视频 URL
  bool _progressEnabled = false; // 是否启用播放进度监听
  bool _isHls = false; // 当前是否为 HLS 视频流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  }; // 用户收藏的频道列表
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新的唯一键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析工具实例
  bool _isAudio = false; // 是否为音频流
  Timer? _playDurationTimer; // 播放持续时间计时器
  Timer? _timeoutTimer; // 缓冲超时计时器
  late AdManager _adManager; // 广告管理实例
  bool _isUserPaused = false; // 是否为用户主动暂停
  bool _showPlayIcon = false; // 是否显示播放图标
  bool _showPauseIconFromListener = false; // 是否显示监听器触发的暂停图标
  Map<String, dynamic>? _pendingSwitch; // 待处理的频道切换请求队列

  /// 检查视频 URL 是否为音频流
  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    final lowercaseUrl = url.toLowerCase();
    return !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
  }

  /// 检查视频 URL 是否为 HLS 流
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

  /// 更新当前播放 URL 并检测是否为 HLS 流
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  /// 切换到预缓存的视频地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
    if (_preCachedUrl == null) {
      LogUtil.i('$logDescription: 预缓存地址为空，无法切换');
      return;
    }
    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址与当前地址相同，跳过切换，尝试重新解析');
      _preCachedUrl = null;
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
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
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
    }
  }

  /// 播放视频，处理初始化和切换逻辑
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
        await _disposeStreamUrlInstance(_streamUrl);
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
        _timeoutActive = false;
        _timeoutTimer?.cancel();
      } catch (e) {
        tempController?.dispose();
        throw e;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrlInstance(_streamUrl);
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
          _pendingSwitch = null; // 清理切换请求，确保不会重复处理
          LogUtil.i('处理最新切换请求: ${_currentChannel!.title}, 源索引: $_sourceIndex');
          Future.microtask(() => _playVideo());
        }
      }
    }
  }

  /// 将频道切换请求加入队列处理
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

  /// 监听视频播放事件并处理状态更新
  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing) return;

    // 缓存状态更新，减少不必要的 setState 调用
    String? newToastString;
    bool? newIsBuffering;
    bool? newIsPlaying;
    bool? newShowPlayIcon;
    bool? newShowPauseIconFromListener;

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
        if (!_isRetrying && !_isSwitchingChannel) { // 检查状态，避免重复触发
          if (_preCachedUrl != null) await _switchToPreCachedUrl('异常触发');
          else _retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        newIsBuffering = true;
        newToastString = S.current.loading;

        // 仅在视频已开始播放后启用缓冲超时检查
        if (isPlaying) {
          _startTimeoutCheck(
            Duration(seconds: _Constants.bufferingStartSeconds),
            onTimeout: () {
              // 检查额外状态以避免不必要触发
              if (_isParsing || _pendingSwitch != null) {
                LogUtil.i('缓冲超时检查被阻止: isParsing=$_isParsing, pendingSwitch=$_pendingSwitch');
                return;
              }
              if (_playerController?.isPlaying() != true) {
                LogUtil.e('播放中缓冲超过${_Constants.bufferingStartSeconds}秒，触发重试');
                _retryPlayback(resetRetryCount: true);
              }
            },
            switchSourceOnTimeout: false, // 禁用默认切换源行为
          );
        } else {
          LogUtil.i('初始缓冲，不启用${_Constants.bufferingStartSeconds}秒超时');
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
                  // 调试才开启下面日志
                  // LogUtil.i('缓冲区范围更新: $_lastBufferedPosition @ $_lastBufferedTime');
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
        newIsBuffering = false;
        newToastString = 'HIDE_CONTAINER';
        if (!_isUserPaused) newShowPauseIconFromListener = false;
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        _cleanupTimers();
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          newIsPlaying = true;
          if (!isBuffering) newToastString = 'HIDE_CONTAINER';
          _progressEnabled = false;
          newShowPlayIcon = false;
          newShowPauseIconFromListener = false;
          _isUserPaused = false;
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          if (_playDurationTimer == null || !_playDurationTimer!.isActive) _startPlayDurationTimer();
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          newIsPlaying = false;
          newToastString = S.current.playpause;
          if (_isUserPaused) newShowPlayIcon = true;
          else newShowPauseIconFromListener = true;
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

            _bufferedHistory[_bufferedHistoryIndex] = {
              'buffered': _lastBufferedPosition!,
              'position': position,
              'timestamp': timestamp,
              'remainingBuffer': remainingBuffer,
            };
            _bufferedHistoryIndex = (_bufferedHistoryIndex + 1) % _Constants.bufferHistorySize;

            if (_isHls && !_isParsing) {
              final remainingTime = duration - position;
                // 调试才开启下面日志
                // LogUtil.i('HLS 检查 - 当前位置: $position, 缓冲末尾: $_lastBufferedPosition, 时间差: $remainingTime, 历史记录: ${_bufferedHistory.map((e) => "${e['position']}->${e['buffered']}@${e['timestamp']}").toList()}');
              if (_preCachedUrl != null && remainingTime.inSeconds <= _Constants.hlsSwitchThresholdSeconds) {
                await _switchToPreCachedUrl('HLS 剩余时间少于 ${_Constants.hlsSwitchThresholdSeconds} 秒');
              } else if (_bufferedHistory.where((e) => e.isNotEmpty).length >= _Constants.bufferHistorySize) {
                int positionIncreaseCount = 0;
                int remainingBufferLowCount = 0;
                for (int i = 0; i < _Constants.positionIncreaseThreshold; i++) {
                  final prevIndex = (_bufferedHistoryIndex - _Constants.positionIncreaseThreshold + i - 1 + _Constants.bufferHistorySize) % _Constants.bufferHistorySize;
                  final currIndex = (_bufferedHistoryIndex - _Constants.positionIncreaseThreshold + i + _Constants.bufferHistorySize) % _Constants.bufferHistorySize;
                  final prev = _bufferedHistory[prevIndex];
                  final curr = _bufferedHistory[currIndex];
                  if (prev.isNotEmpty && curr.isNotEmpty && curr['position'] > prev['position']) positionIncreaseCount++;
                  if (curr.isNotEmpty && (curr['remainingBuffer'] as Duration).inSeconds < _Constants.minRemainingBufferSeconds) remainingBufferLowCount++;
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
      // 处理未显式列出的事件（如 seekTo）
      if (event.betterPlayerEventType != BetterPlayerEventType.changedPlayerVisibility) {
        LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
      }
      break;
    }

    // 统一执行 setState，减少调用次数
    if (newToastString != null || newIsBuffering != null || newIsPlaying != null || newShowPlayIcon != null || newShowPauseIconFromListener != null) {
      setState(() {
        if (newToastString != null) toastString = newToastString;
        if (newIsBuffering != null) isBuffering = newIsBuffering;
        if (newIsPlaying != null) isPlaying = newIsPlaying;
        if (newShowPlayIcon != null) _showPlayIcon = newShowPlayIcon;
        if (newShowPauseIconFromListener != null) _showPauseIconFromListener = newShowPauseIconFromListener;
      });
    }
  }

  /// 启动播放持续时间计时器以启用进度监听
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

  /// 预加载下一个视频源以优化播放切换
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

  /// 启动超时检查以切换视频源
  void _startTimeoutCheck(Duration timeout, {VoidCallback? onTimeout, bool switchSourceOnTimeout = true}) {
    if (_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) return;
    _timeoutActive = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, () {
      if (!mounted || !_timeoutActive || _playerController?.videoPlayerController == null) {
        if (switchSourceOnTimeout) {
          _handleSourceSwitching(); // 仅在 switchSourceOnTimeout 为 true 时切换源
        }
        _timeoutActive = false;
        return;
      }
      if (isBuffering) {
        LogUtil.e('缓冲超时 (${timeout.inSeconds}秒)，执行超时操作');
        if (onTimeout != null) {
          onTimeout(); // 执行自定义回调
        } else if (switchSourceOnTimeout) {
          _handleSourceSwitching(); // 默认切换源，仅在 switchSourceOnTimeout 为 true 时执行
        }
      }
      _timeoutActive = false;
    });
  }

  /// 重试播放逻辑，管理重试次数和状态
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

  /// 获取下一个视频源的 URL
  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null || _sourceIndex + 1 >= _currentChannel!.urls!.length) return null;
    return _currentChannel!.urls![_sourceIndex + 1];
  }

  /// 处理视频源切换逻辑
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

  /// 处理无更多视频源的情况
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

  /// 启动新视频源加载计时器
  void _startNewSourceTimer() {
    _cleanupTimers();
    _retryTimer = Timer(const Duration(seconds: _Constants.retryDelaySeconds), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo(isSourceSwitch: true);
    });
  }

  /// 清理播放器控制器并释放资源
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
      controller.videoPlayerController?.dispose(); // 先释放核心播放器对象
      await _disposeStreamUrlInstance(_streamUrl);
      await _disposeStreamUrlInstance(_preCacheStreamUrl);
      controller.dispose();
      setState(() {
        _playerController = null; // 确保引用置空，避免内存泄漏
        _progressEnabled = false;
        _isAudio = false;
        _bufferedHistory = List.generate(_Constants.bufferHistorySize, (_) => <String, dynamic>{});
        _bufferedHistoryIndex = 0;
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

  /// 释放流地址实例资源
  Future<void> _disposeStreamUrlInstance(StreamUrl? streamUrl) async {
    if (streamUrl != null) {
      await streamUrl.dispose();
      if (streamUrl == _streamUrl) _streamUrl = null; // 更新实例引用
      if (streamUrl == _preCacheStreamUrl) _preCacheStreamUrl = null; // 更新实例引用
    }
  }

  /// 清理所有计时器资源
  void _cleanupTimers() {
    [_retryTimer, _playDurationTimer, _timeoutTimer].forEach((timer) {
      timer?.cancel();
    });
    _retryTimer = null;
    _playDurationTimer = null;
    _timeoutTimer = null;
    _timeoutActive = false;
  }

  /// 重新解析视频源并切换播放
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

  /// 获取用户地理位置信息
  Map<String, String?> _getLocationInfo(String? userInfo) {
    if (userInfo == null || userInfo.isEmpty) return {'region': null, 'city': null};
    try {
      final userData = jsonDecode(userInfo);
      final locationData = userData['info']?['location'];
      final region = locationData?['region'] as String?;
      final city = locationData?['city'] as String?;
      final regionPrefix = _extractPrefix(region); // 使用提取前缀的工具函数
      final cityPrefix = _extractPrefix(city);
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e) {
      LogUtil.e('解析地理信息失败: $e');
      return {'region': null, 'city': null};
    }
  }

  /// 提取字符串的前两个字符作为前缀
  String? _extractPrefix(String? value) {
    return value != null && value.length >= 2 ? value.substring(0, 2) : value;
  }

  /// 根据地理前缀对列表进行排序
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix == null || prefix.isEmpty) return items;
    final matched = <String>[];
    final unmatched = <String>[];
    final originalOrder = items.asMap(); // 保留原始顺序
    items.forEach((item) {
      if (item.startsWith(prefix)) {
        matched.add(item);
      } else {
        unmatched.add(item);
      }
    });
    matched.sort((a, b) => originalOrder[a]!.compareTo(originalOrder[b]!));
    unmatched.sort((a, b) => originalOrder[a]!.compareTo(originalOrder[b]!));
    return [...matched, ...unmatched];
  }

  /// 根据地理位置对播放列表进行排序
  void _sortVideoMap(PlaylistModel videoMap, String? userInfo) {
    if (videoMap.playList == null || videoMap.playList!.isEmpty) {
      LogUtil.i('播放列表为空，无需排序');
      return;
    }
    final location = _getLocationInfo(userInfo);
    if ((location['region'] == null || location['region']!.isEmpty) && 
        (location['city'] == null || location['city']!.isEmpty)) {
      LogUtil.i('地理信息无效，跳过排序');
      return;
    }
    videoMap.playList!.forEach((category, groups) {
      if (groups is! Map<String, Map<String, PlayModel>>) {
        LogUtil.i('跳过无效组: $category -> $groups');
        return;
      }
      final groupList = groups.keys.toList();
      final sortedGroups = _sortByGeoPrefix(groupList, location['region']);
      final newGroups = <String, Map<String, PlayModel>>{};
      for (var group in sortedGroups) {
        final channels = groups[group];
        if (channels == null) {
          LogUtil.i('跳过 null 组: $group');
          continue;
        }
        final sortedChannels = _sortByGeoPrefix(channels.keys.toList(), location['city']);
        final newChannels = <String, PlayModel>{};
        for (var channel in sortedChannels) {
          final playModel = channels[channel];
          if (playModel == null) {
            LogUtil.i('跳过 null 频道: $channel');
            continue;
          }
          newChannels[channel] = playModel;
        }
        newGroups[group] = newChannels;
      }
      videoMap.playList![category] = newGroups;
    });
    LogUtil.i('按地理位置排序完成');
  }

  /// 处理频道点击事件并切换播放
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

  /// 切换当前频道的视频源
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

  /// 处理返回键逻辑并确认退出
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

  /// 处理用户暂停操作
  void _handleUserPaused() => setState(() => _isUserPaused = true);

  /// 处理 HLS 流的播放重试
  void _handleRetry() => _retryPlayback(resetRetryCount: true);

  @override
  void initState() {
    super.initState();
    _adManager = AdManager(); // 初始化广告管理实例
    _adManager.loadAdData(); // 加载广告数据
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden); // 设置非移动设备标题栏样式
    _bufferedHistory = List.generate(_Constants.bufferHistorySize, (_) => <String, dynamic>{});
    _loadData(); // 加载初始数据
    _extractFavoriteList(); // 提取收藏列表
  }

  @override
  void dispose() {
    _isDisposing = true; // 标记资源释放开始
    _cleanupController(_playerController); // 清理播放器控制器
    _disposeStreamUrlInstance(_streamUrl); // 释放当前流地址实例
    _disposeStreamUrlInstance(_preCacheStreamUrl); // 释放预缓存流地址实例
    _pendingSwitch = null; // 清空切换请求队列
    _originalUrl = null; // 清空原始 URL
    _playDurationTimer?.cancel(); // 取消播放持续时间计时器
    _playDurationTimer = null;
    _timeoutTimer?.cancel(); // 取消超时计时器
    _timeoutTimer = null;
    _adManager.dispose(); // 释放广告管理资源
    super.dispose(); // 调用父类释放方法
  }

  /// 发送流量统计数据以分析用户行为
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

  /// 加载初始数据并初始化播放列表
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
      _sortVideoMap(_videoMap!, userInfo);
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表失败', e, stackTrace);
      setState(() => toastString = S.current.parseError);
    }
  }

  /// 处理播放列表并启动播放
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

  /// 从播放列表中提取首个有效频道
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

  /// 从播放列表中提取收藏列表
  void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
    }
  }

  /// 获取频道分组名称
  String getGroupName(String channelId) => _currentChannel?.group ?? '';

  /// 获取频道名称
  String getChannelName(String channelId) => _currentChannel?.title ?? '';

  /// 获取视频源的显示名称
  String _getSourceDisplayName(String url, int index) => url.contains('\$') ? url.split('\$')[1].trim() : S.current.lineIndex(index + 1);

  /// 获取当前频道的播放 URL 列表
  List<String> getPlayUrls(String channelId) => _currentChannel?.urls ?? [];

  /// 检查频道是否已收藏
  bool isChannelFavorite(String channelId) => favoriteList[Config.myFavoriteKey]?[getGroupName(channelId)]?.containsKey(getChannelName(channelId)) ?? false;

  /// 切换频道的收藏状态
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

  /// 重新解析播放列表并更新数据
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
      return TvPage( // 返回 TV 模式下的页面
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

    return Material( // 返回移动设备模式下的页面
      child: OrientationLayoutBuilder(
        portrait: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // 设置竖屏系统 UI 模式
          return WillPopScope(
            onWillPop: () => _handleBackPress(context), // 处理返回键逻辑
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
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); // 设置横屏系统 UI 模式
          return WillPopScope(
            onWillPop: () => _handleBackPress(context), // 处理返回键逻辑
            child: Stack(
              children: [
                Scaffold(
                  body: toastString == 'UNKNOWN'
                      ? EmptyPage(onRefresh: _loadData) // 显示空页面并提供刷新功能
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
                  offstage: !_drawerIsOpen, // 控制抽屉的显示状态
                  child: GestureDetector(
                    onTap: () => setState(() => _drawerIsOpen = false), // 点击关闭抽屉
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
