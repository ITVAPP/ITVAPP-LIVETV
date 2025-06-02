import 'package:better_player/src/configuration/better_player_buffering_configuration.dart';
import 'package:better_player/src/configuration/better_player_data_source_type.dart';
import 'package:better_player/src/configuration/better_player_drm_configuration.dart';
import 'package:better_player/src/configuration/better_player_notification_configuration.dart';
import 'package:better_player/src/configuration/better_player_video_format.dart';
import 'package:better_player/src/subtitles/better_player_subtitles_source.dart';
import 'package:flutter/widgets.dart';
import 'better_player_cache_configuration.dart';

/// Better Player数据源配置，定义视频源及相关设置
class BetterPlayerDataSource {
  /// 数据源类型（网络、文件、内存）
  final BetterPlayerDataSourceType type;

  /// 视频URL
  final String url;

  /// 字幕配置列表
  final List<BetterPlayerSubtitlesSource>? subtitles;

  /// 是否为直播流，默认为false
  final bool? liveStream;

  /// 自定义请求头
  final Map<String, String>? headers;

  /// 是否启用HLS/DASH字幕，默认为true
  final bool? useAsmsSubtitles;

  /// 是否启用HLS轨道，默认为true
  final bool? useAsmsTracks;

  /// 是否启用HLS/DASH音频轨道，默认为true
  final bool? useAsmsAudioTracks;

  /// 轨道名称列表，默认为根据轨道参数自动生成
  final List<String>? asmsTrackNames;

  /// 非HLS/DASH视频的分辨率映射，格式为{"分辨率": "URL"}
  final Map<String, String>? resolutions;

  /// 网络数据源缓存配置
  final BetterPlayerCacheConfiguration? cacheConfiguration;

  /// 内存数据源的字节列表，内存模式下不可为空
  final List<int>? bytes;

  /// 远程通知配置，默认为不显示
  final BetterPlayerNotificationConfiguration? notificationConfiguration;

  /// 覆盖原始视频时长的自定义时长
  final Duration? overriddenDuration;

  /// 视频格式提示，用于无有效扩展名的URL
  final BetterPlayerVideoFormat? videoFormat;

  /// 视频扩展名（不含点）
  final String? videoExtension;

  /// 内容保护（DRM）配置
  final BetterPlayerDrmConfiguration? drmConfiguration;

  /// 视频加载或播放前的占位组件
  final Widget? placeholder;

  /// 视频缓冲配置，仅Android支持，默认为空配置
  final BetterPlayerBufferingConfiguration bufferingConfiguration;

  BetterPlayerDataSource(
    this.type,
    this.url, {
    this.bytes,
    this.subtitles,
    this.liveStream = false,
    this.headers,
    this.useAsmsSubtitles = true,
    this.useAsmsTracks = true,
    this.useAsmsAudioTracks = true,
    this.asmsTrackNames,
    this.resolutions,
    this.cacheConfiguration,
    this.notificationConfiguration =
        const BetterPlayerNotificationConfiguration(
      showNotification: false,
    ),
    this.overriddenDuration,
    this.videoFormat,
    this.videoExtension,
    this.drmConfiguration,
    this.placeholder,
    this.bufferingConfiguration = const BetterPlayerBufferingConfiguration(),
  }) : assert(
            (type == BetterPlayerDataSourceType.network ||
                    type == BetterPlayerDataSourceType.file) ||
                (type == BetterPlayerDataSourceType.memory &&
                    bytes?.isNotEmpty == true),
            "网络或文件数据源的URL不可为空，内存数据源的字节列表不可为空");

  /// 构建网络数据源，基于URL
  factory BetterPlayerDataSource.network(
    String url, {
    List<BetterPlayerSubtitlesSource>? subtitles,
    bool? liveStream,
    Map<String, String>? headers,
    bool? useAsmsSubtitles,
    bool? useAsmsTracks,
    bool? useAsmsAudioTracks,
    Map<String, String>? qualities,
    BetterPlayerCacheConfiguration? cacheConfiguration,
    BetterPlayerNotificationConfiguration notificationConfiguration =
        const BetterPlayerNotificationConfiguration(showNotification: false),
    Duration? overriddenDuration,
    BetterPlayerVideoFormat? videoFormat,
    BetterPlayerDrmConfiguration? drmConfiguration,
    Widget? placeholder,
    BetterPlayerBufferingConfiguration bufferingConfiguration =
        const BetterPlayerBufferingConfiguration(),
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      subtitles: subtitles,
      liveStream: liveStream,
      headers: headers,
      useAsmsSubtitles: useAsmsSubtitles,
      useAsmsTracks: useAsmsTracks,
      useAsmsAudioTracks: useAsmsAudioTracks,
      resolutions: qualities,
      cacheConfiguration: cacheConfiguration,
      notificationConfiguration: notificationConfiguration,
      overriddenDuration: overriddenDuration,
      videoFormat: videoFormat,
      drmConfiguration: drmConfiguration,
      placeholder: placeholder,
      bufferingConfiguration: bufferingConfiguration,
    );
  }

