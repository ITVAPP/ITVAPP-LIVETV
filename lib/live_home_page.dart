import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
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
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
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
  static const int defaultMaxRetries = 1; // 默认最大重试次数，控制播放失败后尝试重新播放的最大次数
  static const int defaultTimeoutSeconds = 36; // 解析超时秒数，若超过此时间仍未完成，则视为解析失败
  static const int initialProgressDelaySeconds = 60; // 播放开始后经过此时间才会启用事件（progress）
  static const int retryDelaySeconds = 2; // 播放失败或切换源时，等待此时间（秒）后重新播放或加载新源，给予系统清理和准备的时间
  static const int m3u8InvalidConfirmDelaySeconds = 1; // 新增：m3u8 失效确认等待时间
  static const int hlsSwitchThresholdSeconds = 3; // 当HLS流剩余播放时间少于此值（秒）且有预缓存地址时，切换到预缓存地址
  static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS流剩余时间少于此值（秒）时，开始预加载下一源，提前准备切换
  static const int nonHlsSwitchThresholdSeconds = 3; // 非HLS流剩余时间少于此值（秒）且有预缓存地址时，切换到预缓存地址
  static const double defaultAspectRatio = 1.78; // 视频播放器的初始宽高比（16:9），若未从播放器获取新值则使用此值
  static const int cleanupDelayMilliseconds = 500; // 清理控制器前的延迟毫秒数，确保旧控制器完全暂停和清理
  static const int snackBarDurationSeconds = 4; // 操作提示的显示时长（秒）
  static const int bufferingStartSeconds = 15; // 缓冲超过计时器的时间就放弃加载，启用重试
  static const int m3u8CheckIntervalSeconds = 10; // m3u8 文件有效性检查的间隔时间（秒）
  static const int reparseMinIntervalMilliseconds = 10000; // 重新解析的最小间隔（秒），避免频繁解析
  static const int m3u8ConnectTimeoutSeconds = 5; // m3u8 检查连接超时秒数
  static const int m3u8ReceiveTimeoutSeconds = 10; // m3u8 检查接收超时秒数

  // 缓冲区检查相关变量
  String? _preCachedUrl; // 预缓存的URL
  bool _isParsing = false; // 是否正在解析
  bool _isRetrying = false; // 是否正在重试
  Timer? _retryTimer; // 重试计时器
  Timer? _m3u8CheckTimer; // m3u8 检查定时器
  int? _lastCheckTime; // 上次 m3u8 检查时间（改为仅用于检查）
  int? _lastParseTime; // 上次解析时间（新增）
  String toastString = S.current.loading; // 提示信息
  PlaylistModel? _videoMap; // 视频映射
  PlayModel? _currentChannel; // 当前频道
  int _sourceIndex = 0; // 当前源索引
  int _lastProgressTime = 0; // 上次进度时间
  BetterPlayerController? _playerController; // 播放器控制器
  bool isBuffering = false; // 是否正在缓冲
  bool isPlaying = false; // 是否正在播放
  double aspectRatio = defaultAspectRatio; // 宽高比
  bool _drawerIsOpen = false; // 抽屉是否打开
  int _retryCount = 0; // 重试次数
  bool _timeoutActive = false; // 超时是否激活
  bool _isDisposing = false; // 是否正在释放资源
  bool _isSwitchingChannel = false; // 是否正在切换频道
  bool _shouldUpdateAspectRatio = true; // 是否应该更新宽高比
  StreamUrl? _streamUrl; // 流地址
  StreamUrl? _preCacheStreamUrl; // 预缓存的 StreamUrl 实例
  String? _currentPlayUrl; // 当前播放的URL（解析后的地址）
  String? _originalUrl; // 解析前的原始地址
  bool _progressEnabled = false; // 进度是否启用
  bool _isHls = false; // 是否是HLS流
  Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
    Config.myFavoriteKey: <String, Map<String, PlayModel>>{},
  }; // 收藏列表
  ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
  final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析
  bool _isAudio = false; // 是否是音频流
  Timer? _playDurationTimer; // 播放持续时间计时器
  Timer? _timeoutTimer; // 缓冲超时的计时器
  late AdManager _adManager; // 广告管理实例
  bool _isUserPaused = false; // 是否为用户触发的暂停
  bool _showPlayIcon = false; // 控制播放图标显示
  bool _showPauseIconFromListener = false; // 控制非用户触发的暂停图标显示
  int _m3u8InvalidCount = 0; // 新增：记录 m3u8 失效次数

  // 切换请求队列
  Map<String, dynamic>? _pendingSwitch; // 存储 {channel: PlayModel, sourceIndex: int} 或 null

  bool _checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    const videoFormats = ['.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb'];
    const audioFormats = ['.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'];
    final lowercaseUrl = url.toLowerCase();
    return !videoFormats.any(lowercaseUrl.contains) && audioFormats.any(lowercaseUrl.contains);
  }

  bool _isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    // 优先检查 HLS 特征
    if (lowercaseUrl.contains('.m3u8')) return true;
    // 排除常见非 HLS 格式
    const formats = [
      '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
      '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac'
    ];
    return !formats.any(lowercaseUrl.contains);
  }

  // 统一更新 _currentPlayUrl 和 _isHls 的方法
  void _updatePlayUrl(String newUrl) {
    _currentPlayUrl = newUrl;
    _isHls = _isHlsStream(_currentPlayUrl);
  }

  // 切换到预缓存地址
  Future<void> _switchToPreCachedUrl(String logDescription) async {
    _cleanupTimers(); // 确保清理所有计时器，包括 _m3u8CheckTimer

    if (_preCachedUrl == null) {
      LogUtil.i('$logDescription: 预缓存地址为空，无法切换');
      return;
    }

    if (_preCachedUrl == _currentPlayUrl) {
      LogUtil.i('$logDescription: 预缓存地址与当前地址相同，跳过切换，尝试重新解析');
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl(); // 先释放预缓存资源
      await _reparseAndSwitch(); // 然后重新解析
      return;
    }

    LogUtil.i('$logDescription: 切换到预缓存地址: $_preCachedUrl');
    _updatePlayUrl(_preCachedUrl!); // 统一更新播放URL和HLS状态

    final newSource = BetterPlayerConfig.createDataSource(url: _currentPlayUrl!, isHls: _isHls);

    try {
      await _playerController?.preCache(newSource);
      LogUtil.i('$logDescription: 预缓存新数据源完成: $_currentPlayUrl');
      await _playerController?.setupDataSource(newSource);
      
      if (isPlaying) {
        await _playerController?.play();
        LogUtil.i('$logDescription: 切换到预缓存地址并开始播放: $_currentPlayUrl');
        _startPlayDurationTimer(); // 重启60秒计时器
      } else {
        LogUtil.i('$logDescription: 切换到预缓存地址但保持暂停状态: $_currentPlayUrl');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('$logDescription: 切换到预缓存地址失败', e, stackTrace);
      _retryPlayback(); // 切换失败时触发重试
      return;
    } finally {
      // 确保在任何情况下都重置状态并释放资源
      _progressEnabled = false;
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl(); // 释放预缓存资源
    }
  }

  /// 播放视频，包含初始化和切换逻辑
  Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
    // 添加空检查以防止 _currentChannel 为 null 时崩溃
    if (_currentChannel == null) return; // 避免空指针异常

    String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
    LogUtil.i('准备播放频道: ${_currentChannel!.title}，源: $sourceName, isRetry: $isRetry, isSourceSwitch: $isSourceSwitch');

    _cleanupTimers(); // 清理计时器
    _adManager.reset(); // 重置广告状态
    setState(() {
      toastString = '${_currentChannel!.title} - $sourceName  ${S.current.loading}';
      isPlaying = false;
      isBuffering = false;
      _progressEnabled = false;
      _isSwitchingChannel = true; // 在清理前设置，保护整个过程
      _isUserPaused = false; // 重置用户暂停状态
      _showPlayIcon = false; // 重置播放图标状态
      _showPauseIconFromListener = false; // 重置暂停图标状态
    });

    // 启动整个播放流程的超时计时
    _timeoutTimer?.cancel();
    _timeoutActive = true;
    _timeoutTimer = Timer(Duration(seconds: defaultTimeoutSeconds), () {
      if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
        _timeoutActive = false;
        return;
      }
      if (_playerController?.isPlaying() != true) { // 如果 36 秒后未播放成功
        LogUtil.e('播放流程超时（解析或缓冲失败），切换下一源');
        _handleSourceSwitching();
        _timeoutActive = false;
      }
    });

    try {
      // 仅在初次播放频道时检查并触发广告
      if (!isRetry && !isSourceSwitch && _adManager.shouldPlayVideoAd()) {
        await _adManager.playVideoAd(); // 等待广告播放完成
        LogUtil.i('视频广告播放完成，准备播放频道');
        _adManager.reset(); // 检查并可能显示文字广告
      }

      // 如果已有控制器，先暂停并重用，避免重复创建
      if (_playerController != null) {
        await _playerController!.pause();
        await _cleanupController(_playerController);
      }

      await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
      if (!mounted) {
        LogUtil.i('组件已卸载，停止播放流程');
        return;
      }

      String url = _currentChannel!.urls![_sourceIndex].toString();
      _originalUrl = url; // 设置解析前地址
      _streamUrl = StreamUrl(url); // 保存 StreamUrl 实例
      String parsedUrl = await _streamUrl!.getStreamUrl(); // 使用保存的实例
      _updatePlayUrl(parsedUrl); // 使用统一方法更新 _currentPlayUrl 和 _isHls

      if (parsedUrl == 'ERROR') {
        LogUtil.e('地址解析失败: $url');
        setState(() {
          toastString = S.current.vpnplayError;
          _isSwitchingChannel = false;
        });
        await _disposeStreamUrl(); // 解析失败时释放
        return;
      }

      bool isDirectAudio = _checkIsAudioStream(parsedUrl);
      setState(() => _isAudio = isDirectAudio);

      LogUtil.i('播放信息 - URL: $parsedUrl, 音频: $isDirectAudio, HLS: $_isHls');

      final dataSource = BetterPlayerConfig.createDataSource(
        url: parsedUrl,
        isHls: _isHls,
      );
      final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
        eventListener: _videoListener,
        isHls: _isHls,
      );

      BetterPlayerController? tempController;
      try {
        tempController = BetterPlayerController(betterPlayerConfiguration);
        await tempController.setupDataSource(dataSource);
        LogUtil.i('播放器数据源设置完成: $parsedUrl');
        setState(() {
          _playerController = tempController;
        });
        await _playerController?.play();
        LogUtil.i('开始播放: $parsedUrl');
        _timeoutActive = false; // 播放成功后取消超时
        _timeoutTimer?.cancel(); // 停止计时器
      } catch (e) {
        tempController?.dispose();
        throw e;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      await _disposeStreamUrl(); // 播放失败时释放
      _handleSourceSwitching();
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingChannel = false;
          // 重置其他状态，确保一致性
          if (_playerController == null) {
            isBuffering = false;
            isPlaying = false;
          }
        });
        // 处理最新的切换请求
        if (_pendingSwitch != null) {
          final nextRequest = _pendingSwitch!;
          _currentChannel = nextRequest['channel'] as PlayModel?;
          _sourceIndex = nextRequest['sourceIndex'] as int;
          _pendingSwitch = null; // 处理完成后清空
          LogUtil.i('处理最新切换请求: ${_currentChannel!.title}, 源索引: $_sourceIndex');
          Future.microtask(() => _playVideo()); // 异步调度，避免递归
        }
      }
    }
  }

  // 切换请求队列
  Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
    if (channel == null) return;
    
    // 先释放当前解析实例，避免资源泄露
    await _disposeStreamUrl();
    await _disposePreCacheStreamUrl(); // 同时释放预缓存实例
    
    if (_isSwitchingChannel) {
      // 若正在切换，覆盖旧请求，只保留最新请求
      _pendingSwitch = {'channel': channel, 'sourceIndex': sourceIndex};
      LogUtil.i('更新最新切换请求: ${channel.title}, 源索引: $sourceIndex');
    } else {
      _currentChannel = channel;
      _sourceIndex = sourceIndex;
      _originalUrl = _currentChannel!.urls![_sourceIndex];
      LogUtil.i('切换频道/源 - 解析前地址: $_originalUrl');
      await _playVideo();
    }
  }

  // 视频事件监听器
  void _videoListener(BetterPlayerEvent event) async {
    if (!mounted || _playerController == null || _isDisposing || event.betterPlayerEventType == BetterPlayerEventType.changedPlayerVisibility || event.betterPlayerEventType == BetterPlayerEventType.bufferingUpdate || event.betterPlayerEventType == BetterPlayerEventType.changedTrack || event.betterPlayerEventType == BetterPlayerEventType.setupDataSource || event.betterPlayerEventType == BetterPlayerEventType.changedSubtitles) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (_shouldUpdateAspectRatio) {
          final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? defaultAspectRatio;
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
        final error = event.parameters?["error"] as String? ?? "Unknown error";
        LogUtil.e('播放器异常: $error');
        
        if (_isParsing) {
          LogUtil.i('正在重新解析中，忽略本次异常，等待解析完成切换');
          return;
        }
        
        // 检查是否是HLS特定错误并强制重新解析
        if (_isHls && (error.contains("403") || error.contains("404") || 
            error.contains("HLSJS") || error.contains("Invalid") || 
            error.contains("expired") || error.contains("failed") ||
            error.contains("timeout") || error.contains("cannot load"))) {
          LogUtil.i('检测到 HLS 特定错误，强制重新解析: $error');
          await _reparseAndSwitch(force: true);
          return;
        }
        
        if (_isHls) {
          if (_preCachedUrl != null) {
            LogUtil.i('异常触发，预缓存地址已准备，立即切换');
            await _switchToPreCachedUrl('异常触发');
          } else {
            LogUtil.i('异常触发，预缓存地址未准备，等待解析');
            await _reparseAndSwitch();
          }
        } else {
          _retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        setState(() {
          isBuffering = true;
          toastString = S.current.loading;
        });
        if (isPlaying) {
          _timeoutTimer?.cancel();
          _timeoutTimer = Timer(const Duration(seconds: bufferingStartSeconds), () {
            if (!mounted || !isBuffering || _isRetrying || _isSwitchingChannel || _isDisposing || _isParsing || _pendingSwitch != null) {
              LogUtil.i('缓冲超时检查被阻止: mounted=$mounted, isBuffering=$isBuffering, '
                  'isRetrying=$_isRetrying, isSwitchingChannel=$_isSwitchingChannel, '
                  'isDisposing=$_isDisposing, isParsing=$_isParsing, pendingSwitch=$_pendingSwitch');
              return;
            }
            if (_playerController?.isPlaying() != true) {
              LogUtil.e('播放中缓冲超过15秒，触发重试');
              _retryPlayback(resetRetryCount: true);
            }
          });
        } else {
          LogUtil.i('初始缓冲，不启用15秒超时');
        }
        break;

      case BetterPlayerEventType.bufferingEnd:
        setState(() {
          isBuffering = false;
          toastString = 'HIDE_CONTAINER';
          if (!_isUserPaused) _showPauseIconFromListener = false;
        });
        _timeoutTimer?.cancel();
        _timeoutTimer = null; // 只清理超时计时器
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying) {
          setState(() {
            isPlaying = true;
            if (!isBuffering) toastString = 'HIDE_CONTAINER';
            _progressEnabled = false;
            _showPlayIcon = false; // 播放时隐藏播放图标
            _showPauseIconFromListener = false; // 隐藏暂停图标
            _isUserPaused = false; // 播放时重置用户暂停状态
          });
          _timeoutTimer?.cancel(); // 播放开始，取消缓冲超时定时器
          _timeoutTimer = null;
          if (_playDurationTimer == null || !_playDurationTimer!.isActive) {
            _startPlayDurationTimer();
          }
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying) {
          setState(() {
            isPlaying = false;
            toastString = S.current.playpause;
            if (_isUserPaused) {
              _showPlayIcon = true; // 用户触发的暂停，显示播放图标
              _showPauseIconFromListener = false;
            } else {
              _showPlayIcon = false; // 非用户触发的暂停，显示暂停图标
              _showPauseIconFromListener = true;
            }
          });
          LogUtil.i('播放暂停，用户触发: $_isUserPaused');
        }
        break;

      case BetterPlayerEventType.progress:
        if (_progressEnabled && isPlaying) {
          final position = event.parameters?["progress"] as Duration?;
          final duration = event.parameters?["duration"] as Duration?;
          if (position != null && duration != null) {
            final remainingTime = duration - position;
            if (_isHls && _preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
              LogUtil.i('HLS 剩余时间少于 $hlsSwitchThresholdSeconds 秒，切换到预缓存地址');
              await _switchToPreCachedUrl('HLS 剩余时间触发切换');
            } else if (!_isHls) { // 非 HLS 流保留原有逻辑
              if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
                final nextUrl = _getNextVideoUrl();
                if (nextUrl != null && nextUrl != _preCachedUrl) {
                  LogUtil.i('非 HLS 剩余时间少于 $nonHlsPreloadThresholdSeconds 秒，预缓存下一源: $nextUrl');
                  _preloadNextVideo(nextUrl);
                }
              }
              if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
                await _switchToPreCachedUrl('非 HLS 剩余时间少于 $nonHlsSwitchThresholdSeconds 秒');
              }
            }
          } else {
            LogUtil.i('Progress 数据不完整: position=$position, duration=$duration');
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!_isHls && _preCachedUrl != null) {
          await _switchToPreCachedUrl('非 HLS 播放结束');
        } else if (_isHls) {
          LogUtil.i('HLS 流异常结束，重试播放');
          _retryPlayback();
        } else {
          LogUtil.i('无更多源可播放');
          _handleNoMoreSources();
        }
        break;

      default:
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        break;
    }
  }

  // 实现 m3u8 文件内容检查
  Future<bool> _checkM3u8Validity() async {
    if (_currentPlayUrl == null || !_isHls) {
      LogUtil.i('当前播放地址为空或非 HLS 流，无需检查: _currentPlayUrl=$_currentPlayUrl, _isHls=$_isHls');
      return true;
    }
    
    try {
      // 使用 HttpUtil 获取 m3u8 内容，利用其内置的头部管理和重试逻辑
      final String? content = await HttpUtil().getRequest<String>(
        _currentPlayUrl!,
        options: Options(
          extra: {
            'connectTimeout': const Duration(seconds: m3u8ConnectTimeoutSeconds),
            'receiveTimeout': const Duration(seconds: m3u8ReceiveTimeoutSeconds),
          }
        ),
        retryCount: 1, // 对于检查来说，单次重试足够
      );
      
      // 严格检查内容有效性
      if (content == null || content.isEmpty) {
        LogUtil.e('m3u8 内容为空或获取失败：$_currentPlayUrl');
        return false;
      }
      
      // 检查内容是否包含 .ts 片段或其他有效标记
      bool hasSegments = content.contains('.ts');
      bool hasValidDirectives = content.contains('#EXTINF') || content.contains('#EXT-X-STREAM-INF');
      
      bool isValid = hasSegments || hasValidDirectives;
      
      if (!isValid) {
        LogUtil.e('m3u8 内容无效，不包含有效标记或片段');
        return false;
      }
      
      LogUtil.i('m3u8 检查通过，内容有效');
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('m3u8 有效性检查出错', e, stackTrace);
      return false;
    }
  }

