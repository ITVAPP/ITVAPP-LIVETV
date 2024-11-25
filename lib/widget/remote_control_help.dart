import 'package:flutter/material.dart';

class RemoteControlHelp {
  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return const RemoteControlHelpDialog();
      },
    );
  }
}

class RemoteControlHelpDialog extends StatelessWidget {
  const RemoteControlHelpDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 120),
                      Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Remote Control SVG
                          Transform.translate(
                            offset: const Offset(0, 0),
                            child: CustomPaint(
                              size: const Size(400, 600),
                              painter: RemoteControlPainter(),
                            ),
                          ),
                          
                          // Left Connection Lines
                          _buildConnectionLine(left: -270, top: 90, width: 250),
                          _buildConnectionLine(left: -270, top: 190, width: 150),
                          _buildConnectionLine(left: -270, top: 310, width: 245),
                          
                          // Right Connection Lines
                          _buildConnectionLine(left: 170, top: 150, width: 225),
                          _buildConnectionLine(left: 110, top: 215, width: 180),
                          _buildConnectionLine(left: 110, top: 378, width: 175),
                          
                          // Left Dots
                          _buildDot(left: -275, top: 88),
                          _buildDot(left: -275, top: 188),
                          _buildDot(left: -275, top: 308),
                          
                          // Right Dots
                          _buildDot(left: 282, top: 148),
                          _buildDot(left: 282, top: 213),
                          _buildDot(left: 282, top: 375),
                          
                          // Left Labels
                          _buildLabel(
                            left: -695,
                            top: 65,
                            text: "「点击上键」打开 线路切换菜单",
                            alignment: Alignment.centerRight,
                          ),
                          _buildLabel(
                            left: -695,
                            top: 165,
                            text: "「点击左键」添加/取消 频道收藏",
                            alignment: Alignment.centerRight,
                          ),
                          _buildLabel(
                            left: -695,
                            top: 288,
                            text: "「点击下键」打开 应用设置界面",
                            alignment: Alignment.centerRight,
                          ),
                          
                          // Right Labels
                          _buildLabel(
                            left: 285,
                            top: 95,
                            text: "「点击确认键」确认选择操作\n显示时间/暂停/播放",
                            alignment: Alignment.centerLeft,
                          ),
                          _buildLabel(
                            left: 285,
                            top: 195,
                            text: "「点击右键」打开 频道选择抽屉",
                            alignment: Alignment.centerLeft,
                          ),
                          _buildLabel(
                            left: 285,
                            top: 355,
                            text: "「点击返回键」退出/取消操作",
                            alignment: Alignment.centerLeft,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom Hint Text
              Positioned(
                left: 0,
                right: 0,
                bottom: 50,
                child: Center(
                  child: Text(
                    "点击任意按键关闭使用帮助 (18)",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionLine({
    required double left,
    required double top,
    required double width,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: width,
        height: 3,
        color: Colors.white.withOpacity(0.8),
      ),
    );
  }

  Widget _buildDot({
    required double left,
    required double top,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: 45 * 3.14159 / 180,
        child: Container(
          width: 8,
          height: 8,
          color: Colors.white.withOpacity(0.8),
        ),
      ),
    );
  }

  Widget _buildLabel({
    required double left,
    required double top,
    required String text,
    required Alignment alignment,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(
          text,
          textAlign: alignment == Alignment.centerRight ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.6,
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
          ),
        ),
      ),
    );
  }
}

class RemoteControlPainter extends CustomPainter {
  const RemoteControlPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF444444).withOpacity(0.5),
          Color(0xFF444444).withOpacity(0.3),
          Color(0xFF444444).withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final Paint borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final Paint whitePaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    // Draw remote body
    final Path remotePath = Path()
      ..moveTo(10, 30)
      ..quadraticBezierTo(10, 0, 40, 0)
      ..lineTo(360, 0)
      ..quadraticBezierTo(390, 0, 390, 30)
      ..lineTo(390, 520)
      ..lineTo(10, 520)
      ..close();

    canvas.drawPath(remotePath, backgroundPaint);
    canvas.drawPath(remotePath, borderPaint);

    // Draw circular pad
    final circleCenter = Offset(190, 200);
    canvas.drawCircle(
      circleCenter,
      140,
      Paint()
        ..color = Color(0xFF444444).withOpacity(0.5)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, 140, borderPaint);

    // Draw directional arrows
    _drawDirectionalArrows(canvas, circleCenter);

    // Draw center circle and OK text
    canvas.drawCircle(
      circleCenter,
      60,
      Paint()
        ..color = Color(0xFF333333).withOpacity(0.7)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, 60, borderPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'OK',
        style: TextStyle(
          color: Colors.white,
          fontSize: 46,
          fontWeight: FontWeight.bold,
          fontFamily: 'Arial, sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      circleCenter.translate(-textPainter.width / 2, -textPainter.height / 2),
    );

    // Draw back button
    _drawBackButton(canvas, Offset(306, 380));
  }

  void _drawDirectionalArrows(Canvas canvas, Offset center) {
    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    // Up arrow
    _drawTriangle(
      canvas,
      center.translate(0, -125),
      28,
      56,
      0,
      arrowPaint,
    );

    // Right arrow
    _drawTriangle(
      canvas,
      center.translate(125, 0),
      56,
      28,
      90,
      arrowPaint,
    );

    // Down arrow
    _drawTriangle(
      canvas,
      center.translate(0, 125),
      28,
      56,
      180,
      arrowPaint,
    );

    // Left arrow
    _drawTriangle(
      canvas,
      center.translate(-125, 0),
      56,
      28,
      270,
      arrowPaint,
    );
  }

  void _drawTriangle(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    double rotation,
    Paint paint,
  ) {
    final path = Path();
    path.moveTo(0, -height / 2);
    path.lineTo(width / 2, height / 2);
    path.lineTo(-width / 2, height / 2);
    path.close();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 3.14159 / 180);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawBackButton(Canvas canvas, Offset center) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, 30, paint);

    paint.strokeWidth = 8;
    final path = Path()
      ..moveTo(center.dx - 12, center.dy - 12)
      ..lineTo(center.dx - 12, center.dy + 12)
      ..lineTo(center.dx + 12, center.dy + 12);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(45 * 3.14159 / 180);
    canvas.translate(-center.dx, -center.dy);
    canvas.translate(5, -5);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
