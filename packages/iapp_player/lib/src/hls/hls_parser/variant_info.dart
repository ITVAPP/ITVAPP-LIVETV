import 'package:flutter/material.dart';

class VariantInfo {
  VariantInfo({
    this.bitrate,
    this.videoGroupId,
    this.audioGroupId,
    this.subtitleGroupId,
    this.captionGroupId,
  });

  /// EXT-X-STREAM-INF 标签声明的比特率
  final int? bitrate;

  /// EXT-X-STREAM-INF 标签中定义的 VIDEO 值，如果 VIDEO 属性不存在则为 null
  final String? videoGroupId;

  /// EXT-X-STREAM-INF 标签中定义的 AUDIO 值，如果 AUDIO 属性不存在则为 null
  final String? audioGroupId;

  /// EXT-X-STREAM-INF 标签中定义的 SUBTITLES 值，如果 SUBTITLES 属性不存在则为 null
  final String? subtitleGroupId;

  /// EXT-X-STREAM-INF 标签中定义的 CLOSED-CAPTIONS 值，如果 CLOSED-CAPTIONS 属性不存在则为 null
  final String? captionGroupId;

  @override
  bool operator ==(dynamic other) {
    if (other is VariantInfo) {
      return other.bitrate == bitrate &&
          other.videoGroupId == videoGroupId &&
          other.audioGroupId == audioGroupId &&
          other.subtitleGroupId == subtitleGroupId &&
          other.captionGroupId == captionGroupId;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(
      bitrate, videoGroupId, audioGroupId, subtitleGroupId, captionGroupId);
}
