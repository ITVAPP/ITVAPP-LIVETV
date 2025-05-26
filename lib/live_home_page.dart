import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider/theme_provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:better_player_plus/better_player_plus.dart';
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

// 【核心播放管理器】- 统一管理所有播放相关逻辑
class CorePlayerManager {
    // 播放配置常量
    static const int defaultMaxRetries = 1;
    static const int defaultTimeoutSeconds = 38;
    static const int retryDelaySeconds = 2;
    static const int hlsSwitchThresholdSeconds = 3;
    static const int nonHlsPreloadThresholdSeconds = 20;
    static const int nonHlsSwitchThresholdSeconds = 3;
    static const double defaultAspectRatio = 1.78;
    static const int m3u8ConnectTimeoutSeconds = 5;
    static const int m3u8ReceiveTimeoutSeconds = 10;
    
    // 创建播放器控制器
    static BetterPlayerController? createController({
        required Function(BetterPlayerEvent) eventListener,
        required bool isHls,
    }) {
        final configuration = BetterPlayerConfig.createPlayerConfig(
            eventListener: eventListener,
            isHls: isHls
        );
        return BetterPlayerController(configuration);
    }
    
    // 【合并】统一播放源方法
    static Future<void> playSource({
        required BetterPlayerController controller,
        required String url,
        required bool isHls,
        String? channelTitle,
        String? channelLogo,
        bool preloadOnly = false,
    }) async {
        final dataSource = BetterPlayerConfig.createDataSource(
            url: url,
            isHls: isHls,
            channelTitle: channelTitle,
            channelLogo: channelLogo,
        );
        
        if (preloadOnly) {
            await controller.preCache(dataSource);
            LogUtil.i('预缓存数据源完成: $url');
        } else {
            await controller.setupDataSource(dataSource);
            await controller.play();
            LogUtil.i('播放源完成: $url');
        }
    }
    
    // 【核心】统一播放流程 - 合并原来的4个方法
    static Future<String> executePlayback({
        required String originalUrl,
        required CancelToken cancelToken,
        String? channelTitle,
    }) async {
        StreamUrl? streamUrl;
        try {
            LogUtil.i('执行播放任务: $originalUrl');
            
            // 创建StreamUrl实例并解析地址
            streamUrl = StreamUrl(originalUrl, cancelToken: cancelToken);
            String parsedUrl = await streamUrl.getStreamUrl();
            
            // 检查解析结果
            if (parsedUrl == 'ERROR') {
                throw Exception('地址解析失败: $originalUrl');
            }
            
            LogUtil.i('地址解析成功: $parsedUrl');
            return parsedUrl;
            
        } catch (e, stackTrace) {
            LogUtil.e('播放任务执行失败: $e\n$stackTrace');
            await safeDisposeResource(streamUrl);
            rethrow;
        }
    }
    
    // 【统一】资源释放方法
    static Future<void> safeDisposeResource(dynamic resource) async {
        if (resource == null) return;
        
        try {
            if (resource is BetterPlayerController) {
                if (resource.isPlaying() ?? false) {
                    await resource.pause();
                    await resource.setVolume(0);
                }
                
                if (resource.videoPlayerController != null) {
                    await resource.videoPlayerController!.dispose();
                }
                resource.dispose();
                LogUtil.i('播放器控制器释放完成');
            } else if (resource is StreamUrl) {
                await resource.dispose();
                LogUtil.i('StreamUrl实例释放完成');
            }
        } catch (e) {
            LogUtil.e('释放资源失败: $e');
        }
    }
    
    // URL类型判断统一方法
    static bool isHlsStream(String? url) {
        if (url?.isEmpty ?? true) return false;
        
        final lowercaseUrl = url!.toLowerCase();
        if (lowercaseUrl.contains('.m3u8')) return true;
        
        final nonHlsFormats = [
            '.mp4', '.mkv', '.avi', '.wmv', '.mov', '.webm', '.mpeg', '.mpg', '.rm', '.rmvb',
            '.mp3', '.wav', '.aac', '.wma', '.ogg', '.m4a', '.flac', '.flv', 'rtmp:'
        ];
        return !nonHlsFormats.any(lowercaseUrl.contains);
    }
}

// 【简化】预定义状态组合
class PlayerStates {
    static const Map<String, dynamic> playing = {
        'playing': true,
        'buffering': false,
        'showPlay': false,
        'showPause': false,
    };
    
    static const Map<String, dynamic> error = {
        'playing': false,
        'buffering': false,
        'retrying': false,
        'switching': false,
    };
    
