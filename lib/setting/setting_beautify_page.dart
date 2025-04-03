import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 背景设置页面主类，继承自 StatefulWidget，用于动态状态管理
class SettingBeautifyPage extends StatefulWidget {
  const SettingBeautifyPage({super.key});

  @override
  _SettingBeautifyPageState createState() => _SettingBeautifyPageState(); // 创建并返回状态类实例
}

// 美化设置页面的状态类，负责页面逻辑和 UI 更新
class _SettingBeautifyPageState extends State<SettingBeautifyPage> {
  // 定义常量样式，避免分散定义并提升复用性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // AppBar 标题样式
  static const _switchTitleStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold); // 开关标题样式
  static const _switchSubtitleStyle = TextStyle(fontSize: 18); // 开关副标题样式

  // 定义颜色常量，避免重复定义并便于维护
  static const Color selectedColor = Color(0xFFEB144C); // 选中时的背景颜色
  static const Color unselectedColor = Color(0xFFDFA02A); // 未选中时的背景颜色
  static const Color tvBackgroundColor = Color(0xFF1E2022); // TV 模式背景颜色
  final List<FocusNode> _focusNodes = List.generate(1, (index) => FocusNode());
  bool _isFocusUpdating = false; // 防止焦点监听重复触发 setState
  late Map<String, Color> _trackColorCache; // 缓存轨道颜色计算结果

  @override
  void initState() {
    super.initState();
    // 初始化轨道颜色缓存
    _trackColorCache = {
      'focused_active': selectedColor,
      'focused_inactive': selectedColor,
      'unfocused_active': unselectedColor,
      'unfocused_inactive': Colors.grey,
    };
    // 为焦点节点添加监听器，优化刷新逻辑
    for (var focusNode in _focusNodes) {
      focusNode.addListener(() {
        if (mounted && !_isFocusUpdating) {
          _isFocusUpdating = true; // 标记正在更新
          setState(() {}); // 仅在挂载时更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isFocusUpdating = false; // 重置标记
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNodes.forEach((node) => node.dispose()); // 清理焦点节点，防止内存泄漏
    super.dispose();
  }

  // 使用缓存获取轨道颜色，避免重复计算
  Color _getTrackColor(bool hasFocus, bool isActive) {
    final key = '${hasFocus ? 'focused' : 'unfocused'}_${isActive ? 'active' : 'inactive'}';
    return _trackColorCache[key]!;
  }

  // 抽取错误页面为独立方法，减少冗余代码
  Widget _buildErrorPage(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(S.of(context).errorLoadingPage), // 显示错误提示页面
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度并直接计算最大宽度约束，避免重复调用
    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxContainerWidth = 580;
    final double containerWidth = screenWidth < maxContainerWidth ? screenWidth : maxContainerWidth;

    // 获取 ThemeProvider 实例，减少重复调用
    late ThemeProvider themeProvider;
    bool isTV;
    try {
      themeProvider = context.watch<ThemeProvider>(); // 一次性获取并缓存
      isTV = themeProvider.isTV; // 动态监听 TV 状态
    } on ProviderNotFoundException catch (e, stackTrace) {
      LogUtil.logError('未找到 ThemeProvider', e, stackTrace);
      return _buildErrorPage(context); // 使用复用错误页面
    } catch (e, stackTrace) {
      LogUtil.logError('获取 ThemeProvider 的 isTV 状态时发生未知错误', e, stackTrace);
      return _buildErrorPage(context); // 使用复用错误页面
    }

    // 构建页面主体，适配 TV 和非 TV 模式
    return Scaffold(
      backgroundColor: isTV ? tvBackgroundColor : null, // TV 模式下设置深色背景
      appBar: AppBar(
        title: Text(
          S.of(context).backgroundImageTitle, // 显示“背景图片”标题，随语言更新
          style: _titleStyle, // 应用预定义标题样式
        ),
        backgroundColor: isTV ? tvBackgroundColor : null, // TV 模式下设置 AppBar 颜色
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
                maxWidth: containerWidth, // 使用计算后的宽度限制
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
                                style: _switchTitleStyle, // 应用统一标题样式
                              ),
                              subtitle: Text(
                                S.of(context).backgroundImageDescription, // 背景图片描述
                                style: _switchSubtitleStyle, // 应用统一副标题样式
                              ),
                              value: themeProvider.isBingBg, // 使用缓存的 themeProvider 获取状态
                              onChanged: (value) async {
                                LogUtil.safeExecute(() async {
                                  await themeProvider.setBingBg(value); // 异步更新状态
                                }, '设置每日Bing背景时发生错误');
                              },
                              activeColor: Colors.white, // 激活时滑块颜色
                              activeTrackColor: _getTrackColor(_focusNodes[0].hasFocus, true), // 使用缓存颜色
                              inactiveThumbColor: Colors.white, // 未激活时滑块颜色
                              inactiveTrackColor: _getTrackColor(_focusNodes[0].hasFocus, false), // 使用缓存颜色
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
