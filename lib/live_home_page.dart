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
import 'package:synchronized/synchronized.dart';
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
  loading,    // 加载中
  playing,    // 播放中
  paused,     // 暂停
  buffering,  // 缓冲中
  error,      // 错误
  disposed    // 已释放
}

/// 播放器错误类型
class PlayerError extends Error {
  final String code;
  final String message;
  final dynamic details;
  
  PlayerError(this.code, this.message, [this.details]);
  
  @override
  String toString() => 'PlayerError($code): $message';
}

/// 资源跟踪器
class ResourceTracker {
  final Map<String, Completer<void>> _pendingOperations = {};
  final _activeResources = <String, Object>{};
  
  Future<void> trackOperation(String key, Future<void> Function() operation) async {
    if (_pendingOperations.containsKey(key)) {
      return _pendingOperations[key]!.future;
    }
    
    final completer = Completer<void>();
    _pendingOperations[key] = completer;
    
    try {
      await operation();
      completer.complete();
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _pendingOperations.remove(key);
    }
  }
  
  void trackResource(String key, Object resource) {
    _activeResources[key] = resource;
  }
  
  void releaseResource(String key) {
    _activeResources.remove(key);
  }
  
  bool hasActiveResources() => _activeResources.isNotEmpty;
}

/// 重试策略配置
class RetryStrategy {
  final Duration initialDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final bool shouldSwitchSource;
  
  const RetryStrategy({
    this.initialDelay = const Duration(seconds: 3),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 3,
    this.shouldSwitchSource = true,
  });
}

/// 主页面类，展示直播流
class LiveHomePage extends StatefulWidget {
  final PlaylistModel m3uData; // 接收上个页面传递的 PlaylistModel 数据

  const LiveHomePage({super.key, required this.m3uData});

  @override
  State<LiveHomePage> createState() => _LiveHomePageState();
}

class _LiveHomePageState extends State<LiveHomePage> {
  // 常量定义
  static const int defaultMaxRetries = 1;        // 默认最大重试次数
  static const int defaultTimeoutSeconds = 18;   // 默认超时时间(秒)
  static const int retryDelaySeconds = 3;        // 重试延迟时间(秒)
  static const double defaultAspectRatio = 1.78; // 默认视频宽高比
  
class _LiveHomePageState extends State<LiveHomePage> {
  // 状态变量
  PlayerState _playerState = PlayerState.initial; // 播放器状态
  String toastString = S.current.loading;         // 加载状态提示文字
  PlaylistModel? _videoMap;                       // 视频播放列表数据模型
  PlayModel? _currentChannel;                     // 当前播放的频道数据模型
  int _sourceIndex = 0;                           // 当前选中的视频源索引
  VideoPlayerController? _playerController;       // 视频播放器控制器
  bool isBuffering = false;                       // 是否处于缓冲状态
  bool isPlaying = false;                         // 是否正在播放
  double aspectRatio = defaultAspectRatio;        // 视频的宽高比
  bool _drawerIsOpen = false;                     // 侧边抽屉是否打开
  bool isDebugMode = false;                       // 调试模式开关
  
  // 资源管理相关
  final ResourceTracker _resourceTracker = ResourceTracker(); // 资源跟踪器
  final Lock _playerLock = Lock();                // 播放器操作锁
  
  // 播放控制相关
  int _retryCount = 0;                           // 重试次数计数器
  Timer? _timeoutTimer;                          // 超时计时器
  final RetryStrategy _retryStrategy = const RetryStrategy(
    initialDelay: Duration(seconds: retryDelaySeconds),
    maxAttempts: defaultMaxRetries,
    maxDelay: Duration(seconds: defaultTimeoutSeconds),
  );
  
  // 状态控制标志
  bool _isDisposing = false;                     // 是否处于释放状态
  bool _isInitialized = false;                   // 播放器是否已初始化
  bool _isRetrying = false;                      // 是否正在重试中
  bool _isSwitchingChannel = false;              // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true;          // 是否需要更新宽高比
  
  // 资源实例
  StreamUrl? _streamUrl;                         // 流媒体URL解析实例
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量统计实例
  
  // 收藏列表
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  };
  
