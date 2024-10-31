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
        // 使用 Overlay 添加全屏淡出动画和 Logo
        final overlayState = Overlay.of(context);
       
        // 创建一个 AnimationController
        final controller = AnimationController(
          duration: const Duration(milliseconds: 800),  // 增加动画时长以适应 Logo 淡出
          vsync: Navigator.of(context),
        );
       
        final animation = CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        );
        final overlayEntry = OverlayEntry(
          builder: (context) => AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Container(
              // 使用半透明的黑色背景
              color: Colors.black.withOpacity(0.6 * animation.value), // 60%的不透明度
              child: Center(
                child: Opacity(
                  opacity: animation.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 使用 Container 创建圆形 logo
                      Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,  // 设置形状为圆形
                          boxShadow: [  // 添加阴影效果
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(  // 裁剪图片为圆形
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.cover,  // 确保图片填充整个圆形区域
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        S.current.appName,  // 退出文字
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
       
        // 插入 Overlay
        overlayState.insert(overlayEntry);
       
        // 开始动画
        await controller.forward();
       
        // 等待一小段时间让用户看清 logo
        await Future.delayed(const Duration(milliseconds: 1000));
       
        // 退出应用
        FlutterExitApp.exitApp();  // 直接调用插件退出应用
       
      } catch (e) {
        LogUtil.e('退出应用错误: $e');  // 记录日志
      }
    }
    return exitConfirmed ?? false;  // 返回非空的 bool 值，如果为空则返回 false
  }
}
