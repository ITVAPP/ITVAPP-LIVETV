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
    
    // 遥控器背景渐变
    final Paint gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF666666),
          const Color(0xFF333333),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    // 遥控器外框路径
    final path = Path()
      ..moveTo(width * 0.1, 0)
      ..lineTo(width * 0.9, 0)
      ..quadraticBezierTo(width, 0, width, height * 0.05)
      ..lineTo(width, height * 0.95)
      ..quadraticBezierTo(width, height, width * 0.9, height)
      ..lineTo(width * 0.1, height)
      ..quadraticBezierTo(0, height, 0, height * 0.95)
      ..lineTo(0, height * 0.05)
      ..quadraticBezierTo(0, 0, width * 0.1, 0);

    // 绘制遥控器背景
    canvas.drawPath(path, gradientPaint);

    // 遥控器边框
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, borderPaint);

    // 方向键背景
    final directionPadPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // 方向键圆形背景
    canvas.drawCircle(
      Offset(width * 0.5, height * 0.25),
      width * 0.2,
      directionPadPaint,
    );

    // 方向键按钮
    final buttonPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // 上键
    _drawDirectionButton(
      canvas,
      Offset(width * 0.5, height * 0.15),
      buttonPaint,
      width * 0.08,
    );

    // 右键
    _drawDirectionButton(
      canvas,
      Offset(width * 0.65, height * 0.25),
      buttonPaint,
      width * 0.08,
    );

    // 下键
    _drawDirectionButton(
      canvas,
      Offset(width * 0.5, height * 0.35),
      buttonPaint,
      width * 0.08,
    );

    // 左键
    _drawDirectionButton(
      canvas,
      Offset(width * 0.35, height * 0.25),
      buttonPaint,
      width * 0.08,
    );

    // 确认键
    _drawDirectionButton(
      canvas,
      Offset(width * 0.5, height * 0.25),
      buttonPaint,
      width * 0.06,
    );

    // 返回键
    final backButtonPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(width * 0.5, height * 0.7),
      width * 0.1,
      backButtonPaint,
    );
  }

  void _drawDirectionButton(Canvas canvas, Offset center, Paint paint, double radius) {
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
