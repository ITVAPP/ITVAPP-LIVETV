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
    final scale = (screenSize.width / 1920).clamp(0.5, 2.0);
    final screenCenter = screenSize.width / 2;  // 添加屏幕中心点计算

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black,
          width: screenSize.width,
          height: screenSize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: 120 * scale),
                      Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // 遥控器SVG - 使用Center确保居中
                          Center(
                            child: SizedBox(
                              width: 400 * scale,
                              height: 600 * scale,
                              child: CustomPaint(
                                painter: RemoteControlPainter(),
                              ),
                            ),
                          ),
                                                    // Left Connection Lines - 使用屏幕中心点定位
                          _buildConnectionLine(
                            left: screenCenter - 270 * scale, 
                            top: 90 * scale, 
                            width: 250 * scale,
                            height: 3 * scale,
                          ),
                          _buildConnectionLine(
                            left: screenCenter - 270 * scale, 
                            top: 190 * scale, 
                            width: 150 * scale,
                            height: 3 * scale,
                          ),
                          _buildConnectionLine(
                            left: screenCenter - 270 * scale, 
                            top: 310 * scale, 
                            width: 245 * scale,
                            height: 3 * scale,
                          ),
                          
                          // Right Connection Lines - 使用屏幕中心点定位
                          _buildConnectionLine(
                            left: screenCenter + 170 * scale, 
                            top: 150 * scale, 
                            width: 225 * scale,
                            height: 3 * scale,
                          ),
                          _buildConnectionLine(
                            left: screenCenter + 110 * scale, 
                            top: 215 * scale, 
                            width: 180 * scale,
                            height: 3 * scale,
                          ),
                          _buildConnectionLine(
                            left: screenCenter + 110 * scale, 
                            top: 378 * scale, 
                            width: 175 * scale,
                            height: 3 * scale,
                          ),
                          
                          // Left Dots - 使用屏幕中心点定位
                          _buildDot(
                            left: screenCenter - 275 * scale, 
                            top: 88 * scale,
                            size: 8 * scale,
                          ),
                          _buildDot(
                            left: screenCenter - 275 * scale, 
                            top: 188 * scale,
                            size: 8 * scale,
                          ),
                          _buildDot(
                            left: screenCenter - 275 * scale, 
                            top: 308 * scale,
                            size: 8 * scale,
                          ),
                          
                          // Right Dots - 使用屏幕中心点定位
                          _buildDot(
                            left: screenCenter + 282 * scale, 
                            top: 148 * scale,
                            size: 8 * scale,
                          ),
                          _buildDot(
                            left: screenCenter + 282 * scale, 
                            top: 213 * scale,
                            size: 8 * scale,
                          ),
                          _buildDot(
                            left: screenCenter + 282 * scale, 
                            top: 375 * scale,
                            size: 8 * scale,
                          ),
                                                    // Left Labels - 使用屏幕中心点定位
                          _buildLabel(
                            context: context,
                            left: screenCenter - 695 * scale,
                            top: 65 * scale,
                            text: "「点击上键」打开 线路切换菜单",
                            alignment: Alignment.centerRight,
                            scale: scale,
                          ),
                          _buildLabel(
                            context: context,
                            left: screenCenter - 695 * scale,
                            top: 165 * scale,
                            text: "「点击左键」添加/取消 频道收藏",
                            alignment: Alignment.centerRight,
                            scale: scale,
                          ),
                          _buildLabel(
                            context: context,
                            left: screenCenter - 695 * scale,
                            top: 288 * scale,
                            text: "「点击下键」打开 应用设置界面",
                            alignment: Alignment.centerRight,
                            scale: scale,
                          ),
                          
                          // Right Labels - 使用屏幕中心点定位
                          _buildLabel(
                            context: context,
                            left: screenCenter + 285 * scale,
                            top: 95 * scale,
                            text: "「点击确认键」确认选择操作\n显示时间/暂停/播放",
                            alignment: Alignment.centerLeft,
                            scale: scale,
                          ),
                          _buildLabel(
                            context: context,
                            left: screenCenter + 285 * scale,
                            top: 195 * scale,
                            text: "「点击右键」打开 频道选择抽屉",
                            alignment: Alignment.centerLeft,
                            scale: scale,
                          ),
                          _buildLabel(
                            context: context,
                            left: screenCenter + 285 * scale,
                            top: 355 * scale,
                            text: "「点击返回键」退出/取消操作",
                            alignment: Alignment.centerLeft,
                            scale: scale,
                          ),
                        ],
                      ),
                      SizedBox(height: 100 * scale),
                    ],
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
      ),
    );
  }
  
    Widget _buildConnectionLine({
    required double left,
    required double top,
    required double width,
    required double height,
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
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
    );
  }

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
            fontSize: 24 * scale,
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
