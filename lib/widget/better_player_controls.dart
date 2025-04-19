import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

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
    // 使用 HeadersConfig 生成默认 headers
    final defaultHeaders = HeadersConfig.generateHeaders(url: url);

    // 合并 defaultHeaders 和传入的 headers
    final mergedHeaders = {...defaultHeaders, ...?headers};
    
    // 检测是否为RTMP流
    final bool isRtmp = url.toLowerCase().startsWith('rtmp://');
    
    // 为RTMP流添加格式提示
    final Map<String, dynamic> formatHint = isRtmp 
        ? {"format": "rtmp"} 
        : {};

    // 提取公共的 BetterPlayerDataSource 配置
    final baseDataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: isHls, // 根据调用方设置的isHls参数决定是否为直播流
      useAsmsTracks: isHls && !isRtmp, // RTMP流不使用ASMS轨道
      useAsmsAudioTracks: isHls && !isRtmp, // RTMP流不使用ASMS音轨
      useAsmsSubtitles: false, // 禁用字幕以降低播放开销
      // 配置系统通知栏行为（此处关闭通知栏播放控制）
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
      // 缓冲配置
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 5000, // 5 秒
        maxBufferMs: 20000, // 20 秒
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      // 缓存配置
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls && !isRtmp, // RTMP流不使用缓存
        preCacheSize: 20 * 1024 * 1024, // 预缓存大小（20MB）
        maxCacheSize: 300 * 1024 * 1024, // 缓存总大小限制（300MB）
        maxCacheFileSize: 50 * 1024 * 1024, // 单个缓存文件大小限制（50MB）
      ),
      // 添加格式提示
      formatHint: formatHint,
    );

    // 根据 mergedHeaders 是否为空返回实例
    return mergedHeaders.isNotEmpty
        ? BetterPlayerDataSource(
            baseDataSource.type,
            baseDataSource.url,
            liveStream: baseDataSource.liveStream,
            useAsmsTracks: baseDataSource.useAsmsTracks,
            useAsmsAudioTracks: baseDataSource.useAsmsAudioTracks,
            useAsmsSubtitles: baseDataSource.useAsmsSubtitles,
            notificationConfiguration: baseDataSource.notificationConfiguration,
            bufferingConfiguration: baseDataSource.bufferingConfiguration,
            cacheConfiguration: baseDataSource.cacheConfiguration,
            headers: mergedHeaders, // 包含 headers
            formatHint: formatHint, // 添加RTMP格式提示
          )
        : baseDataSource; // 不包含 headers，直接使用基础配置
  }

  /// 创建播放器基本配置
  static BetterPlayerConfiguration createPlayerConfig({
    required bool isHls,
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain, // 播放器内容适应模式（保持比例缩放）
      autoPlay: false, // 自动播放
      looping: isHls, // 是HLS时循环播放
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
        showControls: false,  // 不显示控制器
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
