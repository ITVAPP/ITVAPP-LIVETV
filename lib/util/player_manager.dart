import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
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
  bool _isDisposing = false;
  
  // Constructor with onError parameter
  PlayerManager({this.onError});
  VlcPlayerController? get controller => _controller;
  PlayerState get state => _state;
  
// 初始化播放器
Future<bool> initializePlayer(String url, {
  VlcPlayerOptions? options,
  Function(String)? onError,
}) async {
  LogUtil.i('播放器准备初始化播放: $url');    
  if (_isDisposing) {
    LogUtil.i('播放器正在释放中，初始化失败');
    return false;
  }
  
  try {
    // 释放旧控制器
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }

    // 创建新控制器
    LogUtil.i('创建新的VLC控制器');
    _controller = VlcPlayerController.network(
      url,
      hwAcc: HwAcc.full,
      options: options ?? PlayerConfig.defaultOptions,
      autoPlay: false,
    );

    // 添加状态监听
    _controller!.addListener(_controllerListener);
    
    // 初始化控制器
    LogUtil.i('开始初始化控制器');
    await _controller!.initialize();
    LogUtil.i('控制器初始化完成');

    // 设置初始参数
    await _controller!.setVolume(100);
    await _controller!.setPlaybackSpeed(1.0);
    
    _state.isInitialized = true;
    return true;

  } catch (e, stackTrace) {
    LogUtil.logError('初始化失败', e, stackTrace);
    _handleError('初始化失败: $e', onError);
    _state.isInitialized = false;
    return false;
  }
}

  void _controllerListener() {
    if (_controller == null || _isDisposing) return;
    
    try {
      final value = _controller!.value;
      
      _state.isInitialized = value.isInitialized;
      _state.isPlaying = value.isPlaying;
      _state.isBuffering = value.playingState == PlayingState.buffering;
      _state.bufferingNotifier.value = _state.isBuffering;
      _state.playingNotifier.value = _state.isPlaying;

      if (value.aspectRatio != null) {
        _state.aspectRatio = value.aspectRatio!;
      }

      if (value.hasError) {
        _handleError(value.errorDescription ?? '未知错误');
      }
    } catch (e, stackTrace) {
      LogUtil.logError('状态更新失败', e, stackTrace);
      _handleError('状态更新失败: $e');
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
     _handleError('播放失败: $e');  // 调用错误处理函数
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
     _handleError('暂停失败: $e');  // 调用错误处理函数
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
     _handleError('停止失败: $e');  // 调用错误处理函数
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
       _handleError(_state.errorMessage ?? 'Unknown error');  // 调用错误处理函数
     }
   } catch (e, stackTrace) {
     LogUtil.logError('更新状态失败', e, stackTrace);
     _handleError('更新状态失败: $e');  // 调用错误处理函数
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
     // 保存引用后立即清空
     final currentController = _controller;
     _controller = null;

     // 处理控制器
     if (currentController != null) {
       LogUtil.i('开始释放控制器资源');
       
       // 移除监听器
       currentController.removeListener(_controllerListener);  // 修改：指定具体的监听器

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
     _handleError('释放资源时出错: $e');  // 调用错误处理函数
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
