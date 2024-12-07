import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:http/http.dart' as http;
import '../util/stream_url.dart';
import '../util/log_util.dart';
import '../generated/l10n.dart';

/// 可释放资源的接口
abstract class Disposable {
  Future<void> dispose();
}

/// 资源管理类
class ResourceManager {
  final List<Disposable> _resources = [];
  
  void register(Disposable resource) {
    _resources.add(resource);
  }
  
  Future<void> disposeResource(Disposable resource) async {
    try {
      await resource.dispose();
      _resources.remove(resource);
    } catch (e) {
      LogUtil.logError('资源释放失败', e);
    }
  }
  
  Future<void> disposeAll() async {
    for (var resource in _resources.toList()) {
      await disposeResource(resource);
    }
    _resources.clear();
  }
}

/// 播放器控制器管理类
class PlayerControllerManager {
  Future<void> disposeController(BetterPlayerController controller) async {
    if (controller.isPlaying() ?? false) {
      try {
        // 1. 先静音避免释放时的声音问题
        await controller.setVolume(0);
        
        // 2. 停止播放
        await controller.pause();
        
        // 3. 等待短暂时间确保暂停完成
        await Future.delayed(const Duration(milliseconds: 300));
        
        // 4. 释放视频控制器
        if (controller.videoPlayerController != null) {
          await controller.videoPlayerController!.dispose();
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // 5. 最后释放主控制器
        controller.dispose();
      } catch (e) {
        LogUtil.logError('播放器控制器释放失败', e);
      }
    }
  }
}

/// 预加载管理类
class PreloadManager {
  BetterPlayerController? _preloadController;
  String? _preloadUrl;
  bool _isDisposing = false;

  Future<void> cleanupPreload() async {
    if (_isDisposing) return;
    _isDisposing = true;
    
    try {
      if (_preloadController != null) {
        await _preloadController!.pause();
        _preloadController!.dispose();
        _preloadController = null;
        _preloadUrl = null;
      }
    } catch (e) {
      LogUtil.logError('预加载资源释放失败', e);
    } finally {
      _isDisposing = false;
    }
  }
  
  BetterPlayerController? get controller => _preloadController;
  String? get url => _preloadUrl;
  
  void setPreloadData(BetterPlayerController controller, String url) {
    _preloadController = controller;
    _preloadUrl = url;
  }
}

/// 网络资源管理类
class NetworkResourceManager {
  final Map<String, http.Client> _clients = {};
  StreamUrl? _streamUrl;
  
  Future<void> releaseNetworkResources() async {
    // 取消所有进行中的网络请求
    _clients.forEach((key, client) {
      client.close();
    });
    _clients.clear();
    
    // 释放StreamUrl相关资源
    await _disposeStreamUrl();
  }
  
  Future<void> _disposeStreamUrl() async {
    if (_streamUrl != null) {
      await _streamUrl?.dispose();
      _streamUrl = null;
    }
  }
  
  void setStreamUrl(StreamUrl url) {
    _streamUrl = url;
  }
  
  StreamUrl? get streamUrl => _streamUrl;
}

/// 视频播放器事件监听 Mixin
mixin VideoPlayerListenerMixin<T extends StatefulWidget> on State<T> {
  // 播放器控制器
  BetterPlayerController? get playerController;
  set playerController(BetterPlayerController? value);
  
  // 状态变量
  bool get isBuffering;
  set isBuffering(bool value);
  
  bool get isPlaying; 
  set isPlaying(bool value);
  
  double get bufferingProgress;
  set bufferingProgress(double value);
  
  String get toastString;
  set toastString(String value);
  
  double get aspectRatio;
  set aspectRatio(double value);
  
  bool get shouldUpdateAspectRatio;
  set shouldUpdateAspectRatio(bool value);
  
  bool get isRetrying;
  bool get isDisposing;
  bool get isSwitchingChannel;
  
  // 启动超时检测
  void startTimeoutCheck();
  
  // 预加载下一个视频
  Future<void> preloadNextVideo(String url);
  
  /// 视频播放器事件监听方法
  void videoListener(BetterPlayerEvent event) {
    if (playerController == null || isDisposing || isRetrying) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _handleInitialized();
        break;
        
      case BetterPlayerEventType.exception:
        _handleException(event);
        break;
        
      case BetterPlayerEventType.bufferingStart:
        _handleBufferingStart();
        break;
        
      case BetterPlayerEventType.bufferingUpdate:
        _handleBufferingUpdate(event);
        break;
        
      case BetterPlayerEventType.bufferingEnd:
        _handleBufferingEnd();
        break;
        
      case BetterPlayerEventType.play:
        _handlePlay();
        break;
        
      case BetterPlayerEventType.pause:
        _handlePause();
        break;
        
      case BetterPlayerEventType.progress:
        _handleProgress(event);
        break;
        
      case BetterPlayerEventType.finished:
        _handleFinished();
        break;
        
      default:
        _handleOtherEvents(event);
        break;
    }
  }

  // 初始化完成时处理
  void _handleInitialized() {
    if (mounted && shouldUpdateAspectRatio) {
      final newAspectRatio = playerController?.videoPlayerController?.value.aspectRatio ?? 1.78;
      if (aspectRatio != newAspectRatio) {
        setState(() {
          aspectRatio = newAspectRatio;
          shouldUpdateAspectRatio = false;
        });
      }
    }
  }

