// 修改代码开始
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:itvapp_live_tv/generated/l10n.dart';

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

class RemoteControlHelpDialog extends StatefulWidget {
  const RemoteControlHelpDialog({Key? key}) : super(key: key);

  @override
  State<RemoteControlHelpDialog> createState() => _RemoteControlHelpDialogState();
}

class _RemoteControlHelpDialogState extends State<RemoteControlHelpDialog> {
  Timer? _timer;
  int _countdown = 28;
  final FocusNode _focusNode = FocusNode();

  // 定义基线宽度常量，提高 scale 计算的灵活性
  static const double _baseScreenWidth = 1920;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// 启动倒计时定时器，确保每次启动前清理已有定时器
  void _startTimer() {
    _timer?.cancel(); // 优化：防止多个定时器同时运行
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

  void _closeDialog() {
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  /// 根据平台获取字体族
  String _getFontFamily(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS 
      ? '.SF UI Display' 
      : 'Roboto';
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size; // 获取屏幕尺寸
    final scale = (screenSize.width / _baseScreenWidth).clamp(0.5, 2.0); // 使用常量计算缩放比例
    final screenCenter = screenSize.width / 2; // 计算屏幕中心点，用于定位元素

    // 数据驱动的连接线、圆点和标签配置
    final List<Map<String, dynamic>> connectionData = [
      // 左侧连线和标签
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
        'labelText': S.current.remotehelpup,
        'labelAlignment': Alignment.centerRight,
      },
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
        'labelText': S.current.remotehelpleft,
        'labelAlignment': Alignment.centerRight,
      },
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
        'labelText': S.current.remotehelpdown,
        'labelAlignment': Alignment.centerRight,
      },
      // 右侧连线和标签
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
        'labelText': S.current.remotehelpok,
        'labelAlignment': Alignment.centerRight,
      },
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
        'labelText': S.current.remotehelpright,
        'labelAlignment': Alignment.centerLeft,
      },
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
        'labelText': S.current.remotehelpback,
        'labelAlignment': Alignment.centerLeft,
      },
    ];

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          _closeDialog();
        }
        KeyEventResult.handled;
      },
      child: Material(
        type: MaterialType.transparency, // 设置透明背景
        child: GestureDetector(
          onTap: _closeDialog, // 修改: 使用_closeDialog方法
          child: Container(
            color: const Color(0xDD000000), // 设置黑色微透明背景
            width: screenSize.width,
            height: screenSize.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 130 * scale), // 顶部空白
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
                            // 使用数据驱动的方式生成连线、圆点和标签
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
                        SizedBox(height: 100 * scale), // 底部空白
                      ],
                    ),
                  ),
                ),
                // 修改: 底部提示文本，添加倒计时显示
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 50 * scale, // 距离底部的距离
                  child: Center(
                    child: Text(
                      "$S.current.remotehelpclose ($_countdown)", // 修改：添加倒计时显示
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 25 * scale, // 字体大小
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
            fontSize: 28 * scale, // 字体大小动态缩放
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
    final width = size.width;
    final height = size.height;

    // 背景涂层的画笔配置，使用线性渐变模拟遥控器的视觉效果
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

    // 绘制遥控器主体背景
    final Path remotePath = Path()
      ..moveTo(width * 0.05, height * 0.06) // 左上角的起始点
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0) // 左上角的圆角
      ..lineTo(width * 0.85, 0) // 顶部直线
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06) // 右上角的圆角
      ..lineTo(width * 0.95, height) // 右侧直线
      ..lineTo(width * 0.05, height) // 底部直线
      ..close(); // 闭合路径

    canvas.drawPath(remotePath, backgroundPaint); // 绘制背景

    // 自定义顶部边框画笔
    final Paint topBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8) // 半透明白色
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 顶部边框路径
    final Path topBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06) // 左上角起点
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0) // 左上角圆角
      ..lineTo(width * 0.85, 0) // 顶部直线
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06); // 右上角圆角

    canvas.drawPath(topBorderPath, topBorderPaint); // 绘制顶部边框

    // 自定义左右渐变边框画笔
    final Paint gradientBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.8), // 顶部边框颜色
          Colors.white.withOpacity(0.0), // 底部渐变为透明
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;

    // 左侧边框路径
    final Path leftBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06) // 左上角起点
      ..lineTo(width * 0.05, height); // 左侧直线到底部

    canvas.drawPath(leftBorderPath, gradientBorderPaint); // 绘制左侧边框

    // 右侧边框路径
    final Path rightBorderPath = Path()
      ..moveTo(width * 0.95, height * 0.06) // 右上角起点
      ..lineTo(width * 0.95, height); // 右侧直线到底部

    canvas.drawPath(rightBorderPath, gradientBorderPaint); // 绘制右侧边框

    // 绘制圆形控制区域
    final circleCenter = Offset(width * 0.5, height * 0.33); // 圆心
    final circleRadius = width * 0.35; // 圆半径

    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = Color(0xFF444444).withOpacity(0.6) // 半透明深灰色填充
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, circleRadius, topBorderPaint); // 边框

    // 绘制方向箭头
    _drawDirectionalArrows(canvas, circleCenter, width);

    // 绘制中心圆和"OK"文本
    final centerRadius = width * 0.15;
    canvas.drawCircle(
      circleCenter,
      centerRadius,
      Paint()
        ..color = Color(0xFF333333).withOpacity(0.9) // 半透明深灰色填充
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(circleCenter, centerRadius, topBorderPaint); // 边框

    // "OK"文字绘制
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'OK',
        style: TextStyle(
          color: Colors.white, // 白色字体
          fontSize: width * 0.12, // 字体大小
          fontWeight: FontWeight.bold, // 加粗
          fontFamily: 'Roboto', // 字体
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(); // 计算文本布局

    // 文本居中绘制
    textPainter.paint(
      canvas,
      circleCenter.translate(-textPainter.width / 2, -textPainter.height / 2),
    );

    // 绘制返回按钮
    _drawBackButton(canvas, Offset(width * 0.75, height * 0.65), width);
  }

  // 绘制方向箭头
  void _drawDirectionalArrows(Canvas canvas, Offset center, double width) {
    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8) // 半透明白色填充
      ..style = PaintingStyle.fill;

    final arrowSize = width * 0.18; // 箭头宽度
    final arrowDistance = width * 0.25; // 箭头与中心圆的距离

    // 上箭头
    _drawTriangle(
      canvas,
      center.translate(0, -arrowDistance), // 上移
      arrowSize,
      arrowSize * 0.5, // 高度为宽度的一半
      0, // 不旋转
      arrowPaint,
    );

    // 右箭头
    _drawTriangle(
      canvas,
      center.translate(arrowDistance, 0), // 右移
      arrowSize,
      arrowSize * 0.5,
      90, // 顺时针旋转90度
      arrowPaint,
    );

    // 下箭头
    _drawTriangle(
      canvas,
      center.translate(0, arrowDistance), // 下移
      arrowSize,
      arrowSize * 0.5,
      180, // 顺时针旋转180度
      arrowPaint,
    );

    // 左箭头
    _drawTriangle(
      canvas,
      center.translate(-arrowDistance, 0), // 左移
      arrowSize,
      arrowSize * 0.5,
      270, // 顺时针旋转270度
      arrowPaint,
    );
  }

  // 绘制三角形，用于表示箭头
  void _drawTriangle(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    double rotation,
    Paint paint,
  ) {
    final path = Path();
    path.moveTo(0, -height / 2); // 顶点
    path.lineTo(width / 2, height / 2); // 右下角
    path.lineTo(-width / 2, height / 2); // 左下角
    path.close(); // 闭合路径

    canvas.save(); // 保存当前画布状态
    canvas.translate(center.dx, center.dy); // 移动到目标位置
    canvas.rotate(rotation * 3.14159 / 180); // 按角度旋转
    canvas.drawPath(path, paint); // 绘制三角形
    canvas.restore(); // 恢复画布状态
  }

  // 绘制返回按钮
  void _drawBackButton(Canvas canvas, Offset center, double width) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.8) // 半透明白色
      ..style = PaintingStyle.stroke // 描边
      ..strokeWidth = width * 0.01; // 描边宽度

    final radius = width * 0.08; // 圆的半径
    canvas.drawCircle(center, radius, paint); // 绘制圆

    // 绘制箭头
    paint.strokeWidth = width * 0.02; // 重新设置描边宽度
    final arrowSize = radius * 0.5; // 箭头尺寸
    final path = Path()
      ..moveTo(center.dx - arrowSize, center.dy - arrowSize) // 箭头左上角
      ..lineTo(center.dx - arrowSize, center.dy + arrowSize) // 向下
      ..lineTo(center.dx + arrowSize, center.dy + arrowSize); // 向右

    canvas.save(); // 保存当前画布状态
    canvas.translate(center.dx, center.dy); //  ascended
    canvas.drawCircle(center, radius, paint); // 绘制圆

    // 绘制箭头
    paint.strokeWidth = width * 0.02; // 重新设置描边宽度
    final arrowSize = radius * 0.5; // 箭头尺寸
    final path = Path()
      ..moveTo(center.dx - arrowSize, center.dy - arrowSize) // 箭头左上角
      ..lineTo(center.dx - arrowSize, center.dy + arrowSize) // 向下
      ..lineTo(center.dx + arrowSize, center.dy + arrowSize); // 向右

    canvas.save(); // 保存当前画布状态
    canvas.translate(center.dx, center.dy); // 移动到箭头位置
    canvas.rotate(45 * 3.14159 / 180); // 顺时针旋转45度
    canvas.translate(-center.dx, -center.dy); // 还原中心点位置
    canvas.translate(width * 0.02, -width * 0.02); // 微调箭头位置
    canvas.drawPath(path, paint); // 绘制箭头
    canvas.restore(); // 恢复画布状态
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false; // 无需重绘
}
// 修改代码结束
