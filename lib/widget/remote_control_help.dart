import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:itvapp_live_tv/generated/l10n.dart';

class RemoteControlHelp {
  /// 显示遥控器帮助对话框，展示遥控器操作指引
  static Future<void> show(BuildContext context) async {
    // 进入全屏模式
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [], // 隐藏所有系统UI
    );
    
    return showDialog(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (BuildContext context) {
        return const RemoteControlHelpDialog();
      },
    ).then((_) {
      // 对话框关闭后恢复系统UI
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values, // 恢复所有系统UI
      );
    });
  }
}

/// 遥控器帮助界面配置常量
class _RemoteHelpConfig {
  // 字体大小配置
  static const double labelFontSize = 32.0;
  static const double countdownFontSize = 28.0;
  static const double okButtonFontSize = 0.12;
  
  // 倒计时配置
  static const int countdownSeconds = 28;
  
  // 基线尺寸和缩放
  static const double baseScreenWidth = 1920;
  static const double minScale = 0.4;
  static const double maxScale = 2.5;
  
  // 遥控器尺寸
  static const double remoteWidth = 400;
  static const double remoteHeight = 600;
  
  // 布局间距
  static const double topPadding = 130;
  static const double bottomPadding = 100;
  static const double bottomTextPadding = 50;
}

class RemoteControlHelpDialog extends StatefulWidget {
  const RemoteControlHelpDialog({Key? key}) : super(key: key);

  @override
  State<RemoteControlHelpDialog> createState() => _RemoteControlHelpDialogState();
}

class _RemoteControlHelpDialogState extends State<RemoteControlHelpDialog> {
  Timer? _timer;
  int _countdown = _RemoteHelpConfig.countdownSeconds;
  bool _isClosing = false;
  
  // 简化的按键指引数据
  static const List<ButtonGuide> _buttonGuides = [
    ButtonGuide(
      labelKey: 'remotehelpup',
      buttonPosition: ButtonPosition.up,
      isLeftSide: false,
    ),
    ButtonGuide(
      labelKey: 'remotehelpleft', 
      buttonPosition: ButtonPosition.left,
      isLeftSide: false,
    ),
    ButtonGuide(
      labelKey: 'remotehelpdown',
      buttonPosition: ButtonPosition.down,
      isLeftSide: false,
    ),
    ButtonGuide(
      labelKey: 'remotehelpok',
      buttonPosition: ButtonPosition.center,
      isLeftSide: true,
    ),
    ButtonGuide(
      labelKey: 'remotehelpright',
      buttonPosition: ButtonPosition.right,
      isLeftSide: true,
    ),
    ButtonGuide(
      labelKey: 'remotehelpback',
      buttonPosition: ButtonPosition.back,
      isLeftSide: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  /// 简化的硬件键盘事件处理
  bool _handleHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent && !_isClosing) {
      _closeDialog();
      return true;
    }
    return false;
  }

  /// 启动倒计时
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          _closeDialog();
        }
      });
    });
  }

  /// 关闭对话框
  void _closeDialog() {
    if (_isClosing || !mounted) return;
    
    _isClosing = true;
    _timer?.cancel();
    Navigator.of(context, rootNavigator: true).pop();
  }
  
  /// 简化的缩放计算
  double _calculateScale(Size screenSize) {
    final scale = screenSize.width / _RemoteHelpConfig.baseScreenWidth;
    return scale.clamp(_RemoteHelpConfig.minScale, _RemoteHelpConfig.maxScale);
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final scale = _calculateScale(screenSize);
    final s = S.current;

    return WillPopScope(
      onWillPop: () async {
        if (!_isClosing) {
          _closeDialog();
        }
        return false;
      },
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: () {
            if (!_isClosing) {
              _closeDialog();
            }
          },
          child: Container(
            color: const Color(0xDD000000),
            width: screenSize.width,
            height: screenSize.height,
            child: Stack(
              children: [
                // 主内容区域
                Positioned.fill(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: _RemoteHelpConfig.topPadding * scale),
                        // 遥控器和指引
                        SizedBox(
                          width: screenSize.width,
                          height: _RemoteHelpConfig.remoteHeight * scale,
                          child: _buildRemoteControl(context, scale),
                        ),
                        SizedBox(height: _RemoteHelpConfig.bottomPadding * scale),
                      ],
                    ),
                  ),
                ),
                // 底部倒计时提示
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _RemoteHelpConfig.bottomTextPadding * scale,
                  child: Center(
                    child: Text(
                      "${s.remotehelpclose} ($_countdown)",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: _RemoteHelpConfig.countdownFontSize * scale,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 构建遥控器控件
  Widget _buildRemoteControl(BuildContext context, double scale) {
    final s = S.current;
    final labelTexts = {
      'remotehelpup': s.remotehelpup,
      'remotehelpleft': s.remotehelpleft,
      'remotehelpdown': s.remotehelpdown,
      'remotehelpok': s.remotehelpok,
      'remotehelpright': s.remotehelpright,
      'remotehelpback': s.remotehelpback,
    };

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 遥控器主体
        SizedBox(
          width: _RemoteHelpConfig.remoteWidth * scale,
          height: _RemoteHelpConfig.remoteHeight * scale,
          child: CustomPaint(
            painter: RemoteControlPainter(),
          ),
        ),
        // 按键指引
        ..._buttonGuides.map((guide) => 
          ButtonGuideWidget(
            guide: guide,
            scale: scale,
            labelText: labelTexts[guide.labelKey] ?? '',
          ),
        ),
      ],
    );
  }
}

