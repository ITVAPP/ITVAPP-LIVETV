import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class SettingBeautifyPage extends StatefulWidget {
  const SettingBeautifyPage({super.key});

  @override
  _SettingBeautifyPageState createState() => _SettingBeautifyPageState();
}

class _SettingBeautifyPageState extends State<SettingBeautifyPage> {
  final Color selectedColor = const Color(0xFFEB144C); // 选中时背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时背景颜色

  // 设置焦点节点
  final List<FocusNode> _focusNodes = List.generate(1, (index) => FocusNode());
  
  @override
  void initState() {
    super.initState();
    // 监听焦点变化，焦点变化时触发重绘
    for (var focusNode in _focusNodes) {
      focusNode.addListener(() {
        setState(() {}); // 焦点变化时触发setState来重绘UI
      });
    }
  }
  
  @override
  void dispose() {
    // 释放焦点资源
    _focusNodes.forEach((node) => node.dispose()); // 释放所有焦点节点
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

      // 使用 Scaffold 包裹，并在 body 内使用 FocusScope 包裹 TvKeyNavigation
      return Scaffold(
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV 模式下设置背景颜色
        appBar: AppBar(
          title: Text(
            S.of(context).backgroundImageTitle, // AppBar 标题
            style: const TextStyle(
              fontSize: 22, // 设置字号
              fontWeight: FontWeight.bold, // 设置加粗
            ),
          ),
          backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV 模式下设置 AppBar 颜色
          leading: isTV ? const SizedBox.shrink() : null, // 如果是 TV 模式，隐藏返回按钮
        ),
        body: FocusScope(
          child: TvKeyNavigation(
            focusNodes: _focusNodes, // 传入焦点节点列表
            isHorizontalGroup: true, // 启用横向分组
            initialIndex: 0, // 设置初始焦点索引为 0
            isFrame: isTV ? true : false, // TV 模式下启用框架模式
            frameType: isTV ? "child" : null, // TV 模式下设置为子页面
            child: Align(
              alignment: Alignment.center, // 内容居中显示
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 增加内边距
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // 子组件从左对齐
                    children: [
                      Group( // 使用 Group 包裹分组 0
                        groupIndex: 0, // 分组索引
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10.0), // 添加垂直间距
                            child: FocusableItem( // 使用 FocusableItem 包裹焦点节点
                              focusNode: _focusNodes[0], // 将焦点节点绑定到该组件
                              child: SwitchListTile(
                                title: Text(
                                  S.of(context).dailyBing, 
                                  style: TextStyle(
                                    fontSize: 18, // 设置字体大小为 18
                                    fontWeight: FontWeight.bold, // 设置加粗
                                  ),
                                ),
                                subtitle: Text(
                                  S.of(context).backgroundImageDescription, // 提示信息
                                  style: TextStyle(fontSize: 18), // 设置字体大小
                                ),
                                value: context.watch<ThemeProvider>().isBingBg, // 读取 Bing 背景状态
                                onChanged: (value) {
                                  LogUtil.safeExecute(() {
                                    context.read<ThemeProvider>().setBingBg(value); // 设置 Bing 背景状态
                                  }, '设置每日Bing背景时发生错误');
                                },
                                activeColor: Colors.white, // 滑块的颜色
                                activeTrackColor: _focusNodes[0].hasFocus
                                   ? selectedColor // 聚焦时颜色变暗
                                   : selectedColor, // 启动时背景颜色
                                inactiveThumbColor: Colors.white, // 关闭时滑块的颜色
                                inactiveTrackColor: Colors.grey, // 关闭时轨道的背景颜色
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
