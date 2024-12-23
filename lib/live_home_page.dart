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
import 'channel_drawer_page.dart';
import 'mobile_video_widget.dart';
import 'table_video_widget.dart';
import 'tv/tv_page.dart';
import 'util/env_util.dart';
import 'util/log_util.dart';
import 'util/m3u_util.dart';
import 'util/stream_url.dart';
import 'util/dialog_util.dart';
import 'util/custom_snackbar.dart';
import 'util/channel_util.dart';
import 'util/traffic_analytics.dart';
import 'widget/better_player_controls.dart';
import 'widget/empty_page.dart';
import 'widget/show_exit_confirm.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

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
  static const int defaultTimeoutSeconds = 28;
  
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
  
  // 检查是否为音频流
bool _checkIsAudioStream(String? url) {
  if (url == null || url.isEmpty) return false;
  final lowercaseUrl = url.toLowerCase();
  // 先检查是否为视频格式
  if (lowercaseUrl.contains('.mp4') || 
      lowercaseUrl.contains('.mkv') ||
      lowercaseUrl.contains('.avi') ||
      lowercaseUrl.contains('.mov') ||
      lowercaseUrl.contains('.wmv') ||
      lowercaseUrl.contains('.flv')) {
    return false;
  }
  // 如果不是视频，则检查是否为音频格式
  return lowercaseUrl.contains('.mp3') || 
         lowercaseUrl.contains('.aac') || 
         lowercaseUrl.contains('.m4a') ||
         lowercaseUrl.contains('.ogg') ||
         lowercaseUrl.contains('.wav');
}
  
  // 判断是否是HLS流
  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.contains('.m3u');
  }
  
/// 播放前解析频道的视频源 
Future<void> _playVideo() async {
    if (_currentChannel == null) return;

    setState(() {
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
        isPlaying = false;     // 重置播放状态
        isBuffering = false;   // 重置缓冲状态
        _isSwitchingChannel = false;  // 重置频道状态
    });

    // 先释放旧播放器，再设置新播放器
    await _disposePlayer();
    // 添加短暂延迟确保资源完全释放
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
        // 解析URL
        String url = _currentChannel!.urls![_sourceIndex].toString();
        _streamUrl = StreamUrl(url); 
        String parsedUrl = await _streamUrl!.getStreamUrl();
        _currentPlayUrl = parsedUrl;  // 保存解析后的地址
        
        if (parsedUrl == 'ERROR') {  // 如果解析返回错误就不需要重试
            setState(() {
                toastString = S.current.vpnplayError;
            });
            return;
        }

        // 检查是否为音频URL
        bool isDirectAudio = _checkIsAudioStream(parsedUrl);
        setState(() {
          _isAudio = isDirectAudio;
        });
        
        // 检测是否为hls流
        final bool isHls = _isHlsStream(parsedUrl);
        
        if (_isSwitchingChannel) return;  // 如果切换频道的状态改变则停止继续
        
        LogUtil.i('准备播放：$parsedUrl ,音频：$isDirectAudio ,是否为hls流：$isHls');

        // 使用配置工具类创建数据源
        final dataSource = BetterPlayerConfig.createDataSource(
          url: parsedUrl,
          isHls: isHls,
        );

        // 创建播放器配置
        final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
          eventListener: _videoListener,
          isHls: isHls, 
        );
        
        // 创建播放器控制器
        BetterPlayerController newController = BetterPlayerController(
          betterPlayerConfiguration,
        );

        try {
            await newController.setupDataSource(dataSource);
        } catch (e, stackTrace) {
            _handleSourceSwitching();
            LogUtil.logError('初始化出错', e, stackTrace);
            return; 
        }

       if (_isSwitchingChannel) return;
        // 设置新的控制器
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
            setState(() {
                _isSwitchingChannel = false;
            });
        }
    }
}