// 定期检查 m3u8 文件定时器（引入两次检查机制，不修改）
  void _startM3u8CheckTimer() {
    _m3u8CheckTimer?.cancel();
    
    if (!_isHls) return;
    
    _m3u8CheckTimer = Timer.periodic(const Duration(seconds: m3u8CheckIntervalSeconds), (_) async {
      if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) return;
      
      _lastCheckTime = DateTime.now().millisecondsSinceEpoch;
      
      // 检查 m3u8 有效性
      final isValid = await _checkM3u8Validity();
      if (!isValid) {
        _m3u8InvalidCount++;
        LogUtil.i('m3u8 检查失效，次数: $_m3u8InvalidCount');
        
        if (_m3u8InvalidCount == 1) {
          LogUtil.i('第一次检测到 m3u8 失效，等待 $m3u8InvalidConfirmDelaySeconds 秒后再次检查');
          Timer(Duration(seconds: m3u8InvalidConfirmDelaySeconds), () async {
            if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) {
              _m3u8InvalidCount = 0; // 中断时重置
              return;
            }
            final secondCheck = await _checkM3u8Validity();
            if (!secondCheck) {
              LogUtil.i('第二次检查确认 m3u8 失效，触发重新解析');
              await _reparseAndSwitch();
            } else {
              LogUtil.i('第二次检查 m3u8 有效，取消重新解析');
              _m3u8InvalidCount = 0; // 重置计数
            }
          });
        } else if (_m3u8InvalidCount >= 2) {
          // 连续两次失效，直接触发重新解析
          LogUtil.i('连续两次检查到 m3u8 失效，触发重新解析');
          await _reparseAndSwitch();
          _m3u8InvalidCount = 0; // 重置计数
        }
      } else {
        _m3u8InvalidCount = 0; // 检查通过，重置计数
      }
    });
  }

  void _startPlayDurationTimer() {
    _playDurationTimer?.cancel();
    _playDurationTimer = Timer(const Duration(seconds: initialProgressDelaySeconds), () {
      if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
        LogUtil.i('播放 $initialProgressDelaySeconds 秒，开始检查逻辑');
        
        if (_isHls) {
          // 仅当播放指定时间后且包含 timelimit 时检查 HLS 流有效性
          if (_originalUrl != null && _originalUrl!.toLowerCase().contains('timelimit')) {
            _startM3u8CheckTimer();
            LogUtil.i('HLS 流包含 timelimit，启用 m3u8 检查定时器');
          }
        } else {
          // 非 HLS 流保留原有逻辑
          if (_getNextVideoUrl() != null) {
            _progressEnabled = true;
            LogUtil.i('非 HLS 流，启用 progress 监听');
          }
        }
        
        _retryCount = 0;
        _playDurationTimer = null;
      }
    });
  }

  Future<void> _preloadNextVideo(String url) async {
    if (_isDisposing || _isSwitchingChannel || _playerController == null) {
      LogUtil.i('预加载被阻止: _isDisposing=$_isDisposing, _isSwitchingChannel=$_isSwitchingChannel, controller=${_playerController != null}');
      return;
    }

    try {
      LogUtil.i('开始预加载: $url');
      // 先释放旧的预缓存实例
      await _disposePreCacheStreamUrl();
      
      // 创建新实例进行解析
      _preCacheStreamUrl = StreamUrl(url);
      String parsedUrl = await _preCacheStreamUrl!.getStreamUrl();
      
      if (parsedUrl == 'ERROR') {
        LogUtil.e('预加载解析失败: $url');
        await _disposePreCacheStreamUrl(); // 解析失败时释放资源
        return;
      }
      
      _preCachedUrl = parsedUrl;
      LogUtil.i('预缓存地址: $_preCachedUrl, 当前 _isHls: $_isHls (保持不变)');

      final nextSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(parsedUrl), // 仅用于预缓存，不影响当前 _isHls
        url: parsedUrl,
      );

      await _playerController!.preCache(nextSource);
      LogUtil.i('预缓存完成: $parsedUrl');
    } catch (e, stackTrace) {
      LogUtil.logError('预加载失败: $url', e, stackTrace);
      _preCachedUrl = null;
      await _disposePreCacheStreamUrl(); // 确保异常时也释放资源
    }
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

  void _retryPlayback({bool resetRetryCount = false}) {
    if (_isRetrying || _isSwitchingChannel || _isDisposing) return;

    if (_isParsing) {
      LogUtil.i('正在重新解析中，跳过重试，等待解析完成切换');
      return;
    }

    _cleanupTimers();

    if (resetRetryCount) {
      setState(() {
        _retryCount = 0; // 用户触发时重置重试次数
      });
    }

    if (_retryCount < defaultMaxRetries) {
      setState(() {
        _isRetrying = true;
        _retryCount++;
        isBuffering = false;
        toastString = S.current.retryplay;
        _showPlayIcon = false; // 重试时隐藏播放图标
        _showPauseIconFromListener = false; // 重试时隐藏暂停图标
      });
      LogUtil.i('重试播放: 第 $_retryCount 次');

      _retryTimer = Timer(const Duration(seconds: retryDelaySeconds), () async {
        if (!mounted || _isSwitchingChannel || _isDisposing || _isParsing) {
          LogUtil.i('重试中断: mounted=$mounted, isSwitchingChannel=$_isSwitchingChannel, isDisposing=$_isDisposing, isParsing=$_isParsing');
          setState(() => _isRetrying = false);
          return;
        }
        await _playVideo(isRetry: true); // 标记为重试
        if (mounted) {
          setState(() {
            _isRetrying = false;
          });
        }
      });
    } else {
      LogUtil.i('重试次数达上限，切换下一源');
      _handleSourceSwitching();
    }
  }

  String? _getNextVideoUrl() {
    if (_currentChannel == null || _currentChannel!.urls == null) return null;
    final List<String> urls = _currentChannel!.urls!;
    if (urls.isEmpty) return null;
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
      _preCachedUrl = null;
    });

    LogUtil.i('切换到下一源: $nextUrl');
    _startNewSourceTimer();
  }

  Future<void> _handleNoMoreSources() async {
    setState(() {
      toastString = S.current.playError;
      _sourceIndex = 0;
      isBuffering = false;
      isPlaying = false;
      _isRetrying = false;
      _retryCount = 0;
      _showPlayIcon = false; // 无源时隐藏播放图标
      _showPauseIconFromListener = false; // 无源时隐藏暂停图标
    });
    await _cleanupController(_playerController);
    LogUtil.i('播放结束，无更多源');
  }

  void _startNewSourceTimer() {
    _cleanupTimers();
    _retryTimer = Timer(const Duration(seconds: retryDelaySeconds), () async {
      if (!mounted || _isSwitchingChannel) return;
      await _playVideo(isSourceSwitch: true); // 标记为切换源
    });
  }

