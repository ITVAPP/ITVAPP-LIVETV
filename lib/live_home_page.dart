import 'dart:async';
import 'dart:convert';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider/theme_provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:video_player/video_player.dart';
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

/// 播放器状态枚举
enum PlayerState {
  initial,    // 初始状态
  preparing,  // 准备中（加载资源）
  ready,      // 准备就绪
  playing,    // 播放中
  paused,     // 已暂停
  error,      // 错误状态
  disposed    // 已释放资源
}

/// 重试状态管理类
class RetryState {
  final int maxRetries;
  final Duration retryDelay;
  int _currentRetry = 0;
  
  RetryState({
    this.maxRetries = 1,
    this.retryDelay = const Duration(seconds: 3),
  });

  bool get canRetry => _currentRetry < maxRetries;
  int get currentRetryCount => _currentRetry;
  
  void incrementRetry() {
    _currentRetry++;
  }
  
  void reset() {
    _currentRetry = 0;
  }
}

/// 资源管理类
class ResourceManager {
  VideoPlayerController? _controller;
  StreamUrl? _streamUrl;
  Timer? _timeoutTimer;
  bool _isDisposing = false;
  
  VideoPlayerController? get controller => _controller;
  bool get isDisposing => _isDisposing;
  
  Future<void> initializeController({
    required String url,
    required Function onError,
    required Function(VideoPlayerController) onInitialized,
  }) async {
    await disposeController();
    
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
          mixWithOthers: false,
          webOptions: const VideoPlayerWebOptions(
            controls: VideoPlayerWebOptionsControls.enabled()
          ),
        ),
      )..setVolume(1.0);

      await _controller?.initialize();
      onInitialized(_controller!);
    } catch (e, stack) {
      LogUtil.logError('初始化播放器失败', e, stack);
      onError();
    }
  }
  
  Future<void> disposeController() async {
    if (_isDisposing) return;
    
    _isDisposing = true;
    try {
      final controller = _controller;
      _controller = null;
      
      if (controller != null) {
        try {
          if (controller.value.isPlaying) {
            await controller.pause();
          }
          await controller.dispose();
        } catch (e) {
          LogUtil.logError('释放控制器时出错', e);
        }
      }
    } finally {
      _isDisposing = false;
    }
  }
  
  Future<void> disposeStreamUrl() async {
    try {
      _streamUrl?.dispose();
      _streamUrl = null;
    } catch (e) {
      LogUtil.logError('释放StreamUrl时出错', e);
    }
  }
  
  void cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
  
  void startTimeoutTimer(Duration duration, Function onTimeout) {
    cancelTimeoutTimer();
    _timeoutTimer = Timer(duration, () {
      if (!_isDisposing && _controller != null && !_controller!.value.isPlaying) {
        onTimeout();
      }
    });
  }
  
  Future<void> disposeAll() async {
    cancelTimeoutTimer();
    await disposeController();
    disposeStreamUrl();
  }
}

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  // 状态管理相关
  late final ResourceManager _resourceManager;
  late final RetryState _retryState;
  PlayerState _playerState = PlayerState.initial;
  
  // 超时检测的时间
  static const int defaultTimeoutSeconds = 18;
  final Duration timeoutDuration = const Duration(seconds: defaultTimeoutSeconds);
  
  // 存储加载状态的提示文字
  String toastString = S.current.loading;

  // 视频播放列表的数据模型  
  PlaylistModel? _videoMap;
  
  // 当前播放的频道数据模型
  PlayModel? _currentChannel;
  
  // 当前选中的视频源索引
  int _sourceIndex = 0;
  
