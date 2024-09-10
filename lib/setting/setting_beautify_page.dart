import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingBeautifyPage extends StatelessWidget {
  const SettingBeautifyPage({super.key});
  @override
  Widget build(BuildContext context) {
    // 获取当前屏幕的宽度
    var screenWidth = MediaQuery.of(context).size.width;

    // 通过 Provider 获取 isTV 的状态
    bool isTV = context.watch<ThemeProvider>().isTV;

    // 设置最大容器宽度为 580，适用于大屏幕设备
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // 在 TV 模式下设置背景颜色
      appBar: AppBar(
        title: const Text('美化'), // AppBar 标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV 模式下设置 AppBar 颜色
        leading: isTV ? const SizedBox.shrink() : null, // 如果是 TV 模式，隐藏返回按钮
      ),
      body: Align(
        alignment: Alignment.center, // 将内容居中
        child: Container(
          constraints: BoxConstraints(
            // 如果屏幕宽度超过 580，则设置最大宽度为 580；否则为屏幕的全部宽度
            maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity,
          ),
          alignment: Alignment.center,
          child: ListView(
            children: [
              // 切换每日 Bing 背景图片的设置项
              SwitchListTile(
                title: const Text('每日Bing'), // 选项标题
                value: context.watch<ThemeProvider>().isBingBg, // 获取当前 Bing 背景设置的状态
                subtitle: const Text('未播放时的屏幕背景，每日更换图片'), // 选项的说明文字
                onChanged: (value) async {
                  // 这里我们增加了 `await` 来等待状态更新完成
                  // 并且使用 `async` 方式确保异步操作的安全性
                  
                  await context.read<ThemeProvider>().setBingBg(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
