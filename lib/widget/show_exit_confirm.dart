import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart'; 
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class ShowExitConfirm {
  // 定义常量
  static const _totalSteps = 100; // 动画总步数（100个百分点）
  static const _stepDuration = Duration(milliseconds: 50); // 每步持续时间，总计5秒
  static const _strokeWidth = 5.0; // 圆环粗细
  static const _gradientColors = [Colors.blue, Colors.purple, Color(0xFFEB144C)]; // 渐变颜色数组
  static const _gradientStops = [0.0, 0.5, 1.0]; // 渐变颜色停止点
  
  // 优化：预计算数学常量
  static const _deg2Rad = 3.14159 / 180; // 角度转弧度常量
  static const _startAngle = 90 * _deg2Rad; // 起始角度（从顶部开始）

  // 显示退出确认对话框并返回用户选择结果
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
   
    // 处理用户确认退出时的逻辑
    if (exitConfirmed == true) {
      try {
        await _showExitAnimation(context); // 显示退出动画
        FlutterExitApp.exitApp(); // 动画结束后退出应用
      } catch (e) {
        LogUtil.e('退出应用错误: $e'); // 记录退出时的异常
        FlutterExitApp.exitApp(); // 确保即使出错也能退出
      }
    }
    return exitConfirmed ?? false; // 返回确认结果，默认false
  }

  // 显示退出时的圆环动画效果
  static Future<void> _showExitAnimation(BuildContext context) async {
    final overlayState = Overlay.of(context);
    final completer = Completer<void>();
    OverlayEntry? overlayEntry;
    AnimationController? controller;

    // 初始化动画控制器，控制动画时长和进度
    controller = AnimationController(
      duration: _stepDuration * _totalSteps, // 总动画时长5秒
      vsync: Navigator.of(context), // 使用Navigator提供的同步机制
    );

    overlayEntry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: controller!,
        builder: (context, child) {
          return Stack(
            children: [
              // 全屏半透明背景层
              Container(
                color: Colors.black.withOpacity(0.7), // 背景色带70%透明度
              ),
              Material( 
                type: MaterialType.transparency,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 118, // 圆环和logo的容器宽度
                        height: 118, // 圆环和logo的容器高度
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 绘制带进度的圆环
                            CustomPaint(
                              painter: CircleProgressPainter(
                                controller!.value, // 当前动画进度
                                strokeWidth: _strokeWidth, // 圆环粗细
                              ),
                              child: Container(
                                width: 118, // logo区域宽度
                                height: 118, // logo区域高度
                                alignment: Alignment.center,
                                child: ClipOval( 
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    width: 88, // logo图片宽度
                                    height: 88, // logo图片高度
                                    fit: BoxFit.cover, // 图片填充裁剪区域
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8), // 文字与圆环间距
                      Text(
                        S.current.exittip, // 退出提示文本
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
      // 在下一帧插入动画并启动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          overlayState.insert(overlayEntry!);
          controller!.forward().then((_) {
            completer.complete(); // 动画完成时标记完成
          });
        } catch (e) {
          LogUtil.e('退出动画插入失败: $e'); // 记录插入失败的异常
          completer.complete(); // 出错时强制完成
        }
      });

      // 等待动画执行完毕
      await completer.future;
    } finally {
      // 清理资源
      controller?.dispose(); // 释放动画控制器
      overlayEntry?.remove(); // 移除动画层
      overlayEntry = null; // 清空引用
    }
  }
}

// 自定义圆环进度条绘制类
class CircleProgressPainter extends CustomPainter {
  final double progress; // 当前进度值（0.0到1.0）
  final double strokeWidth; // 圆环粗细
  
  // 优化：使用静态Paint对象复用，避免每帧创建新对象
  static final Paint _backgroundPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  
  static final Paint _progressPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  CircleProgressPainter(this.progress, {required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2; // 计算圆环半径

    // 优化：复用Paint对象，只更新必要的属性
    _backgroundPaint
      ..color = Colors.grey.withOpacity(0.5)
      ..strokeWidth = strokeWidth;
    
    // 绘制灰色背景圆环
    canvas.drawCircle(center, radius, _backgroundPaint);

    // 优化：复用Paint对象并设置渐变着色器
    _progressPaint
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: ShowExitConfirm._gradientColors, // 应用渐变颜色
        stops: ShowExitConfirm._gradientStops, // 应用渐变停止点
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = strokeWidth;

    // 绘制进度弧线
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    // 优化：使用预计算的常量，避免每帧重复计算
    canvas.drawArc(
      arcRect,
      ShowExitConfirm._startAngle, // 使用预计算的起始角度
      360 * progress.clamp(0.0, 1.0) * ShowExitConfirm._deg2Rad, // 使用预计算的转换常量
      false,
      _progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || 
           oldDelegate.strokeWidth != strokeWidth; // 判断是否需要重绘
  }
}
