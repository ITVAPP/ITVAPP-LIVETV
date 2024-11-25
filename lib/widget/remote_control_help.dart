import 'package:flutter/material.dart';

class RemoteControlHelp {
  /// 显示遥控器帮助对话框
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

  /// 根据平台获取字体族
  String _getFontFamily(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS 
      ? '.SF UI Display' 
      : 'Roboto';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size; // 获取屏幕尺寸
    final scale = (screenSize.width / 1920).clamp(0.5, 2.0); // 缩放比例，限制在0.5到2之间
    final screenCenter = screenSize.width / 2; // 计算屏幕中心点，用于定位元素

    return Material(
      type: MaterialType.transparency, // 设置透明背景
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(), // 点击时关闭对话框
        child: Container(
          color: Colors.black, // 设置黑色背景
          width: screenSize.width,
          height: screenSize.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: 120 * scale), // 顶部空白
                      Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // 遥控器SVG图形，确保居中显示
                          Center(
                            child: SizedBox(
                              width: 400 * scale, // 遥控器宽度
                              height: 600 * scale, // 遥控器高度
                              child: CustomPaint(
                                painter: RemoteControlPainter(), // 自定义绘制遥控器
                              ),
                            ),
                          ),
                          // 左侧连线
                          _buildConnectionLine(
                            left: screenCenter - 270 * scale, 
                            top: 90 * scale,
                            width: 250 * scale, // 连线宽度
                            height: 3 * scale, // 连线高度
                            isLeftSide: true,
                          ),
                          _buildConnectionLine(
                            left: screenCenter - 270 * scale, 
                            top: 190 * scale, 
                            width: 150 * scale,
                            height: 3 * scale,
                            isLeftSide: false,
                          ),
                          _buildConnectionLine(
                            left: screenCenter - 270 * scale, 
                            top: 310 * scale, 
                            width: 245 * scale,
                            height: 3 * scale,
                          ),
                          // 右侧连线
                          _buildConnectionLine(
                            left: screenCenter + 70 * scale, 
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
                          // 左侧小圆点
                          _buildDot(
                            left: screenCenter - 275 * scale, 
                            top: 88 * scale,
                            size: 8 * scale, // 圆点大小
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
                          // 右侧小圆点
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
                          // 左侧标签
                          _buildLabel(
                            context: context,
                            left: screenCenter - 675 * scale,
                            top: 75 * scale,
                            text: "「点击上键」打开 线路切换菜单",
                            alignment: Alignment.centerRight,
                            scale: scale,
                          ),
                          _buildLabel(
                            context: context,
                            left: screenCenter - 675 * scale,
                            top: 170 * scale,
                            text: "「点击左键」添加/取消 频道收藏",
                            alignment: Alignment.centerRight,
                            scale: scale,
                          ),
                          _buildLabel(
                            context: context,
                            left: screenCenter - 675 * scale,
                            top: 292 * scale,
                            text: "「点击下键」打开 应用设置界面",
                            alignment: Alignment.centerRight,
                            scale: scale,
                          ),
                          // 右侧标签
                          _buildLabel(
                            context: context,
                            left: screenCenter + 285 * scale,
                            top: 95 * scale,
                            text: "「点击确认键」确认选择操作\n显示时间/暂停/播放",
                            alignment: Alignment.centerRight,
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
                      SizedBox(height: 100 * scale), // 底部空白
                    ],
                  ),
                ),
              ),
              // 底部提示文本
              Positioned(
                left: 0,
                right: 0,
                bottom: 50 * scale, // 距离底部的距离
                child: Center(
                  child: Text(
                    "点击任意按键关闭使用帮助 (18)", // 提示文本
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16 * scale, // 字体大小
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

/// 构建连接线组件
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
          // 根据是左侧还是右侧来决定渐变方向
          begin: isLeftSide ? Alignment.centerRight : Alignment.centerLeft,
          end: isLeftSide ? Alignment.centerLeft : Alignment.centerRight,
        ),
      ),
    ),
  );
}

  /// 构建小圆点组件
  Widget _buildDot({
    required double left,
    required double top,
    required double size,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: size, // 圆点的宽度
        height: size, // 圆点的高度
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8), // 圆点颜色
          shape: BoxShape.circle, // 圆点形状
        ),
      ),
    );
  }

  /// 构建标签组件
  Widget _buildLabel({
    required BuildContext context,
    required double left,
    required double top,
    required String text,
    required Alignment alignment,
    required double scale,
  }) {
    return Positioned(
      left: left, // 标签位置
      top: top, // 标签位置
      child: Container(
        alignment: alignment, // 文本对齐方式
        child: Text(
          text, // 标签文本
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 24 * scale, // 字体大小动态缩放
            fontFamily: _getFontFamily(context), // 字体
          ),
          textAlign: alignment == Alignment.centerLeft 
              ? TextAlign.left 
              : TextAlign.right, // 根据对齐方式设置文本方向
        ),
      ),
    );
  }
}

  /// 遥控器SVG绘制
class RemoteControlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width; // 绘制区域宽度
    final height = size.height; // 绘制区域高度

    // 绘制遥控器主体背景
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

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height), 
      backgroundPaint
    );

    // 左边框渐变
    final Paint leftBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.5),
          Colors.white.withOpacity(0.3),
          Colors.white.withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(
        width * 0.05,
        0,
        0,
        height
      ))
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 右边框渐变
    final Paint rightBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.5),
          Colors.white.withOpacity(0.3),
          Colors.white.withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(
        width * 0.95,
        0,
        0,
        height
      ))
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 上边框（不带渐变）
    final Paint topBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 左边框（带渐变）
    canvas.drawLine(
      Offset(width * 0.05, 0), 
      Offset(width * 0.05, height), 
      leftBorderPaint
    );

    // 右边框（带渐变）
    canvas.drawLine(
      Offset(width * 0.95, 0), 
      Offset(width * 0.95, height), 
      rightBorderPaint
    );

    // 上边框
    canvas.drawLine(
      Offset(width * 0.05, 0), 
      Offset(width * 0.95, 0), 
      topBorderPaint
    );

    // 中心圆区域
    final circleCenter = Offset(width * 0.5, height * 0.33); // 中心圆的位置
    final circleRadius = width * 0.35; // 中心圆的半径

    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = Color(0xFF444444).withOpacity(0.5)
        ..style = PaintingStyle.fill,
    );
    
    // 绘制方向箭头
    _drawDirectionalArrows(canvas, circleCenter, width);

    // 绘制中心圆和"OK"文本
    final centerRadius = width * 0.15;
    canvas.drawCircle(
      circleCenter,
      centerRadius,
      Paint()
        ..color = Color(0xFF333333).withOpacity(0.7)
        ..style = PaintingStyle.fill,
    );

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
    // 调整返回按钮位置：修改 width * 0.75 和 height * 0.7 这两个值可以改变返回按钮的位置
    // width * 0.75：越大越靠右，越小越靠左
    // height * 0.7：越大越靠下，越小越靠上
    _drawBackButton(canvas, Offset(width * 0.75, height * 0.5), width);
  }

  /// 绘制方向箭头
  void _drawDirectionalArrows(Canvas canvas, Offset center, double width) {
    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    // 调整方向箭头大小：修改 width * 0.18 这个值可以改变箭头大小
    // 值越大箭头越大，值越小箭头越小
    final arrowSize = width * 0.18;

    // 调整箭头与中心的距离：修改 width * 0.25 这个值可以改变箭头离中心的距离
    // 值越大箭头离中心越远，值越小箭头离中心越近
    final arrowDistance = width * 0.25;

    // 上箭头位置：通过修改 -arrowDistance 可以调整上箭头的上下位置
    // 数值越小，箭头位置越向上
    _drawTriangle(
      canvas,
      center.translate(0, -arrowDistance),
      arrowSize,
      arrowSize * 0.5,
      0,
      arrowPaint,
    );

    // 右箭头位置：通过修改 arrowDistance 可以调整右箭头的左右位置
    // 数值越大，箭头位置越向右
    _drawTriangle(
      canvas,
      center.translate(arrowDistance, 0),
      arrowSize,
      arrowSize * 0.5,
      90,
      arrowPaint,
    );

    // 下箭头位置：通过修改 arrowDistance 可以调整下箭头的上下位置
    // 数值越大，箭头位置越向下
    _drawTriangle(
      canvas,
      center.translate(0, arrowDistance),
      arrowSize,
      arrowSize * 0.5,
      180,
      arrowPaint,
    );

    // 左箭头位置：通过修改 -arrowDistance 可以调整左箭头的左右位置
    // 数值越小，箭头位置越向左
    _drawTriangle(
      canvas,
      center.translate(-arrowDistance, 0),
      arrowSize,
      arrowSize * 0.5,
      270,
      arrowPaint,
    );
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

  /// 绘制返回按钮
  void _drawBackButton(Canvas canvas, Offset center, double width) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      // 调整返回按钮圆圈的线条粗细：修改 width * 0.01 这个值
      // 值越大线条越粗，值越小线条越细
      ..strokeWidth = width * 0.01;

    // 调整返回按钮圆圈的大小：修改 width * 0.08 这个值
    // 值越大圆圈越大，值越小圆圈越小
    final radius = width * 0.08;
    canvas.drawCircle(center, radius, paint);

    // 调整返回箭头的线条粗细：修改 width * 0.02 这个值
    // 值越大线条越粗，值越小线条越细
    paint.strokeWidth = width * 0.02;

    // 调整返回箭头的大小：修改 radius * 0.6 这个值
    // 值越大箭头越大，值越小箭头越小
    final arrowSize = radius * 0.6;
    final path = Path()
      ..moveTo(center.dx - arrowSize, center.dy - arrowSize)
      ..lineTo(center.dx - arrowSize, center.dy + arrowSize)
      ..lineTo(center.dx + arrowSize, center.dy + arrowSize);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // 调整返回箭头的旋转角度：修改 45 这个值
    // 值越大旋转角度越大
    canvas.rotate(45 * 3.14159 / 180);
    canvas.translate(-center.dx, -center.dy);
    // 微调返回箭头的位置：修改 width * 0.05 和 -width * 0.05 这两个值
    canvas.translate(width * 0.05, -width * 0.05);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
