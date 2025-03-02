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

  // HLS 缓冲区检查相关变量
  Timer? _hlsCheckTimer; // HLS 检查定时器
  List<int> _recentRemainingBuffers = []; // 记录最近 3 次缓冲区剩余时间
  bool _isParsing = false; // 解析状态标志

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
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName');

    setState(() {
      toastString = '${_currentChannel!.title} - $sourceName  ${S.current.loading}';
      isPlaying = false;
      isBuffering = false;
    });

    try {
      if (_playerController != null && _isSwitchingChannel) {
        int waitAttempts = 0;
        const maxWaitAttempts = 3;
        while (_isSwitchingChannel && waitAttempts < maxWaitAttempts) {
          if (_playerController == null || !(_playerController!.isPlaying() ?? false)) {
            LogUtil.i('旧播放器已停止，提前退出等待');
            break;
          }
          LogUtil.i('等待旧播放器清理: 尝试 ${waitAttempts + 1}/$maxWaitAttempts');
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
      LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $isDirectAudio, HLS: $isHls');

      final dataSource = BetterPlayerConfig.createDataSource(
        url: parsedUrl,
        isHls: isHls,
      );
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

      // 设置默认音量为 0.6
      await _playerController?.setVolume(0.6);
      LogUtil.i('设置播放器音量为 0.6');

      await _playerController?.play();
      LogUtil.i('开始播放: $parsedUrl');

      if (isHls) {
        _startHlsCheckTimer(); // 启动 HLS 检查定时器
      }
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        setState(() => _isSwitchingChannel = false);
      }
    }
  }

  // HLS 检查定时器
  void _startHlsCheckTimer() {
    _hlsCheckTimer?.cancel();
    LogUtil.i('启动 HLS 检查定时器，每 5 秒检查一次');
    _hlsCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!mounted || _playerController == null || !_isHlsStream(_currentPlayUrl)) {
        LogUtil.i('停止 HLS 检查定时器，原因: mounted=$mounted, controller=${_playerController != null}, isHls=${_isHlsStream(_currentPlayUrl)}');
        timer.cancel();
        return;
      }
      _checkHlsStatus();
    });
  }

  void _checkHlsStatus() {
    final position = _playerController?.videoPlayerController?.value.position ?? Duration.zero;
    final bufferedPosition = _playerController?.videoPlayerController?.value.buffered?.last.end ?? Duration.zero;
    if (bufferedPosition >= position) {
      final remainingBuffer = bufferedPosition - position;
      int remainingSec = remainingBuffer.inSeconds.clamp(0, double.infinity.toInt());
      _recentRemainingBuffers.add(remainingSec);
      if (_recentRemainingBuffers.length > 3) _recentRemainingBuffers.removeAt(0);

      LogUtil.i('HLS 检查 - 当前播放位置: $position, 缓冲区末尾: $bufferedPosition, 剩余时间: $remainingSec 秒, 最近记录: $_recentRemainingBuffers');

      if (_recentRemainingBuffers.length == 3 &&
          _recentRemainingBuffers[0] > _recentRemainingBuffers[1] &&
          _recentRemainingBuffers[1] > _recentRemainingBuffers[2] &&
          remainingSec <= 10) {
        LogUtil.i('HLS 缓冲区连续 3 次减少且剩余 ≤ 10 秒，触发重新解析');
        _reparseAndSwitch();
      }
    } else {
      LogUtil.i('HLS 检查异常 - 缓冲区位置 $bufferedPosition 小于播放位置 $position');
    }
  }

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
            LogUtil.i('初始化完成，更新宽高比: $newAspectRatio');
          }
        }
        break;

      case BetterPlayerEventType.exception:
        if (_isParsing) {
          LogUtil.i('正在解析中，忽略异常: ${event.parameters?["error"] ?? "Unknown error"}');
          return;
        }
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "Unknown error"}');
        _playDurationTimer?.cancel();
        _retryPlayback();
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
        final buffered = event.parameters?["bufferedPosition"] as Duration?;
        if (buffered != null) {
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
            if (!isBuffering) toastString = 'HIDE_CONTAINER';
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
            final remainingTime = duration - position;
            if (remainingTime.inSeconds <= 20) {
              final nextUrl = _getNextVideoUrl();
              if (nextUrl != null && nextUrl != _nextVideoUrl) {
                _nextVideoUrl = nextUrl;
                LogUtil.i('非 HLS 剩余时间少于 20 秒，预加载下一源: $nextUrl');
                _preloadNextVideo(nextUrl);
              }
            }
            if (remainingTime.inSeconds <= 3 && _nextPlayerController != null) {
              LogUtil.i('非 HLS 剩余时间少于 3 秒，切换到预加载播放器');
              _switchToPreloadedPlayer(_playerController!);
            }
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!_isHlsStream(_currentPlayUrl) && _nextPlayerController != null && _nextVideoUrl != null) {
          LogUtil.i('非 HLS 播放结束，切换预加载播放器');
          _handleSourceSwitching(isFromFinished: true, oldController: _playerController);
        } else if (_isHlsStream(_currentPlayUrl)) {
          LogUtil.i('HLS 流异常结束，重试播放');
          _retryPlayback();
        } else {
          LogUtil.i('无更多源可播放');
          _handleNoMoreSources();
        }
        break;

      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.progress) {
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  void _startPlayDurationTimer() {
    _playDurationTimer?.cancel();
    _playDurationTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && isPlaying && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
        LogUtil.i('播放 60 秒，重置重试次数');
        _retryCount = 0;
        _playDurationTimer?.cancel();
        _playDurationTimer = null;
      }
    });
  }

  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel) return;
    _cleanupPreload();

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
      LogUtil.logError('预加载失败: $url', e, stackTrace);
    }
  }

  void _setupNextPlayerListener(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.setupDataSource:
        LogUtil.i('预加载数据源设置完成');
        break;
      case BetterPlayerEventType.exception:
        LogUtil.e('预加载异常: ${event.parameters?["error"] ?? "Unknown error"}');
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
    LogUtil.i('清理预加载资源');
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
            if (_playerController?.isPlaying() ?? false) {
              isPlaying = true;
              _startPlayDurationTimer();
            }
          });
        }
      });
    } else {
      LogUtil.i('重试次数达上限，切换下一源');
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
    });

    if (isFromFinished && oldController != null && _nextPlayerController != null) {
      LogUtil.i('非 HLS 播放结束，切换预加载播放器');
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
    LogUtil.i('播放结束，无更多源');
  }

  void _switchToPreloadedPlayer(BetterPlayerController oldController) async {
    if (_nextPlayerController == null) {
      LogUtil.i('预加载播放器未准备好');
      return;
    }

    LogUtil.i('切换预加载播放器: $_currentPlayUrl -> $_nextVideoUrl');
    setState(() => toastString = S.current.loading);

    try {
      await oldController.pause();
      oldController.videoPlayerController?.setVolume(0);
      await Future.delayed(const Duration(milliseconds: 300));

      setState(() {
        _playerController = _nextPlayerController;
        _nextPlayerController = null;
        _currentPlayUrl = _nextVideoUrl;
        _nextVideoUrl = null;
        _shouldUpdateAspectRatio = true;
        _recentRemainingBuffers.clear();
      });

      _playerController?.addEventsListener(_videoListener);
      final currentPosition = oldController.videoPlayerController?.value.position ?? Duration.zero;
      LogUtil.i('切换播放器，定位至: $currentPosition');
      await _playerController?.seekTo(currentPosition);
      await _playerController?.play();

      oldController.dispose();
      LogUtil.i('切换完成');
      setState(() => toastString = 'HIDE_CONTAINER');
    } catch (e, stackTrace) {
      LogUtil.logError('切换预加载播放器失败', e, stackTrace);
      _handleSourceSwitching();
    }
  }

  void _startNewSourceTimer() {
    _cleanupTimers();
    _retryTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo();
    });
  }

  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;

    _isDisposing = true;
    try {
      LogUtil.i('开始清理播放器');
      setState(() {
        _cleanupTimers();
        _isAudio = false;
        _playerController = null;
        _recentRemainingBuffers.clear();
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
      LogUtil.i('播放器清理完成');
    } catch (e, stackTrace) {
      LogUtil.logError('清理播放器失败', e, stackTrace);
    } finally {
      if (mounted) setState(() => _isDisposing = false);
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
    _hlsCheckTimer?.cancel();
    _hlsCheckTimer = null;
    _timeoutActive = false;
  }

  Future<void> _reparseAndSwitch() async {
    if (_isRetrying || _isSwitchingChannel || _isDisposing || _isParsing) {
      LogUtil.i('重新解析被阻止: _isRetrying=$_isRetrying, _isSwitchingChannel=$_isSwitchingChannel, _isDisposing=$_isDisposing, _isParsing=$_isParsing');
      return;
    }

    _isParsing = true;
    setState(() => _isRetrying = true);
    LogUtil.i('HLS 重新解析开始');

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
        LogUtil.i('新地址与当前地址相同，切换下一源');
        _handleSourceSwitching();
        return;
      }
      _currentPlayUrl = newParsedUrl;
      LogUtil.i('重新解析成功: $newParsedUrl');
      await _preloadNextVideo(newParsedUrl);
      if (_nextPlayerController != null && mounted) {
        LogUtil.i('重新解析完成，切换新播放器');
        _switchToPreloadedPlayer(_playerController!);
      } else {
        LogUtil.i('预加载未完成，无法切换');
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
