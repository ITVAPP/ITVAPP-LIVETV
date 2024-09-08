import 'package:flutter/material.dart'; // 导入 Flutter 的核心组件库

// 定义一个无状态的渐变进度条组件
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

// 定义一个有状态的私有组件，用于显示带动画的渐变进度条
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

// 定义 _AnimatedGradientProgressBar 的状态类
class _AnimatedGradientProgressBarState extends State<_AnimatedGradientProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller; // 动画控制器

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration, // 动画的持续时间
      vsync: this, // 提供 vsync 信号防止屏幕外的动画消耗资源
    )..repeat(); // 重复播放动画
  }

  @override
  void dispose() {
    _controller.dispose(); // 销毁动画控制器，释放资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 静态背景容器，只需构建一次
    final background = Container(
      width: widget.width,  // 设置进度条的宽度
      height: widget.height, // 设置进度条的高度
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2), // 设置圆角
        gradient: LinearGradient(
          colors: [Colors.blue, Colors.purple, Color(0xFFEB144C)], // 渐变颜色从蓝色到紫色到红色
          begin: Alignment.centerLeft, // 渐变开始于左侧
          end: Alignment.centerRight,  // 渐变结束于右侧
        ),
      ),
    );

    // 使用 Stack 将渐变背景和移动的前景色叠加
    return Stack(
      children: [
        background, // 渐变背景色容器
        // 使用 AnimatedBuilder 仅构建动画部分
        AnimatedBuilder(
          animation: _controller, // 使用动画控制器来重建动画
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                return _buildGradientShader().createShader(bounds); // 使用私有方法生成着色器
              },
              child: Container(
                width: widget.width,  // 设置遮罩容器的宽度
                height: widget.height, // 设置遮罩容器的高度
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.height / 2), // 设置圆角
                  color: Colors.white, // 设置遮罩颜色为白色，使渐变色应用于整个容器
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // 私有方法，用于构建线性渐变的着色器
  LinearGradient _buildGradientShader() {
    return LinearGradient(
      colors: [
        Colors.transparent, // 开始位置透明
        Colors.white, // 中间是白色
        Colors.white, // 中间是白色
        Colors.transparent, // 结束位置透明
      ],
      stops: [
        (_controller.value - 0.1).clamp(0.0, 1.0), // 动态起始位置并限制在 0 到 1 之间
        _controller.value.clamp(0.0, 1.0),       // 白色开始位置并限制在 0 到 1 之间
        (_controller.value + 0.1).clamp(0.0, 1.0), // 白色结束位置并限制在 0 到 1 之间
        (_controller.value + 0.2).clamp(0.0, 1.0), // 动态结束位置并限制在 0 到 1 之间
      ],
      begin: Alignment.centerLeft, // 渐变从左到右
      end: Alignment.centerRight,  // 渐变从左到右
      tileMode: TileMode.clamp,    // 超出范围的颜色会被边界颜色填充
    );
  }
}
