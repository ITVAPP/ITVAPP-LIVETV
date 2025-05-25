import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider/theme_provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:better_player_plus/better_player.dart';
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
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/util/channel_util.dart';
import 'package:itvapp_live_tv/util/traffic_analytics.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/zhConverter.dart';
import 'package:itvapp_live_tv/widget/better_player_controls.dart';
import 'package:itvapp_live_tv/widget/empty_page.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/widget/ad_manager.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 主页面，管理播放和频道切换
class LiveHomePage extends StatefulWidget {
    final PlaylistModel m3uData; // 播放列表数据
    const LiveHomePage({super.key, required this.m3uData});

    @override
    State<LiveHomePage> createState() => _LiveHomePageState();
}

// 计时器类型枚举，区分不同计时任务
enum TimerType {
    retry,        // 重试计时
    m3u8Check,    // m3u8检查
    playDuration, // 播放时长
    timeout,      // 超时检测
    bufferingCheck, // 缓冲检查
    switchTimeout,  // 切换超时检测
}

// 频道切换请求，封装频道和源索引
class SwitchRequest {
    final PlayModel? channel; // 目标频道
    final int sourceIndex;    // 源索引
    SwitchRequest(this.channel, this.sourceIndex);
}

// 计时器管理，统一处理计时任务
class TimerManager {
    final Map<TimerType, Timer?> _timers = {}; // 计时器实例映射

    // 启动单次计时器
    void startTimer(TimerType type, Duration duration, Function() callback) {
        cancelTimer(type);
        _timers[type] = Timer(duration, () {
            callback();
            _timers[type] = null;
        });
    }

    // 启动周期性计时器
    void startPeriodicTimer(TimerType type, Duration period, Function(Timer) callback) {
        cancelTimer(type);
        _timers[type] = Timer.periodic(period, callback);
    }

    // 取消指定计时器
    void cancelTimer(TimerType type) => _timers[type]?.cancel();

    // 取消所有计时器
    void cancelAll() {
        _timers.forEach((_, timer) => timer?.cancel());
        _timers.clear();
    }

    // 检查计时器是否活跃
    bool isActive(TimerType type) => _timers[type]?.isActive == true;
}

class _LiveHomePageState extends State<LiveHomePage> {
    static const int defaultMaxRetries = 1; // 最大重试次数
    static const int defaultTimeoutSeconds = 58; // 超时时间（秒）
    static const int initialProgressDelaySeconds = 60; // 初始进度检查延迟（秒）
    static const int retryDelaySeconds = 2; // 重试延迟（秒）
    static const int hlsSwitchThresholdSeconds = 3; // HLS切换阈值（秒）
    static const int nonHlsPreloadThresholdSeconds = 20; // 非HLS预加载阈值（秒）
    static const int nonHlsSwitchThresholdSeconds = 3; // 非HLS切换阈值（秒）
    static const double defaultAspectRatio = 1.78; // 默认宽高比
    static const int cleanupDelayMilliseconds = 500; // 切换清理延迟（毫秒）
    static const int snackBarDurationSeconds = 5; // 提示条显示时长（秒）
    static const int m3u8InvalidConfirmDelaySeconds = 1; // m3u8失效确认延迟（秒）
    static const int m3u8CheckIntervalSeconds = 10; // m3u8检查间隔（秒）
    static const int reparseMinIntervalMilliseconds = 10000; // m3u8重新解析间隔（毫秒）
    static const int m3u8ConnectTimeoutSeconds = 5; // m3u8连接超时（秒）
    static const int m3u8ReceiveTimeoutSeconds = 10; // m3u8接收超时（秒）
    static const int maxSwitchAttempts = 3; // 最大切换尝试次数