/// 按键指引数据模型
class ButtonGuide {
  final String labelKey;
  final ButtonPosition buttonPosition;
  final bool isLeftSide;

  const ButtonGuide({
    required this.labelKey,
    required this.buttonPosition,
    required this.isLeftSide,
  });
}

/// 按键位置枚举
enum ButtonPosition {
  up, down, left, right, center, back
}

/// 按键指引组件
class ButtonGuideWidget extends StatelessWidget {
  final ButtonGuide guide;
  final double scale;
  final String labelText;

  const ButtonGuideWidget({
    Key? key,
    required this.guide,
    required this.scale,
    required this.labelText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final positions = _calculatePositions(guide.buttonPosition, scale);
    
    return Stack(
      children: [
        // 连接线
        Positioned(
          left: positions['lineLeft']!,
          top: positions['lineTop']!,
          child: Container(
            width: positions['lineWidth']!,
            height: 3 * scale,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.8),
                  Colors.white.withOpacity(0),
                ],
                begin: guide.isLeftSide ? Alignment.centerRight : Alignment.centerLeft,
                end: guide.isLeftSide ? Alignment.centerLeft : Alignment.centerRight,
              ),
            ),
          ),
        ),
        // 圆点
        Positioned(
          left: positions['dotLeft']!,
          top: positions['dotTop']!,
          child: Container(
            width: 8 * scale,
            height: 8 * scale,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
          ),
        ),
        // 标签
        Positioned(
          left: positions['labelLeft']!,
          top: positions['labelTop']!,
          child: Text(
            labelText,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: _RemoteHelpConfig.labelFontSize * scale,
            ),
            textAlign: guide.isLeftSide ? TextAlign.left : TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// 根据按键位置计算各元素的位置
  Map<String, double> _calculatePositions(ButtonPosition position, double scale) {
    final screenWidth = WidgetsBinding.instance.window.physicalSize.width / 
                       WidgetsBinding.instance.window.devicePixelRatio;
    final centerX = screenWidth / 2;
    
    // 基础位置配置（相对于屏幕中心）
    final Map<ButtonPosition, Map<String, double>> basePositions = {
      ButtonPosition.up: {
        'lineOffset': -270, 'lineTop': 90, 'lineWidth': 250,
        'dotOffset': -275, 'dotTop': 88,
        'labelOffset': -750, 'labelTop': 65,
      },
      ButtonPosition.left: {
        'lineOffset': -270, 'lineTop': 190, 'lineWidth': 150,
        'dotOffset': -275, 'dotTop': 188,
        'labelOffset': -765, 'labelTop': 165,
      },
      ButtonPosition.down: {
        'lineOffset': -270, 'lineTop': 310, 'lineWidth': 245,
        'dotOffset': -275, 'dotTop': 308,
        'labelOffset': -750, 'labelTop': 285,
      },
      ButtonPosition.center: {
        'lineOffset': 50, 'lineTop': 150, 'lineWidth': 235,
        'dotOffset': 282, 'dotTop': 148,
        'labelOffset': 285, 'labelTop': 95,
      },
      ButtonPosition.right: {
        'lineOffset': 110, 'lineTop': 215, 'lineWidth': 180,
        'dotOffset': 282, 'dotTop': 213,
        'labelOffset': 285, 'labelTop': 195,
      },
      ButtonPosition.back: {
        'lineOffset': 110, 'lineTop': 378, 'lineWidth': 175,
        'dotOffset': 282, 'dotTop': 375,
        'labelOffset': 285, 'labelTop': 355,
      },
    };

    final pos = basePositions[position]!;
    
    return {
      'lineLeft': centerX + pos['lineOffset']! * scale,
      'lineTop': pos['lineTop']! * scale,
      'lineWidth': pos['lineWidth']! * scale,
      'dotLeft': centerX + pos['dotOffset']! * scale,
      'dotTop': pos['dotTop']! * scale,
      'labelLeft': centerX + pos['labelOffset']! * scale,
      'labelTop': pos['labelTop']! * scale,
    };
  }
}

/// 简化的遥控器绘制类
class RemoteControlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    
    // 基础画笔设置
    final strokeWidth = width * 0.01;
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    
    final fillPaint = Paint()
      ..style = PaintingStyle.fill;

