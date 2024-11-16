import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// 移到外部的音柱特性类
class _BarCharacteristics {
  final double baseFrequency; // 基础频率 - 决定基本高度
  final double amplitude;     // 振幅范围 - 决定可变化范围
  final double speed;        // 变化速度 - 决定高度变化的快慢
  
  _BarCharacteristics({
    required this.baseFrequency,
    required this.amplitude,
    required this.speed,
  });
}

// 移到外部的音柱动态参数类
class _BarDynamics {
  double velocity = 0;      // 当前速度
  double acceleration = 0;  // 当前加速度
  double phase = 0;        // 当前相位
  
  // 应用阻尼效果使运动更自然
  void applyDamping(double dampingFactor) {
    velocity *= (1 - dampingFactor);
  }
}

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
    this.animationSpeed = const Duration(milliseconds: 50),  // 更快的更新速度
    this.smoothness = 0.6,  // 降低平滑度以获得更快的响应
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
  
  final List<_BarCharacteristics> _barCharacteristics = [];
  final List<_BarDynamics> _barDynamics = [];

  // 根据音柱位置生成其特性参数
  _BarCharacteristics _generateCharacteristics(int index, int totalBars) {
    // 计算音柱的相对位置（0-1之间）
    final position = index / totalBars;
    
    // 低频音柱（左侧）：振幅大，速度慢
    // 高频音柱（右侧）：振幅小，速度快
    return _BarCharacteristics(
      baseFrequency: 0.1 + (position * 0.4),  // 基础频率随位置增加
      amplitude: 0.8 - (position * 0.3),      // 振幅随位置减小
      speed: 0.5 + (position * 1.5),         // 速度随位置增加
    );
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.animationSpeed, _updateBars);
  }

  void _updateBars(Timer timer) {
    if (!_isAnimating) return;

    final currentHeights = _heightsNotifier.value;
    if (currentHeights.isEmpty) return;

    final newHeights = List<double>.generate(
      currentHeights.length,
      (index) {
        final dynamics = _barDynamics[index];
        final chars = _barCharacteristics[index];
        
        // 更新相位
        dynamics.phase += chars.speed * 0.1;
        
        // 计算新的目标高度：结合多个因素
        // 1. 基础高度
        final baseHeight = chars.baseFrequency;
        // 2. 随机噪声
        final noise = _random.nextDouble() * 0.3;
        // 3. 正弦波动
        final wave = sin(dynamics.phase) * chars.amplitude;
        
        // 组合所有因素，计算目标高度
        final targetHeight = (baseHeight + wave * 0.3 + noise * 0.2).clamp(0.1, 1.0);
        
        // 计算加速度（向目标高度移动）
        final currentHeight = currentHeights[index];
        final heightDiff = targetHeight - currentHeight;
        dynamics.acceleration = heightDiff * 0.8;
        
        // 更新速度和应用阻尼
        dynamics.velocity += dynamics.acceleration;
        dynamics.applyDamping(0.1);
        
        // 计算新高度
        final newHeight = (currentHeight + dynamics.velocity).clamp(0.1, 1.0);
            
        // 应用平滑过渡
        return (currentHeight * widget.smoothness +
                newHeight * (1 - widget.smoothness))
            .clamp(0.1, 1.0);
      },
    );

    _heightsNotifier.value = newHeights;
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
              ? 15.0 * devicePixelRatio
              : 11.0 * devicePixelRatio;
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

        if (_heightsNotifier.value.length != numberOfBars) {
          _colorIndices.clear();
          _barCharacteristics.clear();
          _barDynamics.clear();
          
          for (int i = 0; i < numberOfBars; i++) {
            _colorIndices.add(_random.nextInt(7)); // 更新为7种颜色
            _barCharacteristics.add(_generateCharacteristics(i, numberOfBars));
            _barDynamics.add(_BarDynamics());
          }

          _heightsNotifier.value = List<double>.generate(
            numberOfBars,
            (index) => 0.3 + _random.nextDouble() * 0.3,
          );
        }

        return Align(
          alignment: Alignment.bottomCenter,
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
                    maxHeightRanges: List.filled(heights.length, 1.0),
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
  final double spacing = 6.0;

  final List<Color> googleColors = [
    Color(0xFF4285F4), // Google Blue
    Color(0xFFDB4437), // Google Red
    Color(0xFFF4B400), // Google Yellow
    Color(0xFF0F9D58), // Google Green
    Color(0xFF4285F4), // Google Blue
    Color(0xFFEB144C), // Pink
    Colors.purple,     // Purple
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
      final color = googleColors[colorIndices[i]];
      
      // 创建半透明效果的画笔
      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.fill;

      final barHeight = barHeights[i] * maxHeight;
      final barX = i * (barWidth + spacing);
      final rect = Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight);

      // 绘制阴影
      canvas.drawShadow(
        Path()..addRect(rect),
        Colors.black,
        3.0,
        true
      );
      
      // 绘制音柱
      canvas.drawRect(rect, paint);
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
