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
  /// 释放资源的方法，返回一个 Future
  Future<void> dispose();
}

/// 资源管理类：用于管理所有需要释放的资源
class ResourceManager {
  final List<Disposable> _resources = [];

  /// 注册资源：将资源加入管理列表
  void register(Disposable resource) {
    _resources.add(resource);
  }

  /// 释放指定资源：释放并移除单个资源
  Future<void> disposeResource(Disposable resource) async {
    try {
      await resource.dispose();  // 调用资源的释放方法
      _resources.remove(resource);  // 从管理列表中移除资源
    } catch (e) {
      LogUtil.logError('资源释放失败', e);  // 捕获并记录释放失败的错误
    }
  }

  /// 释放所有资源：逐个释放并清空资源列表
  Future<void> disposeAll() async {
    for (var resource in _resources.toList()) {
      await disposeResource(resource);  // 释放资源
    }
    _resources.clear();  // 清空资源管理列表
  }
}

/// 播放器控制器管理类：负责管理和释放播放器控制器
class PlayerControllerManager {
  /// 释放播放器控制器：释放播放器控制器相关资源
  Future<void> disposeController(BetterPlayerController controller) async {
    // 检查播放器是否正在播放
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
          await controller.videoPlayerController!.dispose();  // 释放视频播放器控制器
          await Future.delayed(const Duration(milliseconds: 300));  // 等待视频控制器释放
        }
        
        // 5. 最后释放主控制器
        controller.dispose();
      } catch (e) {
        LogUtil.logError('播放器控制器释放失败', e);  // 捕获并记录释放失败的错误
      }
    }
  }
}

/// 预加载管理类：负责预加载视频资源并处理相关操作
class PreloadManager {
  BetterPlayerController? _preloadController;  // 预加载的播放器控制器
  String? _preloadUrl;  // 预加载的URL地址
  bool _isDisposing = false;  // 标记是否正在释放资源

  /// 清理预加载资源：释放预加载控制器及相关资源
  Future<void> cleanupPreload() async {
    if (_isDisposing) return;
    _isDisposing = true;

    try {
      if (_preloadController != null) {
        // 1. 先移除事件监听
        _preloadController!.removeEventsListener((event) {});
        
        // 2. 确保暂停播放
        if (_preloadController!.isPlaying() ?? false) {
          await _preloadController!.pause();
        }
        
        // 3. 先释放视频控制器
        if (_preloadController!.videoPlayerController != null) {
          await _preloadController!.videoPlayerController!.dispose();
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // 4. 再释放主控制器
        await _preloadController!.dispose();
        _preloadController = null;
        _preloadUrl = null;
      }
    } catch (e) {
      LogUtil.logError('预加载资源释放失败', e);
    } finally {
      _isDisposing = false;
    }
  }

  BetterPlayerController? get controller => _preloadController;  // 获取预加载控制器
  String? get url => _preloadUrl;  // 获取预加载URL

  /// 设置预加载数据：设置预加载的控制器和URL
  void setPreloadData(BetterPlayerController controller, String url) {
    _preloadController = controller;  // 设置预加载控制器
    _preloadUrl = url;  // 设置预加载URL
  }
}

/// 网络资源管理类：负责管理网络请求相关的资源
class NetworkResourceManager {
  final Map<String, http.Client> _clients = {};  // 存储所有网络请求的客户端
  StreamUrl? _streamUrl;  // 用于流媒体的URL

  /// 释放网络资源：关闭所有网络请求并释放相关资源
  Future<void> releaseNetworkResources() async {
    // 取消所有进行中的网络请求
    _clients.forEach((key, client) {
      client.close();  // 关闭HTTP客户端
    });
    _clients.clear();  // 清空客户端列表
    
    // 释放StreamUrl相关资源
    await _disposeStreamUrl();
  }

  /// 释放StreamUrl资源
  Future<void> _disposeStreamUrl() async {
    if (_streamUrl != null) {
      _streamUrl!.dispose();  // 移除 await，因为 dispose() 返回 void
      _streamUrl = null;  // 清空流媒体URL引用
    }
  }

  /// 设置StreamUrl：设置流媒体URL
  void setStreamUrl(StreamUrl url) {
    _streamUrl = url;  // 设置流媒体URL
  }

