import 'package:iapp_player/src/hls/hls_parser/variant_info.dart';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';

class HlsTrackMetadataEntry {
  HlsTrackMetadataEntry({this.groupId, this.name, this.variantInfos});

  /// 如果轨道来源于 EXT-X-MEDIA 标签，则为该轨道的 GROUP-ID 值。如果轨道不是来源于 EXT-X-MEDIA 标签则为 null
  final String? groupId;

  /// 如果轨道来源于 EXT-X-MEDIA 标签，则为该轨道的 NAME 值。如果轨道不是来源于 EXT-X-MEDIA 标签则为 null
  final String? name;

  /// 与该轨道关联的 EXT-X-STREAM-INF 标签属性。如果该轨道来源于 EXT-X-MEDIA 标签，则此字段不适用（因此为空）
  final List<VariantInfo>? variantInfos;

  @override
  bool operator ==(dynamic other) {
    if (other is HlsTrackMetadataEntry) {
      return other.groupId == groupId &&
          other.name == name &&
          const ListEquality<VariantInfo>()
              .equals(other.variantInfos, variantInfos);
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(groupId, name, variantInfos);
}