// 播放器相关状态
  bool isBuffering = false;
  bool isPlaying = false;
  double aspectRatio = 1.78;
  bool _shouldUpdateAspectRatio = true;

  // UI 相关状态
  bool _drawerIsOpen = false;
  bool isDebugMode = false;

  // 状态标记
  bool _isSwitchingChannel = false;

  // 收藏列表相关
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };

  // 实例化 TrafficAnalytics 流量统计
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();

  /// 播放前解析频道的视频源
  Future<void> _playVideo() async {
    if (_currentChannel == null || _playerState == PlayerState.disposed) {
      return;
    }

    // 更新状态和UI
    _playerState = PlayerState.preparing;
    setState(() {
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    });

    try {
      // 解析视频URL
      final parsedUrl = await _prepareStreamUrl();
      if (parsedUrl == null) {
        _handlePlayError(S.current.vpnplayError);
        return;
      }

      // 初始化播放器
      await _initializePlayer(parsedUrl);

      // 开始播放
      await _startPlayback();
    } catch (e, stackTrace) {
      LogUtil.logError('播放视频时出错', e, stackTrace);
      await _handlePlayError('播放出错');
    } finally {
      _isSwitchingChannel = false;
    }
  }

  /// 准备视频流URL
  Future<String?> _prepareStreamUrl() async {
    try {
      final url = _currentChannel!.urls![_sourceIndex].toString();
      final streamUrl = StreamUrl(url);
      final parsedUrl = await streamUrl.getStreamUrl();

      if (parsedUrl == 'ERROR') {
        return null;
      }

      // 调试模式下显示确认对话框
      if (isDebugMode) {
        final shouldPlay = await _showConfirmationDialog(context, parsedUrl);
        if (!shouldPlay) {
          return null;
        }
      }

      return parsedUrl;
    } catch (e, stackTrace) {
      LogUtil.logError('解析视频地址出错', e, stackTrace);
      return null;
    }
  }

  /// 初始化播放器
  Future<void> _initializePlayer(String url) async {
    await _resourceManager.initializeController(
      url: url,
      onError: () {
        _handlePlayError('初始化播放器失败');
      },
      onInitialized: (controller) {
        controller.addListener(_videoListener);
      },
    );
  }

  /// 开始播放视频
  Future<void> _startPlayback() async {
    final controller = _resourceManager.controller;
    if (controller == null) return;

    try {
      await controller.play();
      
      setState(() {
        toastString = S.current.loading;
        _playerState = PlayerState.playing;
      });

      _retryState.reset();
      _startTimeoutCheck();
    } catch (e) {
      _handlePlayError('开始播放失败');
    }
  }

  /// 处理播放错误
  Future<void> _handlePlayError(String errorMessage) async {
    if (_playerState == PlayerState.disposed) return;

    _playerState = PlayerState.error;
    setState(() {
      toastString = errorMessage;
    });

    // 尝试重试播放
    await _retryPlayback();
  }

  /// 开始超时检测
  void _startTimeoutCheck() {
    _resourceManager.startTimeoutTimer(
      timeoutDuration,
      () => _retryPlayback(),
    );
  }

  /// 重试播放逻辑
  Future<void> _retryPlayback() async {
    if (_playerState == PlayerState.disposed) return;

    if (_retryState.canRetry) {
      _retryState.incrementRetry();
      setState(() {
        toastString = S.current.retryplay;
      });

      await Future.delayed(_retryState.retryDelay);
      if (_playerState != PlayerState.disposed) {
        await _playVideo();
      }
    } else {
      await _switchToNextSource();
    }
  }

  /// 切换到下一个视频源
  Future<void> _switchToNextSource() async {
    final nextIndex = _sourceIndex + 1;
    
    if (_currentChannel == null || 
        nextIndex >= (_currentChannel!.urls?.length ?? 0)) {
      setState(() {
        toastString = S.current.playError;
      });
      return;
    }

    setState(() {
      _sourceIndex = nextIndex;
      toastString = S.current.switchLine(_sourceIndex + 1);
    });

    await Future.delayed(const Duration(seconds: 3));
    if (_playerState != PlayerState.disposed) {
      await _playVideo();
    }
  }

  /// 视频播放状态监听器
  void _videoListener() {
    final controller = _resourceManager.controller;
    if (controller == null || _playerState == PlayerState.disposed) return;

    // 检查播放错误
    if (controller.value.hasError) {
      _retryPlayback();
      return;
    }

    // 更新缓冲状态
    if (isBuffering != controller.value.isBuffering) {
      setState(() {
        isBuffering = controller.value.isBuffering;
      });
    }

    // 更新播放状态和宽高比
    if (isPlaying != controller.value.isPlaying) {
      setState(() {
        isPlaying = controller.value.isPlaying;
        if (isPlaying && _shouldUpdateAspectRatio) {
          aspectRatio = controller.value.aspectRatio;
          _shouldUpdateAspectRatio = false;
        }
      });
    }
  }

  /// 显示播放确认对话框
  Future<bool> _showConfirmationDialog(BuildContext context, String url) async {
    return await DialogUtil.showCustomDialog(
      context,
      title: S.current.foundStreamTitle,
      content: S.current.streamUrlContent(url),
      positiveButtonLabel: S.current.playButton,
      onPositivePressed: () {
        Navigator.of(context).pop(true);
      },
      negativeButtonLabel: S.current.cancelButton,
      onNegativePressed: () {
        Navigator.of(context).pop(false);
      },
      isDismissible: false,
    ) ?? false;
  }
  