  StreamUrl? get streamUrl => _streamUrl;  // 获取流媒体URL
}

/// 视频播放器事件监听 Mixin：用于监听播放器事件并进行处理
mixin VideoPlayerListenerMixin<T extends StatefulWidget> on State<T> {
  // 成员变量用于控制更新频率
  int? _lastUpdateTime;
  double? _lastProgress;
  static const int UPDATE_INTERVAL = 2000; // 更新间隔设置为2000毫秒

  BetterPlayerController? get playerController;  // 播放器控制器
  set playerController(BetterPlayerController? value);

  bool get isBuffering;  // 是否正在缓冲
  set isBuffering(bool value);

  bool get isPlaying;  // 是否正在播放
  set isPlaying(bool value);

  double get bufferingProgress;  // 缓冲进度
  set bufferingProgress(double value);

  String get toastString;  // 用于显示的提示字符串
  set toastString(String value);

  double get aspectRatio;  // 播放器视频的宽高比
  set aspectRatio(double value);

  bool get shouldUpdateAspectRatio;  // 是否需要更新宽高比
  set shouldUpdateAspectRatio(bool value);

  bool get isRetrying;  // 是否正在重试
  bool get isDisposing;  // 是否正在释放资源
  bool get isSwitchingChannel;  // 是否正在切换频道
  
  /// 处理播放完成事件的抽象方法
  void handleFinishedEvent(); 

  /// 启动超时检测
  void startTimeoutCheck();

  /// 预加载下一个视频
  Future<void> preloadNextVideo(String url);

  /// 视频播放器事件监听方法：根据事件类型处理不同的逻辑
  void videoListener(BetterPlayerEvent event) {
    // 检查播放器控制器是否存在，以及是否正在释放或重试
    if (playerController == null || isDisposing || isRetrying) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _handleInitialized();  // 初始化完成后的处理
        break;

      case BetterPlayerEventType.exception:
        _handleException(event);  // 异常处理
        break;

      case BetterPlayerEventType.bufferingStart:
        _handleBufferingStart();  // 缓冲开始处理
        break;

      case BetterPlayerEventType.bufferingUpdate:
        _handleBufferingUpdate(event);  // 缓冲进度更新处理
        break;

      case BetterPlayerEventType.bufferingEnd:
        _handleBufferingEnd();  // 缓冲结束处理
        break;

      case BetterPlayerEventType.play:
        _handlePlay();  // 播放处理
        break;

      case BetterPlayerEventType.pause:
        _handlePause();  // 暂停处理
        break;

      case BetterPlayerEventType.progress:
        _handleProgress(event);  // 进度处理
        break;

      case BetterPlayerEventType.finished:
        _handleFinished();  // 播放结束处理
        break;

      default:
        _handleOtherEvents(event);  // 处理其他未处理的事件
        break;
    }
  }
  
    /// 初始化完成时处理
  void _handleInitialized() {
    // 检查组件是否挂载以及是否需要更新宽高比
    if (mounted && shouldUpdateAspectRatio) {
      final newAspectRatio = playerController?.videoPlayerController?.value.aspectRatio ?? 1.78;
      // 如果宽高比发生变化，更新状态
      if (aspectRatio != newAspectRatio) {
        setState(() {
          aspectRatio = newAspectRatio;  // 更新宽高比
          shouldUpdateAspectRatio = false;
        });
      }
    }
  }

  /// 异常处理
  void _handleException(BetterPlayerEvent event) {
    // 如果没有在切换频道，记录错误信息
    if (!isSwitchingChannel) {
      final errorMessage = event.parameters?["error"]?.toString() ?? "Unknown error";
      LogUtil.e('监听到播放器错误：$errorMessage');
    }
  }

  /// 开始缓冲处理
  void _handleBufferingStart() {
    if (mounted) {
      LogUtil.i('播放卡住，开始缓冲');
      setState(() {
        isBuffering = true;  // 设置为缓冲状态
        bufferingProgress = 0.0;  // 重置缓冲进度
      });
      startTimeoutCheck();  // 启动超时检测
    }
  }

  /// 缓冲更新处理
  void _handleBufferingUpdate(BetterPlayerEvent event) {
    if (!mounted) return;

    // 获取当前时间，检查更新间隔
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastUpdateTime != null && (now - _lastUpdateTime!) < UPDATE_INTERVAL) {
      return;  // 如果距离上次更新不到2000毫秒，直接返回
    }

    final dynamic buffered = event.parameters?["buffered"];
    if (buffered == null || !(buffered is List) || buffered.isEmpty) {
      return;
    }

