import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../generated/l10n.dart';

class SettingFontPage extends StatefulWidget {
  const SettingFontPage({super.key});

  @override
  State<SettingFontPage> createState() => _SettingFontPageState();
}

class _SettingFontPageState extends State<SettingFontPage> {
  final _fontScales = [1.0, 1.1, 1.2, 1.3, 1.5]; // 字体缩放比例
  final _languages = ['English', '简体中文', '正體中文']; // 语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 语言代码

  // 统一的圆角样式
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30), // 设置圆角
  );

  // 统一的按钮选中颜色
  final _selectedColor = const Color(0xFFEB144C); // 选中时颜色
  final _unselectedColor = Colors.grey[300]; // 未选中时颜色

  // 焦点节点列表，用于 TV 端焦点管理
  final List<FocusNode> _focusNodes = List.generate(5, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    // 页面加载时，将焦点默认设置到第一个过滤按钮
    _focusNodes[0].requestFocus();
  }

  @override
  void dispose() {
    // 释放所有焦点节点资源，防止内存泄漏
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度以进行布局优化
    var screenWidth = MediaQuery.of(context).size.width;

    // 通过 Provider 获取 isTV 状态
    bool isTV = context.watch<ThemeProvider>().isTV;

    // 最大内容宽度，适用于大屏设备
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下的背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下不显示返回按钮
        title: Text(S.of(context).settings), // 设置页面标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下AppBar背景颜色
      ),
      body: Align(
        alignment: Alignment.center, // 内容居中显示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
          ),
          child: FocusTraversalGroup( // 在 TV 模式下，使用焦点组管理方向键焦点切换
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 子组件从左对齐
              children: [
                // 字体大小设置部分
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.of(context).fontSizeTitle, style: TextStyle(fontSize: 17)), // 字体大小标题
                      const SizedBox(height: 10), // 间距
                      Wrap(
                        spacing: 10,
                        runSpacing: 10, // 选项排列方式
                        children: List.generate(
                          _fontScales.length,
                          (index) => ChoiceChip(
                            label: Text(
                              '${_fontScales[index]}', // 显示字体缩放比例
                              style: TextStyle(
                                fontSize: 15,
                                color: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                                    ? Colors.white // 选中状态的文字颜色
                                    : Colors.black, // 未选中状态的文字颜色
                              ),
                            ),
                            selected: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index], // 当前选中的字体缩放
                            onSelected: (bool selected) {
                              context.read<ThemeProvider>().setTextScale(_fontScales[index]); // 设置字体缩放
                            },
                            selectedColor: _selectedColor, // 选中状态颜色
                            backgroundColor: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                                ? _selectedColor // 选中状态颜色
                                : _unselectedColor, // 未选中状态颜色
                            shape: _buttonShape, // 统一的圆角外形
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12), // 间距

                // 语言选择部分
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.of(context).languageSelection, style: TextStyle(fontSize: 17)), // 语言选择标题
                      const SizedBox(height: 6), // 间距
                      Column(
                        children: List.generate(
                          _languages.length,
                          (index) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0), // 增加下部的外边距
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左侧显示语言，右侧显示按钮
                              children: [
                                Text(_languages[index], style: const TextStyle(fontSize: 15)), // 显示语言名称
                                ChoiceChip(
                                  label: Text(
                                    context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                        ? S.of(context).inUse // 已选中的显示 "使用中"
                                        : S.of(context).use, // 未选中的显示 "使用"
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                          ? Colors.white // 选中状态的文字颜色
                                          : Colors.black, // 未选中状态的文字颜色
                                    ),
                                  ),
                                  selected: context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index], // 当前选中的语言
                                  onSelected: (bool selected) {
                                    // 切换语言，点击即触发，不判断是否已选中
                                    context.read<LanguageProvider>().changeLanguage(_languageCodes[index]);
                                  },
                                  selectedColor: _selectedColor, // 选中状态颜色
                                  backgroundColor: context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                      ? _selectedColor // 已选中状态颜色
                                      : _unselectedColor, // 未选中状态的颜色
                                  shape: _buttonShape, // 统一的圆角外形
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
