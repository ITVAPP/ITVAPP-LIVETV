import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DynamicAudioBars extends StatefulWidget {
  final double maxHeightPercentage; // 音柱最大高度占播放器高度的百分比
  final Duration animationSpeed; // 控制音柱动画的速度
  final double smoothness; // 添加平滑度控制参数
  
  const DynamicAudioBars({
    Key? key,
    this.maxHeightPercentage = 0.8, // 最大高度占比
    this.animationSpeed = const Duration(milliseconds: 100), // 动画速度
    this.smoothness = 0.5, // 默认平滑度
  }) : assert(maxHeightPercentage > 0 && maxHeightPercentage <= 1.0),
       assert(smoothness >= 0 && smoothness <= 1.0),
       super(key: key);

  @override
  _DynamicAudioBarsState createState() => _DynamicAudioBarsState();
}

class _DynamicAudioBarsState extends State<DynamicAudioBars>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<List<double>> _heightsNotifier = ValueNotifier<List<double>>([]);
  late Timer _timer;
  bool _isAnimating = true;

  @override
  void initState() {
    super.initState();
    // 定时器模拟动态更新音柱的高度
    _timer = Timer.periodic(widget.animationSpeed, (timer) {
      if (!_isAnimating) return;
      
      final currentHeights = _heightsNotifier.value;
      final newHeights = List<double>.generate(
        currentHeights.length,
        (index) {
          // 使用平滑度参数实现过渡
          final currentHeight = currentHeights[index];
          final targetHeight = Random().nextDouble();
          return (currentHeight * widget.smoothness + 
                 targetHeight * (1 - widget.smoothness))
                 .clamp(0.0, 1.0);
        },
      );
      
      _heightsNotifier.value = newHeights;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _heightsNotifier.dispose();
    super.dispose();
  }

  // 添加暂停/继续控制方法
  void pauseAnimation() {
    setState(() {
      _isAnimating = false;
    });
  }

  void resumeAnimation() {
    setState(() {
      _isAnimating = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据当前布局宽度，动态计算音柱的数量，音柱宽度设为20像素
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        int numberOfBars = (constraints.maxWidth / (20 * devicePixelRatio)).floor();
        
        if (_heightsNotifier.value.length != numberOfBars) {
          _heightsNotifier.value = List<double>.filled(numberOfBars, 0.0);
        }
        
        return RepaintBoundary(
          child: ValueListenableBuilder<List<double>>(
            valueListenable: _heightsNotifier,
            builder: (context, heights, _) {
              return CustomPaint(
                size: Size(double.infinity, constraints.maxHeight),
                painter: AudioBarsPainter(
                  heights,
                  maxHeightPercentage: widget.maxHeightPercentage, // 设置最大高度占比
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
  final List<double> barHeights;
  final double maxHeightPercentage;
  final double spacing = 2.0; // 音柱间距

  AudioBarsPainter(this.barHeights, {this.maxHeightPercentage = 0.8});

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return;
    
    // 优化宽度计算逻辑，考虑间距
    final totalSpacing = spacing * (barHeights.length - 1);
    final barWidth = (size.width - totalSpacing) / barHeights.length;
    final maxHeight = size.height * maxHeightPercentage; // 音柱最大高度

    for (int i = 0; i < barHeights.length; i++) {
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.blueAccent.withOpacity(0.7),
            Colors.greenAccent.withOpacity(0.6),
            Colors.yellowAccent.withOpacity(0.5),
            Colors.orangeAccent.withOpacity(0.4),
            Colors.redAccent.withOpacity(0.3),
          ],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      final barHeight = barHeights[i] * maxHeight; // 随机高度 * 最大高度
      final barX = i * (barWidth + spacing);

      // 绘制矩形音柱
      canvas.drawRect(
        Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights ||
           oldDelegate.maxHeightPercentage != maxHeightPercentage;
  }
}
