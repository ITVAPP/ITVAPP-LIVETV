import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart'; // 导入日志工具

class SettingBeautifyPage extends StatefulWidget {
  const SettingBeautifyPage({super.key});

  @override
  _SettingBeautifyPageState createState() => _SettingBeautifyPageState();
}

class _SettingBeautifyPageState extends State<SettingBeautifyPage> {
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
          alignment: Alignment.center, // 内容居中显示
          child: Container(
            constraints: BoxConstraints(
              maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), // 增加内边距
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0), // 添加垂直间距
                    child: SwitchListTile(
                      title: const Text(
                        '每日Bing',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ), // 设置标题加粗
                      subtitle: const Text('未播放时的屏幕背景，每日更换图片'), // 提示信息
                      value: context.watch<ThemeProvider>().isBingBg, // 读取 Bing 背景状态
                      onChanged: (value) {
                        LogUtil.safeExecute(() {
                          context.read<ThemeProvider>().setBingBg(value); // 设置 Bing 背景状态
                          LogUtil.i('每日Bing背景设置为: ${value ? "启用" : "禁用"}');
                        }, '设置每日Bing背景时发生错误');
                      },
                      activeColor: Colors.white, // 启用时滑块颜色
                      activeTrackColor: const Color(0xFFEB144C), // 启用时轨道颜色
                      inactiveThumbColor: Colors.white, // 关闭时滑块颜色
                      inactiveTrackColor: Colors.grey, // 关闭时轨道颜色
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      LogUtil.logError('构建 SettingBeautifyPage 时发生错误', e, stackTrace);
      return Scaffold(
        body: const Center(
          child: Text('加载页面时出错'), // 错误页面提示
        ),
      );
    }
  }
}
