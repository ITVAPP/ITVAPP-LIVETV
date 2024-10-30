import 'dart:io'; // 导入dart:io以使用exit
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
        bool isTV = context.watch<ThemeProvider>().isTV; // 判断是否为 TV
        if (isTV) {
          exit(0);  // 在 TV 上退出
        } else {
          SystemNavigator.pop();  // 非 TV 设备使用 SystemNavigator.pop()
        }
      } catch (e) {
        LogUtil.e('退出应用错误: $e');  // 记录日志
      }
      return true;  // 返回 true 表示退出
    } else {
      return false;  // 返回 false 表示不退出
    }
  }
}