/// 处理频道切换操作
  Future<void> _onTapChannel(PlayModel? model) async {
    if (_isSwitchingChannel || model == null ||
        _playerState == PlayerState.disposed) {
      return;
    }

    _isSwitchingChannel = true;
    try {
      // 更新频道信息和重置状态
      _currentChannel = model;
      _sourceIndex = 0;
      _retryState.reset();
      _shouldUpdateAspectRatio = true;
      
      // 取消当前的超时检测
      _resourceManager.cancelTimeoutTimer();

      // 发送流量统计数据
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }

      // 开始播放新频道
      await _playVideo();
    } catch (e, stack) {
      LogUtil.logError('切换频道失败', e, stack);
      _handlePlayError('切换频道失败');
    } finally {
      _isSwitchingChannel = false;
    }
  }

  /// 发送页面访问统计数据
  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        await _trafficAnalytics.sendPageView(
          context, 
          "LiveHomePage",
          additionalPath: channelName
        );
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计时发生错误', e, stackTrace);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // 初始化资源管理器和重试状态
    _resourceManager = ResourceManager();
    _retryState = RetryState();

    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }

    // 初始化数据
    _initializeData();
  }

  /// 初始化数据
  Future<void> _initializeData() async {
    // 加载播放列表数据
    await _loadData();

    // 加载收藏列表
    _extractFavoriteList();

    // 延迟1分钟后执行版本检测
    Future.delayed(Duration(minutes: 1), () {
      CheckVersionUtil.checkVersion(context, false, false);
    });
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

  /// 异步加载视频数据
  Future<void> _loadData() async {
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
    if (_playerState == PlayerState.disposed) return;

    if (_videoMap?.playList?.isNotEmpty ?? false) {
      // 获取第一个可用的频道
      _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

      if (_currentChannel != null) {
        // 发送流量统计数据
        if (Config.Analytics) {
          await _sendTrafficAnalytics(context, _currentChannel!.title);
        }

        if (!_isSwitchingChannel) {
          await _playVideo();
        }
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

  /// 处理返回按键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      setState(() {
        _drawerIsOpen = false;
      });
      return false;
    }

    return await ShowExitConfirm.ExitConfirm(context);
  }

  @override
  void dispose() {
    // 更新状态
    _playerState = PlayerState.disposed;
    
    // 禁用保持屏幕唤醒功能
    WakelockPlus.disable();
    
    // 释放所有资源
    _resourceManager.disposeAll();
    
    super.dispose();
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
  Future<void> toggleFavorite(String channelId) async {
    if (_playerState == PlayerState.disposed) return;

    try {
      String actualChannelId = _currentChannel?.id ?? channelId;
      String groupName = getGroupName(actualChannelId);
      String channelName = getChannelName(actualChannelId);

      // 验证频道信息
      if (!_validateChannelInfo(groupName, channelName)) {
        return;
      }

      bool isFavoriteChanged = await _updateFavoriteStatus(
        groupName, 
        channelName, 
        actualChannelId
      );

      if (isFavoriteChanged) {
        await _saveFavoriteChanges();
      }
    } catch (e) {
      _handleFavoriteError();
    }
  }

  /// 验证频道信息
  bool _validateChannelInfo(String groupName, String channelName) {
    if (groupName.isEmpty || channelName.isEmpty) {
      CustomSnackBar.showSnackBar(
        context,
        S.current.channelnofavorite,
        duration: Duration(seconds: 4),
      );
      return false;
    }
    return true;
  }

  /// 更新收藏状态
  Future<bool> _updateFavoriteStatus(
    String groupName, 
    String channelName, 
    String channelId
  ) async {
    if (isChannelFavorite(channelId)) {
      return _removeFavorite(groupName, channelName);
    } else {
      return _addFavorite(groupName, channelName);
    }
  }

  /// 移除收藏
  Future<bool> _removeFavorite(String groupName, String channelName) async {
    favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
    if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
      favoriteList[Config.myFavoriteKey]!.remove(groupName);
    }
    
    CustomSnackBar.showSnackBar(
      context,
      S.current.removefavorite,
      duration: Duration(seconds: 4),
    );
    
    return true;
  }

  /// 添加收藏
  Future<bool> _addFavorite(String groupName, String channelName) async {
    favoriteList[Config.myFavoriteKey]![groupName] ??= {};

    PlayModel newFavorite = PlayModel(
      id: _currentChannel?.id ?? '',
      group: groupName,
      logo: _currentChannel?.logo,
      title: channelName,
      urls: getPlayUrls(_currentChannel?.id ?? ''),
    );
    
    favoriteList[Config.myFavoriteKey]![groupName]![channelName] = newFavorite;
    
    CustomSnackBar.showSnackBar(
      context,
      S.current.newfavorite,
      duration: Duration(seconds: 4),
    );
    
    return true;
  }

  /// 保存收藏更改
  Future<void> _saveFavoriteChanges() async {
    try {
      await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
      _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
      LogUtil.i('修改收藏列表后的播放列表: ${_videoMap}');
      await M3uUtil.saveCachedM3uData(_videoMap.toString());
      setState(() {}); // 重新渲染频道列表
    } catch (e) {
      _handleFavoriteError();
    }
  }

  /// 处理收藏操作错误
  void _handleFavoriteError() {
    CustomSnackBar.showSnackBar(
      context,
      S.current.newfavoriteerror,
      duration: Duration(seconds: 4),
    );
    LogUtil.e('收藏状态保存失败');
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;

    if (isTV) {
      return _buildTVLayout();
    }

    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) => _buildPortraitLayout(context),
        landscape: (context) => _buildLandscapeLayout(context),
      ),
    );
  }

  /// 构建TV布局
  Widget _buildTVLayout() {
    return TvPage(
      videoMap: _videoMap,
      playModel: _currentChannel,
      onTapChannel: _onTapChannel,
      toastString: toastString,
      controller: _resourceManager.controller,
      isBuffering: isBuffering,
      isPlaying: isPlaying,
      aspectRatio: aspectRatio,
      onChangeSubSource: _parseData,
      changeChannelSources: _changeChannelSources,
      toggleFavorite: toggleFavorite,
      isChannelFavorite: isChannelFavorite,
      currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
    );
  }

  /// 构建竖屏布局
  Widget _buildPortraitLayout(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return WillPopScope(
      onWillPop: () => _handleBackPress(context),
      child: MobileVideoWidget(
        toastString: toastString,
        controller: _resourceManager.controller,
        changeChannelSources: _changeChannelSources,
        isLandscape: false,
        isBuffering: isBuffering,
        isPlaying: isPlaying,
        aspectRatio: aspectRatio,
        onChangeSubSource: _parseData,
        drawChild: _buildChannelDrawer(false),
        toggleFavorite: toggleFavorite,
        currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
        isChannelFavorite: isChannelFavorite,
      ),
    );
  }

  /// 构建横屏布局
  Widget _buildLandscapeLayout(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return WillPopScope(
      onWillPop: () => _handleBackPress(context),
      child: Stack(
        children: [
          Scaffold(
            body: _buildMainContent(),
          ),
          Offstage(
            offstage: !_drawerIsOpen,
            child: GestureDetector(
              onTap: _closeDrawer,
              child: _buildChannelDrawer(true),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建主内容区域
  Widget _buildMainContent() {
    return toastString == 'UNKNOWN'
        ? EmptyPage(onRefresh: _parseData)
        : TableVideoWidget(
            toastString: toastString,
            controller: _resourceManager.controller,
            isBuffering: isBuffering,
            isPlaying: isPlaying,
            aspectRatio: aspectRatio,
            drawerIsOpen: _drawerIsOpen,
            changeChannelSources: _changeChannelSources,
            isChannelFavorite: isChannelFavorite,
            currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
            toggleFavorite: toggleFavorite,
            isLandscape: true,
            onToggleDrawer: _toggleDrawer,
          );
  }

  /// 构建频道抽屉
  Widget _buildChannelDrawer(bool isLandscape) {
    return ChannelDrawerPage(
      videoMap: _videoMap,
      playModel: _currentChannel,
      onTapChannel: _onTapChannel,
      isLandscape: isLandscape,
      onCloseDrawer: _closeDrawer,
    );
  }

  /// 关闭抽屉
  void _closeDrawer() {
    setState(() {
      _drawerIsOpen = false;
    });
  }

  /// 切换抽屉状态
  void _toggleDrawer() {
    setState(() {
      _drawerIsOpen = !_drawerIsOpen;
    });
  }

  /// 弹出选择不同的视频源
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

    // 切换到选中的视频源进行播放
    if (selectedIndex != null && 
        _sourceIndex != selectedIndex && 
        _playerState != PlayerState.disposed) {
      _sourceIndex = selectedIndex;
      _playVideo();
    }
  }
}
