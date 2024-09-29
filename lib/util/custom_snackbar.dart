import 'package:flutter/material.dart';

class CustomSnackBar {
  // 创建一个静态方法，允许传入自定义的内容和持续时间
  static void showSnackBar(BuildContext context, String message, {Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,  // 背景设置为透明，以便显示渐变背景
        behavior: SnackBarBehavior.floating,  // 浮动的 SnackBar
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),  // 四个角的圆角
        ),
        margin: EdgeInsets.only(
          left: MediaQuery.of(context).size.width * 0.06,  // 左右边距占屏幕 6%
          right: MediaQuery.of(context).size.width * 0.06,
          bottom: 30,  // 距离底部 30px
        ),
        duration: duration ?? Duration(seconds: 4),  // 使用传入的持续时间，默认为 4 秒
        padding: EdgeInsets.zero,  // 去掉 SnackBar 的内边距，使渐变色更平滑
        elevation: 0,  // 去掉阴影
        content: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xff6D6875),  // 渐变颜色1
                Color(0xffB4838D),  // 渐变颜色2
                Color(0xffE5989B),  // 渐变颜色3
              ],
            ),
            borderRadius: BorderRadius.circular(20),  // 圆角边框
            boxShadow: [
              BoxShadow(
                color: Colors.black26,  // 阴影颜色
                offset: Offset(0, 4),   // 阴影位置 (x, y)
                blurRadius: 8,          // 模糊半径
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),  // 设置内容区域的内边距
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,  // 垂直居中对齐
            mainAxisAlignment: MainAxisAlignment.center,  // 水平居中对齐
            children: [
              Icon(Icons.notifications, color: Colors.white),  // 🔔 图标，白色
              SizedBox(width: 10),  // 图标与文字的间距
              Flexible(
                child: Text(
                  message,  // 动态消息
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: 16,  // 字体大小
                    fontWeight: FontWeight.bold,  // 加粗
                  ),
                  maxLines: null,  // 允许多行显示
                  softWrap: true,  // 自动换行
                  overflow: TextOverflow.visible,  // 处理溢出
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
