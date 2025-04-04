import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// SelectionState 类用于管理焦点和选中状态
class SelectionState {
  final int focusedIndex; // 当前聚焦的按钮索引
  final bool isSelected; // 当前开关的选中状态

  SelectionState(this.focusedIndex, this.isSelected);
}

// 背景设置页面主类，管理美化设置的动态状态
class SettingBeautifyPage extends StatefulWidget {
  const SettingBeautifyPage({super.key});

  @override
  _SettingBeautifyPageState createState() => _SettingBeautifyPageState(); // 创建状态实例
}

// 美化设置页面的状态类，处理逻辑和界面更新
class _SettingBeautifyPageState extends State<SettingBeautifyPage> {
  // 定义常量样式，提升代码复用性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // AppBar标题样式
  static const _switchTitleStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold); // 开关标题样式
  static const _switchSubtitleStyle = TextStyle(fontSize: 18); // 开关副标题样式

  // 定义颜色常量，便于维护
  static const Color selectedColor = Color(0xFFEB144C); // 选中时的背景色（红色）
  static const Color unselectedColor = Color(0xFFDFA02A); // 未选中时的背景色（黄色）
  static const Color tvBackgroundColor = Color(0xFF1E2022); // TV模式背景色
  late final List<FocusNode> _focusNodes; // 焦点节点列表，初始化后不可变
  late SelectionState _switchState; // 当前焦点和开关状态
  late Map<String, Color> _trackColorCache; // 缓存轨道颜色，优化性能

  // 防抖定时器和方法，减少频繁状态更新
  Timer? _debounceTimer;
  void _debounceSetState() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() {}); // 延迟刷新UI
    });
  }

  @override
  void initState() {
    super.initState();
    // 初始化焦点节点并绑定监听器
    _focusNodes = List.generate(1, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 添加焦点变化监听
      return node;
    });
    _switchState = SelectionState(-1, context.read<ThemeProvider>().isBingBg); // 初始化状态
    // 初始化轨道颜色缓存
    _trackColorCache = {
      'focused_active': selectedColor,
      'focused_inactive': selectedColor,
      'unfocused_active': unselectedColor,
      'unfocused_inactive': Colors.grey,
    };
  }

  // 处理焦点变化，更新状态
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    final themeProvider = context.read<ThemeProvider>();
    _switchState = SelectionState(focusedIndex, themeProvider.isBingBg); // 更新焦点和开关状态
    _debounceSetState(); // 使用防抖更新UI
  }

  @override
  void dispose() {
    _debounceTimer?.cancel(); // 清理防抖定时器
    for (var focusNode in _focusNodes) {
      focusNode.removeListener(_handleFocusChange); // 移除焦点监听
      focusNode.dispose(); // 释放焦点节点
    }
    super.dispose();
  }

  // 获取轨道颜色，使用缓存避免重复计算
  Color _getTrackColor(bool hasFocus, bool isActive) {
    final key = '${hasFocus ? 'focused' : 'unfocused'}_${isActive ? 'active' : 'inactive'}';
    return _trackColorCache[key]!;
  }

  // 构建错误页面，复用错误提示逻辑
  Widget _buildErrorPage(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(S.of(context).errorLoadingPage), // 显示加载错误提示
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 计算容器宽度，优化性能
    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxContainerWidth = 580;
    final double containerWidth = screenWidth < maxContainerWidth ? screenWidth : maxContainerWidth;

    // 获取ThemeProvider并处理异常
    late ThemeProvider themeProvider;
    bool isTV;
    try {
      themeProvider = context.watch<ThemeProvider>(); // 获取主题提供者
      isTV = themeProvider.isTV; // 判断是否为TV模式
    } on ProviderNotFoundException catch (e, stackTrace) {
      LogUtil.logError('未找到 ThemeProvider', e, stackTrace); // 记录Provider未找到错误
      return _buildErrorPage(context);
    } catch (e, stackTrace) {
      LogUtil.logError('获取 ThemeProvider 的 isTV 状态时发生未知错误', e, stackTrace); // 记录未知错误
      return _buildErrorPage(context);
    }

    // 构建页面主体
    return Scaffold(
      backgroundColor: isTV ? tvBackgroundColor : null, // TV模式设置背景色
      appBar: AppBar(
        title: Text(
          S.of(context).backgroundImageTitle, // 显示“背景图片”标题
          style: _titleStyle, // 应用标题样式
        ),
        backgroundColor: isTV ? tvBackgroundColor : null, // TV模式设置AppBar颜色
        leading: isTV ? const SizedBox.shrink() : null, // TV模式隐藏返回按钮
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 绑定焦点节点
          isHorizontalGroup: true, // 启用横向分组导航
          initialIndex: 0, // 初始焦点索引
          isFrame: isTV ? true : false, // TV模式启用框架导航
          frameType: isTV ? "child" : null, // TV模式标记为子页面
          child: Align(
            alignment: Alignment.center, // 内容居中对齐
            child: Container(
              constraints: BoxConstraints(
                maxWidth: containerWidth, // 限制容器最大宽度
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 设置内边距
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 子组件左对齐
                  children: [
                    Group(
                      groupIndex: 0, // 开关分组索引
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0), // 开关垂直间距
                          child: FocusableItem(
                            focusNode: _focusNodes[0], // 绑定焦点节点
                            child: SwitchListTile(
                              title: Text(
                                S.of(context).dailyBing, // “每日 Bing”标题
                                style: _switchTitleStyle, // 应用开关标题样式
                              ),
                              subtitle: Text(
                                S.of(context).backgroundImageDescription, // 背景图片描述
                                style: _switchSubtitleStyle, // 应用副标题样式
                              ),
                              value: themeProvider.isBingBg, // 当前开关状态
                              onChanged: (value) async {
                                LogUtil.safeExecute(() async {
                                  await themeProvider.setBingBg(value); // 异步更新背景设置
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