/// 播放器监听方法
void _videoListener(BetterPlayerEvent event) {
    // 统一的前置条件检查
    if (!mounted || _playerController == null || _isDisposing || _isRetrying) return;

    switch (event.betterPlayerEventType) {
        // 初始化完成时，更新视频的宽高比
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

        // 当事件类型为异常时，调用错误处理函数
        case BetterPlayerEventType.exception:
            if (!_isSwitchingChannel) {
                final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
                LogUtil.e('监听到播放器错误：$errorMessage');
                _retryPlayback();
            }
            break;

        // 当事件类型为缓冲开始时
        case BetterPlayerEventType.bufferingStart:
            LogUtil.i('播放卡住，开始缓冲');
            setState(() {
                isBuffering = true; 
                toastString = S.current.loading;
            });
            _startTimeoutCheck();  // 启动超时检测
            break;

        // 当事件类型为缓冲更新时
        case BetterPlayerEventType.bufferingUpdate:
            break;

        // 当事件类型为缓冲结束时
        case BetterPlayerEventType.bufferingEnd:
            LogUtil.i('缓冲结束');
            setState(() {
                isBuffering = false;
                toastString = 'HIDE_CONTAINER';
            });
            _cleanupTimers();  // 缓冲结束时清理超时检测
            break;

        // 当事件类型为播放时
        case BetterPlayerEventType.play:
            if (!isPlaying) { // 避免重复设置
                setState(() {
                    isPlaying = true;
                    if (!isBuffering) {
                        toastString = 'HIDE_CONTAINER';
                    }
                });
            }
            break;

        // 当事件类型为暂停时
        case BetterPlayerEventType.pause:
            if (isPlaying) { // 避免重复设置
                setState(() {
                    isPlaying = false;
                    toastString = S.current.playpause; // 更新提示状态
                });
            }
            break;

        // 监听播放时间
        case BetterPlayerEventType.progress:
            final position = event.parameters?["progress"] as Duration?;
            final duration = event.parameters?["duration"] as Duration?;
    
            // 处理普通视频的预缓存和平滑切换
            if (position != null && 
                duration != null && 
                !_isHlsStream(_currentPlayUrl) &&
                duration.inSeconds > 0) {
                final remainingTime = duration - position;
                // 在视频剩余15秒时预加载下一个视频
                if (remainingTime.inSeconds <= 15) {
                    final nextUrl = _getNextVideoUrl();
                    if (nextUrl != null && nextUrl != _nextVideoUrl) {
                        _nextVideoUrl = nextUrl;
                        _preloadNextVideo(nextUrl);
                    }
                }
            }
            break;
            
        // 当事件类型为播放结束时
        case BetterPlayerEventType.finished:
            handleFinishedEvent();
            break;
            
        // 默认情况，忽略所有其他未处理的事件类型
        default:
            if (event.betterPlayerEventType != BetterPlayerEventType.progress) {
                LogUtil.i('未处理的事件类型: ${event.betterPlayerEventType}');
            }
            break;
    }
}

/// 处理播放结束事件
Future<void> handleFinishedEvent() async {
  if (!_isHlsStream(_currentPlayUrl) && _nextPlayerController != null && _nextVideoUrl != null) {
    _handleSourceSwitching(
      isFromFinished: true,
      oldController: _playerController,
    );
  } else if (_isHlsStream(_currentPlayUrl)) {
    // HLS 流意外结束，需要重试
    LogUtil.e('HLS流意外结束');
    _retryPlayback();
  } else {
    await _handleNoMoreSources();
  }
}

/// 预加载方法
Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel) return;
    // 如果已经有预加载的控制器，先清理掉
    _cleanupPreload();
    
    try {
        // 创建新的 StreamUrl 实例来解析URL
        _streamUrl = StreamUrl(url);
        String parsedUrl = await _streamUrl!.getStreamUrl();
        
        if (parsedUrl == 'ERROR') {
            LogUtil.e('预加载解析URL失败');
            return;
        }

        // 创建数据源
        final nextSource = BetterPlayerConfig.createDataSource(
            isHls: _isHlsStream(parsedUrl),
            url: parsedUrl,
        );

        // 创建新的播放器配置
        final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
            eventListener: _setupNextPlayerListener,
            isHls: _isHlsStream(parsedUrl),
        );

        // 创建新的控制器用于预加载
        final preloadController = BetterPlayerController(
            betterPlayerConfiguration,
        );

        // 设置数据源
        await preloadController.setupDataSource(nextSource);
        
        // 只有设置成功才保存控制器和URL
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
    // 避免重复启动超时检测
    if (_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
        return;
    }
    _timeoutActive = true;  // 标记超时检测已启动
    Timer(Duration(seconds: defaultTimeoutSeconds), () {
        // 状态检查
        if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
            return;
        }
        // 检查播放器状态
        if (_playerController?.videoPlayerController == null) {
            LogUtil.e('超时检查：播放器控制器无效');
            _handleSourceSwitching();
            _timeoutActive = false;
            return;
        }
        // 只有在缓冲状态下才判断超时
        if (isBuffering) {
            LogUtil.e('缓冲超时，切换下一个源');
            _handleSourceSwitching();
        }
        _timeoutActive = false;
    });
}