  /// 更新播放器状态
  Future<void> _updatePlayerState(PlayerState newState) async {
    if (_playerState == newState) return;
    
    if (mounted) {
      setState(() {
        _playerState = newState;
        toastString = _getToastForState(newState);
      });
    }
  }
  
  /// 根据播放器状态获取提示文字
  String _getToastForState(PlayerState state) {
    switch (state) {
      case PlayerState.initial:
        return S.current.loading;
      case PlayerState.loading:
        return S.current.loading;
      case PlayerState.playing:
        return '';
      case PlayerState.paused:
        return S.current.paused;
      case PlayerState.buffering:
        return S.current.buffering;
      case PlayerState.error:
        return S.current.playError;
      case PlayerState.disposed:
        return '';
      default:
        return '';
    }
  }

  /// 播放器资源释放
  Future<void> _disposePlayer() async {
    return _resourceTracker.trackOperation('dispose_player', () async {
      // 使用锁确保资源释放的原子性
      return _playerLock.synchronized(() async {
        if (_playerState == PlayerState.disposed) return;
        
        await _updatePlayerState(PlayerState.disposed);
        final controller = _playerController;
        _playerController = null;
        
        if (controller != null) {
          _resourceTracker.trackResource('player_controller', controller);
          
          try {
            // 1. 首先暂停播放
            if (controller.value.isPlaying) {
              await controller.pause();
            }
            
            // 2. 取消所有监听和计时器
            _cancelTimeoutCheck();
            controller.removeListener(_videoListener);
            
            // 3. 释放关联资源
            _disposeStreamUrl();
            
            // 4. 释放控制器
            await controller.dispose();
            _resourceTracker.releaseResource('player_controller');
            
          } catch (e, stack) {
            LogUtil.logError('释放播放器资源时出错', e, stack);
          } finally {
            _resetPlayerState();
          }
        }
      });
    });
  }

  /// 重置播放器状态
  void _resetPlayerState() {
    if (mounted) {
      setState(() {
        isBuffering = false;
        isPlaying = false;
        _shouldUpdateAspectRatio = true;
        _isInitialized = false;
      });
    }
  }
  
/// 释放 StreamUrl 实例
  void _disposeStreamUrl() {
    if (_streamUrl != null) {
      _resourceTracker.trackResource('stream_url', _streamUrl!);
      _streamUrl!.dispose();
      _streamUrl = null;
      _resourceTracker.releaseResource('stream_url');
    }
  }

  /// 开始超时检测
  void _startTimeoutCheck() {
    _cancelTimeoutCheck();
    
    _timeoutTimer = Timer(_retryStrategy.maxDelay, () {
      if (_playerState != PlayerState.disposed && 
          _playerController != null && 
          (!_playerController!.value.isPlaying || _playerController!.value.hasError)) {
        _retryPlayback();
      }
    });
  }

  /// 取消超时检测
  void _cancelTimeoutCheck() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// 播放前解析频道的视频源
  Future<void> _playVideo() async {
    if (_currentChannel == null || _playerState == PlayerState.disposed) return;
    
    return _resourceTracker.trackOperation('play_video', () async {
      try {
        await _updatePlayerState(PlayerState.loading);
        setState(() {
          toastString = S.current.lineToast(_sourceIndex + 1, _currentChannel!.title ?? '');
        });
        
        // 1. 确保之前的播放器已释放
        await _disposePlayer();
        
        // 2. 解析URL
        final url = _currentChannel!.urls?[_sourceIndex];
        if (url == null) {
          throw PlayerError('invalid_url', '无效的视频源URL');
        }
        
        _streamUrl = StreamUrl(url);
        final parsedUrl = await _streamUrl!.getStreamUrl();
        
        if (parsedUrl == 'ERROR') {
          throw PlayerError('parse_error', '解析播放地址失败');
        }
        
        // 3. 调试模式确认
        if (isDebugMode) {
          final shouldPlay = await _showConfirmationDialog(context, parsedUrl);
          if (!shouldPlay) {
            await _updatePlayerState(PlayerState.paused);
            return;
          }
        }
        
        // 4. 创建新的播放器
        if (_playerState == PlayerState.disposed) return;
        
        _playerController = VideoPlayerController.networkUrl(
          Uri.parse(parsedUrl),
          videoPlayerOptions: VideoPlayerOptions(
            allowBackgroundPlayback: false,
            mixWithOthers: false,
            webOptions: const VideoPlayerWebOptions(
              controls: VideoPlayerWebOptionsControls.enabled()
            ),
          ),
        )..setVolume(1.0);
        
        // 5. 初始化播放器
        await _playerController?.initialize();
        
        if (_playerState == PlayerState.disposed) {
          await _disposePlayer();
          return;
        }
        
        _isInitialized = true;
        _playerController?.addListener(_videoListener);
        
        // 6. 开始播放
        await _playerController?.play();
        await _updatePlayerState(PlayerState.playing);
        
        // 7. 重置状态
        _retryCount = 0;
        _startTimeoutCheck();
        
      } catch (e, stackTrace) {
        LogUtil.logError('播放失败', e, stackTrace);
        await _handleError('播放视频', e, stackTrace);
      } finally {
        _isSwitchingChannel = false;
      }
    });
  }

