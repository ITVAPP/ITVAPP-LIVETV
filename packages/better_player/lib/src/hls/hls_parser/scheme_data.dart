import 'dart:typed_data';

import 'package:flutter/material.dart';

class SchemeData {
  SchemeData({
//    @required this.uuid,
    this.licenseServerUrl,
    required this.mimeType,
    this.data,
    this.requiresSecureDecryption,
  });

//  /// DRM方案的uuid，如果数据是通用的（即适用于所有方案）则为null
//  final String uuid;

  /// 应向其发出许可证请求的服务器URL。如果未知则可能为null
  final String? licenseServerUrl;

  /// [data] 的MIME类型
  final String mimeType;

  /// 初始化基础数据
  final Uint8List? data;

  /// 是否需要安全解密
  final bool? requiresSecureDecryption;

  SchemeData copyWithData(Uint8List? data) => SchemeData(
//        uuid: uuid,
        licenseServerUrl: licenseServerUrl,
        mimeType: mimeType,
        data: data,
        requiresSecureDecryption: requiresSecureDecryption,
      );

  @override
  bool operator ==(dynamic other) {
    if (other is SchemeData) {
      return other.mimeType == mimeType &&
          other.licenseServerUrl == licenseServerUrl &&
//          other.uuid == uuid &&
          other.requiresSecureDecryption == requiresSecureDecryption &&
          other.data == data;
    }

    return false;
  }

  @override
  int get hashCode => Object.hash(
      /*uuid, */
      licenseServerUrl,
      mimeType,
      data,
      requiresSecureDecryption);
}
