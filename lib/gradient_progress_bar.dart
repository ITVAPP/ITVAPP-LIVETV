import 'package:flutter/material.dart';

/// 定义一个无状态的渐变进度条组件
class GradientProgressBar extends StatelessWidget {
  final double width; // 进度条的宽度  
  final double height; // 进度条的高度
  final Duration duration; // 动画的持续时间

  const GradientProgressBar({
    Key? key,
    this.width = 280.0, // 默认宽度设为 280.0
    this.height = 5.0,  // 默认高度设为 5.0 
    this.duration = const Duration(seconds: 2), // 默认动画持续时间为 2 秒
  }) : super(key: key);

  @override 
  Widget build(BuildContext context) {
    return _AnimatedGradientProgressBar(
      width: width,
      height: height, 
      duration: duration,
    );
  }
}

/// 定义一个有状态的私有组件，用于显示带动画的渐变进度条
class _AnimatedGradientProgressBar extends StatefulWidget {
  final double width; // 进度条的宽度
  final double height; // 进度条的高度  
  final Duration duration; // 动画的持续时间

  const _AnimatedGradientProgressBar({
    Key? key,
    required this.width,
    required this.height,
    required this.duration,
  }) : super(key: key);

  @override
  _AnimatedGradientProgressBarState createState() => _AnimatedGradientProgressBarState();
}

/// 定义 _AnimatedGradientProgressBar 的状态类
class _AnimatedGradientProgressBarState extends State<_AnimatedGradientProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller; // 动画控制器
  late Animation<double> _animation; // 缓存动画值
  
  // 缓存渐变对象以提高性能
  late final LinearGradient _backgroundGradient;
  late final BoxDecoration _containerDecoration;
  late final Container _background; // 缓存静态背景容器
  late final Container _foregroundChild; // 缓存前景子组件
  
  // 缓存渐变着色器的静态部分
  late final List<Color> _foregroundColors;
  late final Alignment _beginAlignment;
  late final Alignment _endAlignment;
  late final TileMode _tileMode;

  @override
  void initState() {
    super.initState();
    
    // 初始化背景渐变
    _backgroundGradient = const LinearGradient(
      colors: [Colors.blue, Colors.purple, Color(0xFFEB144C)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    // 初始化容器装饰
    _containerDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.height / 2),
      color: Colors.white,
    );

    // 缓存静态背景容器
    _background = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2),
        gradient: _backgroundGradient,
      ),
    );

    // 缓存前景子组件
    _foregroundChild = Container(
      width: widget.width,
      height: widget.height,
      decoration: _containerDecoration,
    );

    // 缓存渐变着色器的静态部分
    _foregroundColors = const [
      Colors.transparent,
      Colors.white70,
      Colors.white70,
      Colors.transparent,
    ];
    _beginAlignment = Alignment.centerLeft;
    _endAlignment = Alignment.centerRight;
    _tileMode = TileMode.clamp;

    // 初始化动画控制器和动画
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    )..addListener(() {
      setState(() {}); // 仅在必要时刷新
    });
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _background, // 使用缓存的背景
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                return _buildGradientShader().createShader(bounds);
              },
              child: _foregroundChild, // 使用缓存的子组件
            );
          },
        ),
      ],
    );
  }

  /// 动态构建线性渐变的着色器，仅更新 stops
  LinearGradient _buildGradientShader() {
    final value = _animation.value;
    return LinearGradient(
      colors: _foregroundColors,
      stops: [
        (value - 0.1).clamp(0.0, 1.0),
        (value - 0.05).clamp(0.0, 1.0),
        (value + 0.05).clamp(0.0, 1.0),
        (value + 0.1).clamp(0.0, 1.0),
      ],
      begin: _beginAlignment,
      end: _endAlignment,
      tileMode: _tileMode,
    );
  }
}