  /// 统一错误处理
  Future<void> _handleError(String operation, dynamic error, StackTrace? stackTrace) async {
    LogUtil.logError('$operation 失败', error, stackTrace);
    
    if (error is PlayerError) {
      switch (error.code) {
        case 'network_error':
          await _handleNetworkError(error);
          break;
        case 'parse_error':
          await _handleParseError(error);
          break;
        default:
          await _updatePlayerState(PlayerState.error);
      }
    } else {
      await _updatePlayerState(PlayerState.error);
      if (!_isDisposing) {
        _retryPlayback();
      }
    }
  }

  /// 处理网络错误
  Future<void> _handleNetworkError(PlayerError error) async {
    await _updatePlayerState(PlayerState.error);
    if (mounted) {
      setState(() {
        toastString = S.current.networkError;
      });
    }
    _retryPlayback();
  }

  /// 处理解析错误
  Future<void> _handleParseError(PlayerError error) async {
    await _updatePlayerState(PlayerState.error);
    if (mounted) {
      setState(() {
        toastString = S.current.parseError;
      });
    }
    _retryPlayback();
  }
  
/// 处理播放失败的逻辑，进行重试或切换线路
  Future<void> _retryPlayback() async {
    if (_isRetrying) return;
    
    return _resourceTracker.trackOperation('retry_playback', () async {
      final retryTimeout = Timer(const Duration(seconds: 30), () {
        _isRetrying = false;
        if (mounted) {
          _updatePlayerState(PlayerState.error);
        }
      });
      
      try {
        _isRetrying = true;
        _cancelTimeoutCheck();
        _retryCount++;

        if (_retryCount <= _retryStrategy.maxAttempts) {
          await _handleRetry();
        } else {
          await _handleSourceSwitch();
        }
      } finally {
        retryTimeout.cancel();
        _isRetrying = false;
      }
    });
  }

  /// 处理重试逻辑
  Future<void> _handleRetry() async {
    if (mounted) {
      await _updatePlayerState(PlayerState.loading);
      setState(() {
        toastString = S.current.retryplay;
      });
    }
    
    await Future.delayed(_retryStrategy.initialDelay);
    if (_playerState != PlayerState.disposed) {
      await _disposePlayer();
      await _playVideo();
    }
  }

  /// 处理视频源切换
  Future<void> _handleSourceSwitch() async {
    final nextSourceIndex = _sourceIndex + 1;
    if (nextSourceIndex >= (_currentChannel?.urls?.length ?? 0)) {
      if (mounted) {
        await _updatePlayerState(PlayerState.error);
        setState(() {
          toastString = S.current.playError;
        });
      }
      // 实现降级策略，尝试切换到其他可用频道
      await _tryFallbackChannel();
    } else {
      _sourceIndex = nextSourceIndex;
      if (mounted) {
        setState(() {
          toastString = S.current.switchLine(_sourceIndex + 1);
        });
      }
      
      await Future.delayed(_retryStrategy.initialDelay);
      if (_playerState != PlayerState.disposed) {
        await _disposePlayer();
        await _playVideo();
      }
    }
  }