    try {
      final Duration? duration = playerController?.videoPlayerController?.value.duration;
      if (duration == null || duration.inMilliseconds <= 0) {
        return;
      }

      final dynamic range = buffered.last;
      if (range == null) return;

      final double progress = (range.end.inMilliseconds / duration.inMilliseconds)
          .clamp(0.0, 1.0);

      // 检查进度值是否发生变化
      if (_lastProgress != null && (progress - _lastProgress!).abs() < 0.01) {
        return;  // 如果进度变化小于1%，不更新
      }

      // 更新时间戳和进度值
      _lastUpdateTime = now;
      _lastProgress = progress;

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

    } catch (e) {
      LogUtil.e('缓冲进度更新失败: $e');
      setState(() {
        isBuffering = false;
        toastString = 'HIDE_CONTAINER';
      });
    }
  }

  /// 缓冲结束处理
  void _handleBufferingEnd() {
    if (mounted) {
      LogUtil.i('缓冲结束');
      setState(() {
        isBuffering = false;  // 设置为非缓冲状态
        toastString = 'HIDE_CONTAINER';  // 隐藏缓冲提示
      });
    }
  }
  
    /// 播放处理
  void _handlePlay() {
    if (mounted && !isPlaying) {
      setState(() {
        isPlaying = true;  // 设置为播放状态
        if (!isBuffering) {
          toastString = 'HIDE_CONTAINER';  // 隐藏缓冲提示
        }
      });
    }
  }

  /// 暂停处理
  void _handlePause() {
    if (mounted && isPlaying) {
      setState(() {
        isPlaying = false;  // 设置为暂停状态
        toastString = S.current.playpause;  // 显示"播放/暂停"提示
      });
    }
  }

  /// 进度处理
  void _handleProgress(BetterPlayerEvent event) {
      final position = event.parameters?["progress"] as Duration?;
      final duration = event.parameters?["duration"] as Duration?;

      if (position != null && duration != null) {
          final remainingTime = duration - position;
          // 如果剩余时间小于等于15秒，且不是HLS流，才预加载下一个视频
          if (remainingTime.inSeconds <= 15 && 
              playerController?.betterPlayerDataSource?.url != null &&
              !VideoPlayerUtils.isHlsStream(playerController?.betterPlayerDataSource?.url)) {
              final nextUrl = getNextVideoUrl();
              if (nextUrl != null) {
                  preloadNextVideo(nextUrl);
              }
          }
      }
  }
  
  /// 播放结束处理
  void _handleFinished() {
    if (mounted) {
      handleFinishedEvent();  // 调用抽象方法
    }
  }

  /// 处理其他事件
  void _handleOtherEvents(BetterPlayerEvent event) {
    // 记录未处理的事件类型
    if (event.betterPlayerEventType != BetterPlayerEventType.progress) {
      LogUtil.i('未处理的事件类型: ${event.betterPlayerEventType}');
    }
  }

  /// 获取下一个视频URL的方法(需要在使用此mixin的类中实现)
  String? getNextVideoUrl();

  // 在 dispose 中清理变量
  @override
  void dispose() {
    _lastUpdateTime = null;
    _lastProgress = null;
    super.dispose();
  }
}

/// 播放器配置工具类：用于创建播放器配置
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
    required String url,  // 视频的URL地址
    required bool isHls,  // 是否为HLS流
    Map<String, String>? headers,  // 可选的请求头
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,  // 数据源类型为网络
      url,  // 视频的URL
      liveStream: isHls,  // 是否为直播流
      useAsmsTracks: isHls,  // 是否使用自适应流媒体
      useAsmsAudioTracks: isHls,  // 是否使用自适应音频流
      useAsmsSubtitles: false,  // 不使用自适应字幕
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,  // 不显示通知
      ),
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 10000,  // 最小缓冲时间
        maxBufferMs: 60000,  // 最大缓冲时间
        bufferForPlaybackMs: 5000,  // 播放前缓冲时间
        bufferForPlaybackAfterRebufferMs: 5000,  // 重新缓冲后的播放缓冲时间
      ),
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls,  // 非HLS流时使用缓存
        preCacheSize: 20 * 1024 * 1024,  // 预缓存大小
        maxCacheSize: 300 * 1024 * 1024,  // 最大缓存大小
        maxCacheFileSize: 50 * 1024 * 1024,  // 单个缓存文件最大大小
      ),
      headers: headers ?? {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
      },
    );
  }

  /// 创建播放器基本配置
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,  // 是否为HLS流
    required Function(BetterPlayerEvent) eventListener,  // 事件监听器
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain,  // 视频适应方式
      autoPlay: false,  // 不自动播放
      looping: isHls,  // HLS流时循环播放
      allowedScreenSleep: false,  // 禁止屏幕休眠
      autoDispose: false,  // 不自动释放资源
      expandToFill: true,  // 扩展以填充屏幕
      handleLifecycle: true,  // 处理生命周期
      errorBuilder: (_, __) => _backgroundImage,  // 错误时显示的背景图片
      placeholder: _backgroundImage,  // 占位符图片
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false,  // 不显示控制器
        enablePlayPause: false,  // 禁用播放/暂停按钮
        enableProgressBar: false,  // 禁用进度条
        enableProgressText: false,  // 禁用进度文本
        enableFullscreen: false,  // 禁用全屏按钮
        showControlsOnInitialize: false,  // 初始化时不显示控制器
      ),
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,  // 全屏后允许的屏幕方向
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      eventListener: eventListener,  // 事件监听器
    );
  }
}

/// 视频播放器工具方法：提供一些静态方法用于视频流相关操作
class VideoPlayerUtils {
  /// 检查是否为音频流
  static bool checkIsAudioStream(String? url) {
    // 如果URL为空或无效，返回false
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    // 检查URL是否以音频格式结尾
    return lowercaseUrl.endsWith('.mp3') || 
           lowercaseUrl.endsWith('.aac') || 
           lowercaseUrl.endsWith('.m4a') ||
           lowercaseUrl.endsWith('.ogg') ||
           lowercaseUrl.endsWith('.wav');
  }
  
  /// 判断是否是HLS流
  static bool isHlsStream(String? url) {
    // 如果URL为空或无效，返回false
    if (url == null || url.isEmpty) return false;
    final lowercaseUrl = url.toLowerCase();
    // 检查URL是否以HLS格式结尾
    return lowercaseUrl.endsWith('.m3u8') || lowercaseUrl.endsWith('.m3u');
  }
}
