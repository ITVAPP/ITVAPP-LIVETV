import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// 可滚动的Toast消息组件，支持文本超出容器宽度时自动滚动
/// 静态文本添加淡入效果，使显示更加平滑
class ScrollingToastMessage extends StatefulWidget {
  final String message; // 提示消息内容
  final double containerWidth; // 外部容器宽度，用于计算最大宽度和判断是否滚动
  final bool isLandscape; // 是否横屏，调整文字样式
  final Duration animationDuration; // 滚动动画时长
  final Curve animationCurve; // 滚动动画曲线
  final Duration fadeInDuration; // 淡入动画时长
  
  const ScrollingToastMessage({
    Key? key,
    required this.message,
    required this.containerWidth,
    this.isLandscape = true,
    this.animationDuration = const Duration(seconds: 10),
    this.animationCurve = Curves.linear,
    this.fadeInDuration = const Duration(milliseconds: 300), // 默认淡入时长
  }) : super(key: key);
  
  @override
  State<ScrollingToastMessage> createState() => _ScrollingToastMessageState();
}

class _ScrollingToastMessageState extends State<ScrollingToastMessage> with SingleTickerProviderStateMixin {
  double? _textWidth; // 缓存文本宽度，优化性能
  bool _needsScroll = false; // 标记文本是否需要滚动
  late AnimationController _fadeController; // 淡入效果控制器
  late Animation<double> _fadeAnimation; // 淡入动画
  
  // 定义文字内边距常量
  static const _TEXT_PADDING = EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0);
  static const _BACKGROUND_OPACITY = 0.5; // 背景透明度
  static const _BACKGROUND_COLOR = Colors.black; // 背景颜色
  static const _BORDER_RADIUS = 12.0; // 容器圆角半径
  static const _MAX_WIDTH_FACTOR = 0.8; // 最大宽度占容器宽度的比例
  static const _SCROLL_VELOCITY = 38.0; // 滚动速度，匹配ad_manager
  
  /// 文字阴影配置，提升视觉效果
  static const _shadowConfig = Shadow(
    offset: Offset(1.0, 1.0),
    blurRadius: 3.0,
    color: Color.fromRGBO(0, 0, 0, 0.7),
  );
  
  /// 动态生成文字样式，根据屏幕方向调整
  TextStyle get _textStyle => TextStyle(
    color: Colors.white,
    fontSize: widget.isLandscape ? 17.0 : 15.0,
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
    
    // 初始化淡入动画控制器
    _fadeController = AnimationController(
      duration: widget.fadeInDuration,
      vsync: this,
    );
    
    // 创建淡入动画
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    
    // 延迟测量文本宽度，确保渲染后获取准确值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureText();
      if (mounted) {
        setState(() {});
        // 开始淡入动画
        _fadeController.forward();
      }
    });
  }
  
  @override
  void didUpdateWidget(ScrollingToastMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 消息或容器宽度变化时重新测量文本
    if (oldWidget.message != widget.message || 
        oldWidget.containerWidth != widget.containerWidth) {
      _textWidth = null;
      
      // 重置并重新开始淡入动画
      _fadeController.reset();
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureText();
        if (mounted) {
          setState(() {});
          // 开始淡入动画
          _fadeController.forward();
        }
      });
    }
  }
  
  @override
  void dispose() {
    // 释放动画控制器资源
    _fadeController.dispose();
    super.dispose();
  }
  
  /// 测量文本宽度，确定是否需要滚动
  void _measureText() {
    final textSpan = TextSpan(text: widget.message, style: _textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = textPainter.width;
    
    // 计算实际宽度（含内边距）
    final totalWidth = _textWidth! + _TEXT_PADDING.horizontal;
    
    // 计算最大允许宽度
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    
    // 判断是否需要滚动
    _needsScroll = totalWidth > maxWidth;
  }
  
  @override
  Widget build(BuildContext context) {
    // 未测量文本宽度时显示空占位
    if (_textWidth == null) {
      return const SizedBox.shrink();
    }
    
    // 计算最大宽度
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    
    // 计算内容宽度（文本+内边距）
    final contentWidth = _textWidth! + _TEXT_PADDING.horizontal;
    
    // 确定容器宽度：滚动时用最大宽度，否则用内容宽度
    final containerWidth = _needsScroll ? maxWidth : contentWidth;
    
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          width: containerWidth,
          decoration: BoxDecoration(
            color: _BACKGROUND_COLOR.withOpacity(_BACKGROUND_OPACITY),
            borderRadius: BorderRadius.circular(_BORDER_RADIUS),
          ),
          padding: _TEXT_PADDING,
          child: _buildTextContent(),
        ),
      ),
    );
  }
  
  /// 构建文本内容，根据是否滚动选择静态或动态显示
  Widget _buildTextContent() {
    if (!_needsScroll) {
      // 短文本居中显示
      return Center(
        child: Text(
          widget.message,
          style: _textStyle,
          textAlign: TextAlign.center,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
      );
    }
    
    // 计算滚动区域最大宽度
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    
    // 使用Marquee实现文本滚动
    return RepaintBoundary(
      child: SizedBox(
        height: _textStyle.fontSize! * 1.5, // 固定高度，适配文字
        child: Marquee(
          text: widget.message,
          style: _textStyle,
          scrollAxis: Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.center,
          velocity: _SCROLL_VELOCITY,
          blankSpace: maxWidth,
          startPadding: maxWidth,
          accelerationDuration: Duration.zero,
          decelerationDuration: Duration.zero,
          accelerationCurve: Curves.linear,
          decelerationCurve: Curves.linear,
          pauseAfterRound: Duration.zero, 
          showFadingOnlyWhenScrolling: false,
          fadingEdgeStartFraction: 0.0,
          fadingEdgeEndFraction: 0.0,
          startAfter: Duration.zero,
        ),
      ),
    );
  }
}
