import 'package:flutter/material.dart';
import 'dart:math' as math;

class CustomSnackBar {
  static void showSnackBar(BuildContext context, String message, {Duration? duration}) {
    final double maxWidth = MediaQuery.of(context).size.width * 0.8; // 计算屏幕宽度的80%

    // 使用 BottomSheet 代替 SnackBar
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,  // 根据内容自动控制
      backgroundColor: Colors.transparent,  // 设置为透明，方便自定义背景
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,  // 避免与底部重叠
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxWidth,  // 限制最大宽度为屏幕宽度的80%
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xff6D6875),  // 渐变颜色1
                  Color(0xffB4838D),  // 渐变颜色2
                  Color(0xffE5989B),  // 渐变颜色3
                ],
              ),
              borderRadius: BorderRadius.circular(20),  // 设置圆角
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,  // 阴影颜色
                  offset: Offset(0, 4),  // 阴影偏移
                  blurRadius: 8,  // 模糊半径
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),  // 设置内边距
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    message,  // 显示传入的消息
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,  // 字体大小
                    ),
                    textAlign: TextAlign.center,  // 文本居中
                    maxLines: null,  // 允许多行
                    softWrap: true,  // 自动换行
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    // 设置自动关闭，模拟 SnackBar 的行为
    Future.delayed(duration ?? const Duration(seconds: 4), () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();  // 关闭 BottomSheet
      }
    });
  }
}