  /// 尝试切换到备用频道
  Future<void> _tryFallbackChannel() async {
    if (_videoMap?.playList == null) return;
    
    // 尝试获取下一个可用频道
    PlayModel? nextChannel;
    bool foundCurrent = false;
    
    for (var category in _videoMap!.playList!.values) {
      if (category is Map<String, Map<String, PlayModel>>) {
        for (var group in category.values) {
          for (var channel in group.values) {
            if (foundCurrent) {
              if (channel.urls?.isNotEmpty ?? false) {
                nextChannel = channel;
                break;
              }
            } else if (channel.id == _currentChannel?.id) {
              foundCurrent = true;
            }
          }
          if (nextChannel != null) break;
        }
      }
      if (nextChannel != null) break;
    }
    
    if (nextChannel != null) {
      await _onTapChannel(nextChannel);
    }
  }

  /// 监听视频播放状态的变化
  void _videoListener() {
    if (_playerController == null || 
        _playerState == PlayerState.disposed || 
        !_isInitialized) return;
    
    try {
      final playerValue = _playerController!.value;
      
      // 检查错误状态
      if (playerValue.hasError) {
        LogUtil.logError('播放器报错', playerValue.errorDescription);
        _handleError('播放监听', 
          PlayerError('player_error', playerValue.errorDescription ?? '播放器错误'), 
          null);
        return;
      }
      
      // 更新UI状态
      if (mounted) {
        setState(() {
          isBuffering = playerValue.isBuffering;
          isPlaying = playerValue.isPlaying;
          
          if (isPlaying) {
            _updatePlayerState(PlayerState.playing);
          } else if (isBuffering) {
            _updatePlayerState(PlayerState.buffering);
          }
          
          // 仅在首次播放成功时更新宽高比
          if (isPlaying && _shouldUpdateAspectRatio) {
            aspectRatio = playerValue.aspectRatio;
            if (aspectRatio > 0) {  // 确保获取到有效的宽高比
              _shouldUpdateAspectRatio = false;
            }
          }
        });
      }
    } catch (e, stackTrace) {
      LogUtil.logError('视频监听器异常', e, stackTrace);
      _handleError('视频监听', e, stackTrace);
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
    if (model == null) return;
    
    return _resourceTracker.trackOperation('channel_switch', () async {
      // 防止重复切换
      if (_isSwitchingChannel) return;
      _isSwitchingChannel = true;
      
      // 保存当前状态用于恢复
      final previousState = _PlayerStateBackup(
        channel: _currentChannel,
        sourceIndex: _sourceIndex,
        state: _playerState,
      );
      
      try {
        // 1. 更新状态和保存之前的状态
        await _updatePlayerState(PlayerState.loading);
        await _disposePlayer();
        
        // 2. 设置新频道信息
        _currentChannel = model;
        _sourceIndex = 0;
        _retryCount = 0;
        _shouldUpdateAspectRatio = true;
        
        // 3. 发送统计数据
        if (Config.Analytics) {
          await _sendTrafficAnalytics(context, model.title);
        }
        
        // 4. 开始播放新频道
        await _playVideo();
        
      } catch (e, stack) {
        LogUtil.logError('切换频道失败', e, stack);
        
        // 5. 发生错误时恢复之前的状态
        await _restorePlayerState(previousState);
      } finally {
        _isSwitchingChannel = false;
      }
    });
  }

  /// 播放器状态备份类
  class _PlayerStateBackup {
    final PlayModel? channel;
    final int sourceIndex;
    final PlayerState state;
    
    _PlayerStateBackup({
      required this.channel,
      required this.sourceIndex,
      required this.state,
    });
  }

  /// 恢复播放器状态
  Future<void> _restorePlayerState(_PlayerStateBackup backup) async {
    _currentChannel = backup.channel;
    _sourceIndex = backup.sourceIndex;
    
    try {
      await _updatePlayerState(PlayerState.loading);
      await _playVideo();
    } catch (e) {
      LogUtil.logError('恢复播放状态失败', e);
      await _updatePlayerState(PlayerState.error);
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

  /// 异步加载视频数据
  Future<void> _loadData() async {
    return _resourceTracker.trackOperation('load_data', () async {
      try {
        _videoMap = widget.m3uData;
        _sourceIndex = 0;
        await _handlePlaylist();
      } catch (e, stackTrace) {
        LogUtil.logError('加载数据时出错', e, stackTrace);
        await _parseData();
      }
    });
  }

  /// 解析并加载本地播放列表
  Future<void> _parseData() async {
    return _resourceTracker.trackOperation('parse_data', () async {
      try {
        final resMap = await M3uUtil.getLocalM3uData();
        _videoMap = resMap.data;
        _sourceIndex = 0;
        await _handlePlaylist();
      } catch (e, stackTrace) {
        LogUtil.logError('解析播放列表时出错', e, stackTrace);
        if (mounted) {
          await _updatePlayerState(PlayerState.error);
          setState(() {
            toastString = S.current.parseError;
          });
        }
      }
    });
  }

  /// 处理播放列表
  Future<void> _handlePlaylist() async {
    return _resourceTracker.trackOperation('handle_playlist', () async {
      if (_videoMap?.playList?.isNotEmpty ?? false) {
        // 获取第一个可用的频道
        _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);

        if (_currentChannel != null) {
          // 发送流量统计数据
          if (Config.Analytics) {
            await _sendTrafficAnalytics(context, _currentChannel!.title);
          }
          
          if (mounted) {
            await _playVideo();
          }
        } else {
          // 没有可用的频道
          if (mounted) {
            await _updatePlayerState(PlayerState.error);
            setState(() {
              toastString = 'UNKNOWN';
            });
          }
        }
      } else {
        // 播放列表为空
        if (mounted) {
          await _updatePlayerState(PlayerState.error);
          setState(() {
            _currentChannel = null;
            toastString = 'UNKNOWN';
          });
        }
      }
    });
  }
  
/// 从播放列表中动态提取频道
  PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
    try {
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
          // 两层结构处理
          Map<String, PlayModel> channelMap = playList[category] ?? {};
          for (PlayModel? channel in channelMap.values) {
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
  Future<void> _extractFavoriteList() async {
    return _resourceTracker.trackOperation('extract_favorite', () async {
      try {
        if (widget.m3uData.playList?.containsKey(Config.myFavoriteKey) ?? false) {
          favoriteList = {
            Config.myFavoriteKey: widget.m3uData.playList![Config.myFavoriteKey]!
          };
        } else {
          favoriteList = {
            Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
          };
        }
      } catch (e, stackTrace) {
        LogUtil.logError('提取收藏列表时出错', e, stackTrace);
        favoriteList = {
          Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
        };
      }
    });
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

  /// 添加或取消收藏
  Future<void> toggleFavorite(String channelId) async {
    if (_currentChannel == null) return;

    return _resourceTracker.trackOperation('toggle_favorite', () async {
      bool isFavoriteChanged = false;
      String actualChannelId = _currentChannel?.id ?? channelId;
      String groupName = getGroupName(actualChannelId);
      String channelName = getChannelName(actualChannelId);

      // 验证分组名字、频道名字和播放地址是否正确
      if (groupName.isEmpty || channelName.isEmpty) {
        if (mounted) {
          CustomSnackBar.showSnackBar(
            context,
            S.current.channelnofavorite,
            duration: Duration(seconds: 4),
          );
        }
        return;
      }

      try {
        if (isChannelFavorite(actualChannelId)) {
          // 取消收藏
          favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
          if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
            favoriteList[Config.myFavoriteKey]!.remove(groupName);
          }
          
          if (mounted) {
            CustomSnackBar.showSnackBar(
              context,
              S.current.removefavorite,
              duration: Duration(seconds: 4),
            );
          }
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
          
          if (mounted) {
            CustomSnackBar.showSnackBar(
              context,
              S.current.newfavorite,
              duration: Duration(seconds: 4),
            );
          }
          isFavoriteChanged = true;
        }

        if (isFavoriteChanged) {
          // 保存收藏列表到缓存
          await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
          _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
          await M3uUtil.saveCachedM3uData(_videoMap.toString());
          
          if (mounted) {
            setState(() {}); // 重新渲染频道列表
          }
        }
      } catch (e, stackTrace) {
        LogUtil.logError('修改收藏状态时出错', e, stackTrace);
        if (mounted) {
          CustomSnackBar.showSnackBar(
            context,
            S.current.newfavoriteerror,
            duration: Duration(seconds: 4),
          );
        }
      }
    });
  }
  
@override
  void initState() {
    super.initState();

    // 如果是桌面设备，隐藏窗口标题栏
    if (!EnvUtil.isMobile) {
      try {
        windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      } catch (e) {
        LogUtil.logError('设置窗口标题栏样式失败', e);
      }
    }

    // 加载播放列表数据
    _loadData();

    // 加载收藏列表
    _extractFavoriteList();

    // 延迟1分钟后执行版本检测
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        CheckVersionUtil.checkVersion(context, false, false);
      }
    });
  }

  @override
  void didUpdateWidget(LiveHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果传入的m3uData发生变化，需要重新加载数据
    if (widget.m3uData != oldWidget.m3uData) {
      _loadData();
      _extractFavoriteList();
    }
  }

  @override
  void dispose() {
    // 禁用保持屏幕唤醒功能
    try {
      WakelockPlus.disable();
    } catch (e) {
      LogUtil.logError('禁用屏幕唤醒失败', e);
    }
    
    _cancelTimeoutCheck();
    _disposePlayer();
    super.dispose();
  }

  /// 处理返回按键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_drawerIsOpen) {
      // 如果抽屉打开则关闭抽屉
      if (mounted) {
        setState(() {
          _drawerIsOpen = false;
        });
      }
      return false;
    }

