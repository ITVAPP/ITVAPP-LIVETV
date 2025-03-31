import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// 性能优化：提升颜色常量
const List<Color> _googleColors = [
  Color(0xFF4285F4),
  Color(0xFFDB4437),
  Color(0xFFF4B400),
  Color(0xFF0F9D58),
  Color(0xFF4285F4),
  Color(0xFFEB144C),
  Colors.purple,
];

class _BarCharacteristics {
  final double baseFrequency;
  final double amplitude;    
  final double speed;       
  
  const _BarCharacteristics({
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
  final double horizontalPadding;

  const DynamicAudioBars({
    Key? key,
    this.maxHeight,
    this.barWidth,
    this.animationSpeed = const Duration(milliseconds: 50),
    this.smoothness = 0.6,
    this.respectDeviceOrientation = true,
    this.horizontalPadding = 18.0,
  }) : assert(maxHeight == null || maxHeight > 0),
       assert(barWidth == null || barWidth > 0),
       assert(smoothness >= 0 && smoothness <= 1.0),
       super(key: key);

  @override
  DynamicAudioBarsState createState() => DynamicAudioBarsState();
}

class DynamicAudioBarsState extends State<DynamicAudioBars>
    with SingleTickerProviderStateMixin {
  // 性能优化：使用late final
  late final Random _random = Random();
  final ValueNotifier<List<double>> _heightsNotifier = ValueNotifier<List<double>>([]);
  final List<int> _colorIndices = [];
  late Timer _timer;
  Timer? _startupTimer;
  bool _isAnimating = false;
  
  final List<_BarCharacteristics> _barCharacteristics = [];
  final List<_BarDynamics> _barDynamics = [];

  // 新增：缓存effectiveBarWidth和effectiveMaxHeight，避免重复计算
  double? _cachedBarWidth;
  double? _cachedMaxHeight;

  // 修改代码开始
  /// 生成条形图特性，包含频率、振幅和速度
  _BarCharacteristics _generateCharacteristics(int index, int totalBars) {
    final position = index / totalBars;
    return _BarCharacteristics(
      baseFrequency: 0.1 + (position * 0.4), // 基础频率，随位置线性增加
      amplitude: 0.8 - (position * 0.3),     // 振幅，随位置减小
      speed: 0.5 + (position * 1.5),         // 速度，随位置加快
    );
  }

  /// 更新所有条形图的高度，应用物理模拟和阻尼效果
  void _updateBars(Timer timer) {
    if (!_isAnimating) return;

    final currentHeights = _heightsNotifier.value;
    if (currentHeights.isEmpty || 
        currentHeights.length != _barDynamics.length || 
        currentHeights.length != _barCharacteristics.length) {
      return; // 防止长度不匹配导致越界
    }

    final newHeights = List<double>.generate(
      currentHeights.length,
      (index) {
        final dynamics = _barDynamics[index];
        final chars = _barCharacteristics[index];
        
        dynamics.phase += chars.speed * 0.1; // 相位随时间和速度递增
        
        final baseHeight = chars.baseFrequency;
        final noise = _random.nextDouble() * 0.3; // 随机噪声增加自然感
        final wave = sin(dynamics.phase) * chars.amplitude; // 正弦波模拟
        
        final targetHeight = (baseHeight + wave * 0.3 + noise * 0.2).clamp(0.1, 1.0);
        
        final currentHeight = currentHeights[index];
        final heightDiff = targetHeight - currentHeight;
        dynamics.acceleration = heightDiff * 0.8; // 加速度基于目标高度差
        
        dynamics.velocity += dynamics.acceleration;
        dynamics.applyDamping(0.1); // 应用阻尼减少震荡
        
        final newHeight = (currentHeight + dynamics.velocity).clamp(0.1, 1.0);
            
        return (currentHeight * widget.smoothness +
                newHeight * (1 - widget.smoothness))
            .clamp(0.1, 1.0); // 平滑过渡
      },
    );

    _heightsNotifier.value = newHeights;
  }
  // 修改代码结束

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.animationSpeed, _updateBars);
    _startupTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isAnimating = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final orientation = MediaQuery.of(context).orientation;
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        
        final availableWidth = constraints.maxWidth - (widget.horizontalPadding * 2);
        
        // 修改代码开始
        // 使用缓存避免重复计算
        _cachedBarWidth ??= widget.barWidth ?? 
          (widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? 18.0 * devicePixelRatio
              : 12.0 * devicePixelRatio);

        _cachedMaxHeight ??= widget.maxHeight ??
          (widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? constraints.maxHeight * 0.38
              : constraints.maxHeight * 0.18);

        final effectiveBarWidth = _cachedBarWidth!;
        final effectiveMaxHeight = _cachedMaxHeight!;
        // 修改代码结束

        final numberOfBars = ((availableWidth - AudioBarsPainter.spacing) / 
          (effectiveBarWidth + AudioBarsPainter.spacing)).floor();

        if (_heightsNotifier.value.length != numberOfBars) {
          _colorIndices.clear();
          _barCharacteristics.clear();
          _barDynamics.clear();
          
          for (int i = 0; i < numberOfBars; i++) {
            _colorIndices.add(_random.nextInt(7));
            _barCharacteristics.add(_generateCharacteristics(i, numberOfBars));
            _barDynamics.add(_BarDynamics());
          }

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
                    size: Size(
                      numberOfBars * (effectiveBarWidth + AudioBarsPainter.spacing) - AudioBarsPainter.spacing,
                      effectiveMaxHeight
                    ),
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

  void pauseAnimation() => setState(() => _isAnimating = false);
  void resumeAnimation() => setState(() => _isAnimating = true);

  // 修改代码开始
  @override
  void dispose() {
    _timer.cancel();
    _startupTimer?.cancel();
    _startupTimer = null; // 防止重复释放
    _heightsNotifier.value = []; // 清空值以释放内存
    _heightsNotifier.dispose();
    super.dispose();
  }
  // 修改代码结束
}

class AudioBarsPainter extends CustomPainter {
  final List<double> barHeights;
  final double maxHeight;
  final double barWidth;
  final double containerHeight;
  final List<int> colorIndices;
  final List<double> maxHeightRanges;
  static const double spacing = 4.0;

  // 性能优化：复用Path对象
  final Path _barPath = Path();

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
    if (barHeights.isEmpty || 
        barHeights.length != colorIndices.length) {
      return; // 防止长度不匹配
    }

    for (int i = 0; i < barHeights.length; i++) {
      final color = _googleColors[colorIndices[i]];
      
      final paint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;

      final barHeight = barHeights[i] * maxHeight;
      final barX = i * (barWidth + spacing);
      final rect = Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight);

      _barPath.reset();
      _barPath.addRect(rect);

      canvas.drawShadow(
        _barPath,
        Colors.black,
        3.0,
        true
      );
      
      canvas.drawRect(rect, paint);
    }
  }

  // 修改代码开始
  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights ||
           oldDelegate.maxHeight != maxHeight ||
           oldDelegate.barWidth != barWidth ||
           oldDelegate.colorIndices != colorIndices; // 移除maxHeightRanges比较，因未使用
  }
  // 修改代码结束
}
