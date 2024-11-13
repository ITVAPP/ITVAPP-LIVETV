import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
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
import 'util/check_version_util.dart';
import 'util/log_util.dart';
import 'util/m3u_util.dart';
import 'util/stream_url.dart';
import 'util/dialog_util.dart';
import 'util/custom_snackbar.dart';
import 'util/channel_util.dart';
import 'util/traffic_analytics.dart';
import 'widget/empty_page.dart';
import 'widget/show_exit_confirm.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

/// 音频检测
mixin AudioDetectionMixin {
  bool _isAudio = false; // 标记是否为音频流
  bool get isAudio => _isAudio;
  
  /// 检查给定URL是否为音频流，如果是音频流返回true，否则返回false
  bool _checkIsAudioStream(String? url) {
    // 如果URL为空则返回false
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.mp3') || 
           lowercaseUrl.endsWith('.aac') || 
           lowercaseUrl.endsWith('.m4a') ||
           lowercaseUrl.endsWith('.ogg') ||
           lowercaseUrl.endsWith('.wav');
  }

  /// 更新音频状态标志
  void _updateAudioState(String? url, Function setState) {
    setState(() {
      _isAudio = _checkIsAudioStream(url);
    });
  }
}

/// 播放器事件处理，用于处理播放器的各种事件状态
mixin PlayerEventHandlerMixin {
  bool isBuffering = false;  // 是否正在缓冲
  bool isPlaying = false;    // 是否正在播放
  double aspectRatio = 1.78; // 视频宽高比，默认16:9
  bool _shouldUpdateAspectRatio = true; // 是否需要更新宽高比
  
  /// 处理播放器事件
  void handlePlayerEvent(
    BetterPlayerEvent event, 
    bool mounted, 
    Function setState,
    BetterPlayerController? playerController
  ) {
    // 如果组件未挂载则直接返回
    if (!mounted) return;
    
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        // 初始化完成时更新视频宽高比
        if (_shouldUpdateAspectRatio) {
          setState(() {
            aspectRatio = playerController?.videoPlayerController?.value.aspectRatio ?? 1.78;
            _shouldUpdateAspectRatio = false;
          });
        }
        break;
      
      case BetterPlayerEventType.bufferingStart:
      case BetterPlayerEventType.bufferingUpdate:
      case BetterPlayerEventType.bufferingEnd:
        // 更新缓冲状态
        setState(() {
          isBuffering = event.betterPlayerEventType == BetterPlayerEventType.bufferingStart ||
                       event.betterPlayerEventType == BetterPlayerEventType.bufferingUpdate;
        });
        break;
      
      case BetterPlayerEventType.play:
      case BetterPlayerEventType.pause:
        // 更新播放状态
        setState(() {
          isPlaying = event.betterPlayerEventType == BetterPlayerEventType.play;
        });
        break;
        
      default:
        break;
    }
  }
}

/// 收藏管理，包括收藏列表的增删改查和本地存储
mixin FavoriteChannelMixin {
  // 收藏列表数据结构：{收藏键: {分组名: {频道名: 频道信息}}}
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };

  /// 保存收藏状态到本地存储
  Future<void> saveFavoriteState(
    PlaylistModel? videoMap, 
    BuildContext context,
    ValueKey<int>? drawerRefreshKey,
    Function setState
  ) async {
    try {
      // 保存收藏列表
      await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
      
      // 更新播放列表中的收藏数据
      if (videoMap != null) {
        videoMap.playList?[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
        await M3uUtil.saveCachedM3uData(videoMap.toString());
      }
      
      // 触发抽屉界面刷新
      setState(() {
        drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
      });
    } catch (error) {
      // 保存失败时显示错误提示
      CustomSnackBar.showSnackBar(
        context,
        S.current.newfavoriteerror,
        duration: const Duration(seconds: 4),
      );
      LogUtil.logError('收藏状态保存失败', error);
    }
  }
  
  /// 更新收藏频道列表
  void updateFavoriteChannel(String groupName, String channelName, PlayModel channel, bool isFavorite) {
    if (isFavorite) {
      // 添加收藏：确保分组存在并添加频道
      favoriteList[Config.myFavoriteKey]![groupName] ??= {};
      favoriteList[Config.myFavoriteKey]![groupName]![channelName] = channel;
    } else {
      // 取消收藏：移除频道，如果分组为空则同时移除分组
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
    }
  }

  /// 检查频道是否已收藏
  bool isChannelFavorite(String groupName, String channelName) {
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
  }

  /// 从播放列表中提取收藏列表
  void extractFavoriteList(PlaylistModel m3uData) {
    if (m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
      // 如果存在收藏数据则加载
      favoriteList = {
        Config.myFavoriteKey: m3uData.playList![Config.myFavoriteKey]!
      };
    } else {
      // 否则初始化空收藏列表
      favoriteList = {
        Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
      };
    }
  }
}

