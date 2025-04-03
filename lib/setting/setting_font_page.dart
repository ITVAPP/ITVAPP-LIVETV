import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 新增 SelectionState 类用于管理焦点和选中状态
class SelectionState {
  final int focusedIndex; // 当前聚焦的索引
  final int selectedIndex; // 当前选中的索引

  SelectionState(this.focusedIndex, this.selectedIndex);
}

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

  // 管理字体和语言的状态
  late SelectionState _fontState;
  late SelectionState _langState;

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
    // 初始化焦点节点并绑定统一的监听器
    _focusNodes = List<FocusNode>.generate(8, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 统一监听焦点变化
      return node;
    });

    // 初始化状态，默认选中 1.0 和 English
    _fontState = SelectionState(-1, 2); // 1.0 在 _fontScales 中索引为 2
    _langState = SelectionState(-1, 0); // English 在 _languageCodes 中索引为 0
  }

  // 统一处理焦点变化
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      if (focusedIndex < 5) {
        _fontState = SelectionState(focusedIndex, _fontScales.indexOf(context.read<ThemeProvider>().textScaleFactor));
      } else {
        _langState = SelectionState(focusedIndex - 5, _languageCodes.indexOf(context.read<LanguageProvider>().currentLocale.toString()));
      }
    }
    _debounceSetState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel(); // 清理防抖定时器
    if (mounted) {
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange); // 统一移除监听器
        node.dispose(); // 释放焦点节点
      }
    }
    super.dispose();
  }

  // 提取颜色计算逻辑
  Color _getChipColor(bool isFocused, bool isSelected) {
    if (isFocused) {
      return isSelected ? darkenColor(_selectedColor) : darkenColor(_unselectedColor);
    }
    return isSelected ? _selectedColor : _unselectedColor;
  }

  // 提取公共方法：创建 ChoiceChip 组件，统一处理样式和逻辑
  Widget _buildChoiceChip({
    required FocusNode focusNode,
    required String labelText,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isBold,
  }) {
    final isFocused = focusNode.hasFocus; // 检查焦点状态
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
      selectedColor: _getChipColor(isFocused, true),
      backgroundColor: _getChipColor(isFocused, false),
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
                        state: _fontState, // 传递状态
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
                        state: _langState, // 传递状态
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

// 修改为无状态组件：FontSizeSection
class FontSizeSection extends StatelessWidget {
  final List<FocusNode> focusNodes;
  final List<double> fontScales;
  final SelectionState state; // 新增状态参数
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
    required this.state,
    required this.themeProvider,
    required this.buildChoiceChip,
  });

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
                fontScales.length,
                (index) => FocusableItem(
                  focusNode: focusNodes[index], // 分配焦点节点
                  child: buildChoiceChip(
                    focusNode: focusNodes[index],
                    labelText: '${fontScales[index]}',
                    isSelected: state.selectedIndex == index,
                    onSelected: () => themeProvider.setTextScale(fontScales[index]),
                    isBold: state.selectedIndex == index,
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

// 修改为无状态组件：LanguageSection
class LanguageSection extends StatelessWidget {
  final List<FocusNode> focusNodes;
  final List<String> languages;
  final List<String> languageCodes;
  final SelectionState state; // 新增状态参数
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
    required this.state,
    required this.languageProvider,
    required this.buildChoiceChip,
  });

  @override
  Widget build(BuildContext context) {
    final currentLocale = languageProvider.currentLocale.toString();
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
            languages.length,
            (index) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  languages[index], // 显示语言名称
                  style: const TextStyle(fontSize: 18),
                ),
                Group(
                  groupIndex: index + 1, // 分组索引递增
                  children: [
                    FocusableItem(
                      focusNode: focusNodes[index], // 分配焦点节点
                      child: buildChoiceChip(
                        focusNode: focusNodes[index],
                        labelText: currentLocale == languageCodes[index]
                            ? S.of(context).inUse
                            : S.of(context).use,
                        isSelected: state.selectedIndex == index,
                        onSelected: () => languageProvider.changeLanguage(languageCodes[index]),
                        isBold: state.selectedIndex == index,
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
