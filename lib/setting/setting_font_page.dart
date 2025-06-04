import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 管理焦点和选中状态
class SelectionState {
  final int focusedIndex; // 聚焦按钮索引
  final int selectedIndex; // 选中选项索引

  SelectionState(this.focusedIndex, this.selectedIndex);

  // 比较状态，避免无效更新
  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is SelectionState &&
    runtimeType == other.runtimeType &&
    focusedIndex == other.focusedIndex &&
    selectedIndex == other.selectedIndex;

  @override
  int get hashCode => focusedIndex.hashCode ^ selectedIndex.hashCode;
}

// 字体设置页面主类
class SettingFontPage extends StatefulWidget {
  const SettingFontPage({super.key});

  @override
  State<SettingFontPage> createState() => _SettingFontPageState();
}

// 字体设置页面状态类
class _SettingFontPageState extends State<SettingFontPage> {
  // 页面标题样式
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  // 章节标题样式
  static const _sectionTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  // 按钮内边距
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 6);
  // 容器最大宽度
  static const _maxContainerWidth = 580.0;
  // 章节内边距
  static const _sectionPadding = EdgeInsets.all(15.0);

  // 定义AppBar分割线样式
  static final _appBarDivider = PreferredSize(
    preferredSize: const Size.fromHeight(1),
    child: Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    ),
  );

  // 定义AppBar装饰样式
  static final _appBarDecoration = BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        spreadRadius: 2,
        offset: const Offset(0, 2),
      ),
    ],
  );

  final _fontScales = [0.8, 0.9, 1.0, 1.1, 1.2]; // 字体缩放比例
  final _languages = ['English', '简体中文', '正體中文']; // 语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 语言代码

  // 按钮圆角样式
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  // 选中背景色（红色）
  final _selectedColor = const Color(0xFFEB144C);
  // 未选中背景色（黄色）
  final _unselectedColor = const Color(0xFFDFA02A);

  // 字体和语言按钮焦点节点
  late final List<FocusNode> _focusNodes;

  // 分组焦点缓存，优化TV导航
  late final Map<int, Map<String, FocusNode>> _groupFocusCache;

  // 字体选择状态
  late SelectionState _fontState;
  // 语言选择状态
  late SelectionState _langState;

  @override
  void initState() {
    super.initState();

    // 初始化字体和语言焦点节点
    final totalNodes = _fontScales.length + _languages.length;
    _focusNodes = List<FocusNode>.generate(totalNodes, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange);
      return node;
    });

    // 初始化分组焦点缓存
    _groupFocusCache = _generateGroupFocusCache();

    // 默认选中字体1.0和English
    _fontState = SelectionState(-1, _fontScales.indexOf(1.0));
    _langState = SelectionState(-1, 0);
  }

  // 生成分组焦点缓存
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache() {
    final cache = <int, Map<String, FocusNode>>{};

    // 字体大小按钮分组
    cache[0] = {
      'firstFocusNode': _focusNodes[0],
      'lastFocusNode': _focusNodes[_fontScales.length - 1],
    };

    // 语言选择按钮分组
    for (int i = 0; i < _languages.length; i++) {
      final nodeIndex = _fontScales.length + i;
      cache[i + 1] = {
        'firstFocusNode': _focusNodes[nodeIndex],
        'lastFocusNode': _focusNodes[nodeIndex],
      };
    }

    return cache;
  }

  // 处理焦点变化，减少无效更新
  void _handleFocusChange() {
    Future.microtask(() {
      if (!mounted) return;
      
      final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
      
      // 默认两个组都没有焦点
      SelectionState newFontState = SelectionState(-1, _fontState.selectedIndex);
      SelectionState newLangState = SelectionState(-1, _langState.selectedIndex);
      
      if (focusedIndex != -1) {
        if (focusedIndex < _fontScales.length) {
          // 焦点在字体组
          newFontState = SelectionState(focusedIndex, _fontState.selectedIndex);
        } else {
          // 焦点在语言组
          newLangState = SelectionState(focusedIndex - _fontScales.length, _langState.selectedIndex);
        }
      }
      
      // 只在状态真正改变时才更新
      if (newFontState != _fontState || newLangState != _langState) {
        setState(() {
          _fontState = newFontState;
          _langState = newLangState;
        });
      }
    });
  }

  @override
  void dispose() {
    if (mounted) {
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange);
        node.dispose();
      }
    }
    super.dispose();
  }

  // 计算按钮颜色
  Color _getChipColor(bool isFocused, bool isSelected) {
    if (isFocused) {
      // 调整焦点状态颜色
      return isSelected ? darkenColor(_selectedColor) : darkenColor(_unselectedColor);
    }
    return isSelected ? _selectedColor : _unselectedColor;
  }

  // 构建通用ChoiceChip按钮
  Widget _buildChoiceChip({
    required FocusNode focusNode,
    required String labelText,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isBold,
  }) {
    final nodeIndex = _focusNodes.indexOf(focusNode);
    bool isFocused = false;
    
    if (nodeIndex < _fontScales.length) {
      isFocused = _fontState.focusedIndex == nodeIndex;
    } else {
      isFocused = _langState.focusedIndex == (nodeIndex - _fontScales.length);
    }
    
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
    final screenWidth = MediaQuery.of(context).size.width;
    final themeProvider = context.watch<ThemeProvider>();
    final isTV = themeProvider.isTV;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48.0,
        centerTitle: true,
        automaticallyImplyLeading: !isTV,
        leading: isTV ? null : null,
        title: Text(
          S.of(context).fontTitle,
          style: _titleStyle,
        ),
        bottom: _appBarDivider,
        flexibleSpace: Container(
          decoration: _appBarDecoration,
        ),
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes,
          groupFocusCache: _groupFocusCache,
          isHorizontalGroup: true,
          initialIndex: 0,
          isFrame: isTV ? true : false,
          frameType: isTV ? "child" : null,
          child: Align(
            alignment: Alignment.center,
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
                        focusNodes: _focusNodes.sublist(0, _fontScales.length),
                        fontScales: _fontScales,
                        state: _fontState,
                        buildChoiceChip: _buildChoiceChip,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: _sectionPadding,
                      child: LanguageSection(
                        focusNodes: _focusNodes.sublist(_fontScales.length),
                        languages: _languages,
                        languageCodes: _languageCodes,
                        state: _langState,
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

// 字体大小选择组件
class FontSizeSection extends StatelessWidget {
  final List<FocusNode> focusNodes;
  final List<double> fontScales;
  final SelectionState state;
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
    required this.buildChoiceChip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).fontSizeTitle,
          style: _SettingFontPageState._sectionTitleStyle,
        ),
        const SizedBox(height: 10),
        Group(
          groupIndex: 0,
          children: [
            Wrap(
              spacing: 5,
              runSpacing: 8,
              children: List.generate(
                fontScales.length,
                (index) => FocusableItem(
                  focusNode: focusNodes[index],
                  child: buildChoiceChip(
                    focusNode: focusNodes[index],
                    labelText: '${fontScales[index]}',
                    isSelected: state.selectedIndex == index,
                    onSelected: () => context.read<ThemeProvider>().setTextScale(fontScales[index]),
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

// 语言选择组件
class LanguageSection extends StatelessWidget {
  final List<FocusNode> focusNodes;
  final List<String> languages;
  final List<String> languageCodes;
  final SelectionState state;
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
    required this.buildChoiceChip,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<LanguageProvider, String>(
      selector: (context, languageProvider) => languageProvider.currentLocale.toString(),
      builder: (context, currentLocale, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.of(context).languageSelection,
            style: _SettingFontPageState._sectionTitleStyle,
          ),
          const SizedBox(height: 6),
          ...List.generate(
            languages.length,
            (index) => Group(
              groupIndex: index + 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      languages[index],
                      style: const TextStyle(fontSize: 18),
                    ),
                    FocusableItem(
                      focusNode: focusNodes[index],
                      child: buildChoiceChip(
                        focusNode: focusNodes[index],
                        labelText: currentLocale == languageCodes[index]
                            ? S.of(context).inUse
                            : S.of(context).use,
                        isSelected: state.selectedIndex == index,
                        onSelected: () async {
                          final currentLanguageCode = currentLocale;
                          await context.read<LanguageProvider>().changeLanguage(languageCodes[index]);
                          final parentState = context.findAncestorStateOfType<_SettingFontPageState>();
                          if (parentState != null && parentState.mounted) {
                            final newLangState = SelectionState(state.focusedIndex, index);
                            if (newLangState != parentState._langState) {
                              parentState.setState(() {
                                parentState._langState = newLangState;
                              });
                            }
                          }
                          final newLanguageCode = languageCodes[index];
                          final isChinese = _isChinese(newLanguageCode);
                          final wasChineseBefore = _isChinese(currentLanguageCode);
                          final isChineseVariantChange = 
                              (currentLanguageCode.contains("CN") && newLanguageCode.contains("TW")) ||
                              (currentLanguageCode.contains("TW") && newLanguageCode.contains("CN"));
                          if (isChinese && (!wasChineseBefore || isChineseVariantChange)) {
                            CustomSnackBar.showSnackBar(
                              context, 
                              S.of(context).langTip,
                              duration: const Duration(seconds: 5),
                            );
                          }
                        },
                        isBold: state.selectedIndex == index,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 检查语言是否为中文
  bool _isChinese(String languageCode) {
    return languageCode == 'zh' || languageCode.startsWith('zh_');
  }
}
