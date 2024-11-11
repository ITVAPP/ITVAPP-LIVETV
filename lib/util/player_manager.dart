import 'dart:async';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:flutter/foundation.dart';
import 'log_util.dart';

/// 播放器状态类，用于管理播放器的所有状态
class PlayerState {
  bool isInitialized = false;
  bool isPlaying = false;
  bool isBuffering = false;
  bool hasError = false;
  String? errorMessage;
  double aspectRatio = 1.78;

  // 添加状态变更通知
  final ValueNotifier<bool> playingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> bufferingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);
}

/// 播放器配置类，用于管理播放器的配置参数
class PlayerConfig {
  // 缓冲设置 (毫秒)
  static const int networkCacheTime = 3000;   // 网络文件缓冲时间
  static const int fileCacheTime = 2000;      // 本地文件缓冲时间
  static const int liveCacheTime = 3000;      // 直播文件缓冲时间
  
  // VLC播放器选项配置
  static final VlcPlayerOptions defaultOptions = VlcPlayerOptions(
    video: VlcVideoOptions([
      VlcVideoOptions.dropLateFrames(true),
      VlcVideoOptions.skipFrames(true),
      '--no-audio-time-stretch',  // 禁用音频时间拉伸
      '--audio-resampler=soxr',   // 使用高质量重采样
    ]),
    advanced: VlcAdvancedOptions([
      VlcAdvancedOptions.networkCaching(networkCacheTime),  // 网络缓冲
      VlcAdvancedOptions.clockJitter(0),                    // 时钟抖动修正
      VlcAdvancedOptions.fileCaching(fileCacheTime),        // 文件缓冲
      VlcAdvancedOptions.liveCaching(liveCacheTime),        // 直播缓冲
    ]),
    http: VlcHttpOptions([
      VlcHttpOptions.httpReconnect(true),
    ]),
    rtp: VlcRtpOptions([
      '--rtsp-tcp',
      '--rtp-timeout=10',
      '--rtp-max-src=2',
    ]),
    extras: ['--audio-resampler=soxr'],
  );
}

/// 播放器管理器类
class PlayerManager {
  VlcPlayerController? _controller;
  final PlayerState _state = PlayerState();
  final Function(String)? onError;  // onError function
  Timer? _initializationTimer;
  bool _isDisposing = false;
  Completer<void>? _initCompleter;  // 新增：初始化完成器
  
  // Constructor with onError parameter
  PlayerManager({this.onError});
  VlcPlayerController? get controller => _controller;
  PlayerState get state => _state;
  