/// 清理播放器控制器，确保资源释放
Future<void> _cleanupController(BetterPlayerController? controller) async {
  if (controller == null) return;

  _isDisposing = true;
  try {
    LogUtil.i('开始清理播放器控制器');
    _cleanupTimers(); // 清理所有计时器
    controller.removeEventsListener(_videoListener);

    // 尝试暂停和降低音量，减少用户感知的中断
    if (controller.isPlaying() ?? false) {
      await controller.pause();
      await controller.setVolume(0);
      LogUtil.i('播放器已暂停并静音');
    }

    // 释放所有关联的解析实例
    await _disposeStreamUrl();
    await _disposePreCacheStreamUrl();
    
    // 释放播放器控制器
    if (controller.videoPlayerController != null) {
      await controller.videoPlayerController?.dispose();
    }
    controller.dispose(); // 移除 await，因为 dispose() 返回 void
    LogUtil.i('播放器控制器已释放');

    // 重置状态
    setState(() {
      _playerController = null;
      _progressEnabled = false;
      _isAudio = false;
      _isParsing = false;
      _isUserPaused = false;
      _showPlayIcon = false;
      _showPauseIconFromListener = false;
      _lastCheckTime = null;
      _lastParseTime = null;
      _preCachedUrl = null; // 确保清理预缓存地址
    });
    LogUtil.i('播放器状态已重置');
  } catch (e, stackTrace) {
    LogUtil.logError('清理播放器失败', e, stackTrace);
  } finally {
    _isDisposing = false; // 确保释放标志被重置
  }
}

  Future<void> _disposeStreamUrl() async {
    if (_streamUrl != null) {
      await _streamUrl!.dispose();
      _streamUrl = null; // 确保设置为null
      LogUtil.i('主StreamUrl实例已释放');
    }
  }

  Future<void> _disposePreCacheStreamUrl() async {
    if (_preCacheStreamUrl != null) {
      await _preCacheStreamUrl!.dispose();
      _preCacheStreamUrl = null; // 确保设置为null
      LogUtil.i('预缓存StreamUrl实例已释放');
    }
  }

  void _cleanupTimers() {
    if (_retryTimer?.isActive == true) {
      _retryTimer?.cancel();
      _retryTimer = null;
      LogUtil.i('重试计时器已清理');
    }
    
    if (_playDurationTimer?.isActive == true) {
      _playDurationTimer?.cancel();
      _playDurationTimer = null;
      LogUtil.i('播放持续时间计时器已清理');
    }
    
    if (_timeoutTimer?.isActive == true) {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _timeoutActive = false;
      LogUtil.i('超时计时器已清理');
    }
    
    if (_m3u8CheckTimer?.isActive == true) {
      _m3u8CheckTimer?.cancel();
      _m3u8CheckTimer = null;
      _m3u8InvalidCount = 0; // 重置失效计数
      LogUtil.i('m3u8检查计时器已清理');
    }
  }

  // 重新解析并准备预缓存地址
  Future<void> _reparseAndSwitch({bool force = false}) async {
    if (_isRetrying || _isSwitchingChannel || _isDisposing || _isParsing) {
      LogUtil.i('重新解析被阻止: _isRetrying=$_isRetrying, _isSwitchingChannel=$_isSwitchingChannel, _isDisposing=$_isDisposing, _isParsing=$_isParsing');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastParseTime != null && (now - _lastParseTime!) < reparseMinIntervalMilliseconds) {
      LogUtil.i('解析频率过高，跳过此次解析，间隔: ${now - _lastParseTime!}ms');
      return;
    }

    _cleanupTimers(); // 清理所有计时器，确保 _m3u8CheckTimer 被停止
    _isParsing = true;
    setState(() => _isRetrying = true);

    try {
      // 确保当前频道信息可用
      if (_currentChannel == null || _currentChannel!.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
        LogUtil.e('重新解析时频道信息无效');
        throw Exception('无效的频道信息');
      }

      String url = _currentChannel!.urls![_sourceIndex].toString();
      LogUtil.i('重新解析地址: $url');
      
      // 释放旧的实例
      await _disposeStreamUrl();
      
      // 创建新实例进行解析
      _streamUrl = StreamUrl(url);
      String newParsedUrl = await _streamUrl!.getStreamUrl();
      
      if (newParsedUrl == 'ERROR') {
        LogUtil.e('重新解析失败: $url');
        await _disposeStreamUrl(); // 解析失败时释放资源
        throw Exception('解析失败');
      }
      
      if (newParsedUrl == _currentPlayUrl) {
        LogUtil.i('新地址与当前播放地址相同，无需切换');
        await _disposeStreamUrl(); // 释放不需要的资源
        return;
      }

      // 设置预缓存地址
      _preCachedUrl = newParsedUrl;
      LogUtil.i('预缓存地址已准备: $_preCachedUrl');

      final newSource = BetterPlayerConfig.createDataSource(
        isHls: _isHlsStream(newParsedUrl),
        url: newParsedUrl,
      );

      if (_playerController != null) {
        // 安全检查：确保在预加载前播放器仍可用
        if (_isDisposing || _isSwitchingChannel) {
          LogUtil.i('预加载前检测到中断，退出重新解析');
          _preCachedUrl = null;
          await _disposeStreamUrl();
          return;
        }

        // 执行预缓存
        await _playerController!.preCache(newSource);
        
        // 再次安全检查：确保在预加载完成后播放器仍可用
        if (_isDisposing || _isSwitchingChannel) {
          LogUtil.i('预加载完成后检测到中断，退出重新解析');
          _preCachedUrl = null;
          await _disposeStreamUrl();
          return;
        }

        // 预缓存成功，启用进度检测以便触发切换
        _progressEnabled = true;
        _lastParseTime = now; // 记录最后成功解析时间

        LogUtil.i('预缓存完成，等待剩余时间或异常触发切换');
      } else {
        LogUtil.i('播放器控制器为空，无法切换');
        _handleSourceSwitching(); // 如果播放器控制器不可用，尝试切换源
      }
    } catch (e, stackTrace) {
      LogUtil.logError('重新解析失败', e, stackTrace);
      await _disposeStreamUrl(); // 确保异常时也释放资源
      _handleSourceSwitching(); // 解析失败时尝试切换源
    } finally {
      _isParsing = false; // 确保解析状态被重置
      if (mounted) setState(() => _isRetrying = false); // 更新UI状态
      LogUtil.i('重新解析结束');
    }
  }

  // 获取地理信息
  Map<String, String?> _getLocationInfo(String? userInfo) {
    if (userInfo == null || userInfo.isEmpty) {
      LogUtil.i('用户地理信息为空，使用默认顺序');
      return {'region': null, 'city': null};
    }
    try {
      final Map<String, dynamic> userData = jsonDecode(userInfo);
      final Map<String, dynamic>? locationData = userData['info']?['location'];
      final String? region = locationData?['region'] as String?;
      final String? city = locationData?['city'] as String?;

      final String? regionPrefix = region != null && region.isNotEmpty
          ? (region.length >= 2 ? region.substring(0, 2) : region)
          : null;
      final String? cityPrefix = city != null && city.isNotEmpty
          ? (city.length >= 2 ? city.substring(0, 2) : city)
          : null;

      LogUtil.i('获取地理信息 - 地区: $region (前缀: $regionPrefix), 城市: $city (前缀: $cityPrefix)');
      return {'region': regionPrefix, 'city': cityPrefix};
    } catch (e) {
      LogUtil.e('解析地理信息失败: $e');
      return {'region': null, 'city': null};
    }
  }

  // 基于地理前缀排序
  List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
    if (prefix == null || prefix.isEmpty) {
      LogUtil.i('地理前缀为空，返回原始顺序: $items');
      return items;
    }
    if (items.isEmpty) {
      LogUtil.i('待排序列表为空，返回空列表');
      return items;
    }

    items.sort((a, b) {
      final aMatches = a.startsWith(prefix);
      final bMatches = b.startsWith(prefix);
      if (aMatches && !bMatches) return -1;
      if (!aMatches && bMatches) return 1;
      return a.compareTo(b);
    });

    LogUtil.i('排序结果: $items');
    return items;
  }

  // 对 videoMap 进行排序
  void _sortVideoMap(PlaylistModel videoMap, String? userInfo) {
    if (videoMap.playList == null || videoMap.playList!.isEmpty) {
      LogUtil.e('播放列表为空，无需排序');
      return;
    }

    final location = _getLocationInfo(userInfo);
    final String? regionPrefix = location['region'];
    final String? cityPrefix = location['city'];

    if (regionPrefix == null || regionPrefix.isEmpty) {
      LogUtil.i('地区前缀为空，跳过排序');
      return;
    }

    videoMap.playList!.forEach((category, groups) {
      if (groups is! Map<String, Map<String, PlayModel>>) {
        LogUtil.e('分类 $category 的 groups 类型无效: ${groups.runtimeType}');
        return;
      }

      final groupList = groups.keys.toList();
      bool categoryNeedsSort = groupList.any((group) => group.contains(regionPrefix));
      if (!categoryNeedsSort) {
        return;
      }

      final sortedGroups = _sortByGeoPrefix(groupList, regionPrefix);
      final newGroups = <String, Map<String, PlayModel>>{};

      for (var group in sortedGroups) {
        final channels = groups[group];
        if (channels is! Map<String, PlayModel>) {
          LogUtil.e('组 $group 的 channels 类型无效: ${channels.runtimeType}');
          continue;
        }

        final channelList = channels.keys.toList();
        final newChannels = <String, PlayModel>{};

        if (group.contains(regionPrefix) && (cityPrefix != null && cityPrefix.isNotEmpty)) {
          final sortedChannels = _sortByGeoPrefix(channelList, cityPrefix);
          for (var channel in sortedChannels) {
            newChannels[channel] = channels[channel]!;
          }
        } else {
          for (var channel in channelList) {
            newChannels[channel] = channels[channel]!;
          }
        }
        newGroups[group] = newChannels;
      }
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成: ${newGroups.keys.toList()}');
    });
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

      await _queueSwitchChannel(_currentChannel, _sourceIndex);

      if (Config.Analytics) {
        await _sendTrafficAnalytics(context, _currentChannel!.title);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('切换频道失败', e, stackTrace);
      setState(() => toastString = S.current.playError);
      await _cleanupController(_playerController);
    }
  }

  // 允许当前源点击后重试
  Future<void> _changeChannelSources() async {
    List<String>? sources = _currentChannel?.urls;
    if (sources?.isEmpty ?? true) {
      LogUtil.e('未找到有效视频源');
      return;
    }

    final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
    if (selectedIndex != null) {
      setState(() {
        _sourceIndex = selectedIndex;
        _isRetrying = false;
        _retryCount = 0;
      });
      await _queueSwitchChannel(_currentChannel, _sourceIndex);
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

  // 处理用户暂停的回调
  void _handleUserPaused() {
    setState(() {
      _isUserPaused = true;
    });
  }

  // HLS 重试的回调
  void _handleRetry() {
    _retryPlayback(resetRetryCount: true); // 用户触发重试，重置次数
  }

  @override
  void initState() {
    super.initState();
    _adManager = AdManager(); // 初始化 AdManager
    _adManager.loadAdData(); // 加载广告数据
    if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    _loadData();
    _extractFavoriteList();
  }

  /// 清理所有资源
  @override
  void dispose() {
    _isDisposing = true;
    _cleanupController(_playerController); // 清理主播放器
    _disposeStreamUrl(); // 清理流地址
    _disposePreCacheStreamUrl(); // 清理预缓存 StreamUrl
    _pendingSwitch = null; // 清理切换队列
    _originalUrl = null; // 清理解析前地址
    _playDurationTimer?.cancel(); // 确保定时器被清理
    _playDurationTimer = null;
    _timeoutTimer?.cancel(); // 清理超时计时器
    _timeoutTimer = null; // 重置为 null
    _m3u8CheckTimer?.cancel(); // 清理 m3u8 检查定时器
    _m3u8CheckTimer = null;
    _adManager.dispose(); // 清理广告资源
    super.dispose();
  }

  Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
    if (channelName != null && channelName.isNotEmpty) {
      try {
        bool? isFirstInstall = SpUtil.getBool('is_first_install');
        bool isTV = context.watch<ThemeProvider>().isTV;

        String deviceType = isTV ? "TV" : "Other";

        if (isFirstInstall == null) {
          await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: deviceType);
          await SpUtil.putBool('is_first_install', true);
        } else {
          await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: channelName);
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
      // 添加排序逻辑
      String? userInfo = SpUtil.getString('user_all_info');
      LogUtil.i('原始 user_all_info: $userInfo'); // 添加调试日志以检查实际数据
      _sortVideoMap(_videoMap!, userInfo);
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
          _queueSwitchChannel(_currentChannel, _sourceIndex); // 使用优化后的队列机制
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
      CustomSnackBar.showSnackBar(context, S.current.channelnofavorite, duration: Duration(seconds: snackBarDurationSeconds));
      return;
    }

    if (isChannelFavorite(actualChannelId)) {
      favoriteList[Config.myFavoriteKey]![groupName]?.remove(channelName);
      if (favoriteList[Config.myFavoriteKey]![groupName]?.isEmpty ?? true) {
        favoriteList[Config.myFavoriteKey]!.remove(groupName);
      }
      CustomSnackBar.showSnackBar(context, S.current.removefavorite, duration: Duration(seconds: snackBarDurationSeconds));
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
      CustomSnackBar.showSnackBar(context, S.current.newfavorite, duration: Duration(seconds: snackBarDurationSeconds));
      isFavoriteChanged = true;
    }

    if (isFavoriteChanged) {
      try {
        await M3uUtil.saveFavoriteList(PlaylistModel(playList: favoriteList));
        _videoMap?.playList[Config.myFavoriteKey] = favoriteList[Config.myFavoriteKey];
        LogUtil.i('更新收藏列表: $_videoMap');
        if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
      } catch (error) {
        CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: snackBarDurationSeconds));
        LogUtil.logError('保存收藏失败', error);
      }
    }
  }

  Future<void> _parseData() async {
    try {
      if (_videoMap == null || _videoMap!.playList == null || _videoMap!.playList!.isEmpty) {
        LogUtil.e('播放列表无效');
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
        adManager: _adManager, // 传递 AdManager 给 TvPage
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
              adManager: _adManager, // 传递 AdManager 给 MobileVideoWidget
              showPlayIcon: _showPlayIcon, // 传递播放图标状态
              showPauseIconFromListener: _showPauseIconFromListener, // 传递暂停图标状态
              isHls: _isHls, // 传递 HLS 状态
              onUserPaused: _handleUserPaused, // 用户暂停回调
              onRetry: _handleRetry, // HLS 重试回调
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
                          adManager: _adManager,
                          showPlayIcon: _showPlayIcon, // 传递播放图标状态
                          showPauseIconFromListener: _showPauseIconFromListener, // 传递暂停图标状态
                          isHls: _isHls, // 传递 HLS 状态
                          onUserPaused: _handleUserPaused, // 用户暂停回调
                          onRetry: _handleRetry, // HLS 重试回调
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
