import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:itvapp_live_tv/generated/l10n.dart';

class RemoteControlHelp {
  /// 显示遥控器帮助对话框，展示遥控器操作指引
  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: true, // 点击外部可关闭
      useRootNavigator: true,
      builder: (BuildContext context) {
        return const RemoteControlHelpDialog();
      },
    );
  }
}

/// 遥控器帮助界面字体配置
class _RemoteHelpFontConfig {
  // 字体族配置
  static const String iosFontFamily = '.SF UI Display';
  static const String androidFontFamily = 'Roboto';
  
  // 字体大小配置（基础值，实际使用时会乘以缩放比例）
  static const double labelFontSize = 32.0;      // 标签文字大小
  static const double countdownFontSize = 28.0;  // 倒计时文字大小
  static const double okButtonFontSize = 0.12;   // OK按钮文字大小（相对于宽度的比例）
}

class RemoteControlHelpDialog extends StatefulWidget {
  const RemoteControlHelpDialog({Key? key}) : super(key: key);

  @override
  State<RemoteControlHelpDialog> createState() => _RemoteControlHelpDialogState();
}

class _RemoteControlHelpDialogState extends State<RemoteControlHelpDialog> {
  Timer? _timer; // 倒计时定时器
  int _countdown = 28; // 倒计时初始值（秒）
  bool _isClosing = false; // 防止重复关闭的标志

  // 定义基线尺寸常量，用于动态缩放计算
  static const double _baseScreenWidth = 1920;
  static const double _baseScreenHeight = 1080;
  
  // 静态连接数据模板
  static const List<Map<String, dynamic>> _connectionTemplates = [
    // 左侧"上"键指引
    {
      'widthFactor': 250,
      'heightFactor': 3,
      'isLeftSide': false,
      'dotSizeFactor': 8,
      'labelKey': 'remotehelpup',
      'labelAlignment': Alignment.centerRight,
      'offsetFactors': {'left': -270, 'top': 90, 'dotLeft': -275, 'dotTop': 88, 'labelLeft': -750, 'labelTop': 65},
    },
    // 左侧"左"键指引
    {
      'widthFactor': 150,
      'heightFactor': 3,
      'isLeftSide': false,
      'dotSizeFactor': 8,
      'labelKey': 'remotehelpleft',
      'labelAlignment': Alignment.centerRight,
      'offsetFactors': {'left': -270, 'top': 190, 'dotLeft': -275, 'dotTop': 188, 'labelLeft': -765, 'labelTop': 165},
    },
    // 左侧"下"键指引
    {
      'widthFactor': 245,
      'heightFactor': 3,
      'isLeftSide': false,
      'dotSizeFactor': 8,
      'labelKey': 'remotehelpdown',
      'labelAlignment': Alignment.centerRight,
      'offsetFactors': {'left': -270, 'top': 310, 'dotLeft': -275, 'dotTop': 308, 'labelLeft': -750, 'labelTop': 285},
    },
    // 右侧"确定"键指引
    {
      'widthFactor': 235,
      'heightFactor': 3,
      'isLeftSide': true,
      'dotSizeFactor': 8,
      'labelKey': 'remotehelpok',
      'labelAlignment': Alignment.centerRight,
      'offsetFactors': {'left': 50, 'top': 150, 'dotLeft': 282, 'dotTop': 148, 'labelLeft': 285, 'labelTop': 95},
    },
    // 右侧"右"键指引
    {
      'widthFactor': 180,
      'heightFactor': 3,
      'isLeftSide': true,
      'dotSizeFactor': 8,
      'labelKey': 'remotehelpright',
      'labelAlignment': Alignment.centerLeft,
      'offsetFactors': {'left': 110, 'top': 215, 'dotLeft': 282, 'dotTop': 213, 'labelLeft': 285, 'labelTop': 195},
    },
    // 右侧"返回"键指引
    {
      'widthFactor': 175,
      'heightFactor': 3,
      'isLeftSide': true,
      'dotSizeFactor': 8,
      'labelKey': 'remotehelpback',
      'labelAlignment': Alignment.centerLeft,
      'offsetFactors': {'left': 110, 'top': 378, 'dotLeft': 282, 'dotTop': 375, 'labelLeft': 285, 'labelTop': 355},
    },
  ];

