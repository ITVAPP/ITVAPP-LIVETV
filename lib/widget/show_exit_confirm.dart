import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 退出确认对话框
class ShowExitConfirm {
  // 退出倒计时时间（秒）
  static const _exitDelaySeconds = 5;
  // 圆环粗细
  static const _strokeWidth = 5.0;
  // 渐变颜色数组
  static const _gradientColors = [Colors.blue, Colors.purple, Color(0xFFEB144C)];
  // 渐变颜色停止点
  static const _gradientStops = [0.0, 0.5, 1.0];
  // 角度转弧度常量
  static const _deg2Rad = 3.14159 / 180;
  // 圆环起始角度，从顶部开始
  static const _startAngle = 90 * _deg2Rad;

  // 显示退出确认对话框，返回用户选择结果
  static Future<bool> ExitConfirm(BuildContext context) async {
    bool? exitConfirmed = await DialogUtil.showCustomDialog(
      context,
      title: '${S.current.exitTitle}💡', // 退出提示标题，带表情符号
      content: S.current.exitMessage, // 退出提示内容
      positiveButtonLabel: S.current.dialogConfirm, // 确认按钮文本
      onPositivePressed: () {
        Navigator.of(context).pop(true); // 点击确认返回true
      },
      negativeButtonLabel: S.current.dialogCancel, // 取消按钮文本
      onNegativePressed: () {
        Navigator.of(context).pop(false); // 点击取消返回false
      },
      isDismissible: false, // 禁止点击外部关闭对话框
    );

    // 处理用户确认退出逻辑
    if (exitConfirmed == true) {
      _showExitAnimation(context); // 显示退出动画（不等待）
      
      // 启动定时器，5秒后退出应用
      Timer(Duration(seconds: _exitDelaySeconds), () {
        FlutterExitApp.exitApp();
      });
    }
    return exitConfirmed ?? false; // 返回确认结果，默认false
  }

  // 显示退出时的圆环动画（简化版本）
  static void _showExitAnimation(BuildContext context) {
    final overlayState = Overlay.of(context);
    OverlayEntry? overlayEntry;
    AnimationController? controller;

    try {
      // 创建动画控制器，循环播放
      controller = AnimationController(
        duration: Duration(seconds: 2), // 单次动画时长2秒
        vsync: Navigator.of(context),
      );

      overlayEntry = OverlayEntry(
        builder: (context) => _ExitAnimationWidget(controller: controller!),
      );

      // 插入动画层并启动循环动画
      overlayState.insert(overlayEntry);
      controller.repeat(reverse: true); // 来回循环播放

      // 5秒后清理资源
      Timer(Duration(seconds: _exitDelaySeconds), () {
        controller?.dispose();
        overlayEntry?.remove();
      });
    } catch (e) {
      LogUtil.e('退出动画异常: $e');
      // 异常时直接退出，不影响主要功能
      Timer(Duration(seconds: _exitDelaySeconds), () {
        FlutterExitApp.exitApp();
      });
    }
  }
}

// 退出动画组件（抽取为独立Widget，简化结构）
class _ExitAnimationWidget extends StatelessWidget {
  final AnimationController controller;

  const _ExitAnimationWidget({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          children: [
            // 全屏半透明背景
            Container(
              color: Colors.black.withOpacity(0.7),
            ),
            Material(
              type: MaterialType.transparency,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 圆环和logo容器
                    Container(
                      width: 118,
                      height: 118,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 绘制带进度的圆环
                          CustomPaint(
                            painter: CircleProgressPainter(
                              controller.value, // 当前动画进度
                              strokeWidth: ShowExitConfirm._strokeWidth,
                            ),
                            child: Container(
                              width: 118,
                              height: 118,
                              alignment: Alignment.center,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 退出提示文本
                    Text(
                      S.current.exittip,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// 自定义圆环进度条绘制
class CircleProgressPainter extends CustomPainter {
  final double progress; // 当前进度值，0.0到1.0
  final double strokeWidth; // 圆环粗细

  // 静态背景画笔，复用以优化性能
  static final Paint _backgroundPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  // 静态进度画笔，复用以优化性能
  static final Paint _progressPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  CircleProgressPainter(this.progress, {required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2; // 计算圆环半径

    // 绘制灰色背景圆环
    _backgroundPaint
      ..color = Colors.grey.withOpacity(0.5)
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, _backgroundPaint);

    // 绘制渐变进度弧线
    _progressPaint
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: ShowExitConfirm._gradientColors, // 渐变颜色
        stops: ShowExitConfirm._gradientStops, // 渐变停止点
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = strokeWidth;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      ShowExitConfirm._startAngle, // 圆环起始角度
      360 * progress.clamp(0.0, 1.0) * ShowExitConfirm._deg2Rad, // 进度弧线角度
      false,
      _progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.strokeWidth != strokeWidth; // 判断是否重绘
  }
}
