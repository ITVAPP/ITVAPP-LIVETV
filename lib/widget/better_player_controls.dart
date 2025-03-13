import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

class BetterPlayerConfig {
  // 定义常量背景图片Widget
  static const _backgroundImage = Image(
    image: AssetImage('assets/images/video_bg.png'),
    fit: BoxFit.cover,
    gaplessPlayback: true,  // 防止图片加载时闪烁
    filterQuality: FilterQuality.medium,  // 优化图片质量和性能的平衡
  );

  /// 创建播放器数据源配置
  /// - [url]: 视频播放地址
  /// - [isHls]: 是否为 HLS 格式（直播流）
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
  }) {
    // 使用 HeadersConfig 生成默认 headers
    final defaultHeaders = HeadersConfig.generateHeaders(url: url);

    // 合并 defaultHeaders 和传入的 headers
    final mergedHeaders = {...defaultHeaders, ...?headers};

    // 提取公共的 BetterPlayerDataSource 配置
    final baseDataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: isHls, // 根据 URL 判断是否为直播流
      useAsmsTracks: isHls, // 启用 ASMS 音视频轨道，非 HLS 时关闭以减少资源占用
      useAsmsAudioTracks: isHls, // 同上
      useAsmsSubtitles: false, // 禁用字幕以降低播放开销
      // 配置系统通知栏行为（此处关闭通知栏播放控制）
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
      // 缓冲配置
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000, // 5 秒
        maxBufferMs: 20000, // 20 秒
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      // 缓存配置
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls, // 非 HLS 启用缓存（直播流缓存可能导致中断）
        preCacheSize: 20 * 1024 * 1024, // 预缓存大小（10MB）
        maxCacheSize: 300 * 1024 * 1024, // 缓存总大小限制（300MB）
        maxCacheFileSize: 50 * 1024 * 1024, // 单个缓存文件大小限制（50MB）
      ),
    );

    // 根据 mergedHeaders 是否为空返回实例
    return mergedHeaders.isNotEmpty
        ? BetterPlayerDataSource(
            baseDataSource.type,
            baseDataSource.url,
            liveStream: baseDataSource.liveStream,
            useAsmsTracks: baseDataSource.useAsmsTracks,
            useAsmsAudioTracks: baseDataSource.useAsmsAudioTracks,
            useAsmsSubtitles: baseDataSource.useAsmsSubtitles,
            notificationConfiguration: baseDataSource.notificationConfiguration,
            bufferingConfiguration: baseDataSource.bufferingConfiguration,
            cacheConfiguration: baseDataSource.cacheConfiguration,
            headers: mergedHeaders, // 包含 headers
          )
        : baseDataSource; // 不包含 headers，直接使用基础配置
  }

  /// 创建播放器基本配置
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 播放器内容适应模式（保持比例缩放）
      autoPlay: false, // 自动播放
      looping: isHls, // 是HLS时循环播放
      allowedScreenSleep: false, // 屏幕休眠
      autoDispose: false, // 自动释放资源
      expandToFill: true, // 填充剩余空间
      handleLifecycle: true, // 生命周期管理
      // 错误界面构建器（此处使用背景图片）
      errorBuilder: (_, __) => _backgroundImage,
      // 设置播放器占位图片
      placeholder: _backgroundImage,
      // 配置控制栏行为
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false,  // 不显示控制器
      ),
      // 全屏后允许的设备方向
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      // 事件监听器
      eventListener: eventListener,
    );
  }
}

class BetterPlayerEventHandler {
  final BetterPlayerController? Function() getPlayerController;
  final bool Function() isHls;
  final bool Function() isPlaying;
  final bool Function() isBuffering;
  final bool Function() progressEnabled;
  final String? Function() preCachedUrl;
  final Duration? Function() lastBufferedPosition;
  final int? Function() lastBufferedTime;
  final List<Map<String, dynamic>> Function() bufferedHistory;
  final bool Function() isDisposing;
  final bool Function() isSwitchingChannel;
  final bool Function() isRetrying;
  final bool Function() isParsing;
  final bool Function() isUserPaused;
  final bool Function() showPlayIcon;
  final bool Function() showPauseIconFromListener;
  final int Function() retryCount;
  final Future<void> Function(String) switchToPreCachedUrl;
  final void Function({bool resetRetryCount}) retryPlayback;
  final Future<void> Function() reparseAndSwitch;
  final void Function(String, dynamic) setState;
  final Future<void> Function(String) preloadNextVideo;
  final String? Function() getNextVideoUrl;
  final void Function() startPlayDurationTimer;
  final void Function(double) onAspectRatioUpdated;
  final void Function() handleNoMoreSources;
  final bool Function() mounted;