    static const Map<String, dynamic> loading = {
        'playing': false,
        'buffering': false,
        'showPlay': false,
        'showPause': false,
        'userPaused': false,
        'switching': true,
    };
    
    static const Map<String, dynamic> resetOperations = {
        'retrying': false,
        'parsing': false,
        'switching': false,
    };
    
    static Map<String, dynamic> retrying(int count) => {
        'retrying': true,
        'retryCount': count,
        'buffering': false,
        'showPlay': false,
        'showPause': false,
        'userPaused': false,
    };
}

// 主页面，管理播放和频道切换
class LiveHomePage extends StatefulWidget {
    final PlaylistModel m3uData; // 播放列表数据
    const LiveHomePage({super.key, required this.m3uData});

    @override
    State<LiveHomePage> createState() => _LiveHomePageState();
}

// 计时器类型枚举
enum TimerType {
    retry,        // 重试计时
    m3u8Check,    // m3u8检查
    playDuration, // 播放时长
    timeout,      // 超时检测
    bufferingCheck, // 缓冲检查
    switchTimeout,  // 切换超时检测
    stateCheck,     // 状态检查
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
    // 【精简】常量统一使用CorePlayerManager中的定义，移除重复
    static const int initialProgressDelaySeconds = 60;
    static const int cleanupDelayMilliseconds = 500;
    static const int snackBarDurationSeconds = 5;
    static const int m3u8InvalidConfirmDelaySeconds = 1;
    static const int m3u8CheckIntervalSeconds = 10;
    static const int reparseMinIntervalMilliseconds = 10000;
    static const int maxSwitchAttempts = 3;

    String? _preCachedUrl; // 预缓存播放地址
    bool _isParsing = false; // 是否正在解析
    bool _isRetrying = false; // 是否正在重试
    bool isBuffering = false; // 是否正在缓冲
    bool isPlaying = false; // 是否正在播放
    bool _isUserPaused = false; // 用户是否暂停
    bool _isDisposing = false; // 是否正在释放资源
    bool _isSwitchingChannel = false; // 是否正在切换频道
    bool _shouldUpdateAspectRatio = true; // 是否需要更新宽高比
    bool _progressEnabled = false; // 是否启用进度检查
    bool _isHls = false; // 是否为HLS流
    bool _isAudio = false; // 是否为音频流
    bool _showPlayIcon = false; // 是否显示播放图标
    int? _lastParseTime; // 上次解析时间戳
    String toastString = S.current.loading; // 当前提示信息
    PlaylistModel? _videoMap; // 视频播放列表
    PlayModel? _currentChannel; // 当前播放频道
    int _sourceIndex = 0; // 当前源索引
    BetterPlayerController? _playerController; // 播放器控制器
    double aspectRatio = CorePlayerManager.defaultAspectRatio; // 当前宽高比
    bool _drawerIsOpen = false; // 抽屉菜单是否打开
    int _retryCount = 0; // 当前重试次数
    bool _timeoutActive = false; // 超时检测是否激活
    StreamUrl? _streamUrl; // 当前流地址实例
    StreamUrl? _preCacheStreamUrl; // 预缓存流地址实例
    String? _currentPlayUrl; // 当前播放地址
    String? _originalUrl; // 原始播放地址
    Map<String, Map<String, Map<String, PlayModel>>> favoriteList = {
        Config.myFavoriteKey: <String, Map<String, PlayModel>>{}, // 收藏列表
    };
    ValueKey<int>? _drawerRefreshKey; // 抽屉刷新键
    final TrafficAnalytics _trafficAnalytics = TrafficAnalytics(); // 流量分析实例
    late AdManager _adManager; // 广告管理实例
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

    // 判断是否为音频流
    bool _checkIsAudioStream(String? url) => !Config.videoPlayMode;

    // 更新播放地址并判断流类型
    void _updatePlayUrl(String newUrl) {
        _currentPlayUrl = newUrl;
        _isHls = CorePlayerManager.isHlsStream(_currentPlayUrl);
    }

