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
  final PlaylistModel m3uData; // 接收上个页面的 PlaylistModel 数据
  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  // 超时重试次数
  static const int defaultMaxRetries = 1;
  
  // 超时检测的时间
  static const int defaultTimeoutSeconds = 32;
  
  // 重试相关的状态管理
  bool _isRetrying = false;
  Timer? _retryTimer;
  
  // 存储加载状态的提示文字
  String toastString = S.current.loading;

  // 视频播放列表的数据模型
  PlaylistModel? _videoMap;

  // 当前播放的频道数据模型
  PlayModel? _currentChannel;

  // 当前选中的视频源索引
  int _sourceIndex = 0;

  // 视频播放器控制器
  BetterPlayerController? _playerController;
  
  // 预加载控制器
  BetterPlayerController? _nextPlayerController;

  // 是否处于缓冲状态
  bool isBuffering = false;

  // 是否正在播放
  bool isPlaying = false;

  // 视频的宽高比
  double aspectRatio = 1.78;

  // 标记侧边抽屉（频道选择）是否打开
  bool _drawerIsOpen = false;

  // 重试次数计数器
  int _retryCount = 0;

  // 等待超时检测
  bool _timeoutActive = false;

  // 是否处于释放状态
  bool _isDisposing = false;

  // 切换时的竞态条件
  bool _isSwitchingChannel = false;

  // 标记是否需要更新宽高比
  bool _shouldUpdateAspectRatio = true;

  // 声明变量，存储 StreamUrl 类的实例
  StreamUrl? _streamUrl;

  // 当前播放URL
  String? _currentPlayUrl;

  // 下一个视频地址
  String? _nextVideoUrl;

  // 收藏列表相关
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  
  // 抽屉刷新键
  ValueKey<int>? _drawerRefreshKey;

  // 流量统计
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();

  // 音频检测状态
  bool _isAudio = false;

  // 计时器，用于检测连续播放60秒
  Timer? _playDurationTimer;

  // 将音频流检查提取为独立方法
  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    final lowercaseUrl = url.toLowerCase();
    return !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
  }

  // 将HLS流检查提取为独立方法
  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const formats = [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'
    ];
    return !formats.any(url.toLowerCase().contains);
  }
  
  /// 播放前解析频道的视频源 
  Future<void> _playVideo() async {
    if (_currentChannel == null) return;
    
    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    
    setState(() {
      toastString = '${_currentChannel!.title} - $sourceName  ${S.current.loading}';
      isPlaying = false;
      isBuffering = false;
    });

    try {
      // 检查上一次播放是否完成
      if (_playerController != null && _isSwitchingChannel) {
        int waitAttempts = 0;
        final maxWaitAttempts = 3;
        while (_isSwitchingChannel && waitAttempts < maxWaitAttempts) {
          // 提前退出条件，检查播放器是否已停止或清理
          if (_playerController == null || !(_playerController!.isPlaying() ?? false)) {
            LogUtil.i('旧播放器已停止或清理，提前退出等待');
            break;
          }
          LogUtil.i('等待上一次播放器清理: 尝试 ${waitAttempts + 1}/$maxWaitAttempts');
          await Future.delayed(const Duration(milliseconds: 1000));
          waitAttempts++;
        }
        
        // 超时后强制清理并重置状态
        if (_isSwitchingChannel && waitAttempts >= maxWaitAttempts) {
          LogUtil.e('等待超时，强制清理旧播放器');
          await _cleanupController(_playerController);
          _isSwitchingChannel = false; // 确保超时后状态重置
        }
      }
      
      // 在清理旧播放器前标记切换状态
      setState(() => _isSwitchingChannel = true);
      
      // 清理旧播放器
      await _cleanupController(_playerController);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      
      // 使用局部变量解析URL，避免类成员冗余
      String url = _currentChannel!.urls![_sourceIndex].toString();
      String parsedUrl = await StreamUrl(url).getStreamUrl();
      _currentPlayUrl = parsedUrl;
      
      if (parsedUrl == 'ERROR') {
        setState(() {
          toastString = S.current.vpnplayError;
          _isSwitchingChannel = false;
        });
        return;
      }

      bool isDirectAudio = _checkIsAudioStream(parsedUrl);
      setState(() => _isAudio = isDirectAudio);
      
      final bool isHls = _isHlsStream(parsedUrl);
      LogUtil.i('准备播放：$parsedUrl ,音频：$isDirectAudio ,是否为hls流：$isHls');

      final dataSource = BetterPlayerConfig.createDataSource(url: parsedUrl, isHls: isHls);
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener,
        isHls: isHls,
      );
      
      BetterPlayerController newController = BetterPlayerController(betterPlayerConfiguration);

      try {
        await newController.setupDataSource(dataSource);
      } catch (e, stackTrace) {
        LogUtil.logError('初始化出错', e, stackTrace);
        _handleSourceSwitching();
        return; 
      }
      
      setState(() {
        _playerController = newController;
        _timeoutActive = false;
      });
      
      await _playerController?.play();
    } catch (e, stackTrace) {
      LogUtil.logError('播放出错', e, stackTrace);
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        setState(() => _isSwitchingChannel = false);
      }
    }
  }

  /// 播放器监听方法（修改部分）
  void _videoListener(BetterPlayerEvent event) {
    // 修改：移除 _isRetrying 从全局条件中，确保重试时的播放事件可以处理
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
          }
        }
        break;

      case BetterPlayerEventType.exception:
        // 修改：在异常事件中保留 _isRetrying 检查，避免重试期间重复处理旧异常
        if (_isRetrying || !_isSwitchingChannel) {
          final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
          LogUtil.e('监听到播放器错误：$errorMessage');
          _playDurationTimer?.cancel();
          _retryPlayback();
        }
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
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) { 
          setState(() {
            isPlaying = false;
            toastString = S.current.playpause;
          });
          _playDurationTimer?.cancel();
        }
        break;

      case BetterPlayerEventType.progress:
        final position = event.parameters?["progress"] as Duration?;
        final duration = event.parameters?["duration"] as Duration?;
        if (position != null && duration != null && !_isHlsStream(_currentPlayUrl) && duration.inSeconds > 0) {
          final remainingTime = duration - position;
          if (remainingTime.inSeconds <= 15) {
            final nextUrl = _getNextVideoUrl();
            if (nextUrl != null && nextUrl != _nextVideoUrl) {
              _nextVideoUrl = nextUrl;
              _preloadNextVideo(nextUrl);
            }
          }
        }
        break;
        
      case BetterPlayerEventType.finished:
        handleFinishedEvent();
        break;
        
      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.progress) {
          LogUtil.i('未处理的事件类型: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  /// 启动播放时长计时器
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

  /// 处理播放结束事件
  Future<void> handleFinishedEvent() async {
    if (!_isHlsStream(_currentPlayUrl) && _nextPlayerController != null && _nextVideoUrl != null) {
      _handleSourceSwitching(isFromFinished: true, oldController: _playerController);
    } else if (_isHlsStream(_currentPlayUrl)) {
      _retryPlayback();
    } else {
      await _handleNoMoreSources();
    }
  }

  /// 预加载方法
  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel) return;
    _cleanupPreload();
    
    try {
      _streamUrl = StreamUrl(url);
      String parsedUrl = await _streamUrl!.getStreamUrl();
      
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析URL失败');
        return;
      }

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
      
      _nextPlayerController = preloadController;
      _nextVideoUrl = url;
    } catch (e, stackTrace) {
      LogUtil.logError('预加载异常', e, stackTrace);
    }
  }

  /// 预加载控制器的事件监听
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
        
  /// 清理预加载资源
  void _cleanupPreload() {
    _nextPlayerController?.dispose();
    _nextPlayerController = null;
    _nextVideoUrl = null;
  }

  /// 超时检测方法
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

  /// 重试播放方法，用于重新尝试播放失败的视频（修改部分）
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
            // 检查播放器状态
            if (_playerController?.isPlaying() ?? false) {
              isPlaying = true;
              _startPlayDurationTimer();
            }
          });
        }
      });
    } else {
      _handleSourceSwitching();
    }
  }

  /// 获取下一个视频地址，返回 null 表示没有更多源
  String? _getNextVideoUrl() {
    final List<String>? urls = _currentChannel?.urls;
    if (urls == null || urls.isEmpty) return null;
    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) return null;
    return urls[nextSourceIndex];
  }

  /// 视频源切换的核心逻辑
  void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
    if (_isRetrying || _isDisposing) return;
    
    _cleanupTimers();
    
    final nextUrl = _getNextVideoUrl();
    if (nextUrl == null) {
      _handleNoMoreSources(); 
      return;
    }

    // 状态更新
    setState(() {
      _sourceIndex++;
      _isRetrying = false;
      _retryCount = 0;
      isBuffering = false;
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
    });

    _startNewSourceTimer();
  }

  /// 处理没有更多源的情况
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
  }

  /// 切换到预加载的播放器
  void _switchToPreloadedPlayer(BetterPlayerController oldController) async {
    setState(() {
      _playerController = _nextPlayerController;
      _nextPlayerController = null;
      _currentPlayUrl = _nextVideoUrl;
      _nextVideoUrl = null;
      _shouldUpdateAspectRatio = true;
    });

    try {
      _playerController?.addEventsListener(_videoListener);
      await _playerController?.play();
    } catch (e, stackTrace) {
      LogUtil.logError('切换到预加载视频时出错', e, stackTrace);
      _handleSourceSwitching();
    }
    
    oldController.dispose();
  }

  /// 启动新源的计时器
  void _startNewSourceTimer() {
    _cleanupTimers();
    
    _retryTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo();
    });
  }

  /// 清理控制器资源（合并原 _disposePlayer 和 _cleanupPreload 的逻辑）
  Future<void> _cleanupController(BetterPlayerController? controller) async {
    if (controller == null) return;
    
    _isDisposing = true;
    
    try {
      setState(() {
        _cleanupTimers();
        _isAudio = false;
        _playerController = null;
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
      _nextPlayerController?.dispose(); // 同时清理预加载控制器
      _nextPlayerController = null;
      _nextVideoUrl = null;
    } catch (e, stackTrace) {
      LogUtil.logError('释放播放器资源时出错', e, stackTrace);
    } finally {
      if (mounted) {
        setState(() => _isDisposing = false);
      }
    }
  }

  /// 释放 StreamUrl 实例
  Future<void> _disposeStreamUrl() async {
    if (_streamUrl != null) {
      await _streamUrl!.dispose();
      _streamUrl = null;
    }
  }

  /// 清理所有计时器
  void _cleanupTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _playDurationTimer?.cancel();
    _playDurationTimer = null;
    _timeoutActive = false;
  }

  /// 处理频道切换操作
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

  /// 切换视频源方法（手动按钮切换）
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

  /// 处理返回按键逻辑，返回值为 true 表示退出应用，false 表示不退出
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

  /// 初始化方法
  @override
  void initState() {
    super.initState();
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    _loadData();
    _extractFavoriteList();
  }

  /// 清理所有资源
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

  /// 发送页面访问统计数据
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

  /// 异步加载视频数据
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

  /// 处理播放列表
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

  /// 从播放列表中动态提取第一个有效频道
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

  /// 从传递的播放列表中提取"我的收藏"部分
  void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      favoriteList = {Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!};
    } else {
      favoriteList = {Config.myFavoriteKey: <String, Map<String, PlayModel>>{}};
    }
  }

  // 获取当前频道的分组名字
  String getGroupName(String channelId) => _currentChannel?.group ?? '';

  // 获取当前频道名字
  String getChannelName(String channelId) => _currentChannel?.title ?? '';

  // 获取线路名称
  String _getSourceDisplayName(String url, int index) {
    if (url.contains('\$')) return url.split('\$')[1].trim();
    return S.current.lineIndex(index + 1);
  }

  // 获取当前频道的播放地址列表
  List<String> getPlayUrls(String channelId) => _currentChannel?.urls ?? [];

  // 检查当前频道是否已收藏
  bool isChannelFavorite(String channelId) {
    String groupName = getGroupName(channelId);
    String channelName = getChannelName(channelId);
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
  }

  // 添加或取消收藏
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

  // 使用 _videoMap，避免从本地读取
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
