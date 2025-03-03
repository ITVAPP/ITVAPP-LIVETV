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
  static const int defaultTimeoutSeconds = 32;

  // 缓冲区检查相关变量
  List<Map<String, dynamic>> _bufferedHistory = [];
  String? _preCachedUrl;
  bool _isParsing = false;

  // 新增状态变量，用于优化 HLS 检查
  Duration? _lastBufferedPosition; // 上次缓冲位置
  int? _lastBufferedTime; // 上次缓冲时间戳（毫秒）

  bool _isRetrying = false;
  Timer? _retryTimer;
  String toastString = S.current.loading;
  PlaylistModel? _videoMap;
  PlayModel? _currentChannel;
  int _sourceIndex = 0;
  int _lastProgressTime = 0; 
  BetterPlayerController? _playerController;
  bool isBuffering = false;
  bool isPlaying = false;
  double aspectRatio = 1.78;
  bool _drawerIsOpen = false;
  int _retryCount = 0;
  bool _timeoutActive = false;
  bool _isDisposing = false;
  bool _isSwitchingChannel = false;
  bool _shouldUpdateAspectRatio = true;
  StreamUrl? _streamUrl;
  String? _currentPlayUrl;
  bool _progressEnabled = false;
  bool _isHls = false;
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  ValueKey<int>? _drawerRefreshKey;
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();
  bool _isAudio = false;
  Timer? _playDurationTimer;

  // 切换请求队列
  Map<String, dynamic>? _pendingSwitch; // 存储 {channel: PlayModel, sourceIndex: int} 或 null

  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    final lowercaseUrl = url.toLowerCase();
    return !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
  }

  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const formats = [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'
    ];
    return !formats.any(url.toLowerCase().contains);
  }

  /// 播放视频，包含初始化和切换逻辑
  Future<void> _playVideo() async {
    // 添加空检查以防止 _currentChannel 为 null 时崩溃
    if (_currentChannel == null) return; // 避免空指针异常

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName');

    _cleanupTimers();
    setState(() {
      toastString = '${_currentChannel!.title} - $sourceName  ${S.current.loading}';
      isPlaying = false;
      isBuffering = false;
      _progressEnabled = false;
      _isSwitchingChannel = true; // 在清理前设置，保护整个过程
    });

    try {
      // 如果已有控制器，先暂停并重用，避免重复创建
      if (_playerController != null) {
        await _playerController!.pause();
        await _cleanupController(_playerController);
      }

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) {
        LogUtil.i('组件已卸载，停止播放流程');
        return;
      }

      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('解析播放地址: $url');
      String parsedUrl = await StreamUrl(url).getStreamUrl();
      _currentPlayUrl = parsedUrl;

      if (parsedUrl == 'ERROR') {
        LogUtil.e('地址解析失败: $url');
        setState(() {
          toastString = S.current.vpnplayError;
          _isSwitchingChannel = false;
        });
        return;
      }

      bool isDirectAudio = _checkIsAudioStream(parsedUrl);
      setState(() => _isAudio = isDirectAudio);

      final bool isHls = _isHlsStream(parsedUrl);
      _isHls = isHls;
      LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $isDirectAudio, HLS: $isHls');

      final dataSource = BetterPlayerConfig.createDataSource(
        url: parsedUrl,
        isHls: isHls,
      );
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener,
        isHls: isHls,
      );

      BetterPlayerController? tempController;
      try {
        tempController = BetterPlayerController(betterPlayerConfiguration);
        await tempController.setupDataSource(dataSource);
        LogUtil.i('播放器数据源设置完成: $parsedUrl');
        setState(() {
          _playerController = tempController;
          _timeoutActive = false;
        });
        await _playerController?.play();
        LogUtil.i('开始播放: $parsedUrl');
      } catch (e) {
        tempController?.dispose();
        throw e;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingChannel = false;
          // 重置其他状态，确保一致性
          if (_playerController == null) {
            isBuffering = false;
            isPlaying = false;
          }
        });
        // 处理最新的切换请求
        if (_pendingSwitch != null) {
          final nextRequest = _pendingSwitch!;
          _currentChannel = nextRequest['channel'] as PlayModel?;
          _sourceIndex = nextRequest['sourceIndex'] as int;
          _pendingSwitch = null; // 处理完成后清空
          LogUtil.i('处理最新切换请求: ${_currentChannel!.title}, 源索引: $_sourceIndex');
          Future.microtask(() => _playVideo()); // 异步调度，避免递归
        }
      }
    }
  }

  // 将切换请求加入队列
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) return;

    if (_isSwitchingChannel) {
      // 若正在切换，覆盖旧请求，只保留最新请求
      _pendingSwitch = {'channel': channel, 'sourceIndex': sourceIndex};
      LogUtil.i('更新最新切换请求: ${channel.title}, 源索引: $sourceIndex');
    } else {
      _currentChannel = channel;
      _sourceIndex = sourceIndex;
      await _playVideo();
    }
  }

  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (_shouldUpdateAspectRatio) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? 1.78;
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
          LogUtil.i('异常触发，切换到预缓存地址: $_preCachedUrl');
          final newSource = BetterPlayerConfig.createDataSource(url: _preCachedUrl!, isHls: _isHls);
          await _playerController?.preCache(newSource);
          LogUtil.i('预缓存新数据源完成: $_preCachedUrl');
          await _playerController?.setupDataSource(newSource);
          if (isPlaying) {
            await _playerController?.play();
            LogUtil.i('异常切换后开始播放: $_preCachedUrl');
          } else {
            LogUtil.i('异常切换后保持暂停状态: $_preCachedUrl');
          }
          _preCachedUrl = null;
        } else {
          _retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        LogUtil.i('开始缓冲');
        setState(() {
          isBuffering = true;
          toastString = S.current.loading;
        });
        _startTimeoutCheck();
        break;

case BetterPlayerEventType.bufferingUpdate:
  final bufferedData = event.parameters?["buffered"];
  LogUtil.i('原始缓冲数据: ${event.parameters}');
  if (bufferedData != null) {
    if (bufferedData is Duration) {
      // 如果是单一的 Duration
      _lastBufferedPosition = bufferedData;
      _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('缓冲区更新: $_lastBufferedPosition @ $_lastBufferedTime');
    } else if (bufferedData is List<dynamic>) {
      // 如果是 List<DurationRange>，类似于官方代码
      final bufferedRanges = bufferedData.map((range) {
        if (range is DurationRange) return range;
        return null;
      }).whereType<DurationRange>().toList();
      if (bufferedRanges.isNotEmpty) {
        _lastBufferedPosition = bufferedRanges.last.end; // 取最后一个范围的结束位置
        _lastBufferedTime = DateTime.now().millisecondsSinceEpoch;
        LogUtil.i('缓冲区范围更新: $_lastBufferedPosition @ $_lastBufferedTime');
      }
    } else {
      LogUtil.w('未知的缓冲区数据类型: $bufferedData');
    }
  } else {
    LogUtil.w('缓冲区数据为空');
  }
  break;

      case BetterPlayerEventType.bufferingEnd:
        LogUtil.i('缓冲结束');
        setState(() {
          isBuffering = false;
          toastString = 'HIDE_CONTAINER';
        });
        _cleanupTimers();
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          setState(() {
            isPlaying = true;
            if (!isBuffering) toastString = 'HIDE_CONTAINER';
            _progressEnabled = false;
          });
          if (_playDurationTimer == null || !_playDurationTimer!.isActive) {
            _startPlayDurationTimer();
          }
          LogUtil.i('播放开始');
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          setState(() {
            isPlaying = false;
            toastString = S.current.playpause;
          });
          LogUtil.i('播放暂停');
        }
        break;

      case BetterPlayerEventType.progress:
        if (_progressEnabled && isPlaying) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastProgressTime < 1000) break; // 修改监控为 1 秒频率控制
          _lastProgressTime = now;
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
            if (_bufferedHistory.length > 5) _bufferedHistory.removeAt(0); // 保留最近 5 次历史（约 5 秒）

            if (_isHls && !_isParsing) {
              // HLS 检查逻辑
              final remainingTime = duration - position;
              LogUtil.i('HLS 检查 - 当前位置: $position, 缓冲末尾: $_lastBufferedPosition, duration: $duration, 时间差: $remainingTime, 历史记录: ${_bufferedHistory.map((e) => "${e['position']}->${e['buffered']}@${e['timestamp']}").toList()}');

              // 检查剩余时间 ≤ 2 秒且有预缓存地址
              if (_preCachedUrl != null && remainingTime.inSeconds <= 2) {
                LogUtil.i('HLS 剩余时间少于 2 秒，切换到预缓存地址: $_preCachedUrl');
                final newSource = BetterPlayerConfig.createDataSource(url: _preCachedUrl!, isHls: _isHls);
                // 预缓存新数据源（若未完成）
                await _playerController?.preCache(newSource);
                LogUtil.i('HLS 预缓存新数据源完成: $_preCachedUrl');
                await _playerController?.setupDataSource(newSource);
                if (isPlaying) {
                  await _playerController?.play();
                  LogUtil.i('HLS 切换到预缓存地址并开始播放: $_preCachedUrl');
                } else {
                  LogUtil.i('HLS 切换到预缓存地址但保持暂停状态: $_preCachedUrl');
                }
                _preCachedUrl = null; // 清理已使用的预缓存地址
              } 
              // 缓冲停滞检查
              else if (_bufferedHistory.length == 5 && _lastBufferedPosition!.inSeconds > 2) {
                int positionIncreaseCount = 0;
                int bufferStalledCount = 0;
                int remainingBufferLowCount = 0;

                for (int i = 1; i < _bufferedHistory.length; i++) {
                  final prev = _bufferedHistory[i - 1];
                  final curr = _bufferedHistory[i];
                  // 检查位置是否增加
                  if (curr['position'] > prev['position']) {
                    positionIncreaseCount++;
                  }
                  // 检查缓冲区停滞（距上次缓冲更新 > 5 秒）
                  final timeDiff = (curr['timestamp'] as int) - (_lastBufferedTime ?? curr['timestamp'] as int);
                  if (timeDiff / 1000.0 > 5) {
                    bufferStalledCount++;
                  }
                  // 检查剩余缓冲是否 < 10 秒
                  if ((curr['remainingBuffer'] as Duration).inSeconds < 10) {
                    remainingBufferLowCount++;
                  }
                }

                if (positionIncreaseCount == 5 && bufferStalledCount >= 3 && remainingBufferLowCount >= 3) {
                  LogUtil.i('HLS 当前位置 5 次中至少 5 次增加，缓冲区停滞至少 3 次，且剩余缓冲连续 3 次 < 10 秒，触发提前解析');
                  _reparseAndSwitch();
                }
              }
            } else {
              // 非 HLS 检查逻辑
              final remainingTime = duration - position;
              if (remainingTime.inSeconds <= 30) {
                final nextUrl = _getNextVideoUrl();
                if (nextUrl != null && nextUrl != _preCachedUrl) {
                  LogUtil.i('非 HLS 剩余时间少于 30 秒，预缓存下一源: $nextUrl');
                  _preloadNextVideo(nextUrl);
                }
              }
              if (remainingTime.inSeconds <= 2 && _preCachedUrl != null) {
                LogUtil.i('非 HLS 剩余时间少于 2 秒，切换到预缓存地址: $_preCachedUrl');
                final newSource = BetterPlayerConfig.createDataSource(url: _preCachedUrl!, isHls: false);
                await _playerController?.preCache(newSource);
                LogUtil.i('非 HLS 预缓存新数据源完成: $_preCachedUrl');
                await _playerController?.setupDataSource(newSource);
                if (isPlaying) {
                  await _playerController?.play();
                  LogUtil.i('非 HLS 切换到预缓存地址并开始播放: $_preCachedUrl');
                } else {
                  LogUtil.i('非 HLS 切换到预缓存地址但保持暂停状态: $_preCachedUrl');
                }
                _preCachedUrl = null;
              }
            }
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!_isHls && _preCachedUrl != null) {
          LogUtil.i('非 HLS 播放结束，切换到预缓存地址: $_preCachedUrl');
          final newSource = BetterPlayerConfig.createDataSource(url: _preCachedUrl!, isHls: false);
          await _playerController?.preCache(newSource);
          LogUtil.i('非 HLS 预缓存新数据源完成: $_preCachedUrl');
          await _playerController?.setupDataSource(newSource);
          if (isPlaying) {
            await _playerController?.play();
            LogUtil.i('非 HLS 切换到预缓存地址并开始播放: $_preCachedUrl');
          } else {
            LogUtil.i('非 HLS 切换到预缓存地址但保持暂停状态: $_preCachedUrl');
          }
          _preCachedUrl = null;
        } else if (_isHls) {
          LogUtil.i('HLS 流异常结束，重试播放');
          _retryPlayback();
        } else {
          LogUtil.i('无更多源可播放');
          _handleNoMoreSources();
        }
        break;

      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.bufferingUpdate) {
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  void _startPlayDurationTimer() {
    _playDurationTimer?.cancel();
    _playDurationTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
        LogUtil.i('播放 60 秒，重置重试次数并启用 progress 监听');
        _retryCount = 0;
        _progressEnabled = true;
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
      String parsedUrl = await StreamUrl(url).getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        return;
      }
      LogUtil.i('预加载解析完成: $parsedUrl');

      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl),
        url: parsedUrl,
      );

      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
      _preCachedUrl = parsedUrl;
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
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

  void _retryPlayback() {
    if (_isRetrying || _isSwitchingChannel || _isDisposing) return;

    _cleanupTimers();

    if (_retryCount < defaultMaxRetries) {
      setState(() {
        _isRetrying = true;
        _retryCount++;
        isBuffering = false;
        toastString = S.current.retryplay;
      });
      LogUtil.i('重试播放: 第 $_retryCount 次');

      _retryTimer = Timer(const Duration(seconds: 2), () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) {
          LogUtil.i('重试中断: mounted=$mounted, isSwitchingChannel=$_isSwitchingChannel, isDisposing=$_isDisposing');
          setState(() => _isRetrying = false);
          return;
        }
        await _playVideo();
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
    // 添加空检查以防止 _currentChannel 或 urls 为 null
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
    });
    await _cleanupController(_playerController);
    LogUtil.i('播放结束，无更多源');
  }

  void _startNewSourceTimer() {
    _cleanupTimers();
    _retryTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo();
    });
  }

  /// 清理播放器控制器，确保资源释放
  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;

    _isDisposing = true;
    try {
      LogUtil.i('开始清理播放器');
      _cleanupTimers();
      controller.removeEventsListener(_videoListener);

      if (controller.isPlaying() ?? false) {
        await controller.pause();
        await controller.setVolume(0);
      }

      await _disposeStreamUrl();
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

  void _cleanupTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _playDurationTimer?.cancel();
    _playDurationTimer = null;
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
      String newParsedUrl = await StreamUrl(url).getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        _handleSourceSwitching();
        return;
      }
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与解析地址相同，无需重新预加载');
        return;
      }

      // 检查当前缓冲区状态，若恢复则取消预加载
      final position = _playerController?.videoPlayerController?.value.position ?? Duration.zero;
      final bufferedPosition = _playerController?.videoPlayerController?.value.buffered?.isNotEmpty == true
          ? _playerController!.videoPlayerController!.value.buffered!.last.end
          : position;
      final remainingBuffer = bufferedPosition - position;
      if (remainingBuffer.inSeconds > 9) {
        LogUtil.i('网络恢复，剩余缓冲 > 9 秒，取消预加载');
        _preCachedUrl = null;
        _isParsing = false;
        setState(() => _isRetrying = false);
        return;
      }

      _currentPlayUrl = newParsedUrl;
      LogUtil.i('重新解析成功: $newParsedUrl');

      final newSource = BetterPlayerConfig.createDataSource(
        isHls: _isHls,
        url: newParsedUrl,
      );

      if (_playerController != null) {
        await _playerController!.preCache(newSource);
        LogUtil.i('预缓存完成: $newParsedUrl');
        _preCachedUrl = newParsedUrl;
        _progressEnabled = false;
        _playDurationTimer?.cancel();
        _playDurationTimer = null;
        await _playerController!.setupDataSource(newSource);
        if (isPlaying) {
          await _playerController!.play();
          LogUtil.i('切换到新数据源并开始播放: $newParsedUrl');
          _preCachedUrl = null;
          _startPlayDurationTimer();
        } else {
          LogUtil.i('切换到新数据源但保持暂停状态: $newParsedUrl');
          _preCachedUrl = null;
        }
      } else {
        LogUtil.i('播放器控制器为空，无法切换');
        _handleSourceSwitching();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      _handleSourceSwitching();
    } finally {
      _isParsing = false;
      if (mounted) setState(() => _isRetrying = false);
      LogUtil.i('重新解析结束');
    }
  }

  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null) return;

    try {
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
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
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

  @override
  void initState() {
    super.initState();
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    _loadData();
    _extractFavoriteList();
  }

  /// 清理所有资源，确保无内存泄漏
  @override
  void dispose() {
    _isDisposing = true;
    _cleanupController(_playerController); // 清理主播放器
    _disposeStreamUrl(); // 清理流地址
    _pendingSwitch = null; // 清理切换队列
    super.dispose();
  }

  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        bool? isFirstInstall = SpUtil.getBool('is_first_install');
        bool isTV = context.watch<ThemeProvider>().isTV;

        String deviceType = isTV ? "TV" : "Other";

        if (isFirstInstall == null) {
          await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: deviceType);
          await SpUtil.putBool('is_first_install', true);
        } else {
          await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: channelName);
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
      CustomSnackBar.showSnackBar(context, S.current.channelnofavorite, duration: Duration(seconds: 4));
      return;
    }

    if (isChannelFavorite(actualChannelId)) {
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
      CustomSnackBar.showSnackBar(context, S.current.removefavorite, duration: Duration(seconds: 4));
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
      CustomSnackBar.showSnackBar(context, S.current.newfavorite, duration: Duration(seconds: 4));
      isFavoriteChanged = true;
    }

    if (isFavoriteChanged) {
      try {
        await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
        _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
        LogUtil.i('更新收藏列表: $_videoMap');
        if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: 4));
        LogUtil.logError('保存收藏失败', error);
      }
    }
  }

  Future<void> _parseData() async {
    try {
      if (_videoMap == null || _videoMap!.playList == null || _videoMap!.playList!.isEmpty) {
        LogUtil.e('_videoMap 无效');
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
