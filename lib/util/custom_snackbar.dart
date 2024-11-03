import 'package:flutter/material.dart';
import 'dart:math' as math;
class CustomSnackBar {
  static void showSnackBar(BuildContext context, String message, {Duration? duration}) {
    // final double maxWidth = MediaQuery.of(context).size.width * 0.8; // 计算屏幕宽度的80%
    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,  // 避免与底部重叠
        left: 0,  // 确保左右都设置为0，避免固定位置
        right: 0,  // 右侧也设置为0，使SnackBar居中
        child: Center(  // 使用Center替代FractionallySizedBox
          child: Material(
            color: Colors.transparent,  // 设置透明背景以允许自定义样式
            child: Container(
              constraints: BoxConstraints(  // 添加约束，确保不会太宽
                maxWidth: MediaQuery.of(context).size.width * 0.8,
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
                mainAxisSize: MainAxisSize.min,  // 让Row根据内容自适应宽度
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      message,  // 显示传入的消息
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,  // 字体大小
                        fontWeight: FontWeight.w500,  // 加粗字体
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),  // 阴影偏移
                            blurRadius: 3,  // 阴影模糊半径
                            color: Colors.black45,  // 阴影颜色
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,  // 文本居中
                      maxLines: null,  // 允许多行
                      softWrap: true,  // 自动换行
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context)?.insert(overlayEntry);
    // 设置自动关闭，模拟 SnackBar 的行为
    Future.delayed(duration ?? const Duration(seconds: 4), () {
      overlayEntry.remove();  // 移除 OverlayEntry
    });
  }
}
