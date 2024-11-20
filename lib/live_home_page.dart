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

class _LiveHomePageState extends State<LiveHomePage> {
	
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
  BetterPlayerController? _playerController;

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

  // 添加当前播放URL变量
  String? _currentPlayUrl;

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
    return lowercaseUrl.endsWith('.mp3') || 
           lowercaseUrl.endsWith('.aac') || 
           lowercaseUrl.endsWith('.m4a') ||
           lowercaseUrl.endsWith('.ogg') ||
           lowercaseUrl.endsWith('.wav');
  }
  
  // 判断是否是HLS流
  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.m3u8') || lowercaseUrl.endsWith('.m3u');
  }
  
/// 播放前解析频道的视频源 
Future<void> _playVideo() async {
    if (_currentChannel == null) return;

    setState(() {
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
        _isRetrying = false;  // 播放开始时重置重试状态
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
        
        // 判断是否是 YouTube HLS 直播流
        final bool isYoutubeHls = _streamUrl!.isYTUrl(parsedUrl) && isHls;

        LogUtil.i('准备播放：$parsedUrl ,音频：$isDirectAudio ,是否为YThls流：$isYoutubeHls');

        // 使用配置工具类创建数据源
        final dataSource = VideoPlayerConfig.createDataSource(
          url: parsedUrl,
          isHls: isHls,
        );

        // 创建播放器配置
        final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
          toastString: toastString,
          eventListener: _videoListener,
        );

        // 启动超时检测
        _startTimeoutCheck();
        
        // 创建播放器控制器
        BetterPlayerController newController = BetterPlayerController(
          betterPlayerConfiguration,
        );
        
        // 禁用所有控件
        // newController.setControlsEnabled(false);

        try {
            await newController.setupDataSource(dataSource);
        } catch (e, stackTrace) {
            _handleSourceSwitch();
            LogUtil.logError('初始化出错', e, stackTrace);
            return; 
        }

        // 设置新的控制器
        setState(() {
            _playerController = newController;
            toastString = S.current.loading;
            _retryCount = 0;
            _timeoutActive = false;
        });
        
        await _playerController?.play();
   
    } catch (e, stackTrace) {
        LogUtil.logError('播放出错', e, stackTrace);
        _handleError(); 
    }
}

/// 播放器监听方法
void _videoListener(BetterPlayerEvent event) {
    if (_playerController == null || _isDisposing || _isRetrying) return;

    // 根据事件类型执行不同的处理逻辑
    switch (event.betterPlayerEventType) {
        // 当事件类型为播放器初始化完成时，更新视频的宽高比
        case BetterPlayerEventType.initialized:
            if (mounted) {
                setState(() {
                    if (_shouldUpdateAspectRatio) {
                        aspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? 1.78;
                        _shouldUpdateAspectRatio = false;  
                    }
                });
            }
            break;
        
        // 当事件类型为异常时，调用错误处理函数
        case BetterPlayerEventType.exception:
        	final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
                LogUtil.e('监听到播放器错误：$errorMessage');
            break;
        
        // 当事件类型为缓冲开始、缓冲更新或缓冲结束时，更新缓冲状态
        case BetterPlayerEventType.bufferingStart:
        case BetterPlayerEventType.bufferingUpdate:
        case BetterPlayerEventType.bufferingEnd:
            if (mounted) {
                setState(() {
                    // 如果事件类型为缓冲开始或缓冲更新，将 isBuffering 设为 true；缓冲结束时设为 false
                    isBuffering = event.betterPlayerEventType == BetterPlayerEventType.bufferingStart || event.betterPlayerEventType == BetterPlayerEventType.bufferingUpdate;
                });
            }
            break;
        
        // 当事件类型为播放或暂停时，更新播放状态
        case BetterPlayerEventType.play:
        case BetterPlayerEventType.pause:
            if (mounted) {
                setState(() {
                    // 如果事件类型为 play，将 isPlaying 设为 true；pause 时设为 false
                    isPlaying = event.betterPlayerEventType == BetterPlayerEventType.play;
                    toastString = 'HIDE_CONTAINER';  // 不渲染VideoHoldBg底部容器
                });
            }
            break;
        
        // 当事件类型为播放结束时，切换到下一个源
        case BetterPlayerEventType.finished:
            break;
        
        // 默认情况，忽略所有其他未处理的事件类型
        default:
            break;
    }
}