    // 【简化】统一状态更新方法 - 替代多个重复的状态更新方法
    void _updateState({
        bool? playing, bool? buffering, String? message, bool? showPlay, bool? showPause,
        bool? userPaused, bool? switching, bool? retrying, bool? parsing, int? sourceIndex, int? retryCount,
        Map<String, dynamic>? stateMap,
    }) {
        if (!mounted) return;
        
        setState(() {
            if (stateMap != null) {
                // 批量更新状态
                if (stateMap.containsKey('playing')) isPlaying = stateMap['playing'];
                if (stateMap.containsKey('buffering')) isBuffering = stateMap['buffering'];
                if (stateMap.containsKey('message')) toastString = stateMap['message'];
                if (stateMap.containsKey('showPlay')) _showPlayIcon = stateMap['showPlay'];
                if (stateMap.containsKey('showPause')) _showPauseIconFromListener = stateMap['showPause'];
                if (stateMap.containsKey('userPaused')) _isUserPaused = stateMap['userPaused'];
                if (stateMap.containsKey('switching')) _isSwitchingChannel = stateMap['switching'];
                if (stateMap.containsKey('retrying')) _isRetrying = stateMap['retrying'];
                if (stateMap.containsKey('parsing')) _isParsing = stateMap['parsing'];
                if (stateMap.containsKey('sourceIndex')) _sourceIndex = stateMap['sourceIndex'];
                if (stateMap.containsKey('retryCount')) _retryCount = stateMap['retryCount'];
            } else {
                // 单个更新状态
                if (playing != null) isPlaying = playing;
                if (buffering != null) isBuffering = buffering;
                if (message != null) toastString = message;
                if (showPlay != null) _showPlayIcon = showPlay;
                if (showPause != null) _showPauseIconFromListener = showPause;
                if (userPaused != null) _isUserPaused = userPaused;
                if (switching != null) _isSwitchingChannel = switching;
                if (retrying != null) _isRetrying = retrying;
                if (parsing != null) _isParsing = parsing;
                if (sourceIndex != null) _sourceIndex = sourceIndex;
                if (retryCount != null) _retryCount = retryCount;
            }
        });
    }

    // 【简化】通用状态检查方法 - 合并多个重复的检查方法
    bool _canPerformOperation(String operationName, {
        bool checkRetrying = true, 
        bool checkSwitching = true, 
        bool checkDisposing = true, 
        bool checkParsing = true,
        bool? customCondition,
        VoidCallback? onFailed,
    }) {
        if (!mounted) {
            onFailed?.call();
            return false;
        }
        
        List<String> blockers = [];
        if (checkDisposing && _isDisposing) blockers.add('正在释放资源');
        if (checkRetrying && _isRetrying) blockers.add('正在重试');
        if (checkSwitching && _isSwitchingChannel) blockers.add('正在切换频道');
        if (checkParsing && _isParsing) blockers.add('正在解析');
        if (customCondition == false) blockers.add('自定义条件不满足');
        
        if (blockers.isNotEmpty) {
            LogUtil.i('$operationName 被阻止: ${blockers.join(", ")}');
            onFailed?.call();
            return false;
        }
        return true;
    }

    // 启动状态检查定时器
    void _startStateCheckTimer() {
        LogUtil.i('启动状态检查定时器，3秒后检查异常状态');
        _timerManager.startTimer(TimerType.stateCheck, Duration(seconds: 3), () {
            if (!_canPerformOperation('状态检查', 
                checkSwitching: false, 
                checkParsing: false,
                onFailed: () => LogUtil.i('组件已销毁，取消状态检查'),
            )) return;
            _checkAndFixStuckStates();
        });
    }

    // 检查并修复卡住的状态
    void _checkAndFixStuckStates() {
        List<String> stuckStates = [];
        
        if (_isDisposing) stuckStates.add('disposing');
        if (_isParsing) stuckStates.add('parsing');
        if (_isRetrying && _retryCount > 0) stuckStates.add('retrying');
        if (_isSwitchingChannel) stuckStates.add('switching');
        
        if (stuckStates.isEmpty) {
            LogUtil.i('状态检查完成，所有状态正常');
            return;
        }
        
        LogUtil.e('检测到状态异常: [${stuckStates.join(", ")}]，执行强制恢复');
        
        // 重置异常状态
        _updateState(stateMap: {
            'parsing': false,
            'retrying': false,
            'switching': false,
            'retryCount': 0,
        });
        _isDisposing = false;
        
        // 取消相关定时器
        _timerManager.cancelTimer(TimerType.timeout);
        _timerManager.cancelTimer(TimerType.switchTimeout);
        
        // 处理待切换请求或重新播放
        if (_pendingSwitch != null) {
            LogUtil.i('状态恢复后处理待切换请求');
            _processPendingSwitch();
        } else if (_currentChannel != null) {
            LogUtil.i('状态恢复后重新播放当前频道');
            Future.microtask(() => _playVideo());
        }
    }

