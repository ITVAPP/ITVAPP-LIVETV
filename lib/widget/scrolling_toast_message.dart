import 'package:flutter/material.dart';

/// 可滚动的Toast消息组件，支持文本超出容器宽度时自动滚动
class ScrollingToastMessage extends StatefulWidget {
  final String message; // 提示消息内容
  final double containerWidth; // 外部容器宽度，用于判断是否滚动
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

class _ScrollingToastMessageState extends State<ScrollingToastMessage> with SingleTickerProviderStateMixin {
  AnimationController? _textAnimationController; // 控制文字滚动动画
  late Animation<Offset> _textAnimation; // 文字滚动偏移动画
  double? _textWidth; // 文本宽度，缓存计算结果
  bool _needsScroll = false; // 是否需要滚动标记

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
    _setupTextAnimation(); // 设置滚动动画
  }

  /// 测量文本宽度并缓存，确定是否需要滚动
  void _measureText() {
    if (_textWidth != null) return;
    final textSpan = TextSpan(text: widget.message, style: _textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = textPainter.width;
    _needsScroll = _textWidth! > widget.containerWidth;
  }

  /// 初始化滚动动画，仅在需要时创建
  void _setupTextAnimation() {
    if (!_needsScroll) return;
    _textAnimationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    final scrollDistance = (_textWidth! / widget.containerWidth) + 1.0;
    _textAnimation = Tween<Offset>(
      begin: Offset(-scrollDistance, 0.0),
      end: Offset(scrollDistance, 0.0),
    ).animate(CurvedAnimation(
      parent: _textAnimationController!,
      curve: widget.animationCurve,
    ));
    _textAnimationController!.addStatusListener(_onAnimationStatus);
    _textAnimationController!.forward();
  }

  /// 监听动画状态，完成时重启动画
  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _textAnimationController!.reset();
      _textAnimationController!.forward();
    }
  }

  @override
  void dispose() {
    _textAnimationController?.dispose(); // 释放动画控制器资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(
        widget.message,
        style: _textStyle,
        textAlign: TextAlign.center,
      );
    }
    return RepaintBoundary(
      child: SlideTransition(
        position: _textAnimation,
        child: Text(widget.message, style: _textStyle),
      ),
    );
  }
}
