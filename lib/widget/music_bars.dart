import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class DynamicAudioBars extends StatefulWidget {
  final double? maxHeight;
  final double? barWidth;
  final Duration animationSpeed;
  final double smoothness;
  final bool respectDeviceOrientation;

  const DynamicAudioBars({
    Key? key,
    this.maxHeight,
    this.barWidth,
    this.animationSpeed = const Duration(milliseconds: 100),
    this.smoothness = 0.8,
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
  final List<int> _colorIndices = [];
  late Timer _timer;
  bool _isAnimating = true;
  final Random _random = Random();
  
  // 存储每个音柱的最大高度范围
  final List<double> _maxHeightRanges = [];
  // 存储每个音柱的当前目标高度
  final List<double> _targetHeights = [];
  // 存储每个音柱的高度变化方向（1表示上升，-1表示下降）
  final List<int> _heightDirections = [];

  // 为每个音柱生成随机的最大高度范围
  double _generateMaxHeightRange() {
    return 0.2 + _random.nextDouble() * 0.7; // 生成0.2到1.0之间的随机值
  }

  // 为每个音柱生成目标高度，考虑其最大高度范围
  double _generateTargetHeight(int index) {
    if (index >= _maxHeightRanges.length) {
      return 0.0;
    }

    final maxRange = _maxHeightRanges[index];
    final currentHeight = _heightsNotifier.value[index];
    final direction = _heightDirections[index];

    // 在0到最大范围之间生成新的目标高度
    double newTarget = currentHeight + (direction * _random.nextDouble() * 0.2);

    // 如果超出范围，改变方向
    if (newTarget > maxRange) {
      _heightDirections[index] = -1;
      newTarget = maxRange;
    } else if (newTarget < 0.1) {
      _heightDirections[index] = 1;
      newTarget = 0.1;
    }

    return newTarget;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.animationSpeed, (timer) {
      if (!_isAnimating) return;

      final currentHeights = _heightsNotifier.value;
      if (currentHeights.isEmpty) return;

      final newHeights = List<double>.generate(
        currentHeights.length,
        (index) {
          final currentHeight = currentHeights[index];
          final targetHeight = _generateTargetHeight(index);
          
          // 平滑过渡到新的目标高度
          return (currentHeight * widget.smoothness +
                  targetHeight * (1 - widget.smoothness))
              .clamp(0.0, _maxHeightRanges[index]);
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
        
        double effectiveBarWidth;
        if (widget.barWidth != null) {
          effectiveBarWidth = widget.barWidth!;
        } else {
          effectiveBarWidth = widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? 8.0 * devicePixelRatio
              : 12.0 * devicePixelRatio;
        }

        double effectiveMaxHeight;
        if (widget.maxHeight != null) {
          effectiveMaxHeight = widget.maxHeight!;
        } else {
          effectiveMaxHeight = widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? constraints.maxHeight * 0.3
              : constraints.maxHeight * 0.2;
        }

        int numberOfBars = ((constraints.maxWidth - 4.0) / (effectiveBarWidth + 4.0)).floor();

        // 初始化或更新音柱相关的数据
        if (_heightsNotifier.value.length != numberOfBars) {
          // 初始化颜色索引
          _colorIndices.clear();
          for (int i = 0; i < numberOfBars; i++) {
            _colorIndices.add(_random.nextInt(5));
          }

          // 初始化最大高度范围
          _maxHeightRanges.clear();
          for (int i = 0; i < numberOfBars; i++) {
            _maxHeightRanges.add(_generateMaxHeightRange());
          }

          // 初始化高度变化方向
          _heightDirections.clear();
          for (int i = 0; i < numberOfBars; i++) {
            _heightDirections.add(_random.nextBool() ? 1 : -1);
          }

          // 初始化当前高度
          _heightsNotifier.value = List<double>.generate(
            numberOfBars,
            (index) => _random.nextDouble() * _maxHeightRanges[index],
          );
        }

        return Center(
          child: RepaintBoundary(
            child: ValueListenableBuilder<List<double>>(
              valueListenable: _heightsNotifier,
              builder: (context, heights, _) {
                return CustomPaint(
                  size: Size(numberOfBars * (effectiveBarWidth + 4.0) - 4.0, effectiveMaxHeight),
                  painter: AudioBarsPainter(
                    heights,
                    maxHeight: effectiveMaxHeight,
                    barWidth: effectiveBarWidth,
                    containerHeight: constraints.maxHeight,
                    colorIndices: _colorIndices,
                    maxHeightRanges: _maxHeightRanges,
                  ),
                );
              },
            ),
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
  final List<int> colorIndices;
  final List<double> maxHeightRanges;
  final double spacing = 5.0;

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
    required this.colorIndices,
    required this.maxHeightRanges,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return;

    for (int i = 0; i < barHeights.length; i++) {
      final paint = Paint()
        ..color = googleColors[colorIndices[i]]
        ..style = PaintingStyle.fill;

      // 根据各自的最大高度范围计算实际高度
      final barHeight = barHeights[i] * maxHeight * maxHeightRanges[i];
      final barX = i * (barWidth + spacing);

      canvas.drawRect(
        Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights ||
           oldDelegate.maxHeight != maxHeight ||
           oldDelegate.barWidth != barWidth ||
           oldDelegate.colorIndices != colorIndices ||
           oldDelegate.maxHeightRanges != maxHeightRanges;
  }
}