    // 清理预缓存资源
    Future<void> _cleanupPreCache() async {
        _preCachedUrl = null;
        if (_preCacheStreamUrl != null) {
            await CorePlayerManager.safeDisposeResource(_preCacheStreamUrl);
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
            await _cleanupPreCache();
            await _reparseAndSwitch();
            return;
        }
        
        try {
            _updateState(stateMap: PlayerStates.loading);
            
            await CorePlayerManager.playSource(
                controller: _playerController!,
                url: _preCachedUrl!,
                isHls: CorePlayerManager.isHlsStream(_preCachedUrl),
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
                preloadOnly: true,
            );
            
            await CorePlayerManager.playSource(
                controller: _playerController!,
                url: _preCachedUrl!,
                isHls: CorePlayerManager.isHlsStream(_preCachedUrl),
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
            );
            
            _startPlayDurationTimer();
            _updatePlayUrl(_preCachedUrl!);
            _updateState(stateMap: {...PlayerStates.playing, 'switching': false});
            _switchAttemptCount = 0;
            LogUtil.i('$logDescription: 切换预缓存地址成功: $_preCachedUrl');
        } catch (e, stackTrace) {
            LogUtil.e('$logDescription: 切换预缓存地址失败: $e');
            _retryPlayback();
        } finally {
            _updateState(switching: false);
            _progressEnabled = false;
            await _cleanupPreCache();
        }
    }

    // 【核心重构】统一播放流程 - 合并原来的4个方法
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
        
        _updateState(stateMap: {
            ...PlayerStates.loading,
            'message': '${_currentChannel!.title} - $sourceName  ${S.current.loading}',
        });
        _startPlaybackTimeout();
        
