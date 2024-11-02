import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart'; 
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import '../generated/l10n.dart';

class ShowExitConfirm {
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
   
    // 如果用户确认退出，执行退出逻辑
    if (exitConfirmed == true) {
      try {
        final overlayState = Overlay.of(context);
       
        // 创建一个 AnimationController
        final controller = AnimationController(
          duration: const Duration(milliseconds: 5000),  // 使用毫秒确保更精确的时间控制
          vsync: Navigator.of(context),
        )..addStatusListener((status) {
          LogUtil.d('Animation status: $status'); // 添加日志记录动画状态
        });
       
        final animation = CurvedAnimation(
          parent: controller,
          curve: const Interval(0.0, 1.0, curve: Curves.linear), // 使用 Interval 确保动画平滑
        );

        final overlayEntry = OverlayEntry(
          builder: (context) => Material(  // 添加 Material widget 确保正确渲染
            type: MaterialType.transparency,
            child: Center(
              child: Container(
                width: 108, // 整个区域大小
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 圆环进度条
                    AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: CircleProgressPainter(
                            animation.value,
                            strokeWidth: 6.0, // 通过参数控制圆环粗细
                          ),
                          child: Container(
                            width: 108, // 整个区域大小
                            height: 108,
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
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
       
        // 插入 Overlay
        overlayState.insert(overlayEntry);
       
        // 开始动画，使用 try-catch 确保动画完成后的清理工作
        try {
          await controller.forward();
        } catch (e) {
          LogUtil.e('Animation error: $e');
        } finally {
          controller.dispose();
          overlayEntry.remove();
          FlutterExitApp.exitApp();  // 直接调用插件退出应用
        }
       
      } catch (e) {
        LogUtil.e('退出应用错误: $e');  // 记录日志
        FlutterExitApp.exitApp(); // 确保在出错时也能退出
      }
    }
    return exitConfirmed ?? false;  // 返回非空的 bool 值，如果为空则返回 false
  }
}

class CircleProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth; // 添加圆环粗细参数

  CircleProgressPainter(this.progress, {this.strokeWidth = 6.0}); // 默认粗细为 6.0

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2; // 考虑线宽来计算半径

    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth // 使用传入的粗细参数
      ..strokeCap = StrokeCap.round; // 添加圆角效果

    // 绘制背景圆环
    canvas.drawCircle(center, radius, paint);

    // 绘制渐变进度
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Colors.blue, Colors.purple, Color(0xFFEB144C)],
        stops: const [0.0, 0.5, 1.0], // 添加渐变停止点使颜色过渡更均匀
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth // 使用传入的粗细参数
      ..strokeCap = StrokeCap.round;

    // 绘制进度
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      arcRect,
      90 * (3.14159 / 180), // 从底部开始 (90度)
      -360 * progress.clamp(0.0, 1.0) * (3.14159 / 180), // 负值使其逆时针方向绘制,乘以进度
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
