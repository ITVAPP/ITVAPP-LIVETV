import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import '../gradient_progress_bar.dart';

/// 播放器配置工具类
class BetterPlayerConfig {
  /// 创建播放器数据源配置
  ///
  /// 参数说明：
  /// - [url]: 视频播放地址
  /// - [isHls]: 是否为 HLS 格式（直播流）
  /// - [headers]: 自定义请求头（可选）
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
  }) {
    return BetterPlayerDataSource(
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
        minBufferMs: 10000, // 最小缓冲时间，单位毫秒（10秒）
        maxBufferMs: 60000, // 最大缓冲时间，单位毫秒（60秒）
        bufferForPlaybackMs: 5000, // 播放前的最小缓冲时间，单位毫秒（5秒）
        bufferForPlaybackAfterRebufferMs: 5000, // 重缓冲后的最小播放缓冲时间
      ),
      // 缓存配置
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls, // 非 HLS 启用缓存（直播流缓存可能导致中断）
        preCacheSize: 10 * 1024 * 1024, // 预缓存大小（10MB）
        maxCacheSize: 300 * 1024 * 1024, // 缓存总大小限制（300MB）
        maxCacheFileSize: 30 * 1024 * 1024, // 单个缓存文件大小限制（30MB）
      ),
      // 请求头设置，提供默认 User-Agent
      headers: headers ?? {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
      },
    );
  }

  /// 创建播放器基本配置
  ///
  /// 参数说明：
  /// - [toastString]: 显示提示信息的字符串
  /// - [eventListener]: 事件监听器
  /// - [placeholderAsset]: 占位图片资源路径（默认使用本地图片）
  /// - [bufferProgress]: 缓冲进度值，范围 0.0 - 1.0
  static BetterPlayerConfiguration createPlayerConfig({
    required String toastString,
    required Function(BetterPlayerEvent) eventListener,
    String placeholderAsset = 'assets/images/video_bg.png',
    double bufferProgress = 0.0,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 播放器内容适应模式（保持比例缩放）
      autoPlay: false, // 是否自动播放
      looping: true, // 是否循环播放
      allowedScreenSleep: false, // 禁止屏幕休眠
      autoDispose: false, // 禁止自动释放资源
      expandToFill: true, // 是否填充剩余空间
      handleLifecycle: true, // 是否处理生命周期事件（例如暂停/恢复）
      // 错误界面构建器（此处使用空白组件）
      errorBuilder: (BuildContext context, String? errorMessage) {
        return const SizedBox.shrink();
      },
      // 设置播放器占位图片
      placeholder: Image.asset(
        placeholderAsset, // 图片资源路径
        fit: BoxFit.cover, // 图片填充方式
      ),
      // 配置控制栏行为
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false, // 禁用默认控制
        // 自定义控制栏构建器
        customControlsBuilder: (BetterPlayerController controller, Function(bool) onControlsVisibilityChanged) {
          return CustomVideoControls(
            controller: controller,
            toastString: toastString,
            bufferProgress: bufferProgress,
          );
        },
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

/// 视频播放器自定义控件
class CustomVideoControls extends StatelessWidget {
  final BetterPlayerController controller;
  final String toastString;
  final double bufferProgress;  // 缓冲进度值，范围 0.0 - 1.0

  const CustomVideoControls({
    Key? key,
    required this.controller,
    required this.toastString,
    this.bufferProgress = 0.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 检测当前设备方向
        final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        final mediaQuery = MediaQuery.of(context);

        // 根据方向调整进度条宽度
        final progressBarWidth = isPortrait
            ? mediaQuery.size.width * 0.5
            : mediaQuery.size.width * 0.3;

        // 设置文本样式
        final textStyle = TextStyle(
          color: Colors.white,
          fontSize: isPortrait ? 16 : 18,
        );

        return Stack(
          children: [
            // 缓冲状态显示
            Positioned.fill(
              child: Center(
                // 使用父组件传入的 toastString 来控制显示状态
                child: toastString != "HIDE_CONTAINER"
                    ? _BufferingContainer(
                        isPortrait: isPortrait,
                        progressBarWidth: progressBarWidth,
                        textStyle: textStyle,
                        toastString: toastString,
                        progress: bufferProgress,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 缓冲状态显示容器
class _BufferingContainer extends StatelessWidget {
  final bool isPortrait;
  final double progressBarWidth;
  final TextStyle textStyle;
  final String toastString;
  final double progress;  // 缓冲进度值，范围 0.0 - 1.0

  const _BufferingContainer({
    Key? key,
    required this.isPortrait,
    required this.progressBarWidth,
    required this.textStyle,
    required this.toastString,
    required this.progress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26, // 半透明背景
        borderRadius: const BorderRadius.all(Radius.circular(8)), // 圆角边框
      ),
      padding: EdgeInsets.symmetric(
        vertical: isPortrait ? 12 : 15, // 竖屏和横屏的垂直内边距
        horizontal: isPortrait ? 16 : 20, // 竖屏和横屏的水平内边距
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 组件大小适配内容
        children: [
          // 渐变进度条
          GradientProgressBar(
            width: progressBarWidth, // 进度条宽度
            height: 5, // 进度条高度
            progress: progress, // 传入缓冲进度值
          ),
          SizedBox(height: isPortrait ? 8 : 10), // 添加间距
          Text(
            toastString, // 提示信息
            style: textStyle, // 应用样式
            textAlign: TextAlign.center, // 居中对齐
          ),
        ],
      ),
    );
  }
}
