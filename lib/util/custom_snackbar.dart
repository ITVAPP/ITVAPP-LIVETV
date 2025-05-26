import 'package:flutter/material.dart';

// 自定义SnackBar类，用于显示带渐变背景和阴影的提示框
class CustomSnackBar {
  // 定义静态颜色常量，便于样式统一和维护
  static const Color _gradientColor1 = Color(0xff6D6875);  // 渐变起始颜色
  static const Color _gradientColor2 = Color(0xffB4838D);  // 渐变中间颜色
  static const Color _gradientColor3 = Color(0xffE5989B);  // 渐变结束颜色
  static const Color _shadowColor = Colors.black26;  // 阴影颜色
  
  // 显示自定义SnackBar，展示带渐变和阴影的提示信息
  // [message] 显示的消息文本
  // [duration] 显示持续时间，默认4秒
  static void showSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),  // 默认显示4秒
  }) {
    final overlay = Overlay.of(context);  // 获取Overlay实例
    if (overlay == null) {  // 检查Overlay是否可用
      debugPrint('Overlay不可用，无法显示SnackBar');  // 输出调试信息
      return;  // 不可用时直接返回
    }

    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,  // 动态调整底部位置，避免键盘遮挡
        left: 0,  // 左边界为0，确保水平居中
        right: 0,  // 右边界为0，确保水平居中
        child: Center(  // 居中显示SnackBar内容
          child: Material(
            color: Colors.transparent,  // 设置透明背景以突出自定义样式
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,  // 限制宽度为屏幕的80%
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    _gradientColor1,  // 渐变色1
                    _gradientColor2,  // 渐变色2
                    _gradientColor3,  // 渐变色3
                  ],
                ),
                borderRadius: BorderRadius.circular(18),  // 设置圆角
                boxShadow: const [
                  BoxShadow(
                    color: _shadowColor,  // 应用阴影颜色
                    offset: Offset(0, 4),  // 阴影向下偏移4像素
                    blurRadius: 8,  // 阴影模糊半径为8
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),  // 设置内边距
              child: Row(
                mainAxisSize: MainAxisSize.min,  // Row宽度自适应内容
                mainAxisAlignment: MainAxisAlignment.center,  // 内容水平居中
                children: [
                  Flexible(
                    child: Text(
                      message,  // 显示传入的消息文本
                      style: const TextStyle(
                        color: Colors.white,  // 文本颜色为白色
                        fontSize: 18,  // 字体大小18像素
                        fontWeight: FontWeight.w500,  // 字体粗细中等
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),  // 文本阴影向下偏移1像素
                            blurRadius: 3,  // 阴影模糊半径为3
                            color: Colors.black45,  // 阴影颜色为半透明黑色
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,  // 文本居中对齐
                      maxLines: null,  // 支持多行显示
                      softWrap: true,  // 启用自动换行
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);  // 将SnackBar插入Overlay
    Future.delayed(duration, () {  // 设置定时器移除SnackBar
      overlayEntry.remove();  // 到时间后移除OverlayEntry
    });
  }
}
