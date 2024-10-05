import 'package:flutter/material.dart';
import 'dart:math' as math;

class CustomSnackBar {
  static void showSnackBar(BuildContext context, String message, {Duration? duration}) {
    final double maxWidth = MediaQuery.of(context).size.width * 0.8; // 计算屏幕宽度的80%
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,  // 背景设置为透明，以便显示渐变背景
        behavior: SnackBarBehavior.floating,  // 使SnackBar悬浮
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),  // 四个角的圆角
        ),
        duration: duration ?? const Duration(seconds: 4),  // 默认持续4秒
        padding: EdgeInsets.zero,  // 去掉内边距
        elevation: 0,  // 去掉阴影
        content: Container(
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
            borderRadius: BorderRadius.circular(20),  // 圆角边框
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,  // 阴影颜色
                offset: Offset(0, 4),  // 阴影位置 (x, y)
                blurRadius: 8,  // 模糊半径
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),  // 内容内边距
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  message,  // 动态消息
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,  // 字体大小
                  ),
                  textAlign: TextAlign.center,  // 文本内容水平居中
                  maxLines: null,  // 允许多行显示
                  softWrap: true,  // 自动换行
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
