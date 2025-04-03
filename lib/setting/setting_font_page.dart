import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'dart:async';

class SettingFontPage extends StatefulWidget {
  const SettingFontPage({super.key});

  @override
  State<SettingFontPage> createState() => _SettingFontPageState();
}

class _SettingFontPageState extends State<SettingFontPage> {
  // 提取常用样式为静态常量
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  static const _sectionTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 6);
  static const _maxContainerWidth = 580.0; // 提取最大宽度为常量
  static const _sectionPadding = EdgeInsets.all(15.0); // 提取内边距为常量

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
  late final List<FocusNode> _focusNodes;

  // 用于防抖的定时器和函数
  Timer? _debounceTimer;
  void _debounceSetState() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    // 初始化焦点节点并绑定监听器
    _focusNodes = List<FocusNode>.generate(8, (index) {
      final node = FocusNode();
      node.addListener(_debounceSetState); // 使用统一的防抖函数
      return node;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel(); // 清理防抖定时器
    if (mounted) {
      for (var node in _focusNodes) node.dispose(); // 确保 mounted 时释放资源
    }
    super.dispose();
  }

  // 提取公共方法：创建 ChoiceChip 组件，统一处理样式和逻辑
  Widget _buildChoiceChip({
    required FocusNode focusNode,
    required String labelText,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isBold,
  }) {
    return ChoiceChip(
      label: Text(
        labelText,
        style: TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (bool selected) => onSelected(),
      selectedColor: focusNode.hasFocus ? darkenColor(_selectedColor) : _selectedColor,
      backgroundColor: focusNode.hasFocus ? darkenColor(_unselectedColor) : _unselectedColor,
      shape: _buttonShape,
      padding: _buttonPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 缓存 build 中常用值
    final screenWidth = MediaQuery.of(context).size.width;
    final themeProvider = context.watch<ThemeProvider>();
    final languageProvider = context.watch<LanguageProvider>();
    final isTV = themeProvider.isTV;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式下背景颜色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式下隐藏返回按钮
        title: Text(
          S.of(context).fontTitle, // 标题
          style: _titleStyle,
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
                maxWidth: screenWidth > _maxContainerWidth ? _maxContainerWidth : double.infinity,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: _sectionPadding,
                      child: FontSizeSection(
                        focusNodes: _focusNodes.sublist(0, 5),
                        fontScales: _fontScales,
                        themeProvider: themeProvider,
                        buildChoiceChip: _buildChoiceChip,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: _sectionPadding,
                      child: LanguageSection(
                        focusNodes: _focusNodes.sublist(5),
                        languages: _languages,
                        languageCodes: _languageCodes,
                        languageProvider: languageProvider,
                        buildChoiceChip: _buildChoiceChip,
                      ),
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

// 新增独立的 FontSizeSection 组件，减少重绘范围
class FontSizeSection extends StatefulWidget {
  final List<FocusNode> focusNodes;
  final List<double> fontScales;
  final ThemeProvider themeProvider;
  final Widget Function({
    required FocusNode focusNode,
    required String labelText,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isBold,
  }) buildChoiceChip;

  const FontSizeSection({
    super.key,
    required this.focusNodes,
    required this.fontScales,
    required this.themeProvider,
    required this.buildChoiceChip,
  });

  @override
  State<FontSizeSection> createState() => _FontSizeSectionState();
}

class _FontSizeSectionState extends State<FontSizeSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).fontSizeTitle, // 字体大小标题
          style: _SettingFontPageState._sectionTitleStyle,
        ),
        const SizedBox(height: 10), // 间距
        Group(
          groupIndex: 0, // 分组 0：字体大小
          children: [
            Wrap(
              spacing: 5,
              runSpacing: 8, // 按钮排列方式
              children: List.generate(
                widget.fontScales.length,
                (index) => FocusableItem(
                  focusNode: widget.focusNodes[index], // 分配焦点节点
                  child: widget.buildChoiceChip(
                    focusNode: widget.focusNodes[index],
                    labelText: '${widget.fontScales[index]}',
                    isSelected: widget.themeProvider.textScaleFactor == widget.fontScales[index],
                    onSelected: () => widget.themeProvider.setTextScale(widget.fontScales[index]),
                    isBold: widget.themeProvider.textScaleFactor == widget.fontScales[index],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 新增独立的 LanguageSection 组件，减少重绘范围
class LanguageSection extends StatefulWidget {
  final List<FocusNode> focusNodes;
  final List<String> languages;
  final List<String> languageCodes;
  final LanguageProvider languageProvider;
  final Widget Function({
    required FocusNode focusNode,
    required String labelText,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isBold,
  }) buildChoiceChip;

  const LanguageSection({
    super.key,
    required this.focusNodes,
    required this.languages,
    required this.languageCodes,
    required this.languageProvider,
    required this.buildChoiceChip,
  });

  @override
  State<LanguageSection> createState() => _LanguageSectionState();
}

class _LanguageSectionState extends State<LanguageSection> {
  @override
  Widget build(BuildContext context) {
    final currentLocale = widget.languageProvider.currentLocale.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).languageSelection, // 语言选择标题
          style: _SettingFontPageState._sectionTitleStyle,
        ),
        const SizedBox(height: 6), // 间距
        Column(
          children: List.generate(
            widget.languages.length,
            (index) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.languages[index], // 显示语言名称
                  style: const TextStyle(fontSize: 18),
                ),
                Group(
                  groupIndex: index + 1, // 分组索引递增
                  children: [
                    FocusableItem(
                      focusNode: widget.focusNodes[index], // 分配焦点节点
                      child: widget.buildChoiceChip(
                        focusNode: widget.focusNodes[index],
                        labelText: currentLocale == widget.languageCodes[index]
                            ? S.of(context).inUse
                            : S.of(context).use,
                        isSelected: currentLocale == widget.languageCodes[index],
                        onSelected: () => widget.languageProvider.changeLanguage(widget.languageCodes[index]),
                        isBold: currentLocale == widget.languageCodes[index],
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
}
