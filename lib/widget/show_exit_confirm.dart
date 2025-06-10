import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart';
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
  // 动画容器尺寸
  static const _containerSize = 118.0;
  // Logo尺寸
  static const _logoSize = 88.0;
  // 动画循环时长（毫秒）
  static const _animationDuration = 2000;

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
      _showExitAnimation(context); // 显示退出动画（包含退出逻辑）
      
      // 返回false，防止调用方立即退出
      return false;
    }
    return exitConfirmed ?? false; // 返回确认结果，默认false
  }

  // 显示退出时的圆环动画
  static void _showExitAnimation(BuildContext context) {
    final overlayState = Overlay.of(context);
    OverlayEntry? overlayEntry;

    try {
      overlayEntry = OverlayEntry(
        builder: (context) => _ExitAnimationWidget(),
      );

      // 插入动画层
      overlayState.insert(overlayEntry);

      // 清理资源并退出
      Timer(Duration(seconds: _exitDelaySeconds), () {
        overlayEntry?.remove(); // 先移除overlay
        FlutterExitApp.exitApp(); // 然后退出应用
      });
    } catch (e) {
      LogUtil.e('退出动画异常: $e');
      // 异常时直接退出，不影响主要功能
      FlutterExitApp.exitApp();
    }
  }
}

// 退出动画组件
class _ExitAnimationWidget extends StatefulWidget {
  const _ExitAnimationWidget({Key? key}) : super(key: key);

  @override
  State<_ExitAnimationWidget> createState() => _ExitAnimationWidgetState();
}

class _ExitAnimationWidgetState extends State<_ExitAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: ShowExitConfirm._animationDuration), // 循环速度：2000毫秒一圈
      vsync: this,
    );
    _controller.repeat(); // 无限循环播放，直到被dispose
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  width: ShowExitConfirm._containerSize,
                  height: ShowExitConfirm._containerSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 绘制循环加载圆环
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: LoadingCirclePainter(
                              _controller.value, // 当前动画进度
                              strokeWidth: ShowExitConfirm._strokeWidth,
                            ),
                            child: Container(
                              width: ShowExitConfirm._containerSize,
                              height: ShowExitConfirm._containerSize,
                            ),
                          );
                        },
                      ),
                      // Logo图片
                      ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: ShowExitConfirm._logoSize,
                          height: ShowExitConfirm._logoSize,
                          fit: BoxFit.cover,
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
  }
}

// 自定义循环加载圆环绘制
class LoadingCirclePainter extends CustomPainter {
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

  // 缓存的shader对象
  static Shader? _cachedShader;
  static Size? _cachedShaderSize;

  LoadingCirclePainter(this.progress, {required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2; // 计算圆环半径

    // 绘制灰色背景圆环
    _backgroundPaint
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, _backgroundPaint);

    // 计算旋转角度和弧长
    final rotationAngle = progress * 2 * 3.14159; // 完整旋转
    final arcLength = 3.14159; // 固定弧长（180度）

    // 缓存shader对象，仅在尺寸变化时重新创建
    if (_cachedShader == null || _cachedShaderSize != size) {
      _cachedShader = LinearGradient(
        begin: Alignment(-1, -1),
        end: Alignment(1, 1),
        colors: ShowExitConfirm._gradientColors, // 渐变颜色
        stops: ShowExitConfirm._gradientStops, // 渐变停止点
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      _cachedShaderSize = size;
    }

    // 绘制渐变加载弧线
    _progressPaint
      ..shader = _cachedShader
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotationAngle - 1.5708, // 起始角度（-90度）+ 旋转角度
      arcLength, // 固定弧长
      false,
      _progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant LoadingCirclePainter oldDelegate) {
    return oldDelegate.progress != progress; // 判断是否重绘
  }
}
