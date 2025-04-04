import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// SelectionState 类用于管理焦点和选中状态
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
  // 提取常用样式为静态常量，提升复用性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold); // 标题样式
  static const _sectionTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold); // 章节标题样式
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 6); // 按钮内边距
  static const _maxContainerWidth = 580.0; // 容器最大宽度
  static const _sectionPadding = EdgeInsets.all(15.0); // 章节内边距

  final _fontScales = [0.8, 0.9, 1.0, 1.1, 1.2]; // 可选字体缩放比例
  final _languages = ['English', '简体中文', '正體中文']; // 可选语言显示名称
  final _languageCodes = ['en', 'zh_CN', 'zh_TW']; // 对应的语言代码

  // 统一的圆角样式
  final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16), // 按钮圆角半径
  );

  // 按钮颜色定义
  final _selectedColor = const Color(0xFFEB144C); // 选中状态颜色
  final _unselectedColor = const Color(0xFFDFA02A); // 未选中状态颜色

  // 焦点节点列表，按顺序分配给字体和语言按钮
  late final List<FocusNode> _focusNodes;

  // 分组焦点缓存，用于TV导航
  late final Map<int, Map<String, FocusNode>> _groupFocusCache;

  // 管理字体和语言的选择状态
  late SelectionState _fontState; // 字体缩放状态
  late SelectionState _langState; // 语言选择状态

  @override
  void initState() {
    super.initState();

    // 动态生成焦点节点总数：字体 + 语言
    final totalNodes = _fontScales.length + _languages.length;
    _focusNodes = List<FocusNode>.generate(totalNodes, (index) {
      final node = FocusNode();
      node.addListener(_handleFocusChange); // 添加焦点变化监听
      return node;
    });

    // 初始化分组焦点缓存
    _groupFocusCache = _generateGroupFocusCache();

    // 初始化状态：默认选中字体 1.0 和 English
    _fontState = SelectionState(-1, _fontScales.indexOf(1.0)); // 字体默认选中 1.0
    _langState = SelectionState(-1, 0); // 语言默认选中 English
  }

  // 动态生成分组焦点缓存
  Map<int, Map<String, FocusNode>> _generateGroupFocusCache() {
    final cache = <int, Map<String, FocusNode>>{};

    // 分组 0：字体大小
    cache[0] = {
      'firstFocusNode': _focusNodes[0], // 字体第一个焦点
      'lastFocusNode': _focusNodes[_fontScales.length - 1], // 字体最后一个焦点
    };

    // 分组 1 及以上：语言选择
    for (int i = 0; i < _languages.length; i++) {
      final nodeIndex = _fontScales.length + i;
      cache[i + 1] = {
        'firstFocusNode': _focusNodes[nodeIndex], // 语言焦点起始
        'lastFocusNode': _focusNodes[nodeIndex], // 每个语言单节点
      };
    }

    return cache;
  }

  // 统一处理焦点变化
  void _handleFocusChange() {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      if (focusedIndex < _fontScales.length) {
        _fontState = SelectionState(focusedIndex, _fontState.selectedIndex);
      } else {
        _langState = SelectionState(focusedIndex - _fontScales.length, _langState.selectedIndex);
      }
      if (mounted) setState(() {});
    } else {
      // 若未找到焦点，延迟检查
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newFocusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
        if (newFocusedIndex != -1 && mounted) {
          setState(() {
            if (newFocusedIndex < _fontScales.length) {
              _fontState = SelectionState(newFocusedIndex, _fontState.selectedIndex);
            } else {
              _langState = SelectionState(newFocusedIndex - _fontScales.length, _langState.selectedIndex);
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    if (mounted) {
      for (var node in _focusNodes) {
        node.removeListener(_handleFocusChange); // 移除焦点监听
        node.dispose(); // 释放焦点节点
      }
    }
    super.dispose();
  }

  // 计算按钮颜色
  Color _getChipColor(bool isFocused, bool isSelected) {
    if (isFocused) {
      return isSelected ? darkenColor(_selectedColor) : darkenColor(_unselectedColor);
    }
    return isSelected ? _selectedColor : _unselectedColor;
  }

  // 创建统一的 ChoiceChip 组件
  Widget _buildChoiceChip({
    required FocusNode focusNode,
    required String labelText,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isBold,
  }) {
    final isFocused = focusNode.hasFocus;
    return ChoiceChip(
      label: Text(
        labelText,
        style: TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal, // 选中时加粗
        ),
      ),
      selected: isSelected,
      onSelected: (bool selected) => onSelected(), // 点击时触发回调
      selectedColor: _getChipColor(isFocused, true),
      backgroundColor: _getChipColor(isFocused, false),
      shape: _buttonShape, // 统一圆角样式
      padding: _buttonPadding, // 统一内边距
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width; // 获取屏幕宽度
    final themeProvider = context.watch<ThemeProvider>(); // 主题提供者
    final languageProvider = context.watch<LanguageProvider>(); // 语言提供者
    final isTV = themeProvider.isTV; // 是否为TV模式

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式背景色
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null, // TV模式隐藏返回按钮
        title: Text(
          S.of(context).fontTitle, // 页面标题
          style: _titleStyle,
        ),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null, // TV模式标题栏颜色
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _focusNodes, // 焦点节点列表
          groupFocusCache: _groupFocusCache, // 分组焦点缓存
          isHorizontalGroup: true, // 启用横向分组
          initialIndex: 0, // 初始焦点索引
          isFrame: isTV ? true : false, // TV模式启用框架
          frameType: isTV ? "child" : null, // TV模式子页面类型
          child: Align(
            alignment: Alignment.center, // 内容居中对齐
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth > _maxContainerWidth ? _maxContainerWidth : double.infinity, // 限制最大宽度
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: _sectionPadding,
                      child: FontSizeSection(
                        focusNodes: _focusNodes.sublist(0, _fontScales.length), // 字体焦点节点
                        fontScales: _fontScales,
                        state: _fontState, // 字体状态
                        themeProvider: themeProvider,
                        buildChoiceChip: _buildChoiceChip, // 按钮构建方法
                      ),
                    ),
                    const SizedBox(height: 12), // 章节间距
                    Padding(
                      padding: _sectionPadding,
                      child: LanguageSection(
                        focusNodes: _focusNodes.sublist(_fontScales.length), // 语言焦点节点
                        languages: _languages,
                        languageCodes: _languageCodes,
                        state: _langState, // 语言状态
                        languageProvider: languageProvider,
                        buildChoiceChip: _buildChoiceChip, // 按钮构建方法
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

// 无状态组件：字体大小选择部分
class FontSizeSection extends StatelessWidget {
  final List<FocusNode> focusNodes; // 焦点节点列表
  final List<double> fontScales; // 字体缩放比例
  final SelectionState state; // 当前状态
  final ThemeProvider themeProvider; // 主题提供者
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
        const SizedBox(height: 10), // 标题与内容间距
        Group(
          groupIndex: 0, // 分组索引：字体大小
          children: [
            Wrap(
              spacing: 5, // 按钮水平间距
              runSpacing: 8, // 按钮垂直间距
              children: List.generate(
                fontScales.length,
                (index) => FocusableItem(
                  focusNode: focusNodes[index], // 分配焦点
                  child: buildChoiceChip(
                    focusNode: focusNodes[index],
                    labelText: '${fontScales[index]}', // 显示缩放比例
                    isSelected: state.selectedIndex == index,
                    onSelected: () => themeProvider.setTextScale(fontScales[index]), // 设置字体缩放
                    isBold: state.selectedIndex == index, // 选中时加粗
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

// 无状态组件：语言选择部分
class LanguageSection extends StatelessWidget {
  final List<FocusNode> focusNodes; // 焦点节点列表
  final List<String> languages; // 语言名称列表
  final List<String> languageCodes; // 语言代码列表
  final SelectionState state; // 当前状态
  final LanguageProvider languageProvider; // 语言提供者
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
    final currentLocale = languageProvider.currentLocale.toString(); // 当前语言代码
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).languageSelection, // 语言选择标题
          style: _SettingFontPageState._sectionTitleStyle,
        ),
        const SizedBox(height: 6), // 标题与内容间距
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
                      focusNode: focusNodes[index], // 分配焦点
                      child: buildChoiceChip(
                        focusNode: focusNodes[index],
                        labelText: currentLocale == languageCodes[index]
                            ? S.of(context).inUse // 当前使用中
                            : S.of(context).use, // 使用此语言
                        isSelected: state.selectedIndex == index,
                        onSelected: () async {
                          await languageProvider.changeLanguage(languageCodes[index]);
                          final parentState = context.findAncestorStateOfType<_SettingFontPageState>();
                          if (parentState != null && parentState.mounted) {
                            parentState.setState(() {
                              parentState._langState = SelectionState(index, index); // 同步聚焦和选中
                            });
                            focusNodes[index].requestFocus(); // 确保焦点切换
                          }
                        },
                        isBold: state.selectedIndex == index, // 选中时加粗
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