/// 播放器管理类
class VideoPlayerManager {
  BetterPlayerController? _controller;  // 播放器控制器
  StreamUrl? _streamUrl;                // 流媒体URL处理器
  bool _isDisposing = false;           // 是否正在销毁资源标志
  
  VideoPlayerManager();
  
  BetterPlayerController? get controller => _controller;

  /// 初始化播放器
  Future<BetterPlayerController?> initializePlayer({
    required String url,      // 媒体URL地址
    required bool isAudio,    // 是否为音频模式
    required Function(BetterPlayerEvent) eventListener,  // 事件监听器
  }) async {
    // 如果正在销毁则返回null
    if (_isDisposing) return null;

    // 释放现有播放器资源
    await dispose();

    try {
      // 创建流URL解析器并获取实际播放地址
      _streamUrl = StreamUrl(url);
      String parsedUrl = await _streamUrl!.getStreamUrl();
      
      // URL解析失败则返回null
      if (parsedUrl == 'ERROR') {
        return null;
      }

      LogUtil.i('准备播放：$parsedUrl');
      
      // 设置播放器数据源
      BetterPlayerDataSource dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,  // 网络流媒体类型
        parsedUrl,                           // 解析后的URL
        notificationConfiguration: const BetterPlayerNotificationConfiguration(
          showNotification: false,           // 禁用通知栏控制
        ),
        // 配置缓冲参数
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 50000,                // 最小缓冲时长(50秒)
          maxBufferMs: 360000,               // 最大缓冲时长(6分钟)
          bufferForPlaybackMs: 2500,         // 开始播放所需的最小缓冲(2.5秒)
          bufferForPlaybackAfterRebufferMs: 5000  // 重新缓冲后开始播放所需的最小缓冲(5秒)
        ),
        // 配置缓存参数
        cacheConfiguration: BetterPlayerCacheConfiguration(
          useCache: true,                    // 启用缓存
          preCacheSize: 10 * 1024 * 1024,    // 预缓存大小(10MB)
          maxCacheSize: 100 * 1024 * 1024,   // 最大缓存大小(100MB)
          maxCacheFileSize: 10 * 1024 * 1024, // 单个文件最大缓存(10MB)
        ),
        // 根据媒体类型设置不同的格式
        videoFormat: isAudio ? BetterPlayerVideoFormat.dash : BetterPlayerVideoFormat.hls,
      );

      // 配置播放器参数
      BetterPlayerConfiguration betterPlayerConfiguration = BetterPlayerConfiguration(
        autoPlay: true,                      // 自动开始播放
        fit: BoxFit.contain,                 // 视频适应方式：保持比例
        allowedScreenSleep: false,           // 禁止屏幕休眠
        autoDispose: true,                   // 自动释放资源
        handleLifecycle: true,               // 处理生命周期事件
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableFullscreen: true,            // 允许全屏
          enableMute: true,                  // 允许静音
          enablePlayPause: true,             // 允许播放/暂停
          enableProgressBar: true,           // 显示进度条
          enableSkips: false,                // 禁用跳过功能
          enableAudioTracks: true,           // 允许音轨选择
          loadingWidget: CircularProgressIndicator(),  // 加载动画
          showControlsOnInitialize: true,    // 初始化时显示控制栏
          enableOverflowMenu: false,         // 禁用溢出菜单
        ),
        // 全屏模式后支持的屏幕方向
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.landscapeLeft,    // 横屏-左
          DeviceOrientation.landscapeRight,   // 横屏-右
          DeviceOrientation.portraitUp,       // 竖屏-正向
        ],
        eventListener: eventListener,         // 事件监听器
      );

      // 创建并初始化新的播放器控制器
      final newController = BetterPlayerController(betterPlayerConfiguration);
      
      try {
        await newController.setupDataSource(dataSource);
        _controller = newController;
        return newController;
      } catch (e, stackTrace) {
        // 初始化失败时释放控制器资源
        newController.dispose();
        LogUtil.logError('初始化播放器失败', e, stackTrace);
        rethrow;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('创建播放器失败', e, stackTrace);
      rethrow;
    }
  }

  /// 释放播放器资源
  Future<void> dispose() async {
    if (_isDisposing) return;
    
    _isDisposing = true;
    try {
      // 释放播放器控制器资源
      final currentController = _controller;
      if (currentController != null) {
        if (currentController.isPlaying() ?? false) {
          await currentController.pause();
        }
        
        currentController.clearCache();
        currentController.dispose(forceDispose: true);
        _controller = null;
      }
      
      // 释放流URL解析器资源
      if (_streamUrl != null) {
        _streamUrl!.dispose();
        _streamUrl = null;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('释放播放器资源失败', e, stackTrace);
    } finally {
      _isDisposing = false;
    }
  }
}

