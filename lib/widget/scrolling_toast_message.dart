import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';

// 显示可滚动的 Toast 消息，支持淡入和自动滚动
class ScrollingToastMessage extends StatefulWidget {
  final String message; // 提示消息内容
  final double containerWidth; // 外部容器宽度
  final bool isLandscape; // 是否横屏模式
  final Duration fadeInDuration; // 淡入动画时长
  
  const ScrollingToastMessage({
    Key? key,
    required this.message,
    required this.containerWidth,
    this.isLandscape = true,
    this.fadeInDuration = const Duration(milliseconds: 500), // 默认淡入时长
  }) : super(key: key);
  
  @override
  State<ScrollingToastMessage> createState() => _ScrollingToastMessageState();
}

class _ScrollingToastMessageState extends State<ScrollingToastMessage> with SingleTickerProviderStateMixin {
  double? _textWidth; // 缓存文本宽度
  bool _needsScroll = false; // 标记是否需要滚动
  late AnimationController _fadeController; // 淡入动画控制器
  late Animation<double> _fadeAnimation; // 淡入动画
  TextStyle? _cachedTextStyle; // 缓存文字样式
  TextPainter? _textPainter; // 缓存 TextPainter 实例
  bool _isInitialized = false; // 标记是否已初始化
  
  static const _TEXT_PADDING = EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0); // 文本内边距
  static const _BACKGROUND_OPACITY = 0.5; // 背景透明度
  static const _BACKGROUND_COLOR = Colors.black; // 背景颜色
  static const _BORDER_RADIUS = 12.0; // 容器圆角
  static const _MAX_WIDTH_FACTOR = 0.8; // 最大宽度比例
  static const _SCROLL_VELOCITY = 38.0; // 文本滚动速度
  
  // 文字阴影配置
  static const _shadowConfig = Shadow(
    offset: Offset(1.0, 1.0),
    blurRadius: 3.0,
    color: Color.fromRGBO(0, 0, 0, 0.7),
  );
  
  // 反向文字阴影配置
  static const _reverseShadow = Shadow(
    offset: Offset(-1.0, -1.0),
    blurRadius: 3.0,
    color: Color.fromRGBO(0, 0, 0, 0.7),
  );
  
  // 获取文字样式
  TextStyle get _textStyle {
    final isTV = context.read<ThemeProvider>().isTV;
    final double fontSize = isTV ? 22.0 : 16.0; // isTV使用增大的字体
    
    _cachedTextStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      shadows: const [_shadowConfig, _reverseShadow],
    );
    return _cachedTextStyle!;
  }
  
  @override
  void initState() {
    super.initState();
    
    // 初始化淡入动画
    _fadeController = AnimationController(
      duration: widget.fadeInDuration,
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    
    // 初始化 TextPainter
    _textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    
    // 直接初始化文本
    _initializeText();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 仅在首次初始化时测量文本
    if (!_isInitialized) {
      _isInitialized = true;
      _initializeText();
    }
  }
  
  @override
  void didUpdateWidget(ScrollingToastMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message || 
        oldWidget.containerWidth != widget.containerWidth ||
        oldWidget.isLandscape != widget.isLandscape) {
      _textWidth = null;
      
      // 如果横竖屏切换，清除缓存的样式
      if (oldWidget.isLandscape != widget.isLandscape) {
        _cachedTextStyle = null;
      }
      
      _fadeController.reset();
      _initializeText();
    }
  }
  
  @override
  void dispose() {
    // 释放资源
    _fadeController.dispose();
    _textPainter?.dispose();
    super.dispose();
  }
  
  // 初始化文本并触发测量
  void _initializeText() {
    if (!mounted) return;
    final oldWidth = _textWidth;
    final oldNeedsScroll = _needsScroll;
    _measureText();
    if (oldWidth != _textWidth || oldNeedsScroll != _needsScroll) {
      setState(() {});
    }
    _fadeController.forward();
  }
  
  // 测量文本宽度并判断是否需要滚动
  void _measureText() {
    _textPainter!.text = TextSpan(text: widget.message, style: _textStyle);
    _textPainter!.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = _textPainter!.width;
    
    final totalWidth = _textWidth! + _TEXT_PADDING.horizontal;
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    _needsScroll = totalWidth > maxWidth;
  }
  
  @override
  Widget build(BuildContext context) {
    if (_textWidth == null) {
      return const SizedBox.shrink();
    }
    
    final maxWidth = widget.containerWidth * _MAX_WIDTH_FACTOR;
    final contentWidth = _textWidth! + _TEXT_PADDING.horizontal;
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
  
  // 构建文本内容，支持滚动或静态显示
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
    
    return RepaintBoundary(
      child: SizedBox(
        height: _textStyle.fontSize! * 1.5,
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
