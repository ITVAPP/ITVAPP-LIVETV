import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';

// 用于显示空白页或错误提示页面
class EmptyPage extends StatelessWidget {
  // 点击刷新按钮的回调函数
  final GestureTapCallback onRefresh;

  // 构造函数，要求传入刷新回调函数
  const EmptyPage({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // 通过 Provider 获取 ThemeProvider 中的 isTV 状态，判断是否为 TV 设备
    bool isTV = context.watch<ThemeProvider>().isTV;

    return Center(
      // 使用 Column 布局，内容垂直居中排列
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // 子组件水平居中
        mainAxisAlignment: MainAxisAlignment.center, // 子组件垂直居中
        mainAxisSize: MainAxisSize.min, // 最小化占用空间
        children: [
          const Text(
            '⚠️', 
            style: TextStyle(fontSize: 38), // 设置字体大小
          ),
          // 显示错误信息
          Text(
            S.of(context).filterError,
            textAlign: TextAlign.center, // 文本居中显示
            style: TextStyle(fontSize: 20, color: Colors.white), // 设置文本样式
          ),
          // 定义一个带有样式的按钮，点击按钮时执行传入的 onRefresh 函数
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent, // 按钮背景颜色为红色
            ),
            onPressed: onRefresh, // 点击时执行 onRefresh 回调
            child: Text(
              // 根据是否为 TV 设备，显示不同的按钮文本
              '      ${isTV ? S.of(context).okRefresh : S.of(context).refresh}      ',
              style: const TextStyle(color: Colors.white), // 设置按钮文本颜色为白色
            ),
          ),
        ],
      ),
    );
  }
}
