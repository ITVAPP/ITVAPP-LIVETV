import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';

import 'scheme_data.dart';

class DrmInitData {
  DrmInitData({this.schemeType, this.schemeData = const []});

  /// DRM方案数据列表
  final List<SchemeData> schemeData;
  
  /// DRM方案类型
  final String? schemeType;

  @override
  bool operator ==(dynamic other) {
    if (other is DrmInitData) {
      return schemeType == other.schemeType &&
          const ListEquality<SchemeData>().equals(other.schemeData, schemeData);
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(schemeType, schemeData);
}
