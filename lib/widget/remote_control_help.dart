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

  String _getFontFamily(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS 
      ? '.SF UI Display' 
      : 'Roboto';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = MediaQuery.of(context).size;
          final baseWidth = 400.0;
          final minScale = 0.5;
          final maxScale = 1.5;
          final scale = (constraints.maxWidth / baseWidth).clamp(minScale, maxScale);
          
          final contentWidth = screenSize.width;
          final horizontalPadding = (contentWidth - (baseWidth * scale)) / 2;

          return GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.black,
              width: contentWidth,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: Column(
                          children: [
                            SizedBox(height: 120 * scale),
                            Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                Transform.scale(
                                  scale: scale,
                                  child: CustomPaint(
                                    size: const Size(400, 600),
                                    painter: RemoteControlPainter(),
                                  ),
                                ),
                                
                                // Left Connection Lines
                                _buildConnectionLine(left: -270 * scale, top: 90 * scale, width: 250 * scale),
                                _buildConnectionLine(left: -270 * scale, top: 190 * scale, width: 150 * scale),
                                _buildConnectionLine(left: -270 * scale, top: 310 * scale, width: 245 * scale),
                                
                                // Right Connection Lines
                                _buildConnectionLine(left: 170 * scale, top: 150 * scale, width: 225 * scale),
                                _buildConnectionLine(left: 110 * scale, top: 215 * scale, width: 180 * scale),
                                _buildConnectionLine(left: 110 * scale, top: 378 * scale, width: 175 * scale),
                                
                                // Left Dots
                                _buildDot(left: -275 * scale, top: 88 * scale),
                                _buildDot(left: -275 * scale, top: 188 * scale),
                                _buildDot(left: -275 * scale, top: 308 * scale),
                                
                                // Right Dots
                                _buildDot(left: 282 * scale, top: 148 * scale),
                                _buildDot(left: 282 * scale, top: 213 * scale),
                                _buildDot(left: 282 * scale, top: 375 * scale),
                                
                                // Left Labels
                                _buildLabel(
                                  context: context,
                                  scale: scale,
                                  left: -695 * scale,
                                  top: 65 * scale,
                                  text: "「点击上键」打开 线路切换菜单",
                                  alignment: Alignment.centerRight,
                                ),
                                _buildLabel(
                                  context: context,
                                  scale: scale,
                                  left: -695 * scale,
                                  top: 165 * scale,
                                  text: "「点击左键」添加/取消 频道收藏",
                                  alignment: Alignment.centerRight,
                                ),
                                _buildLabel(
                                  context: context,
                                  scale: scale,
                                  left: -695 * scale,
                                  top: 288 * scale,
                                  text: "「点击下键」打开 应用设置界面",
                                  alignment: Alignment.centerRight,
                                ),
                                
                                // Right Labels
                                _buildLabel(
                                  context: context,
                                  scale: scale,
                                  left: 285 * scale,
                                  top: 95 * scale,
                                  text: "「点击确认键」确认选择操作\n显示时间/暂停/播放",
                                  alignment: Alignment.centerLeft,
                                ),
                                _buildLabel(
                                  context: context,
                                  scale: scale,
                                  left: 285 * scale,
                                  top: 195 * scale,
                                  text: "「点击右键」打开 频道选择抽屉",
                                  alignment: Alignment.centerLeft,
                                ),
                                _buildLabel(
                                  context: context,
                                  scale: scale,
                                  left: 285 * scale,
                                  top: 355 * scale,
                                  text: "「点击返回键」退出/取消操作",
                                  alignment: Alignment.centerLeft,
                                ),
                              ],
                            ),
                            SizedBox(height: 100 * scale),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Bottom Hint Text
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 50 * scale,
                    child: Center(
                      child: Text(
                        "点击任意按键关闭使用帮助 (18)",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 16 * scale,
                          fontFamily: _getFontFamily(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    required BuildContext context,
    required double scale,
    required double left,
    required double top,
    required String text,
    required Alignment alignment,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        constraints: BoxConstraints(maxWidth: 400 * scale),
        child: Text(
          text,
          textAlign: alignment == Alignment.centerRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: Colors.white,
            fontSize: 28 * scale,
            height: 1.6,
            fontFamily: _getFontFamily(context),
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

    // Draw remote body background
    final Path remotePath = Path()
      ..moveTo(10, 30)
      ..quadraticBezierTo(10, 0, 40, 0)
      ..lineTo(360, 0)
      ..quadraticBezierTo(390, 0, 390, 30)
      ..lineTo(390, 520)
      ..lineTo(10, 520)
      ..close();

    canvas.drawPath(remotePath, backgroundPaint);

    // Draw three border lines separately
    final Path topBorder = Path()
      ..moveTo(10, 30)
      ..quadraticBezierTo(10, 0, 40, 0)
      ..lineTo(360, 0)
      ..quadraticBezierTo(390, 0, 390, 30);

    final Path leftBorder = Path()
      ..moveTo(10, 30)
      ..lineTo(10, 520);

    final Path rightBorder = Path()
      ..moveTo(390, 30)
      ..lineTo(390, 520);

    canvas.drawPath(topBorder, borderPaint);
    canvas.drawPath(leftBorder, borderPaint);
    canvas.drawPath(rightBorder, borderPaint);

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
          fontFamily: 'Roboto',
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
      center.translate(0, -85),
      61.6,
      30.8,
      0,
      arrowPaint,
    );

    // Right arrow
    _drawTriangle(
      canvas,
      center.translate(85, 0),
      61.6,
      30.8,
      90,
      arrowPaint,
    );

    // Down arrow
    _drawTriangle(
      canvas,
      center.translate(0, 85),
      61.6,
      30.8,
      180,
      arrowPaint,
    );

    // Left arrow
    _drawTriangle(
      canvas,
      center.translate(-85, 0),
      61.6,
      30.8,
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
