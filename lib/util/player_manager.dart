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
  LogUtil.i('播放器准备初始化播放: $url');	
  if (_isDisposing) return false;
  
  try {
    // 先确保没有遗留的计时器
    _initializationTimer?.cancel();
    _initializationTimer = null;

    _initCompleter = Completer<void>();

    final newController = VlcPlayerController.network(
      url,
      hwAcc: HwAcc.auto,
      // options: options ?? PlayerConfig.defaultOptions,
      autoPlay: false,
      autoInitialize: true,
    );

    // 添加详细的状态监听和日志
    newController.addListener(() {
      if (_isDisposing) {
        LogUtil.i('播放器正在释放中，忽略状态更新');
        return;
      }
      
      final value = newController.value;
      LogUtil.i('VLC状态: ' + 
        'playingState=${value.playingState}, ' +
        'isInitialized=${value.isInitialized}, ' +
        'isBuffering=${value.isBuffering}, ' +
        'hasError=${value.hasError}');

      // 错误检查
      if (value.hasError) {
        LogUtil.e('''VLC播放器错误:
          错误描述: ${value.errorDescription}
          播放状态: ${value.playingState}
          初始化状态: ${value.isInitialized}
        ''');
        if (!_initCompleter!.isCompleted) {
          _initCompleter!.completeError(value.errorDescription ?? 'Unknown error');
        }
        return;
      }

      // 初始化检查
      if (!_initCompleter!.isCompleted) {
        if (value.isInitialized) {
          LogUtil.i('播放器初始化完成');
          _state.isInitialized = true;
          _initCompleter!.complete();
        } else if (value.playingState == PlayingState.buffering) {
          LogUtil.i('播放器正在缓冲');
          _state.isBuffering = true;
          _state.bufferingNotifier.value = true;
        }
      }
    });

    _controller = newController;
    _state.isInitialized = false;
    _state.hasError = false;
    _state.errorMessage = null;
    _state.errorNotifier.value = null;

    // 设置超时检查
    _initializationTimer = Timer(timeout, () {
      LogUtil.i('检查初始化状态: ' +
        'isInitialized=${_state.isInitialized}, ' +
        'isCompleted=${_initCompleter?.isCompleted}');
        
      if (!_state.isInitialized && !_initCompleter!.isCompleted) {
        LogUtil.e('播放器初始化超时');
        _initCompleter!.completeError(TimeoutException('播放器初始化超时'));
      }
    });

    // 等待初始化完成
    try {
      await _initCompleter!.future;
      
      if (_controller != null && _controller!.value.isInitialized) {
        await _controller!.setVolume(100);
        await _controller!.setPlaybackSpeed(1.0);
        LogUtil.i('播放器初始化并设置参数完成');
        return true;
      }
      
      throw Exception('播放器初始化失败');
    } catch (e) {
      LogUtil.e('等待初始化完成时出错: $e');
      rethrow;
    }

  } catch (e, stackTrace) {
    LogUtil.logError('初始化失败', e, stackTrace);
    _handleError('初始化失败: $e', onError);
    return false;
  } finally {
    _initializationTimer?.cancel();
    _initializationTimer = null;
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
  LogUtil.i('开始释放资源');
  if (_isDisposing) {
    LogUtil.i('正在释放中，跳过重复调用');
    return;
  }
  
  _isDisposing = true;
  
  try {
    // 先取消定时器
    _initializationTimer?.cancel();
    _initializationTimer = null;

    // 保存引用后立即清空
    final currentController = _controller;
    _controller = null;
    
    // 处理 initCompleter
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      LogUtil.i('处理未完成的初始化器');
      try {
        _initCompleter!.completeError('Disposed');
      } catch (e) {
        LogUtil.i('初始化器已完成，忽略错误: $e');
      }
    }
    _initCompleter = null;

    // 处理控制器
    if (currentController != null) {
      LogUtil.i('开始释放控制器资源');
      
      // 移除监听器
      currentController.removeListener(() {});
      
      try {
        // 检查初始化和播放状态
        final isInitialized = currentController.value.isInitialized;
        final isPlaying = currentController.value.isPlaying;
        
        if (isInitialized && isPlaying) {
          LogUtil.i('停止播放');
          await currentController.stop();
          // 等待停止完成
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // 释放控制器
        if (isInitialized) {
          LogUtil.i('释放已初始化的控制器');
          await Future.delayed(const Duration(milliseconds: 100));
          await currentController.dispose();
        } else {
          LogUtil.i('控制器未初始化，直接释放');
          try {
            await currentController.dispose();
          } catch (e) {
            if (e.toString().contains('_viewId')) {
              LogUtil.i('忽略 _viewId 未初始化错误');
            } else {
              rethrow;
            }
          }
        }
      } catch (e) {
        LogUtil.e('释放控制器时出错: $e');
      }
    }
    
  } catch (e, stackTrace) {
    LogUtil.logError('释放资源时出错', e, stackTrace);
  } finally {
    LogUtil.i('重置所有状态');
    _state.isInitialized = false;
    _state.isPlaying = false;
    _state.playingNotifier.value = false;
    _state.isBuffering = false;
    _state.bufferingNotifier.value = false;
    _state.hasError = false;
    _state.errorMessage = null;
    _state.errorNotifier.value = null;
    _isDisposing = false;
  }
}
}
