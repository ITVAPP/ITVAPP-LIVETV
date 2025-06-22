import 'package:flutter/material.dart';

/// 字幕配置 - 字体、颜色、边距等
class IAppPlayerSubtitlesConfiguration {
  /// 字幕字体大小
  final double fontSize;

  /// 字幕字体颜色
  final Color fontColor;

  /// 启用文本描边
  final bool outlineEnabled;

  /// 描边颜色
  final Color outlineColor;

  /// 描边大小
  final double outlineSize;

  /// 字幕字体家族
  final String fontFamily;

  /// 字幕左侧边距
  final double leftPadding;

  /// 字幕右侧边距
  final double rightPadding;

  /// 字幕底部边距
  final double bottomPadding;

  /// 字幕对齐方式
  final Alignment alignment;

  /// 字幕背景颜色
  final Color backgroundColor;

  const IAppPlayerSubtitlesConfiguration({
    this.fontSize = 14,
    this.fontColor = Colors.white,
    this.outlineEnabled = true,
    this.outlineColor = Colors.black,
    this.outlineSize = 2.0,
    this.fontFamily = "Roboto",
    this.leftPadding = 8.0,
    this.rightPadding = 8.0,
    this.bottomPadding = 20.0,
    this.alignment = Alignment.center,
    this.backgroundColor = Colors.transparent,
  });
}
