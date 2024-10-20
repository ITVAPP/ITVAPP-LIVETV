import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class SettingFontPage extends StatefulWidget {
  const SettingFontPage({super.key});

  @override
  State<SettingFontPage> createState() => _SettingFontPageState();
}

class _SettingFontPageState extends State<SettingFontPage> {
  final _fontScales = [0.8, 0.9, 1.0, 1.1, 1.2]; // 字体缩放比例
  final _languages = ['English', '简体中文', '正體中文']; // 语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 语言代码

  // 提取统一的按钮样式
  RoundedRectangleBorder get _buttonShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), // 设置圆角
      );

  // 定义选中和未选中的颜色
  static const _selectedColor = Color(0xFFEB144C); // 选中时颜色
  static const _unselectedColor = Color(0xFFDFA02A); // 未选中时颜色

  // 焦点节点列表（按顺序分配给字体和语言选择按钮）
  final List<FocusNode> _focusNodes = List.generate(8, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    // 监听所有焦点节点的变化，焦点变化时触发 UI 更新
    for (var focusNode in _focusNodes) {
      focusNode.addListener(() {
        if (mounted) setState(() {}); // 确保组件已挂载后再触发重绘
      });
    }
  }

  @override
  void dispose() {
    for (var node in _focusNodes) node.dispose(); // 释放所有焦点节点资源
    super.dispose();
  }

  /// 用于将颜色变暗的函数
  Color darkenColor(Color color, [double amount = 0.1]) {
    final hsl = HSLColor.fromColor(color);
    final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }

  @override
  Widget build(BuildContext context) {
    // 缓存 ThemeProvider 和 LanguageProvider，减少重复调用 context.watch()
    final themeProvider = context.watch<ThemeProvider>();
    final languageProvider = context.watch<LanguageProvider>();

    var screenWidth = MediaQuery.of(context).size.width;
    bool isTV = themeProvider.isTV; // 获取 TV 模式状态
    double maxContainerWidth = 580;

    return FocusScope(
      child: TvKeyNavigation(
        focusNodes: _focusNodes,
        isHorizontalGroup: true, // 启用横向分组
        initialIndex: 0, // 设置初始焦点索引为 0
        isFrame: isTV, // TV 模式下启用框架模式
        frameType: isTV ? "child" : null, // TV 模式下设置为子页面
        child: Scaffold(
          backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下背景颜色
          appBar: AppBar(
            leading: isTV ? const SizedBox.shrink() : null, // TV模式下隐藏返回按钮
            title: Text(
              S.of(context).fontTitle, // 标题
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            backgroundColor: isTV ? const Color(0xFF1E2022) : null,
          ),
          body: Align(
            alignment: Alignment.center, // 内容居中
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 字体大小选择部分
                    _buildFontSizeSelection(themeProvider),
                    const SizedBox(height: 12), // 间距
                    // 语言选择部分
                    _buildLanguageSelection(languageProvider),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 抽取字体大小选择部分为独立函数，使用 Group 包裹
  Widget _buildFontSizeSelection(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.of(context).fontSizeTitle, // 字体大小标题
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10), // 间距
          Group(
            groupIndex: 0, // 设置 Group 的索引为 0
            children: List.generate(_fontScales.length, (index) {
              return FocusableItem(
                focusNode: _focusNodes[index], // 包裹按钮并分配焦点节点
                child: _buildChoiceChip(
                  label: '${_fontScales[index]}',
                  isSelected: themeProvider.textScaleFactor == _fontScales[index],
                  onSelected: () => themeProvider.setTextScale(_fontScales[index]),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // 抽取语言选择部分为独立函数，每个 FocusableItem 用 Group 包裹
  Widget _buildLanguageSelection(LanguageProvider languageProvider) {
    return Padding(
      padding: const EdgeInsets.all(15), // 外边距
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.of(context).languageSelection, // 语言选择标题
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6), // 间距
          Column(
            children: List.generate(_languages.length, (index) {
              return Group(
                groupIndex: index + 1, // 为每个语言选择设置递增的 groupIndex
                children: [
                  FocusableItem(
                    focusNode: _focusNodes[index + 5], // 包裹按钮并分配焦点节点
                    child: _buildChoiceChip(
                      label: languageProvider.currentLocale.toString() ==
                              _languageCodes[index]
                          ? S.of(context).inUse
                          : S.of(context).use,
                      isSelected: languageProvider.currentLocale.toString() ==
                          _languageCodes[index],
                      onSelected: () =>
                          languageProvider.changeLanguage(_languageCodes[index]),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // 提取 ChoiceChip 的构建逻辑，减少重复代码
  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: _selectedColor,
      backgroundColor: isSelected ? darkenColor(_unselectedColor) : _unselectedColor,
      shape: _buttonShape,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    );
  }
}
