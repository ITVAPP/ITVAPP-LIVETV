import 'package:flutter/material.dart';

/// 可滚动的Toast消息组件，当消息文本超出容器宽度时自动启用滚动动画
class ScrollingToastMessage extends StatefulWidget {
  final String message; // 消息内容
  final double containerWidth; // 容器宽度，用于判断是否滚动
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
  late final AnimationController _textAnimationController; // 控制文字滚动动画
  late final Animation<Offset> _textAnimation; // 实现文字滚动效果的偏移动画
  late double _textWidth; // 文本宽度，用于判断是否需要滚动
  bool _needsScroll = false; // 标记文字是否需要滚动

  static const _shadowBlurRadius = 3.0; // 阴影模糊半径
  static final _shadowColor = Colors.black.withOpacity(0.7); // 阴影颜色
  late final TextPainter _textPainter; // 用于测量文本宽度的TextPainter

  /// 根据屏幕方向动态调整文字样式
  TextStyle get _textStyle => TextStyle(
        color: Colors.white, // 文字颜色
        fontSize: widget.isLandscape ? 18.0 : 16.0, // 根据屏幕方向调整字体大小
        shadows: [
          Shadow(offset: const Offset(1.0, 1.0), blurRadius: _shadowBlurRadius, color: _shadowColor),
          Shadow(offset: const Offset(-1.0, -1.0), blurRadius: _shadowBlurRadius, color: _shadowColor),
        ],
      );

  @override
  void initState() {
    super.initState();
    _textPainter = TextPainter(textDirection: TextDirection.ltr); // 初始化TextPainter
    _measureText(); // 测量文本宽度
    _setupTextAnimation(); // 设置滚动动画
  }

  @override
  void didUpdateWidget(ScrollingToastMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当关键属性变化时重新测量和设置动画
    if (oldWidget.message != widget.message ||
        oldWidget.containerWidth != widget.containerWidth ||
        oldWidget.isLandscape != widget.isLandscape) {
      _measureText();
      _setupTextAnimation();
    }
  }

  /// 测量文字宽度，判断是否需要滚动
  void _measureText() {
    final textSpan = TextSpan(text: widget.message, style: _textStyle);
    _textPainter.text = textSpan; // 设置文本内容
    _textPainter.layout(minWidth: 0, maxWidth: double.infinity); // 计算宽度
    _textWidth = _textPainter.width; // 获取文本宽度
    _needsScroll = _textWidth > widget.containerWidth; // 判断是否需要滚动
  }

  /// 初始化滚动动画
  void _setupTextAnimation() {
    _textAnimationController = AnimationController(
      duration: widget.animationDuration, // 设置动画时长
      vsync: this, // 提供TickerProvider
    );

    final scrollDistance = (_textWidth - widget.containerWidth) / widget.containerWidth; // 计算滚动距离
    final isRtl = Directionality.of(context) == TextDirection.rtl; // 判断文本方向
    _textAnimation = Tween<Offset>(
      begin: Offset(isRtl ? scrollDistance : -scrollDistance, 0.0), // 设置起始偏移
      end: Offset(isRtl ? -scrollDistance : scrollDistance, 0.0), // 设置结束偏移
    ).animate(CurvedAnimation(
      parent: _textAnimationController,
      curve: widget.animationCurve, // 应用动画曲线
    ));

    if (_needsScroll) {
      _textAnimationController.addStatusListener(_onAnimationStatus); // 添加动画状态监听
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _textAnimationController.forward(); // 延迟启动动画
      });
    }
  }

  /// 监听动画状态，实现无限滚动
  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _textAnimationController.reset(); // 重置动画
      _textAnimationController.forward(); // 重新启动动画
    }
  }

  @override
  void dispose() {
    _textAnimationController.dispose(); // 释放动画控制器
    _textPainter.dispose(); // 释放TextPainter
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(
        widget.message,
        style: _textStyle, // 应用文字样式
        textAlign: TextAlign.center, // 居中显示
      );
    }

    return RepaintBoundary(
      child: SlideTransition(
        position: _textAnimation, // 应用滚动动画
        child: Text(widget.message, style: _textStyle), // 显示滚动文字
      ),
    );
  }
}