    String? _preCachedUrl; // 预缓存播放地址
    bool _isParsing = false; // 是否正在解析
    bool _isRetrying = false; // 是否正在重试
    int? _lastParseTime; // 上次解析时间戳
    String toastString = S.current.loading; // 当前提示信息
    PlaylistModel? _videoMap; // 视频播放列表
    PlayModel? _currentChannel; // 当前播放频道
    int _sourceIndex = 0; // 当前源索引
    BetterPlayerController? _playerController; // 播放器控制器
    bool isBuffering = false; // 是否正在缓冲
    bool isPlaying = false; // 是否正在播放
    double aspectRatio = defaultAspectRatio; // 当前宽高比
    bool _drawerIsOpen = false; // 抽屉菜单是否打开
    int _retryCount = 0; // 当前重试次数
    bool _timeoutActive = false; // 超时检测是否激活
    bool _isDisposing = false; // 是否正在释放资源
    bool _isSwitchingChannel = false; // 是否正在切换频道
    bool _shouldUpdateAspectRatio = true; // 是否需要更新宽高比
    StreamUrl? _streamUrl; // 当前流地址实例
    StreamUrl? _preCacheStreamUrl; // 预缓存流地址实例
    String? _currentPlayUrl; // 当前播放地址
    String? _originalUrl; // 原始播放地址
    bool _progressEnabled = false; // 是否启用进度检查
    bool _isHls = false; // 是否为HLS流
    Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
        Config.myFavoriteKey: <String, Map<String, PlayModel>>{}, // 收藏列表
    };
    ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
    final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析实例
    bool _isAudio = false; // 是否为音频流
    late AdManager _adManager; // 广告管理实例
    bool _isUserPaused = false; // 用户是否暂停
    bool _showPlayIcon = false; // 是否显示播放图标
    bool _showPauseIconFromListener = false; // 是否显示暂停图标（监听触发）
    int _m3u8InvalidCount = 0; // m3u8失效计数
    int _switchAttemptCount = 0; // 切换尝试计数
    ZhConverter? _s2tConverter; // 简体转繁体转换器
    ZhConverter? _t2sConverter; // 繁体转简体转换器
    bool _zhConvertersInitializing = false; // 是否正在初始化中文转换器
    bool _zhConvertersInitialized = false; // 中文转换器是否初始化完成
    final TimerManager _timerManager = TimerManager(); // 计时器管理实例
    SwitchRequest? _pendingSwitch; // 待处理切换请求
    Timer? _debounceTimer; // 防抖定时器
    bool _hasInitializedAdManager = false; // 广告管理器初始化状态
    String? _lastPlayedChannelId; // 最后播放频道ID
    
    late CancelToken _currentCancelToken; // 当前解析任务的CancelToken
    late CancelToken _preloadCancelToken; // 预加载任务的CancelToken

    // 获取频道logo，缺省返回默认logo
    String _getChannelLogo() => 
        _currentChannel?.logo?.isNotEmpty == true ? _currentChannel!.logo! : 'assets/images/logo-2.png';

    // 检查URL是否符合指定格式
    bool _checkUrlFormat(String? url, List<String> formats) {
        if (url?.isEmpty ?? true) return false;
        final lowercaseUrl = url!.toLowerCase();
        return formats.any(lowercaseUrl.contains);
    }

    // 判断是否为音频流
    bool _checkIsAudioStream(String? url) => !Config.videoPlayMode;

    // 判断是否为HLS流
    bool _isHlsStream(String? url) {
        if (_checkUrlFormat(url, ['.m3u8'])) return true;
        return !_checkUrlFormat(url, [
            '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
            '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac', '.flv', 'rtmp:'
        ]);
    }

    // 更新播放地址并判断流类型
    void _updatePlayUrl(String newUrl) {
        _currentPlayUrl = newUrl;
        _isHls = _isHlsStream(_currentPlayUrl);
    }

    // 批量更新播放状态，减少UI重建
    void _updatePlayState({
        bool? playing, bool? buffering, String? message, bool? showPlay, bool? showPause,
        bool? userPaused, bool? switching, bool? retrying, bool? parsing, int? sourceIndex, int? retryCount,
    }) {
        if (!mounted) return;
    
        bool hasChanges = false;
        List<String> changes = [];
    
        setState(() {
            // 使用统一的状态更新逻辑
            void updateState<T>(T? newValue, T currentValue, String fieldName, void Function(T) setter) {
                if (newValue != null && currentValue != newValue) {
                    setter(newValue);
                    hasChanges = true;
                    changes.add('$fieldName: $newValue');
                }
            }
            updateState(playing, isPlaying, 'playing', (v) => isPlaying = v);
            updateState(buffering, isBuffering, 'buffering', (v) => isBuffering = v);
            updateState(message, toastString, 'message', (v) => toastString = v);
            updateState(showPlay, _showPlayIcon, 'showPlay', (v) => _showPlayIcon = v);
            updateState(showPause, _showPauseIconFromListener, 'showPause', (v) => _showPauseIconFromListener = v);
            updateState(userPaused, _isUserPaused, 'userPaused', (v) => _isUserPaused = v);
            updateState(switching, _isSwitchingChannel, 'switching', (v) => _isSwitchingChannel = v);
            updateState(retrying, _isRetrying, 'retrying', (v) => _isRetrying = v);
            updateState(parsing, _isParsing, 'parsing', (v) => _isParsing = v);
            updateState(sourceIndex, _sourceIndex, 'sourceIndex', (v) => _sourceIndex = v);
            updateState(retryCount, _retryCount, 'retryCount', (v) => _retryCount = v);
        });
    }

    // 检查操作可执行性，避免状态冲突
    bool _canPerformOperation(String operationName, {
        bool checkRetrying = true, bool checkSwitching = true, bool checkDisposing = true, bool checkParsing = true,
    }) {
        if (checkDisposing && _isDisposing) {
            LogUtil.i('$operationName 被阻止: 正在释放资源');
            return false;
        }
        
        List<String> blockers = [];
        if (checkRetrying && _isRetrying) blockers.add('正在重试');
        if (checkSwitching && _isSwitchingChannel) blockers.add('正在切换频道');
        if (checkParsing && _isParsing) blockers.add('正在解析');
        
        if (blockers.isNotEmpty) {
            LogUtil.i('$operationName 被阻止: ${blockers.join(", ")}');
            return false;
        }
        return true;
    }

    // 取消当前解析任务
    void _cancelCurrentTask() {
        try {
            if (!_currentCancelToken.isCancelled) {
                _currentCancelToken.cancel('切换频道或超时');
                LogUtil.i('取消当前解析任务');
            }
        } catch (e) {
            LogUtil.i('当前任务CancelToken未初始化或已取消');
        }
    }

    // 取消预加载任务
    void _cancelPreloadTask() {
        try {
            if (!_preloadCancelToken.isCancelled) {
                _preloadCancelToken.cancel('切换频道或新预加载');
                LogUtil.i('取消预加载任务');
            }
        } catch (e) {
            LogUtil.i('预加载任务CancelToken未初始化或已取消');
        }
    }

    // 准备预缓存数据源
    Future<void> _preparePreCacheSource(String url) async {
        if (_playerController == null) {
            LogUtil.e('预缓存失败: 播放器控制器为空');
            return;
        }
        final newSource = BetterPlayerConfig.createDataSource(
            isHls: _isHlsStream(url),
            url: url,
            channelTitle: _currentChannel?.title,
            channelLogo: _getChannelLogo(),
        );
        await _playerController!.preCache(newSource);
        LogUtil.i('预缓存数据源: $url');
    }

    // 清理预缓存资源
    Future<void> _cleanupPreCacheResources() async {
        _preCachedUrl = null;
        if (_preCacheStreamUrl != null) {
            await _disposeStreamUrlInstance(_preCacheStreamUrl);
            _preCacheStreamUrl = null;
            LogUtil.i('清理预缓存资源完成');
        }
    }

    // 切换到预缓存地址
    Future<void> _switchToPreCachedUrl(String logDescription) async {
        if (_isDisposing || _preCachedUrl == null) {
            LogUtil.i('$logDescription: ${_isDisposing ? "正在释放资源" : "预缓存地址为空"}，跳过切换');
            return;
        }
        
        _timerManager.cancelTimer(TimerType.timeout);
        _timerManager.cancelTimer(TimerType.retry);
        
        if (_preCachedUrl == _currentPlayUrl) {
            LogUtil.i('$logDescription: 预缓存地址与当前地址相同，重新解析');
            await _cleanupPreCacheResources();
            await _reparseAndSwitch();
            return;
        }
        
        try {
            _updatePlayState(switching: true);
            if (_playerController == null) {
                LogUtil.e('$logDescription: 切换失败，播放器控制器为空');
                return;
            }
            await _preparePreCacheSource(_preCachedUrl!);
            final newSource = BetterPlayerConfig.createDataSource(
                url: _preCachedUrl!,
                isHls: _isHlsStream(_preCachedUrl),
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
            );
            await _playerController?.setupDataSource(newSource);
            await _playerController?.play();
            _startPlayDurationTimer();
            _updatePlayUrl(_preCachedUrl!);
            _updatePlayState(playing: true, switching: false);
            _switchAttemptCount = 0;
            LogUtil.i('$logDescription: 切换预缓存地址成功: $_preCachedUrl');
        } catch (e, stackTrace) {
            LogUtil.e('$logDescription: 切换预缓存地址失败: $e');
            _retryPlayback();
        } finally {
            _updatePlayState(switching: false);
            _progressEnabled = false;
            await _cleanupPreCacheResources();
        }
    }

    // 执行视频播放流程
    Future<void> _playVideo({bool isRetry = false, bool isSourceSwitch = false}) async {
        if (_currentChannel == null || !_isSourceIndexValid()) {
            LogUtil.e('播放失败：${_currentChannel == null ? "频道为空" : "源索引无效"}');
            return;
        }
        
        bool isChannelChange = !isSourceSwitch || (_lastPlayedChannelId != _currentChannel!.id);
        String channelId = _currentChannel?.id ?? _currentChannel!.title ?? 'unknown_channel';
        _lastPlayedChannelId = channelId;
        
        if (isChannelChange) {
            _adManager.onChannelChanged(channelId);
        }
        
        String sourceName = _getSourceDisplayName(_currentChannel!.urls![_sourceIndex], _sourceIndex);
        LogUtil.i('播放频道: ${_currentChannel!.title}, 源: $sourceName, retry: $isRetry, switch: $isSourceSwitch');
        
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.cancelTimer(TimerType.timeout);
        
        _updatePlayState(
            message: '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
            playing: false,
            buffering: false,
            showPlay: false,
            showPause: false,
            userPaused: false,
            switching: true,
        );
        _startPlaybackTimeout();
        
        try {
            if (!isRetry && !isSourceSwitch && isChannelChange && _hasInitializedAdManager) {
                try {
                    bool shouldPlay = await _adManager.shouldPlayVideoAdAsync();
                    if (shouldPlay) {
                        await _adManager.playVideoAd();
                        LogUtil.i('视频广告播放完成');
                    }
                } catch (e) {
                    LogUtil.e('视频广告播放失败: $e');
                }
            }
            
            if (_playerController != null) {
                await _releaseAllResources(isDisposing: false);
            }
            
            await _preparePlaybackUrl();
            await _setupPlayerController();
            await _startPlayback();
            _switchAttemptCount = 0;
        } catch (e, stackTrace) {
            LogUtil.e('播放失败: $e');
            await _disposeStreamUrlInstance(_streamUrl);
            _streamUrl = null;
            _switchAttemptCount++;
            
            if (_switchAttemptCount <= maxSwitchAttempts) {
                _handleSourceSwitching();
            } else {
                _switchAttemptCount = 0;
                _updatePlayState(
                    message: S.current.playError,
                    playing: false,
                    buffering: false,
                    retrying: false,
                    switching: false,
                );
            }
        } finally {
            if (mounted) {
                _updatePlayState(
                    playing: null,
                    buffering: null,
                    message: null,
                    switching: false,
                );
                _timerManager.cancelTimer(TimerType.switchTimeout);
                _processPendingSwitch();
            }
        }
    }

    // 验证当前源索引有效性
    bool _isSourceIndexValid() {
        if (_sourceIndex < 0 || _currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
            _sourceIndex = 0;
            if (_currentChannel?.urls?.isEmpty ?? true) {
                LogUtil.e('频道无可用源');
                _updatePlayState(
                    message: S.current.playError,
                    playing: false,
                    buffering: false,
                    showPlay: false,
                    showPause: false,
                );
                return false;
            }
        }
        return true;
    }

    // 启动播放超时检测
    void _startPlaybackTimeout() {
        _timeoutActive = true;
        _timerManager.startTimer(
            TimerType.timeout,
            Duration(seconds: defaultTimeoutSeconds),
            () {
                if (!mounted || !_timeoutActive || _isRetrying || _isSwitchingChannel || _isDisposing) {
                    _timeoutActive = false;
                    return;
                }
                if (_playerController?.isPlaying() != true) {
                    _handleSourceSwitching();
                    _timeoutActive = false;
                }
            }
        );
    }

    // 准备播放地址并解析流
    Future<void> _preparePlaybackUrl() async {
        if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
            throw Exception('频道源索引无效');
        }
        
        String url = _currentChannel!.urls![_sourceIndex].toString();
        _originalUrl = url;
        
        await _disposeStreamUrlInstance(_streamUrl);
        _currentCancelToken = CancelToken();
        _streamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
        String parsedUrl = await _streamUrl!.getStreamUrl();
        
        if (parsedUrl == 'ERROR') {
            LogUtil.e('地址解析失败: $url');
            if (mounted) setState(() => toastString = S.current.vpnplayError);
            await _disposeStreamUrlInstance(_streamUrl);
            _streamUrl = null;
            throw Exception('地址解析失败');
        }
        
        _updatePlayUrl(parsedUrl);
        bool isAudio = _checkIsAudioStream(null);
        setState(() => _isAudio = isAudio);
        LogUtil.i('播放信息: URL=$parsedUrl, 音频模式=$isAudio, HLS=$_isHls');
    }

    // 设置播放器控制器并初始化数据源
    Future<void> _setupPlayerController() async {
        if (_playerController != null) {
            await _releaseAllResources(isDisposing: false);
        }
        
        if (_currentPlayUrl?.isEmpty ?? true) {
            throw Exception('播放地址为空');
        }
        
        try {
            final dataSource = BetterPlayerConfig.createDataSource(
                url: _currentPlayUrl!,
                isHls: _isHls,
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
            );
            final betterPlayerConfiguration = BetterPlayerConfig.createPlayerConfig(
                eventListener: _videoListener,
                isHls: _isHls
            );
            _playerController = BetterPlayerController(betterPlayerConfiguration);
            await _playerController!.setupDataSource(dataSource);
            if (mounted) setState(() {});
        } catch (e, stackTrace) {
            LogUtil.e('设置播放器失败: $e');
            await _releaseAllResources(isDisposing: false);
            throw e;
        }
    }

    // 开始播放视频
    Future<void> _startPlayback() async {
        if (_playerController == null) {
            throw Exception('播放器控制器为空');
        }
        await _playerController?.play();
        _timeoutActive = false;
        _timerManager.cancelTimer(TimerType.timeout);
    }

    // 处理待执行的频道切换请求
    void _processPendingSwitch() {
        if (_pendingSwitch == null || _isParsing || _isRetrying || _isDisposing) {
            if (_pendingSwitch != null) {
                LogUtil.i('切换请求冲突: parsing=$_isParsing, retrying=$_isRetrying, disposing=$_isDisposing');
            }
            return;
        }
        
        final nextRequest = _pendingSwitch!;
        _pendingSwitch = null;
        _currentChannel = nextRequest.channel;
        _sourceIndex = nextRequest.sourceIndex;
        
        Future.microtask(() async {
            await _playVideo(); 
        });
    }

    // 队列化切换频道，防抖处理
    Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
        if (channel == null) {
            LogUtil.e('切换频道失败: 频道为空');
            return;
        }
        
        final safeSourceIndex = _getSafeSourceIndex(channel, sourceIndex);
        _debounceTimer?.cancel();
        _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
            if (!mounted) return;
            _pendingSwitch = SwitchRequest(channel, safeSourceIndex);
            
            if (!_isSwitchingChannel) {
                _processPendingSwitch();
            } else {
                _timerManager.startTimer(
                    TimerType.switchTimeout, 
                    Duration(seconds: m3u8ConnectTimeoutSeconds), 
                    () {
                        if (mounted) {
                            LogUtil.e('强制处理切换频道');
                            _updatePlayState(switching: false);
                            _processPendingSwitch();
                        }
                    },
                );
            }
        });
    }

    // 获取安全的源索引
    int _getSafeSourceIndex(PlayModel channel, int requestedIndex) {
        if (channel.urls?.isEmpty ?? true) {
            LogUtil.e('频道无可用源');
            return 0;
        }
        return channel.urls!.length > requestedIndex ? requestedIndex : 0;
    }

    // 视频播放事件监听器
    void _videoListener(BetterPlayerEvent event) async {
        if (!mounted || _playerController == null || _isDisposing) return;
        
        final ignoredEvents = {
            BetterPlayerEventType.changedPlayerVisibility,
            BetterPlayerEventType.bufferingUpdate,
            BetterPlayerEventType.changedTrack,
            BetterPlayerEventType.setupDataSource,
            BetterPlayerEventType.changedSubtitles,
        };
        if (ignoredEvents.contains(event.betterPlayerEventType)) return;
        
        switch (event.betterPlayerEventType) {
            case BetterPlayerEventType.initialized:
                if (_shouldUpdateAspectRatio) {
                    final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? defaultAspectRatio;
                    if (aspectRatio != newAspectRatio) {
                        setState(() {
                            aspectRatio = newAspectRatio;
                            _shouldUpdateAspectRatio = false;
                        });
                    }
                }
                break;
                
            case BetterPlayerEventType.exception:
                if (_isParsing || _isSwitchingChannel) return;
                final error = event.parameters?["error"] as String? ?? "Unknown error";
                LogUtil.e('播放器异常: $error');
                
                if (_preCachedUrl != null) {
                    await _switchToPreCachedUrl('异常触发');
                } else {
                    _retryPlayback();
                }
                break;
                
            case BetterPlayerEventType.bufferingStart:
                _updatePlayState(buffering: true, message: S.current.loading);
                break;
                
            case BetterPlayerEventType.bufferingEnd:
                _updatePlayState(
                    buffering: false,
                    message: 'HIDE_CONTAINER',
                    showPause: _isUserPaused ? false : _showPauseIconFromListener,
                );
                _timerManager.cancelTimer(TimerType.bufferingCheck);
                break;
                
            case BetterPlayerEventType.play:
                if (!isPlaying) {
                    _updatePlayState(
                        playing: true,
                        message: isBuffering ? toastString : 'HIDE_CONTAINER',
                        showPlay: false,
                        showPause: false,
                        userPaused: false,
                    );
                    _timerManager.cancelTimer(TimerType.bufferingCheck);
                    if (!_timerManager.isActive(TimerType.playDuration)) {
                        _startPlayDurationTimer();
                    }
                }
                _adManager.onVideoStartPlaying();
                break;
                
            case BetterPlayerEventType.pause:
                if (isPlaying) {
                    _updatePlayState(
                        playing: false,
                        message: S.current.playpause,
                        showPlay: _isUserPaused,
                        showPause: !_isUserPaused,
                    );
                    LogUtil.i('播放暂停，用户触发: $_isUserPaused');
                }
                break;
                
            case BetterPlayerEventType.progress:
                if (_isParsing || _isSwitchingChannel || !_progressEnabled || !isPlaying) return;
                
                final position = event.parameters?["progress"] as Duration?;
                final duration = event.parameters?["duration"] as Duration?;
                
                if (position != null && duration != null) {
                    final remainingTime = duration - position;
                    
                    if (_isHls) {
                        if (_preCachedUrl != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
                            await _switchToPreCachedUrl('HLS剩余时间触发');
                        }
                    } else {
                        if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
                            final nextUrl = _getNextVideoUrl();
                            if (nextUrl != null && nextUrl != _preCachedUrl) {
                                LogUtil.i('非HLS预加载下一源: $nextUrl');
                                _preloadNextVideo(nextUrl);
                            }
                        }
                        if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
                            await _switchToPreCachedUrl('非HLS切换触发');
                        }
                    }
                }
                break;
                
            case BetterPlayerEventType.finished:
                if (_isParsing || _isSwitchingChannel) return;
                if (!_isHls && _preCachedUrl != null) {
                    await _switchToPreCachedUrl('非HLS播放结束');
                } else if (_isHls) {
                    LogUtil.i('HLS流异常结束，重试');
                    _retryPlayback();
                } else {
                    _handleNoMoreSources();
                }
                break;
                
            default:
                break;
        }
    }

    // 检查m3u8文件有效性
    Future<bool> _checkM3u8Validity() async {
        if (_currentPlayUrl == null || !_isHls) return true;
        
        try {
            final completer = Completer<bool>();
            Future(() async {
                try {
                    final String? content = await HttpUtil().getRequest<String>(
                        _currentPlayUrl!,
                        options: Options(
                            extra: {
                                'connectTimeout': const Duration(seconds: m3u8ConnectTimeoutSeconds),
                                'receiveTimeout': const Duration(seconds: m3u8ReceiveTimeoutSeconds),
                            },
                        ),
                        retryCount: 1,
                    );
                    
                    if (content?.isEmpty ?? true) {
                        LogUtil.e('m3u8内容为空: $_currentPlayUrl');
                        completer.complete(false);
                        return;
                    }
                    
                    bool hasSegments = content!.contains('.ts');
                    bool hasValidDirectives = content.contains('#EXTINF') || content.contains('#EXT-X-STREAM-INF');
                    bool isValid = hasSegments || hasValidDirectives;
                    
                    if (!isValid) LogUtil.e('m3u8内容无效');
                    completer.complete(isValid);
                } catch (e, stackTrace) {
                    LogUtil.e('m3u8检查失败: $e');
                    completer.complete(false);
                }
            });
            return await completer.future;
        } catch (e, stackTrace) {
            LogUtil.e('m3u8有效性检查异常: $e');
            return false;
        }
    }

    // 启动m3u8检查定时器
    void _startM3u8CheckTimer() {
        if (!_isHls) return;
        
        _timerManager.cancelTimer(TimerType.m3u8Check);
        _timerManager.startPeriodicTimer(
            TimerType.m3u8Check,
            const Duration(seconds: m3u8CheckIntervalSeconds),
            (_) async {
                if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) return;
                
                final isValid = await _checkM3u8Validity();
                
                if (!isValid) {
                    _m3u8InvalidCount++;
                    if (_m3u8InvalidCount == 1) {
                        _timerManager.startTimer(
                            TimerType.retry,
                            Duration(seconds: m3u8InvalidConfirmDelaySeconds),
                            () async {
                                if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) {
                                    _m3u8InvalidCount = 0;
                                    return;
                                }
                                
                                final secondCheck = await _checkM3u8Validity();
                                if (!secondCheck) {
                                    LogUtil.i('m3u8连续失效，重新解析');
                                    await _reparseAndSwitch();
                                } else {
                                    _m3u8InvalidCount = 0;
                                }
                            },
                        );
                    } else if (_m3u8InvalidCount >= 2) {
                        LogUtil.i('m3u8连续失效，重新解析');
                        await _reparseAndSwitch();
                        _m3u8InvalidCount = 0;
                    }
                } else {
                    _m3u8InvalidCount = 0;
                }
            },
        );
    }

    // 启动播放时长检查定时器
    void _startPlayDurationTimer() {
        _timerManager.cancelTimer(TimerType.playDuration);
        _timerManager.startTimer(
            TimerType.playDuration,
            const Duration(seconds: initialProgressDelaySeconds),
            () {
                if (mounted && !_isRetrying && !_isSwitchingChannel && !_isDisposing) {
                    LogUtil.i('播放时长检查启动');
                    if (_isHls) {
                        if (_originalUrl?.toLowerCase().contains('timelimit') ?? false) {
                            _startM3u8CheckTimer();
                        }
                    } else {
                        if (_getNextVideoUrl() != null) {
                            _progressEnabled = true;
                            LogUtil.i('非HLS流启用progress监听');
                        }
                    }
                    _retryCount = 0;
                }
            },
        );
    }

    // 预加载下一视频源
    Future<void> _preloadNextVideo(String url) async {
        if (!_canPerformOperation('预加载视频', checkDisposing: true, checkSwitching: true, checkRetrying: false, checkParsing: false)) return;
        
        if (_playerController == null) {
            LogUtil.e('预加载失败: 播放器控制器为空');
            return;
        }
        
        if (_preCachedUrl == url) {
            LogUtil.i('URL已预缓存: $url');
            return;
        }
        
        if (_preCachedUrl != null) {
            await _cleanupPreCacheResources();
        }
        
        StreamUrl? tempStreamUrl;
        
        try {
            LogUtil.i('开始预加载: $url');
            _preloadCancelToken = CancelToken();
            tempStreamUrl = StreamUrl(url, cancelToken: _preloadCancelToken);
            String parsedUrl = await tempStreamUrl.getStreamUrl();
            
            if (parsedUrl == 'ERROR') {
                LogUtil.e('预加载解析失败: $url');
                return;
            }
            
            if (_playerController == null) {
                LogUtil.e('预缓存失败: 播放器控制器已释放');
                return;
            }
            
            _preCacheStreamUrl = tempStreamUrl;
            tempStreamUrl = null;
            _preCachedUrl = parsedUrl;
            
            final nextSource = BetterPlayerConfig.createDataSource(
                isHls: _isHlsStream(parsedUrl),
                url: parsedUrl,
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
            );
            
            await _playerController!.preCache(nextSource);
            LogUtil.i('预缓存完成: $parsedUrl');
        } catch (e, stackTrace) {
            LogUtil.e('预加载失败: $e');
            _preCachedUrl = null;
            if (_playerController != null) {
                try {
                    await _playerController!.clearCache();
                } catch (clearError) {
                    LogUtil.e('清除缓存失败: $clearError');
                }
            }
        } finally {
            if (tempStreamUrl != null) {
                await _disposeStreamUrlInstance(tempStreamUrl);
            }
        }
    }

    // 初始化中文转换器
    Future<void> _initializeZhConverters() async {
        if (_zhConvertersInitialized || _zhConvertersInitializing) return;
        
        _zhConvertersInitializing = true;
        try {
            await Future.wait([
                if (_s2tConverter == null) (_s2tConverter = ZhConverter('s2t')).initialize(),
                if (_t2sConverter == null) (_t2sConverter = ZhConverter('t2s')).initialize(),
            ]);
            _zhConvertersInitialized = true;
            LogUtil.i('中文转换器初始化完成');
        } catch (e, stackTrace) {
            LogUtil.e('中文转换器初始化失败: $e');
        } finally {
            _zhConvertersInitializing = false;
        }
    }

    // 重试播放，限制重试次数
    void _retryPlayback({bool resetRetryCount = false}) {
        if (!_canPerformOperation('重试播放') || _isParsing) {
            LogUtil.i('重试阻止: ${_isParsing ? "正在解析" : "状态冲突"}');
            return;
        }
        
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.cancelTimer(TimerType.timeout);
        
        if (resetRetryCount) {
            _updatePlayState(retryCount: 0);
        }
        
        if (_retryCount < defaultMaxRetries) {
            _updatePlayState(
                buffering: false,
                message: S.current.retryplay,
                showPlay: false,
                showPause: false,
                retrying: true,
                retryCount: _retryCount + 1,
            );
            LogUtil.i('重试播放: 第$_retryCount次');
            
            _timerManager.startTimer(
                TimerType.retry,
                const Duration(seconds: retryDelaySeconds),
                () async {
                    if (!mounted || _isDisposing || _isSwitchingChannel || _isParsing) {
                        _updatePlayState(retrying: false);
                        return;
                    }
                    await _playVideo(isRetry: true);
                    if (mounted) _updatePlayState(retrying: false);
                }
            );
        } else {
            LogUtil.i('重试次数超限，切换下一源');
            _handleSourceSwitching();
        }
    }

    // 获取下一个视频源地址
    String? _getNextVideoUrl() {
        if (_currentChannel?.urls?.isEmpty ?? true) return null;
        
        final List<String> urls = _currentChannel!.urls!;
        final nextSourceIndex = _sourceIndex + 1;
        
        return nextSourceIndex < urls.length ? urls[nextSourceIndex] : null;
    }

    // 处理源切换
    void _handleSourceSwitching({bool isFromFinished = false, BetterPlayerController? oldController}) {
        if (_isRetrying || _isDisposing) return;
        
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.cancelTimer(TimerType.timeout);
        
        final nextUrl = _getNextVideoUrl();
        if (nextUrl == null) {
            LogUtil.i('无更多源可切换');
            _handleNoMoreSources();
            return;
        }
        
        _switchAttemptCount++;
        if (_switchAttemptCount > maxSwitchAttempts) {
            LogUtil.e('切换尝试超限: $_switchAttemptCount');
            _handleNoMoreSources();
            _switchAttemptCount = 0;
            return;
        }
        
        _updatePlayState(
            sourceIndex: _sourceIndex + 1,
            retrying: false,
            retryCount: 0,
            buffering: false,
            message: S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? ''),
        );
        _preCachedUrl = null;
        LogUtil.i('切换下一源: $nextUrl');
        _startNewSourceTimer();
    }

    // 处理无更多源的情况
    Future<void> _handleNoMoreSources() async {
        _updatePlayState(
            message: S.current.playError,
            playing: false,
            buffering: false,
            showPlay: false,
            showPause: false,
            sourceIndex: 0,
            retrying: false,
            retryCount: 0,
        );
        await _releaseAllResources(isDisposing: false);
        LogUtil.i('播放结束，无更多源');
        _switchAttemptCount = 0;
    }

    // 启动新源播放定时器
    void _startNewSourceTimer() {
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.startTimer(
            TimerType.retry,
            const Duration(seconds: retryDelaySeconds),
            () async {
                if (!mounted || _isSwitchingChannel || _isDisposing) return;
                await _playVideo(isSourceSwitch: true);
            }
        );
    }

    // 释放所有资源
    Future<void> _releaseAllResources({bool isDisposing = false}) async {
        if (_isDisposing) return;
        _isDisposing = true;
        _timerManager.cancelAll();
        
        try {
            if (_playerController != null) {
                final controller = _playerController!;
                _playerController = null;
                
                try {
                    controller.removeEventsListener(_videoListener);
                    
                    if (controller.isPlaying() ?? false) {
                        await controller.pause();
                        await controller.setVolume(0);
                    }
                    
                    if (controller.videoPlayerController != null) {
                        await controller.videoPlayerController!.dispose();
                    }
                    controller.dispose();
                } catch (e) {
                    LogUtil.e('释放播放器资源失败: $e');
                }
            }
            
            final currentStreamUrl = _streamUrl;
            final preStreamUrl = _preCacheStreamUrl;
            
            _streamUrl = null;
            _preCacheStreamUrl = null;
            
            if (currentStreamUrl != null) {
                await _disposeStreamUrlInstance(currentStreamUrl);
            }
            
            if (preStreamUrl != null && preStreamUrl != currentStreamUrl) {
                await _disposeStreamUrlInstance(preStreamUrl);
            }
            
            if (isDisposing) {
                _adManager.dispose();
            } else {
                _adManager.reset(rescheduleAds: false, preserveTimers: true);
            }
            
            if (mounted && !isDisposing) {
                _updatePlayState(
                    playing: false,
                    buffering: false,
                    retrying: false,
                    parsing: false,
                    switching: false,
                    showPlay: false,
                    showPause: false,
                    userPaused: false,
                );
                _progressEnabled = false;
                _preCachedUrl = null;
                _lastParseTime = null;
                _currentPlayUrl = null;
                _originalUrl = null;
                _m3u8InvalidCount = 0;
            }
            
            await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
        } catch (e, stackTrace) {
            LogUtil.e('释放资源失败: $e');
        } finally {
            _isDisposing = isDisposing;
        }
    }

    // 释放StreamUrl实例
    Future<void> _disposeStreamUrlInstance(StreamUrl? instance) async {
        if (instance == null) return;
        try {
            await instance.dispose();
        } catch (e, stackTrace) {
            LogUtil.e('释放StreamUrl失败: $e');
        }
    }

    // 重新解析并切换播放地址
    Future<void> _reparseAndSwitch({bool force = false}) async {
        if (!_canPerformOperation('重新解析')) return;
        
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!force && _lastParseTime != null) {
            final timeSinceLastParse = now - _lastParseTime!;
            if (timeSinceLastParse < reparseMinIntervalMilliseconds) {
                LogUtil.i('解析频率过高，延迟${reparseMinIntervalMilliseconds - timeSinceLastParse}ms');
                _timerManager.startTimer(
                    TimerType.retry,
                    Duration(milliseconds: (reparseMinIntervalMilliseconds - timeSinceLastParse).toInt()),
                    () {
                        if (mounted) _reparseAndSwitch(force: true);
                    }
                );
                return;
            }
        }
        
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.cancelTimer(TimerType.m3u8Check);
        
        _updatePlayState(parsing: true, retrying: true);
        
        StreamUrl? tempStreamUrl;
        
        try {
            if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
                LogUtil.e('频道信息无效');
                throw Exception('无效的频道信息');
            }
            
            _updatePlayState(switching: true);
            String url = _currentChannel!.urls![_sourceIndex].toString();
            LogUtil.i('重新解析地址: $url');
            
            await _disposeStreamUrlInstance(_streamUrl);
            _streamUrl = null;
            
            _currentCancelToken = CancelToken();
            tempStreamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
            String newParsedUrl = await tempStreamUrl.getStreamUrl();
            
            if (newParsedUrl == 'ERROR') {
                LogUtil.e('重新解析失败: $url');
                return;
            }
            
            if (newParsedUrl == _currentPlayUrl) {
                LogUtil.i('新地址与当前地址相同，无需切换');
                _updatePlayState(parsing: false, retrying: false, switching: false);
                return;
            }
            
            _streamUrl = tempStreamUrl;
            tempStreamUrl = null;
            _preCachedUrl = newParsedUrl;
            LogUtil.i('预缓存地址: $_preCachedUrl');
            
            if (_playerController != null) {
                if (_isDisposing) {
                    LogUtil.i('解析中断，退出');
                    _preCachedUrl = null;
                    _updatePlayState(parsing: false, retrying: false, switching: false);
                    return;
                }
                
                await _preparePreCacheSource(newParsedUrl);
                
                if (_isDisposing) {
                    LogUtil.i('预加载中断，退出');
                    _preCachedUrl = null;
                    _updatePlayState(parsing: false, retrying: false, switching: false);
                    return;
                }
                
                _progressEnabled = true;
                _lastParseTime = now;
                LogUtil.i('预缓存完成，等待切换');
            } else {
                LogUtil.i('播放器控制器为空，切换下一源');
                _handleSourceSwitching();
            }
            _updatePlayState(switching: false);
        } catch (e, stackTrace) {
            LogUtil.e('重新解析失败: $e');
            _preCachedUrl = null;
            _handleSourceSwitching();
        } finally {
            if (tempStreamUrl != null) {
                await _disposeStreamUrlInstance(tempStreamUrl);
            }
            if (_streamUrl != null && _preCachedUrl == null) {
                await _disposeStreamUrlInstance(_streamUrl);
                _streamUrl = null;
            }
            if (mounted) {
                _updatePlayState(parsing: false, retrying: false);
            }
        }
    }

    // 提取并转换地理信息
    Future<Map<String, String?>> _getLocationInfo(String? userInfo) async {
        if (userInfo?.isEmpty ?? true) {
            LogUtil.i('地理信息为空');
            return {'region': null, 'city': null};
        }
        
        try {
            final Map<String, dynamic> userData = jsonDecode(userInfo!);
            final Map<String, dynamic>? locationData = userData['info']?['location'];
            
            if (locationData == null) {
                LogUtil.i('无location字段');
                return {'region': null, 'city': null};
            }
            
            String? region = locationData['region'] as String?;
            String? city = locationData['city'] as String?;
            
            if ((region?.isEmpty ?? true) && (city?.isEmpty ?? true)) {
                return {'region': null, 'city': null};
            }
            
            if (!mounted) return {'region': null, 'city': null};
            
            final currentLocale = Localizations.localeOf(context).toString();
            LogUtil.i('当前语言环境: $currentLocale');
            
            if (currentLocale.startsWith('zh')) {
                if (!_zhConvertersInitialized) {
                    await _initializeZhConverters();
                }
                
                if (_zhConvertersInitialized) {
                    bool isTraditional = currentLocale.contains('TW') ||
                        currentLocale.contains('HK') ||
                        currentLocale.contains('MO');
                    ZhConverter? converter = isTraditional ? _s2tConverter : _t2sConverter;
                    String targetType = isTraditional ? '繁体' : '简体';
                    
                    if (converter != null) {
                        if (region?.isNotEmpty ?? false) {
                            String oldRegion = region!;
                            region = converter.convertSync(region);
                            LogUtil.i('region转换$targetType: $oldRegion -> $region');
                        }
                        if (city?.isNotEmpty ?? false) {
                            String oldCity = city!;
                            city = converter.convertSync(city);
                            LogUtil.i('city转换$targetType: $oldCity -> $city');
                        }
                    }
                } else {
                    LogUtil.e('转换器初始化失败');
                }
            }
            
            final String? regionPrefix = (region?.length ?? 0) >= 2 ? region!.substring(0, 2) : region;
            final String? cityPrefix = (city?.length ?? 0) >= 2 ? city!.substring(0, 2) : city;
            
            LogUtil.i('地理信息: 地区=$regionPrefix, 城市=$cityPrefix');
            return {'region': regionPrefix, 'city': cityPrefix};
        } catch (e, stackTrace) {
            LogUtil.e('解析地理信息失败: $e');
            return {'region': null, 'city': null};
        }
    }

    // 根据地理前缀排序列表
    List<String> _sortByGeoPrefix(List<String> items, String? prefix) {
        if (prefix?.isEmpty ?? true) {
            LogUtil.i('地理前缀为空，保持原序');
            return items;
        }
        
        if (items.isEmpty) {
            LogUtil.i('列表为空');
            return items;
        }
        
        final matchingItems = <String>[];
        final nonMatchingItems = <String>[];
        
        for (var item in items) {
            if (item.startsWith(prefix!)) {
                matchingItems.add(item);
            } else {
                nonMatchingItems.add(item);
            }
        }
        
        final result = [...matchingItems, ...nonMatchingItems];
        LogUtil.i('排序结果: $result');
        return result;
    }

    // 根据地理信息排序播放列表
    Future<void> _sortVideoMap(PlaylistModel videoMap, String? userInfo) async {
        if (videoMap.playList?.isEmpty ?? true) return;
        
        final location = await _getLocationInfo(userInfo);
        final String? regionPrefix = location['region'];
        final String? cityPrefix = location['city'];
        
        if (regionPrefix?.isEmpty ?? true) {
            LogUtil.i('地区前缀为空，跳过排序');
            return;
        }
        
        videoMap.playList!.forEach((category, groups) {
            if (groups is! Map<String, Map<String, PlayModel>>) {
                LogUtil.e('分类 $category 类型无效');
                return;
            }
            
            final groupList = groups.keys.toList();
            bool categoryNeedsSort = groupList.any((group) => group.contains(regionPrefix!));
            if (!categoryNeedsSort) return;
            
            final sortedGroups = _sortByGeoPrefix(groupList, regionPrefix);
            final newGroups = <String, Map<String, PlayModel>>{};
            
            for (var group in sortedGroups) {
                final channels = groups[group];
                if (channels is! Map<String, PlayModel>) {
                    LogUtil.e('组 $group 类型无效');
                    continue;
                }
                
                final channelList = channels.keys.toList();
                final newChannels = <String, PlayModel>{};
                
                if (regionPrefix != null && group.contains(regionPrefix) && (cityPrefix?.isNotEmpty ?? false)) {
                    final sortedChannels = _sortByGeoPrefix(channelList, cityPrefix);
                    for (var channel in sortedChannels) newChannels[channel] = channels[channel]!;
                } else {
                    for (var channel in channelList) newChannels[channel] = channels[channel]!;
                }
                newGroups[group] = newChannels;
            }
            
            videoMap.playList![category] = newGroups;
            LogUtil.i('分类 $category 排序完成');
        });
    }

    // 处理频道点击事件
    Future<void> _onTapChannel(PlayModel? model) async {
        if (model == null) return;
        
        try {
            _updatePlayState(
                buffering: false,
                message: S.current.loading,
                retrying: false,
                retryCount: 0,
            );
            
            _timerManager.cancelTimer(TimerType.retry);
            _timerManager.cancelTimer(TimerType.m3u8Check);
            
            _currentChannel = model;
            _sourceIndex = 0;
            _shouldUpdateAspectRatio = true;
            _switchAttemptCount = 0;
            await _queueSwitchChannel(_currentChannel, _sourceIndex);
            
            if (Config.Analytics) {
                await _sendTrafficAnalytics(context, _currentChannel!.title);
            }
        } catch (e, stackTrace) {
            LogUtil.e('切换频道失败: $e');
            _updatePlayState(message: S.current.playError);
            await _releaseAllResources(isDisposing: false);
        }
    }

    // 切换频道源
    Future<void> _changeChannelSources() async {
        final sources = _currentChannel?.urls;
        if (sources?.isEmpty ?? true) {
            LogUtil.e('无有效视频源');
            return;
        }
        
        final selectedIndex = await changeChannelSources(context, sources, _sourceIndex);
        if (selectedIndex != null) {
            _updatePlayState(sourceIndex: selectedIndex, retrying: false, retryCount: 0);
            _switchAttemptCount = 0;
            await _queueSwitchChannel(_currentChannel, _sourceIndex);
        }
    }

    // 处理返回键事件
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

    // 处理用户暂停事件
    void _handleUserPaused() => _updatePlayState(userPaused: true);

    // 处理重试事件
    void _handleRetry() => _retryPlayback(resetRetryCount: true);

    @override
    void initState() {
        super.initState();
        _adManager = AdManager();
        Future.microtask(() async {
            await _adManager.loadAdData();
            _hasInitializedAdManager = true;
        });
        if (!EnvUtil.isMobile) windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        _loadData();
        _extractFavoriteList();
        LogUtil.i('播放模式: ${Config.videoPlayMode ? "视频" : "音频"}');
        Future.microtask(() => _initializeZhConverters());
    }

    @override
    void dispose() {
        _releaseAllResources(isDisposing: true);
        favoriteList.clear();
        _videoMap = null;
        _s2tConverter = null;
        _t2sConverter = null;
        _debounceTimer?.cancel();
        super.dispose();
    }

    // 发送流量统计数据
    Future<void> _sendTrafficAnalytics(BuildContext context, String? channelName) async {
        if (channelName?.isNotEmpty ?? false) {
            try {
                bool? isFirstInstall = SpUtil.getBool('is_first_install');
                bool isTV = context.watch<ThemeProvider>().isTV;
                String deviceType = isTV ? "TV" : "Other";
                
                if (isFirstInstall == null) {
                    await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: deviceType);
                    await SpUtil.putBool('is_first_install', true);
                } else {
                    await _trafficAnalytics.sendPageView(context, referrer: "LiveHomePage", additionalPath: channelName!);
                }
            } catch (e, stackTrace) {
                LogUtil.e('发送流量统计失败: $e');
            }
        }
    }

    // 加载播放数据并排序
    Future<void> _loadData() async {
        _updatePlayState(retrying: false, retryCount: 0);
        _timerManager.cancelAll();
        setState(() => _isAudio = false);
        
        if (widget.m3uData.playList?.isEmpty ?? true) {
            LogUtil.e('播放列表无效');
            setState(() => toastString = S.current.getDefaultError);
            return;
        }
        
        try {
            _videoMap = widget.m3uData;
            String? userInfo = SpUtil.getString('user_all_info');
            LogUtil.i('加载用户地理信息: $userInfo');
            await _initializeZhConverters();
            await _sortVideoMap(_videoMap!, userInfo);
            _sourceIndex = 0;
            await _handlePlaylist();
        } catch (e, stackTrace) {
            LogUtil.e('加载播放列表失败: $e');
            setState(() => toastString = S.current.parseError);
        }
    }

    // 处理播放列表并选择首个频道
    Future<void> _handlePlaylist() async {
        if (_videoMap?.playList?.isNotEmpty ?? false) {
            _currentChannel = _getChannelFromPlaylist(_videoMap!.playList!);
            
            if (_currentChannel != null) {
                if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
                _updatePlayState(retryCount: 0);
                _timeoutActive = false;
                _switchAttemptCount = 0;
                if (!_isSwitchingChannel && !_isRetrying && !_isParsing) {
                    await _queueSwitchChannel(_currentChannel, _sourceIndex);
                } else {
                    LogUtil.i('用户操作中，跳过初始化切换');
                }
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

    // 从播放列表提取首个可用频道
    PlayModel? _getChannelFromPlaylist(Map<String, dynamic> playList) {
        try {
            for (final categoryEntry in playList.entries) {
                final categoryData = categoryEntry.value;
                
                if (categoryData is Map<String, Map<String, PlayModel>>) {
                    for (final groupEntry in categoryData.entries) {
                        final channelMap = groupEntry.value;
                        for (final channel in channelMap.values) {
                            if (channel.urls?.isNotEmpty ?? false) return channel;
                        }
                    }
                } else if (categoryData is Map<String, PlayModel>) {
                    for (final channel in categoryData.values) {
                        if (channel.urls?.isNotEmpty ?? false) return channel;
                    }
                }
            }
        } catch (e, stackTrace) {
            LogUtil.e('提取频道失败: $e');
        }
        return null;
    }

    // 提取收藏列表
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

    // 切换频道收藏状态
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
            favoriteList[Config.myFavoriteKey]![groupName] ??= {};
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
                LogUtil.i('更新收藏列表');
                if (mounted) setState(() => _drawerRefreshKey = ValueKey(DateTime.now().millisecondsSinceEpoch));
            } catch (error) {
                CustomSnackBar.showSnackBar(context, S.current.newfavoriteerror, duration: Duration(seconds: snackBarDurationSeconds));
                LogUtil.e('保存收藏失败: $error');
            }
        }
    }

    // 解析播放数据
    Future<void> _parseData() async {
        try {
            if (_videoMap?.playList?.isEmpty ?? true) {
                LogUtil.e('播放列表无效');
                setState(() => toastString = S.current.getDefaultError);
                return;
            }
            _sourceIndex = 0;
            _switchAttemptCount = 0;
            await _handlePlaylist();
        } catch (e, stackTrace) {
            LogUtil.e('处理播放列表失败: $e');
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
                adManager: _adManager,
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
                            adManager: _adManager,
                            showPlayIcon: _showPlayIcon,
                            showPauseIconFromListener: _showPauseIconFromListener,
                            isHls: _isHls,
                            onUserPaused: _handleUserPaused,
                            onRetry: _handleRetry,
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
                                            showPlayIcon: _showPlayIcon,
                                            showPauseIconFromListener: _showPauseIconFromListener,
                                            isHls: _isHls,
                                            onUserPaused: _handleUserPaused,
                                            onRetry: _handleRetry,
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