  @override
  void initState() {
    super.initState();
    _startTimer(); // 初始化时启动倒计时
    // 使用HardwareKeyboard全局监听，确保能接收到键盘事件
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    _timer?.cancel(); // 清理定时器
    // 移除硬件键盘监听器，防止内存泄漏
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  /// 处理硬件键盘事件
  bool _handleHardwareKey(KeyEvent event) {
    // 只处理按键按下事件，避免重复触发
    if (event is KeyDownEvent) {
      if (!_isClosing) {
        _closeDialog(); // 按任意键关闭对话框
      }
      return true; // 返回true表示事件已处理，阻止事件继续传播
    }
    return false; // 返回false表示事件未处理
  }

  /// 启动倒计时定时器，自动关闭对话框
  void _startTimer() {
    _timer?.cancel(); // 防止重复定时器
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdown > 0) {
          _countdown--; // 每秒减少倒计时
        } else {
          _closeDialog(); // 倒计时结束时关闭对话框
        }
      });
    });
  }

  /// 关闭对话框并清理资源
  void _closeDialog() {
    // 防止重复关闭
    if (_isClosing || !mounted) return;
    
    _isClosing = true; // 设置关闭标志
    _timer?.cancel(); // 停止定时器
    
    // 使用 rootNavigator 并明确传递当前 context，确保只关闭 Dialog
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// 根据平台选择合适的字体族
  String _getFontFamily(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS 
      ? _RemoteHelpFontConfig.iosFontFamily // iOS 平台字体
      : _RemoteHelpFontConfig.androidFontFamily; // 默认 Android 字体
  }
  
  /// 计算综合缩放比例，同时考虑宽度和高度
  double _calculateScale(Size screenSize) {
    // 计算宽度和高度的缩放比例
    final widthScale = screenSize.width / _baseScreenWidth;
    final heightScale = screenSize.height / _baseScreenHeight;
    
    // 使用较小的缩放比例，确保内容不会超出屏幕
    final scale = widthScale < heightScale ? widthScale : heightScale;
    
    // 限制缩放范围，适配更多设备
    return scale.clamp(0.4, 2.5);
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size; // 获取屏幕尺寸
    final scale = _calculateScale(screenSize); // 使用改进的缩放计算
    final screenCenter = screenSize.width / 2; // 计算屏幕水平中心点

    // 根据当前语言获取标签文本
    final s = S.current;
    final labelTexts = [
      s.remotehelpup,
      s.remotehelpleft,
      s.remotehelpdown,
      s.remotehelpok,
      s.remotehelpright,
      s.remotehelpback,
    ];

    // 使用 WillPopScope 来控制返回键行为
    return WillPopScope(
      onWillPop: () async {
        if (!_isClosing) {
          _closeDialog();
        }
        return false; // 防止默认的 pop 行为
      },
      child: Material(
        type: MaterialType.transparency, // 设置透明背景
        child: GestureDetector(
          onTap: () {
            if (!_isClosing) {
              _closeDialog(); // 点击关闭对话框
            }
          },
          child: Container(
            color: const Color(0xDD000000), // 黑色半透明背景
            width: screenSize.width,
            height: screenSize.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 130 * scale), // 顶部预留空间
                        Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // 绘制遥控器主体
                            Center(
                              child: SizedBox(
                                width: 400 * scale, // 遥控器宽度
                                height: 600 * scale, // 遥控器高度
                                child: CustomPaint(
                                  painter: RemoteControlPainter(), // 自定义遥控器绘制
                                ),
                              ),
                            ),
                            // 使用for循环构建连线、圆点和标签，提高性能
                            for (int i = 0; i < _connectionTemplates.length; i++) ...[
                              _buildConnectionLine(
                                left: screenCenter + _connectionTemplates[i]['offsetFactors']['left'] * scale,
                                top: _connectionTemplates[i]['offsetFactors']['top'] * scale,
                                width: _connectionTemplates[i]['widthFactor'] * scale,
                                height: _connectionTemplates[i]['heightFactor'] * scale,
                                isLeftSide: _connectionTemplates[i]['isLeftSide'],
                              ),
                              _buildDot(
                                left: screenCenter + _connectionTemplates[i]['offsetFactors']['dotLeft'] * scale,
                                top: _connectionTemplates[i]['offsetFactors']['dotTop'] * scale,
                                size: _connectionTemplates[i]['dotSizeFactor'] * scale,
                              ),
                              _buildLabel(
                                context: context,
                                left: screenCenter + _connectionTemplates[i]['offsetFactors']['labelLeft'] * scale,
                                top: _connectionTemplates[i]['offsetFactors']['labelTop'] * scale,
                                text: labelTexts[i],
                                alignment: _connectionTemplates[i]['labelAlignment'],
                                scale: scale,
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 100 * scale), // 底部预留空间
                      ],
                    ),
                  ),
                ),
                // 显示底部关闭提示和倒计时
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 50 * scale,
                  child: Center(
                    child: Text(
                      "${S.current.remotehelpclose} ($_countdown)", // 关闭提示及倒计时
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: _RemoteHelpFontConfig.countdownFontSize * scale,
                        fontFamily: _getFontFamily(context),
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
  
  /// 构建连接线，显示遥控器按键指引路径
  Widget _buildConnectionLine({
    required double left,
    required double top,
    required double width,
    required double height,
    bool isLeftSide = true,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.8),
              Colors.white.withOpacity(0),
            ],
            begin: isLeftSide ? Alignment.centerRight : Alignment.centerLeft,
            end: isLeftSide ? Alignment.centerLeft : Alignment.centerRight,
          ),
        ),
      ),
    );
  }

  /// 构建指引圆点，用于连接线端点
  Widget _buildDot({
    required double left,
    required double top,
    required double size,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// 构建标签，显示按键功能说明
  Widget _buildLabel({
    required BuildContext context,
    required double left,
    required double top,
    required String text,
    required Alignment alignment,
    required double scale,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        alignment: alignment,
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: _RemoteHelpFontConfig.labelFontSize * scale,
            fontFamily: _getFontFamily(context),
          ),
          textAlign: alignment == Alignment.centerLeft 
              ? TextAlign.left 
              : TextAlign.right,
        ),
      ),
    );
  }
}