/// 重试播放方法，用于重新尝试播放失败的视频
void _retryPlayback() {
    // 防止重复重试或在不适当的状态下重试
    if (_isRetrying || _isSwitchingChannel || _isDisposing) return;
    
    // 取消当前的超时检测和重试计时器
    _cleanupTimers();

    // 检查是否在重试次数范围内
    if (_retryCount < defaultMaxRetries) {  // 改用 < 而不是 <=，因为从0开始计数
       LogUtil.i('开始重试：${_retryCount}/${defaultMaxRetries}');
        setState(() {
            _isRetrying = true;
            _retryCount++;
            isBuffering = false; 
            toastString = S.current.retryplay;  // 显示重试次数
        });
        
        // 延迟后重试
        _retryTimer = Timer(const Duration(seconds: 2), () async {
            if (!mounted || _isSwitchingChannel) return;
            setState(() {
                _isRetrying = false;  // 重置重试状态
            });
            await _playVideo();  // 重新尝试播放
        });
    } else {
        _handleSourceSwitching();  // 重试次数用尽，切换视频源
    }
}

/// 获取下一个视频地址，返回 null 表示没有更多源
String? _getNextVideoUrl() {
  final List<String>? urls = _currentChannel?.urls;
  if (urls == null || urls.isEmpty) {
    return null;
  }
  final nextSourceIndex = _sourceIndex + 1;
  // 如果超出源列表范围，返回 null
  if (nextSourceIndex >= urls.length) {
    return null;
  }

  return urls[nextSourceIndex];
}

/// 视频源切换的核心逻辑
void _handleSourceSwitching({
  bool isFromFinished = false,
  BetterPlayerController? oldController,
}) {
  // 防止在不适当的状态下切换源
  if (_isRetrying || _isSwitchingChannel || _isDisposing) return;
  
  // 清理所有计时器和状态
  _cleanupTimers();
  
  // 如果是从播放结束触发的切换，且有预加载的播放器
  if (isFromFinished && 
      !_isHlsStream(_currentPlayUrl) && 
      _nextPlayerController != null && 
      oldController != null) {
    
    setState(() {
      // 直接替换控制器，保持最少状态变化
      _playerController = _nextPlayerController;
      _nextPlayerController = null;
      _currentPlayUrl = _nextVideoUrl;
      _nextVideoUrl = null;
      
      // 仅更新必要的状态
      _sourceIndex++;
      _shouldUpdateAspectRatio = true;
      
      LogUtil.i('无缝切换第二段视频完成');
    });

    try {
      // 直接播放，不添加额外延迟
      _playerController?.addEventsListener(_videoListener);
      _playerController?.play();
    } catch (e, stackTrace) {
      LogUtil.logError('无缝切换失败', e, stackTrace);
      _handleSourceSwitching();  
    }
    
    // 异步释放旧控制器
    oldController.dispose();
  } else {
    // 获取下一个视频源
    final nextUrl = _getNextVideoUrl();
    
    if (nextUrl == null) {
      _handleNoMoreSources();
      return;
    }

    // 常规切换逻辑
    setState(() {
      _sourceIndex++;
      _isRetrying = false;
      _retryCount = 0;
      isBuffering = false;
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
    });

    // 延迟后尝试新源
    _startNewSourceTimer();
  }
}

/// 处理没有更多源的情况
Future<void> _handleNoMoreSources() async {
  setState(() {
    toastString = S.current.playError;
    _sourceIndex = 0;  // 重置源索引
    isBuffering = false;
    isPlaying = false;
    _isRetrying = false;
    _retryCount = 0;
  });
  await _disposePlayer();
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
    _handleSourceSwitching();  // 如果切换失败，尝试普通切换
  }
  
  oldController.dispose();
}

/// 启动新源的计时器
void _startNewSourceTimer() {
  _cleanupTimers();  // 确保先清理旧计时器
  
  _retryTimer = Timer(const Duration(seconds: 2), () async {
    if (!mounted || _isSwitchingChannel) return;
    await _playVideo();
  });
}

