import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// 可滚动的Toast消息组件，支持文本超出容器宽度时自动滚动
/// 添加半透明背景和自适应宽度，使用Marquee实现滚动效果
class ScrollingToastMessage extends StatefulWidget {
  final String message; // 提示消息内容
  final double containerWidth; // 外部容器宽度，用于计算最大宽度和判断是否滚动
  final bool isLandscape; // 是否横屏，调整文字样式
  final Duration animationDuration; // 滚动动画时长
  final Curve animationCurve; // 滚动动画曲线
  
  const ScrollingToastMessage({
    Key? key,
    required this.message,
    required this.containerWidth,
    this.isLandscape = true,
    this.animationDuration = const Duration(seconds: 10),
    this.animationCurve = Curves.linear,
  }) : super(key: key);
  
  @override
  State<ScrollingToastMessage> createState() => _ScrollingToastMessageState();
}

class _ScrollingToastMessageState extends State<ScrollingToastMessage> {
  double? _textWidth; // 文本宽度，缓存计算结果
  bool _needsScroll = false; // 是否需要滚动标记
  
  // 文字样式常量，提高性能
  static const _TEXT_PADDING = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
  static const _BACKGROUND_OPACITY = 0.5;
  static const _BACKGROUND_COLOR = Colors.black;
  static const _BORDER_RADIUS = 16.0;
  static const _MAX_WIDTH_FACTOR = 0.8; // 最大宽度为容器宽度的80%
  static const _SCROLL_VELOCITY = 38.0; // 匹配ad_manager中的滚动速度
  // 不设置滚动循环次数，允许无限滚动
  
  /// 文字阴影配置常量，提升复用性
  static const _shadowConfig = Shadow(
    offset: Offset(1.0, 1.0),
    blurRadius: 3.0,
    color: Color.fromRGBO(0, 0, 0, 0.7),
  );
  
  /// 根据屏幕方向动态生成文字样式
  TextStyle get _textStyle => TextStyle(
    color: Colors.white,
    fontSize: widget.isLandscape ? 18.0 : 16.0,
    shadows: [
      _shadowConfig,
      Shadow(
        offset: Offset(-_shadowConfig.offset.dx, -_shadowConfig.offset.dy),
        blurRadius: _shadowConfig.blurRadius,
        color: _shadowConfig.color,
      ),
    ],
  );
  
  @override
  void initState() {
    super.initState();
    _measureText(); // 计算文本宽度并判断是否滚动
  }
  
  /// 测量文本宽度并缓存，确定是否需要滚动
  void _measureText() {
    if (_textWidth != null) return;
    
    // 使用TextPainter测量文本宽度
    final textSpan = TextSpan(text: widget.message, style: _textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = textPainter.width;
    
    // 考虑内边距，计算实际需要的宽度
    final totalWidth = _textWidth! + _TEXT_PADDING.horizontal;
    
    // 计算最大允许宽度
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    
    // 如果文本加上内边距超过最大宽度，需要滚动
    _needsScroll = totalWidth > maxWidth;
  }
  
  @override
  Widget build(BuildContext context) {
    // 计算实际容器宽度（自适应文本或最大宽度）
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    final contentWidth = _textWidth! + _TEXT_PADDING.horizontal;
    final containerWidth = _needsScroll ? maxWidth : contentWidth;
    
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minWidth: 100.0, // 设置最小宽度避免过窄
        ),
        width: containerWidth,
        decoration: BoxDecoration(
          color: _BACKGROUND_COLOR.withOpacity(_BACKGROUND_OPACITY),
          borderRadius: BorderRadius.circular(_BORDER_RADIUS),
        ),
        padding: _TEXT_PADDING,
        child: _buildTextContent(),
      ),
    );
  }
  
  /// 根据是否需要滚动构建不同的文本内容
  Widget _buildTextContent() {
    if (!_needsScroll) {
      // 修改：添加固定宽度容器确保文本真正居中
      return Container(
        width: _textWidth,  // 使用文本的实际宽度
        alignment: Alignment.center, // 确保内容居中对齐
        child: Text(
          widget.message,
          style: _textStyle,
          textAlign: TextAlign.center,
          softWrap: false,  // 防止文本自动换行
          maxLines: 1,      // 强制单行显示
          overflow: TextOverflow.visible, // 允许文本溢出容器
        ),
      );
    }
    
    // 计算容器宽度，用于设置间距
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    
    // 使用Marquee实现滚动效果，与ad_manager保持完全一致的参数
    return RepaintBoundary(
      child: SizedBox(
        height: _textStyle.fontSize! * 1.5, // 设置固定高度，与文字大小匹配
        child: Marquee(
          text: widget.message,
          style: _textStyle,
          scrollAxis: Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.center,
          velocity: _SCROLL_VELOCITY, // 滚动速度
          blankSpace: maxWidth, 
          startPadding: maxWidth, 
          accelerationDuration: Duration.zero,
          decelerationDuration: Duration.zero,
          accelerationCurve: Curves.linear,
          decelerationCurve: Curves.linear,
          // 不限制循环次数，允许无限滚动
          pauseAfterRound: Duration.zero, 
          showFadingOnlyWhenScrolling: false,
          fadingEdgeStartFraction: 0.0,
          fadingEdgeEndFraction: 0.0,
          startAfter: Duration.zero,
          onDone: () {
            // 滚动完成后的回调，可以在此处添加日志或其他处理
          },
        ),
      ),
    );
  }
}
