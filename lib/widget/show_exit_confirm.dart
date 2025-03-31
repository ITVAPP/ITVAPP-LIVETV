import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart'; 
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import '../generated/l10n.dart';

class ShowExitConfirm {
  // 定义常量
  static const _totalSteps = 100; // 动画总步数（100个百分点）
  static const _stepDuration = Duration(milliseconds: 50); // 每步持续时间，总计5秒
  static const _strokeWidth = 5.0; // 圆环粗细
  static const _gradientColors = [Colors.blue, Colors.purple, Color(0xFFEB144C)]; // 渐变颜色
  static const _gradientStops = [0.0, 0.5, 1.0]; // 渐变停止点

  // 退出确认对话框逻辑
  static Future<bool> ExitConfirm(BuildContext context) async {
    bool? exitConfirmed = await DialogUtil.showCustomDialog(
      context,
      title: '${S.current.exitTitle}💡',  // 退出提示标题
      content: S.current.exitMessage,  // 退出提示内容
      positiveButtonLabel: S.current.dialogConfirm,  // 确认按钮文本
      onPositivePressed: () {
        Navigator.of(context).pop(true);  // 返回 true 表示确认退出
      },
      negativeButtonLabel: S.current.dialogCancel,  // 取消按钮文本
      onNegativePressed: () {
        Navigator.of(context).pop(false);  // 返回 false，表示不退出
      },
      isDismissible: false,  // 点击对话框外部不关闭弹窗
    );
   
    // 如果用户确认退出，执行退出动画和退出逻辑
    if (exitConfirmed == true) {
      try {
        await _showExitAnimation(context); // 显示退出动画
        FlutterExitApp.exitApp(); // 动画完成后退出应用
      } catch (e) {
        LogUtil.e('退出应用错误: $e');  // 记录错误日志
        FlutterExitApp.exitApp(); // 确保即使出错也能退出
      }
    }
    return exitConfirmed ?? false;  // 返回非空的 bool 值，如果为空则返回 false
  }

  // 显示退出动画的独立方法
  static Future<void> _showExitAnimation(BuildContext context) async {
    final overlayState = Overlay.of(context);
    final completer = Completer<void>();
    OverlayEntry? overlayEntry;
    AnimationController? controller;

    // 使用 AnimationController 替代 Timer.periodic
    controller = AnimationController(
      duration: _stepDuration * _totalSteps, // 总动画时长
      vsync: Navigator.of(context), // 使用 Navigator 提供的 vsync
    );

    overlayEntry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: controller!,
        builder: (context, child) {
          return Stack(
            children: [
              // 添加全屏半透明背景
              Container(
                color: Colors.black.withOpacity(0.7), // 设置半透明背景颜色
              ),
              Material( 
                type: MaterialType.transparency,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 118, // logo区域大小
                        height: 118,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 圆环进度条
                            CustomPaint(
                              painter: CircleProgressPainter(
                                controller!.value, // 使用 AnimationController 的进度值
                                strokeWidth: _strokeWidth, // 使用常量控制粗细
                              ),
                              child: Container(
                                width: 118, // logo区域大小
                                height: 118,
                                alignment: Alignment.center,
                                child: ClipOval(  // 裁剪图片为圆形
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    width: 88, // LOGO 的宽度
                                    height: 88, // LOGO 的高度
                                    fit: BoxFit.cover,  // 确保图片填充整个圆形区域
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8), // 添加间距
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
      ),
    );

    try {
      // 在下一帧渲染时插入 OverlayEntry 并开始动画
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          overlayState.insert(overlayEntry!);
          controller!.forward().then((_) {
            completer.complete(); // 动画完成时标记完成
          });
        } catch (e) {
          LogUtil.e('退出动画插入失败: $e'); // 捕获回调中的异常
          completer.complete(); // 出错时也完成动画
        }
      });

      // 等待动画完成
      await completer.future;
    } finally {
      // 确保资源被清理
      controller?.dispose(); // 释放 AnimationController
      overlayEntry?.remove(); // 移除 OverlayEntry
      overlayEntry = null; // 置空引用，避免重复使用
    }
  }
}

class CircleProgressPainter extends CustomPainter {
  final double progress; // 当前进度值（0.0 到 1.0）
  final double strokeWidth; // 圆环粗细

  CircleProgressPainter(this.progress, {this.strokeWidth = _strokeWidth}); // 默认使用常量粗细

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2; // 考虑线宽计算半径

    // 绘制背景圆环
    final backgroundPaint = Paint()
      ..color = Colors.grey.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth // 使用传入的粗细参数
      ..strokeCap = StrokeCap.round; // 添加圆角效果
    canvas.drawCircle(center, radius, backgroundPaint);

    // 绘制渐变进度圆环
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: ShowExitConfirm._gradientColors, // 使用常量渐变颜色
        stops: ShowExitConfirm._gradientStops, // 使用常量渐变停止点
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth // 使用传入的粗细参数
      ..strokeCap = StrokeCap.round;

    // 绘制进度弧
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      arcRect,
      90 * (3.14159 / 180), // 起始角度（垂直向上）
      360 * progress.clamp(0.0, 1.0) * (3.14159 / 180), // 顺时针绘制进度弧
      false,
      gradientPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || 
           oldDelegate.strokeWidth != strokeWidth;
  }
}
