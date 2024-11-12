import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'log_util.dart';

// PlayerState 和 PlayerConfig 类保持不变...

/// 播放器管理器类
class PlayerManager {
  VlcPlayerController? _controller;
  final PlayerState _state = PlayerState();
  final Function(String)? onError;
  Timer? _initializationTimer;
  bool _isDisposing = false;
  Completer<void>? _initCompleter;
  VlcPlayerController? _newController;
  
  PlayerManager({this.onError});
  VlcPlayerController? get controller => _controller;
  PlayerState get state => _state;
  
// 初始化播放器
Future<bool> initializePlayer(String url, {
  Duration timeout = const Duration(seconds: 20),
  VlcPlayerOptions? options,
  Function(String)? onError,
}) async {
  LogUtil.i('1. 播放器准备初始化播放: $url');    
  if (_isDisposing) {
    LogUtil.i('2. 播放器正在释放中，初始化失败');
    return false;
  }
  
  try {
    LogUtil.i('3. 开始取消已有计时器');
    _initializationTimer?.cancel();
    _initializationTimer = null;

    LogUtil.i('4. 创建新的初始化完成器');
    _initCompleter = Completer<void>();

    LogUtil.i('5. 准备创建VLC控制器，配置信息：hwAcc=full, options=${options ?? PlayerConfig.defaultOptions}');
    try {
      // 移除 isVlcInit 检查，因为新版本不支持此API
      
      _newController = VlcPlayerController.network(
        url,
        hwAcc: HwAcc.full,
        options: options ?? PlayerConfig.defaultOptions,
        autoPlay: false,
      );
      LogUtil.i('6. VLC控制器创建完成，初始状态：${_newController?.value.toString()}');
    } catch (e) {
      LogUtil.e('5.2 VLC控制器创建失败: $e');
      rethrow;
    }

    void controllerListener() {
      LogUtil.i('7. 进入控制器监听回调');
      if (_isDisposing) {
        LogUtil.i('8. 播放器正在释放中，忽略状态更新');
        return;
      }
      
      final value = _newController?.value;
      LogUtil.i('9. VLC当前状态: ' + 
        'playingState=${value?.playingState}, ' +
        'isInitialized=${value?.isInitialized}, ' +
        'isBuffering=${value?.isBuffering}, ' +
        'hasError=${value?.hasError}, ' +
        'position=${value?.position}, ' +
        'duration=${value?.duration}, ' +
        'size=${value?.size}, ' +
        'aspectRatio=${value?.aspectRatio}, ' +
        'playbackSpeed=${value?.playbackSpeed}, ' +
        'isPlaying=${value?.isPlaying}');

      if (value?.hasError == true) {
        LogUtil.e('10. VLC播放器错误: ' +
          '错误描述: ${value?.errorDescription}, ' +
          '播放状态: ${value?.playingState}, ' +
          '初始化状态: ${value?.isInitialized}');
        if (!_initCompleter!.isCompleted) {
          LogUtil.i('11. 初始化未完成，报告错误');
          _initCompleter!.completeError(value?.errorDescription ?? '未知错误');
        }
        _handleError(value?.errorDescription ?? '未知错误');
        return;
      }

      if (!_initCompleter!.isCompleted) {
        LogUtil.i('12. 检查初始化状态');
        if (value?.isInitialized == true) {
          LogUtil.i('13. 播放器初始化完成');
          _state.isInitialized = true;
          _initCompleter!.complete();
        } else if (value?.playingState == PlayingState.buffering) {
          LogUtil.i('14. 播放器正在缓冲');
          _state.isBuffering = true;
          _state.bufferingNotifier.value = true;
        } else {
          LogUtil.i('15. 播放器当前状态: ' +
            '播放状态=${value?.playingState}, ' +
            '是否初始化=${value?.isInitialized}');
        }
      }
    }

    LogUtil.i('16. 准备添加控制器监听器');
    try {
      _newController?.addListener(controllerListener);
      LogUtil.i('17. 控制器监听器添加完成');
    } catch (e) {
      LogUtil.e('17.1 添加监听器失败: $e');
    }

    _controller = _newController;
    LogUtil.i('18. 控制器赋值完成');
      
    LogUtil.i('19. 重置播放器状态');
    _state.isInitialized = false;
    _state.hasError = false;
    _state.errorMessage = null;
    _state.errorNotifier.value = null;

    LogUtil.i('20. 设置初始化超时检查，超时时间: ${timeout.inSeconds}秒');
    _initializationTimer = Timer(timeout, () {
      LogUtil.i('21. 超时检查触发，当前状态: ' +
        'isInitialized=${_state.isInitialized}, ' +
        'isCompleted=${_initCompleter?.isCompleted}, ' + 
        '控制器Value=${_newController?.value.toString()}');
          
      if (!_state.isInitialized && !_initCompleter!.isCompleted) {
        LogUtil.i('22. 播放器初始化超时，准备报告错误');
        _initCompleter!.completeError(TimeoutException('播放器初始化超时'));
        _handleError('播放器初始化超时');
      }
    });

    LogUtil.i('23. 等待初始化完成');
    try {
      await _initCompleter!.future;
      
      if (_controller != null && _controller!.value.isInitialized) {
        LogUtil.i('24. 设置播放器音量和速度');
        await _controller!.setVolume(100);
        await _controller!.setPlaybackSpeed(1.0);
        LogUtil.i('25. 播放器初始化完全完成');
        return true;
      }
      
      throw Exception('播放器初始化失败');
    } catch (e) {
      LogUtil.e('26. 等待初始化完成时出错: $e');
      rethrow;
    }

  } catch (e, stackTrace) {
    LogUtil.logError('27. 初始化失败', e, stackTrace);
    _handleError('初始化失败: $e', onError);
    return false;
  } finally {
    LogUtil.i('28. 清理初始化计时器');
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
       
       try {
         // 移除监听器
         currentController.removeListener(() {});

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

     // 清理 newController
     if (_newController != null) {
       try {
         await _newController!.dispose();
       } catch (e) {
         LogUtil.e('释放临时控制器时出错: $e');
       }
       _newController = null;
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
