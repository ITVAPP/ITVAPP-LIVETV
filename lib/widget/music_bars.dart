import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DynamicAudioBars extends StatefulWidget {
  // 动态音柱组件，用于显示模拟音频频谱的动态效果
  final double maxHeightPercentage; // 音柱最大高度占容器高度的百分比
  final Duration animationSpeed; // 动画更新速度
  final double smoothness; // 控制音柱高度过渡的平滑度参数

  const DynamicAudioBars({
    Key? key,
    this.maxHeightPercentage = 0.8, // 默认最大高度为容器高度的80%
    this.animationSpeed = const Duration(milliseconds: 100), // 默认动画更新间隔100ms
    this.smoothness = 0.5, // 默认平滑度为0.5
  }) : assert(maxHeightPercentage > 0 && maxHeightPercentage <= 1.0), // 确保高度比例在合法范围内
       assert(smoothness >= 0 && smoothness <= 1.0), // 确保平滑度参数在合法范围内
       super(key: key);

  @override
  DynamicAudioBarsState createState() => DynamicAudioBarsState(); // 创建与组件关联的状态对象
}

class DynamicAudioBarsState extends State<DynamicAudioBars>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<List<double>> _heightsNotifier = ValueNotifier<List<double>>([]); // 用于存储音柱高度的可监听列表
  late Timer _timer; // 定时器，用于周期性更新音柱高度
  bool _isAnimating = true; // 控制动画播放状态

  @override
  void initState() {
    super.initState();
    // 启动定时器，按照指定速度更新音柱高度
    _timer = Timer.periodic(widget.animationSpeed, (timer) {
      if (!_isAnimating) return; // 如果动画暂停，直接返回

      final currentHeights = _heightsNotifier.value; // 当前音柱高度
      final newHeights = List<double>.generate(
        currentHeights.length,
        (index) {
          // 为每个音柱生成新的高度，结合平滑度参数实现平滑过渡
          final currentHeight = currentHeights[index];
          final targetHeight = Random().nextDouble(); // 随机生成目标高度（范围0到1）
          return (currentHeight * widget.smoothness +
                  targetHeight * (1 - widget.smoothness))
              .clamp(0.0, 1.0); // 限制高度在0到1的范围内
        },
      );

      _heightsNotifier.value = newHeights; // 更新音柱高度列表
    });
  }

  @override
  void dispose() {
    // 页面销毁时清理资源
    _timer.cancel(); // 停止定时器
    _heightsNotifier.dispose(); // 释放监听器资源
    super.dispose();
  }

  // 暂停动画
  void pauseAnimation() {
    setState(() {
      _isAnimating = false; // 将动画状态设置为暂停
    });
  }

  // 恢复动画
  void resumeAnimation() {
    setState(() {
      _isAnimating = true; // 将动画状态设置为继续
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据容器的宽度动态计算需要的音柱数量
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio; // 获取设备的像素比
        int numberOfBars = (constraints.maxWidth / (20 * devicePixelRatio)).floor(); // 计算音柱数量（每个宽度为20像素）

        // 如果音柱数量发生变化，重新初始化高度列表
        if (_heightsNotifier.value.length != numberOfBars) {
          _heightsNotifier.value = List<double>.filled(numberOfBars, 0.0); // 初始化为指定数量的音柱，高度为0
        }

        return RepaintBoundary(
          child: ValueListenableBuilder<List<double>>(
            valueListenable: _heightsNotifier, // 监听音柱高度列表的变化
            builder: (context, heights, _) {
              return CustomPaint(
                size: Size(double.infinity, constraints.maxHeight), // 设置画布大小
                painter: AudioBarsPainter(
                  heights, // 当前的音柱高度列表
                  maxHeightPercentage: widget.maxHeightPercentage, // 最大高度占比
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class AudioBarsPainter extends CustomPainter {
  final List<double> barHeights; // 每个音柱的高度（值范围0到1）
  final double maxHeightPercentage; // 音柱最大高度占容器高度的百分比
  final double spacing = 2.0; // 音柱之间的水平间距

  AudioBarsPainter(this.barHeights, {this.maxHeightPercentage = 0.8});

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return; // 如果没有音柱数据，不执行绘制

    final totalSpacing = spacing * (barHeights.length - 1); // 总间距宽度
    final barWidth = (size.width - totalSpacing) / barHeights.length; // 每个音柱的宽度
    final maxHeight = size.height * maxHeightPercentage; // 音柱允许的最大高度

    for (int i = 0; i < barHeights.length; i++) {
      // 定义音柱的渐变颜色效果
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.blueAccent.withOpacity(0.7),
            Colors.greenAccent.withOpacity(0.6),
            Colors.yellowAccent.withOpacity(0.5),
            Colors.orangeAccent.withOpacity(0.4),
            Colors.redAccent.withOpacity(0.3),
          ],
          begin: Alignment.bottomCenter, // 渐变起始点（底部）
          end: Alignment.topCenter, // 渐变结束点（顶部）
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      final barHeight = barHeights[i] * maxHeight; // 计算音柱实际高度
      final barX = i * (barWidth + spacing); // 计算音柱的横向位置

      // 绘制音柱为矩形
      canvas.drawRect(
        Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight), // 矩形从底部向上绘制
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    // 判断是否需要重绘
    return oldDelegate.barHeights != barHeights || // 如果音柱高度发生变化
           oldDelegate.maxHeightPercentage != maxHeightPercentage; // 如果最大高度比例改变
  }
}