  BetterPlayerEventHandler({
    required this.getPlayerController,
    required this.isHls,
    required this.isPlaying,
    required this.isBuffering,
    required this.progressEnabled,
    required this.preCachedUrl,
    required this.lastBufferedPosition,
    required this.lastBufferedTime,
    required this.bufferedHistory,
    required this.isDisposing,
    required this.isSwitchingChannel,
    required this.isRetrying,
    required this.isParsing,
    required this.isUserPaused,
    required this.showPlayIcon,
    required this.showPauseIconFromListener,
    required this.retryCount,
    required this.switchToPreCachedUrl,
    required this.retryPlayback,
    required this.reparseAndSwitch,
    required this.setState,
    required this.preloadNextVideo,
    required this.getNextVideoUrl,
    required this.startPlayDurationTimer,
    required this.onAspectRatioUpdated,
    required this.handleNoMoreSources,
  });

  static const int bufferHistorySize = 6;
  static const int positionIncreaseThreshold = 5;
  static const int lowBufferThresholdCount = 3;
  static const int minRemainingBufferSeconds = 8;
  static const int bufferUpdateTimeoutSeconds = 6;
  static const int hlsSwitchThresholdSeconds = 3;
  static const int nonHlsSwitchThresholdSeconds = 3;
  static const int nonHlsPreloadThresholdSeconds = 20;
  static const int bufferingStartSeconds = 15;

  Timer? _bufferingTimeoutTimer;

