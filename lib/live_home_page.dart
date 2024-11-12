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
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'channel_drawer_page.dart';
import 'mobile_video_widget.dart';
import 'table_video_widget.dart';
import 'tv/tv_page.dart';
import 'util/player_manager.dart';
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

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  // 播放器管理器实例
  late final PlayerManager _playerManager;
  
  // 超时重试次数
  static const int defaultMaxRetries = 1;
  
  // 超时检测的时间
  static const int defaultTimeoutSeconds = 18;
  
  // 新增重试相关的状态管理
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
  VlcPlayerController? _playerController;

  // 视频的宽高比
  double get aspectRatio => _playerManager.state.aspectRatio;
  
  // 是否处于缓冲状态
  bool get isBuffering => _playerManager.state.isBuffering;
  
  // 是否正在播放
  bool get isPlaying => _playerManager.state.isPlaying;

  // 标记侧边抽屉（频道选择）是否打开
  bool _drawerIsOpen = false;

  // 重试次数计数器
  int _retryCount = 0;

  // 最大重试次数
  final int maxRetries = defaultMaxRetries;

  // 等待超时检测
  bool _timeoutActive = false;

  // 是否处于释放状态
  bool _isDisposing = false;

  // 切换时的竞态条件
  bool _isSwitchingChannel = false;

  // 超时检测时间
  final int timeoutSeconds = defaultTimeoutSeconds;

  // 标记是否需要更新宽高比
  bool _shouldUpdateAspectRatio = true;

  // 声明变量，存储 StreamUrl 类的实例
  StreamUrl? _streamUrl;

  // 收藏列表相关
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  
  // 抽屉刷新键
  ValueKey<int>? _drawerRefreshKey;

  // 实例化 TrafficAnalytics 流量统计
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics();

  // 音频检测状态
  bool _isAudio = false;

  @override
  void initState() {
    super.initState();
    _playerManager = PlayerManager(
      onError: (error) {
        LogUtil.e('播放器错误：$error');
        _handleSourceSwitch();
      }
    );
    
    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    // 加载播放列表数据
    _loadData();

    // 加载收藏列表
    _extractFavoriteList();

    // 延迟1分钟后执行版本检测
    Future.delayed(Duration(minutes: 1), () {
      CheckVersionUtil.checkVersion(context, false, false);
    });
  }

  // 检查是否为音频流
  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.mp3') || 
           lowercaseUrl.endsWith('.aac') || 
           lowercaseUrl.endsWith('.m4a') ||
           lowercaseUrl.endsWith('.ogg') ||
           lowercaseUrl.endsWith('.wav');
  }

  /// 播放前解析频道的视频源 
  Future<void> _playVideo() async {
    if (_currentChannel == null || _currentChannel!.urls == null || 
        _currentChannel!.urls!.isEmpty || _sourceIndex >= _currentChannel!.urls!.length) {
      setState(() {
        toastString = S.current.playError;
      });
      return;
    }

    setState(() {
      toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
      _isRetrying = false;
    });

    try {
      // 解析URL
      String url = _currentChannel!.urls![_sourceIndex].toString();
      _streamUrl = StreamUrl(url);
      String parsedUrl = await _streamUrl!.getStreamUrl();

      if (parsedUrl == 'ERROR') {
        setState(() {
          toastString = S.current.vpnplayError;
        });
        _handleSourceSwitch();
        return;
      }

      // 检查是否为音频
      setState(() {
        _isAudio = _checkIsAudioStream(parsedUrl);
      });

      LogUtil.i('准备播放：$parsedUrl');
      
      // 释放旧播放器
      await _playerManager.dispose();
      
      // 启动超时检测
      _startTimeoutCheck();

      // 初始化新播放器
      bool initialized = await _playerManager.initializePlayer(
        parsedUrl,
        onError: (error) {
          LogUtil.e('播放器错误：$error');
          _handleSourceSwitch();
        },
      );

      if (!initialized || !mounted) return;

      // 设置状态和开始播放
      setState(() {
        _playerController = _playerManager.controller;
        toastString = S.current.loading;
        _retryCount = 0;
        _timeoutActive = false;
      });

      // 添加监听器
      _playerController?.addListener(_videoListener);
      
      // 开始播放
      await _playerManager.play();

    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      setState(() {
        _isRetrying = false;
      });
      _handleSourceSwitch();
    }
  }

  /// 视频状态监听器
  void _videoListener() {
    if (_playerController == null || _isDisposing || _isRetrying) return;

    try {
      _playerManager.updateState(_playerController!);
      _shouldUpdateAspectRatio = false;

      // 检查错误状态
      if (_playerManager.state.hasError) {
        LogUtil.logError('播放器错误', _playerManager.state.errorMessage ?? 'Unknown Error');
        _handleSourceSwitch();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('监听器错误', e, stackTrace);
    }
  }

  /// 超时检测方法
  void _startTimeoutCheck() {
    if (_timeoutActive || _isRetrying) return;
    
    _timeoutActive = true;
    Timer(Duration(seconds: timeoutSeconds), () {
      if (!_timeoutActive || _isRetrying) return;
      
      if (_playerController != null && 
          _playerController!.value.playingState != PlayingState.playing && 
          _playerController!.value.playingState != PlayingState.buffering) {
        LogUtil.e('播放超时：$timeoutSeconds seconds');
        _retryPlayback();
      }
    });
  }

  /// 重试播放方法
  void _retryPlayback() {
    if (_isRetrying) return;
    
    _isRetrying = true;
    _timeoutActive = false;
    _retryCount += 1;

    if (_retryCount <= maxRetries) {
      setState(() {
        toastString = S.current.retryplay;
      });
      
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 3), () {
        setState(() {
           _isRetrying = false;
        });
        _playVideo();
      });
    } else {
      _handleSourceSwitch();
    }
  }
  
