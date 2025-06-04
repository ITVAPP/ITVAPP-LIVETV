import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// 定义Google风格的颜色列表
const List<Color> _googleColors = [
  Color(0xFF4285F4), // 蓝色
  Color(0xFFDB4437), // 红色
  Color(0xFFF4B400), // 黄色
  Color(0xFF0F9D58), // 绿色
  Color(0xFFFF5722), // 橙色
  Color(0xFFEB144C), // 粉红色
  Colors.purple,      // 紫色
];

// 定义条形图的静态特性：频率、振幅和速度
class _BarCharacteristics {
  final double baseFrequency; // 基础频率
  final double amplitude;     // 振幅
  final double speed;         // 变化速度
  
  const _BarCharacteristics({
    required this.baseFrequency,
    required this.amplitude,
    required this.speed,
  });
}

// 定义条形图的动态属性：速度、加速度和相位
class _BarDynamics {
  double velocity = 0;      // 当前速度
  double acceleration = 0;  // 当前加速度
  double phase = 0;         // 当前相位
  
  // 应用阻尼效果，减缓速度变化
  void applyDamping(double dampingFactor) {
    velocity *= (1 - dampingFactor);
  }
}

// 动态音频条形图组件，支持高度动画和设备方向适配
class DynamicAudioBars extends StatefulWidget {
  final double? maxHeight;              // 最大高度，可选
  final double? barWidth;               // 条形宽度，可选
  final Duration animationSpeed;        // 动画速度，默认50ms
  final double smoothness;              // 平滑度，范围0-1
  final bool respectDeviceOrientation;  // 是否适配设备方向
  final double horizontalPadding;       // 水平内边距

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
  // 性能优化：延迟初始化随机数生成器
  late final Random _random = Random();
  
  // 使用单个列表存储高度，避免频繁创建新列表
  late List<double> _heights;
  bool _heightsInitialized = false;
  
  final List<int> _colorIndices = [];       // 颜色索引列表
  late Timer _timer;                        // 动画定时器
  Timer? _startupTimer;                     // 启动延迟定时器
  bool _isAnimating = false;                // 动画运行状态
  
  final List<_BarCharacteristics> _barCharacteristics = []; // 条形特性列表
  final List<_BarDynamics> _barDynamics = [];               // 条形动态列表
  
  // 缓存计算结果
  int _cachedNumberOfBars = 0;
  double _cachedBarWidth = 0;
  double _cachedMaxHeight = 0;
  
  // 缓存sin值表，避免重复计算
  static const int _sinTableSize = 360;
  static final List<double> _sinTable = List.generate(
    _sinTableSize,
    (i) => sin(i * pi / 180),
  );
  
  // 获取缓存的sin值
  double _getCachedSin(double phase) {
    final degrees = (phase * 180 / pi) % 360;
    final index = degrees.toInt() % _sinTableSize;
    return _sinTable[index];
  }

  /// 生成条形图特性，包含频率、振幅和速度
  _BarCharacteristics _generateCharacteristics(int index, int totalBars) {
    final position = index / totalBars;              // 计算条形位置比例
    return _BarCharacteristics(
      baseFrequency: 0.1 + (position * 0.4),         // 基础频率，随位置线性增加
      amplitude: 0.8 - (position * 0.3),             // 振幅，随位置减小
      speed: 0.5 + (position * 1.5),                 // 速度，随位置加快
    );
  }

  /// 更新所有条形图的高度，应用物理模拟和阻尼效果
  void _updateBars(Timer timer) {
    if (!_isAnimating || !_heightsInitialized) return;

    final barCount = _heights.length;
    if (barCount == 0 || 
        barCount != _barDynamics.length || 
        barCount != _barCharacteristics.length) {
      return;
    }

    // 直接修改现有列表，而不是创建新列表
    for (int i = 0; i < barCount; i++) {
      final dynamics = _barDynamics[i];
      final chars = _barCharacteristics[i];
      
      dynamics.phase += chars.speed * 0.1;
      
      final baseHeight = chars.baseFrequency;
      final noise = _random.nextDouble() * 0.3;
      final wave = _getCachedSin(dynamics.phase) * chars.amplitude;
      
      final targetHeight = (baseHeight + wave * 0.3 + noise * 0.2).clamp(0.1, 1.0);
      final currentHeight = _heights[i];
      final heightDiff = targetHeight - currentHeight;
      
      dynamics.acceleration = heightDiff * 0.8;
      dynamics.velocity += dynamics.acceleration;
      dynamics.applyDamping(0.1);
      
      final newHeight = (currentHeight + dynamics.velocity).clamp(0.1, 1.0);
      
      // 应用平滑过渡
      _heights[i] = (currentHeight * widget.smoothness + newHeight * (1 - widget.smoothness))
          .clamp(0.1, 1.0);
    }

    // 触发重绘
    if (mounted) {
      setState(() {});
    }
  }

