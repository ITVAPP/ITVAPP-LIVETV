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

/// 重试配置类，用于配置播放器重试的各项参数
class BetterPlayerRetryConfig {
  final int maxRetries;
  final Duration retryDelay;
  final Duration timeoutDuration;
  final bool autoRetry;
  
  /// 构造函数，设置默认值
  const BetterPlayerRetryConfig({
    this.maxRetries = 1,          // 默认最多重试1次
    this.retryDelay = const Duration(seconds: 2),      // 默认重试间隔2秒
    this.timeoutDuration = const Duration(seconds: 18), // 默认超时时间18秒
    this.autoRetry = true,        // 默认启用自动重试
  });
}

/// 重试管理的Mixin，提供播放器重试相关的功能
mixin BetterPlayerRetryMixin {
  /// 当前重试次数
  int _retryCount = 0;
  Timer? _retryTimer;
  Timer? _timeoutTimer;
  /// 是否正在重试中
  bool _isRetrying = false;
  /// 是否正在销毁中
  bool _isDisposing = false;
  StreamSubscription? _eventSubscription;
  
  // 添加这个字段来保存事件监听器的引用
  void Function(BetterPlayerEvent)? _eventListener;
  
  /// 获取重试配置对象的抽象getter方法
  BetterPlayerRetryConfig get retryConfig;
  
  /// 获取播放器控制器的抽象方法 
  BetterPlayerController? get betterPlayerController;
  
  /// 重试开始时的回调
  void onRetryStarted();
  
  /// 重试失败时的回调
  void onRetryFailed();
  
  /// 需要切换视频源时的回调
  void onSourceSwitchNeeded();
  
  /// 初始化播放器
  Future<void> initializePlayer();
  
  /// 设置重试机制，监听播放器事件
  void setupRetryMechanism() {
       if (_playerController == null) return;
       
      // 确保清理之前的事件监听
      disposeRetryMechanism();
    
      if (_playerController == null) return;
    
      _eventListener = (BetterPlayerEvent event) {
       if (_isDisposing) return;

        switch (event.betterPlayerEventType) {
          case BetterPlayerEventType.initialized:
            _resetRetryState();
            break;
            
          case BetterPlayerEventType.exception:
            if (retryConfig.autoRetry && !_isDisposing) {
              _handlePlaybackError();
            }
            break;
            
          case BetterPlayerEventType.finished:
            if (retryConfig.autoRetry && !_isDisposing) {
              _resetAndReplay();
            }
            break;
          
          default:
            break;
        }
      };
    
      playerController!.addEventsListener(_eventListener!);
    
      // 如果配置了超时检测时间，启动超时检测
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
    
    // 判断是否还可以继续重试
    if (_retryCount < retryConfig.maxRetries) {
      _isRetrying = true;
      _retryCount++;
      
      // 触发重试开始回调
      onRetryStarted();
      
      // 取消之前的重试定时器
      _retryTimer?.cancel();
      // 延迟指定时间后重试
      _retryTimer = Timer(retryConfig.retryDelay, () async {
        if (_isDisposing) return;
        
        try {
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
      // 超过最大重试次数，触发失败回调并切换视频源
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
      
      // 检查播放状态，如果未在播放且不在重试中，则处理播放错误  
      final isPlaying = betterPlayerController?.isPlaying() ?? false;
      if (!isPlaying && !_isRetrying) {
        _handlePlaybackError();
      }
    });
  }
  
  /// 重置并重新播放
  Future<void> _resetAndReplay() async {
    if (_isDisposing) return;
    
    try {
      final controller = betterPlayerController;
      if (controller != null) {
        // 将播放位置重置到开始
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
  
  /// 清理重试机制相关资源
  void disposeRetryMechanism() {
    _isDisposing = true;
    if (_eventListener != null) {
      betterPlayerController?.removeEventsListener(_eventListener!);
    }
    _eventSubscription?.cancel();
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    _resetRetryState();
  }
}

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> with BetterPlayerRetryMixin {
  
  final BetterPlayerRetryConfig _retryConfig = const BetterPlayerRetryConfig();

  @override
  BetterPlayerRetryConfig get retryConfig => _retryConfig;

  @override
  BetterPlayerController? get betterPlayerController => _playerController;
  
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
  
  @override
  BetterPlayerController? get playerController => _playerController;

  // 是否处于缓冲状态
  bool isBuffering = false;

  // 是否正在播放
  bool isPlaying = false;

  // 视频的宽高比
  double aspectRatio = 1.78;

  // 标记侧边抽屉（频道选择）是否打开
  bool _drawerIsOpen = false;

  // 是否处于释放状态
  bool _isDisposing = false;

  // 切换时的竞态条件
  bool _isSwitchingChannel = false;

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
  void onRetryStarted() {
    if (mounted) {
      setState(() {
        toastString = S.current.retryplay;
      });
    }
  }

  @override
  void onRetryFailed() {
    if (mounted) {
      setState(() {
        toastString = S.current.playError;
      });
    }
  }

  @override
  void onSourceSwitchNeeded() {
    _handleSourceSwitch();
  }

  @override
  Future<void> initializePlayer() async {
    await _playVideo();
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
  
  // 判断是否是HLS流
  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.m3u8') || lowercaseUrl.endsWith('.m3u');
  }
  
/// 播放前解析频道的视频源 
Future<void> _playVideo() async {
    // 检查是否有可用的频道数据
    if (_currentChannel == null) return;
    
    // 更新UI显示当前播放的线路信息
    setState(() {
        toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
    });

    // 在创建新播放器之前，确保释放旧播放器的资源
    await _disposePlayer();
    
    try {
        // 从当前频道获取指定索引的URL并进行解析
        String url = _currentChannel!.urls![_sourceIndex].toString();
        
        // 创建流URL解析器并获取实际的播放地址
        _streamUrl = StreamUrl(url);
        String parsedUrl = await _streamUrl!.getStreamUrl();
        
        // 检查URL解析是否失败，如果失败则切换到下一个源
        if (parsedUrl == 'ERROR') {
            setState(() {
                toastString = S.current.vpnplayError;
            });
            _handleSourceSwitch();
            return;
        }

        // 检测是否为音频流，并更新状态
        bool isDirectAudio = _checkIsAudioStream(parsedUrl);
        setState(() {
          _isAudio = isDirectAudio;
        });

        // 记录日志
        LogUtil.i('准备播放：$parsedUrl');
        
        // 检测是否为hls流
        final bool isHls = _isHlsStream(parsedUrl);

        // 播放器的数据源配置
        BetterPlayerDataSource dataSource = BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          parsedUrl,
          liveStream: isHls,              // 根据URL判断是否为直播流
          useAsmsTracks: isHls,       // HLS 音轨
          useAsmsAudioTracks: isHls,  // HLS 音频轨道
          // 禁用系统通知栏的播放控制
          notificationConfiguration: const BetterPlayerNotificationConfiguration(
            showNotification: false,
          ),
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 60000,            // 最小缓冲时间(60秒)
            maxBufferMs: 360000,           // 最大缓冲时间(6分钟)
            bufferForPlaybackMs: 3000,     // 开始播放所需的最小缓冲(3秒)
            bufferForPlaybackAfterRebufferMs: 5000 // 重新缓冲后开始播放所需的最小缓冲(5秒)
          ),
          cacheConfiguration: BetterPlayerCacheConfiguration(
            useCache: true,                // 启用缓存
            preCacheSize: 30 * 1024 * 1024, // 预缓存大小
            maxCacheSize: 100 * 1024 * 1024, // 最大缓存大小
            maxCacheFileSize: 30 * 1024 * 1024, // 单个文件最大缓存大小
          ),
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
          },
        );

        // 创建播放器的基本配置
        BetterPlayerConfiguration betterPlayerConfiguration = BetterPlayerConfiguration(
          autoPlay: false,              // 自动播放
          fit: BoxFit.contain,         // 视频适配模式
          allowedScreenSleep: false,   // 禁止屏幕休眠
          autoDispose: true,           // 自动释放资源
          handleLifecycle: true,       // 处理生命周期事件
          // 全屏后支持的设备方向
          deviceOrientationsAfterFullScreen: [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
            DeviceOrientation.portraitUp,
          ],
          // 设置事件监听器
          eventListener: (BetterPlayerEvent event) {
            _videoListener(event);
          },
        );

        // 创建播放器控制器
        BetterPlayerController newController = BetterPlayerController(
          betterPlayerConfiguration,
        );
        
        // 禁用所有控件
        newController.setControlsEnabled(false);

        // 设置播放器的重试机制
        setupRetryMechanism();
        
        // 尝试设置数据源
        try {
            await newController.setupDataSource(dataSource);
        } catch (e, stackTrace) {
            newController.dispose();  // 出错时释放控制器资源
            _handleSourceSwitch();    // 切换到下一个源
            LogUtil.logError('初始化出错', e, stackTrace);
            return;
        }

        // 确保组件还在树中且未处于释放状态
        if (!mounted || _isDisposing) {
            newController.dispose();
            return;
        }

        // 更新状态，设置新的控制器
        setState(() {
            _playerController = newController;
            toastString = S.current.loading;
        }); 
        
        // 开始播放
        await _playerController?.play();
   
    } catch (e, stackTrace) {
        // 捕获并记录所有其他错误，然后尝试切换源
        LogUtil.logError('播放出错', e, stackTrace);
        _handleSourceSwitch();
    }
}

/// 播放器监听方法
void _videoListener(BetterPlayerEvent event) {
    if (_playerController == null || _isDisposing) return;

    switch (event.betterPlayerEventType) {
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
            
        case BetterPlayerEventType.bufferingStart:
        case BetterPlayerEventType.bufferingUpdate:
        case BetterPlayerEventType.bufferingEnd:
            if (mounted) {
                setState(() {
                    isBuffering = event.betterPlayerEventType == BetterPlayerEventType.bufferingStart ||
                                event.betterPlayerEventType == BetterPlayerEventType.bufferingUpdate;
                });
            }
            break;
            
        case BetterPlayerEventType.play:
        case BetterPlayerEventType.pause:
            if (mounted) {
                setState(() {
                    isPlaying = event.betterPlayerEventType == BetterPlayerEventType.play;
                });
            }
            break;
            
        default:
            break;
    }
}

/// 处理视频源切换的方法
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

    // 检查新的源是否为音频
    bool isDirectAudio = _checkIsAudioStream(urls[_sourceIndex]);
    setState(() {
        _isAudio = isDirectAudio;
        toastString = S.current.switchLine(_sourceIndex + 1);
    });

    // 直接重新初始化播放器
    initializePlayer();
}

/// 播放器资源释放方法
Future<void> _disposePlayer() async {
    if (_isDisposing) return;
    
    _isDisposing = true;
    final currentController = _playerController;
    
    try {
        if (currentController != null) {
            disposeRetryMechanism(); // 清理重试机制
            
            // 停止播放
            if (currentController.isPlaying() ?? false) {
                try {
                    await currentController.pause();  // pause() 返回 Future
                } catch (e) {
                    LogUtil.logError('暂停播放时出错', e);
                }
            }
            
            // 清理数据源
            try {
                currentController.clearCache();  // clearCache() 是同步方法
            } catch (e) {
                LogUtil.logError('清理缓存时出错', e);
            }
            
            // 释放流资源
            _disposeStreamUrl();
            
            // 释放控制器
            try {
                currentController.dispose(forceDispose: true);  // dispose() 是同步方法
            } catch (e) {
                LogUtil.logError('释放播放器时出错', e);
            }
            
            // 清空控制器引用
            if (_playerController == currentController) {
                _playerController = null;
            }
        }
    } catch (e, stackTrace) {
        LogUtil.logError('释放播放器资源时出错', e, stackTrace);
    } finally {
        _isDisposing = false;
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
    
    setState(() {
        _isSwitchingChannel = true;
        toastString = S.current.loading;
    });
    
    try {
        await _disposePlayer();  // 确保先释放当前播放器资源
        
        // 更新频道信息
        _currentChannel = model;
        _sourceIndex = 0;
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
        if (!_isSwitchingChannel) return;
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

/// 切换视频源方法
Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources == null || sources.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return;
    }

    disposeRetryMechanism(); // 切换源前清理重试机制

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

    if (selectedIndex != null && _sourceIndex != selectedIndex) {
      _sourceIndex = selectedIndex;
      bool isDirectAudio = _checkIsAudioStream(sources[selectedIndex]);
      setState(() {
        _isAudio = isDirectAudio;
      });
      await _playVideo();
    } else {
      setupRetryMechanism(); // 如果没有切换源，重新设置重试机制
    }
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

    // 延迟1分钟后执行版本检测
    Future.delayed(const Duration(minutes: 1), () {
      CheckVersionUtil.checkVersion(context, false, false);
    });
}

/// 清理所有资源
@override
void dispose() {
    _isDisposing = true;
    disposeRetryMechanism();  // 清理重试机制
    WakelockPlus.disable();
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
    disposeRetryMechanism(); // 先清理当前的重试机制
    
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
        
        await _playVideo(); // 会重新设置重试机制
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
