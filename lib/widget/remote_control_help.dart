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
    final screenSize = MediaQuery.of(context).size;
    final remoteHeight = screenSize.height * 0.7; // 遥控器高度为屏幕高度的70%
    final remoteWidth = remoteHeight * 0.6; // 保持宽高比
    final scale = remoteHeight / 600; // 600是原始SVG高度

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black,
          width: screenSize.width,
          height: screenSize.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: screenSize.height * 0.05),
                      Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Remote Control
                          SizedBox(
                            width: remoteWidth,
                            height: remoteHeight,
                            child: CustomPaint(
                              painter: RemoteControlPainter(),
                            ),
                          ),
                          
                          // Left Connection Lines
                          _buildConnectionLine(
                            left: -remoteWidth * 0.5,
                            top: remoteHeight * 0.15,
                            width: remoteWidth * 0.4,
                          ),
                          _buildConnectionLine(
                            left: -remoteWidth * 0.5,
                            top: remoteHeight * 0.32,
                            width: remoteWidth * 0.3,
                          ),
                          _buildConnectionLine(
                            left: -remoteWidth * 0.5,
                            top: remoteHeight * 0.52,
                            width: remoteWidth * 0.4,
                          ),
                          
                          // Right Connection Lines
                          _buildConnectionLine(
                            left: remoteWidth * 0.3,
                            top: remoteHeight * 0.25,
                            width: remoteWidth * 0.4,
                          ),
                          _buildConnectionLine(
                            left: remoteWidth * 0.2,
                            top: remoteHeight * 0.36,
                            width: remoteWidth * 0.3,
                          ),
                          _buildConnectionLine(
                            left: remoteWidth * 0.2,
                            top: remoteHeight * 0.63,
                            width: remoteWidth * 0.3,
                          ),
                          
                          // Left Dots
                          _buildDot(
                            left: -remoteWidth * 0.5,
                            top: remoteHeight * 0.15,
                          ),
                          _buildDot(
                            left: -remoteWidth * 0.5,
                            top: remoteHeight * 0.32,
                          ),
                          _buildDot(
                            left: -remoteWidth * 0.5,
                            top: remoteHeight * 0.52,
                          ),
                          
                          // Right Dots
                          _buildDot(
                            left: remoteWidth * 0.7,
                            top: remoteHeight * 0.25,
                          ),
                          _buildDot(
                            left: remoteWidth * 0.7,
                            top: remoteHeight * 0.36,
                          ),
                          _buildDot(
                            left: remoteWidth * 0.7,
                            top: remoteHeight * 0.63,
                          ),
                          
                          // Left Labels
                          _buildLabel(
                            context: context,
                            scale: scale,
                            left: -remoteWidth * 1.2,
                            top: remoteHeight * 0.11,
                            text: "「点击上键」打开 线路切换菜单",
                            alignment: Alignment.centerRight,
                          ),
                          _buildLabel(
                            context: context,
                            scale: scale,
                            left: -remoteWidth * 1.2,
                            top: remoteHeight * 0.28,
                            text: "「点击左键」添加/取消 频道收藏",
                            alignment: Alignment.centerRight,
                          ),
                          _buildLabel(
                            context: context,
                            scale: scale,
                            left: -remoteWidth * 1.2,
                            top: remoteHeight * 0.48,
                            text: "「点击下键」打开 应用设置界面",
                            alignment: Alignment.centerRight,
                          ),
                          
                          // Right Labels
                          _buildLabel(
                            context: context,
                            scale: scale,
                            left: remoteWidth * 0.7,
                            top: remoteHeight * 0.16,
                            text: "「点击确认键」确认选择操作\n显示时间/暂停/播放",
                            alignment: Alignment.centerLeft,
                          ),
                          _buildLabel(
                            context: context,
                            scale: scale,
                            left: remoteWidth * 0.7,
                            top: remoteHeight * 0.33,
                            text: "「点击右键」打开 频道选择抽屉",
                            alignment: Alignment.centerLeft,
                          ),
                          _buildLabel(
                            context: context,
                            scale: scale,
                            left: remoteWidth * 0.7,
                            top: remoteHeight * 0.59,
                            text: "「点击返回键」退出/取消操作",
                            alignment: Alignment.centerLeft,
                          ),
                        ],
                      ),
                      SizedBox(height: screenSize.height * 0.05),
                    ],
                  ),
                ),
              ),
              
              // Bottom Hint Text
              Positioned(
                left: 0,
                right: 0,
                bottom: screenSize.height * 0.05,
                child: Center(
                  child: Text(
                    "点击任意按键关闭使用帮助",
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
        height: 2,
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
          width: 6,
          height: 6,
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
        constraints: BoxConstraints(maxWidth: 200 * scale),
        child: Text(
          text,
          textAlign: alignment == Alignment.centerRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16 * scale,
            height: 1.6,
            fontFamily: _getFontFamily(context),
          ),
        ),
      ),
    );
  }
}

class RemoteControlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    
    final Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF444444).withOpacity(0.5),
          Color(0xFF444444).withOpacity(0.3),
          Color(0xFF444444).withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    final Paint borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // Draw remote body background
    final Path remotePath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06)
      ..lineTo(width * 0.95, height)
      ..lineTo(width * 0.05, height)
      ..close();

    canvas.drawPath(remotePath, backgroundPaint);
    canvas.drawPath(remotePath, borderPaint);

    // Draw circular pad
    final circleCenter = Offset(width * 0.5, height * 0.33);
    final circleRadius = width * 0.35;
    
    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = Color(0xFF444444).withOpacity(0.5)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);

    // Draw directional arrows
    _drawDirectionalArrows(canvas, circleCenter, width);

    // Draw center circle and OK text
    final centerRadius = width * 0.15;
    canvas.drawCircle(
      circleCenter,
      centerRadius,
      Paint()
        ..color = Color(0xFF333333).withOpacity(0.7)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, centerRadius, borderPaint);

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

    // Draw back button
    _drawBackButton(canvas, Offset(width * 0.75, height * 0.7), width);
  }

  void _drawDirectionalArrows(Canvas canvas, Offset center, double width) {
    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final arrowSize = width * 0.15;
    final arrowDistance = width * 0.22;

    // Up arrow
    _drawTriangle(
      canvas,
      center.translate(0, -arrowDistance),
      arrowSize,
      arrowSize * 0.5,
      0,
      arrowPaint,
    );

    // Right arrow
    _drawTriangle(
      canvas,
      center.translate(arrowDistance, 0),
      arrowSize,
      arrowSize * 0.5,
      90,
      arrowPaint,
    );

    // Down arrow
    _drawTriangle(
      canvas,
      center.translate(0, arrowDistance),
      arrowSize,
      arrowSize * 0.5,
      180,
      arrowPaint,
    );

    // Left arrow
    _drawTriangle(
      canvas,
      center.translate(-arrowDistance, 0),
      arrowSize,
      arrowSize * 0.5,
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

  void _drawBackButton(Canvas canvas, Offset center, double width) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.01;

    final radius = width * 0.08;
    canvas.drawCircle(center, radius, paint);

    paint.strokeWidth = width * 0.02;
    final arrowSize = radius * 0.8;
    final path = Path()
      ..moveTo(center.dx - arrowSize, center.dy - arrowSize)
      ..lineTo(center.dx - arrowSize, center.dy + arrowSize)
      ..lineTo(center.dx + arrowSize, center.dy + arrowSize);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(45 * 3.14159 / 180);
    canvas.translate(-center.dx, -center.dy);
    canvas.translate(width * 0.01, -width * 0.01);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
