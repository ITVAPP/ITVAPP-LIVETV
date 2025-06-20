import 'package:flutter/material.dart';

// 定义渐变进度条组件
class GradientProgressBar extends StatelessWidget {
  final double width; // 定义进度条宽度
  final double height; // 定义进度条高度
  final Duration duration; // 定义动画持续时间

  const GradientProgressBar({
    Key? key,
    this.width = 300.0, // 默认宽度 280.0
    this.height = 5.0,  // 默认高度 5.0
    this.duration = const Duration(seconds: 3), // 默认动画持续秒
  }) : super(key: key);

  @override 
  Widget build(BuildContext context) {
    // 构建带动画的渐变进度条
    return _AnimatedGradientProgressBar(
      width: width,
      height: height, 
      duration: duration,
    );
  }
}

// 定义带动画的渐变进度条组件
class _AnimatedGradientProgressBar extends StatefulWidget {
  final double width; // 定义进度条宽度
  final double height; // 定义进度条高度
  final Duration duration; // 定义动画持续时间

  const _AnimatedGradientProgressBar({
    Key? key,
    required this.width,   // 进度条宽度
    required this.height,  // 进度条高度
    required this.duration, // 动画持续时间
  }) : super(key: key);

  @override
  _AnimatedGradientProgressBarState createState() => _AnimatedGradientProgressBarState();
}

// 管理渐变进度条动画状态
class _AnimatedGradientProgressBarState extends State<_AnimatedGradientProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller; // 动画控制器
  
  // 缓存渐变对象，优化性能
  late final LinearGradient _backgroundGradient;
  
  // 缓存容器装饰，避免重复构建
  late final BoxDecoration _containerDecoration;
  
  // 缓存静态渐变颜色数组
  static const List<Color> _shaderColors = [
    Colors.transparent, // 左侧透明
    Colors.white70, // 柔和白色
    Colors.white70, // 柔和白色
    Colors.transparent, // 右侧透明
  ];

  @override
  void initState() {
    super.initState();
    
    // 初始化背景渐变
    _backgroundGradient = const LinearGradient(
      colors: [Colors.blue, Colors.purple, Color(0xFFEB144C)], // 渐变颜色
      begin: Alignment.centerLeft, // 渐变起始位置
      end: Alignment.centerRight, // 渐变结束位置
    );

    // 初始化容器装饰，设置圆角
    _containerDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.height / 2), // 圆角半径
      color: Colors.white, // 背景色
    );

    // 初始化并启动动画控制器
    _controller = AnimationController(
      duration: widget.duration, // 动画持续时间
      vsync: this, // 单一动画提供者
    )..repeat(); // 单向循环动画
  }

  @override
  void dispose() {
    _controller.dispose(); // 安全释放动画控制器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 构建静态背景容器
    final background = Container(
      width: widget.width, // 定义容器宽度
      height: widget.height, // 定义容器高度
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2), // 圆角边框
        gradient: _backgroundGradient, // 应用缓存渐变背景
      ),
    );

    // 叠加背景和动画前景
    return Stack(
      children: [
        RepaintBoundary(
          child: background, // 静态渐变背景
        ),
        // 实现动态动画效果
        AnimatedBuilder(
          animation: _controller, // 绑定动画控制器
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                // 动态生成前景着色器
                return _buildGradientShader().createShader(bounds);
              },
              child: child!, // 使用缓存子组件
            );
          },
          // 缓存不变的容器装饰
          child: Container(
            width: widget.width, // 定义容器宽度
            height: widget.height, // 定义容器高度
            decoration: _containerDecoration, // 应用缓存装饰
          ),
        ),
      ],
    );
  }

  // 动态生成线性渐变着色器
  LinearGradient _buildGradientShader() {
    final value = Curves.easeInOut.transform(_controller.value); 
    
    return LinearGradient(
      colors: _shaderColors, // 使用缓存颜色数组
      stops: [
        // 平滑过渡渐变点
        (value - 0.1).clamp(0.0, 1.0), // 左侧透明到白色
        (value - 0.05).clamp(0.0, 1.0), // 左侧白色
        (value + 0.05).clamp(0.0, 1.0), // 右侧白色
        (value + 0.1).clamp(0.0, 1.0), // 白色到透明
      ],
      begin: Alignment.centerLeft, // 渐变起始位置
      end: Alignment.centerRight, // 渐变结束位置
      tileMode: TileMode.clamp, // 限制颜色范围
    );
  }
}
