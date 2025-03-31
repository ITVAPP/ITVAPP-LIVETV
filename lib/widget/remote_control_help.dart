import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import '../generated/l10n.dart';

class RemoteControlHelp {
  /// 显示遥控器帮助对话框
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
  final FocusNode _focusNode = FocusNode(); // 键盘焦点管理
  bool _isDialogOpen = true; // 检查对话框是否打开

  @override
  void initState() {
    super.initState();
    _startTimer(); // 启动倒计时
    _focusNode.requestFocus(); // 获取键盘焦点
  }

  @override
  void dispose() {
    _timer?.cancel(); // 取消定时器
    _focusNode.dispose(); // 释放焦点资源
    super.dispose();
  }

  /// 启动倒计时，仅在关键秒数更新 UI
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        _countdown--;
        if (_countdown % 5 == 0 || _countdown <= 5) { // 每5秒或最后5秒刷新
          setState(() {});
        }
      } else {
        _closeDialog(); // 倒计时结束关闭对话框
      }
    });
  }

  /// 关闭对话框并确保只关闭一次
  void _closeDialog() {
    if (_isDialogOpen) {
      _timer?.cancel();
      Navigator.of(context).pop();
      _isDialogOpen = false; // 更新关闭状态
    }
  }

  /// 根据平台返回字体族（iOS 用 SF，非 iOS 用 Roboto）
  String _getFontFamily(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS 
      ? '.SF UI Display' 
      : 'Roboto';
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size; // 获取屏幕尺寸
    final scale = (screenSize.width / 1920).clamp(0.5, 2.0); // 计算缩放比例
    final screenCenter = screenSize.width / 2; // 屏幕水平中心点

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) _closeDialog(); // 按键时关闭对话框
        return KeyEventResult.handled; // 标记事件已处理
      },
      child: Material(
        type: MaterialType.transparency, // 透明背景
        child: GestureDetector(
          onTap: _closeDialog, // 点击关闭对话框
          child: Container(
            color: const Color(0xDD000000), // 黑色微透明背景
            width: screenSize.width,
            height: screenSize.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 130 * scale), // 顶部间距
                        Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Center(
                              child: SizedBox(
                                width: 400 * scale, // 遥控器宽度
                                height: 600 * scale, // 遥控器高度
                                child: CustomPaint(
                                  painter: RemoteControlPainter(), // 绘制遥控器
                                ),
                              ),
                            ),
                            ..._buildConnectionLinesAndDots(screenCenter, scale), // 连接线和圆点
                            ..._buildLabels(screenCenter, scale, context), // 标签列表
                          ],
                        ),
                        SizedBox(height: 100 * scale), // 底部间距
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 50 * scale, // 底部提示距离
                  child: Center(
                    child: Text(
                      "${S.current.remotehelpclose} ($_countdown)", // 显示倒计时
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

  /// 生成连接线和小圆点的组件列表
  List<Widget> _buildConnectionLinesAndDots(double screenCenter, double scale) {
    final List<Map<String, dynamic>> lineDotData = [
      // 左侧连接线和圆点数据
      {'left': screenCenter - 270 * scale, 'top': 90 * scale, 'width': 250 * scale, 'height': 3 * scale, 'isLeftSide': false, 'dotTop': 88 * scale},
      {'left': screenCenter - 270 * scale, 'top': 190 * scale, 'width': 150 * scale, 'height': 3 * scale, 'isLeftSide': false, 'dotTop': 188 * scale},
      {'left': screenCenter - 270 * scale, 'top': 310 * scale, 'width': 245 * scale, 'height': 3 * scale, 'isLeftSide': false, 'dotTop': 308 * scale},
      // 右侧连接线和圆点数据
      {'left': screenCenter + 50 * scale, 'top': 150 * scale, 'width': 235 * scale, 'height': 3 * scale, 'isLeftSide': true, 'dotLeft': screenCenter + 282 * scale, 'dotTop': 148 * scale},
      {'left': screenCenter + 110 * scale, 'top': 215 * scale, 'width': 180 * scale, 'height': 3 * scale, 'isLeftSide': true, 'dotLeft': screenCenter + 282 * scale, 'dotTop': 213 * scale},
      {'left': screenCenter + 110 * scale, 'top': 378 * scale, 'width': 175 * scale, 'height': 3 * scale, 'isLeftSide': true, 'dotLeft': screenCenter + 282 * scale, 'dotTop': 375 * scale},
    ];

    return lineDotData.map((data) {
      return [
        _buildConnectionLine(
          left: data['left'],
          top: data['top'],
          width: data['width'],
          height: data['height'],
          isLeftSide: data['isLeftSide'],
        ),
        _buildDot(
          left: data['dotLeft'] ?? screenCenter - 275 * scale, // 默认左侧圆点位置
          top: data['dotTop'],
          size: 8 * scale,
        ),
      ];
    }).expand((element) => element).toList(); // 展开为单一列表
  }

  /// 生成标签的组件列表
  List<Widget> _buildLabels(double screenCenter, double scale, BuildContext context) {
    final List<Map<String, dynamic>> labelData = [
      // 左侧标签数据
      {'left': screenCenter - 690 * scale, 'top': 75 * scale, 'text': S.current.remotehelpup, 'alignment': Alignment.centerRight},
      {'left': screenCenter - 700 * scale, 'top': 170 * scale, 'text': S.current.remotehelpleft, 'alignment': Alignment.centerRight},
      {'left': screenCenter - 690 * scale, 'top': 292 * scale, 'text': S.current.remotehelpdown, 'alignment': Alignment.centerRight},
      // 右侧标签数据
      {'left': screenCenter + 285 * scale, 'top': 95 * scale, 'text': S.current.remotehelpok, 'alignment': Alignment.centerRight},
      {'left': screenCenter + 285 * scale, 'top': 195 * scale, 'text': S.current.remotehelpright, 'alignment': Alignment.centerLeft},
      {'left': screenCenter + 285 * scale, 'top': 355 * scale, 'text': S.current.remotehelpback, 'alignment': Alignment.centerLeft},
    ];

    return labelData.map((data) {
      return _buildLabel(
        context: context,
        left: data['left'],
        top: data['top'],
        text: data['text'],
        alignment: data['alignment'],
        scale: scale,
      );
    }).toList();
  }

  /// 构建渐变连接线组件
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
            colors: [Colors.white.withOpacity(0.8), Colors.white.withOpacity(0)],
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
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// 构建文本标签组件
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
          textAlign: alignment == Alignment.centerLeft ? TextAlign.left : TextAlign.right,
        ),
      ),
    );
  }
}

