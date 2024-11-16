import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class _BarCharacteristics {
  final double baseFrequency;
  final double amplitude;    
  final double speed;       
  
  _BarCharacteristics({
    required this.baseFrequency,
    required this.amplitude,
    required this.speed,
  });
}

class _BarDynamics {
  double velocity = 0;     
  double acceleration = 0;  
  double phase = 0;        
  
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
  final double horizontalPadding; // 新增水平边距参数

  const DynamicAudioBars({
    Key? key,
    this.maxHeight,
    this.barWidth,
    this.animationSpeed = const Duration(milliseconds: 50),
    this.smoothness = 0.6,
    this.respectDeviceOrientation = true,
    this.horizontalPadding = 18.0, // 默认水平边距
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
  bool _isAnimating = false; // 初始状态设为false
  final Random _random = Random();
  
  final List<_BarCharacteristics> _barCharacteristics = [];
  final List<_BarDynamics> _barDynamics = [];

  // 新增：动画延迟启动的计时器
  Timer? _startupTimer;

  _BarCharacteristics _generateCharacteristics(int index, int totalBars) {
    final position = index / totalBars;
    
    return _BarCharacteristics(
      baseFrequency: 0.1 + (position * 0.4),
      amplitude: 0.8 - (position * 0.3),
      speed: 0.5 + (position * 1.5),
    );
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.animationSpeed, _updateBars);
    
    // 新增：3秒后启动动画
    _startupTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isAnimating = true;
        });
      }
    });
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
        
        dynamics.phase += chars.speed * 0.1;
        
        final baseHeight = chars.baseFrequency;
        final noise = _random.nextDouble() * 0.3;
        final wave = sin(dynamics.phase) * chars.amplitude;
        
        final targetHeight = (baseHeight + wave * 0.3 + noise * 0.2).clamp(0.1, 1.0);
        
        final currentHeight = currentHeights[index];
        final heightDiff = targetHeight - currentHeight;
        dynamics.acceleration = heightDiff * 0.8;
        
        dynamics.velocity += dynamics.acceleration;
        dynamics.applyDamping(0.1);
        
        final newHeight = (currentHeight + dynamics.velocity).clamp(0.1, 1.0);
            
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
    _startupTimer?.cancel(); // 新增：清理启动计时器
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
        
        // 计算实际可用宽度（减去左右边距）
        final availableWidth = constraints.maxWidth - (widget.horizontalPadding * 2);
        
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

        // 使用可用宽度计算音柱数量
        // 使用 AudioBarsPainter.spacing 计算音柱数量
int numberOfBars = ((availableWidth - AudioBarsPainter.spacing) / (effectiveBarWidth + AudioBarsPainter.spacing)).floor();

        if (_heightsNotifier.value.length != numberOfBars) {
          _colorIndices.clear();
          _barCharacteristics.clear();
          _barDynamics.clear();
          
          for (int i = 0; i < numberOfBars; i++) {
            _colorIndices.add(_random.nextInt(7));
            _barCharacteristics.add(_generateCharacteristics(i, numberOfBars));
            _barDynamics.add(_BarDynamics());
          }

          // 初始化时所有音柱都是最低高度 0.1
          _heightsNotifier.value = List<double>.generate(
            numberOfBars,
            (index) => 0.1,
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: Align(
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
  static const double spacing = 4.0; // 音柱之间的间距

  final List<Color> googleColors = [
    Color(0xFF4285F4),
    Color(0xFFDB4437),
    Color(0xFFF4B400),
    Color(0xFF0F9D58),
    Color(0xFF4285F4),
    Color(0xFFEB144C),
    Colors.purple,
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
      
      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.fill;

      final barHeight = barHeights[i] * maxHeight;
      final barX = i * (barWidth + spacing);
      final rect = Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight);

      canvas.drawShadow(
        Path()..addRect(rect),
        Colors.black,
        3.0,
        true
      );
      
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
