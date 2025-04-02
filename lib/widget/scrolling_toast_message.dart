import 'package:flutter/material.dart';

// 可滚动的 Toast 消息组件，文本超宽时自动启用滚动动画
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
  late final Animation<Offset> _textAnimation; // 实现文字滚动的偏移动画
  late double _textWidth; // 文本宽度
  bool _needsScroll = false; // 是否需要滚动

  static const _shadowBlurRadius = 3.0; // 阴影模糊半径
  static final _shadowColor = Colors.black.withOpacity(0.7); // 阴影颜色
  late final TextPainter _textPainter; // 用于测量文本宽度

  // 根据屏幕方向动态调整文字样式
  TextStyle get _textStyle => TextStyle(
        color: Colors.white,
        fontSize: widget.isLandscape ? 18.0 : 16.0, // 横屏字体大，竖屏字体小
        shadows: [
          Shadow(offset: const Offset(1.0, 1.0), blurRadius: _shadowBlurRadius, color: _shadowColor),
          Shadow(offset: const Offset(-1.0, -1.0), blurRadius: _shadowBlurRadius, color: _shadowColor),
        ],
      );

  @override
  void initState() {
    super.initState();
    _textPainter = TextPainter(textDirection: TextDirection.ltr); // 初始化文本测量工具
    _measureText(); // 测量文本宽度
    _setupTextAnimation(); // 设置滚动动画
  }

  @override
  void didUpdateWidget(ScrollingToastMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.containerWidth != widget.containerWidth ||
        oldWidget.isLandscape != widget.isLandscape) {
      _textAnimationController.stop(); // 停止当前动画
      _textAnimationController.reset(); // 重置动画状态
      _measureText(); // 重新测量文本
      _setupTextAnimation(); // 重新设置动画
    }
  }

  // 测量文本宽度并判断是否需要滚动
  void _measureText() {
    final textSpan = TextSpan(text: widget.message, style: _textStyle);
    _textPainter.text = textSpan;
    _textPainter.layout(minWidth: 0, maxWidth: double.infinity); // 计算文本布局
    _textWidth = _textPainter.width;
    _needsScroll = _textWidth > widget.containerWidth; // 文本超宽时需滚动
  }

  // 初始化并配置滚动动画
  void _setupTextAnimation() {
    _textAnimationController?.dispose(); // 释放旧控制器
    _textAnimationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this, // 绑定 TickerProvider
    );

    final scrollDistance = (_textWidth - widget.containerWidth) / widget.containerWidth; // 计算滚动距离比例
    final isRtl = Directionality.of(context) == TextDirection.rtl; // 判断文本方向
    _textAnimation = Tween<Offset>(
      begin: Offset(isRtl ? scrollDistance : -scrollDistance, 0.0), // 从左或右开始
      end: Offset(isRtl ? -scrollDistance : scrollDistance, 0.0), // 到另一侧结束
    ).animate(CurvedAnimation(
      parent: _textAnimationController,
      curve: widget.animationCurve, // 应用指定曲线
    ));

    if (_needsScroll) {
      _textAnimationController.addStatusListener(_onAnimationStatus); // 监听动画状态
      if (mounted) _textAnimationController.forward(); // 启动动画
    }
  }

  // 监听动画状态以实现循环滚动
  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _textAnimationController.reset();
      _textAnimationController.forward(); // 完成后重启动画
    }
  }

  @override
  void dispose() {
    _textAnimationController.removeStatusListener(_onAnimationStatus); // 移除监听
    _textAnimationController.dispose(); // 释放控制器
    _textPainter.dispose(); // 释放文本测量工具
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(
        widget.message,
        style: _textStyle,
        textAlign: TextAlign.center, // 静态文本居中显示
      );
    }

    return RepaintBoundary(
      child: SlideTransition(
        position: _textAnimation, // 应用滚动动画
        child: Text(widget.message, style: _textStyle), // 滚动显示文本
      ),
    );
  }
}