    // 弹出退出确认对话框
    return await ShowExitConfirm.ExitConfirm(context);
  }

  /// 弹出选择不同的视频源
  Future<void> _changeChannelSources() async {
    return _resourceTracker.trackOperation('change_sources', () async {
      List<String>? sources = _currentChannel?.urls;
      if (sources == null || sources.isEmpty) {
        LogUtil.e('未找到有效的视频源');
        return;
      }

      try {
        final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);

        // 切换到选中的视频播放
        if (selectedIndex != null && _sourceIndex != selectedIndex) {
          _sourceIndex = selectedIndex;
          await _playVideo();
        }
      } catch (e, stackTrace) {
        LogUtil.logError('切换视频源时出错', e, stackTrace);
      }
    });
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
      'isPlaying': isPlaying,
      'aspectRatio': aspectRatio,
      'onChangeSubSource': _parseData,
      'changeChannelSources': _changeChannelSources,
    };
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
        currentChannelId: _currentChannel?.id ?? '',
      );
    }

    return Material(
      child: OrientationLayoutBuilder(
        portrait: (context) {
          // 竖屏模式UI
          try {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          } catch (e) {
            LogUtil.logError('设置系统UI模式失败', e);
          }
          
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
                videoMap: _videoMap,
                playModel: _currentChannel,
                onTapChannel: _onTapChannel,
                isLandscape: false,
                onCloseDrawer: () {
                  if (mounted) {
                    setState(() {
                      _drawerIsOpen = false;
                    });
                  }
                },
              ),
              toggleFavorite: toggleFavorite,
              currentChannelId: _currentChannel?.id ?? '',
              isChannelFavorite: isChannelFavorite,
            ),
          );
        },
        landscape: (context) {
          // 横屏模式UI
          try {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          } catch (e) {
            LogUtil.logError('设置系统UI模式失败', e);
          }
          
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
                          currentChannelId: _currentChannel?.id ?? '',
                          toggleFavorite: toggleFavorite,
                          isLandscape: true,
                          onToggleDrawer: () {
                            if (mounted) {
                              setState(() {
                                _drawerIsOpen = !_drawerIsOpen;
                              });
                            }
                          }
                        ),
                ),
                Offstage(
                  offstage: !_drawerIsOpen,
                  child: GestureDetector(
                    onTap: () {
                      if (mounted) {
                        setState(() {
                          _drawerIsOpen = false;
                        });
                      }
                    },
                    child: ChannelDrawerPage(
                      videoMap: _videoMap,
                      playModel: _currentChannel,
                      onTapChannel: _onTapChannel,
                      isLandscape: true,
                      onCloseDrawer: () {  
                        if (mounted) {
                          setState(() {
                            _drawerIsOpen = false;
                          });
                        }
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