  /// 构建文件数据源，基于URL
  factory BetterPlayerDataSource.file(
    String url, {
    List<BetterPlayerSubtitlesSource>? subtitles,
    bool? useAsmsSubtitles,
    bool? useAsmsTracks,
    Map<String, String>? qualities,
    BetterPlayerCacheConfiguration? cacheConfiguration,
    BetterPlayerNotificationConfiguration? notificationConfiguration,
    Duration? overriddenDuration,
    Widget? placeholder,
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.file,
      url,
      subtitles: subtitles,
      useAsmsSubtitles: useAsmsSubtitles,
      useAsmsTracks: useAsmsTracks,
      resolutions: qualities,
      cacheConfiguration: cacheConfiguration,
      notificationConfiguration: notificationConfiguration =
          const BetterPlayerNotificationConfiguration(showNotification: false),
      overriddenDuration: overriddenDuration,
      placeholder: placeholder,
    );
  }

  /// 构建内存数据源，基于字节列表
  factory BetterPlayerDataSource.memory(
    List<int> bytes, {
    String? videoExtension,
    List<BetterPlayerSubtitlesSource>? subtitles,
    bool? useAsmsSubtitles,
    bool? useAsmsTracks,
    Map<String, String>? qualities,
    BetterPlayerCacheConfiguration? cacheConfiguration,
    BetterPlayerNotificationConfiguration? notificationConfiguration,
    Duration? overriddenDuration,
    Widget? placeholder,
  }) {
    return BetterPlayerDataSource(
      BetterPlayerDataSourceType.memory,
      "",
      videoExtension: videoExtension,
      bytes: bytes,
      subtitles: subtitles,
      useAsmsSubtitles: useAsmsSubtitles,
      useAsmsTracks: useAsmsTracks,
      resolutions: qualities,
      cacheConfiguration: cacheConfiguration,
      notificationConfiguration: notificationConfiguration =
          const BetterPlayerNotificationConfiguration(showNotification: false),
      overriddenDuration: overriddenDuration,
      placeholder: placeholder,
    );
  }

  /// 创建数据源副本，仅更新指定属性，无变化时返回原实例以优化性能
  BetterPlayerDataSource copyWith({
    BetterPlayerDataSourceType? type,
    String? url,
    List<int>? bytes,
    List<BetterPlayerSubtitlesSource>? subtitles,
    bool? liveStream,
    Map<String, String>? headers,
    bool? useAsmsSubtitles,
    bool? useAsmsTracks,
    bool? useAsmsAudioTracks,
    Map<String, String>? resolutions,
    BetterPlayerCacheConfiguration? cacheConfiguration,
    BetterPlayerNotificationConfiguration? notificationConfiguration =
        const BetterPlayerNotificationConfiguration(showNotification: false),
    Duration? overriddenDuration,
    BetterPlayerVideoFormat? videoFormat,
    String? videoExtension,
    BetterPlayerDrmConfiguration? drmConfiguration,
    Widget? placeholder,
    BetterPlayerBufferingConfiguration? bufferingConfiguration =
        const BetterPlayerBufferingConfiguration(),
  }) {
    /// 检查是否有实际变化，无变化则返回当前实例
    if (type == null &&
        url == null &&
        bytes == null &&
        subtitles == null &&
        liveStream == null &&
        headers == null &&
        useAsmsSubtitles == null &&
        useAsmsTracks == null &&
        useAsmsAudioTracks == null &&
        resolutions == null &&
        cacheConfiguration == null &&
        notificationConfiguration == null &&
        overriddenDuration == null &&
        videoFormat == null &&
        videoExtension == null &&
        drmConfiguration == null &&
        placeholder == null &&
        bufferingConfiguration == null) {
      return this;
    }

    return BetterPlayerDataSource(
      type ?? this.type,
      url ?? this.url,
      bytes: bytes ?? this.bytes,
      subtitles: subtitles ?? this.subtitles,
      liveStream: liveStream ?? this.liveStream,
      headers: headers ?? this.headers,
      useAsmsSubtitles: useAsmsSubtitles ?? this.useAsmsSubtitles,
      useAsmsTracks: useAsmsTracks ?? this.useAsmsTracks,
      useAsmsAudioTracks: useAsmsAudioTracks ?? this.useAsmsAudioTracks,
      resolutions: resolutions ?? this.resolutions,
      cacheConfiguration: cacheConfiguration ?? this.cacheConfiguration,
      notificationConfiguration:
          notificationConfiguration ?? this.notificationConfiguration,
      overriddenDuration: overriddenDuration ?? this.overriddenDuration,
      videoFormat: videoFormat ?? this.videoFormat,
      videoExtension: videoExtension ?? this.videoExtension,
      drmConfiguration: drmConfiguration ?? this.drmConfiguration,
      placeholder: placeholder ?? this.placeholder,
      bufferingConfiguration:
          bufferingConfiguration ?? this.bufferingConfiguration,
    );
  }
}
