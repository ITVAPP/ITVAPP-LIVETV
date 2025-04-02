import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 用于显示空白页或错误提示页面
class EmptyPage extends StatelessWidget {
  // 点击刷新按钮的回调函数，可能为 null
  final GestureTapCallback? onRefresh;

  // 构造函数，要求传入刷新回调函数
  const EmptyPage({super.key, this.onRefresh});

  // 按钮样式常量，提升复用性
  static final ButtonStyle _refreshButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.redAccent, // 按钮背景颜色为红色
  );

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
          // 显示警告图标
          const Text(
            '⚠️',
            style: TextStyle(fontSize: 38), // 设置字体大小
          ),
          // 显示本地化的错误提示信息
          Text(
            S.of(context).filterError,
            textAlign: TextAlign.center, // 文本居中显示
            style: const TextStyle(fontSize: 20, color: Colors.white), // 设置文本样式
          ),
          // 刷新按钮，点击时执行 onRefresh 回调
          ElevatedButton(
            style: _refreshButtonStyle, // 使用定义好的按钮样式
            onPressed: onRefresh ?? () {}, // 若 onRefresh 为 null，则禁用点击
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0), // 使用 Padding 替代空格
              child: Text(
                // 根据设备类型选择不同的本地化文本
                isTV ? S.of(context).okRefresh : S.of(context).refresh,
                style: const TextStyle(color: Colors.white), // 设置按钮文本颜色为白色
              ),
            ),
          ),
        ],
      ),
    );
  }
}
