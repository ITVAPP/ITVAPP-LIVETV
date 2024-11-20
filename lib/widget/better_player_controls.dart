import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import '../gradient_progress_bar.dart';

/// 播放器配置工具类
class BetterPlayerConfig {
  /// 创建播放器数据源配置
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: isHls,          // 根据URL判断是否为直播流
      useAsmsTracks: isHls,       // 不是 HLS 时关闭 
      useAsmsAudioTracks: isHls,    // 不是 HLS 时关闭
      useAsmsSubtitles: false,    // 禁用字幕减少开销
      // 禁用系统通知栏的播放控制
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 10000,            // 最小缓冲时间(10秒)
        maxBufferMs: 60000,           // 最大缓冲时间(60秒)
        bufferForPlaybackMs: 5000,     // 开始播放所需的最小缓冲(5秒)
        bufferForPlaybackAfterRebufferMs: 5000 // 重新缓冲后开始播放所需的最小缓冲(5秒)
      ),
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls,                // 启用缓存，YouTube 和 HLS 时关闭 否则播放直播流有中断问题
        preCacheSize: 10 * 1024 * 1024, // 预缓存大小
        maxCacheSize: 300 * 1024 * 1024, // 最大缓存大小
        maxCacheFileSize: 30 * 1024 * 1024, // 单个文件最大缓存大小
      ),
      headers: headers ?? {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
      },
    );
  }

  /// 创建播放器基本配置
  static BetterPlayerConfiguration createPlayerConfig({
    required String toastString,
    required Function(BetterPlayerEvent) eventListener,
    String placeholderAsset = 'assets/images/video_bg.png',
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain,        // 自动缩放
      autoPlay: false,              // 自动播放
      looping: true,        // 开启循环播放
      allowedScreenSleep: false,   // 禁止屏幕休眠
      autoDispose: false,         // 自动释放资源
      expandToFill: true,         //  自动填充剩余空间
      handleLifecycle: true,     // 自动处理生命周期事件
      // 禁用错误处理UI
      errorBuilder: (BuildContext context, String? errorMessage) {
         return const SizedBox.shrink();
      },
      // 添加背景图片
      placeholder: Image.asset(
        placeholderAsset,  // 图片资源路径
        fit: BoxFit.cover,              // 图片填充方式
      ),
      // 只开启缓冲进度控件
      controlsConfiguration: BetterPlayerControlsConfiguration(
        // 控制栏颜色和样式
        controlBarColor: Colors.transparent,  
        backgroundColor: Colors.transparent,
        textColor: Colors.white,             
        iconsColor: Colors.white,            
        // 功能开关
        showControls: true,                  
        enableFullscreen: false,             
        enableMute: false,                   
        enableProgressText: false,           
        enableProgressBar: false,            
        enableProgressBarDrag: false,        
        enablePlayPause: false,              
        enableSkips: false,                  
        enableOverflowMenu: false,           
        enablePlaybackSpeed: false,          
        enableSubtitles: false,              
        enableQualities: false,              
        enablePip: false,                    
        enableRetry: false,                  
        enableAudioTracks: false, 
        // 其他设置
        controlsHideTime: const Duration(seconds: 3),       
        showControlsOnInitialize: false,                
        overflowMenuCustomItems: const [],            
        // 自定义控件构建器
        customControlsBuilder: (controller) {
          return CustomVideoControls(
            controller: controller,
            toastString: toastString,
          );
        },
      ),
      // 全屏后支持的设备方向
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ],
      // 设置事件监听器
      eventListener: eventListener,
    );
  }
}

/// 视频播放器自定义控件
class CustomVideoControls extends StatelessWidget {
  final BetterPlayerController controller;
  final String toastString;

  const CustomVideoControls({
    Key? key,
    required this.controller,
    required this.toastString,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        final mediaQuery = MediaQuery.of(context);
        
        // 计算进度条宽度
        final progressBarWidth = isPortrait 
            ? mediaQuery.size.width * 0.5 
            : mediaQuery.size.width * 0.3;
            
        // 文本样式
        final textStyle = TextStyle(
          color: Colors.white,
          fontSize: isPortrait ? 16 : 18,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: ValueListenableBuilder<bool>(
                  valueListenable: controller.bufferingNotifier,
                  builder: (context, isBuffering, child) {
                    if ((isBuffering || !controller.isVideoInitialized()) && 
                        toastString != "HIDE_CONTAINER") {
                      return _BufferingContainer(
                        isPortrait: isPortrait,
                        progressBarWidth: progressBarWidth,
                        textStyle: textStyle,
                        toastString: toastString,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ],
        );
      }
    );
  }
}

/// 缓冲状态显示容器
class _BufferingContainer extends StatelessWidget {
  final bool isPortrait;
  final double progressBarWidth;
  final TextStyle textStyle;
  final String toastString;

  const _BufferingContainer({
    Key? key,
    required this.isPortrait,
    required this.progressBarWidth,
    required this.textStyle,
    required this.toastString,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      padding: EdgeInsets.symmetric(
        vertical: isPortrait ? 12 : 15,
        horizontal: isPortrait ? 16 : 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientProgressBar(
            width: progressBarWidth,
            height: 5,
          ),
          SizedBox(height: isPortrait ? 8 : 10),
          Text(
            toastString,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
