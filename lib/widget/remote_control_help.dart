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
      builder: (BuildContext context) {
        return const RemoteControlHelpDialog();
      },
    );
  }
}

class RemoteControlHelpDialog extends StatefulWidget {
  const RemoteControlHelpDialog({Key? key}) : super(key: key);

  @override
  State<RemoteControlHelpDialog> createState() => _RemoteControlHelpDialogState();
}

class _RemoteControlHelpDialogState extends State<RemoteControlHelpDialog> {
  Timer? _timer; // 倒计时定时器
  int _countdown = 28; // 倒计时初始值（秒）
  final FocusNode _focusNode = FocusNode(); // 用于键盘焦点管理

  // 定义基线宽度常量，用于动态缩放计算
  static const double _baseScreenWidth = 1920;

  @override
  void initState() {
    super.initState();
    _startTimer(); // 初始化时启动倒计时
    _focusNode.requestFocus(); // 获取焦点以监听键盘事件
  }

  @override
  void dispose() {
    _timer?.cancel(); // 清理定时器
    _focusNode.dispose(); // 释放焦点资源
    super.dispose();
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
    _timer?.cancel(); // 停止定时器
    Navigator.of(context).pop(); // 关闭对话框
  }

  /// 根据平台选择合适的字体族
  String _getFontFamily(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS 
      ? '.SF UI Display' // iOS 平台字体
      : 'Roboto'; // 默认 Android 字体
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size; // 获取屏幕尺寸
    final scale = (screenSize.width / _baseScreenWidth).clamp(0.5, 2.0); // 计算缩放比例
    final screenCenter = screenSize.width / 2; // 计算屏幕水平中心点

    // 配置遥控器帮助界面的连线、圆点和标签数据
    final List<Map<String, dynamic>> connectionData = [
      // 左侧“上”键指引
      {
        'left': screenCenter - 270 * scale,
        'top': 90 * scale,
        'width': 250 * scale,
        'height': 3 * scale,
        'isLeftSide': false,
        'dotLeft': screenCenter - 275 * scale,
        'dotTop': 88 * scale,
        'dotSize': 8 * scale,
        'labelLeft': screenCenter - 690 * scale,
        'labelTop': 75 * scale,
        'labelText': S.current.remotehelpup, // “上”键标签
        'labelAlignment': Alignment.centerRight,
      },
      // 左侧“左”键指引
      {
        'left': screenCenter - 270 * scale,
        'top': 190 * scale,
        'width': 150 * scale,
        'height': 3 * scale,
        'isLeftSide': false,
        'dotLeft': screenCenter - 275 * scale,
        'dotTop': 188 * scale,
        'dotSize': 8 * scale,
        'labelLeft': screenCenter - 700 * scale,
        'labelTop': 170 * scale,
        'labelText': S.current.remotehelpleft, // “左”键标签
        'labelAlignment': Alignment.centerRight,
      },
      // 左侧“下”键指引
      {
        'left': screenCenter - 270 * scale,
        'top': 310 * scale,
        'width': 245 * scale,
        'height': 3 * scale,
        'isLeftSide': false,
        'dotLeft': screenCenter - 275 * scale,
        'dotTop': 308 * scale,
        'dotSize': 8 * scale,
        'labelLeft': screenCenter - 690 * scale,
        'labelTop': 292 * scale,
        'labelText': S.current.remotehelpdown, // “下”键标签
        'labelAlignment': Alignment.centerRight,
      },
      // 右侧“确定”键指引
      {
        'left': screenCenter + 50 * scale,
        'top': 150 * scale,
        'width': 235 * scale,
        'height': 3 * scale,
        'isLeftSide': true,
        'dotLeft': screenCenter + 282 * scale,
        'dotTop': 148 * scale,
        'dotSize': 8 * scale,
        'labelLeft': screenCenter + 285 * scale,
        'labelTop': 95 * scale,
        'labelText': S.current.remotehelpok, // “确定”键标签
        'labelAlignment': Alignment.centerRight,
      },
      // 右侧“右”键指引
      {
        'left': screenCenter + 110 * scale,
        'top': 215 * scale,
        'width': 180 * scale,
        'height': 3 * scale,
        'isLeftSide': true,
        'dotLeft': screenCenter + 282 * scale,
        'dotTop': 213 * scale,
        'dotSize': 8 * scale,
        'labelLeft': screenCenter + 285 * scale,
        'labelTop': 195 * scale,
        'labelText': S.current.remotehelpright, // “右”键标签
        'labelAlignment': Alignment.centerLeft,
      },
      // 右侧“返回”键指引
      {
        'left': screenCenter + 110 * scale,
        'top': 378 * scale,
        'width': 175 * scale,
        'height': 3 * scale,
        'isLeftSide': true,
        'dotLeft': screenCenter + 282 * scale,
        'dotTop': 375 * scale,
        'dotSize': 8 * scale,
        'labelLeft': screenCenter + 285 * scale,
        'labelTop': 355 * scale,
        'labelText': S.current.remotehelpback, // “返回”键标签
        'labelAlignment': Alignment.centerLeft,
      },
    ];

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          _closeDialog(); // 按键时关闭对话框
        }
        KeyEventResult.handled;
      },
      child: Material(
        type: MaterialType.transparency, // 设置透明背景
        child: GestureDetector(
          onTap: _closeDialog, // 点击关闭对话框
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
                            // 动态生成连线、圆点和标签
                            ...connectionData.map((data) => [
                              _buildConnectionLine(
                                left: data['left'],
                                top: data['top'],
                                width: data['width'],
                                height: data['height'],
                                isLeftSide: data['isLeftSide'],
                              ),
                              _buildDot(
                                left: data['dotLeft'],
                                top: data['dotTop'],
                                size: data['dotSize'],
                              ),
                              _buildLabel(
                                context: context,
                                left: data['labelLeft'],
                                top: data['labelTop'],
                                text: data['labelText'],
                                alignment: data['labelAlignment'],
                                scale: scale,
                              ),
                            ]).expand((element) => element),
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
                        fontSize: 25 * scale,
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
            fontSize: 28 * scale,
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
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

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

    // 配置顶部边框画笔
    final Paint topBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 绘制顶部边框路径
    final Path topBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06);

    canvas.drawPath(topBorderPath, topBorderPaint);

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

    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = Color(0xFF444444).withOpacity(0.6) // 填充颜色
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, circleRadius, topBorderPaint); // 圆形边框

    // 绘制方向箭头
    _drawDirectionalArrows(canvas, circleCenter, width);

    // 绘制中心“OK”按钮
    final centerRadius = width * 0.15;
    canvas.drawCircle(
      circleCenter,
      centerRadius,
      Paint()
        ..color = Color(0xFF333333).withOpacity(0.9) // 填充颜色
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, centerRadius, topBorderPaint); // 边框

    // 绘制“OK”文本
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'OK',
        style: TextStyle(
          color: Colors.white,
          fontSize: width * 0.12,
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto',
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
    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final arrowSize = width * 0.18; // 箭头尺寸
    final arrowDistance = width * 0.25; // 箭头与中心距离

    _drawTriangle(canvas, center.translate(0, -arrowDistance), arrowSize, arrowSize * 0.5, 0, arrowPaint); // 上箭头
    _drawTriangle(canvas, center.translate(arrowDistance, 0), arrowSize, arrowSize * 0.5, 90, arrowPaint); // 右箭头
    _drawTriangle(canvas, center.translate(0, arrowDistance), arrowSize, arrowSize * 0.5, 180, arrowPaint); // 下箭头
    _drawTriangle(canvas, center.translate(-arrowDistance, 0), arrowSize, arrowSize * 0.5, 270, arrowPaint); // 左箭头
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
