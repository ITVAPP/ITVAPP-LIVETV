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

  // === 修改部分开始：新增 HLS 缓冲区剩余时间监控变量 ===
  List<int> _recentRemainingBuffers = []; // 记录最近 3 次 HLS 缓冲区剩余时间
  bool _isParsing = false; // 解析状态标志，避免重复解析
  Duration? _lastBufferedPosition; // 上次缓冲区位置，用于日志记录
  // === 修改部分结束 ===

  bool _isRetrying = false;
  Timer? _retryTimer;
  String toastString = S.current.loading;
  PlaylistModel? _videoMap;
  PlayModel? _currentChannel;
  int _sourceIndex = 0;
  BetterPlayerController? _playerController;
  BetterPlayerController? _nextPlayerController;
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
  String? _nextVideoUrl;

  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  ValueKey<int>? _drawerRefreshKey;
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();
  bool _isAudio = false;
  Timer? _playDurationTimer;

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

  Future<void> _playVideo() async {
    if (_currentChannel == null) return;

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);

    setState(() {
      toastString = '${_currentChannel!.title} - $sourceName  ${S.current.loading}';
      isPlaying = false;
      isBuffering = false;
    });

    try {
      if (_playerController != null && _isSwitchingChannel) {
        int waitAttempts = 0;
        final maxWaitAttempts = 3;
        while (_isSwitchingChannel && waitAttempts < maxWaitAttempts) {
          if (_playerController == null || !(_playerController!.isPlaying() ?? false)) {
            LogUtil.i('旧播放器已停止或清理，提前退出等待');
            break;
          }
          LogUtil.i('等待上一次播放器清理: 尝试 ${waitAttempts + 1}/$maxWaitAttempts');
          await Future.delayed(const Duration(milliseconds: 1000));
          waitAttempts++;
        }
        if (_isSwitchingChannel && waitAttempts >= maxWaitAttempts) {
          LogUtil.e('等待超时，强制清理旧播放器');
          await _cleanupController(_playerController);
          _isSwitchingChannel = false;
        }
      }

      setState(() => _isSwitchingChannel = true);

      await _cleanupController(_playerController);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('开始解析播放地址: $url');
      String parsedUrl = await StreamUrl(url).getStreamUrl();
      _currentPlayUrl = parsedUrl;

      if (parsedUrl == 'ERROR') {
        LogUtil.e('播放地址解析失败: $url');
        setState(() {
          toastString = S.current.vpnplayError;
          _isSwitchingChannel = false;
        });
        return;
      }

      bool isDirectAudio = _checkIsAudioStream(parsedUrl);
      setState(() => _isAudio = isDirectAudio);

      final bool isHls = _isHlsStream(parsedUrl);
      LogUtil.i('准备播放：$parsedUrl ,音频：$isDirectAudio ,是否为HLS流：$isHls');

      final dataSource = BetterPlayerConfig.createDataSource(url: parsedUrl, isHls: isHls);
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener,
        isHls: isHls,
      );

      BetterPlayerController newController = BetterPlayerController(betterPlayerConfiguration);

      await newController.setupDataSource(dataSource);
      LogUtil.i('播放器数据源设置完成: $parsedUrl');

      setState(() {
        _playerController = newController;
        _timeoutActive = false;
      });

      await _playerController?.play();
      LogUtil.i('开始播放: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('播放出错', e, stackTrace);
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        setState(() => _isSwitchingChannel = false);
      }
    }
  }

  // === 修改部分开始：优化播放器监听方法 ===
  void _videoListener(BetterPlayerEvent event) {
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
            LogUtil.i('播放器初始化完成，更新宽高比为: $newAspectRatio');
          }
        }
        break;

      case BetterPlayerEventType.exception:
        if (_isParsing) {
          LogUtil.i('正在解析中，忽略异常: ${event.parameters?["error"] ?? "Unknown error"}');
          return;
        }
        final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
        LogUtil.e('监听到播放器错误: $errorMessage');
        _playDurationTimer?.cancel();
        _retryPlayback();
        break;

      case BetterPlayerEventType.bufferingStart:
        LogUtil.i('播放卡住，开始缓冲');
        setState(() {
          isBuffering = true;
          toastString = S.current.loading;
        });
        _startTimeoutCheck();
        break;

      case BetterPlayerEventType.bufferingUpdate:
        final buffered = event.parameters?["bufferedPosition"] as Duration?;
        if (buffered != null) {
          _lastBufferedPosition = buffered;
          LogUtil.i('缓冲区更新: $buffered');
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
            if (!isBuffering) {
              toastString = 'HIDE_CONTAINER';
            }
          });
          _startPlayDurationTimer();
          LogUtil.i('播放开始');
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          setState(() {
            isPlaying = false;
            toastString = S.current.playpause;
          });
          _playDurationTimer?.cancel();
          LogUtil.i('播放暂停');
        }
        break;

      case BetterPlayerEventType.progress:
        final position = event.parameters?["progress"] as Duration?;
        final duration = event.parameters?["duration"] as Duration?;
        if (position != null && duration != null) {
          final bool isHls = _isHlsStream(_currentPlayUrl);
          if (!isHls && duration.inSeconds > 0) {
            // 非 HLS 流：提前 20 秒预加载，剩余 3 秒切换
            final remainingTime = duration - position;
            if (remainingTime.inSeconds <= 20) {
              final nextUrl = _getNextVideoUrl();
              if (nextUrl != null && nextUrl != _nextVideoUrl) {
                _nextVideoUrl = nextUrl;
                LogUtil.i('非 HLS 剩余时间少于 20 秒，开始预加载下一源: $nextUrl');
                _preloadNextVideo(nextUrl);
              }
            }
            if (remainingTime.inSeconds <= 3 && _nextPlayerController != null) {
              LogUtil.i('非 HLS 剩余时间少于 3 秒，切换到预加载播放器');
              _switchToPreloadedPlayer(_playerController!);
            }
          } else if (isHls) {
            // HLS 流：检查缓冲区剩余时间，连续减少至 20 秒触发重新解析
            final bufferedPosition = _playerController?.videoPlayerController?.value.buffered?.last.end;
            if (bufferedPosition != null) {
              final remainingBuffer = bufferedPosition - position;
              int remainingSec = remainingBuffer.inSeconds;
              _recentRemainingBuffers.add(remainingSec);
              if (_recentRemainingBuffers.length > 3) _recentRemainingBuffers.removeAt(0);
              LogUtil.i('HLS 当前缓冲区剩余时间: $remainingSec 秒，最近记录: $_recentRemainingBuffers');
              if (_recentRemainingBuffers.length == 3 &&
                  _recentRemainingBuffers[0] > _recentRemainingBuffers[1] &&
                  _recentRemainingBuffers[1] > _recentRemainingBuffers[2] &&
                  remainingSec <= 20) {
                LogUtil.i('HLS 缓冲区连续减少且剩余 ≤ 20 秒，触发重新解析');
                _reparseAndSwitch();
              }
            }
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!_isHlsStream(_currentPlayUrl) && _nextPlayerController != null && _nextVideoUrl != null) {
          LogUtil.i('非 HLS 播放结束，切换到预加载播放器');
          _handleSourceSwitching(isFromFinished: true, oldController: _playerController);
        } else if (_isHlsStream(_currentPlayUrl)) {
          LogUtil.i('HLS 流异常结束，尝试重试播放');
          _retryPlayback();
        } else {
          LogUtil.i('无更多源可播放');
          _handleNoMoreSources();
        }
        break;

      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.progress) {
          LogUtil.i('未处理的事件类型: ${event.betterPlayerEventType}');
        }
        break;
    }
  }
  // === 修改部分结束 ===

  void _startPlayDurationTimer() {
    _playDurationTimer?.cancel();
    _playDurationTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && isPlaying && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
        LogUtil.i('媒体已连续播放60秒，重置重试次数');
        _retryCount = 0;
        _playDurationTimer?.cancel();
        _playDurationTimer = null;
      }
    });
  }

  Future<void> handleFinishedEvent() async {
    if (!_isHlsStream(_currentPlayUrl) && _nextPlayerController != null && _nextVideoUrl != null) {
      _handleSourceSwitching(isFromFinished: true, oldController: _playerController);
    } else if (_isHlsStream(_currentPlayUrl)) {
      _retryPlayback();
    } else {
      await _handleNoMoreSources();
    }
  }

  // === 修改部分开始：优化预加载方法 ===
  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel) return;
    _cleanupPreload();

    try {
      LogUtil.i('开始预加载视频: $url');
      String parsedUrl = await StreamUrl(url).getStreamUrl();
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析URL失败: $url');
        return;
      }
      LogUtil.i('预加载解析完成: $parsedUrl');

      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl),
        url: parsedUrl,
      );

      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _setupNextPlayerListener,
        isHls: _isHlsStream(parsedUrl),
      );

      final preloadController = BetterPlayerController(betterPlayerConfiguration);
      await preloadController.setupDataSource(nextSource);
      LogUtil.i('预加载数据源设置完成: $parsedUrl');

      _nextPlayerController = preloadController;
      _nextVideoUrl = url;
    } catch (e, stackTrace) {
      LogUtil.logError('预加载异常: $url', e, stackTrace);
    }
  }
  // === 修改部分结束 ===

  void _setupNextPlayerListener(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.setupDataSource:
        LogUtil.i('预加载数据源设置完成');
        break;
      case BetterPlayerEventType.exception:
        final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
        LogUtil.e('预加载发生错误：$errorMessage');
        _cleanupPreload();
        break;
      default:
        break;
    }
  }

  void _cleanupPreload() {
    _nextPlayerController?.dispose();
    _nextPlayerController = null;
    _nextVideoUrl = null;
    LogUtil.i('清理预加载资源完成');
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
        LogUtil.e('超时检查：播放器控制器无效');
        _handleSourceSwitching();
        _timeoutActive = false;
        return;
      }

      if (isBuffering) {
        LogUtil.e('缓冲超时，切换下一个源');
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

      LogUtil.i('尝试第 ${_retryCount} 次重试播放');

      _retryTimer = Timer(const Duration(seconds: 2), () async {
        if (!mounted || _isSwitchingChannel || _isDisposing) {
          LogUtil.i('重试被阻断，条件：mounted=$mounted, isSwitchingChannel=$_isSwitchingChannel, isDisposing=$_isDisposing');
          setState(() => _isRetrying = false);
          return;
        }
        await _playVideo();
        if (mounted) {
          setState(() {
            _isRetrying = false;
            if (_playerController?.isPlaying() ?? false) {
              isPlaying = true;
              _startPlayDurationTimer();
            }
          });
        }
      });
    } else {
      LogUtil.i('重试次数达到上限，切换到下一源');
      _handleSourceSwitching();
    }
  }

  String? _getNextVideoUrl() {
    final List<String>? urls = _currentChannel?.urls;
    if (urls == null || urls.isEmpty) return null;
    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) return null;
    return urls[nextSourceIndex];
  }

  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;

    _cleanupTimers();

    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      LogUtil.i('无更多视频源可切换');
      _handleNoMoreSources();
      return;
    }

    setState(() {
      _sourceIndex++;
      _isRetrying = false;
      _retryCount = 0;
      isBuffering = false;
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
    });

    if (isFromFinished && oldController != null && _nextPlayerController != null) {
      LogUtil.i('非 HLS 播放完毕，直接切换到预加载播放器');
      _switchToPreloadedPlayer(oldController);
    } else {
      LogUtil.i('切换到下一源: $nextUrl');
      _startNewSourceTimer();
    }
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
    LogUtil.i('无更多源，播放结束');
  }

  // === 修改部分开始：优化切换到预加载播放器方法 ===
  void _switchToPreloadedPlayer(BetterPlayerController oldController) async {
    if (_nextPlayerController == null) {
      LogUtil.w('预加载播放器未准备好，无法切换');
      return;
    }

    LogUtil.i('开始切换到预加载播放器，当前URL: $_currentPlayUrl -> $_nextVideoUrl');
    setState(() {
      toastString = S.current.loading; // 显示加载提示
    });

    try {
      await oldController.pause();
      oldController.videoPlayerController?.setVolume(0); // 静音减少中断感
      await Future.delayed(const Duration(milliseconds: 300)); // 延迟销毁旧播放器

      setState(() {
        _playerController = _nextPlayerController;
        _nextPlayerController = null;
        _currentPlayUrl = _nextVideoUrl;
        _nextVideoUrl = null;
        _shouldUpdateAspectRatio = true;
        _recentRemainingBuffers.clear(); // 重置 HLS 缓冲记录
      });

      _playerController?.addEventsListener(_videoListener);
      final currentPosition = oldController.videoPlayerController?.value.position ?? Duration.zero;
      LogUtil.i('切换播放器，保持位置: $currentPosition');
      await _playerController?.seekTo(currentPosition);
      await _playerController?.play();

      oldController.dispose();
      LogUtil.i('切换到新播放器完成，隐藏加载提示');
      setState(() => toastString = 'HIDE_CONTAINER');
    } catch (e, stackTrace) {
      LogUtil.logError('切换到预加载播放器出错', e, stackTrace);
      _handleSourceSwitching();
    }
  }
  // === 修改部分结束 ===

  void _startNewSourceTimer() {
    _cleanupTimers();

    _retryTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo();
    });
  }

  // === 修改部分开始：优化清理控制器方法 ===
  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;

    _isDisposing = true;

    try {
      LogUtil.i('开始清理播放器控制器');
      setState(() {
        _cleanupTimers();
        _isAudio = false;
        _playerController = null;
        _recentRemainingBuffers.clear(); // 清理 HLS 缓冲记录
      });

      controller.removeEventsListener(_videoListener);
      if (controller.isPlaying() ?? false) {
        await controller.pause();
        controller.videoPlayerController?.setVolume(0);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (_streamUrl != null) {
        await _streamUrl!.dispose();
        _streamUrl = null;
      }

      controller.videoPlayerController?.dispose();
      await Future.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      _nextPlayerController?.dispose();
      _nextPlayerController = null;
      _nextVideoUrl = null;
      LogUtil.i('播放器控制器清理完成');
    } catch (e, stackTrace) {
      LogUtil.logError('释放播放器资源时出错', e, stackTrace);
    } finally {
      if (mounted) {
        setState(() => _isDisposing = false);
      }
    }
  }
  // === 修改部分结束 ===

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

  // === 修改部分开始：优化重新解析方法 ===
  Future<void> _reparseAndSwitch() async {
    if (_isRetrying || _isSwitchingChannel || _isDisposing || _isParsing) {
      LogUtil.i('重新解析被阻止，当前状态: _isRetrying=$_isRetrying, _isSwitchingChannel=$_isSwitchingChannel, _isDisposing=$_isDisposing, _isParsing=$_isParsing');
      return;
    }

    _isParsing = true;
    setState(() => _isRetrying = true);
    LogUtil.i('HLS 开始重新解析当前源');

    try {
      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      String newParsedUrl = await StreamUrl(url).getStreamUrl();
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析地址失败: $url');
        _handleSourceSwitching();
        return;
      }
      _currentPlayUrl = newParsedUrl;
      LogUtil.i('重新解析成功，新地址: $newParsedUrl');
      await _preloadNextVideo(newParsedUrl);
      if (_nextPlayerController != null && mounted) {
        LogUtil.i('重新解析完成，直接切换到新播放器');
        _switchToPreloadedPlayer(_playerController!);
      } else {
        LogUtil.w('预加载未完成，无法切换');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析出错', e, stackTrace);
      _handleSourceSwitching();
    } finally {
      _isParsing = false;
      if (mounted) setState(() => _isRetrying = false);
      LogUtil.i('重新解析流程结束');
    }
  }
  // === 修改部分结束 ===

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

      await _playVideo();

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
      LogUtil.e('未找到有效的视频源');
      return;
    }

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      setState(() {
        _sourceIndex = selectedIndex;
        _isRetrying = false;
        _retryCount = 0;
      });
      _playVideo();
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

  @override
  void dispose() {
    _cleanupTimers();
    _isRetrying = false;
    _isAudio = false;
    WakelockPlus.disable();
    _isDisposing = true;
    _cleanupController(_playerController);
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
        LogUtil.logError('发送流量统计时发生错误', e, stackTrace);
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
      LogUtil.e('传入的播放列表无效');
      setState(() => toastString = S.current.getDefaultError);
      return;
    }

    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载播放列表时出错', e, stackTrace);
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
          _playVideo();
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
      LogUtil.logError('提取频道时出错', e, stackTrace);
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
        LogUtil.i('修改收藏列表后的播放列表: $_videoMap');
        if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: 4));
        LogUtil.logError('收藏状态保存失败', error);
      }
    }
  }

  Future<void> _parseData() async {
    try {
      if (_videoMap == null || _videoMap!.playList == null || _videoMap!.playList!.isEmpty) {
        LogUtil.e('当前 _videoMap 无效');
        setState(() => toastString = S.current.getDefaultError);
        return;
      }
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('处理播放列表时出错', e, stackTrace);
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