/// 处理播放器发生错误的方法
void _handleError() {
    if (_retryCount < defaultMaxRetries) {
        _retryPlayback();  // 如果重试次数未超限，则进行重试播放
    } else {
        _handleSourceSwitch();  // 重试次数超限时切换到其他视频源
    }
}

/// 超时检测方法，用于检测播放启动超时
void _startTimeoutCheck() {
    if (_timeoutActive || _isRetrying) return;
    _timeoutActive = true;  // 标记超时检测已启动
    Timer(Duration(seconds: defaultTimeoutSeconds), () {
      if (!_timeoutActive || _isRetrying) return;
      
      // 检查播放器是否存在且未播放
      if (_playerController != null && !(_playerController!.isPlaying() ?? false) && !isBuffering) { 
        LogUtil.logError('播放超时', '$defaultTimeoutSeconds seconds');
        _retryPlayback(); 
      }
    });
}

/// 重试播放方法，用于重新尝试播放失败的视频
void _retryPlayback() {
    if (_isRetrying) return;
    
    _timeoutActive = false;  // 重试期间取消超时检测

    // 检查是否在重试次数范围内
    if (_retryCount <= defaultMaxRetries) {
        setState(() {
            _isRetrying = true;  // 标记进入重试状态
            _retryCount += 1;  // 增加重试计数
            toastString = S.current.retryplay; 
        });
        
        // 取消当前的重试计时器
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 2), () {
            _playVideo();  // 再次尝试播放
        });
    } else {
        _handleSourceSwitch();  // 重试次数用尽，切换视频源
    }
}

/// 处理视频源切换的方法（自动）
void _handleSourceSwitch() {
    // 先停止当前播放和清理状态
    _disposePlayer();
    
    // 获取当前频道的视频源列表
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

    // 延迟后尝试新源
    _retryTimer = Timer(const Duration(seconds: 2), () {
        _playVideo();
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
        _timeoutActive = false;
        _retryTimer?.cancel();
        _isRetrying = false;
        _retryCount = 0;
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
      } catch (e) {
        LogUtil.logError('释放播放器资源时出错', e);
      }
    }
  } catch (e, stackTrace) {
    LogUtil.logError('释放播放器资源时出错', e, stackTrace);
  } finally {
    _isDisposing = false; 
    if (mounted) {
      setState(() {});
    }
  }
}

/// 释放 StreamUrl 实例
void _disposeStreamUrl() {
    if (_streamUrl != null) {
      _streamUrl!.dispose();
      _streamUrl = null;
    }
}

/// 处理频道切换操作
Future<void> _onTapChannel(PlayModel? model) async {
    if (_isSwitchingChannel || model == null) return;
      
    try {
        // 更新频道信息
        setState(() {
            _isSwitchingChannel = true;
            _currentChannel = model;
            _sourceIndex = 0;
            _shouldUpdateAspectRatio = true;
            toastString = S.current.loading; // 更新加载状态
        });
        
        // 先停止当前播放和清理状态
        await _disposePlayer(); 
         
        // 确保状态正确后开始新的播放
        if (!_isSwitchingChannel) return; // 如果状态已改变则退出
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
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }
    
    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
    // 先停止当前播放和清理状态
    await _disposePlayer(); 
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
    _retryTimer?.cancel();
    _timeoutActive = false;
    _isRetrying = false;
    _isAudio = false;
    WakelockPlus.disable();
    _isDisposing = true;
    _disposePlayer();
    super.dispose();
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