/// 播放器资源释放方法
Future<void> _disposePlayer() async {
  while (_isDisposing) {
    await Future.delayed(const Duration(milliseconds: 300));
  }
  _isDisposing = true;
  final currentController = _playerController;
  
  try {
    if (currentController != null) {
      // 1. 重置状态,防止新的播放请求
      setState(() {
        _cleanupTimers();
        _isAudio = false;
        _playerController = null;
      });
      
      // 2. 移除事件监听并终止当前播放
      currentController.removeEventsListener(_videoListener);
    
      // 3. 先强制停止播放并等待
      if (currentController.isPlaying() ?? false) {
        await currentController.pause();
        // 强制停止播放,不等待缓冲完成
        currentController.videoPlayerController?.setVolume(0);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // 4. 中断所有网络请求
      _disposeStreamUrl();
      
      // 5. 释放播放器资源 
      try {
        if (currentController.videoPlayerController != null)  {
          // 强制释放视频控制器
          currentController.videoPlayerController!.dispose();
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
          // 最后释放主控制器
          currentController.dispose(); 
          
          // 清理预加载资源
          _cleanupPreload(); 
      } catch (e) {
        LogUtil.logError('释放播放器资源时出错', e);
      }
    }
  } catch (e, stackTrace) {
    LogUtil.logError('释放播放器资源时出错', e, stackTrace);
  } finally {
      setState(() {
         _isDisposing = false; 
      });
  }
}

/// 释放 StreamUrl 实例
void _disposeStreamUrl() {
    if (_streamUrl != null) {
      _streamUrl!.dispose();
      _streamUrl = null;
    }
}

/// 清理所有计时器
void _cleanupTimers() {
  _retryTimer?.cancel();
  _retryTimer = null;
  _timeoutActive = false;
}

/// 处理频道切换操作
Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null || _isSwitchingChannel) return;
    
    try {
        setState(() {
            _isSwitchingChannel = true;
            isBuffering = false;
            toastString = S.current.loading;
            _cleanupTimers();
            _currentChannel = model;
            _sourceIndex = 0;
            _isRetrying = false;
            _retryCount = 0;
            _shouldUpdateAspectRatio = true;
        });
        
        // 开始播放新频道
        await _playVideo();
        
        // 发送统计数据
        if (Config.Analytics) {
            await _sendTrafficAnalytics(context, _currentChannel!.title);
        }
    } catch (e, stackTrace) {
        LogUtil.logError('切换频道失败', e, stackTrace);
        setState(() {
            toastString = S.current.playError;
        });
        await _disposePlayer();
    } finally {
        if (mounted) {
            setState(() {
                _isSwitchingChannel = false;
            });
        }
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
                  _isSwitchingChannel = true;
                  _isRetrying = false;
                  _retryCount = 0;
            });
      _playVideo();
    }
}

/// 处理返回按键逻辑，返回值为 true 表示退出应用，false`表示不退出
Future<bool> _handleBackPress(BuildContext context) async {
  if (_drawerIsOpen) {
    // 如果抽屉打开，则关闭抽屉
    setState(() {
      _drawerIsOpen = false;
    });
    return false; 
  }

  // 如果正在播放则暂停
  bool wasPlaying = _playerController?.isPlaying() ?? false;
  if (wasPlaying) {
    await _playerController?.pause();  // 暂停视频播放
  }

  // 显示退出确认对话框
  bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
  if (!shouldExit && wasPlaying && mounted) {
    await _playerController?.play(); 
  }
  return shouldExit;
}

/// 初始化方法
@override
void initState() {
    super.initState();

    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    // 加载播放列表数据
    _loadData();

    // 加载收藏列表
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
    _disposePlayer();
    _cleanupPreload(); 
    super.dispose();
}

/// 发送页面访问统计数据
Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        // 检查是否是首次安装
        bool? isFirstInstall = SpUtil.getBool('is_first_install');
        bool isTV = context.watch<ThemeProvider>().isTV;
        
        String deviceType;
        if (isTV) {
          deviceType = "TV";
        } else {
          deviceType = "Other";
        }
        
        // 如果是首次安装（值不存在）
        if (isFirstInstall == null) {
          // 发送首次安装的统计数据，使用设备类型作为channelName
          await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: deviceType);
          // 标记已不是首次安装
          await SpUtil.putBool('is_first_install', true);
        } else {
          // 不是首次安装，使用正常的channelName
          await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: channelName);
        }
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计时发生错误', e, stackTrace);
      }
    }
}