  void videoListener(BetterPlayerEvent event) {
    if (isDisposing() || getPlayerController() == null || !mounted()) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        final newAspectRatio = getPlayerController()?.videoPlayerController?.value.aspectRatio ?? 1.78;
        onAspectRatioUpdated(newAspectRatio);
        break;

      case BetterPlayerEventType.exception:
        LogUtil.e('播放器异常: ${event.parameters?["error"] ?? "Unknown error"}');
        if (preCachedUrl() != null) {
          switchToPreCachedUrl('异常触发');
        } else {
          retryPlayback();
        }
        break;

      case BetterPlayerEventType.bufferingStart:
        setState('isBuffering', true);
        setState('toastString', S.current.loading);
        if (isPlaying()) {
          _bufferingTimeoutTimer?.cancel();
          _bufferingTimeoutTimer = Timer(const Duration(seconds: bufferingStartSeconds), () {
            if (!isBuffering() || isRetrying() || isSwitchingChannel() || isDisposing() || isParsing()) {
              LogUtil.i('缓冲超时检查被阻止');
              return;
            }
            if (getPlayerController()?.isPlaying() != true) {
              LogUtil.e('播放中缓冲超过 $bufferingStartSeconds 秒，触发重试');
              retryPlayback(resetRetryCount: true);
            }
          });
        } else {
          LogUtil.i('初始缓冲，不启用 $bufferingStartSeconds 秒超时');
        }
        break;

      case BetterPlayerEventType.bufferingUpdate:
        if (progressEnabled() && isPlaying()) {
          final bufferedData = event.parameters?["buffered"];
          if (bufferedData != null) {
            if (bufferedData is List<dynamic> && bufferedData.isNotEmpty) {
              final lastBuffer = bufferedData.last;
              try {
                setState('lastBufferedPosition', lastBuffer.end as Duration);
                setState('lastBufferedTime', DateTime.now().millisecondsSinceEpoch);
              } catch (e) {
                LogUtil.i('无法解析缓冲对象: $lastBuffer, 错误: $e');
                setState('lastBufferedTime', DateTime.now().millisecondsSinceEpoch);
              }
            } else if (bufferedData is Duration) {
              setState('lastBufferedPosition', bufferedData);
              setState('lastBufferedTime', DateTime.now().millisecondsSinceEpoch);
              LogUtil.i('缓冲区更新: $bufferedData');
            } else {
              LogUtil.i('未知的缓冲区数据类型: $bufferedData');
              setState('lastBufferedTime', DateTime.now().millisecondsSinceEpoch);
            }
          } else {
            LogUtil.i('缓冲区数据为空');
            setState('lastBufferedTime', DateTime.now().millisecondsSinceEpoch);
          }
        }
        break;

      case BetterPlayerEventType.bufferingEnd:
        setState('isBuffering', false);
        setState('toastString', 'HIDE_CONTAINER');
        if (!isUserPaused()) setState('showPauseIconFromListener', false);
        _bufferingTimeoutTimer?.cancel();
        _bufferingTimeoutTimer = null;
        break;

      case BetterPlayerEventType.play:
        if (!isPlaying()) {
          setState('isPlaying', true);
          if (!isBuffering()) setState('toastString', 'HIDE_CONTAINER');
          setState('progressEnabled', false);
          setState('showPlayIcon', false);
          setState('showPauseIconFromListener', false);
          setState('isUserPaused', false);
          startPlayDurationTimer();
          if (retryCount() > 0) setState('retryCount', 0);
        }
        break;

      case BetterPlayerEventType.pause:
        if (isPlaying()) {
          setState('isPlaying', false);
          setState('toastString', S.current.playpause);
          if (isUserPaused()) {
            setState('showPlayIcon', true);
            setState('showPauseIconFromListener', false);
          } else {
            setState('showPlayIcon', false);
            setState('showPauseIconFromListener', true);
          }
          LogUtil.i('播放暂停，用户触发: ${isUserPaused()}');
        }
        break;

      case BetterPlayerEventType.progress:
        if (progressEnabled() && isPlaying()) {
          final position = event.parameters?["progress"] as Duration?;
          final duration = event.parameters?["duration"] as Duration?;
          if (position != null && duration != null) {
            final lastPos = lastBufferedPosition();
            final lastTime = lastBufferedTime();
            if (lastPos != null && lastTime != null) {
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final timeSinceLastUpdate = (timestamp - lastTime) / 1000.0;
              final remainingBuffer = lastPos - position;

              final history = bufferedHistory();
              history.add({
                'buffered': lastPos,
                'position': position,
                'timestamp': timestamp,
                'remainingBuffer': remainingBuffer,
              });
              if (history.length > bufferHistorySize) history.removeAt(0);

              if (isHls() && !isParsing()) {
                final remainingTime = duration - position;
                if (preCachedUrl() != null && remainingTime.inSeconds <= hlsSwitchThresholdSeconds) {
                  switchToPreCachedUrl('HLS 剩余时间少于 $hlsSwitchThresholdSeconds 秒');
                } else if (history.length >= bufferHistorySize) {
                  int positionIncreaseCount = 0;
                  int remainingBufferLowCount = 0;

                  for (int i = history.length - positionIncreaseThreshold; i < history.length; i++) {
                    final prev = history[i - 1];
                    final curr = history[i];
                    if (curr['position'] > prev['position']) positionIncreaseCount++;
                    if ((curr['remainingBuffer'] as Duration).inSeconds < minRemainingBufferSeconds) remainingBufferLowCount++;
                  }

                  if (positionIncreaseCount == positionIncreaseThreshold &&
                      remainingBufferLowCount >= lowBufferThresholdCount &&
                      timeSinceLastUpdate > bufferUpdateTimeoutSeconds) {
                    LogUtil.i('触发重新解析');
                    reparseAndSwitch();
                  }
                }
              } else {
                final remainingTime = duration - position;
                if (remainingTime.inSeconds <= nonHlsPreloadThresholdSeconds) {
                  final nextUrl = getNextVideoUrl();
                  if (nextUrl != null && nextUrl != preCachedUrl()) {
                    LogUtil.i('非 HLS 剩余时间少于 $nonHlsPreloadThresholdSeconds 秒，预缓存下一源');
                    preloadNextVideo(nextUrl);
                  }
                }
                if (remainingTime.inSeconds <= nonHlsSwitchThresholdSeconds && preCachedUrl() != null) {
                  switchToPreCachedUrl('非 HLS 剩余时间少于 $nonHlsSwitchThresholdSeconds 秒');
                }
              }
            } else {
              LogUtil.i('缓冲数据未准备好: lastPos=$lastPos, lastTime=$lastTime');
            }
          } else {
            LogUtil.i('Progress 数据不完整: position=$position, duration=$duration');
          }
        }
        break;

      case BetterPlayerEventType.finished:
        if (!isHls() && preCachedUrl() != null) {
          switchToPreCachedUrl('非 HLS 播放结束');
        } else if (isHls()) {
          LogUtil.i('HLS 流异常结束，重试播放');
          retryPlayback();
        } else {
          LogUtil.i('无更多源可播放');
          handleNoMoreSources();
        }
        break;

      default:
        if (event.betterPlayerEventType != BetterPlayerEventType.changedPlayerVisibility) {
          LogUtil.i('未处理事件: ${event.betterPlayerEventType}');
        }
        break;
    }
  }

  void dispose() {
    _bufferingTimeoutTimer?.cancel();
    _bufferingTimeoutTimer = null;
  }
}