  // 初始化或更新条形数量
  void _updateBarCount(int newCount) {
    if (newCount == _cachedNumberOfBars) return;
    
    _cachedNumberOfBars = newCount;
    _colorIndices.clear();
    _barCharacteristics.clear();
    _barDynamics.clear();
    
    // 初始化或调整高度列表大小
    if (!_heightsInitialized) {
      _heights = List<double>.filled(newCount, 0.1);
      _heightsInitialized = true;
    } else {
      // 调整列表大小
      if (_heights.length < newCount) {
        _heights.addAll(List<double>.filled(newCount - _heights.length, 0.1));
      } else if (_heights.length > newCount) {
        _heights.removeRange(newCount, _heights.length);
      }
    }
    
    // 初始化其他属性
    for (int i = 0; i < newCount; i++) {
      _colorIndices.add(_random.nextInt(_googleColors.length));
      _barCharacteristics.add(_generateCharacteristics(i, newCount));
      _barDynamics.add(_BarDynamics());
    }
  }

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

        // 计算条形宽度和最大高度
        final effectiveBarWidth = widget.barWidth ?? 
          (widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? 18.0 * devicePixelRatio
              : 12.0 * devicePixelRatio);
        
        final effectiveMaxHeight = widget.maxHeight ??
          (widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? constraints.maxHeight * 0.38
              : constraints.maxHeight * 0.18);

        // 只在值变化时更新缓存
        if (_cachedBarWidth != effectiveBarWidth || _cachedMaxHeight != effectiveMaxHeight) {
          _cachedBarWidth = effectiveBarWidth;
          _cachedMaxHeight = effectiveMaxHeight;
        }

        final numberOfBars = ((availableWidth - AudioBarsPainter.spacing) / 
          (effectiveBarWidth + AudioBarsPainter.spacing)).floor();

        // 更新条形数量
        _updateBarCount(numberOfBars);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(
                  numberOfBars * (effectiveBarWidth + AudioBarsPainter.spacing) - AudioBarsPainter.spacing,
                  effectiveMaxHeight
                ),
                painter: AudioBarsPainter(
                  _heightsInitialized ? _heights : [],
                  maxHeight: effectiveMaxHeight,
                  barWidth: effectiveBarWidth,
                  containerHeight: constraints.maxHeight,
                  colorIndices: _colorIndices,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 暂停动画
  void pauseAnimation() => setState(() => _isAnimating = false);
  
  // 恢复动画
  void resumeAnimation() => setState(() => _isAnimating = true);

  @override
  void dispose() {
    _timer.cancel();
    _startupTimer?.cancel();
    super.dispose();
  }
}

// 自定义绘制器，负责渲染音频条形图
class AudioBarsPainter extends CustomPainter {
  final List<double> barHeights;
  final double maxHeight;
  final double barWidth;
  final double containerHeight;
  final List<int> colorIndices;
  static const double spacing = 4.0;

  // 缓存Paint对象，避免重复创建
  static final Map<Color, Paint> _paintCache = {};
  
  // 复用Path对象
  final Path _barPath = Path();
  
  // 缓存上一次的条形数量，用于判断是否需要清理缓存
  static int _lastBarCount = 0;

  AudioBarsPainter(
    this.barHeights, {
    required this.maxHeight,
    required this.barWidth,
    required this.containerHeight,
    required this.colorIndices,
  });

  // 获取缓存的Paint对象
  Paint _getCachedPaint(Color color) {
    // 如果条形数量变化很大，清理缓存
    if (_paintCache.length > 20 && barHeights.length != _lastBarCount) {
      _paintCache.clear();
      _lastBarCount = barHeights.length;
    }
    
    return _paintCache.putIfAbsent(
      color,
      () => Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty || 
        barHeights.length != colorIndices.length) {
      return;
    }

    // 使用批量绘制优化
    for (int i = 0; i < barHeights.length; i++) {
      final colorIndex = colorIndices[i] % _googleColors.length;
      final color = _googleColors[colorIndex];
      final paint = _getCachedPaint(color);

      final barHeight = barHeights[i] * maxHeight;
      final barX = i * (barWidth + spacing);
      final barY = size.height - barHeight;
      
      // 复用Path对象
      _barPath.reset();
      _barPath.addRect(Rect.fromLTWH(barX, barY, barWidth, barHeight));

      // 绘制阴影（简化）
      canvas.drawPath(
        _barPath,
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      
      // 绘制条形
      canvas.drawPath(_barPath, paint);
    }
  }

  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    // 优化比较逻辑，只比较关键属性
    if (oldDelegate.barHeights.length != barHeights.length ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.barWidth != barWidth) {
      return true;
    }
    
    // 对于高度列表，只检查是否同一引用
    return !identical(oldDelegate.barHeights, barHeights);
  }
}