/// 自定义遥控器绘制类，渲染遥控器图形
class RemoteControlPainter extends CustomPainter {
  // 缓存的Paint对象，避免重复创建
  final Paint _topBorderPaint = Paint()
    ..color = Colors.white.withOpacity(0.8)
    ..style = PaintingStyle.stroke;
  
  final Paint _circleFillPaint = Paint()
    ..color = const Color(0xFF444444).withOpacity(0.6)
    ..style = PaintingStyle.fill;
  
  final Paint _centerButtonPaint = Paint()
    ..color = const Color(0xFF333333).withOpacity(0.9)
    ..style = PaintingStyle.fill;
  
  final Paint _arrowPaint = Paint()
    ..color = Colors.white.withOpacity(0.8)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 更新动态属性
    _topBorderPaint.strokeWidth = width * 0.01;

    // 配置遥控器背景渐变画笔
    final Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF444444).withOpacity(0.6),
          Color(0xFF444444).withOpacity(0.3),
          Color(0xFF444444).withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    // 绘制遥控器主体路径
    final Path remotePath = Path()
      ..moveTo(width * 0.05, height * 0.06) // 左上角起点
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0) // 左上圆角
      ..lineTo(width * 0.85, 0) // 顶部直线
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06) // 右上圆角
      ..lineTo(width * 0.95, height) // 右侧直线
      ..lineTo(width * 0.05, height) // 底部直线
      ..close();

    canvas.drawPath(remotePath, backgroundPaint); // 绘制遥控器背景

    // 绘制顶部边框路径
    final Path topBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06);

    canvas.drawPath(topBorderPath, _topBorderPaint);

    // 配置左右渐变边框画笔
    final Paint gradientBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.8),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 绘制左侧边框
    final Path leftBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..lineTo(width * 0.05, height);

    canvas.drawPath(leftBorderPath, gradientBorderPaint);

    // 绘制右侧边框
    final Path rightBorderPath = Path()
      ..moveTo(width * 0.95, height * 0.06)
      ..lineTo(width * 0.95, height);

    canvas.drawPath(rightBorderPath, gradientBorderPaint);

    // 绘制圆形控制区域
    final circleCenter = Offset(width * 0.5, height * 0.33); // 圆心位置
    final circleRadius = width * 0.35; // 圆形半径

    canvas.drawCircle(circleCenter, circleRadius, _circleFillPaint); // 填充
    canvas.drawCircle(circleCenter, circleRadius, _topBorderPaint); // 圆形边框

    // 绘制方向箭头
    _drawDirectionalArrows(canvas, circleCenter, width);

    // 绘制中心"OK"按钮
    final centerRadius = width * 0.15;
    canvas.drawCircle(circleCenter, centerRadius, _centerButtonPaint); // 填充
    canvas.drawCircle(circleCenter, centerRadius, _topBorderPaint); // 边框

    // 绘制"OK"文本
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'OK',
        style: TextStyle(
          color: Colors.white,
          fontSize: width * _RemoteHelpFontConfig.okButtonFontSize,
          fontWeight: FontWeight.bold,
          fontFamily: _RemoteHelpFontConfig.androidFontFamily,
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

  /// 绘制四个方向箭头
  void _drawDirectionalArrows(Canvas canvas, Offset center, double width) {
    final arrowSize = width * 0.18; // 箭头尺寸
    final arrowDistance = width * 0.25; // 箭头与中心距离

    _drawTriangle(canvas, center.translate(0, -arrowDistance), arrowSize, arrowSize * 0.5, 0, _arrowPaint); // 上箭头
    _drawTriangle(canvas, center.translate(arrowDistance, 0), arrowSize, arrowSize * 0.5, 90, _arrowPaint); // 右箭头
    _drawTriangle(canvas, center.translate(0, arrowDistance), arrowSize, arrowSize * 0.5, 180, _arrowPaint); // 下箭头
    _drawTriangle(canvas, center.translate(-arrowDistance, 0), arrowSize, arrowSize * 0.5, 270, _arrowPaint); // 左箭头
  }

  /// 绘制三角形箭头
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

  /// 绘制返回按钮（圆形+箭头）
  void _drawBackButton(Canvas canvas, Offset center, double width) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.01;

    final radius = width * 0.08;
    canvas.drawCircle(center, radius, paint);

    paint.strokeWidth = width * 0.02;
    final arrowSize = radius * 0.5;
    final path = Path()
      ..moveTo(center.dx - arrowSize, center.dy - arrowSize)
      ..lineTo(center.dx - arrowSize, center.dy + arrowSize)
      ..lineTo(center.dx + arrowSize, center.dy + arrowSize);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(45 * 3.14159 / 180);
    canvas.translate(-center.dx, -center.dy);
    canvas.translate(width * 0.02, -width * 0.02);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false; // 静态图形，无需重绘
}
