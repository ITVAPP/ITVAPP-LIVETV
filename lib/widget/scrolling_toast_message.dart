/// 可滚动的Toast消息组件
/// 当消息文本超出容器宽度时自动启用滚动动画
class ScrollingToastMessage extends StatefulWidget {
  final String message;
  final double containerWidth;
  final TextStyle textStyle;
  final bool isPortrait;
  final bool showProgress;
  final Duration animationDuration;
  final Curve animationCurve;

  const ScrollingToastMessage({
    Key? key,
    required this.message,
    required this.containerWidth,
    required this.textStyle,
    this.isPortrait = false,
    this.showProgress = false,
    this.animationDuration = const Duration(seconds: 10),
    this.animationCurve = Curves.linear,
  }) : super(key: key);

  @override
  State<ScrollingToastMessage> createState() => _ScrollingToastMessageState();
}

class _ScrollingToastMessageState extends State<ScrollingToastMessage> with SingleTickerProviderStateMixin {
  late final AnimationController _textAnimationController;
  late final Animation<Offset> _textAnimation;
  late double _textWidth;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _measureText();
    _setupTextAnimation();
  }

  void _measureText() {
    final textSpan = TextSpan(text: widget.message, style: widget.textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = textPainter.width;
    _needsScroll = _textWidth > widget.containerWidth;
  }

  void _setupTextAnimation() {
    _textAnimationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _textAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(-1.0, 0.0),
    ).animate(CurvedAnimation(
      parent: _textAnimationController,
      curve: widget.animationCurve,
    ));

    if (_needsScroll) {
      _textAnimationController.addStatusListener(_onAnimationStatus);
      _textAnimationController.forward();
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _textAnimationController.reset();
      _textAnimationController.forward();
    }
  }

  @override
  void dispose() {
    _textAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScroll) {
      return Text(
        widget.message,
        style: widget.textStyle,
        textAlign: TextAlign.center,
      );
    }

    return RepaintBoundary(
      child: SlideTransition(
        position: _textAnimation,
        child: Text(
          widget.message,
          style: widget.textStyle,
        ),
      ),
    );
  }
}