/// 处理视频源切换的方法
  void _handleSourceSwitch() {
    final List<String>? urls = _currentChannel?.urls;  // 获取当前频道的视频源列表
    if (urls == null || urls.isEmpty) {
      setState(() {
        toastString = S.current.playError;
        _isRetrying = false;
        _retryCount = 0;
      });
      return;
    }

    // 切换到下一个源
    _sourceIndex += 1;
    if (_sourceIndex >= urls.length) {
      setState(() {
        toastString = S.current.playError;
        _isRetrying = false;  
      });
      return;
    }

    // 检查新的源是否为音频
    bool isDirectAudio = _checkIsAudioStream(urls[_sourceIndex]);
    setState(() {
      _isAudio = isDirectAudio;
      toastString = S.current.switchLine(_sourceIndex + 1);
    });

    // 延迟后尝试新源
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      setState(() {
        _retryCount = 0;  // 新源从0开始计数重试
      });
      _playVideo();
    });
  }

  /// 处理频道切换操作
  Future<void> _onTapChannel(PlayModel? model) async {
    if (_isSwitchingChannel || model == null) return;
    
    setState(() {
      _isSwitchingChannel = true;
      toastString = S.current.loading; // 更新加载状态
    });
    
    try {
      _retryTimer?.cancel();
      setState(() { 
        _isRetrying = false;
        _timeoutActive = false;
      });
      
      // 更新频道信息
      _currentChannel = model;
      _sourceIndex = 0;
      _retryCount = 0;
      _shouldUpdateAspectRatio = true;

      // 检查新频道是否为音频
      final String? url = model.urls?.isNotEmpty == true ? model.urls![0] : null;
      bool isDirectAudio = _checkIsAudioStream(url);
      setState(() {
        _isAudio = isDirectAudio;
      });

      // 发送统计数据
      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }

      // 确保状态正确后开始新的播放
      if (!_isSwitchingChannel) return; // 如果状态已改变则退出
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

  /// 异步加载视频数据
  Future<void> _loadData() async {
    // 重置所有状态
    _retryTimer?.cancel();
    setState(() { 
      _isRetrying = false;
      _timeoutActive = false;
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
        bool isDirectAudio = _checkIsAudioStream(url);
        setState(() {
          _isAudio = isDirectAudio;
        });

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

  /// 切换视频源的外部调用方法
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }

    _retryTimer?.cancel();
    _isRetrying = false;
    _timeoutActive = false;

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      bool isDirectAudio = _checkIsAudioStream(sources[selectedIndex]);
      setState(() {
        _isAudio = isDirectAudio;
      });
      _retryCount = 0;
      _playVideo();
    }
  }

  /// 发送页面访问统计数据
  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        await _trafficAnalytics.sendPageView(context, "LiveHomePage", additionalPath: channelName);
      } catch (e, stackTrace) {
        LogUtil.logError('发送流量统计时发生错误', e, stackTrace);
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

    final isPlaying = _playerController?.value.playingState == PlayingState.playing;
    if (isPlaying) {
      await _playerController?.pause();
    }

    bool shouldExit = await ShowExitConfirm.ExitConfirm(context);
    
    if (!shouldExit && isPlaying && mounted) {
      await _playerController?.play();
    }
    
    return shouldExit;
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
        // 更新刷新键，触发抽屉重建
        setState(() {
          _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
        });
      } catch (error, stackTrace) {
        CustomSnackBar.showSnackBar(
          context,
          S.current.newfavoriteerror,
          duration: Duration(seconds: 4),
        );
        LogUtil.logError('收藏状态保存失败', error, stackTrace);
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _timeoutActive = false;
    _isRetrying = false;
    WakelockPlus.disable();
    _playerManager.dispose();
    super.dispose();
  }

  /// 播放器公共属性
  Map<String, dynamic> _buildCommonProps() {
    return {
      'videoMap': _videoMap,
      'playModel': _currentChannel,
      'onTapChannel': _onTapChannel,
      'toastString': toastString,
      'controller': _playerController,
      'isBuffering': isBuffering,
      'isPlaying': _playerController?.value.playingState == PlayingState.playing,
      'aspectRatio': aspectRatio,
      'onChangeSubSource': _parseData,
      'changeChannelSources': _changeChannelSources,
    };
  }
  