  // 异常处理
  void _handleException(BetterPlayerEvent event) {
    if (!isSwitchingChannel) {
      final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
      LogUtil.e('监听到播放器错误：$errorMessage');
    }
  }

  // 开始缓冲处理
  void _handleBufferingStart() {
    if (mounted) {
      LogUtil.i('播放卡住，开始缓冲');
      setState(() {
        isBuffering = true;
        bufferingProgress = 0.0;
      });
      startTimeoutCheck();
    }
  }

  // 缓冲更新处理
  void _handleBufferingUpdate(BetterPlayerEvent event) {
    if (mounted) {
      final dynamic buffered = event.parameters?["buffered"];
      if (buffered != null) {
        try {
          final Duration? duration = playerController?.videoPlayerController?.value.duration;
          if (duration != null && duration.inMilliseconds > 0) {
            final dynamic range = buffered.last;
            final double progress = range.end.inMilliseconds / duration.inMilliseconds;
            
            setState(() {
              bufferingProgress = progress;
              if (isBuffering) {
                if (progress >= 0.99) {
                  isBuffering = false;
                  toastString = 'HIDE_CONTAINER';
                } else {
                  toastString = '${S.current.loading} (${(progress * 100).toStringAsFixed(0)}%)';
                }
              }
            });
          }
        } catch (e) {
          LogUtil.e('缓冲进度更新失败: $e');
          setState(() {
            isBuffering = false;
            toastString = 'HIDE_CONTAINER';
          });
        }
      }
    }
  }

  // 缓冲结束处理
  void _handleBufferingEnd() {
    if (mounted) {
      LogUtil.i('缓冲结束');
      setState(() {
        isBuffering = false;
        toastString = 'HIDE_CONTAINER';
      });
    }
  }

  // 播放处理
  void _handlePlay() {
    if (mounted && !isPlaying) {
      setState(() {
        isPlaying = true;
        if (!isBuffering) {
          toastString = 'HIDE_CONTAINER';
        }
      });
    }
  }

  // 暂停处理
  void _handlePause() {
    if (mounted && isPlaying) {
      setState(() {
        isPlaying = false;
        toastString = S.current.playpause;
      });
    }
  }

  // 进度处理
  void _handleProgress(BetterPlayerEvent event) {
    final position = event.parameters?["progress"] as Duration?;
    final duration = event.parameters?["duration"] as Duration?;

    if (position != null && duration != null) {
      final remainingTime = duration - position;
      if (remainingTime.inSeconds <= 15) {
        final nextUrl = getNextVideoUrl();
        if (nextUrl != null) {
          preloadNextVideo(nextUrl);
        }
      }
    }
  }

  // 播放结束处理
  void _handleFinished() {
    // 实现播放结束的处理逻辑
  }

  // 处理其他事件
  void _handleOtherEvents(BetterPlayerEvent event) {
    if (event.betterPlayerEventType != BetterPlayerEventType.progress) {
      LogUtil.i('未处理的事件类型: ${event.betterPlayerEventType}');
    }
  }

  // 获取下一个视频URL的方法(需要在使用此mixin的类中实现)
  String? getNextVideoUrl();
}

/// 播放器配置工具类
class BetterPlayerConfig {
  // 定义常量背景图片Widget
  static const _backgroundImage = Image(
    image: AssetImage('assets/images/video_bg.png'),
    fit: BoxFit.cover,
    gaplessPlayback: true,  // 防止图片加载时闪烁
    filterQuality: FilterQuality.medium,  // 优化图片质量和性能的平衡
  );

  /// 创建播放器数据源配置
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: isHls,
      useAsmsTracks: isHls,
      useAsmsAudioTracks: isHls,
      useAsmsSubtitles: false,
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 10000,
        maxBufferMs: 60000,
        bufferForPlaybackMs: 5000,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls,
        preCacheSize: 20 * 1024 * 1024,
        maxCacheSize: 300 * 1024 * 1024,
        maxCacheFileSize: 50 * 1024 * 1024,
      ),
      headers: headers ?? {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
      },
    );
  }

  /// 创建播放器基本配置
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain,
      autoPlay: false,
      looping: isHls,
      allowedScreenSleep: false,
      autoDispose: false,
      expandToFill: true,
      handleLifecycle: true,
      errorBuilder: (_, __) => _backgroundImage,
      placeholder: _backgroundImage,
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false,
      ),
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      eventListener: eventListener,
    );
  }
}

/// 视频播放器工具方法
class VideoPlayerUtils {
  /// 检查是否为音频流
  static bool checkIsAudioStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.mp3') || 
           lowercaseUrl.endsWith('.aac') || 
           lowercaseUrl.endsWith('.m4a') ||
           lowercaseUrl.endsWith('.ogg') ||
           lowercaseUrl.endsWith('.wav');
  }
  
  /// 判断是否是HLS流
  static bool isHlsStream(String? url) {
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.endsWith('.m3u8') || lowercaseUrl.endsWith('.m3u');
  }
}
