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
  final ValueNotifier<List<double>> _heightsNotifier = ValueNotifier<List<double>>([]); // 高度变化通知器
  final List<int> _colorIndices = [];       // 颜色索引列表
  late Timer _timer;                        // 动画定时器
  Timer? _startupTimer;                     // 启动延迟定时器
  bool _isAnimating = false;                // 动画运行状态
  
  final List<_BarCharacteristics> _barCharacteristics = []; // 条形特性列表
  final List<_BarDynamics> _barDynamics = [];               // 条形动态列表

  // 缓存有效宽度和高度，避免重复计算
  double? _cachedBarWidth;
  double? _cachedMaxHeight;

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
    if (!_isAnimating) return;                       // 未动画时直接返回

    final currentHeights = _heightsNotifier.value;   // 获取当前高度列表
    if (currentHeights.isEmpty || 
        currentHeights.length != _barDynamics.length || 
        currentHeights.length != _barCharacteristics.length) {
      return;                                        // 防止长度不匹配导致越界
    }

    final newHeights = List<double>.generate(
      currentHeights.length,
      (index) {
        final dynamics = _barDynamics[index];        // 当前动态属性
        final chars = _barCharacteristics[index];    // 当前静态特性
        
        dynamics.phase += chars.speed * 0.1;         // 相位随时间和速度递增
        
        final baseHeight = chars.baseFrequency;      // 基础高度
        final noise = _random.nextDouble() * 0.3;    // 随机噪声增加自然感
        final wave = sin(dynamics.phase) * chars.amplitude; // 正弦波模拟
        
        final targetHeight = (baseHeight + wave * 0.3 + noise * 0.2).clamp(0.1, 1.0); // 计算目标高度
        final currentHeight = currentHeights[index]; // 当前高度
        final heightDiff = targetHeight - currentHeight; // 高度差
        
        dynamics.acceleration = heightDiff * 0.8;    // 加速度基于目标高度差
        dynamics.velocity += dynamics.acceleration;  // 更新速度
        dynamics.applyDamping(0.1);                  // 应用阻尼减少震荡
        
        final newHeight = (currentHeight + dynamics.velocity).clamp(0.1, 1.0); // 新高度
        
        return (currentHeight * widget.smoothness + newHeight * (1 - widget.smoothness))
            .clamp(0.1, 1.0);                       // 平滑过渡
      },
    );

    _heightsNotifier.value = newHeights;            // 更新高度通知器
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.animationSpeed, _updateBars); // 初始化动画定时器
    _startupTimer = Timer(const Duration(seconds: 5), () {       // 5秒后启动动画
      if (mounted) {
        setState(() {
          _isAnimating = true;                            // 标记动画开始
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final orientation = MediaQuery.of(context).orientation;        // 获取设备方向
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio; // 获取设备像素比
        final availableWidth = constraints.maxWidth - (widget.horizontalPadding * 2); // 计算可用宽度

        // 使用缓存避免重复计算条形宽度和最大高度
        _cachedBarWidth ??= widget.barWidth ?? 
          (widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? 18.0 * devicePixelRatio
              : 12.0 * devicePixelRatio);
        _cachedMaxHeight ??= widget.maxHeight ??
          (widget.respectDeviceOrientation && orientation == Orientation.landscape
              ? constraints.maxHeight * 0.38
              : constraints.maxHeight * 0.18);

        final effectiveBarWidth = _cachedBarWidth!;     // 有效条形宽度
        final effectiveMaxHeight = _cachedMaxHeight!;   // 有效最大高度

        final numberOfBars = ((availableWidth - AudioBarsPainter.spacing) / 
          (effectiveBarWidth + AudioBarsPainter.spacing)).floor(); // 计算条形数量

        if (_heightsNotifier.value.length != numberOfBars) { // 高度数量不匹配时初始化
          _colorIndices.clear();
          _barCharacteristics.clear();
          _barDynamics.clear();
          
          for (int i = 0; i < numberOfBars; i++) {
            _colorIndices.add(_random.nextInt(7));         // 随机分配颜色索引
            _barCharacteristics.add(_generateCharacteristics(i, numberOfBars)); // 生成特性
            _barDynamics.add(_BarDynamics());              // 初始化动态属性
          }

          _heightsNotifier.value = List<double>.generate(
            numberOfBars,
            (index) => 0.1,                              // 初始高度设为0.1
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding), // 应用水平内边距
          child: Align(
            alignment: Alignment.bottomCenter,           // 底部居中对齐
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

  // 暂停动画
  void pauseAnimation() => setState(() => _isAnimating = false);
  
  // 恢复动画
  void resumeAnimation() => setState(() => _isAnimating = true);

  @override
  void dispose() {
    _timer.cancel();                    // 取消动画定时器
    _startupTimer?.cancel();            // 取消启动定时器
    _startupTimer = null;               // 防止重复释放
    _heightsNotifier.value = [];        // 清空值以释放内存
    _heightsNotifier.dispose();         // 释放通知器
    super.dispose();
  }
}

// 自定义绘制器，负责渲染音频条形图
class AudioBarsPainter extends CustomPainter {
  final List<double> barHeights;       // 条形高度列表
  final double maxHeight;              // 最大高度
  final double barWidth;               // 条形宽度
  final double containerHeight;        // 容器高度
  final List<int> colorIndices;        // 颜色索引列表
  final List<double> maxHeightRanges;  // 最大高度范围（未使用）
  static const double spacing = 4.0;   // 条形间距

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
      return;                                // 防止长度不匹配
    }

    for (int i = 0; i < barHeights.length; i++) {
      final color = _googleColors[colorIndices[i]]; // 获取条形颜色
      final paint = Paint()
        ..color = color.withOpacity(0.8)     // 设置颜色和透明度
        ..style = PaintingStyle.fill;        // 填充样式

      final barHeight = barHeights[i] * maxHeight; // 计算实际高度
      final barX = i * (barWidth + spacing);       // 计算X坐标
      final rect = Rect.fromLTWH(barX, size.height - barHeight, barWidth, barHeight); // 定义矩形

      _barPath.reset();
      _barPath.addRect(rect);              // 添加矩形路径

      canvas.drawShadow(
        _barPath,
        Colors.black,
        3.0,
        true
      );                                   // 绘制阴影
      
      canvas.drawRect(rect, paint);        // 绘制矩形
    }
  }

  @override
  bool shouldRepaint(AudioBarsPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights || // 高度变化时重绘
           oldDelegate.maxHeight != maxHeight ||   // 最大高度变化时重绘
           oldDelegate.barWidth != barWidth ||     // 宽度变化时重绘
           oldDelegate.colorIndices != colorIndices; // 颜色索引变化时重绘
  }
}
