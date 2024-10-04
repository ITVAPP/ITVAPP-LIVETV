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
  final _fontScales = [0.8, 0.9, 1.0, 1.1, 1.2]; // 字体缩放比例
  final _languages = ['English', '简体中文', '正體中文']; // 语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 语言代码

  // 统一的圆角样式
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16), // 设置圆角
  );

  // 按钮颜色更新
  final _selectedColor = const Color(0xFFEB144C); // 选中时颜色
  final _unselectedColor = const Color(0xFFFE8401); // 未选中时颜色

  // 焦点节点列表，用于 TV 端焦点管理
  final List<FocusNode> _fontFocusNodes = List.generate(5, (index) => FocusNode());
  final List<FocusNode> _languageFocusNodes = List.generate(3, (index) => FocusNode());

  @override
  void initState() {
    super.initState();
    // 页面加载时，将焦点默认设置到第一个字体按钮
    _fontFocusNodes[0].requestFocus();
  }

  @override
  void dispose() {
    // 释放所有焦点节点资源，防止内存泄漏
    for (var node in _fontFocusNodes) {
      node.dispose();
    }
    for (var node in _languageFocusNodes) {
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
        title: Text(S.of(context).fontTitle), // 设置页面标题
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下AppBar背景颜色
      ),
      body: Align(
        alignment: Alignment.center, // 内容居中显示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 580 ? maxContainerWidth : double.infinity, // 限制最大宽度
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0), // 添加左右内边距
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
                        Text(S.of(context).fontSizeTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 字体大小标题
                        const SizedBox(height: 10), // 间距
                        Wrap(
                          spacing: 5,
                          runSpacing: 8, // 选项排列方式
                          children: List.generate(
                            _fontScales.length,
                            (index) => Focus(
                              focusNode: _fontFocusNodes[index], // 为每个按钮设置焦点节点
                              child: ChoiceChip(
                                label: Text(
                                  '${_fontScales[index]}', // 显示字体缩放比例
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white, // 文字颜色统一为白色
                                    fontWeight: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                                        ? FontWeight.bold // 选中状态加粗
                                        : FontWeight.normal, // 未选中状态正常
                                  ),
                                ),
                                selected: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index], // 当前选中的字体缩放
                                onSelected: (bool selected) {
                                  context.read<ThemeProvider>().setTextScale(_fontScales[index]); // 设置字体缩放
                                },
                                selectedColor: _selectedColor, // 选中或焦点颜色为 #FE8401
                                backgroundColor: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                                    ? _selectedColor // 选中状态颜色
                                    : _unselectedColor, // 未选中状态颜色
                                shape: _buttonShape, // 统一的圆角外形
                              ),
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
                        Text(S.of(context).languageSelection, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 语言选择标题
                        const SizedBox(height: 6), // 间距
                        Column(
                          children: List.generate(
                            _languages.length,
                            (index) => Focus(
                              focusNode: _languageFocusNodes[index], // 为每个语言按钮设置焦点节点
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6.0), // 增加下部的外边距
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左侧显示语言，右侧显示按钮
                                  children: [
                                    Text(_languages[index], style: const TextStyle(fontSize: 16)), // 显示语言名称
                                    ChoiceChip(
                                      label: Text(
                                        context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                            ? S.of(context).inUse // 已选中的显示 "使用中"
                                            : S.of(context).use, // 未选中的显示 "使用"
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white, // 文字颜色统一为白色
                                          fontWeight: context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                              ? FontWeight.bold // 选中状态加粗
                                              : FontWeight.normal, // 未选中状态正常
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
                                          : _unselectedColor, // 未选中状态颜色
                                      shape: _buttonShape, // 统一的圆角外形
                                    ),
                                  ],
                                ),
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
      ),
    );
  }
}
