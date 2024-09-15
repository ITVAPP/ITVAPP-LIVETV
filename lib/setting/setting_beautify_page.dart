import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import '../generated/l10n.dart';

class SettingBeautifyPage extends StatefulWidget {
  const SettingBeautifyPage({super.key});

  @override
  _SettingBeautifyPageState createState() => _SettingBeautifyPageState();
}

class _SettingBeautifyPageState extends State<SettingBeautifyPage> {
  // 焦点节点，用于TV端焦点管理
  final FocusNode _bingFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 页面加载时，将焦点默认设置到第一个可用组件
    _bingFocusNode.requestFocus();
  }

  @override
  void dispose() {
    // 释放焦点资源
    _bingFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      // 获取当前屏幕的宽度
      var screenWidth = MediaQuery.of(context).size.width;

      // 通过 Provider 获取 isTV 的状态
      bool isTV = context.watch<ThemeProvider>().isTV;

      // 设置最大容器宽度为 580，适用于大屏幕设备
      double maxContainerWidth = 580;

      return Scaffold(
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // 在 TV 模式下设置背景颜色
        appBar: AppBar(
          title: Text(S.of(context).backgroundImageTitle),  // AppBar 标题
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
              child: FocusTraversalGroup( // 在 TV 模式下使用焦点组管理方向键切换
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 子组件从左对齐
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0), // 添加垂直间距
                      child: SwitchListTile(
                        focusNode: _bingFocusNode, // 将焦点节点绑定到该组件
                        title: Text(
                          Text(S.of(context).dailyBing),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ), // 设置标题加粗
                        subtitle: Text(S.of(context).backgroundImageDescription),  // 提示信息
                        value: context.watch<ThemeProvider>().isBingBg, // 读取 Bing 背景状态
                        onChanged: (value) {
                          LogUtil.safeExecute(() {
                            context.read<ThemeProvider>().setBingBg(value); // 设置 Bing 背景状态
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
        ),
      );
    } catch (e, stackTrace) {
      LogUtil.logError('构建 SettingBeautifyPage 时发生错误', e, stackTrace);
      return Scaffold(
        body: Center(
          child: Text(S.of(context).errorLoadingPage), // 错误页面提示
        ),
      );
    }
  }
}