/// 自定义绘制遥控器图形
class RemoteControlPainter extends CustomPainter {
  static final _cache = <Size, Picture>{}; // 缓存绘制结果

  @override
  void paint(Canvas canvas, Size size) {
    final recorder = PictureRecorder();
    final cacheCanvas = Canvas(recorder);
    final width = size.width;
    final height = size.height;

    final Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF444444).withOpacity(0.6),
          Color(0xFF444444).withOpacity(0.3),
          Color(0xFF444444).withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height)); // 背景渐变

    // 绘制遥控器主体
    final Path remotePath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06)
      ..lineTo(width * 0.95, height)
      ..lineTo(width * 0.05, height)
      ..close();
    cacheCanvas.drawPath(remotePath, backgroundPaint);

    // 顶部边框
    final Paint topBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;
    final Path topBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..quadraticBezierTo(width * 0.05, 0, width * 0.15, 0)
      ..lineTo(width * 0.85, 0)
      ..quadraticBezierTo(width * 0.95, 0, width * 0.95, height * 0.06);
    cacheCanvas.drawPath(topBorderPath, topBorderPaint);

    // 左右渐变边框
    final Paint gradientBorderPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withOpacity(0.8), Colors.white.withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..strokeWidth = width * 0.01
      ..style = PaintingStyle.stroke;
    final Path leftBorderPath = Path()
      ..moveTo(width * 0.05, height * 0.06)
      ..lineTo(width * 0.05, height);
    cacheCanvas.drawPath(leftBorderPath, gradientBorderPaint);
    final Path rightBorderPath = Path()
      ..moveTo(width * 0.95, height * 0.06)
      ..lineTo(width * 0.95, height);
    cacheCanvas.drawPath(rightBorderPath, gradientBorderPaint);

    // 绘制圆形控制区域
    final circleCenter = Offset(width * 0.5, height * 0.33);
    final circleRadius = width * 0.35;
    cacheCanvas.drawCircle(circleCenter, circleRadius, Paint()..color = Color(0xFF444444).withOpacity(0.6));
    cacheCanvas.drawCircle(circleCenter, circleRadius, topBorderPaint);

    _drawDirectionalArrows(cacheCanvas, circleCenter, width); // 绘制方向箭头

    // 绘制中心“OK”按钮
    final centerRadius = width * 0.15;
    cacheCanvas.drawCircle(circleCenter, centerRadius, Paint()..color = Color(0xFF333333).withOpacity(0.9));
    cacheCanvas.drawCircle(circleCenter, centerRadius, topBorderPaint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'OK',
        style: TextStyle(color: Colors.white, fontSize: width * 0.12, fontWeight: FontWeight.bold, fontFamily: 'Roboto'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(cacheCanvas, circleCenter.translate(-textPainter.width / 2, -textPainter.height / 2));

    _drawBackButton(cacheCanvas, Offset(width * 0.75, height * 0.65), width); // 绘制返回按钮

    final picture = recorder.endRecording();
    _cache[size] = picture; // 缓存绘制结果
    canvas.drawPicture(picture);
  }

  /// 绘制四个方向箭头
  void _drawDirectionalArrows(Canvas canvas, Offset center, double width) {
    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    final arrowSize = width * 0.18;
    final arrowDistance = width * 0.25;
    _drawTriangle(canvas, center.translate(0, -arrowDistance), arrowSize, arrowSize * 0.5, 0, arrowPaint); // 上
    _drawTriangle(canvas, center.translate(arrowDistance, 0), arrowSize, arrowSize * 0.5, 90, arrowPaint); // 右
    _drawTriangle(canvas, center.translate(0, arrowDistance), arrowSize, arrowSize * 0.5, 180, arrowPaint); // 下
    _drawTriangle(canvas, center.translate(-arrowDistance, 0), arrowSize, arrowSize * 0.5, 270, arrowPaint); // 左
  }

  /// 绘制三角形箭头
  void _drawTriangle(Canvas canvas, Offset center, double width, double height, double rotation, Paint paint) {
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
  bool shouldRepaint(CustomPainter oldDelegate) => false; // 无需重绘
}