/// 重试配置类，用于配置播放器重试的各项参数
class BetterPlayerRetryConfig {
  /// 最大重试次数
  final int maxRetries;
  
  /// 重试之间的延迟时间
  final Duration retryDelay;
  
  /// 播放超时时间
  final Duration timeoutDuration;
  
  /// 是否自动重试
  final bool autoRetry;
  
  /// 构造函数，设置重试相关参数的默认值
  const BetterPlayerRetryConfig({
    this.maxRetries = 3,               // 默认最多重试3次
    this.retryDelay = const Duration(seconds: 3),  // 默认延迟3秒重试
    this.timeoutDuration = const Duration(seconds: 18), // 默认18秒超时
    this.autoRetry = true,             // 默认启用自动重试
  });
}

/// 重试管理，包括自动重试、超时检测等
mixin BetterPlayerRetryMixin {
  int _retryCount = 0;           // 当前重试次数
  Timer? _retryTimer;            // 重试定时器
  Timer? _timeoutTimer;          // 超时定时器
  bool _isRetrying = false;      // 是否正在重试标志
  bool _isDisposing = false;     // 是否正在销毁标志
  StreamSubscription? _playerEventSubscription;  // 播放器事件订阅
  final BetterPlayerRetryConfig retryConfig;    // 重试配置
  
  BetterPlayerRetryMixin(this.retryConfig);

  // 抽象成员，需要实现类提供具体实现
  BetterPlayerController? get playerController;
  void onRetryStarted();         // 重试开始回调
  void onRetryFailed();          // 重试失败回调
  void onSourceSwitchNeeded();   // 需要切换源回调
  Future<void> initializePlayer();  // 初始化播放器方法
  
  /// 设置重试机制
  void setupRetryMechanism() {
    // 取消之前的事件订阅（如果存在）
    _playerEventSubscription?.cancel();
    
    // 设置播放器事件监听
    _playerEventSubscription = playerController?.getBetterPlayerEventsStream().listen((event) {
      if (_isDisposing) return;
      
      switch (event.betterPlayerEventType) {
        case BetterPlayerEventType.initialized:
          // 初始化完成时重置重试状态
          _resetRetryState();
          break;
          
        case BetterPlayerEventType.exception:
          // 发生异常时，如果启用了自动重试，则进行重试
          if (retryConfig.autoRetry && !_isDisposing) {
            _handlePlaybackError();
          }
          break;
          
        case BetterPlayerEventType.finished:
          // 播放结束时，如果启用了自动重试，则重新播放
          if (retryConfig.autoRetry && !_isDisposing) {
            _resetAndReplay();
          }
          break;
          
        default:
          break;
      }
    });
    
    // 如果设置了超时时间，启动超时检测
    if (retryConfig.timeoutDuration.inSeconds > 0) {
      _startTimeoutCheck();
    }
  }
  
  /// 重置重试状态
  void _resetRetryState() {
    if (_isDisposing) return;
    _retryCount = 0;
    _isRetrying = false;
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
  }

  /// 处理播放错误
  Future<void> _handlePlaybackError() async {
    if (_isRetrying || _isDisposing) return;
    
    // 检查是否达到最大重试次数
    if (_retryCount < retryConfig.maxRetries) {
      _isRetrying = true;
      _retryCount++;
      
      // 通知重试开始
      onRetryStarted();
      
      // 取消之前的重试定时器（如果存在）
      _retryTimer?.cancel();
      
      // 设置新的重试定时器
      _retryTimer = Timer(retryConfig.retryDelay, () async {
        if (_isDisposing) return;
        
        try {
          // 尝试重新初始化播放器
          await initializePlayer();
          if (!_isDisposing) {
            _isRetrying = false;
          }
        } catch (e, stackTrace) {
          LogUtil.logError('重试播放失败', e, stackTrace);
          if (!_isDisposing) {
            _handlePlaybackError();
          }
        }
      });
    } else {
      // 重试次数用尽，通知失败并请求切换源
      if (!_isDisposing) {
        onRetryFailed();
        onSourceSwitchNeeded();
      }
    }
  }

  /// 启动超时检测
  void _startTimeoutCheck() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(retryConfig.timeoutDuration, () {
      if (_isDisposing) return;
      
      // 检查播放状态，如果未在播放且未在重试，则触发错误处理
      final isPlaying = playerController?.isPlaying() ?? false;
      if (!isPlaying && !_isRetrying) {
        _handlePlaybackError();
      }
    });
  }
  
  /// 重置播放器并重新开始播放
  Future<void> _resetAndReplay() async {
    if (_isDisposing) return;
    
    try {
      final controller = playerController;
      if (controller != null) {
        // 重置播放位置到开始
        await controller.seekTo(Duration.zero);
        if (!_isDisposing) {
          // 开始播放
          await controller.play();
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重置播放失败', e, stackTrace);
      if (!_isDisposing) {
        _handlePlaybackError();
      }
    }
  }
  
  /// 释放重试机制相关资源
  void disposeRetryMechanism() {
    _isDisposing = true;
    _playerEventSubscription?.cancel();
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    _resetRetryState();
  }
}

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData;  // 播放列表数据

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

/// LiveHomePage的状态类，实现完整的播放器功能
class _LiveHomePageState extends State<LiveHomePage> 
    with BetterPlayerRetryMixin, AudioDetectionMixin, PlayerEventHandlerMixin, FavoriteChannelMixin {
  
  /// 构造函数，初始化重试配置
  _LiveHomePageState() : super(const BetterPlayerRetryConfig(
    maxRetries: defaultMaxRetries,         // 最大重试次数
    retryDelay: Duration(seconds: 3),      // 重试延迟
    timeoutDuration: Duration(seconds: defaultTimeoutSeconds),  // 超时时间
    autoRetry: true,                       // 启用自动重试
  ));
  
  // 默认配置常量
  static const int defaultMaxRetries = 1;        // 默认重试次数
  static const int defaultTimeoutSeconds = 18;   // 默认超时秒数
  
  String toastString = S.current.loading;        // 显示给用户的状态信息
  PlaylistModel? _videoMap;                      // 视频地图数据
  PlayModel? _currentChannel;                    // 当前播放的频道
  int _sourceIndex = 0;                          // 当前使用的视频源索引

  //播放器管理器实例
  late final VideoPlayerManager _playerManager;
  @override
  BetterPlayerController? get playerController => _playerManager.controller;

  bool _drawerIsOpen = false;              // 抽屉是否打开
  bool _isDisposing = false;               // 是否正在销毁
  bool _isSwitchingChannel = false;        // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true;    // 是否需要更新宽高比
  
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();  // 流量分析器
  ValueKey<int>? _drawerRefreshKey;        // 抽屉刷新键

  @override
  /// 重试开始回调，更新UI显示重试状态
  void onRetryStarted() {
    if (mounted) {
      setState(() {
        toastString = S.current.retryplay;
      });
    }
  }

  @override
  /// 重试失败回调，更新UI显示错误状态
  void onRetryFailed() {
    if (mounted) {
      setState(() {
        toastString = S.current.playError;
      });
    }
  }

  @override
  /// 触发源切换逻辑
  void onSourceSwitchNeeded() {
    _handleSourceSwitch();
  }

  @override
  /// 初始化播放器
  Future<void> initializePlayer() async {
    await _playVideo();
  }

  /// 播放视频
  Future<void> _playVideo() async {
    if (_currentChannel == null) return;
    
    setState(() {
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    });

    try {
      String url = _currentChannel!.urls![_sourceIndex].toString();
      
      // 使用播放器管理器初始化播放器
      final newController = await _playerManager.initializePlayer(
        url: url,
        isAudio: isAudio,
        eventListener: _videoListener,
      );
      
      // 如果初始化失败，显示错误并尝试切换源
      if (newController == null) {
        setState(() {
          toastString = S.current.vpnplayError;
        });
        _handleSourceSwitch();
        return;
      }

      if (!mounted || _isDisposing) return;

      setState(() {
        toastString = S.current.loading;
      });
      
      setupRetryMechanism();
      await newController.play();
   
    } catch (e, stackTrace) {
      LogUtil.logError('播放出错', e, stackTrace);
      _handleSourceSwitch();
    }
  }

  /// 播放器事件监听方法
  void _videoListener(BetterPlayerEvent event) {
    if (_isDisposing) return;
    handlePlayerEvent(event, mounted, setState, playerController);
  }

  /// 处理视频源切换
  void _handleSourceSwitch() {
    final List<String>? urls = _currentChannel?.urls;
    if (urls == null || urls.isEmpty) {
      setState(() {
        toastString = S.current.playError;
      });
      return;
    }

    // 切换到下一个源
    _sourceIndex += 1;
    if (_sourceIndex >= urls.length) {
      setState(() {
        toastString = S.current.playError;
      });
      return;
    }

    // 更新音频状态并开始播放新源
    _updateAudioState(urls[_sourceIndex], setState);
    setState(() {
      toastString = S.current.switchLine(_sourceIndex + 1);
    });

    initializePlayer();
  }

  /// 处理频道切换操作
  Future<void> _onTapChannel(PlayModel? model) async {
    if (_isSwitchingChannel || model == null) return;
    
    setState(() {
      _isSwitchingChannel = true;
      toastString = S.current.loading;
    });
    
    try {
      // 清理当前播放器资源
      await _playerManager.dispose();
      
      // 更新频道信息和状态
      _currentChannel = model;
      _sourceIndex = 0;
      _shouldUpdateAspectRatio = true;

      // 更新音频状态
      final String? url = model.urls?.isNotEmpty == true ? model.urls![0] : null;
      _updateAudioState(url, setState);

      // 如果启用了流量统计，发送统计数据
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }

      if (!_isSwitchingChannel) return;
      
      // 开始播放新频道
      await _playVideo();
      
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      setState(() {
        toastString = S.current.playError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingChannel = false;
        });
      }
    }
  }

  /// 切换视频源
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }

    disposeRetryMechanism();

    // 显示源选择对话框
    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

    // 如果用户选择了新的源，则切换到该源
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      _updateAudioState(sources[selectedIndex], setState);
      await _playVideo();
    } else {
      setupRetryMechanism();
    }
  }
  