        try {
            // 播放广告
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
            
            // 释放旧资源
            if (_playerController != null) {
                await _releaseAllResources(isDisposing: false);
            }
            
            // 【合并】解析播放地址、设置播放器、开始播放
            String url = _currentChannel!.urls![_sourceIndex].toString();
            _originalUrl = url;
            
            await CorePlayerManager.safeDisposeResource(_streamUrl);
            
            // 取消旧任务并创建新的 CancelToken
            _currentCancelToken.cancel();
            _currentCancelToken = CancelToken();
            
            // 执行播放任务并解析地址
            String parsedUrl = await CorePlayerManager.executePlayback(
                originalUrl: url,
                cancelToken: _currentCancelToken,
                channelTitle: _currentChannel?.title,
            );
            
            _streamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
            _updatePlayUrl(parsedUrl);
            bool isAudio = _checkIsAudioStream(null);
            setState(() => _isAudio = isAudio);
            LogUtil.i('播放信息: URL=$parsedUrl, 音频模式=$isAudio, HLS=$_isHls');
            
            // 创建并设置播放器控制器
            _playerController = CorePlayerManager.createController(
                eventListener: _videoListener,
                isHls: _isHls,
            );
            
            await CorePlayerManager.playSource(
                controller: _playerController!,
                url: _currentPlayUrl!,
                isHls: _isHls,
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
            );
            
            if (mounted) setState(() {});
            
            // 开始播放
            await _playerController?.play();
            _timeoutActive = false;
            _timerManager.cancelTimer(TimerType.timeout);
            
            _switchAttemptCount = 0;
        } catch (e, stackTrace) {
            LogUtil.e('播放失败: $e');
            await CorePlayerManager.safeDisposeResource(_streamUrl);
            _streamUrl = null;
            _switchAttemptCount++;
            
            if (_switchAttemptCount <= maxSwitchAttempts) {
                _handleSourceSwitching();
            } else {
                _switchAttemptCount = 0;
                _updateState(stateMap: {
                    ...PlayerStates.error,
                    'message': S.current.playError,
                });
            }
        } finally {
            if (mounted) {
                _updateState(switching: false);
                _timerManager.cancelTimer(TimerType.switchTimeout);
                _processPendingSwitch();
            }
        }
    }

    // 【简化】源索引修正
    ({int safeIndex, bool hasValidSources}) _fixSourceIndex(PlayModel? channel, int currentIndex) {
        if (channel?.urls?.isEmpty ?? true) {
            LogUtil.e('频道无可用源');
            return (safeIndex: 0, hasValidSources: false);
        }
        
        final safeIndex = (currentIndex < 0 || currentIndex >= channel!.urls!.length) ? 0 : currentIndex;
        return (safeIndex: safeIndex, hasValidSources: true);
    }

    // 验证当前源索引有效性
    bool _isSourceIndexValid() {
        final result = _fixSourceIndex(_currentChannel, _sourceIndex);
        _sourceIndex = result.safeIndex;
        
        if (!result.hasValidSources) {
            _updateState(stateMap: {
                ...PlayerStates.error,
                'message': S.current.playError,
            });
            return false;
        }
        return true;
    }

    // 启动播放超时检测
    void _startPlaybackTimeout() {
        _timeoutActive = true;
        _timerManager.startTimer(TimerType.timeout, Duration(seconds: CorePlayerManager.defaultTimeoutSeconds), () {
            if (!_canPerformOperation('超时检查', 
                customCondition: _timeoutActive,
                onFailed: () => _timeoutActive = false,
            )) return;
            
            if (_playerController?.isPlaying() != true) {
                _handleSourceSwitching();
                _timeoutActive = false;
            }
        });
    }

    // 处理待执行的频道切换请求
    void _processPendingSwitch() {
        if (_pendingSwitch == null || !_canPerformOperation('处理待切换请求')) {
            if (_pendingSwitch != null) {
                LogUtil.i('切换请求冲突，检查状态');
                _checkAndFixStuckStates();
            }
            return;
        }
        
        final nextRequest = _pendingSwitch!;
        _pendingSwitch = null;
        _currentChannel = nextRequest.channel;
        _sourceIndex = nextRequest.sourceIndex;
        
        Future.microtask(() => _playVideo());
    }

    // 【简化】队列化切换频道
    Future<void> _queueSwitchChannel(PlayModel? channel, int sourceIndex) async {
        if (channel == null) {
            LogUtil.e('切换频道失败: 频道为空');
            return;
        }
        
        final result = _fixSourceIndex(channel, sourceIndex);
        
        _debounceTimer?.cancel();
        _debounceTimer = Timer(Duration(milliseconds: cleanupDelayMilliseconds), () {
            if (!mounted) return;
            _pendingSwitch = SwitchRequest(channel, result.safeIndex);
            
            if (!_isSwitchingChannel) {
                _processPendingSwitch();
            } else {
                _timerManager.startTimer(TimerType.switchTimeout, Duration(seconds: CorePlayerManager.m3u8ConnectTimeoutSeconds), () {
                    if (mounted) {
                        LogUtil.e('强制处理切换频道');
                        _updateState(switching: false);
                        _processPendingSwitch();
                    }
                });
            }
        });
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
                    final newAspectRatio = _playerController?.videoPlayerController?.value.aspectRatio ?? CorePlayerManager.defaultAspectRatio;
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
                _updateState(buffering: true, message: S.current.loading);
                break;
                
            case BetterPlayerEventType.bufferingEnd:
                _updateState(
                    buffering: false,
                    message: 'HIDE_CONTAINER',
                    showPause: _isUserPaused ? false : _showPauseIconFromListener,
                );
                _timerManager.cancelTimer(TimerType.bufferingCheck);
                break;
                
            case BetterPlayerEventType.play:
                if (!isPlaying) {
                    _updateState(stateMap: PlayerStates.playing);
                    _updateState(message: isBuffering ? toastString : 'HIDE_CONTAINER', userPaused: false);
                    _timerManager.cancelTimer(TimerType.bufferingCheck);
                    if (!_timerManager.isActive(TimerType.playDuration)) {
                        _startPlayDurationTimer();
                    }
                }
                _adManager.onVideoStartPlaying();
                break;
                
            case BetterPlayerEventType.pause:
                if (isPlaying) {
                    _updateState(
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
                        if (_preCachedUrl != null && remainingTime.inSeconds <= CorePlayerManager.hlsSwitchThresholdSeconds) {
                            await _switchToPreCachedUrl('HLS剩余时间触发');
                        }
                    } else {
                        if (remainingTime.inSeconds <= CorePlayerManager.nonHlsPreloadThresholdSeconds) {
                            final nextUrl = _getNextVideoUrl();
                            if (nextUrl != null && nextUrl != _preCachedUrl) {
                                LogUtil.i('非HLS预加载下一源: $nextUrl');
                                _preloadNextVideo(nextUrl);
                            }
                        }
                        if (remainingTime.inSeconds <= CorePlayerManager.nonHlsSwitchThresholdSeconds && _preCachedUrl != null) {
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

    // 启动m3u8检查定时器
    void _startM3u8Monitor() {
        if (!_isHls) return;
        
        _timerManager.cancelTimer(TimerType.m3u8Check);
        
        _timerManager.startPeriodicTimer(
            TimerType.m3u8Check,
            const Duration(seconds: m3u8CheckIntervalSeconds),
            (_) async {
                // 基本状态检查
                if (!mounted || !_isHls || !isPlaying || _isDisposing || _isParsing) {
                    return;
                }
                
                // 检查m3u8有效性
                if (_currentPlayUrl?.isNotEmpty == true) {
                    try {
                        final content = await HttpUtil().getRequest<String>(
                            _currentPlayUrl!,
                            options: Options(
                                extra: {
                                    'connectTimeout': const Duration(seconds: m3u8ConnectTimeoutSeconds),
                                    'receiveTimeout': const Duration(seconds: m3u8ReceiveTimeoutSeconds),
                                },
                            ),
                            retryCount: 1,
                        );
                        
                        // 简单的内容有效性检查
                        bool isValid = content?.isNotEmpty == true && 
                                      (content!.contains('.ts') || 
                                       content.contains('#EXTINF') || 
                                       content.contains('#EXT-X-STREAM-INF'));
                        
                        if (!isValid) {
                            _m3u8InvalidCount++;
                            LogUtil.i('m3u8内容无效，失效次数: $_m3u8InvalidCount');
                            
                            // 连续2次失效就重新解析
                            if (_m3u8InvalidCount >= 2) {
                                LogUtil.i('m3u8连续失效，重新解析');
                                _m3u8InvalidCount = 0;
                                await _reparseAndSwitch();
                            }
                        } else {
                            _m3u8InvalidCount = 0; // 重置计数
                        }
                        
                    } catch (e) {
                        LogUtil.e('m3u8检查失败: $e');
                        _m3u8InvalidCount++;
                        if (_m3u8InvalidCount >= 3) {
                            LogUtil.i('m3u8检查异常过多，重新解析');
                            _m3u8InvalidCount = 0;
                            await _reparseAndSwitch();
                        }
                    }
                }
            },
        );
    }

    // 启动播放时长检查定时器
    void _startPlayDurationTimer() {
        _timerManager.cancelTimer(TimerType.playDuration);
        _timerManager.startTimer(TimerType.playDuration, const Duration(seconds: initialProgressDelaySeconds), () {
            if (!_canPerformOperation('播放时长检查', checkParsing: false)) return;
            
            LogUtil.i('播放时长检查启动');
            if (_isHls) {
                if (_originalUrl?.toLowerCase().contains('timelimit') ?? false) {
                    _startM3u8Monitor();
                }
            } else {
                if (_getNextVideoUrl() != null) {
                    _progressEnabled = true;
                    LogUtil.i('非HLS流启用progress监听');
                }
            }
            _retryCount = 0;
        });
    }

    // 预加载下一视频源
    Future<void> _preloadNextVideo(String url) async {
        if (!_canPerformOperation('预加载视频')) return;
        
        if (_playerController == null) {
            LogUtil.e('预加载失败: 播放器控制器为空');
            return;
        }
        
        if (_preCachedUrl == url) {
            LogUtil.i('URL已预缓存: $url');
            return;
        }
        
        if (_preCachedUrl != null) {
            await _cleanupPreCache();
        }
        
        try {
            LogUtil.i('开始预加载: $url');
            
            // 取消旧任务并创建新的 CancelToken
            _preloadCancelToken.cancel();
            _preloadCancelToken = CancelToken();
            
            String parsedUrl = await CorePlayerManager.executePlayback(
                originalUrl: url,
                cancelToken: _preloadCancelToken,
                channelTitle: _currentChannel?.title,
            );
            
            if (_playerController == null) {
                LogUtil.e('预缓存失败: 播放器控制器已释放');
                return;
            }
            
            _preCacheStreamUrl = StreamUrl(url, cancelToken: _preloadCancelToken);
            _preCachedUrl = parsedUrl;
            
            await CorePlayerManager.playSource(
                controller: _playerController!,
                url: parsedUrl,
                isHls: CorePlayerManager.isHlsStream(parsedUrl),
                channelTitle: _currentChannel?.title,
                channelLogo: _getChannelLogo(),
                preloadOnly: true,
            );
            
            LogUtil.i('预缓存完成: $parsedUrl');
            
        } catch (e, stackTrace) {
            LogUtil.e('预加载失败: $e');
            _preCachedUrl = null;
            
            if (_preCacheStreamUrl != null) {
                await _cleanupPreCache();
            }
            
            if (_playerController != null) {
                try {
                    await _playerController!.clearCache();
                } catch (clearError) {
                    LogUtil.e('清除缓存失败: $clearError');
                }
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

    // 重试播放
    void _retryPlayback({bool resetRetryCount = false}) {
        if (!_canPerformOperation('重试播放') || _isParsing) {
            LogUtil.i('重试阻止: ${_isParsing ? "正在解析" : "状态冲突"}');
            return;
        }
        
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.cancelTimer(TimerType.timeout);
        
        if (resetRetryCount) {
            _updateState(retryCount: 0);
        }
        
        if (_retryCount < CorePlayerManager.defaultMaxRetries) {
            _updateState(stateMap: {
                ...PlayerStates.retrying(_retryCount + 1),
                'message': S.current.retryplay,
            });
            LogUtil.i('重试播放: 第$_retryCount次');
            
            _timerManager.startTimer(TimerType.retry, const Duration(seconds: CorePlayerManager.retryDelaySeconds), () async {
                if (!_canPerformOperation('执行重试', onFailed: () => _updateState(retrying: false))) return;
                
                await _playVideo(isRetry: true);
                if (mounted) _updateState(retrying: false);
            });
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
        
        _updateState(
            sourceIndex: _sourceIndex + 1,
            buffering: false,
            message: S.current.lineToast(_sourceIndex + 1, _currentChannel?.title ?? ''),
        );
        _updateState(stateMap: PlayerStates.resetOperations);
        _preCachedUrl = null;
        LogUtil.i('切换下一源: $nextUrl');
        _startNewSourceTimer();
    }

    // 处理无更多源的情况
    Future<void> _handleNoMoreSources() async {
        _updateState(stateMap: {
            ...PlayerStates.error,
            'message': S.current.playError,
            'sourceIndex': 0,
        });
        await _releaseAllResources(isDisposing: false);
        LogUtil.i('播放结束，无更多源');
        _switchAttemptCount = 0;
    }

    // 启动新源播放定时器
    void _startNewSourceTimer() {
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.startTimer(TimerType.retry, const Duration(seconds: CorePlayerManager.retryDelaySeconds), () async {
            if (!_canPerformOperation('启动新源', checkParsing: false)) return;
            await _playVideo(isSourceSwitch: true);
        });
    }

    // 【统一】释放所有资源
    Future<void> _releaseAllResources({bool isDisposing = false}) async {
        if (_isDisposing && !isDisposing) {
            LogUtil.i('资源正在释放中，跳过重复调用');
            return;
        }
        
        _isDisposing = true;
        _timerManager.cancelAll();
        
        // 取消所有 CancelToken
        _currentCancelToken.cancel();
        _preloadCancelToken.cancel();
        
        try {
            // 释放播放器
            if (_playerController != null) {
                final controller = _playerController!;
                _playerController = null;
                
                try {
                    controller.removeEventsListener(_videoListener);
                    await CorePlayerManager.safeDisposeResource(controller);
                } catch (e) {
                    LogUtil.e('释放播放器资源失败: $e');
                }
            }
            
            // 释放StreamUrl资源
            final currentStreamUrl = _streamUrl;
            final preStreamUrl = _preCacheStreamUrl;
            
            _streamUrl = null;
            _preCacheStreamUrl = null;
            
            if (currentStreamUrl != null) {
                await CorePlayerManager.safeDisposeResource(currentStreamUrl);
            }
            
            if (preStreamUrl != null && preStreamUrl != currentStreamUrl) {
                await CorePlayerManager.safeDisposeResource(preStreamUrl);
            }
            
            // 处理广告管理器
            if (isDisposing) {
                _adManager.dispose();
            } else {
                _adManager.reset(rescheduleAds: false, preserveTimers: true);
            }
            
            // 重置状态
            if (mounted && !isDisposing) {
                _updateState(stateMap: {
                    ...PlayerStates.resetOperations,
                    'playing': false,
                    'buffering': false,
                    'showPlay': false,
                    'showPause': false,
                    'userPaused': false,
                });
                _progressEnabled = false;
                _preCachedUrl = null;
                _lastParseTime = null;
                _currentPlayUrl = null;
                _originalUrl = null;
                _m3u8InvalidCount = 0;
            }
            
            await Future.delayed(const Duration(milliseconds: cleanupDelayMilliseconds));
            LogUtil.i('资源释放完成');
            
        } catch (e, stackTrace) {
            LogUtil.e('释放资源失败: $e\n调用栈: $stackTrace');
        } finally {
            _isDisposing = false;
            
            // 处理待切换请求
            if (_pendingSwitch != null && mounted) {
                final pendingRequest = _pendingSwitch;
                LogUtil.i('资源释放完成，处理待切换请求: ${pendingRequest!.channel?.title}');
                Future.microtask(() {
                    if (mounted && !_isDisposing && _pendingSwitch == pendingRequest) {
                        _processPendingSwitch();
                    } else {
                        LogUtil.i('待切换请求已过期或状态不允许处理');
                    }
                });
            }
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
                _timerManager.startTimer(TimerType.retry, Duration(milliseconds: (reparseMinIntervalMilliseconds - timeSinceLastParse).toInt()), () {
                    if (mounted) _reparseAndSwitch(force: true);
                });
                return;
            }
        }
        
        _timerManager.cancelTimer(TimerType.retry);
        _timerManager.cancelTimer(TimerType.m3u8Check);
        _updateState(parsing: true);
        
        try {
            if (_currentChannel?.urls == null || _sourceIndex >= _currentChannel!.urls!.length) {
                LogUtil.e('频道信息无效');
                throw Exception('无效的频道信息');
            }
            
            _updateState(switching: true);
            String url = _currentChannel!.urls![_sourceIndex].toString();
            LogUtil.i('重新解析地址: $url');
            
            await CorePlayerManager.safeDisposeResource(_streamUrl);
            _streamUrl = null;
            
            // 取消旧任务并创建新的 CancelToken
            _currentCancelToken.cancel();
            _currentCancelToken = CancelToken();
            
            String parsedUrl = await CorePlayerManager.executePlayback(
                originalUrl: url,
                cancelToken: _currentCancelToken,
                channelTitle: _currentChannel?.title,
            );
            
            if (parsedUrl == _currentPlayUrl) {
                LogUtil.i('新地址与当前地址相同，无需切换');
                _updateState(parsing: false, switching: false);
                return;
            }
            
            _streamUrl = StreamUrl(url, cancelToken: _currentCancelToken);
            _preCachedUrl = parsedUrl;
            LogUtil.i('预缓存地址: $_preCachedUrl');
            
            if (_playerController != null) {
                if (_isDisposing) {
                    LogUtil.i('解析中断，退出');
                    _preCachedUrl = null;
                    _updateState(parsing: false, switching: false);
                    return;
                }
                
                await CorePlayerManager.playSource(
                    controller: _playerController!,
                    url: parsedUrl,
                    isHls: CorePlayerManager.isHlsStream(parsedUrl),
                    channelTitle: _currentChannel?.title,
                    channelLogo: _getChannelLogo(),
                    preloadOnly: true,
                );
                
                if (_isDisposing) {
                    LogUtil.i('预加载中断，退出');
                    _preCachedUrl = null;
                    _updateState(parsing: false, switching: false);
                    return;
                }
                
                _progressEnabled = true;
                _lastParseTime = now;
                LogUtil.i('预缓存完成，等待切换');
            } else {
                LogUtil.i('播放器控制器为空，切换下一源');
                _handleSourceSwitching();
            }
            _updateState(switching: false);
        } catch (e, stackTrace) {
            LogUtil.e('重新解析失败: $e');
            _preCachedUrl = null;
            _handleSourceSwitching();
        } finally {
            if (mounted) {
                _updateState(parsing: false);
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
            _updateState(
                buffering: false,
                message: S.current.loading,
            );
            _updateState(stateMap: PlayerStates.resetOperations);
            
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
            _updateState(message: S.current.playError);
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
            _updateState(sourceIndex: selectedIndex);
            _updateState(stateMap: PlayerStates.resetOperations);
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
    void _handleUserPaused() => _updateState(userPaused: true);

    // 处理重试事件
    void _handleRetry() => _retryPlayback(resetRetryCount: true);

    @override
    void initState() {
        super.initState();
        
        // 初始化 CancelToken
        _currentCancelToken = CancelToken();
        _preloadCancelToken = CancelToken();
        
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
        _updateState(stateMap: PlayerStates.resetOperations);
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
            _currentChannel = _getFirstChannel(_videoMap!.playList!);
            
            if (_currentChannel != null) {
                if (Config.Analytics) await _sendTrafficAnalytics(context, _currentChannel!.title);
                _updateState(retryCount: 0);
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

    // 【简化】获取首个可用频道
    PlayModel? _getFirstChannel(Map<String, dynamic> playList) {
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
