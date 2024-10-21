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

  // 统一的圆角样式
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16), // 设置圆角
  );

  // 按钮颜色更新
  final _selectedColor = const Color(0xFFEB144C); // 选中时颜色
  final _unselectedColor = const Color(0xFFDFA02A); // 未选中时颜色

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

  Widget _buildFontSizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).fontSizeTitle, // 字体大小标题
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10), // 间距
        Group(
          groupIndex: 0, // 分组 0：字体大小
          children: [
            Wrap(
              spacing: 5,
              runSpacing: 8, // 按钮排列方式
              children: List.generate(
                _fontScales.length,
                (index) => FocusableItem(
                  focusNode: _focusNodes[index], // 分配焦点节点
                  child: ChoiceChip(
                    label: Text(
                      '${_fontScales[index]}', // 显示字体大小
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: context.watch<ThemeProvider>().textScaleFactor == _fontScales[index],
                    onSelected: (bool selected) {
                      context.read<ThemeProvider>().setTextScale(_fontScales[index]); // 更新字体大小
                    },
                    selectedColor: _selectedColor,
                    backgroundColor: _focusNodes[index].hasFocus
                        ? (context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                            ? darkenColor(_selectedColor) // 已选中且聚焦时
                            : darkenColor(_unselectedColor)) // 未选中但聚焦时
                        : (context.watch<ThemeProvider>().textScaleFactor == _fontScales[index]
                            ? _selectedColor // 已选中且未聚焦
                            : _unselectedColor), // 未选中且未聚焦
                    shape: _buttonShape,
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLanguageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).languageSelection, // 语言选择标题
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6), // 间距
        Column(
          children: List.generate(
            _languages.length,
            (index) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _languages[index], // 显示语言名称
                  style: const TextStyle(fontSize: 18),
                ),
                Group(
                  groupIndex: index + 1, // 分组索引递增
                  children: [
                    FocusableItem(
                      focusNode: _focusNodes[index + 5], // 分配焦点节点
                      child: ChoiceChip(
                        label: Text(
                          context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                              ? S.of(context).inUse
                              : S.of(context).use,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index],
                        onSelected: (bool selected) {
                          context.read<LanguageProvider>().changeLanguage(_languageCodes[index]); // 切换语言
                        },
                        selectedColor: _selectedColor,
                        backgroundColor: _focusNodes[index + 5].hasFocus
                            ? (context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                ? darkenColor(_selectedColor) // 已选中且聚焦时
                                : darkenColor(_unselectedColor)) // 未选中但聚焦时
                            : (context.watch<LanguageProvider>().currentLocale.toString() == _languageCodes[index]
                                ? _selectedColor // 已选中且未聚焦
                                : _unselectedColor), // 未选中且未聚焦
                        shape: _buttonShape,
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    bool isTV = context.watch<ThemeProvider>().isTV;
    double maxContainerWidth = 580;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下隐藏返回按钮
        title: Text(
          S.of(context).fontTitle, // 标题
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes,
          isHorizontalGroup: true, // 启用横向分组
          initialIndex: 0, // 设置初始焦点索引为 0
          isFrame: isTV ? true : false, // TV 模式下启用框架模式
          frameType: isTV ? "child" : null, // TV 模式下设置为子页面
          child: Align(
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
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: _buildFontSizeSection(),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: _buildLanguageSection(),
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