@override
  Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;

    if (isTV) {
      return ValueListenableBuilder<bool>(
        valueListenable: _playerManager.state.playingNotifier,
        builder: (context, isPlaying, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: _playerManager.state.bufferingNotifier,
            builder: (context, isBuffering, _) {
              return TvPage(
                videoMap: _videoMap,
                playModel: _currentChannel,
                onTapChannel: _onTapChannel,
                toastString: toastString,
                controller: _playerController,
                isBuffering: isBuffering,
                isPlaying: isPlaying,
                aspectRatio: _playerManager.state.aspectRatio,
                onChangeSubSource: _parseData,
                changeChannelSources: _changeChannelSources,
                toggleFavorite: toggleFavorite,
                isChannelFavorite: isChannelFavorite,
                currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
                isAudio: _isAudio,
                onInit: _playerManager.onPlatformViewCreated,
              );
            }
          );
        }
      );
    }

    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return WillPopScope(
            onWillPop: () => _handleBackPress(context),
            child: ValueListenableBuilder<bool>(
              valueListenable: _playerManager.state.playingNotifier,
              builder: (context, isPlaying, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _playerManager.state.bufferingNotifier,
                  builder: (context, isBuffering, _) {
                    return MobileVideoWidget(
                      toastString: toastString,
                      controller: _playerController,
                      changeChannelSources: _changeChannelSources,
                      isLandscape: false,
                      isBuffering: isBuffering,
                      isPlaying: isPlaying,
                      aspectRatio: _playerManager.state.aspectRatio,
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
                      isChannelFavorite: isChannelFavorite,
                      isAudio: _isAudio,
                      onInit: _playerManager.onPlatformViewCreated,
                    );
                  }
                );
              }
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
                      : ValueListenableBuilder<bool>(
                          valueListenable: _playerManager.state.playingNotifier,
                          builder: (context, isPlaying, _) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _playerManager.state.bufferingNotifier,
                              builder: (context, isBuffering, _) {
                                return TableVideoWidget(
                                  toastString: toastString,
                                  controller: _playerController,
                                  isBuffering: isBuffering,
                                  isPlaying: isPlaying,
                                  aspectRatio: _playerManager.state.aspectRatio,
                                  drawerIsOpen: _drawerIsOpen,
                                  changeChannelSources: _changeChannelSources,
                                  isChannelFavorite: isChannelFavorite,
                                  currentChannelId: _currentChannel?.id ?? 'exampleChannelId',
                                  toggleFavorite: toggleFavorite,
                                  isLandscape: true,
                                  isAudio: _isAudio,
                                  onInit: _playerManager.onPlatformViewCreated,
                                  onToggleDrawer: () {
                                    setState(() {
                                      _drawerIsOpen = !_drawerIsOpen;
                                    });
                                  },
                                );
                              }
                            );
                          }
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
