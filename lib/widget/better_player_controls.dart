import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import '../util/log_util.dart';
import '../gradient_progress_bar.dart';

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
  /// - [url]: 视频播放地址
  /// - [isHls]: 是否为 HLS 格式（直播流）
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
  static BetterPlayerConfiguration createPlayerConfig({
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 播放器内容适应模式（保持比例缩放）
      autoPlay: false, // 自动播放
      looping: true, // 循环播放
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
        showControls: false, // 禁用默认控制
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