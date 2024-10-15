import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DynamicAudioBars extends StatefulWidget {
  final double maxHeightPercentage; // 音柱最大高度占播放器高度的百分比
  final Duration animationSpeed; // 控制音柱动画的速度

  const DynamicAudioBars({
    Key? key,
    this.maxHeightPercentage = 0.8, // 最大高度占比
    this.animationSpeed = const Duration(milliseconds: 100), // 动画速度
  }) : super(key: key);

  @override
  _DynamicAudioBarsState createState() => _DynamicAudioBarsState();
}

class _DynamicAudioBarsState extends State<DynamicAudioBars>
    with SingleTickerProviderStateMixin {
  List<double> _barHeights = [];
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    // 定时器模拟动态更新音柱的高度
    _timer = Timer.periodic(widget.animationSpeed, (timer) {
      setState(() {
        for (int i = 0; i < _barHeights.length; i++) {
          _barHeights[i] = Random().nextDouble(); // 随机生成 0 到 1 之间的值
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据当前布局宽度，动态计算音柱的数量，音柱宽度设为20像素
        int numberOfBars = (constraints.maxWidth / 20).floor();
        if (_barHeights.length != numberOfBars) {
          _barHeights = List<double>.filled(numberOfBars, 0.0);
        }

        return CustomPaint(
          size: Size(double.infinity, constraints.maxHeight),
          painter: AudioBarsPainter(
            _barHeights,
            maxHeightPercentage: widget.maxHeightPercentage, // 设置最大高度占比
          ),
        );
      },
    );
  }
}

class AudioBarsPainter extends CustomPainter {
  final List<double> barHeights;
  final double maxHeightPercentage;

  AudioBarsPainter(this.barHeights, {this.maxHeightPercentage = 0.8});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / barHeights.length;
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
      final barX = i * barWidth;

      // 绘制矩形音柱
      canvas.drawRect(
        Rect.fromLTWH(barX, size.height - barHeight, barWidth - 2, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
