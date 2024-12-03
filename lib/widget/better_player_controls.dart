import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import '../util/log_util.dart';

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
  /// - [url]: 视频播放地址（单个URL或用"|"分隔的多个URL）
  /// - [isHls]: 是否为 HLS 格式（直播流）
  /// - [headers]: 自定义请求头，为空时使用默认User-Agent
  static BetterPlayerDataSource createDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
  }) {
    // 检查是否包含分隔符"|"
    if (url.contains("|")) {
      // 分割URL并清理空值和空格
      List<String> urls = url
          .split("|")
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // 如果清理后没有有效URL，返回空数据源
      if (urls.isEmpty) {
        LogUtil.e('没有有效的播放地址');
        return BetterPlayerDataSource(BetterPlayerDataSourceType.network, '');
      }

      // 如果只有一个URL，使用单URL方式
      if (urls.length == 1) {
        return _createSingleDataSource(
          url: urls.first,
          isHls: isHls,
          headers: headers,
        );
      }

      // 创建播放列表数据源，第一个URL作为主源，其余URL作为播放列表
      return _createSingleDataSource(
        url: urls.first,
        isHls: isHls,
        headers: headers,
        playlist: urls.skip(1).toList(),
      );
    }

    // 没有分隔符，使用原来的单URL逻辑
    return _createSingleDataSource(
      url: url,
      isHls: isHls,
      headers: headers,
    );
  }

  /// 创建单个数据源的辅助方法
  /// - [url]: 视频播放地址
  /// - [isHls]: 是否为 HLS 格式（直播流）
  /// - [headers]: 自定义请求头，为空时使用默认User-Agent
  /// - [playlist]: 播放列表URLs，仅在多URL模式下使用
  static BetterPlayerDataSource _createSingleDataSource({
    required String url,
    required bool isHls,
    Map<String, String>? headers,
    List<String>? playlist,
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: isHls,  // HLS模式下启用直播流支持
      useAsmsTracks: isHls,  // HLS模式下启用自适应流
      useAsmsAudioTracks: isHls,  // HLS模式下启用音频流切换
      useAsmsSubtitles: false,  // 禁用字幕以优化性能
      // 配置系统通知栏行为（禁用通知栏播放控制）
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
      // 缓冲配置：优化播放流畅度
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 10000,  // 最小缓冲时间（10秒）
        maxBufferMs: 60000,  // 最大缓冲时间（60秒）
        bufferForPlaybackMs: 5000,  // 开始播放所需的最小缓冲（5秒）
        bufferForPlaybackAfterRebufferMs: 5000,  // 重新缓冲后开始播放所需的最小缓冲（5秒）
      ),
      // 缓存配置：优化播放性能和流量使用
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: !isHls,  // 非HLS模式下启用缓存
        preCacheSize: 10 * 1024 * 1024,  // 预缓存大小（10MB）
        maxCacheSize: 300 * 1024 * 1024,  // 最大缓存大小（300MB）
        maxCacheFileSize: 30 * 1024 * 1024,  // 单个文件最大缓存（30MB）
      ),
      // 请求头设置：提供默认User-Agent或使用自定义headers
      headers: headers ?? {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
      },
      playlist: playlist,  // 可选的播放列表URLs
    );
  }

  /// 创建播放器基本配置
  /// - [eventListener]: 播放器事件监听器，用于处理播放状态变化等事件
  static BetterPlayerConfiguration createPlayerConfig({
    required Function(BetterPlayerEvent) eventListener,
  }) {
    return BetterPlayerConfiguration(
      fit: BoxFit.contain,  // 播放器内容适应模式（保持比例缩放）
      autoPlay: false,  // 禁用自动播放
      looping: true,  // 启用循环播放
      allowedScreenSleep: false,  // 禁止屏幕休眠
      autoDispose: false,  // 禁用自动释放资源
      expandToFill: true,  // 允许填充剩余空间
      handleLifecycle: true,  // 启用生命周期管理
      // 错误界面构建器（使用背景图片）
      errorBuilder: (_, __) => _backgroundImage,
      // 设置播放器占位图片
      placeholder: _backgroundImage,
      // 配置控制栏行为（禁用默认控制）
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false,
      ),
      // 全屏模式下允许的设备方向
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
