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
    // 返回一个带有动画的渐变进度条组件
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
    required this.width,   // 必须传递进度条的宽度
    required this.height,  // 必须传递进度条的高度
    required this.duration, // 必须传递动画的持续时间
  }) : super(key: key);

  @override
  _AnimatedGradientProgressBarState createState() => _AnimatedGradientProgressBarState();
}

/// 定义 _AnimatedGradientProgressBar 的状态类
class _AnimatedGradientProgressBarState extends State<_AnimatedGradientProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller; // 动画控制器
  
  // 缓存渐变对象以提高性能，避免重复创建
  late final LinearGradient _backgroundGradient;
  
  // 缓存不变的容器装饰，避免在每次 build 时重新构建
  late final BoxDecoration _containerDecoration;
  
  // 缓存静态的渐变颜色数组，避免每帧创建新数组
  static const List<Color> _shaderColors = [
    Colors.transparent, // 左侧透明区域
    Colors.white70, // 修改：使用更柔和的白色 
    Colors.white70, // 修改：使用更柔和的白色
    Colors.transparent, // 右侧透明区域
  ];

  @override
  void initState() {
    super.initState();
    
    // 初始化背景渐变，表示进度条的底色
    _backgroundGradient = const LinearGradient(
      colors: [Colors.blue, Colors.purple, Color(0xFFEB144C)], // 渐变颜色
      begin: Alignment.centerLeft, // 渐变开始位置
      end: Alignment.centerRight, // 渐变结束位置
    );

    // 初始化容器装饰，定义圆角和背景颜色
    _containerDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(widget.height / 2), // 圆角半径
      color: Colors.white, // 容器背景色
    );

    // 初始化动画控制器并启动动画
    _controller = AnimationController(
      duration: widget.duration, // 动画持续时间
      vsync: this, // 使用单一动画提供者
    )..repeat(); // 修改：移除 reverse 参数，实现单向动画
  }

  @override
  void dispose() {
    _controller.dispose(); // 销毁动画控制器，释放资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 创建静态背景容器，仅构建一次
    final background = Container(
      width: widget.width, // 设置容器宽度
      height: widget.height, // 设置容器高度
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2), // 圆角边框
        gradient: _backgroundGradient, // 使用缓存的渐变对象作为背景
      ),
    );

    // 使用 Stack 将背景和前景动画叠加在一起
    return Stack(
      children: [
        // 使用 RepaintBoundary 隔离静态背景，避免无效重绘
        RepaintBoundary(
          child: background, // 底部静态渐变背景
        ),
        // 使用 AnimatedBuilder 实现动态效果
        AnimatedBuilder(
          animation: _controller, // 绑定动画控制器
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                // 调用私有方法，动态生成前景的着色器
                return _buildGradientShader().createShader(bounds);
              },
              child: child!, // 使用不变的子组件
            );
          },
          // 将不变的部分（容器装饰）作为子组件，避免重复构建
          child: Container(
            width: widget.width, // 容器宽度
            height: widget.height, // 容器高度
            decoration: _containerDecoration, // 使用缓存的装饰对象
          ),
        ),
      ],
    );
  }

  /// 私有方法，用于动态构建线性渐变的着色器
  LinearGradient _buildGradientShader() {
    // 修改：使用 Curves.easeInOut 使动画更自然
    final value = Curves.easeInOut.transform(_controller.value); 
    
    return LinearGradient(
      colors: _shaderColors, // 使用缓存的静态颜色数组
      stops: [
        // 修改：更平滑的位置变化
        (value - 0.1).clamp(0.0, 1.0), // 左侧透明到白色的渐变点
        (value - 0.05).clamp(0.0, 1.0), // 左侧白色位置
        (value + 0.05).clamp(0.0, 1.0), // 右侧白色位置
        (value + 0.1).clamp(0.0, 1.0), // 白色到透明的渐变点
      ],
      begin: Alignment.centerLeft, // 渐变开始位置
      end: Alignment.centerRight, // 渐变结束位置
      tileMode: TileMode.clamp, // 限制颜色范围，超出部分用边界颜色填充
    );
  }
}
