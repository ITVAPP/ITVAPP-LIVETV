import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DynamicAudioBars extends StatefulWidget {
  final double? maxHeight; // 音柱最大高度（像素）
  final double? barWidth; // 音柱宽度（像素）
  final Duration animationSpeed; // 动画更新速度
  final double smoothness; // 控制音柱高度过渡的平滑度参数
  final bool respectDeviceOrientation; // 是否根据设备方向调整尺寸

  const DynamicAudioBars({
    Key? key,
    this.maxHeight,
    this.barWidth,
    this.animationSpeed = const Duration(milliseconds: 100), // 更快的更新速度
    this.smoothness = 0.8, // 增加平滑度
    this.respectDeviceOrientation = true,
  }) : assert(maxHeight == null || maxHeight > 0),
       assert(barWidth == null || barWidth > 0),
       assert(smoothness >= 0 && smoothness <= 1.0),
       super(key: key);

  @override
  DynamicAudioBarsState createState() => DynamicAudioBarsState();
}

class DynamicAudioBarsState extends State<DynamicAudioBars>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<List<double>> _heightsNotifier = ValueNotifier<List<double>>([]);
  late Timer _timer;
  bool _isAnimating = true;
  final Random _random = Random();

  // 生成更自然的目标高度
  double _generateTargetHeight() {
    // 使用正弦波生成更自然的波动
    final time = DateTime.now().millisecondsSinceEpoch / 1000;
    final baseLine = (sin(time) + 1) / 2; // 基准线，范围在0-1之间
    
    // 添加随机噪声，但保持在合理范围内
    final noise = _random.nextDouble() * 0.3 - 0.15; // 较小的随机波动
    return (baseLine + noise).clamp(0.1, 0.95); // 确保高度不会太低或太高
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.animationSpeed, (timer) {
      if (!_isAnimating) return;

      final currentHeights = _heightsNotifier.value;
      final newHeights = List<double>.generate(
        currentHeights.length,
        (index) {
          final currentHeight = currentHeights[index];
          final targetHeight = _generateTargetHeight();
          
          // 使用更平滑的插值
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
        final orientation = MediaQuery.of(context).orientation;
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        
        // 计算有效的音柱宽度
        double effectiveBarWidth;
        if (widget.barWidth != null) {
          effectiveBarWidth = widget.barWidth!;
        } else {
          effectiveBarWidth = widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? 8.0 * devicePixelRatio
              : 12.0 * devicePixelRatio;
        }

        // 计算有效的最大高度
        double effectiveMaxHeight;
        if (widget.maxHeight != null) {
          effectiveMaxHeight = widget.maxHeight!;
        } else {
          // 根据屏幕方向设置默认高度
          effectiveMaxHeight = widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? constraints.maxHeight * 0.3 // 横屏时高度较小
              : constraints.maxHeight * 0.2; // 竖屏时高度较大
        }

        // 计算可以容纳的音柱数量
        int numberOfBars = ((constraints.maxWidth - 8.0) / (effectiveBarWidth + 8.0)).floor();

        if (_heightsNotifier.value.length != numberOfBars) {
          _heightsNotifier.value = List<double>.filled(numberOfBars, 0.0);
        }

        return RepaintBoundary(
          child: ValueListenableBuilder<List<double>>(
            valueListenable: _heightsNotifier,
            builder: (context, heights, _) {
              return CustomPaint(
                size: Size(double.infinity, effectiveMaxHeight),
                painter: AudioBarsPainter(
                  heights,
                  maxHeight: effectiveMaxHeight,
                  barWidth: effectiveBarWidth,
                  containerHeight: constraints.maxHeight,
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
  final double maxHeight;
  final double barWidth;
  final double containerHeight;
  final double spacing = 8.0;

  final List<Color> googleColors = [
    Color(0xFF4285F4), // Google Blue
    Color(0xFFDB4437), // Google Red
    Color(0xFFF4B400), // Google Yellow
    Color(0xFF0F9D58), // Google Green
    Color(0xFF4285F4), // Google Blue
  ];

  AudioBarsPainter(
    this.barHeights, {
    required this.maxHeight,
    required this.barWidth,
    required this.containerHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return;

    final totalSpacing = spacing * (barHeights.length - 1);

    for (int i = 0; i < barHeights.length; i++) {
      final colorIndex = i % googleColors.length;
      final paint = Paint()
        ..color = googleColors[colorIndex]
        ..style = PaintingStyle.fill;

      final barHeight = barHeights[i] * maxHeight;
      final barX = i * (barWidth + spacing);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights ||
           oldDelegate.maxHeight != maxHeight ||
           oldDelegate.barWidth != barWidth;
  }
}
