import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:better_player/better_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'provider/theme_provider.dart';
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

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据
  const LiveHomePage({super.key, required this.m3uData});
  
  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> with VideoPlayerListenerMixin {
  // 资源管理器实例
  final ResourceManager _resourceManager = ResourceManager();
  final PlayerControllerManager _playerManager = PlayerControllerManager();
  final PreloadManager _preloadManager = PreloadManager();
  final NetworkResourceManager _networkManager = NetworkResourceManager();
  
  // 超时和重试配置
  static const int defaultMaxRetries = 1;
  static const int defaultTimeoutSeconds = 18;
  
  // 播放器状态
  @override
  BetterPlayerController? get playerController => _playerController;
  @override
  set playerController(BetterPlayerController? value) => _playerController = value;
  
  @override
  bool get isBuffering => _isBuffering;
  @override
  set isBuffering(bool value) {
    if (mounted) {
      setState(() {
        _isBuffering = value;
      });
    }
  }
  
  @override
  bool get isPlaying => _isPlaying;
  @override
  set isPlaying(bool value) {
    if (mounted) {
      setState(() {
        _isPlaying = value;
      });
    }
  }
  
  @override
  double get bufferingProgress => _bufferingProgress;
  @override
  set bufferingProgress(double value) {
    if (mounted) {
      setState(() {
        _bufferingProgress = value;
      });
    }
  }
  
  @override
  String get toastString => _toastString;
  @override
  set toastString(String value) {
    if (mounted) {
      setState(() {
        _toastString = value;
      });
    }
  }
  
  @override
  double get aspectRatio => _aspectRatio;
  @override
  set aspectRatio(double value) {
    if (mounted) {
      setState(() {
        _aspectRatio = value;
      });
    }
  }
  
  @override
  bool get shouldUpdateAspectRatio => _shouldUpdateAspectRatio;
  @override
  set shouldUpdateAspectRatio(bool value) {
    if (mounted) {
      setState(() {
        _shouldUpdateAspectRatio = value;
      });
    }
  }
  
  @override
  bool get isRetrying => _isRetrying;
  @override
  bool get isDisposing => _isDisposing;
  @override
  bool get isSwitchingChannel => _isSwitchingChannel;

  // 私有状态变量
  BetterPlayerController? _playerController;
  bool _isBuffering = false;
  bool _isPlaying = false;
  double _bufferingProgress = 0.0;
  String _toastString = S.current.loading;
  double _aspectRatio = 1.78;
  bool _shouldUpdateAspectRatio = true;
  bool _isRetrying = false;
  bool _isDisposing = false;
  bool _isSwitchingChannel = false;
  bool _timeoutActive = false;
  bool _drawerIsOpen = false;
  bool _isAudio = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  
  // 播放相关变量
  PlaylistModel? _videoMap;
  PlayModel? _currentChannel;
  int _sourceIndex = 0;
  String? _currentPlayUrl;
  
  // 收藏列表
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  ValueKey<int>? _drawerRefreshKey;
  
  // 流量统计
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();
  
    /// 播放前解析频道的视频源 
  Future<void> _playVideo() async {
    if (_currentChannel == null) return;

    setState(() {
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
        isPlaying = false;
        isBuffering = false;
        _isSwitchingChannel = false;
    });

    // 使用PlayerControllerManager释放旧播放器
    if (_playerController != null) {
        await _playerManager.disposeController(_playerController!);
        _playerController = null;
    }
    
    // 添加短暂延迟确保资源完全释放
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
        // 解析URL
        String url = _currentChannel!.urls![_sourceIndex].toString();
        final streamUrl = StreamUrl(url);
        // 注册到网络资源管理器
        _networkManager.setStreamUrl(streamUrl);
        String parsedUrl = await streamUrl.getStreamUrl();
        _currentPlayUrl = parsedUrl;
        
        if (parsedUrl == 'ERROR') {
            setState(() {
                toastString = S.current.vpnplayError;
            });
            return;
        }

        // 使用VideoPlayerUtils检查流类型
        bool isDirectAudio = VideoPlayerUtils.checkIsAudioStream(parsedUrl);
        bool isHls = VideoPlayerUtils.isHlsStream(parsedUrl);
        
        setState(() {
          _isAudio = isDirectAudio;
        });
        
        if (_isSwitchingChannel) return;

        LogUtil.i('准备播放：$parsedUrl ,音频：$isDirectAudio ,是否为HLS流：$isHls');

        // 使用配置工具类创建数据源
        final dataSource = BetterPlayerConfig.createDataSource(
          url: parsedUrl,
          isHls: isHls,
        );

        // 创建播放器配置
        final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
          eventListener: videoListener,  // 使用mixin中的videoListener
          isHls: isHls, 
        );

        // 启动超时检测
        startTimeoutCheck();
        
        // 创建播放器控制器
        BetterPlayerController newController = BetterPlayerController(
          betterPlayerConfiguration,
        );
        
        try {
            await newController.setupDataSource(dataSource);
        } catch (e, stackTrace) {
            _handleSourceSwitch();
            LogUtil.logError('初始化出错', e, stackTrace);
            return; 
        }

        if (_isSwitchingChannel) return;
        
        setState(() {
            _playerController = newController;
            _timeoutActive = false;
        });
        
        await _playerController?.play();
   
    } catch (e, stackTrace) {
        LogUtil.logError('播放出错', e, stackTrace);
        _handleSourceSwitch();
    } finally {
        if (mounted) {
            setState(() {
                _isSwitchingChannel = false;
            });
        }
    }
  }

  /// 预加载方法
  @override
  Future<void> preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel) return;
    
    // 使用PreloadManager清理现有预加载资源
    await _preloadManager.cleanupPreload();
    
    try {
        // 创建新的 StreamUrl 实例来解析URL
        StreamUrl streamUrl = StreamUrl(url);
        String parsedUrl = await streamUrl.getStreamUrl();
        
        if (parsedUrl == 'ERROR') {
            LogUtil.e('预加载解析URL失败');
            return;
        }

        // 检查流类型
        bool isHls = VideoPlayerUtils.isHlsStream(parsedUrl);

        // 创建数据源
        final nextSource = BetterPlayerDataSource(
            BetterPlayerDataSourceType.network,
            parsedUrl,
        );

        // 创建新的播放器配置
        final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
            eventListener: (BetterPlayerEvent event) {},
            isHls: isHls,
        );

        // 创建新的控制器用于预加载
        final preloadController = BetterPlayerController(
            betterPlayerConfiguration,
        );
        
        // 设置预加载专用的事件监听
        _setupNextPlayerListener(preloadController);

        // 设置数据源
        await preloadController.setupDataSource(nextSource);
        
        // 使用PreloadManager保存预加载状态
        _preloadManager.setPreloadData(preloadController, url);
        
    } catch (e, stackTrace) {
        LogUtil.logError('预加载异常', e, stackTrace);
    }
  }

  /// 预加载控制器的事件监听
  void _setupNextPlayerListener(BetterPlayerController controller) {
    controller.addEventsListener((event) {
        switch (event.betterPlayerEventType) {
            case BetterPlayerEventType.setupDataSource:
                LogUtil.i('预加载数据源设置完成');
                break;
            case BetterPlayerEventType.exception:
                final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
                LogUtil.e('预加载发生错误：$errorMessage');
                _preloadManager.cleanupPreload();
                break;
            default:
                break;
        }
    });
  }

  /// 播放器资源释放方法
  Future<void> _disposePlayer() async {
    while (_isDisposing) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _isDisposing = true;
    
    try {
      // 1. 重置状态,防止新的播放请求
      setState(() {
        _timeoutActive = false;
        _retryTimer?.cancel();
        _isAudio = false;
      });
      
      // 2. 使用PlayerControllerManager释放当前播放器
      if (_playerController != null) {
        await _playerManager.disposeController(_playerController!);
        _playerController = null;
      }
      
      // 3. 使用NetworkResourceManager释放网络资源
      await _networkManager.releaseNetworkResources();
      
      // 4. 使用PreloadManager清理预加载资源
      await _preloadManager.cleanupPreload();
      
      // 5. 释放所有注册的资源
      await _resourceManager.disposeAll();
      
    } catch (e, stackTrace) {
      LogUtil.logError('释放播放器资源时出错', e, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
           _isDisposing = false; 
        });
      }
    }
  }

  /// 超时检测方法
  @override
  void startTimeoutCheck() {
    if (_timeoutActive || _isRetrying) return;
    _timeoutActive = true;
    
    Timer(Duration(seconds: defaultTimeoutSeconds), () {
      if (!_timeoutActive || _isRetrying) return;
      
      // 检查播放器是否存在且未播放
      if (_playerController != null && 
          !(_playerController!.isPlaying() ?? false) && 
          !isBuffering) { 
        LogUtil.logError('播放超时', '$defaultTimeoutSeconds seconds');
        _retryPlayback(); 
      }
    });
  }

  /// 重试播放方法
  void _retryPlayback() {
    // 防止重复重试或在不适当的状态下重试
    if (_isRetrying || _isSwitchingChannel || _isDisposing) return;
    
    // 取消当前的超时检测和重试计时器
    _timeoutActive = false;
    _retryTimer?.cancel();
    _retryTimer = null;

    // 检查是否在重试次数范围内
    if (_retryCount < defaultMaxRetries) {
        setState(() {
            _isRetrying = true;
            _retryCount++;
            isBuffering = false;
            bufferingProgress = 0.0;
            toastString = '${S.current.retryplay} (${_retryCount}/${defaultMaxRetries})';
        });
        
        // 延迟后重试
        _retryTimer = Timer(const Duration(seconds: 2), () async {
            if (!mounted || _isSwitchingChannel) return;
            setState(() {
                _isRetrying = false;
            });
            await _playVideo();
        });
    } else {
        _handleSourceSwitch();
    }
  }

  /// 获取下一个视频地址
  @override
  String? getNextVideoUrl() {
    final List<String>? urls = _currentChannel?.urls;
    if (urls == null || urls.isEmpty) {
      return null;
    }

    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= urls.length) {
      return null;
    }

    return urls[nextSourceIndex];
  }

  /// 处理视频源切换（自动）
  void _handleSourceSwitch() {
    if (_isRetrying || _isSwitchingChannel || _isDisposing) return;
    
    _retryTimer?.cancel();
    _retryTimer = null;
    _timeoutActive = false;

    final nextUrl = getNextVideoUrl();
    if (nextUrl == null) {
        setState(() {
            toastString = S.current.playError;
            _sourceIndex = 0;
            isBuffering = false;
            bufferingProgress = 0.0;
            isPlaying = false;
            _isRetrying = false;
            _retryCount = 0;
        });
        return;
    }
    
    setState(() {
        _sourceIndex++; 
        _isRetrying = false;
        _retryCount = 0; 
        isBuffering = false;
        bufferingProgress = 0.0;
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
    });

    _retryTimer = Timer(const Duration(seconds: 2), () async {
        if (!mounted || _isSwitchingChannel) return;
        await _playVideo();
    });
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

  /// 处理频道切换操作
  Future<void> _onTapChannel(PlayModel? model) async {
    if (model == null || _isSwitchingChannel) return;
    
    try {
        setState(() {
            _isSwitchingChannel = true;
            isBuffering = false;
            bufferingProgress = 0.0;
            toastString = S.current.loading;
            _retryTimer?.cancel();
            _retryTimer = null;
            _timeoutActive = false;
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

  /// 处理返回按键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      setState(() {
        _drawerIsOpen = false;
      });
      return false; 
    }

    bool wasPlaying = _playerController?.isPlaying() ?? false;
    if (wasPlaying) {
      await _playerController?.pause();
    }

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
    if (!EnvUtil.isMobile) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }

    // 加载播放列表数据
    _loadData();

    // 加载收藏列表
    _extractFavoriteList();
  }

  /// 清理所有资源
  @override
  void dispose() {
    _retryTimer?.cancel();
    _timeoutActive = false;
    _isRetrying = false;
    _isAudio = false;
    WakelockPlus.disable();
    _isDisposing = true;
    
    // 使用资源管理器清理所有资源
    _disposePlayer();
    _preloadManager.cleanupPreload();
    _networkManager.releaseNetworkResources();
    _resourceManager.disposeAll();
    
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
    _retryTimer?.cancel();
    setState(() { 
        _isRetrying = false;
        _timeoutActive = false;
        _retryCount = 0;
        _isAudio = false;
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
  
    /// 获取当前频道的分组名字
  String getGroupName(String channelId) {
    return _currentChannel?.group ?? '';
  }

  /// 获取当前频道名字
  String getChannelName(String channelId) {
    return _currentChannel?.title ?? '';
  }

  /// 获取当前频道的播放地址列表
  List<String> getPlayUrls(String channelId) {
    return _currentChannel?.urls ?? [];
  }

  /// 检查当前频道是否已收藏
  bool isChannelFavorite(String channelId) {
    String groupName = getGroupName(channelId);
    String channelName = getChannelName(channelId);
    return favoriteList[Config.myFavoriteKey]?[groupName]?.containsKey(channelName) ?? false;
  }

  /// 添加或取消收藏
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
        setState(() {
          _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
        });
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

  /// 处理播放完成事件
  @override
  void handleFinishedEvent() {
    // 如果是直播流，不需要特殊处理
    if (VideoPlayerUtils.isHlsStream(_currentPlayUrl)) {
      return;
    }
    
    // 对于点播内容，可以实现自动切换到下一个视频
    final nextUrl = getNextVideoUrl();
    if (nextUrl != null) {
      setState(() {
        _sourceIndex++;
        _isRetrying = false;
        _retryCount = 0;
        isBuffering = false;
        bufferingProgress = 0.0;
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? '');
      });
      
      // 延迟一段时间后播放下一个视频
      Timer(const Duration(seconds: 2), () async {
        if (!mounted || _isSwitchingChannel) return;
        await _playVideo();
      });
    } else {
      // 如果没有下一个视频，重置到第一个源
      setState(() {
        _sourceIndex = 0;
        isBuffering = false;
        bufferingProgress = 0.0;
        isPlaying = false;
        _isRetrying = false;
        _retryCount = 0;
        toastString = S.current.playError;
      });
    }
  }
  
    @override
  Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;

    // TV模式下的界面构建
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

    // 移动设备模式下的界面构建
    return Material(
      child: OrientationLayoutBuilder(
        // 竖屏布局
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
        // 横屏布局
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
                // 频道抽屉
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
