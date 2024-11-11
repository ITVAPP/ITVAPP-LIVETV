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
  static const int networkCacheTime = 3000;   // 网络缓冲时间
  static const int fileCacheTime = 2000;      // 文件缓冲时间
  static const int liveCacheTime = 3000;      // 直播缓冲时间
  
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
  Completer<void>? _disposingCompleter;  // 新增同步标记
  
  // Constructor with onError parameter
  PlayerManager({this.onError});

  // Getter方法
  VlcPlayerController? get controller => _controller;
  PlayerState get state => _state;
  
  // 初始化播放器
  Future<bool> initializePlayer(String url, {
    Duration timeout = const Duration(seconds: 10),
    VlcPlayerOptions? options,
    Function(String)? onError,
  }) async {
    // 等待之前的dispose完成
    if (_disposingCompleter != null) {
      try {
        await _disposingCompleter!.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
      } catch (_) {}
    }
    
    if (_isDisposing) return false;
    
    try {
      // 释放旧控制器
      await dispose();
      
      // 创建新控制器
      final newController = VlcPlayerController.network(
        url,
        hwAcc: HwAcc.full,
        options: options ?? PlayerConfig.defaultOptions,
        autoPlay: false,
        autoInitialize: true,  // 修改为true以确保正确初始化
      );

      _controller = newController;
      _state.isInitialized = false;
      _state.hasError = false;
      _state.errorMessage = null;
      _state.errorNotifier.value = null;

      // 添加状态监听
      newController.addListener(() {
        if (!_isDisposing) {
          _handleControllerUpdate(newController);
        }
      });

      // 设置初始化超时
      _initializationTimer?.cancel();
      _initializationTimer = Timer(timeout, () {
        if (!_state.isInitialized) {
          _handleError('初始化超时', onError);
        }
      });

      // 等待初始化完成
      await newController.initialize().timeout(
        timeout,
        onTimeout: () => throw TimeoutException('播放器初始化超时'),
      );

      // 验证初始化状态
      if (!newController.value.isInitialized) {
        throw StateError('Controller initialized but not ready');
      }

      _state.isInitialized = true;
      await newController.setVolume(100);
      await newController.setPlaybackSpeed(1.0);
      
      return true;
    } catch (e, stackTrace) {
      _handleError('初始化失败: $e', onError);
      LogUtil.logError('播放器初始化失败', e, stackTrace);
      await _safeDispose();  // 使用安全释放
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
    if (_isDisposing) return;  // 添加释放检查
    
    _state.hasError = true;
    _state.errorMessage = message;
    _state.errorNotifier.value = message;
    
    try {
      if (errorCallback != null) {
        errorCallback(message);
      } else if (onError != null) {
        onError!(message);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('错误回调执行失败', e, stackTrace);  // 添加错误处理
    }
  }

  // 新增：处理控制器更新
  void _handleControllerUpdate(VlcPlayerController controller) {
    try {
      final playingState = controller.value.playingState;
      
      final bool newBuffering = playingState == PlayingState.buffering;
      if (_state.isBuffering != newBuffering) {
        _state.isBuffering = newBuffering;
        _state.bufferingNotifier.value = newBuffering;
      }
      
      final bool newPlaying = playingState == PlayingState.playing;
      if (_state.isPlaying != newPlaying) {
        _state.isPlaying = newPlaying;
        _state.playingNotifier.value = newPlaying;
      }
      
      if (newPlaying && controller.value.aspectRatio != null) {
        _state.aspectRatio = controller.value.aspectRatio!;
      }

      if (playingState == PlayingState.error || controller.value.hasError) {
        _handleError(controller.value.errorDescription ?? 'Unknown error', onError);
      }
    } catch (e, stackTrace) {
      LogUtil.logError('状态更新失败', e, stackTrace);
    }
  }

  // 新增：安全释放方法
  Future<void> _safeDispose() async {
    final currentController = _controller;
    _controller = null;

    if (currentController != null) {
      try {
        if (currentController.value.isPlaying) {
          await currentController.stop().timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
        }
        
        await currentController.dispose().timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
      } catch (e, stackTrace) {
        LogUtil.logError('安全释放失败', e, stackTrace);
      }
    }
  }

  // 修改后的dispose方法
  Future<void> dispose() async {
    if (_isDisposing) return;
    
    _isDisposing = true;
    _initializationTimer?.cancel();
    _disposingCompleter = Completer<void>();
    
    try {
      await _safeDispose();
      
      // 重置所有状态
      _state.isInitialized = false;
      _state.isPlaying = false;
      _state.playingNotifier.value = false;
      _state.isBuffering = false;
      _state.bufferingNotifier.value = false;
      _state.hasError = false;
      _state.errorMessage = null;
      _state.errorNotifier.value = null;
    } finally {
      _isDisposing = false;
      _disposingCompleter?.complete();
      _disposingCompleter = null;
    }
  }
}