  // 初始化播放器
  Future<bool> initializePlayer(String url, {
    Duration timeout = const Duration(seconds: 10),
    VlcPlayerOptions? options,
    Function(String)? onError,
  }) async {
    if (_isDisposing) return false;
    
    // 确保之前的控制器被正确释放
    await dispose();
    
    try {
      _initCompleter = Completer<void>();  // 创建新的完成器

      // 创建新控制器
      final newController = VlcPlayerController.network(
        url,
        hwAcc: HwAcc.full,
        options: options ?? PlayerConfig.defaultOptions,
        autoPlay: false,
        autoInitialize: true,  // 改为 true
      );

      // 设置监听器
      newController.addListener(() {
        if (!_initCompleter!.isCompleted && newController.value.isInitialized) {
          _state.isInitialized = true;
          _initCompleter!.complete();
        }
      });

      _controller = newController;
      _state.isInitialized = false;
      _state.hasError = false;
      _state.errorMessage = null;
      _state.errorNotifier.value = null;

      // 设置初始化超时
      _initializationTimer?.cancel();
      _initializationTimer = Timer(timeout, () {
        if (!_state.isInitialized && !_initCompleter!.isCompleted) {
          _initCompleter!.completeError(TimeoutException('播放器初始化超时'));
        }
      });

      // 等待初始化完成
      await _initCompleter!.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('播放器初始化超时'),
      );

      // 初始化成功后的设置
      if (_controller != null && _controller!.value.isInitialized) {
        await _controller!.setVolume(100);
        await _controller!.setPlaybackSpeed(1.0);
        return true;
      }
      
      throw Exception('播放器初始化失败');

    } catch (e, stackTrace) {
      _handleError('初始化失败: $e', onError);
      LogUtil.logError('播放器初始化失败', e, stackTrace);
      await dispose();
      return false;
    } finally {
      _initializationTimer?.cancel();
    }
  }

  // 开始播放
  Future<bool> play() async {
    if (_controller == null || !_state.isInitialized || _isDisposing) {
      return false;
    }

    try {
      await _controller!.play();
      _state.isPlaying = true;
      _state.playingNotifier.value = true;
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('播放失败', e, stackTrace);
      return false;
    }
  }

  // 暂停播放
  Future<bool> pause() async {
    if (_controller == null || !_state.isInitialized || _isDisposing) {
      return false;
    }

    try {
      await _controller!.pause();
      _state.isPlaying = false;
      _state.playingNotifier.value = false;
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('暂停失败', e, stackTrace);
      return false;
    }
  }

  // 停止播放
  Future<bool> stop() async {
    if (_controller == null || _isDisposing) {
      return false;
    }

    try {
      if (_controller!.value.isPlaying) {
        await _controller!.stop();
      }
      _state.isPlaying = false;
      _state.playingNotifier.value = false;
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('停止失败', e, stackTrace);
      return false;
    }
  }

  // 处理错误
  void _handleError(String message, [Function(String)? errorCallback]) {
    _state.hasError = true;
    _state.errorMessage = message;
    _state.errorNotifier.value = message;
    if (errorCallback != null) {
      errorCallback(message);  // 使用传入的错误回调
    } else if (onError != null) {
      onError!(message);  // 使用构造函数中定义的回调
    }
  }

  // 更新播放器状态
  void updateState(VlcPlayerController controller) {
    if (_isDisposing) return;
    
    try {
      final playingState = controller.value.playingState;
      
      _state.isBuffering = playingState == PlayingState.buffering;
      _state.bufferingNotifier.value = _state.isBuffering;
      
      _state.isPlaying = playingState == PlayingState.playing;
      _state.playingNotifier.value = _state.isPlaying;
      
      if (_state.isPlaying && controller.value.aspectRatio != null) {
        _state.aspectRatio = controller.value.aspectRatio!;
      }

      if (playingState == PlayingState.error || controller.value.hasError) {
        _state.hasError = true;
        _state.errorMessage = controller.value.errorDescription ?? 'Unknown error';
        _state.errorNotifier.value = _state.errorMessage;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('更新状态失败', e, stackTrace);
    }
  }

  // 释放资源
  Future<void> dispose() async {
    if (_isDisposing) return;
    
    _isDisposing = true;
    _initializationTimer?.cancel();
    
    try {
      final currentController = _controller;
      _controller = null;
      
      if (currentController != null) {
        // 移除所有监听器
        currentController.removeListener(() {});
        
        try {
          if (currentController.value.isInitialized && currentController.value.isPlaying) {
            await currentController.stop();
            // 添加短暂延迟确保stop完成
            await Future.delayed(const Duration(milliseconds: 50));
          }
        } catch (e) {
          LogUtil.logError('停止播放失败', e);
        }

        try {
          // 延迟后释放控制器
          await currentController.dispose();
        } catch (e) {
          LogUtil.logError('释放控制器失败', e);
        }
      }

      // 确保完成器被完成
      _initCompleter?.completeError('Disposed');
      
    } catch (e, stackTrace) {
      LogUtil.logError('释放资源失败', e, stackTrace);
    } finally {
      // 重置所有状态
      _isDisposing = false;
      _state.isInitialized = false;
      _state.isPlaying = false;
      _state.playingNotifier.value = false;
      _state.isBuffering = false;
      _state.bufferingNotifier.value = false;
      _state.hasError = false;
      _state.errorMessage = null;
      _state.errorNotifier.value = null;
      _initCompleter = null;
    }
  }
}
