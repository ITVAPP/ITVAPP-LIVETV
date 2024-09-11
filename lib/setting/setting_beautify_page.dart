import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; // 导入日志工具

class SettingBeautifyPage extends StatelessWidget {
  const SettingBeautifyPage({super.key});
  
  @override
  Widget build(BuildContext context) {
    try {
      // 获取当前屏幕的宽度
      var screenWidth = MediaQuery.of(context).size.width;
      LogUtil.d('屏幕宽度: $screenWidth');

      // 通过 Provider 获取 isTV 的状态
      bool isTV = context.watch<ThemeProvider>().isTV;
      LogUtil.d('当前设备模式: ${isTV ? "TV" : "非TV"}');

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
                // 自定义切换每日 Bing 背景图片的设置项
                ListTile(
                  title: const Text('每日Bing'), // 选项标题
                  subtitle: const Text('未播放时的屏幕背景，每日更换图片'), // 选项的说明文字
                  trailing: Transform.scale(
                    scale: 1.2, // 调整开关大小
                    child: Switch(
                      value: context.watch<ThemeProvider>().isBingBg, // 获取当前 Bing 背景设置的状态
                      onChanged: (value) {
                        safeExecute(() {
                          context.read<ThemeProvider>().setBingBg(value); // 直接调用同步存储的方法
                          LogUtil.i('每日Bing背景设置为: ${value ? "启用" : "禁用"}');
                        }, '设置每日Bing背景时发生错误');
                      },
                      activeColor: Colors.white, // 滑块的颜色
                      activeTrackColor: const Color(0xFFEB144C), // 开启时轨道的背景颜色
                      inactiveThumbColor: Colors.white, // 关闭时滑块的颜色
                      inactiveTrackColor: Colors.grey, // 关闭时轨道的背景颜色
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      logError('构建 SettingBeautifyPage 时发生错误', e, stackTrace);
      return Scaffold(
        body: Center(child: Text('加载页面时出错')),
      );
    }
  }
}