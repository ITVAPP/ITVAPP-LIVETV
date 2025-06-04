import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// 定义Google风格颜色列表
const List<Color> _googleColors = [
  Color(0xFF4285F4), // 蓝色
  Color(0xFFDB4437), // 红色
  Color(0xFFF4B400), // 黄色
  Color(0xFF0F9D58), // 绿色
  Color(0xFFFF5722), // 橙色
  Color(0xFFEB144C), // 粉红色
  Colors.purple,      // 紫色
];

// 定义条形图静态特性
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

// 定义条形图动态属性
class _BarDynamics {
  double velocity = 0;      // 当前速度
  double acceleration = 0;  // 当前加速度
  double phase = 0;         // 当前相位
  
  // 应用阻尼，减缓速度变化
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
  // 延迟初始化Random
  late final Random _random = Random();
  
  // 存储条形高度
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

  // 生成条形特性（频率、振幅、速度）
  _BarCharacteristics _generateCharacteristics(int index, int totalBars) {
    final position = index / totalBars;              // 计算条形位置比例
    return _BarCharacteristics(
      baseFrequency: 0.1 + (position * 0.4),         // 频率随位置线性增加
      amplitude: 0.8 - (position * 0.3),             // 振幅随位置减小
      speed: 0.5 + (position * 1.5),                 // 速度随位置加快
    );
  }

  // 更新条形高度，应用物理模拟和阻尼
  void _updateBars(Timer timer) {
    // 检查动画状态和高度初始化
    if (!_isAnimating || !_heightsInitialized) return;

    final barCount = _heights.length;
    // 验证数据一致性
    if (barCount == 0 || 
        barCount != _barDynamics.length || 
        barCount != _barCharacteristics.length) {
      return;
    }

    // 更新每个条形高度
    for (int i = 0; i < barCount; i++) {
      final dynamics = _barDynamics[i];
      final chars = _barCharacteristics[i];
      
      // 更新相位
      dynamics.phase += chars.speed * 0.1;
      
      // 计算目标高度，结合波形和噪声
      final baseHeight = chars.baseFrequency;
      final noise = _random.nextDouble() * 0.3;
      final wave = _getCachedSin(dynamics.phase) * chars.amplitude;
      
      // 限制目标高度范围
      final targetHeight = (baseHeight + wave * 0.3 + noise * 0.2).clamp(0.1, 1.0);
      final currentHeight = _heights[i];
      final heightDiff = targetHeight - currentHeight;
      
      // 更新加速度和速度
      dynamics.acceleration = heightDiff * 0.8;
      dynamics.velocity += dynamics.acceleration;
      dynamics.applyDamping(0.1);
      
      // 计算新高度并限制范围
      final newHeight = (currentHeight + dynamics.velocity).clamp(0.1, 1.0);
      
      // 应用平滑过渡
      _heights[i] = (currentHeight * widget.smoothness + newHeight * (1 - widget.smoothness))
          .clamp(0.1, 1.0);
    }

    // 触发界面重绘
    if (mounted) {
      setState(() {});
    }
  }

  // 初始化或更新条形数量
  void _updateBarCount(int newCount) {
    // 检查是否需要更新
    if (newCount == _cachedNumberOfBars) return;
    
    _cachedNumberOfBars = newCount;
    _colorIndices.clear();
    _barCharacteristics.clear();
    _barDynamics.clear();
    
    // 初始化或调整高度列表
    if (!_heightsInitialized) {
      _heights = List<double>.filled(newCount, 0.1);
      _heightsInitialized = true;
    } else {
      // 扩展或截断高度列表
      if (_heights.length < newCount) {
        _heights.addAll(List<double>.filled(newCount - _heights.length, 0.1));
      } else if (_heights.length > newCount) {
        _heights.removeRange(newCount, _heights.length);
      }
    }
    
    // 初始化颜色、特性、动态属性
    for (int i = 0; i < newCount; i++) {
      _colorIndices.add(_random.nextInt(_googleColors.length));
      _barCharacteristics.add(_generateCharacteristics(i, newCount));
      _barDynamics.add(_BarDynamics());
    }
  }

  @override
  void initState() {
    super.initState();
    // 启动动画定时器
    _timer = Timer.periodic(widget.animationSpeed, _updateBars);
    // 延迟5秒启动动画
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

        // 更新缓存值
        if (_cachedBarWidth != effectiveBarWidth || _cachedMaxHeight != effectiveMaxHeight) {
          _cachedBarWidth = effectiveBarWidth;
          _cachedMaxHeight = effectiveMaxHeight;
        }

        // 计算条形数量
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
    // 清理定时器
    _timer.cancel();
    _startupTimer?.cancel();
    super.dispose();
  }
}

// 自定义绘制器，渲染音频条形图
class AudioBarsPainter extends CustomPainter {
  final List<double> barHeights;
  final double maxHeight;
  final double barWidth;
  final double containerHeight;
  final List<int> colorIndices;
  static const double spacing = 4.0;

  // 缓存Paint对象
  static final Map<Color, Paint> _paintCache = {};
  
  // 复用Path对象
  final Path _barPath = Path();
  
  // 缓存上一次条形数量
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
    // 清理过大缓存
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
    // 验证数据有效性
    if (barHeights.isEmpty || 
        barHeights.length != colorIndices.length) {
      return;
    }

    // 批量绘制条形
    for (int i = 0; i < barHeights.length; i++) {
      final colorIndex = colorIndices[i] % _googleColors.length;
      final color = _googleColors[colorIndex];
      final paint = _getCachedPaint(color);

      // 计算条形位置和高度
      final barHeight = barHeights[i] * maxHeight;
      final barX = i * (barWidth + spacing);
      final barY = size.height - barHeight;
      
      // 绘制矩形
      _barPath.reset();
      _barPath.addRect(Rect.fromLTWH(barX, barY, barWidth, barHeight));

      // 绘制阴影
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
    // 重绘判断
    if (oldDelegate.barHeights.length != barHeights.length ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.barWidth != barWidth) {
      return true;
    }
    
    // 检查高度列表引用
    return !identical(oldDelegate.barHeights, barHeights);
  }
}