    // 背景渐变
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF444444).withOpacity(0.6),
          Color(0xFF444444).withOpacity(0.3),
          Color(0xFF444444).withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    // 绘制遥控器主体
    final remotePath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06)
      ..lineTo(width * 0.95, height)
      ..lineTo(width * 0.05, height)
      ..close();

    canvas.drawPath(remotePath, backgroundPaint);

    // 绘制顶部边框
    final topBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06);

    canvas.drawPath(topBorderPath, borderPaint);

    // 绘制侧边框
    canvas.drawLine(
      Offset(width * 0.05, height * 0.06),
      Offset(width * 0.05, height),
      borderPaint,
    );
    canvas.drawLine(
      Offset(width * 0.95, height * 0.06),
      Offset(width * 0.95, height),
      borderPaint,
    );

    // 绘制圆形控制区域
    final circleCenter = Offset(width * 0.5, height * 0.33);
    final circleRadius = width * 0.35;

    fillPaint.color = const Color(0xFF444444).withOpacity(0.6);
    canvas.drawCircle(circleCenter, circleRadius, fillPaint);
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);

    // 绘制方向箭头
    _drawArrows(canvas, circleCenter, width);

    // 绘制中心OK按钮
    final centerRadius = width * 0.15;
    fillPaint.color = const Color(0xFF333333).withOpacity(0.9);
    canvas.drawCircle(circleCenter, centerRadius, fillPaint);
    canvas.drawCircle(circleCenter, centerRadius, borderPaint);

    // 绘制OK文本
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'OK',
        style: TextStyle(
          color: Colors.white,
          fontSize: width * _RemoteHelpConfig.okButtonFontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      circleCenter.translate(-textPainter.width / 2, -textPainter.height / 2),
    );

    // 绘制返回按钮
    _drawBackButton(canvas, Offset(width * 0.75, height * 0.65), width);
  }

  /// 绘制方向箭头
  void _drawArrows(Canvas canvas, Offset center, double width) {
    final arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    
    final arrowSize = width * 0.18;
    final distance = width * 0.25;
    
    // 上下左右四个箭头
    final arrows = [
      {'offset': Offset(0, -distance), 'rotation': 0},
      {'offset': Offset(distance, 0), 'rotation': 90},
      {'offset': Offset(0, distance), 'rotation': 180},
      {'offset': Offset(-distance, 0), 'rotation': 270},
    ];
    
    for (final arrow in arrows) {
      _drawTriangle(
        canvas,
        center + (arrow['offset'] as Offset),
        arrowSize,
        arrowSize * 0.5,
        (arrow['rotation'] as num).toDouble(),
        arrowPaint,
      );
    }
  }

  /// 绘制三角形
  void _drawTriangle(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    double rotation,
    Paint paint,
  ) {
    final path = Path()
      ..moveTo(0, -height / 2)
      ..lineTo(width / 2, height / 2)
      ..lineTo(-width / 2, height / 2)
      ..close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 3.14159 / 180);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  /// 绘制返回按钮
  void _drawBackButton(Canvas canvas, Offset center, double width) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.01;

    final radius = width * 0.08;
    canvas.drawCircle(center, radius, paint);

    // 绘制返回箭头
    paint.strokeWidth = width * 0.02;
    final arrowPath = Path()
      ..moveTo(-radius * 0.5, 0)
      ..lineTo(0, -radius * 0.5)
      ..moveTo(-radius * 0.5, 0)
      ..lineTo(0, radius * 0.5);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(45 * 3.14159 / 180);
    canvas.drawPath(arrowPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(RemoteControlPainter oldDelegate) => false;
}
