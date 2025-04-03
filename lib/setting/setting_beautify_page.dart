import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

// 美化设置页面主类，继承自 StatefulWidget，用于动态状态管理
class SettingBeautifyPage extends StatefulWidget {
  const SettingBeautifyPage({super.key});

  @override
  _SettingBeautifyPageState createState() => _SettingBeautifyPageState(); // 创建并返回状态类实例
}

// 美化设置页面的状态类，负责页面逻辑和 UI 更新
class _SettingBeautifyPageState extends State<SettingBeautifyPage> {
  // 定义静态常量标题样式，避免重复创建以提升性能
  static const _titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  final Color selectedColor = const Color(0xFFEB144C); // 选中时的背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时的背景颜色

  // 初始化焦点节点列表，目前仅一个焦点，后续可扩展
  final List<FocusNode> _focusNodes = List.generate(1, (index) => FocusNode());
  
  @override
  void initState() {
    super.initState();
    for (var focusNode in _focusNodes) {
      focusNode.addListener(() {
        // 监听焦点变化，仅在挂载时更新状态
        if (mounted) {
          setState(() {});
        }
      });
    }
  }
  
  @override
  void dispose() {
    _focusNodes.forEach((node) => node.dispose()); // 清理焦点节点，防止内存泄漏
    super.dispose();
  }

  // 计算 SwitchListTile 轨道颜色，根据焦点和激活状态动态调整
  Color _getTrackColor(bool hasFocus, bool isActive) {
    if (isActive) {
      return hasFocus ? selectedColor : unselectedColor; // 激活时区分焦点状态
    } else {
      return hasFocus ? selectedColor : Colors.grey; // 未激活时区分焦点状态
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度，用于布局适配
    var screenWidth = MediaQuery.of(context).size.width;

    // 获取是否为 TV 模式，包含异常处理
    bool isTV;
    try {
      isTV = context.watch<ThemeProvider>().isTV; // 动态监听 TV 状态
    } catch (e, stackTrace) {
      LogUtil.logError('获取 ThemeProvider 的 isTV 状态时发生错误', e, stackTrace);
      return Scaffold(
        body: Center(
          child: Text(S.of(context).errorLoadingPage), // 显示错误提示页面
        ),
      );
    }

    // 设置最大容器宽度为 580，适配大屏幕
    const double maxContainerWidth = 580;

    // 构建页面主体，适配 TV 和非 TV 模式
    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV 模式下设置深色背景
      appBar: AppBar(
        title: Text(
          S.of(context).backgroundImageTitle, // 显示“背景图片”标题，随语言更新
          style: _titleStyle, // 应用预定义标题样式
        ),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV 模式下设置 AppBar 颜色
        leading: isTV ? const SizedBox.shrink() : null, // TV 模式隐藏返回按钮
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 提供焦点节点列表给导航组件
          isHorizontalGroup: true, // 启用横向焦点分组
          initialIndex: 0, // 设置初始焦点为第一个选项
          isFrame: isTV ? true : false, // TV 模式启用框架导航
          frameType: isTV ? "child" : null, // TV 模式下标记为子页面
          child: Align(
            alignment: Alignment.center, // 内容居中对齐
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth < maxContainerWidth ? screenWidth : maxContainerWidth, // 限制最大宽度
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 设置内边距
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 子组件左对齐
                  children: [
                    Group( // 分组 0，包含背景设置选项
                      groupIndex: 0, // 分组索引，用于焦点管理
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0), // 选项垂直间距
                          child: FocusableItem( // 可聚焦项，绑定焦点节点
                            focusNode: _focusNodes[0], // 使用第一个焦点节点
                            child: SwitchListTile(
                              title: Text(
                                S.of(context).dailyBing, // “每日 Bing”标题
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                S.of(context).backgroundImageDescription, // 背景图片描述
                                style: const TextStyle(fontSize: 18),
                              ),
                              value: context.watch<ThemeProvider>().isBingBg, // 当前 Bing 背景状态
                              onChanged: (value) {
                                LogUtil.safeExecute(() {
                                  context.read<ThemeProvider>().setBingBg(value); // 更新 Bing 背景设置
                                }, '设置每日Bing背景时发生错误');
                              },
                              activeColor: Colors.white, // 激活时滑块颜色
                              activeTrackColor: _getTrackColor(_focusNodes[0].hasFocus, true), // 激活时轨道颜色
                              inactiveThumbColor: Colors.white, // 未激活时滑块颜色
                              inactiveTrackColor: _getTrackColor(_focusNodes[0].hasFocus, false), // 未激活时轨道颜色
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
  }
}
