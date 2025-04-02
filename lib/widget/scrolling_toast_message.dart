// 修改代码开始
import 'package:flutter/material.dart';

/// 可滚动的Toast消息组件
/// 当消息文本超出容器宽度时自动启用滚动动画
class ScrollingToastMessage extends StatefulWidget {
  final String message; // 滚动提示消息内容
  final double containerWidth; // 外部容器的宽度，用于计算文字是否需要滚动
  final bool isLandscape; // 是否为横屏模式，用于调整文字样式
  final Duration animationDuration; // 滚动动画持续时间
  final Curve animationCurve; // 滚动动画曲线效果

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
  AnimationController? _textAnimationController; // 动画控制器，控制文字滚动动画，仅在需要时初始化
  late Animation<Offset> _textAnimation; // 偏移动画，用于实现文字的滚动效果
  double? _textWidth; // 文本内容的宽度，缓存结果以避免重复计算
  bool _needsScroll = false; // 标记文字是否需要滚动

  // 提取重复的 Shadow 配置为常量，提升可读性和维护性
  static const _shadowConfig = Shadow(
    offset: Offset(1.0, 1.0),
    blurRadius: 3.0,
    color: Color.fromRGBO(0, 0, 0, 0.7), // 使用 RGBO 替代 withOpacity 以明确颜色值
  );

  // 根据屏幕方向动态调整文字样式
  TextStyle get _textStyle => TextStyle(
        color: Colors.white, // 设置文字颜色为白色
        fontSize: widget.isLandscape ? 18.0 : 16.0, // 根据横屏或竖屏调整字体大小
        shadows: [
          _shadowConfig, // 使用提取的常量
          Shadow(
            offset: Offset(-_shadowConfig.offset.dx, -_shadowConfig.offset.dy), // 反向偏移复用配置
            blurRadius: _shadowConfig.blurRadius,
            color: _shadowConfig.color,
          ),
        ],
      );

  @override
  void initState() {
    super.initState();
    _measureText(); // 测量文本宽度，确定是否需要滚动
    _setupTextAnimation(); // 初始化滚动动画
  }

  // 测量文字宽度，判断是否超出容器宽度，结果缓存到 _textWidth
  void _measureText() {
    if (_textWidth != null) return; // 如果已缓存宽度，直接返回，避免重复计算
    final textSpan = TextSpan(text: widget.message, style: _textStyle); // 创建文本样式对象
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr, // 设置文字绘制方向为从左到右
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity); // 计算文字的宽度
    _textWidth = textPainter.width; // 缓存文字宽度
    _needsScroll = _textWidth! > widget.containerWidth; // 判断文字是否需要滚动
  }

  // 初始化滚动动画，仅在需要滚动时创建控制器并动态计算偏移
  void _setupTextAnimation() {
    if (!_needsScroll) return; // 如果不需要滚动，不初始化动画

    _textAnimationController = AnimationController(
      duration: widget.animationDuration, // 动画时长
      vsync: this, // 提供 TickerProvider
    );

    // 动态计算动画偏移量，确保滚动距离与文本宽度匹配
    final scrollDistance = (_textWidth! / widget.containerWidth) + 1.0; // 计算滚动所需的倍数
    _textAnimation = Tween<Offset>(
      begin: Offset(-scrollDistance, 0.0), // 从左侧超出部分开始
      end: Offset(scrollDistance, 0.0), // 到右侧超出部分结束
    ).animate(CurvedAnimation(
      parent: _textAnimationController!, // 动画控制器
      curve: widget.animationCurve, // 动画曲线
    ));

    // 设置监听器并启动动画
    _textAnimationController!.addStatusListener(_onAnimationStatus);
    _textAnimationController!.forward(); // 启动动画
  }

  // 监听动画状态，当动画完成时重启动画
  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _textAnimationController!.reset(); // 重置动画
      _textAnimationController!.forward(); // 重新启动动画
    }
  }

  @override
  void dispose() {
    _textAnimationController?.dispose(); // 仅在控制器存在时释放资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      // 如果文字宽度小于容器宽度，直接显示文字居中对齐
      return Text(
        widget.message,
        style: _textStyle, // 应用文字样式
        textAlign: TextAlign.center, // 居中显示文字
      );
    }

    // 如果文字需要滚动，使用 SlideTransition 实现滚动效果
    return RepaintBoundary(
      child: SlideTransition(
        position: _textAnimation, // 应用滚动动画
        child: Text(
          widget.message,
          style: _textStyle, // 应用文字样式
        ),
      ),
    );
  }
}
// 修改代码结束