@override
  /// 初始化状态
  void initState() {
    super.initState();

    // 初始化播放器管理器
    _playerManager = VideoPlayerManager();

    // 如果不是移动设备，隐藏标题栏
    if (!EnvUtil.isMobile) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }

    // 加载数据并提取收藏列表
    _loadData();
    extractFavoriteList(widget.m3uData);

    // 延迟检查版本更新
    Future.delayed(const Duration(minutes: 1), () {
      CheckVersionUtil.checkVersion(context, false, false);
    });
  }

  @override
  /// 释放资源
  void dispose() {
    _isDisposing = true;
    disposeRetryMechanism();
    WakelockPlus.disable();
    _playerManager.dispose();
    super.dispose();
  }

  /// 加载播放列表数据
  Future<void> _loadData() async {
    disposeRetryMechanism();
    
    try {
      _videoMap = widget.m3uData;
      _sourceIndex = 0;
      await _handlePlaylist();
    } catch (e, stackTrace) {
      LogUtil.logError('加载数据时出错', e, stackTrace);
      await _parseData();
    }
  }

  /// 解析本地播放列表数据，当直接加载数据失败时的备选方案
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

  /// 初始化第一个可用的频道
  Future<void> _handlePlaylist() async {
    if (_videoMap?.playList?.isNotEmpty ?? false) {
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
        // 更新音频状态
        final String? url = _currentChannel?.urls?.isNotEmpty == true ? _currentChannel?.urls![0] : null;
        _updateAudioState(url, setState);

        // 发送统计数据（如果启用）
        if (Config.Analytics) {
          await _sendTrafficAnalytics(context, _currentChannel!.title);
        }
        
        await _playVideo();
      } else {
        setState(() {
          toastString = 'UNKNOWN';
        });
      }
    } else {
      setState(() {
        _currentChannel = null;
        toastString = 'UNKNOWN';
      });
    }
  }

  /// 发送流量统计数据
  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: channelName);
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计时发生错误', e, stackTrace);
      }
    }
  }

  /// 切换频道收藏状态
  void toggleFavorite(String channelId) async {
    String groupName = _currentChannel?.group ?? '';
    String channelName = _currentChannel?.title ?? '';

    // 检查频道信息是否完整
    if (groupName.isEmpty || channelName.isEmpty) {
      CustomSnackBar.showSnackBar(
        context,
        S.current.channelnofavorite,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    // 根据当前状态切换收藏
    bool isFavorite = isChannelFavorite(groupName, channelName);
    if (isFavorite) {
      updateFavoriteChannel(groupName, channelName, _currentChannel!, false);
      CustomSnackBar.showSnackBar(
        context,
        S.current.removefavorite,
        duration: const Duration(seconds: 4),
      );
    } else {
      updateFavoriteChannel(groupName, channelName, _currentChannel!, true);
      CustomSnackBar.showSnackBar(
        context,
        S.current.newfavorite,
        duration: const Duration(seconds: 4),
      );
    }

    // 保存收藏状态
    await saveFavoriteState(_videoMap, context, _drawerRefreshKey, setState);
  }

  /// 处理返回按键事件
  Future<bool> _handleBackPress(BuildContext context) async {
    // 如果抽屉打开，则关闭抽屉
    if (_drawerIsOpen) {
      setState(() {
        _drawerIsOpen = false;
      });
      return false;
    }

    // 暂停当前播放
    bool wasPlaying = playerController?.isPlaying() ?? false;
    if (wasPlaying) {
      await playerController?.pause();
    }

    // 显示退出确认对话框
    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    
    // 如果不退出且之前在播放，则恢复播放
    if (!shouldExit && wasPlaying && mounted) {
      await playerController?.play();
    }
    
    return shouldExit;
  }

  /// 从播放列表中提取第一个有效频道
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    // 遍历播放列表中的所有分类
    for (String category in playList.keys) {
      if (playList[category] is Map<String, Map<String, PlayModel>>) {
        // 处理二级分组结构
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
        // 处理单级分组结构
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

  @override
  /// 根据不同设备和方向显示不同的布局
  Widget build(BuildContext context) {
    // 检查是否为TV模式
    bool isTV = context.watch<ThemeProvider>().isTV;

    // TV模式下显示TV专用页面
    if (isTV) {
      return TvPage(
        videoMap: _videoMap,
        playModel: _currentChannel,
        onTapChannel: _onTapChannel,
        toastString: toastString,
        controller: _playerManager.controller,
        isBuffering: isBuffering,
        isPlaying: isPlaying,
        aspectRatio: aspectRatio,
        onChangeSubSource: _parseData,
        changeChannelSources: _changeChannelSources,
        toggleFavorite: toggleFavorite,
        isChannelFavorite: (String channelId) => 
            isChannelFavorite(_currentChannel?.group ?? '', _currentChannel?.title ?? ''),
        currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
        isAudio: isAudio,
      );
    }

    // 非TV模式下使用响应式布局
    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) {
          // 竖屏模式
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: MobileVideoWidget(
              toastString: toastString,
              controller: _playerManager.controller,
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
              isChannelFavorite: (String channelId) => 
                  isChannelFavorite(_currentChannel?.group ?? '', _currentChannel?.title ?? ''),
              isAudio: isAudio,
            ),
          );
        },
        landscape: (context) {
          // 横屏模式
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
                          controller: _playerManager.controller,
                          isBuffering: isBuffering,
                          isPlaying: isPlaying,
                          aspectRatio: aspectRatio,
                          drawerIsOpen: _drawerIsOpen,
                          changeChannelSources: _changeChannelSources,
                          isChannelFavorite: (String channelId) => 
                              isChannelFavorite(_currentChannel?.group ?? '', _currentChannel?.title ?? ''),
                          currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
                          toggleFavorite: toggleFavorite,
                          isLandscape: true,
                          isAudio: isAudio,
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