/// 异步加载视频数据
Future<void> _loadData() async {
    // 重置所有状态
    setState(() { 
        _isRetrying = false;
        _cleanupTimers();
        _retryCount = 0;
        _isAudio = false; // 重置音频状态
    });
    
    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载数据时出错', e, stackTrace);
      await _parseData();
    }
}

/// 解析并加载本地播放列表
Future<void> _parseData() async {
    try {
      final resMap = await M3uUtil.getLocalM3uData();
      _videoMap = resMap.data;
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('解析播放列表时出错', e, stackTrace);
    }
}

/// 处理播放列表
Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
        final String? url = _currentChannel?.urls?.isNotEmpty == true ? _currentChannel?.urls![0] : null;

        if (Config.Analytics) {
          await _sendTrafficAnalytics(context, _currentChannel!.title);
        }
        
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

/// 从播放列表中动态提取频道
PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    for (String category in playList.keys) {
      if (playList[category] is Map<String, Map<String, PlayModel>>) {
        Map<String, Map<String, PlayModel>> groupMap = playList[category];

        for (String group in groupMap.keys) {
          Map<String, PlayModel> channelMap = groupMap[group] ?? {};
          for (PlayModel? channel in channelMap.values) {
            if (channel?.urls != null && channel!.urls!.isNotEmpty) {
              return channel;
            }
          }
        }
      } else if (playList[category] is Map<String, PlayModel>) {
        Map<String, PlayModel> channelMap = playList[category] ?? {};
        for (PlayModel? channel in channelMap.values) {
          if (channel?.urls != null && channel!.urls!.isNotEmpty) {
            return channel;
          }
        }
      }
    }
    return null;
}

/// 从传递的播放列表中提取"我的收藏"部分
void _extractFavoriteList() {
    if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
       favoriteList = {
          Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!
       };
    } else {
       favoriteList = {
          Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
       };
    }
}

// 获取当前频道的分组名字
String getGroupName(String channelId) {
    return _currentChannel?.group ?? '';
}

// 获取当前频道名字
String getChannelName(String channelId) {
    return _currentChannel?.title ?? '';
}

// 获取当前频道的播放地址列表
List<String> getPlayUrls(String channelId) {
    return _currentChannel?.urls ?? [];
}

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

    // 验证分组名字、频道名字和播放地址是否正确
    if (groupName.isEmpty || channelName.isEmpty) {
      CustomSnackBar.showSnackBar(
        context,
        S.current.channelnofavorite,
        duration: Duration(seconds: 4),
      );
      return;
    }

    if (isChannelFavorite(actualChannelId)) {
      // 取消收藏
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
      CustomSnackBar.showSnackBar(
        context,
        S.current.removefavorite,
        duration: Duration(seconds: 4),
      );
      isFavoriteChanged = true;
    } else {
      // 添加收藏
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
      CustomSnackBar.showSnackBar(
        context,
        S.current.newfavorite,
        duration: Duration(seconds: 4),
      );
      isFavoriteChanged = true;
    }

    if (isFavoriteChanged) {
      try {
        // 保存收藏列表到缓存
        await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
        _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
        LogUtil.i('修改收藏列表后的播放列表: ${_videoMap}');
        await M3uUtil.saveCachedM3uData(_videoMap.toString());
        if (mounted) {
          setState(() {
            _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
          });
        }
      } catch (error) {
        CustomSnackBar.showSnackBar(
          context,
          S.current.newfavoriteerror,
          duration: Duration(seconds: 4),
        );
        LogUtil.logError('收藏状态保存失败', error);
      }
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
                onCloseDrawer: () {
                  setState(() {
                    _drawerIsOpen = false;
                  });
                },
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
                      ? EmptyPage(onRefresh: _parseData)
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
                          onToggleDrawer: () {
                            setState(() {
                              _drawerIsOpen = !_drawerIsOpen;
                            });
                          },
                        ),
                ),
                Offstage(
                  offstage: !_drawerIsOpen,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _drawerIsOpen = false;
                      });
                    },
                    child: ChannelDrawerPage(
                      key: _drawerRefreshKey,
                      refreshKey: _drawerRefreshKey,
                      videoMap: _videoMap,
                      playModel: _currentChannel,
                      onTapChannel: _onTapChannel,
                      isLandscape: true,
                      onCloseDrawer: () {  
                        setState(() {
                          _drawerIsOpen = false;
                        });
                      },
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
